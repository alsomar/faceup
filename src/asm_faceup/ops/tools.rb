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

    ### EXTRUDER TOOL ### ---------------------------------------------------------

    class ExtruderTool

      def initialize
        model = Sketchup.active_model
        @selected_faces     = []
        default = default_extrusion_to_length(CONFIG[:default_extrusion], CONFIG[:default_extrusion_unit])
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
        @dotted_axis        = nil
        @inference_source   = nil
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
        @dotted_axis        = nil
        @inference_source   = nil
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
          @cursor_ip.pick(view, x, y)
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
            @dotted_axis        = nil
            @inference_source   = nil
            @cursor_was_snapped = false
            @anchor_ip          = Sketchup::InputPoint.new
            update_status_text
            view.invalidate
            return true
          else
            reset_tool
          end
        when KEYS[:space] # SketchUp intercepts Space and calls deactivate directly
          Sketchup::set_status_text("", SB_PROMPT)
          UI.start_timer(0) { Sketchup.active_model.select_tool(nil) }
          return true
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
        @cursor_ip.pick(view, x, y)

        was_snapped = @cursor_was_snapped
        @cursor_was_snapped = snapped?(@cursor_ip)

        if @cursor_was_snapped
          @inference_source = @cursor_ip.position.clone
          @dotted_axis      = nil
        elsif was_snapped
          @dotted_axis = nil
        elsif !@cursor_ip.valid?
          # Cursor completely lost — inference broken, like SketchUp native behavior.
          @inference_source = nil
          @dotted_axis      = nil
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

      def update_status_text
        dir = @flip_direction ? Lang.t(:tools, :extruder, :status_flipped) : ""
        @status_text = if !@anchor_set
          "#{Lang.t(:tools, :extruder, :status_idle)}#{dir}"
        elsif !@distance_frozen
          "#{Lang.t(:tools, :extruder, :status_pick)}#{dir}"
        else
          "#{Lang.t(:tools, :extruder, :status_adjust)}#{dir}"
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

        groups.each do |group|
          entities = group.entities.to_a
          faces    = entities.grep(Sketchup::Face)

          faces.each                         { |f| f.layer = default_layer }
          entities.grep(Sketchup::Edge).each { |e| e.layer = default_layer }

          faces.first.pushpull(height) if faces.first
        end
      end

      def reset_tool
        @selected_faces     = []
        @preview_cache      = []
        @anchor_set         = false
        @distance_frozen    = false
        @frozen_point       = nil
        @axis_lock          = nil
        @dotted_axis        = nil
        @inference_source   = nil
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
        space:       32,
        tab:          9,
        arrow_left:  37,
        arrow_right: 39,
        arrow_up:    38,
      }.freeze

      CIRCLE_SEGMENTS = 16

      # Minimum pixel separation between cursor_pos and display_pos (the snapped point)
      # before axis color and jump activate. Both must be visible simultaneously.
      MIN_JUMP_PIXELS = 8

      def draw_pick_guide(view)
        return unless @cursor_screen

        jump_visible = false  # hoisted — also used in cursor-dot section below

        # Lines first, points on top
        if @anchor_ip.valid?
          cursor_pos = effective_cursor_position(view)
          if @axis_lock
            s1 = view.screen_coords(@anchor_ip.position)
            s2 = view.screen_coords(cursor_pos)
            view.line_width    = 2
            view.drawing_color = AXIS_COLORS[@axis_lock]
            view.draw2d(GL_LINES,
              Geom::Point3d.new(s1.x, s1.y, 0),
              Geom::Point3d.new(s2.x, s2.y, 0))
            view.line_width = 1
          else
            unless snapped?(@cursor_ip)
              from = @inference_source || @anchor_ip.position
              update_dotted_axis(from, cursor_pos)
            end

            # Project display_pos onto the detected axis (jump).
            display_pos = if @dotted_axis
              base     = @inference_source || @anchor_ip.position
              axis_vec = AXIS_VECTORS[@dotted_axis]
              base.offset(axis_vec, (cursor_pos - base).dot(axis_vec))
            else
              cursor_pos
            end

            # Only apply axis color when the jump is visually significant —
            # i.e. display_pos and cursor_pos differ enough on screen.
            # This prevents premature coloring before the snap is perceptible.
            jump_visible = if @dotted_axis && @cursor_screen
              s_cur  = view.screen_coords(cursor_pos)
              s_disp = view.screen_coords(display_pos)
              dx = s_cur.x - s_disp.x
              dy = s_cur.y - s_disp.y
              Math.sqrt(dx * dx + dy * dy) >= MIN_JUMP_PIXELS
            else
              false
            end

            s1 = view.screen_coords(@anchor_ip.position)
            s2 = view.screen_coords(display_pos)
            view.drawing_color = jump_visible ? axis_color_for_line(@anchor_ip.position, display_pos) : ORANGE
            view.draw2d(GL_LINES,
              Geom::Point3d.new(s1.x, s1.y, 0),
              Geom::Point3d.new(s2.x, s2.y, 0))
          end

          draw_frozen_marker(view, @frozen_point, @anchor_ip.position) if @frozen_point

          if @anchor_set
            draw_inference_circle(view, @anchor_ip.position, ORANGE)
          elsif snapped?(@anchor_ip)
            draw_inference_marker(view, @anchor_ip.position, @anchor_ip)
          end
        end

        # Cursor marker — projected point on the locked axis (or raw screen if no snap)
        if @cursor_ip.valid?
          cursor_pos   = effective_cursor_position(view)
          snap_differs = @axis_lock && @cursor_ip.position != cursor_pos

          # When soft axis snap is active and the jump is visible, show cursor
          # at the projected position. Otherwise stay at cursor_pos.
          display_pos = if jump_visible && !@axis_lock && !snapped?(@cursor_ip)
            base = @inference_source || (@anchor_ip.valid? ? @anchor_ip.position : cursor_pos)
            axis_vec = AXIS_VECTORS[@dotted_axis]
            base.offset(axis_vec, (cursor_pos - base).dot(axis_vec))
          else
            cursor_pos
          end

          # Dotted reference line: visible when the cursor is aligned with a principal
          # axis from the reference point (@dotted_axis active). Not in arbitrary directions.
          if @inference_source && @dotted_axis && !@axis_lock && !snapped?(@cursor_ip)
            view.line_stipple = '.'
            view.drawing_color = AXIS_COLORS[@dotted_axis]
            view.draw(GL_LINES, @inference_source, display_pos)
            view.line_stipple = ''
            draw_inference_circle(view, @inference_source, INFERENCE_COLORS[:none])
          end

          if snap_differs
            draw_inference_circle(view, display_pos, INFERENCE_COLORS[:none])
            view.line_stipple = '.'
            view.drawing_color = INFERENCE_COLORS[:none]
            view.draw(GL_LINES, @cursor_ip.position, display_pos)
            view.line_stipple = ''
            draw_inference_marker(view, @cursor_ip.position, @cursor_ip)
          elsif snapped?(@cursor_ip)
            draw_inference_marker(view, display_pos, @cursor_ip)
          elsif jump_visible
            draw_inference_circle(view, display_pos, INFERENCE_COLORS[:none])
          elsif !@inference_source
            # Free point with no reference — only show dot if axis snap is active
            draw_inference_circle(view, display_pos, INFERENCE_COLORS[:none]) if @dotted_axis
          end
        else
          @dotted_axis = nil
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

      # Returns the axis color if the line from → to aligns within DOTTED_SNAP_DEG
      # of a global axis; otherwise returns ORANGE (or the block result if given).
      def axis_color_for_line(from, to)
        vec = to - from
        if vec.length > 1e-10
          best_axis = nil
          best_deg  = nil
          AXIS_VECTORS.each do |axis, axis_vec|
            deg = (vec.angle_between(axis_vec) * 180.0 / Math::PI)
            deg = 180.0 - deg if deg > 90.0
            if best_deg.nil? || deg < best_deg
              best_axis = axis
              best_deg  = deg
            end
          end
          return AXIS_COLORS[best_axis] if best_deg && best_deg <= DOTTED_SNAP_DEG
        end
        block_given? ? yield : ORANGE
      end

      DOTTED_SNAP_DEG    = 4.0  # degrees from axis to enter snap
      DOTTED_RELEASE_DEG = 7.0  # degrees from axis to exit snap (wider → stable hysteresis)

      def update_dotted_axis(from, to)
        vec = to - from
        return if vec.length < 1e-10

        # Find the axis whose direction is closest to vec (parallel or anti-parallel)
        best_axis = nil
        best_deg  = nil

        AXIS_VECTORS.each do |axis, axis_vec|
          angle_rad = vec.angle_between(axis_vec)
          # Map to [0, 90] — both parallel (0°) and anti-parallel (180°) count
          deg = (angle_rad * 180.0 / Math::PI)
          deg = 180.0 - deg if deg > 90.0

          if best_deg.nil? || deg < best_deg
            best_axis = axis
            best_deg  = deg
          end
        end

        # Hysteresis: measure against the currently snapped axis to release it
        if @dotted_axis
          current_vec = AXIS_VECTORS[@dotted_axis]
          angle_rad   = vec.angle_between(current_vec)
          current_deg = (angle_rad * 180.0 / Math::PI)
          current_deg = 180.0 - current_deg if current_deg > 90.0

          @dotted_axis = nil if current_deg > DOTTED_RELEASE_DEG
        end

        @dotted_axis = best_axis if @dotted_axis.nil? && best_deg <= DOTTED_SNAP_DEG
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
