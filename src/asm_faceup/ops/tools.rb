require 'set'

module ASM_Extensions
  module FaceUp

    ### SUMMON FACES ### ----------------------------------------------------------

    def self.summon_faces
      model     = Sketchup.active_model
      selection = model.selection

      method_id = __method__

      presel_faces = selection.grep(Sketchup::Face)
      presel_edges = selection.grep(Sketchup::Edge)

      if presel_edges.empty?
        UI.messagebox(Lang.t(:tools, :summon_faces, :no_edges))
        return false
      end

      op_name    = "Summon Faces"
      start_time = Time.now if Debug.enabled
      model.start_operation(op_name, true)

      Debug.separator
      Debug.log(self, method_id, "Process START")

      begin
        Debug.log(self, method_id, "Wrapper ENTER")

        new_faces = create_faces(presel_edges)
        orient_faces(new_faces)
        update_selection(selection, presel_faces, presel_edges, new_faces)

        model.commit_operation
        Debug.log(self, method_id, "Wrapper LEAVE")
      rescue => e
        model.abort_operation
        UI.messagebox("Error: #{e.message}")
        Debug.log(self, method_id, "ERROR #{e.class}: #{e.message}")
        Debug.log(self, method_id, e.backtrace.join("\n"))
        return false
      ensure
        model.active_view.refresh
        if Debug.enabled
          elapsed = Time.now - start_time
          Debug.log(self, method_id, "Process DONE! Elapsed #{format('%.3f', elapsed)} sec.")
        end
      end

      true
    end

    def self.create_faces(presel_edges)
      faces = Set.new
      presel_edges.each do |edge|
        next unless edge && edge.valid?
        edge.find_faces
        edge.faces.each { |f| faces.add(f) if f && f.valid? }
      end
      faces.to_a
    end

    def self.orient_faces(new_faces)
      camera = Sketchup.active_model.active_view.camera
      camera_dir = camera.direction
      return if camera_dir.length <= 0.0
      camera_dir.normalize!

      new_faces.each do |face|
        next unless face && face.valid?
        n = face.normal
        next if n.length <= 0.0
        face.reverse! if n.dot(camera_dir) > 0.0
      end
    end

    def self.update_selection(selection, presel_faces, presel_edges, new_faces)
      selection.clear
      final_faces = (presel_faces + new_faces).uniq
      selection.add(final_faces)
      selection.add(presel_edges)
    end

    ### MIN-AREA BOUNDING RECTANGLE (2D) ### --------------------------------------
    # Pure helpers for the Extruder's optional min-volume axis alignment. Kept
    # free of SketchUp model state so they can be unit-tested with plain arrays.

    # Andrew's monotone-chain convex hull. pts: [[x, y], ...]. Returns the hull
    # vertices counter-clockwise, with no repeated endpoint.
    def self.convex_hull_2d(pts)
      pts = pts.uniq.sort_by { |p| [p[0], p[1]] }
      return pts if pts.length < 3

      cross = lambda do |o, a, b|
        (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
      end

      lower = []
      pts.each do |p|
        lower.pop while lower.length >= 2 && cross.call(lower[-2], lower[-1], p) <= 0
        lower << p
      end

      upper = []
      pts.reverse_each do |p|
        upper.pop while upper.length >= 2 && cross.call(upper[-2], upper[-1], p) <= 0
        upper << p
      end

      lower[0...-1] + upper[0...-1]
    end

    # Rotation angle (radians) of the minimum-area bounding rectangle of a 2D
    # point set. By O'Rourke the optimum has a side flush with a hull edge, so
    # only hull-edge directions are evaluated. Rotating points by -angle then
    # axis-aligns that rectangle.
    def self.min_area_rect_angle(pts2d)
      hull = convex_hull_2d(pts2d)
      return 0.0 if hull.length < 2

      best_angle = 0.0
      best_area  = nil
      n = hull.length

      n.times do |i|
        a = hull[i]
        b = hull[(i + 1) % n]
        theta = Math.atan2(b[1] - a[1], b[0] - a[0])
        cos_t = Math.cos(theta)
        sin_t = Math.sin(theta)

        min_u = max_u = min_v = max_v = nil
        hull.each do |p|
          u =  p[0] * cos_t + p[1] * sin_t
          v = -p[0] * sin_t + p[1] * cos_t
          min_u = u if min_u.nil? || u < min_u
          max_u = u if max_u.nil? || u > max_u
          min_v = v if min_v.nil? || v < min_v
          max_v = v if max_v.nil? || v > max_v
        end

        area = (max_u - min_u) * (max_v - min_v)
        if best_area.nil? || area < best_area
          best_area  = area
          best_angle = theta
        end
      end

      best_angle
    end

    ### MODEL UNITS ### -----------------------------------------------------------

    LENGTH_UNIT_INFO = {
      0 => { key: 'inch', abbr: 'in' },
      1 => { key: 'feet', abbr: 'ft' },
      2 => { key: 'mm',   abbr: 'mm' },
      3 => { key: 'cm',   abbr: 'cm' },
      4 => { key: 'm',    abbr: 'm'  },
      5 => { key: 'yard', abbr: 'yd' },
    }.freeze

    # The active model's length unit as { key:, abbr: }. `key` feeds
    # default_extrusion_to_length (via UNIT_SUFFIXES); `abbr` is shown in the UI.
    def self.model_length_unit(model)
      LENGTH_UNIT_INFO[model.options['UnitsOptions']['LengthUnit']] ||
        { key: 'model', abbr: '' }
    end

    ### EXTRUDER TOOL ### ---------------------------------------------------------

    class ExtruderTool

      def initialize
        model = Sketchup.active_model
        @selected_faces     = []
        unit_key = ASM_Extensions::FaceUp.model_length_unit(model)[:key]
        default = default_extrusion_to_length(CONFIG[:default_extrusion], unit_key)
        @extrusion_distance = if CONFIG[:use_last_extrusion]
          stored = model.get_attribute('ASM_Extensions_FaceUp', 'last_extrusion_distance', nil)
          stored ? stored : default
        else
          default
        end
        @status_text        = ""
        @anchor_set         = false
        @distance_frozen    = false
        @frozen_point       = nil
        @axis_lock          = nil
        @flip_direction     = false
        @operation_open     = false
        @anchor_ip          = Sketchup::InputPoint.new
        @cursor_ip          = Sketchup::InputPoint.new
        @cursor_screen      = nil
        @current_view       = nil
        @preview_cache      = []
        @inference_source   = nil
        @source_axis_snap   = nil
        @cursor_was_snapped = false
      end

      def activate
        model     = Sketchup.active_model
        selection = model.selection
        @selected_faces = selection.grep(Sketchup::Face)

        if @selected_faces.empty?
          UI.messagebox(Lang.t(:tools, :extruder, :no_faces))
          UI.start_timer(0) { Sketchup.active_model.select_tool(nil) }
          return
        end

        Debug.separator
        Debug.log(self.class, __method__, "Tool activated — #{@selected_faces.size} face(s) selected")

        @preview_cache = @selected_faces.map do |face|
          mesh = face.mesh(7)
          {
            normal:     face.normal,
            tris:       mesh.polygons.map { |tri| tri.map { |i| mesh.point_at(i.abs) } },
            loop_pts:   face.outer_loop.vertices.map(&:position),
            hard_edges: face.outer_loop.edges.reject { |e| e.soft? || e.curve }.map { |e| [e.start.position, e.end.position] },
          }
        end

        update_vcb
        update_status_text
        model.active_view.invalidate
      end

      def deactivate(view)
        if @operation_open
          Sketchup.active_model.abort_operation
          @operation_open = false
        end
        extruder(view) if @distance_frozen && !@selected_faces.empty?
        @anchor_set         = false
        @distance_frozen    = false
        @frozen_point       = nil
        @axis_lock          = nil
        @inference_source   = nil
        @source_axis_snap   = nil
        @cursor_was_snapped = false
        view.invalidate
      end

      def enableVCB?
        true
      end

      def getExtents
        bb = Sketchup.active_model.bounds
        return bb if @preview_cache.empty? || @extrusion_distance.zero?

        @preview_cache.each do |data|
          n    = data[:normal]
          dist = @extrusion_distance
          data[:loop_pts].each do |p|
            bb.add(p)
            bb.add(p.offset(n, dist))
          end
        end

        bb
      end

      def suspend(view)
        view.invalidate
      end

      def resume(view)
        update_vcb(@current_vcb_label, @current_vcb_value)
        Sketchup::set_status_text(@status_text, SB_PROMPT)
        view.invalidate
      end

      def draw(view)
        if @extrusion_distance.zero?
          draw_face_highlight(view)
        else
          draw_extrusion_preview(view)
        end
        draw_pick_guide(view)
      end

      def onLButtonDown(flags, x, y, view)
        unless @anchor_set
          @anchor_ip.pick(view, x, y)
          @cursor_ip.pick(view, x, y)
          @anchor_set = true
          Debug.log(self.class, __method__, "Anchor set at #{@anchor_ip.position}")
        else
          pick_cursor(view, x, y)
          @extrusion_distance = compute_pick_distance(@cursor_ip)
          @distance_frozen    = true
          @frozen_point       = effective_cursor_position(view)
          update_vcb(nil, @extrusion_distance.to_s)
          view.invalidate
          Debug.log(self.class, __method__, "Distance set: #{@extrusion_distance} — cursor=#{@cursor_ip.position}")
        end
        update_status_text
      end

      def onKeyDown(key, repeat, flags, view)
        case key
        when KEYS[:esc] # reset anchor, or exit tool if no anchor
          if @anchor_set || @distance_frozen
            @anchor_set         = false
            @distance_frozen    = false
            @frozen_point       = nil
            @axis_lock          = nil
            @inference_source   = nil
            @source_axis_snap   = nil
            @cursor_was_snapped = false
            @anchor_ip          = Sketchup::InputPoint.new
            update_status_text
            view.invalidate
            return true
          else
            reset_tool
          end
        when KEYS[:tab] # flip extrusion direction
          @flip_direction    = !@flip_direction
          @extrusion_distance = -@extrusion_distance
          update_vcb(nil, @extrusion_distance.to_s)
          update_status_text
          view.invalidate
          return true
        when KEYS[:arrow_left]  # X axis (red)
          toggle_axis_lock(:x, view)
        when KEYS[:arrow_right] # Y axis (green)
          toggle_axis_lock(:y, view)
        when KEYS[:arrow_up]    # Z axis (blue)
          toggle_axis_lock(:z, view)
        end
      end

      def onMouseMove(flags, x, y, view)
        @cursor_screen = Geom::Point3d.new(x, y, 0)
        @current_view  = view
        pick_cursor(view, x, y)

        was_snapped = @cursor_was_snapped
        @cursor_was_snapped = snapped?(@cursor_ip)

        if @cursor_was_snapped
          @inference_source = @cursor_ip.position.clone
        elsif !was_snapped && !@cursor_ip.valid?
          # Cursor completely lost — inference broken, like SketchUp native behavior.
          @inference_source = nil
        end

        if @anchor_set && !@distance_frozen
          @extrusion_distance = compute_pick_distance(@cursor_ip)
          update_vcb(nil, @extrusion_distance.to_s)
        end
        view.invalidate
      end

      def onReturn(view)
        extruder(view)
        reset_tool
      end

      def onLButtonDoubleClick(flags, x, y, view)
        extruder(view)
        reset_tool
      end

      def onUserText(text, view)
        begin
          raw = text.to_l.abs
          @extrusion_distance = (@flip_direction ? -raw : raw).to_l
          @distance_frozen    = true
          update_vcb(nil, @extrusion_distance.to_s)
          update_status_text
          view.invalidate
        rescue ArgumentError
          Sketchup::set_status_text(Lang.t(:tools, :extruder, :invalid_length), SB_PROMPT)
        end
      end

      private

      # Picks the cursor input point. Once the anchor is set, the anchor is
      # passed as the inference reference so SketchUp offers native from-point
      # axis inferences (with magnetism) instead of context-free ones.
      def pick_cursor(view, x, y)
        if @anchor_set
          @cursor_ip.pick(view, x, y, @anchor_ip)
        else
          @cursor_ip.pick(view, x, y)
        end
        update_source_axis_snap(view, x, y)
      end

      # Decide whether the correspondence to @inference_source should be active
      # this frame, and if so where the cursor effectively sits.
      #
      # The line shows whenever the cursor is *already* aligned with V along a
      # principal axis (within EXACT_AXIS_DEG) — no pulling needed in that
      # case, since the orange line keeps whichever direction it had. This is
      # the parallel-coincident scenario and the on-axis-vertex scenario.
      #
      # Otherwise we try a soft pull:
      # - Post-anchor: only to a double-inference intersection (an anchor-axis
      #   line crossed with a source-axis line). Keeps the orange line on its
      #   own principal axis while the correspondence to V is on its own.
      # - Pre-anchor: free projection onto the closest source axis. Useful for
      #   landing the anchor on a line from V.
      def update_source_axis_snap(view, x, y)
        prior = @source_axis_snap
        @source_axis_snap = nil
        return unless @inference_source

        current_pos = cursor_position_pre_source_snap(view)
        if (axis = exact_v_axis_from(current_pos))
          @source_axis_snap = { axis: axis, position: current_pos, d2: 0 }
          return
        end

        return if snapped?(@cursor_ip)

        fresh =
          if @anchor_set && @anchor_ip.valid?
            best_anchor_source_intersection(view, x, y)
          else
            best_source_axis_projection(view, x, y)
          end

        if fresh
          @source_axis_snap = fresh
          return
        end

        # Hysteresis: keep the prior snap alive while within the larger
        # release radius. Lets the saltito stick once the user has latched on.
        return unless prior
        d2 = squared_screen_distance(view, prior[:position], x, y)
        @source_axis_snap = prior.merge(d2: d2) if d2 <= SOURCE_HOLD_PX * SOURCE_HOLD_PX
      end

      # Whether (point - @inference_source) is along a principal axis within
      # EXACT_AXIS_DEG. Returns the axis (:x/:y/:z) or nil.
      def exact_v_axis_from(point)
        vec = point - @inference_source
        return nil if vec.length < 1e-6
        vec = vec.normalize
        AXIS_VECTORS.each do |axis, axis_vec|
          cos_a = vec.dot(axis_vec).abs
          cos_a = 1.0 if cos_a > 1.0
          deg = Math.acos(cos_a) * 180.0 / Math::PI
          return axis if deg <= EXACT_AXIS_DEG
        end
        nil
      end

      def best_anchor_source_intersection(view, x, y)
        anchor      = @anchor_ip.position
        anchor_axes = @axis_lock ? [@axis_lock] : AXIS_VECTORS.keys
        best        = nil

        anchor_axes.each do |anchor_axis|
          lock_vec = AXIS_VECTORS[anchor_axis]
          AXIS_VECTORS.each_key do |source_axis|
            next if source_axis == anchor_axis
            third = (AXIS_VECTORS.keys - [anchor_axis, source_axis]).first
            next if (component_of(anchor, third) - component_of(@inference_source, third)).abs > 1e-3

            t   = (@inference_source - anchor).dot(lock_vec)
            pos = anchor.offset(lock_vec, t)
            d2  = squared_screen_distance(view, pos, x, y)
            if d2 <= SOURCE_SNAP_PX * SOURCE_SNAP_PX && (best.nil? || d2 < best[:d2])
              best = { axis: source_axis, position: pos, d2: d2 }
            end
          end
        end
        best
      end

      def best_source_axis_projection(view, x, y)
        ray  = view.pickray(x, y)
        best = nil
        AXIS_VECTORS.each do |axis, axis_vec|
          t   = closest_point_on_axis(@inference_source, axis_vec, ray[0], ray[1])
          pos = @inference_source.offset(axis_vec, t)
          d2  = squared_screen_distance(view, pos, x, y)
          if d2 <= SOURCE_SNAP_PX * SOURCE_SNAP_PX && (best.nil? || d2 < best[:d2])
            best = { axis: axis, position: pos, d2: d2 }
          end
        end
        best
      end

      def squared_screen_distance(view, point_3d, x, y)
        s = view.screen_coords(point_3d)
        dx = s.x - x
        dy = s.y - y
        dx * dx + dy * dy
      end

      def component_of(point, axis)
        case axis
        when :x then point.x
        when :y then point.y
        when :z then point.z
        end
      end

      def update_status_text
        dir = @flip_direction ? Lang.t(:tools, :extruder, :status_flipped) : ""
        @status_text = if @distance_frozen
          "#{Lang.t(:tools, :extruder, :status_adjust)}#{dir}"
        elsif !@anchor_set
          "#{Lang.t(:tools, :extruder, :status_idle)}#{dir}"
        else
          "#{Lang.t(:tools, :extruder, :status_pick)}#{dir}"
        end
        Sketchup::set_status_text(@status_text)
      end

      def extruder(view)
        return if @selected_faces.empty?

        faces_to_extrude = @selected_faces
        @selected_faces  = []  # stop preview immediately

        model     = Sketchup.active_model
        method_id = __method__

        start_time = Time.now if Debug.enabled
        Debug.separator
        Debug.log(self.class, method_id, "Process START — distance=#{@extrusion_distance}")

        model.start_operation("Extruder", true)
        @operation_open = true

        begin
          groups = face2group(faces_to_extrude)
          xtrd_groups(groups, @extrusion_distance)
          model.selection.add(groups)
          model.set_attribute('ASM_Extensions_FaceUp', 'last_extrusion_distance', @extrusion_distance)
          model.commit_operation
          @operation_open = false
          Debug.log(self.class, method_id, "Committed")
        rescue => e
          model.abort_operation
          @operation_open = false
          UI.messagebox("Error: #{e.message}")
          Debug.log(self.class, method_id, "ERROR #{e.class}: #{e.message}")
          Debug.log(self.class, method_id, e.backtrace.join("\n"))
        ensure
          model.active_view.refresh
          if Debug.enabled
            elapsed = Time.now - start_time
            Debug.log(self.class, method_id, "Process DONE! Elapsed #{format('%.3f', elapsed)} sec.")
          end
        end

        view.invalidate
      end

      def draw_face_highlight(view)
        return if @preview_cache.empty?

        tris = @preview_cache.flat_map { |data| data[:tris].flatten }

        view.drawing_color = Sketchup::Color.new('white')
        view.draw(GL_TRIANGLES, tris)

        view.drawing_color = PREVIEW_BLUE
        @preview_cache.each { |data| view.draw(GL_LINE_LOOP, data[:loop_pts]) }
      end

      def draw_extrusion_preview(view)
        return if @preview_cache.empty?

        gray_tris  = []
        gray_quads = []
        white_tris = []
        hard_lines = []

        @preview_cache.each do |data|
          n    = data[:normal]
          dist = @extrusion_distance

          data[:tris].each do |pts|
            top = pts.map { |p| p.offset(n, dist) }

            gray_tris.concat(pts)
            pts.each_index do |j|
              k = (j + 1) % pts.length
              gray_quads.concat([pts[j], pts[k], top[k], top[j]])
            end
            white_tris.concat(top)
          end

          # Top and vertical edges — hard edges only
          data[:hard_edges].each do |s, e|
            st = s.offset(n, dist)
            et = e.offset(n, dist)
            hard_lines.concat([st, et, s, st, e, et])
          end

        end

        view.drawing_color = Sketchup::Color.new(220, 220, 220)
        view.draw(GL_TRIANGLES, gray_tris)
        view.draw(GL_QUADS, gray_quads)

        view.drawing_color = Sketchup::Color.new('white')
        view.draw(GL_TRIANGLES, white_tris)

        view.drawing_color = PREVIEW_BLUE

        # Top face outline — always drawn as a full loop
        @preview_cache.each { |data| view.draw(GL_LINE_LOOP, data[:loop_pts].map { |p| p.offset(data[:normal], @extrusion_distance) }) }

        # Top and vertical hard edges
        view.draw(GL_LINES, hard_lines) unless hard_lines.empty?
      end

      def face2group(faces)
        faces_with_inner_edges    = []
        faces_without_inner_edges = []

        faces.each do |face|
          outer_set = face.outer_loop.edges.to_set
          if face.edges.any? { |edge| !outer_set.include?(edge) }
            faces_with_inner_edges << face
          else
            faces_without_inner_edges << face
          end
        end

        ents = Sketchup.active_model.active_entities

        # rubocop:disable SketchupSuggestions/AddGroup
        # Process largest faces first: grouping a small face collapses its hole,
        # which would inflate the area of a larger overlapping face processed later.
        groups_with_inner_edges = faces_with_inner_edges.sort_by { |face| -face.area }.map do |face|
          ents.add_group([face, *face.edges])
        end

        groups_without_inner_edges = faces_without_inner_edges.map do |face|
          ents.add_group(face)
        end
        # rubocop:enable SketchupSuggestions/AddGroup

        groups_with_inner_edges + groups_without_inner_edges
      end

      def xtrd_groups(groups, height)
        default_layer = Sketchup.active_model.layers[0]
        align         = CONFIG[:align_to_min_bb]

        groups.each do |group|
          entities = group.entities.to_a
          faces    = entities.grep(Sketchup::Face)

          faces.each                         { |f| f.layer = default_layer }
          entities.grep(Sketchup::Edge).each { |e| e.layer = default_layer }

          next unless faces.first

          # The profile normal (before pushpull) is the extrusion axis.
          normal = faces.first.normal
          faces.first.pushpull(height)
          apply_min_bb_alignment(group, normal) if align
        end
      end

      # Redefines the group's local axes so its bounding box is the minimum-volume
      # OBB with the extrusion axis on local Z. World geometry is unchanged: the
      # definition is rotated by R and the group transform set to T0 * R⁻¹.
      def apply_min_bb_alignment(group, normal)
        n = normal
        return if n.length < 1e-9
        n = n.normalize

        e1, e2, _ = n.axes  # arbitrary orthonormal basis spanning the plane ⊥ n
        defn = group.definition

        pts2d = []
        defn.entities.grep(Sketchup::Edge).each do |edge|
          [edge.start.position, edge.end.position].each do |p|
            pts2d << [p.x * e1.x + p.y * e1.y + p.z * e1.z,
                      p.x * e2.x + p.y * e2.y + p.z * e2.z]
          end
        end
        return if pts2d.length < 2

        theta  = ASM_Extensions::FaceUp.min_area_rect_angle(pts2d)
        u      = Geom::Vector3d.linear_combination(Math.cos(theta), e1, Math.sin(theta), e2)
        v      = n.cross(u)            # n × u → right-handed (no mirror)
        origin = Geom::Point3d.new(0, 0, 0)
        frame  = Geom::Transformation.axes(origin, u, v, n)

        # Skip the geometry op when the box is already optimally oriented.
        m     = frame.to_a
        trace = m[0] + m[5] + m[10]
        angle = Math.acos([[(trace - 1.0) / 2.0, -1.0].max, 1.0].min)
        return if angle < 1e-4

        t0 = group.transformation
        defn.entities.transform_entities(frame.inverse, defn.entities.to_a)
        group.transformation = t0 * frame
      end

      def reset_tool
        @selected_faces     = []
        @preview_cache      = []
        @anchor_set         = false
        @distance_frozen    = false
        @frozen_point       = nil
        @axis_lock          = nil
        @inference_source   = nil
        @source_axis_snap   = nil
        @cursor_was_snapped = false
        @flip_direction     = false
        @operation_open     = false
        Sketchup::set_status_text("", SB_PROMPT)
        UI.start_timer(0) { Sketchup.active_model.select_tool(nil) }
      end

      def update_vcb(label = nil, value = nil)
        label ||= Lang.t(:tools, :extruder, :vcb_label)
        value ||= @extrusion_distance.to_s

        @current_vcb_label = label
        @current_vcb_value = value

        Sketchup::set_status_text(label, SB_VCB_LABEL)
        Sketchup::set_status_text(value, SB_VCB_VALUE)
      end

      INFERENCE_COLORS = {
        vertex:   Sketchup::Color.new(0,   255, 0).freeze,   # green
        midpoint: Sketchup::Color.new(0,   191, 255).freeze, # light blue
        edge:     Sketchup::Color.new(255, 0,   0).freeze,   # red
        face:     Sketchup::Color.new(0,   50,  210).freeze, # electric blue
        none:     Sketchup::Color.new(0,   0,   0).freeze,   # black — free point
      }.freeze

      ORANGE        = Sketchup::Color.new(255, 140, 0).freeze
      PREVIEW_BLUE  = Sketchup::Color.new(0,   0,   200).freeze

      AXIS_VECTORS = {
        x: Geom::Vector3d.new(1, 0, 0),
        y: Geom::Vector3d.new(0, 1, 0),
        z: Geom::Vector3d.new(0, 0, 1),
      }.freeze

      AXIS_COLORS = {
        x: Sketchup::Color.new(255, 0,   0).freeze,
        y: Sketchup::Color.new(0,   128, 0).freeze,
        z: Sketchup::Color.new(0,   0,   255).freeze,
      }.freeze

      KEYS = {
        esc:         27,
        tab:          9,
        arrow_left:  37,
        arrow_right: 39,
        arrow_up:    38,
      }.freeze

      CIRCLE_SEGMENTS = 16

      def draw_pick_guide(view)
        return unless @cursor_screen

        # Lines first, points on top
        if @anchor_ip.valid?
          cursor_pos = effective_cursor_position(view)
          s1 = view.screen_coords(@anchor_ip.position)
          s2 = view.screen_coords(cursor_pos)

          if @axis_lock
            view.line_width    = 2
            view.drawing_color = AXIS_COLORS[@axis_lock]
          else
            view.line_width    = 1
            view.drawing_color = ORANGE
          end
          view.draw2d(GL_LINES,
            Geom::Point3d.new(s1.x, s1.y, 0),
            Geom::Point3d.new(s2.x, s2.y, 0))
          view.line_width = 1

          draw_frozen_marker(view, @frozen_point, @anchor_ip.position) if @frozen_point

          if @anchor_set
            draw_inference_circle(view, @anchor_ip.position, ORANGE)
          elsif snapped?(@anchor_ip)
            draw_inference_marker(view, @anchor_ip.position, @anchor_ip)
          end
        end

        # Cursor marker — projected point on the locked axis / source snap
        # (or raw screen if no snap).
        if @cursor_ip.valid?
          cursor_pos         = effective_cursor_position(view)
          position_overridden = (@axis_lock || @source_axis_snap) && @cursor_ip.position != cursor_pos

          # Correspondence line: a dotted line from the last snapped reference
          # point to the cursor. Shown only when the cursor is genuinely on a
          # source axis — either pulled there by the soft snap, or because it
          # snapped to geometry that happens to lie on the axis. Without the
          # snap gate, the 3° tolerance corridor of axis_for_line let an
          # oblique line appear before the soft snap engaged.
          if @inference_source && !@axis_lock && (
               @source_axis_snap ||
               (snapped?(@cursor_ip) && axis_for_line(view, @inference_source, cursor_pos))
             )
            view.line_stipple = '.'
            view.drawing_color = INFERENCE_COLORS[:none]
            view.draw(GL_LINES, @inference_source, cursor_pos)
            view.line_stipple = ''
            draw_inference_circle(view, @inference_source, INFERENCE_COLORS[:none])
          end

          if position_overridden
            draw_inference_circle(view, cursor_pos, INFERENCE_COLORS[:none])
            view.line_stipple = '.'
            view.drawing_color = INFERENCE_COLORS[:none]
            view.draw(GL_LINES, @cursor_ip.position, cursor_pos)
            view.line_stipple = ''
            draw_inference_marker(view, @cursor_ip.position, @cursor_ip) if snapped?(@cursor_ip)
          elsif snapped?(@cursor_ip)
            draw_inference_marker(view, cursor_pos, @cursor_ip)
          end
        else
          view.drawing_color = INFERENCE_COLORS[:none]
          view.draw2d(GL_POLYGON, circle_pts(@cursor_screen.x, @cursor_screen.y))
        end
      end

      def draw_frozen_marker(view, point_3d, anchor_3d)
        s = view.screen_coords(point_3d)
        a = view.screen_coords(anchor_3d)

        view.line_width    = 2
        view.drawing_color = ORANGE
        view.draw2d(GL_LINES,
          Geom::Point3d.new(a.x, a.y, 0),
          Geom::Point3d.new(s.x, s.y, 0))
        view.line_width = 1

        draw_inference_circle(view, point_3d, ORANGE)
      end

      def circle_pts(cx, cy, radius = 5)
        Array.new(CIRCLE_SEGMENTS) do |i|
          angle = 2.0 * Math::PI * i / CIRCLE_SEGMENTS
          Geom::Point3d.new(cx + radius * Math.cos(angle), cy + radius * Math.sin(angle), 0)
        end
      end

      def diamond_pts(cx, cy, radius = 5)
        [
          Geom::Point3d.new(cx,          cy - radius, 0),
          Geom::Point3d.new(cx + radius, cy,          0),
          Geom::Point3d.new(cx,          cy + radius, 0),
          Geom::Point3d.new(cx - radius, cy,          0),
        ]
      end

      def draw_inference_circle(view, point_3d, color)
        screen = view.screen_coords(point_3d)
        view.drawing_color = color
        view.draw2d(GL_POLYGON, circle_pts(screen.x, screen.y))
      end

      def draw_inference_marker(view, point_3d, ip)
        screen = view.screen_coords(point_3d)
        if ip.face && !ip.vertex && !ip.edge
          view.drawing_color = INFERENCE_COLORS[:face]
          view.draw2d(GL_POLYGON, diamond_pts(screen.x, screen.y))
        else
          view.drawing_color = inference_color(ip)
          view.draw2d(GL_POLYGON, circle_pts(screen.x, screen.y))
        end
      end

      def inference_color(ip)
        if ip.vertex
          INFERENCE_COLORS[:vertex]
        elsif ip.edge
          s, e = ip.edge.start.position, ip.edge.end.position
          mid  = Geom::Point3d.new((s.x + e.x) / 2.0, (s.y + e.y) / 2.0, (s.z + e.z) / 2.0)
          ip.position == mid ? INFERENCE_COLORS[:midpoint] : INFERENCE_COLORS[:edge]
        elsif ip.face
          INFERENCE_COLORS[:face]
        else
          INFERENCE_COLORS[:none]
        end
      end

      def snapped?(ip)
        ip.vertex || ip.edge || ip.face
      end

      AXIS_PARALLEL_DEG = 3.0  # max 3D angular deviation to read a segment as axis-parallel
      EXACT_AXIS_DEG    = 0.5  # tight tolerance for "cursor sits on a V axis already"
      MIN_LINE_PIXELS   = 24   # screen dead zone around the reference point before the line shows
      SOURCE_SNAP_PX    = 18   # magnetic radius to engage soft snap to a V axis
      SOURCE_HOLD_PX    = 32   # hysteresis: keep an engaged snap until cursor escapes this radius

      # Whether the from→to 3D segment is parallel to a principal axis within
      # AXIS_PARALLEL_DEG. Returns the matched axis (:x/:y/:z) or nil. Pure —
      # writes no state. The camera is consulted only for the screen deadzone
      # so a tiny on-screen line near the reference doesn't flicker.
      def axis_for_line(view, from, to)
        s_from = view.screen_coords(from)
        s_to   = view.screen_coords(to)
        ldx = s_to.x - s_from.x
        ldy = s_to.y - s_from.y
        return nil if (ldx * ldx + ldy * ldy) < MIN_LINE_PIXELS * MIN_LINE_PIXELS

        vec = to - from
        return nil if vec.length < 1e-6
        vec = vec.normalize

        best_axis = nil
        best_deg  = nil
        AXIS_VECTORS.each do |axis, axis_vec|
          cos_a = vec.dot(axis_vec).abs
          cos_a = 1.0 if cos_a > 1.0
          deg = Math.acos(cos_a) * 180.0 / Math::PI
          if best_deg.nil? || deg < best_deg
            best_axis = axis
            best_deg  = deg
          end
        end
        (best_deg && best_deg <= AXIS_PARALLEL_DEG) ? best_axis : nil
      end

      def toggle_axis_lock(axis, view)
        return unless @anchor_set
        @axis_lock = (@axis_lock == axis) ? nil : axis
        if !@distance_frozen && @cursor_ip.valid?
          @extrusion_distance = compute_pick_distance(@cursor_ip)
          update_vcb(nil, @extrusion_distance.to_s)
        end
        update_status_text
        view.invalidate
      end

      def effective_cursor_position(view = nil)
        return @source_axis_snap[:position] if @source_axis_snap
        cursor_position_pre_source_snap(view)
      end

      # Cursor position honoring only @axis_lock (and native pick). Used both
      # by effective_cursor_position as the no-snap fallback, and by
      # update_source_axis_snap to evaluate the cursor's standing alignment
      # without recursing back through the source snap.
      def cursor_position_pre_source_snap(view = nil)
        return @cursor_ip.position unless @axis_lock && @anchor_ip.valid?

        anchor   = @anchor_ip.position
        axis_vec = AXIS_VECTORS[@axis_lock]

        # If the cursor has snapped to a real point (vertex, midpoint, edge, face),
        # project that point's snapped coordinate onto the locked axis directly.
        # This lets the user reference geometry from other objects — only the
        # axis-aligned component of the snapped position is used.
        if @cursor_ip.valid?
          return anchor.offset(axis_vec, (@cursor_ip.position - anchor).dot(axis_vec))
        end

        # No snap — fall back to projecting the camera ray onto the axis.
        if view && @cursor_screen
          ray = view.pickray(@cursor_screen.x.to_i, @cursor_screen.y.to_i)
          t   = closest_point_on_axis(anchor, axis_vec, ray[0], ray[1])
          return anchor.offset(axis_vec, t)
        end

        @cursor_ip.position
      end

      def closest_point_on_axis(anchor, axis_vec, ray_origin, ray_dir)
        w     = anchor - ray_origin
        b     = axis_vec.dot(ray_dir)
        c     = ray_dir.dot(ray_dir)
        d     = axis_vec.dot(w)
        e     = ray_dir.dot(w)
        denom = c - b * b  # a=1 since axis_vec is a unit vector
        return 0.0 if denom.abs < 1e-10
        (b * e - c * d) / denom
      end

      UNIT_SUFFIXES = {
        'mm'   => 'mm',
        'cm'   => 'cm',
        'm'    => 'm',
        'inch' => '"',
        'feet' => "'",
        'yard' => 'yd',
        'model' => nil,
      }.freeze

      def default_extrusion_to_length(value, unit)
        suffix = UNIT_SUFFIXES[unit.to_s]
        suffix ? "#{value}#{suffix}".to_l : value.to_l
      rescue
        0.to_l
      end

      def compute_pick_distance(target_ip)
        return @extrusion_distance unless @anchor_ip.valid? && target_ip.valid?
        endpoint = effective_cursor_position(@current_view)
        vec      = endpoint - @anchor_ip.position
        (@flip_direction ? -vec.length : vec.length).to_l
      end

    end # class ExtruderTool

    ### TURBO TOOL ### ------------------------------------------------------------

    class TurboTool

      def self.turbo
        return unless ASM_Extensions::FaceUp.summon_faces
        Sketchup.active_model.select_tool(ExtruderTool.new)
      end

    end # class TurboTool

  end # module FaceUp
end # module ASM_Extensions
