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
    # Pure helpers for FaceUp's optional min-volume axis alignment. Kept
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

    ### FACEUP TOOL ### -----------------------------------------------------------

    class FaceUpTool

      MODES = %i[face surface].freeze

      def initialize(mode: :face)
        raise ArgumentError, "Unknown mode: #{mode.inspect}" unless MODES.include?(mode)
        @mode = mode
        model = Sketchup.active_model
        @selected_faces      = []
        unit_key = ASM_Extensions::FaceUp.model_length_unit(model)[:key]
        default = default_extrusion_to_length(CONFIG[:default_extrusion], unit_key)
        @extrusion_distance  = if CONFIG[:use_last_extrusion]
          stored = model.get_attribute('ASM_Extensions_FaceUp', 'last_extrusion_distance', nil)
          stored ? stored : default
        else
          default
        end
        @status_text         = ""
        @anchor_set          = false
        @distance_frozen     = false
        @frozen_point        = nil
        @pending_commit_distance = nil
        @axis_lock           = nil
        @normal_lock         = false   # experimental: lock extrusion to a face normal
        @normal_origin       = nil     # the clicked point on the original face (origin)
        @normal_dir          = nil     # that face's world normal (the locked axis)
        @hover_point         = nil     # current snap point on an original face (orange dot)
        @hover_normal        = nil
        # Seed the flip flag from the (possibly remembered, possibly negative)
        # default distance so it stays in sync with the actual direction.
        # Otherwise typing a length or dragging after Tab derives the sign
        # from @flip_direction and contradicts the direction shown.
        @flip_direction      = @extrusion_distance.to_f < 0
        @both_sides          = false
        @both_pending_flip   = false
        @operation_open      = false
        @anchor_ip           = Sketchup::InputPoint.new
        @cursor_ip           = Sketchup::InputPoint.new
        @v_ip                = nil
        @inference_lock_held = false
        @cursor_screen       = nil
        @current_view        = nil
        @preview_cache       = []
        @coordinated_extrusion = (mode == :surface)
        @coord_unit_disp_by_pos = nil
        @coord_dominant_by_pos  = nil
        @coord_miter_disp       = nil
        @coord_miter_disp_inv   = nil
        @coord_shared_edge_pos  = nil
        @ctrl_was_held          = false
        # Set in `activate` when re-extruding inside a SurfaceUp group. It
        # strips *external* context from the coordination (adjacent unselected
        # faces and already-extruded neighbour groups) while leaving
        # coordination *among the selected geometry* intact.
        @ignore_external_context = false
      end

      def activate
        model     = Sketchup.active_model
        selection = model.selection
        @selected_faces = selection.grep(Sketchup::Face)

        if @selected_faces.empty?
          UI.messagebox(Lang.t(:tools, :faceup, :no_faces))
          UI.start_timer(0) { Sketchup.active_model.select_tool(nil) }
          return
        end

        Debug.separator
        Debug.log(self.class, __method__, "Tool activated — #{@selected_faces.size} face(s) selected")

        # Second-extrusion rule: when the active edit context is a group that
        # SurfaceUp itself created, re-extruding its interior must ignore all
        # *external* context — neither adjacent unselected faces nor already-
        # extruded neighbour groups should tilt the result, so the shell can't
        # drift by re-reading its own or neighbours' stored normals.
        # Coordination *among the selected geometry* still applies (shared
        # vertices across the selection stay welded). A fresh face extruded
        # from *outside* such a group sits in a different edit context, so it
        # still consults it normally.
        if @mode == :surface && extruding_surface_group_interior?
          @ignore_external_context = true
          Debug.log(self.class, __method__, "Inside SurfaceUp group — external context ignored (local coordination kept)")
        end

        @preview_cache = build_preview_cache

        update_vcb
        update_status_text
        start_ctrl_poll_timer
        model.active_view.invalidate
      end

      def deactivate(view)
        if @operation_open
          Sketchup.active_model.abort_operation
          @operation_open = false
        end
        execute(view) if @distance_frozen && !@selected_faces.empty?
        view.lock_inference if @inference_lock_held
        @inference_lock_held = false
        @anchor_set          = false
        @distance_frozen     = false
        @frozen_point        = nil
        @pending_commit_distance = nil
        @axis_lock           = nil
        @normal_lock         = false   # experimental: lock extrusion to a face normal
        @normal_origin       = nil     # the clicked point on the original face (origin)
        @normal_dir          = nil     # that face's world normal (the locked axis)
        @hover_point         = nil     # current snap point on an original face (orange dot)
        @hover_normal        = nil
        @v_ip                = nil
        stop_ctrl_poll_timer
        view.invalidate
      end

      # SketchUp eats Ctrl in `onKeyDown` on Windows and only delivers the
      # COPY_MODIFIER_MASK bit through mouse-event flags, so a press without
      # a follow-up cursor move would otherwise go unnoticed. We poll
      # GetAsyncKeyState directly on Windows; on macOS we fall back to the
      # mouse-flag path inside `onMouseMove`.
      def start_ctrl_poll_timer
        return unless Sketchup.platform == :platform_win
        stop_ctrl_poll_timer
        begin
          require 'fiddle'
          require 'fiddle/import'
        rescue LoadError
          return
        end
        @ctrl_async_key_state ||= Fiddle::Function.new(
          Fiddle.dlopen('user32.dll')['GetAsyncKeyState'],
          [Fiddle::TYPE_INT],
          Fiddle::TYPE_SHORT,
        )
        @ctrl_poll_timer = UI.start_timer(0.05, true) do
          poll_ctrl_state
        end
      end

      def stop_ctrl_poll_timer
        if @ctrl_poll_timer
          UI.stop_timer(@ctrl_poll_timer)
          @ctrl_poll_timer = nil
        end
      end

      def poll_ctrl_state
        return unless @ctrl_async_key_state
        held = (@ctrl_async_key_state.call(0x11) & 0x8000) != 0
        if held && !@ctrl_was_held
          @coordinated_extrusion = !@coordinated_extrusion
          # Switching into coordinated FaceUp drops the "both sides" stop, so
          # fall back to a forward extrusion if it was engaged.
          set_direction_forward if @both_sides && !both_sides_available?
          rebuild_preview_cache
          update_status_text
          (@current_view || Sketchup.active_model.active_view).invalidate
        end
        @ctrl_was_held = held
      rescue StandardError => e
        Debug.log(self.class, __method__, "Ctrl poll failed: #{e.class}: #{e.message}")
        stop_ctrl_poll_timer
      end

      def enableVCB?
        true
      end

      def getExtents
        bb = Sketchup.active_model.bounds
        return bb if @preview_cache.empty? || @extrusion_distance.zero?

        dist = @extrusion_distance
        if surface_style_preview?
          @preview_cache.each do |group|
            group[:vert_disp].each do |v, disp|
              p = group[:vert_pos][v]
              bb.add(p)
              bb.add(Geom::Point3d.new(p.x + dist * disp.x, p.y + dist * disp.y, p.z + dist * disp.z))
            end
          end
        else
          lo, hi = preview_offsets
          @preview_cache.each do |data|
            n = data[:normal]
            data[:loops].each do |lp|
              lp.each do |p|
                bb.add(p.offset(n, lo))
                bb.add(p.offset(n, hi))
              end
            end
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
        draw_orange_line(view)
        draw_normal_lock(view)
        # Suppress the cursor's snap indicator while normal-locked — movement is
        # purely along the line, so off-line snaps must not be shown.
        @cursor_ip.draw(view) if @cursor_ip.display? && !@normal_lock
      end

      def onLButtonDown(flags, x, y, view)
        # Experimental: clicking the orange point (cursor resting on a selected
        # face) locks the extrusion to that face's normal axis, anchored there —
        # from any non-locked state, even mid/after a reference measurement.
        if !@normal_lock && @hover_point
          activate_normal_lock(view, x, y)
          update_status_text
          return
        end
        # While normal-locked, every click stays on the normal: a frozen
        # distance just re-opens for adjustment along the same line — it never
        # re-picks the origin/face. Only ESC leaves the lock. Recompute now (at
        # the click position) so the preview updates without waiting for a move.
        if @normal_lock && @distance_frozen
          @distance_frozen         = false
          @frozen_point            = nil
          @pending_commit_distance = nil
          @cursor_screen           = Geom::Point3d.new(x, y, 0)
          pick_cursor(view, x, y)
          @extrusion_distance      = compute_pick_distance(@cursor_ip)
          update_vcb(nil, @extrusion_distance.to_s)
          update_status_text
          view.invalidate
          return
        end
        if @distance_frozen
          # A distance is already marked: this click starts a NEW measurement
          # — it becomes the start point and the next click marks the end. The
          # distance always takes an explicit start *and* end; re-clicking
          # never nudges the old end. Stash the marked distance so a double-
          # click (whose leading down lands here) still commits what was dialed
          # in; the end-click branch clears the stash once a fresh end is set.
          @pending_commit_distance = @extrusion_distance
          @anchor_ip.pick(view, x, y)
          @cursor_ip.pick(view, x, y)
          @anchor_set         = true
          @distance_frozen    = false
          @frozen_point       = nil
          @extrusion_distance = compute_pick_distance(@cursor_ip)  # ~0 at the new start
          update_vcb(nil, @extrusion_distance.to_s)
          view.invalidate
          Debug.log(self.class, __method__, "Re-anchor (new start) at #{@anchor_ip.position}")
        elsif !@anchor_set
          @anchor_ip.pick(view, x, y)
          @cursor_ip.pick(view, x, y)
          @anchor_set = true
          Debug.log(self.class, __method__, "Anchor set at #{@anchor_ip.position}")
        else
          pick_cursor(view, x, y)
          @extrusion_distance      = compute_pick_distance(@cursor_ip)
          @distance_frozen         = true
          @frozen_point            = effective_cursor_position(view)
          @pending_commit_distance = nil
          update_vcb(nil, @extrusion_distance.to_s)
          view.invalidate
          Debug.log(self.class, __method__, "Distance set: #{@extrusion_distance} — cursor=#{@cursor_ip.position}")
        end
        update_status_text
      end

      def onKeyDown(key, repeat, flags, view)
        case key
        when KEYS[:esc]
          if @anchor_set || @distance_frozen
            reset_pick_state(view)
            update_status_text
            view.invalidate
            return true
          else
            reset_tool
          end
        when KEYS[:tab]
          cycle_extrude_direction(view)
          return true
        when KEYS[:arrow_left]  # X axis (red)
          toggle_axis_lock(:x, view)
        when KEYS[:arrow_right] # Y axis (green)
          toggle_axis_lock(:y, view)
        when KEYS[:arrow_up]    # Z axis (blue)
          toggle_axis_lock(:z, view)
        when KEYS[:shift]
          return false if repeat || @inference_lock_held
          view.lock_inference(@cursor_ip)
          @inference_lock_held = true
          view.invalidate
          return true
        end
      end

      def onKeyUp(key, repeat, flags, view)
        if key == KEYS[:shift] && @inference_lock_held
          view.lock_inference
          @inference_lock_held = false
          recompute_distance
          view.invalidate
          return true
        end
        false
      end

      def onMouseMove(flags, x, y, view)
        @cursor_screen = Geom::Point3d.new(x, y, 0)
        @current_view  = view
        sync_inference_lock(flags, view)
        pick_cursor(view, x, y)
        update_v_ip
        update_hover_point

        if @anchor_set && !@distance_frozen
          @extrusion_distance = compute_pick_distance(@cursor_ip)
          update_vcb(nil, @extrusion_distance.to_s)
        end
        update_status_text
        view.invalidate
      end

      def onReturn(view)
        execute(view)
        reset_tool
      end

      def onLButtonDoubleClick(flags, x, y, view)
        # The leading down of this double-click may have restarted a fresh
        # measurement off a frozen distance (collapsing it); restore the
        # marked value so the double-click still commits what was dialed in.
        @extrusion_distance = @pending_commit_distance if @pending_commit_distance
        execute(view)
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
          Sketchup::set_status_text(Lang.t(:tools, :faceup, :invalid_length), SB_PROMPT)
        end
      end

      private

      # The cursor InputPoint uses the strongest available context:
      # - while a distance is frozen, pick context-free so the cursor simply
      #   detects vertices/edges, ready to drop a NEW start point — no
      #   from-anchor inference lingering from the finished measurement.
      # - @v_ip when a previously-snapped reference vertex/edge/face is alive,
      #   so SketchUp draws "from V on X axis" inferences with native magnetism.
      # - else @anchor_ip once an anchor click has been made, for from-anchor
      #   axis inferences.
      # - else nothing (free cursor).
      def pick_cursor(view, x, y)
        if @distance_frozen
          @cursor_ip.pick(view, x, y)
        elsif @v_ip && @v_ip.valid?
          @cursor_ip.pick(view, x, y, @v_ip)
        elsif @anchor_set
          @cursor_ip.pick(view, x, y, @anchor_ip)
        else
          @cursor_ip.pick(view, x, y)
        end
      end

      # Snapshot the cursor as the from-point reference (V) the first time it
      # snaps to a vertex or edge after the cursor was lost. Once V is set we
      # don't retarget it until the cursor leaves the geometry entirely. Two
      # reasons:
      #
      # - Faces don't get to set V — SketchUp doesn't draw axis inferences from
      #   face references, so drifting from a vertex onto an adjacent face
      #   would silently kill the correspondence line.
      # - Hovering near another vertex (e.g. an edge endpoint) doesn't get to
      #   retarget V either. If it did, the cursor would magnetize to that new
      #   vertex, V would jump there, and `(cursor − V) = 0` would erase the
      #   correspondence line at the worst possible moment.
      #
      # Frozen while the inference lock is held.
      def update_v_ip
        return if @inference_lock_held
        if @v_ip
          @v_ip = nil unless @cursor_ip.valid?
        elsif @cursor_ip.vertex || @cursor_ip.edge
          new_v = Sketchup::InputPoint.new
          new_v.copy!(@cursor_ip)
          @v_ip = new_v
        end
      end

      # Experimental normal-lock hover: when the cursor rests on one of the
      # original (selected) faces, remember the picked point and that face's
      # world normal, so draw() shows the orange dot and a click can lock the
      # extrusion to the normal axis through it. Cleared while the lock is held.
      def update_hover_point
        @hover_point  = nil
        @hover_normal = nil
        # Offered in any non-locked state: resting on a selected face and
        # clicking it enters the normal lock (see onLButtonDown), even after a
        # reference measurement is already under way or frozen.
        return if @normal_lock
        f = @cursor_ip.face
        return unless f && @selected_faces.include?(f)
        n = f.normal.transform(@cursor_ip.transformation)
        return if n.length < 1.0e-9
        @hover_point  = @cursor_ip.position
        @hover_normal = n.normalize
      end

      # Lock the extrusion to the hovered face's normal, anchored at the clicked
      # point. From here the cursor is projected onto that normal line and the
      # distance is its signed offset (so the extrusion runs both ways). ESC
      # (reset_pick_state) clears the lock.
      def activate_normal_lock(view, x, y)
        @normal_lock   = true
        @normal_origin = @hover_point
        @normal_dir    = @hover_normal
        @anchor_ip.pick(view, x, y)   # anchor coincides with the orange point
        @cursor_ip.pick(view, x, y)
        @anchor_set      = true
        @distance_frozen = false      # drop any reference measurement in progress
        @frozen_point    = nil
        @pending_commit_distance = nil
        @flip_direction  = false      # sign now comes from the cursor projection
        @hover_point     = nil
        @hover_normal    = nil
        @extrusion_distance = 0.to_l
        update_vcb(nil, @extrusion_distance.to_s)
        view.invalidate
        Debug.log(self.class, __method__, "Normal lock @#{@normal_origin}, dir #{@normal_dir}")
      end

      # Reconcile the inference lock with the live Shift modifier bit. SketchUp's
      # onKeyDown/Up for modifier keys is unreliable on Windows, so the flag
      # bit (carried on every mouse-move event) is the canonical signal.
      def sync_inference_lock(flags, view)
        held = (flags & CONSTRAIN_MODIFIER_MASK) != 0
        if held && !@inference_lock_held
          view.lock_inference(@cursor_ip)
          @inference_lock_held = true
        elsif !held && @inference_lock_held
          view.lock_inference
          @inference_lock_held = false
          recompute_distance
        end
      end

      def toggle_axis_lock(axis, view)
        return unless @anchor_set
        @axis_lock = (@axis_lock == axis) ? nil : axis
        recompute_distance
        update_status_text
        view.invalidate
      end

      def recompute_distance
        return unless @anchor_set && !@distance_frozen && @cursor_ip.valid?
        @extrusion_distance = compute_pick_distance(@cursor_ip)
        update_vcb(nil, @extrusion_distance.to_s)
      end

      # Whether the "both sides" Tab state is offered. For now only independent
      # FaceUp (a plain prism centred on the face plane); SurfaceUp and
      # coordinated FaceUp keep the two-way forward/backward cycle.
      def both_sides_available?
        @mode == :face && !@coordinated_extrusion
      end

      # Tab cycles the extrusion direction. With "both sides" available it sits
      # between the two one-sided states, reached from each:
      #   forward → both → backward → both → forward …
      # `@both_pending_flip` remembers which one-sided state the *next* Tab out
      # of "both" lands on (the two "both" stops differ only in that). Where
      # "both" isn't available (SurfaceUp, coordinated FaceUp) Tab just toggles
      # forward/backward. "Both" keeps the distance positive — it's the total
      # thickness, split half to each side; the one-sided states carry the sign.
      def cycle_extrude_direction(view)
        if !both_sides_available?
          @flip_direction = !@flip_direction
          apply_direction_sign
        elsif @both_sides
          @both_sides     = false
          @flip_direction = @both_pending_flip
          apply_direction_sign
        else
          # Entering "both": remember which side the next Tab exits to, then
          # clear the flip so the distance reads positive (it's the total
          # thickness, sign-free) while in this symmetric stop.
          @both_pending_flip  = !@flip_direction
          @flip_direction     = false
          @both_sides         = true
          @extrusion_distance = @extrusion_distance.abs.to_l
        end
        update_vcb(nil, @extrusion_distance.to_s)
        update_status_text
        # The coordinated wall miter bakes the extrusion sign into the cached
        # per-vertex displacement (a forward vs an inverted miter map), so the
        # preview must rebuild when Tab flips the direction or it would draw the
        # forward miter at a now-negative distance.
        rebuild_preview_cache
        view.invalidate
      end

      # Coerce @extrusion_distance to its magnitude with the current flip sign.
      # `-Length` collapses to a raw Float (which `.to_s`es in inches and breaks
      # the VCB), so round-trip back to Length for the model's display units.
      def apply_direction_sign
        mag = @extrusion_distance.abs
        @extrusion_distance = (@flip_direction ? -mag : mag).to_l
      end

      def set_direction_forward
        @both_sides         = false
        @flip_direction     = false
        @extrusion_distance = @extrusion_distance.abs.to_l
      end

      def reset_pick_state(view)
        view.lock_inference if @inference_lock_held
        @inference_lock_held = false
        @anchor_set          = false
        @distance_frozen     = false
        @frozen_point        = nil
        @pending_commit_distance = nil
        @axis_lock           = nil
        @normal_lock         = false   # experimental: lock extrusion to a face normal
        @normal_origin       = nil     # the clicked point on the original face (origin)
        @normal_dir          = nil     # that face's world normal (the locked axis)
        @hover_point         = nil     # current snap point on an original face (orange dot)
        @hover_normal        = nil
        @v_ip                = nil
        @anchor_ip           = Sketchup::InputPoint.new
      end

      def update_status_text
        dir = @both_sides ? Lang.t(:tools, :faceup, :status_both_sides) : ""
        coord_hint = if @mode == :surface || @mode == :face
          mode = @coordinated_extrusion ? Lang.t(:tools, :faceup, :mode_coordinated) : Lang.t(:tools, :faceup, :mode_normal)
          ext  = (@mode == :surface && @ignore_external_context) ? " #{Lang.t(:tools, :faceup, :no_external_context)}" : ""
          " | #{Lang.t(:tools, :faceup, :ctrl_mode)} #{mode}#{ext}"
        else
          ""
        end
        tab = " | #{Lang.t(:tools, :faceup, :tab_flip)}"
        @status_text = if @distance_frozen
          "#{Lang.t(:tools, :faceup, :status_adjust)}#{tab}#{dir}#{coord_hint}"
        elsif !@anchor_set
          "#{Lang.t(:tools, :faceup, :status_idle)}#{tab}#{dir}#{coord_hint}"
        else
          "#{Lang.t(:tools, :faceup, :status_pick)}#{tab}#{dir}#{coord_hint}"
        end
        Sketchup::set_status_text(@status_text)
      end

      # Rebuild after a Ctrl toggle: the cache style depends on
      # coordinated/independent, so rebuild through the mode-aware builder.
      def rebuild_preview_cache
        return if @selected_faces.empty?
        @preview_cache = build_preview_cache
      end

      def execute(view)
        return if @selected_faces.empty?

        faces_to_extrude = @selected_faces
        @selected_faces  = []  # stop preview immediately

        model     = Sketchup.active_model
        method_id = __method__

        start_time = Time.now if Debug.enabled
        Debug.separator
        Debug.log(self.class, method_id, "Process START — distance=#{@extrusion_distance}")

        model.start_operation("FaceUp", true)
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
        return draw_surface_highlight(view) if surface_style_preview?

        tris = @preview_cache.flat_map { |data| data[:tris].flatten }

        view.drawing_color = Sketchup::Color.new('white')
        view.draw(GL_TRIANGLES, tris)

        return unless show_preview_outlines?

        view.drawing_color = PREVIEW_BLUE
        @preview_cache.each { |data| data[:loops].each { |lp| view.draw(GL_LINE_LOOP, lift_off_face(lp, view, 5)) } }
      end

      # Normal lift is [0, dist]; "both sides" straddles the face plane at
      # ±dist/2, so the preview mirrors the symmetric solid the executed
      # extrusion builds.
      def preview_offsets
        if @both_sides
          half = @extrusion_distance.abs / 2.0
          [-half, half]
        else
          [0, @extrusion_distance]
        end
      end

      # Whether the preview should draw its contour (outline/hard) edges.
      # Dropping them on very large selections keeps the per-frame preview
      # responsive — the fills still draw, only the outline GL_LINES are
      # skipped. CONFIG[:preview_outline_limit] is the max selected-face count
      # that still shows them; 0 (or negative) disables the cap entirely.
      def show_preview_outlines?
        limit = CONFIG[:preview_outline_limit].to_i
        limit <= 0 || @selected_faces.length <= limit
      end

      def draw_extrusion_preview(view)
        return if @preview_cache.empty?
        return draw_surface_extrusion_preview(view) if surface_style_preview?

        show_outlines = show_preview_outlines?
        lo, hi = preview_offsets
        gray_tris  = []
        gray_quads = []
        white_tris = []
        hard_lines = []

        @preview_cache.each do |data|
          n = data[:normal]

          data[:tris].each do |pts|
            bot = pts.map { |p| p.offset(n, lo) }
            top = pts.map { |p| p.offset(n, hi) }

            gray_tris.concat(bot)
            pts.each_index do |j|
              k = (j + 1) % pts.length
              gray_quads.concat([bot[j], bot[k], top[k], top[j]])
            end
            white_tris.concat(top)
          end

          # Top and vertical edges — hard edges only. With both sides the
          # bottom is a real face too, so draw its outline as well.
          if show_outlines
            data[:hard_edges].each do |s, e|
              sb = s.offset(n, lo); eb = e.offset(n, lo)
              st = s.offset(n, hi); et = e.offset(n, hi)
              hard_lines.concat([st, et, sb, st, eb, et])
              hard_lines.concat([sb, eb]) if @both_sides
            end
          end

        end

        view.drawing_color = ORIGINAL_FACE_BLUE
        view.draw(GL_TRIANGLES, gray_tris)

        view.drawing_color = Sketchup::Color.new(220, 220, 220)
        view.draw(GL_QUADS, gray_quads)

        view.drawing_color = Sketchup::Color.new('white')
        view.draw(GL_TRIANGLES, white_tris)

        return unless show_outlines

        # Face outline at BOTH the base and the offset loop. The base loop used
        # to be drawn only for both-sided extrusion (the original face was left
        # to show through), but the ORIGINAL_FACE_BLUE fill now covers it, hiding
        # the shared verticals between adjacent panels. So draw the base loop too
        # — matching coordinated mode, which always draws its base outline.
        # Lifted toward the camera (see draw_surface_extrusion_preview) so an
        # outline coplanar with an adjacent panel's face wins the z-fight
        # instead of vanishing into it. The base loop (the original face, like
        # its fill) stays blue; the offset loop (the new top) is orange.
        @preview_cache.each do |data|
          n = data[:normal]
          data[:loops].each do |loop_pts|
            view.drawing_color = ORANGE
            view.draw(GL_LINE_LOOP, lift_off_face(loop_pts.map { |p| p.offset(n, hi) }, view, 5))
            view.drawing_color = PREVIEW_BLUE
            view.draw(GL_LINE_LOOP, lift_off_face(loop_pts.map { |p| p.offset(n, lo) }, view, 5))
          end
        end

        # Top and vertical hard edges — new, so orange.
        view.drawing_color = ORANGE
        view.draw(GL_LINES, lift_off_face(hard_lines, view, 5)) unless hard_lines.empty?
      end

      # Idle highlight when no distance is set yet: surface mode shows the
      # welded surface as one mesh and outlines only its perimeter (not the
      # internal soft edges that connect the constituent faces).
      def draw_surface_highlight(view)
        show_outlines = show_preview_outlines?
        bottom_tris = []
        outline_lines = []
        @preview_cache.each do |group|
          group[:tris].each do |tri|
            # Idle highlight: no distance yet, so the base is untrimmed (dist 0).
            tri.each { |meta| bottom_tris << surface_meta_bottom(meta, nil, group[:vert_pos], 0) }
          end
          next unless show_outlines
          group[:boundary].each do |v1, v2, _n|
            outline_lines << group[:vert_pos][v1] << group[:vert_pos][v2]
          end
        end

        view.drawing_color = Sketchup::Color.new('white')
        view.draw(GL_TRIANGLES, bottom_tris) unless bottom_tris.empty?

        view.drawing_color = PREVIEW_BLUE
        view.line_stipple  = ''
        view.draw(GL_LINES, lift_off_face(outline_lines, view, 5)) unless outline_lines.empty?
      end

      # Welded-surface extrusion preview. Per-vertex displacements come from
      # the same LSQ solver as the executed extrusion, so the preview matches
      # the final result (top is an equidistant surface, walls only on the
      # surface boundary, internal soft edges disappear into the skin).
      def draw_surface_extrusion_preview(view)
        raw_dist = @extrusion_distance
        internal = show_preview_outlines?   # below the limit: also draw internal edges
        gray_tris      = []
        gray_quads     = []
        gray_extras    = []   # fan-triangulated walls when the quad isn't planar
        white_tris     = []
        outline_top    = []
        outline_bottom = []
        hard_corner_lines    = []
        hard_internal_lines  = []

        @preview_cache.each do |group|
          vert_disp      = group[:vert_disp]
          vert_pos       = group[:vert_pos]
          vert_base_disp = group[:vert_base_disp]
          # Same flip-clamp the executed extrusion uses, so the preview
          # matches the result instead of running past the safe range.
          # Coordinated face mode stops a hair short of the exact collapse
          # (COORD_FACE_CAP_SAFETY) so the converging tip stays clean; the
          # preview must apply the same margin to match the result.
          cap_sf = @mode == :face ? COORD_FACE_CAP_SAFETY : 1.0
          hi = group[:max_safe_h] && group[:max_safe_h] * cap_sf
          lo = group[:min_safe_h] && group[:min_safe_h] * cap_sf
          dist = raw_dist
          dist = hi if hi && dist > hi
          dist = lo if lo && dist < lo

          # Only taper the holes when the panel is capped at its converging tip
          # (dist clamped below the requested distance), matching the executor —
          # otherwise the holes stay straight perpendicular shafts.
          converging = dist.to_f.abs < raw_dist.to_f.abs - 1.0e-6
          hole_scale = converging ? coordinated_face_hole_scale(group, dist) : nil

          group[:tris].each do |tri|
            bottom = tri.map { |meta| surface_meta_bottom(meta, vert_base_disp, vert_pos, dist) }
            top    = tri.map { |meta| surface_meta_top(meta, vert_disp, vert_pos, dist, hole_scale) }
            gray_tris.concat(bottom)
            white_tris.concat(top)
          end

          group[:boundary].each do |v1, v2, _n, seam, buried|
            next if seam || buried   # seam/buried-cap: no wall fill (seam outline still drawn below)
            bs = surface_bottom_pt(v1, vert_base_disp, vert_pos, dist)
            be = surface_bottom_pt(v2, vert_base_disp, vert_pos, dist)
            ts = surface_top_pt(v1, vert_disp, vert_pos, dist)
            te = surface_top_pt(v2, vert_disp, vert_pos, dist)
            quad = [bs, be, te, ts]
            if coplanar?(quad)
              gray_quads.concat(quad)
            else
              gray_extras.concat([bs, be, te, bs, te, ts])
            end
          end

          # Contour edges of the GENERATED result. Its exterior PERIMETER always
          # draws — every non-seam boundary edge (the silhouette AND the exposed
          # cantos at crossing corners, which are real exterior faces), below.
          # The INTERNAL edges — junction corner verticals, a surface's internal
          # ridges, and the coincident seams between continuous panels — are
          # dropped on heavy selections (CONFIG[:preview_outline_limit]) so only
          # the perimeter shows and the per-frame draw stays light.
          if internal
            group[:hard_corner_verts].each_key do |corner|
              bs = surface_bottom_pt(corner, vert_base_disp, vert_pos, dist)
              ts = surface_top_pt(corner, vert_disp, vert_pos, dist)
              hard_corner_lines.concat([bs, ts])
            end

            group[:hard_internal_edges].each do |v1, v2|
              bs = surface_bottom_pt(v1, vert_base_disp, vert_pos, dist)
              be = surface_bottom_pt(v2, vert_base_disp, vert_pos, dist)
              ts = surface_top_pt(v1, vert_disp, vert_pos, dist)
              te = surface_top_pt(v2, vert_disp, vert_pos, dist)
              hard_internal_lines.concat([bs, be, ts, te])
            end
          end

          group[:boundary].each do |v1, v2, _n, seam, _buried|
            # A coincident internal seam draws only when internal edges are on;
            # the exterior perimeter — every non-seam edge, including exposed
            # cantos — always draws (those are real faces of the result).
            next if seam && !internal
            outline_bottom << surface_bottom_pt(v1, vert_base_disp, vert_pos, dist)
            outline_bottom << surface_bottom_pt(v2, vert_base_disp, vert_pos, dist)
            outline_top << surface_top_pt(v1, vert_disp, vert_pos, dist)
            outline_top << surface_top_pt(v2, vert_disp, vert_pos, dist)
          end

        end

        view.drawing_color = ORIGINAL_FACE_BLUE
        view.draw(GL_TRIANGLES, gray_tris)   unless gray_tris.empty?

        view.drawing_color = Sketchup::Color.new(220, 220, 220)
        view.draw(GL_QUADS,     gray_quads)  unless gray_quads.empty?
        view.draw(GL_TRIANGLES, gray_extras) unless gray_extras.empty?

        view.drawing_color = Sketchup::Color.new('white')
        view.draw(GL_TRIANGLES, white_tris) unless white_tris.empty?

        view.line_stipple  = ''
        # Lift every contour line ~5 px toward the camera. The seam / cap /
        # junction verticals lie coplanar with a neighbour panel's face (their
        # own fill or the still-present original face), so undisplaced they
        # z-fight and vanish. The lift is along the view direction, so the
        # screen position is unchanged — it only wins the depth tie — and a
        # 5 px nudge still lets real front geometry occlude back-side edges.
        # Original (base) edges stay blue; the NEW edges the extrusion draws —
        # offset perimeter, wall verticals and internal hard edges — are orange.
        view.drawing_color = PREVIEW_BLUE
        view.draw(GL_LINES, lift_off_face(outline_bottom, view, 5))    unless outline_bottom.empty?
        view.drawing_color = ORANGE
        view.draw(GL_LINES, lift_off_face(outline_top, view, 5))       unless outline_top.empty?
        view.draw(GL_LINES, lift_off_face(hard_corner_lines, view, 5)) unless hard_corner_lines.empty?
        view.draw(GL_LINES, lift_off_face(hard_internal_lines, view, 5)) unless hard_internal_lines.empty?
      end

      # Edges that pass through the middle of a filled mesh z-fight with
      # the fill at exactly the same depth. Nudging each point toward the
      # camera by a few pixels' worth of model space (computed at that
      # point's own depth so perspective foreshortening doesn't shrink the
      # offset on far points) wins the depth test against the fill while
      # still leaving 3D depth-testing in place so the line is occluded
      # by intervening front-facing geometry.
      def lift_off_face(points, view, px = 5)
        return points if points.empty?
        d = view.camera.direction
        points.map do |p|
          amt = view.pixels_to_model(px, p)
          amt = 0 if amt < 0
          Geom::Point3d.new(p.x - amt * d.x, p.y - amt * d.y, p.z - amt * d.z)
        end
      end

      def surface_meta_bottom(meta, vert_base_disp, vert_pos, dist)
        if meta[0] == :v || meta[0] == :hole
          surface_bottom_pt(meta[1], vert_base_disp, vert_pos, dist)
        else
          meta[1]
        end
      end

      # Bottom point of a vertex column: the base, slid by the coordinated base
      # trim when present (inverted subordinate panels) so the preview's bottom
      # matches the executed result; otherwise the untouched base position.
      def surface_bottom_pt(vertex, vert_base_disp, vert_pos, dist)
        p = vert_pos[vertex]
        d = vert_base_disp && vert_base_disp[vertex]
        return p unless d
        Geom::Point3d.new(p.x + dist * d.x, p.y + dist * d.y, p.z + dist * d.z)
      end

      # `hole_scale` is [ct, s] for coordinated face mode: hole-loop points are
      # slid toward the panel's convergence centre `ct` by the outer's
      # contraction `s`, matching `scale_panel_holes` so the preview shows the
      # hole tapering/converging like the result. nil (surface mode, no holes)
      # leaves hole points on their straight perpendicular lift.
      def surface_meta_top(meta, vert_disp, vert_pos, dist, hole_scale = nil)
        case meta[0]
        when :v
          surface_top_pt(meta[1], vert_disp, vert_pos, dist)
        when :hole
          p = surface_top_pt(meta[1], vert_disp, vert_pos, dist)
          return p unless hole_scale
          ct, s = hole_scale
          Geom::Point3d.new(ct.x + s * (p.x - ct.x), ct.y + s * (p.y - ct.y), ct.z + s * (p.z - ct.z))
        else
          meta[1].offset(meta[2], dist)
        end
      end

      def surface_top_pt(vertex, vert_disp, vert_pos, dist)
        d = vert_disp[vertex]
        p = vert_pos[vertex]
        Geom::Point3d.new(p.x + dist * d.x, p.y + dist * d.y, p.z + dist * d.z)
      end

      # Convergence centre `ct` and contraction `s` for a coordinated face
      # panel's holes at the current distance — the same quantities
      # `scale_panel_holes` uses on the result, so the preview's holes taper
      # and converge identically. Returns nil for surface mode, holeless
      # panels, or degenerate input.
      def coordinated_face_hole_scale(group, dist)
        return nil unless @mode == :face && group[:has_holes] && group[:outer_verts]
        vp = group[:vert_pos]
        vd = group[:vert_disp]
        ob = group[:outer_verts].map { |v| vp[v] }
        ot = group[:outer_verts].map { |v| surface_top_pt(v, vd, vp, dist) }
        cb = average_position(ob)
        ct = average_position(ot)
        den = ob.reduce(0.0) { |a, p| a + p.distance(cb) }
        return nil if den < 1.0e-9
        s = ot.reduce(0.0) { |a, p| a + p.distance(ct) } / den
        [ct, s]
      end

      # Build the cache entries for surface mode: one per soft-connected
      # face group. Each entry stores per-vertex unit displacement (so the
      # preview scales linearly with @extrusion_distance), pre-triangulated
      # surface mesh, boundary edges (for wall preview) and hard boundary
      # edges (for the blue outline).
      # True when the cache is built with the welded-surface machinery —
      # surface mode, or coordinated face mode (singleton-per-face). Drives
      # which draw/extents path the preview takes.
      def surface_style_preview?
        @mode == :surface || @coordinated_extrusion
      end

      # Mode-aware preview cache. Surface mode and coordinated face mode both
      # use the welded-surface builder (face mode treats each face as its own
      # singleton surface, so walls form on every edge); independent face mode
      # keeps the lightweight per-face pushpull cache.
      def build_preview_cache
        if @mode == :surface
          build_surface_preview_cache(@selected_faces)
        elsif @coordinated_extrusion
          build_coordinated_face_preview_cache(@selected_faces)
        else
          build_independent_face_preview_cache(@selected_faces)
        end
      end

      def build_surface_preview_cache(faces)
        groups = group_faces_by_soft_connectivity(faces)

        if @coordinated_extrusion
          coord = coordinated_preview_data(groups)
        else
          coord = nil
        end

        groups.each_with_index.map do |gfaces, i|
          build_surface_preview_group(gfaces, coord, i)
        end
      end

      # Coordinated face mode: one singleton surface group per face so the
      # mitered tops and per-edge walls are drawn by the surface machinery,
      # with shared vertices unified across panels by position.
      def build_coordinated_face_preview_cache(faces)
        groups = faces.map { |f| [f] }
        coord  = coordinated_preview_data(groups)
        groups.each_with_index.map do |gfaces, i|
          build_surface_preview_group(gfaces, coord, i)
        end
      end

      # Independent face mode: per-face pushpull preview (bottom mesh, outer
      # loop, hard contour edges) lifted uniformly along the face normal.
      def build_independent_face_preview_cache(faces)
        faces.map do |face|
          mesh  = face.mesh(7)
          loops      = []
          hard_edges = []
          # All loops — outer AND holes — so the hole contours (and their hard
          # verticals) preview like the result, not just the outer perimeter.
          face.loops.each do |loop|
            verts = loop.vertices
            edges = loop.edges
            kept  = simplifiable_kept_indices(verts, edges)
            loops << kept.map { |i| verts[i].position }
            kept.length.times do |k|
              e = edges[kept[k]]
              next if e.soft? || e.curve
              i_next = kept[(k + 1) % kept.length]
              hard_edges << [verts[kept[k]].position, verts[i_next].position]
            end
          end
          {
            normal:     face.normal,
            tris:       mesh.polygons.map { |tri| tri.map { |i| mesh.point_at(i.abs) } },
            loops:      loops,
            hard_edges: hard_edges,
          }
        end
      end

      # Position-keyed coordination data for the preview cache. Same
      # algorithm as `compute_coord_data_by_position` — see notes there.
      def coordinated_preview_data(groups)
        compute_coord_data_by_position(groups)
      end

      def build_surface_preview_group(gfaces, coord = nil, _group_idx = nil)
        vertex_faces = Hash.new { |h, k| h[k] = [] }
        edge_face_count = Hash.new(0)
        edge_faces      = Hash.new { |h, k| h[k] = [] }
        gfaces.each do |f|
          f.vertices.each { |v| vertex_faces[v] << f }
          f.edges.each    { |e| edge_face_count[e] += 1; edge_faces[e] << f }
        end

        vert_pos       = {}
        vert_disp      = {}
        vert_base_disp = {}
        vertex_faces.each do |v, vf|
          p     = v.position
          disp  = nil
          bdisp = nil
          if coord
            k   = pos_key(p)
            inv = @extrusion_distance.to_f < 0
            # Per-wall miter (forward) keeps every wall at consistent thickness;
            # it also subsumes the run/partition flush. Falls through to the
            # equidistant/subordinate path for non-wall (SurfaceUp) or inverted.
            mm  = inv ? coord[:miter_disp_inv] : coord[:miter_disp]
            md  = mm ? mm[[[k[0], k[1]], norm_key(vf.first.normal)]] : nil
            if md
              disp = md
            else
              dom = coord[:dominant_by_pos] && coord[:dominant_by_pos][k]
              subordinate = dom && dom.any? && vf.none? { |f| dom.any? { |dn| dn.parallel?(f.normal) } }
              disp = subordinate ? subordinate_disp(vf.first.normal, dom, inv) : coord[:unit_disp_by_pos][k]
            end
            # Inverted coordinated FACE mode only: the executor
            # (move_panel_top_to_coordinated) also slides a subordinate panel's
            # BASE end into the neighbour run's offset plane (subordinate_base_shift),
            # keeping base and mitered top parallel — a clean parallelogram.
            # Without replicating it the preview keeps the untrimmed base and
            # shows the panel as a trapezoid (the "bevel" on interior faces).
            # SurfaceUp's executor doesn't trim, so it's scoped out here.
            bdisp = preview_base_disp(p, vf.first.normal, coord) if inv && @mode == :face
          end
          unless disp
            top1 = compute_offset_vertex(p, vf.map(&:normal), 1.0)
            disp = Geom::Vector3d.new(top1.x - p.x, top1.y - p.y, top1.z - p.z)
          end
          vert_pos[v]       = p
          vert_disp[v]      = disp
          vert_base_disp[v] = bdisp if bdisp
        end

        tris = []
        gfaces.each do |face|
          mesh = face.mesh(7)
          # Geom::Point3d doesn't implement value-based hash/eql, so use a
          # rounded coordinate tuple as the lookup key. Without this the
          # mesh's corner points fall through to the :interior branch and
          # adjacent faces' tops drift apart at shared vertices.
          loop_v_by_pos = {}
          face.outer_loop.vertices.each do |v|
            loop_v_by_pos[pos_key(v.position)] = v
          end
          hole_v_by_pos = {}
          face.loops.each do |lp|
            next if lp.outer?
            lp.vertices.each { |v| hole_v_by_pos[pos_key(v.position)] = v }
          end
          point_meta = {}
          (1..mesh.count_points).each do |pi|
            pt = mesh.point_at(pi)
            k  = pos_key(pt)
            point_meta[pi] = if (ov = loop_v_by_pos[k])
              [:v, ov]
            elsif (hv = hole_v_by_pos[k])
              [:hole, hv]
            else
              [:interior, pt, face.normal]
            end
          end
          mesh.polygons.each do |tri|
            tris << tri.map { |i| point_meta[i.abs] }
          end
        end

        boundary            = []
        hard_internal_edges = []
        edge_seen           = {}
        gfaces_set          = gfaces.to_set
        gfaces.each do |face|
          # All loops, not just the outer one: hole (inner-loop) edges are real
          # boundary edges too (count == 1), so they get their wall and contour
          # drawn — otherwise coordinated mode shows no hole outline.
          face.edges.each do |edge|
            next if edge_seen[edge]
            edge_seen[edge] = true
            count = edge_face_count[edge]
            if count == 1
              v1 = edge.start
              v2 = edge.end
              # Coordinated FACE mode builds each panel as its own pushpulled
              # box, so a shared junction edge is an internal seam: its wall
              # fill would show as a bevel (the cap is hidden in the merged
              # result), but its outline edges are real and must still be drawn.
              # So mark it — the draw skips the fill but keeps the outline.
              # SurfaceUp's executor builds walls on its seams, so seam = false
              # there and the wall stays. But suppress the wall ONLY when this
              # panel actually coordinates at the seam — either it continues a
              # same-orientation run (a parallel-normal neighbour shares the
              # edge) or it is subordinate (mitred flush into a dominant run).
              # Otherwise (e.g. two faces of opposite/crossing orientation
              # meeting at a corner) the panels stay separate boxes and the
              # canto is a real exposed face, so its wall must be drawn.
              epk    = edge_pos_key(v1.position, v2.position)
              shared = @mode == :face && coord && coord[:shared_edge_pos] &&
                       coord[:shared_edge_pos][epk]
              coordinated = false
              if shared
                vk    = pos_key(v1.position)
                inv   = @extrusion_distance.to_f < 0
                mm    = inv ? coord[:miter_disp_inv] : coord[:miter_disp]
                norms = coord[:shared_edge_normals] && coord[:shared_edge_normals][epk]
                my    = mm && mm[[[vk[0], vk[1]], norm_key(face.normal)]]
                # A neighbour panel's offset corner coincides with this one — a
                # same-orientation run continuing, or a clean mitre meeting at
                # the same apex — so the canto is internal/coincident (count >= 2
                # includes self). Otherwise the offsets diverge (crossing corner)
                # and the canto is exposed.
                coincide = !!(my && norms && norms.count { |nn|
                  d = mm[[[vk[0], vk[1]], norm_key(nn)]]
                  d && (d.x - my.x).abs < 1.0e-4 && (d.y - my.y).abs < 1.0e-4
                } >= 2)
                # Or this panel is subordinate — mitred flush into a dominant
                # run, so its cap is coplanar with the run and hidden.
                dom = coord[:dominant_by_pos] && coord[:dominant_by_pos][vk]
                subordinate = dom && dom.any? && !dom.any? { |dn| dn.parallel?(face.normal) }
                coordinated = coincide || subordinate
              end
              seam = !!(shared && coordinated)
              # A subordinate panel's END CAP — the vertical edge at a junction
              # where the trimmed base meets the neighbour run — lands coplanar
              # with the run's inner face, so its WALL would show a stray gray
              # sliver the result hides. Mark it buried to drop that fill. (Its
              # base/offset verticals are still real hard edges, so its outline
              # is drawn like any other.) Same plan point at both ends ⇒ vertical
              # cap edge; both ends trimmed ⇒ subordinate.
              k1 = pos_key(v1.position)
              k2 = pos_key(v2.position)
              buried = !!(vert_base_disp[v1] && vert_base_disp[v2] &&
                          k1[0] == k2[0] && k1[1] == k2[1])
              boundary << [v1, v2, face.normal, seam, buried]
            elsif count == 2
              # Internal edge — predict hard top counterpart when the two
              # adjacent faces bend > 60°.
              in_group = edge.faces.select { |f| gfaces_set.include?(f) }
              next unless in_group.size == 2
              cos_a = in_group[0].normal.dot(in_group[1].normal)
              cos_a =  1.0 if cos_a >  1.0
              cos_a = -1.0 if cos_a < -1.0
              hard_internal_edges << [edge.start, edge.end] if cos_a < 0.5
            end
          end
        end

        # Predict which corner verticals end up hard after extrusion: two
        # adjacent walls meet at each boundary-corner vertex, and the
        # vertical between them is hard when their outward normals form
        # more than 60° — same threshold `classify_shell_edges` uses on
        # the final geometry. Shared seams are in `boundary` too, so this
        # catches seam-vs-perimeter junctions naturally.
        hard_corner_verts = predict_hard_corner_verticals(boundary, vert_disp)

        # Same self-intersection cap the executed extrusion uses, over the
        # same collinear-simplified loop, so the preview stops the cursor
        # distance exactly where the result welds.
        active_indices = compute_active_outer_loop_indices(gfaces, edge_faces, true)
        min_h, max_h = clamp_range_for_faces(gfaces, active_indices, vert_disp)

        {
          vert_pos:            vert_pos,
          vert_disp:           vert_disp,
          vert_base_disp:      vert_base_disp,
          tris:                tris,
          boundary:            boundary,
          hard_corner_verts:   hard_corner_verts,
          hard_internal_edges: hard_internal_edges,
          min_safe_h:          min_h,
          max_safe_h:          max_h,
          outer_verts:         gfaces.flat_map { |f| f.outer_loop.vertices }.uniq,
          has_holes:           gfaces.any? { |f| f.loops.size > 1 },
        }
      end

      # Positive/negative self-intersection caps for the preview — the
      # range `[min_h, max_h]` outside which a concave corner would fold
      # through itself. Mirrors `clamp_height_to_avoid_flip` (genuine
      # near-collapse at the edge's shortest point, over the simplified
      # loop); `nil` on a side means that direction is unconstrained.
      def clamp_range_for_faces(gfaces, active_indices, vert_disp)
        min_h = nil
        max_h = nil
        gfaces.each do |face|
          verts = face.outer_loop.vertices
          idx   = active_indices[face]
          n     = idx.length
          n.times do |k|
            v1 = verts[idx[k]]
            v2 = verts[idx[(k + 1) % n]]
            d1 = vert_disp[v1]
            d2 = vert_disp[v2]
            next unless d1 && d2
            edge_vec    = v2.position - v1.position
            edge_len_sq = edge_vec.dot(edge_vec)
            next if edge_len_sq < 1.0e-12
            diff    = Geom::Vector3d.new(d2.x - d1.x, d2.y - d1.y, d2.z - d1.z)
            diff_sq = diff.dot(diff)
            next if diff_sq < 1.0e-12
            dot_diff = diff.dot(edge_vec)
            h_min = -dot_diff / diff_sq
            next if h_min.abs < 1.0e-9
            len_min_sq = edge_len_sq - (dot_diff * dot_diff) / diff_sq
            next if len_min_sq > edge_len_sq * COLLAPSE_TOL_SQ
            if h_min > 0
              max_h = max_h ? [max_h, h_min].min : h_min
            else
              min_h = min_h ? [min_h, h_min].max : h_min
            end
          end
        end
        [min_h, max_h]
      end

      def predict_hard_corner_verticals(boundary, vert_disp)
        corner_walls = Hash.new { |h, k| h[k] = [] }
        boundary.each do |v1, v2, fn|
          corner_walls[v1] << [v1, v2, fn]
          corner_walls[v2] << [v1, v2, fn]
        end

        cos_threshold = 0.5
        hard = {}
        corner_walls.each do |corner, walls|
          next unless walls.size == 2
          n1 = approximate_wall_normal(walls[0], corner, vert_disp)
          n2 = approximate_wall_normal(walls[1], corner, vert_disp)
          next unless n1 && n2 && n1.length > 1.0e-9 && n2.length > 1.0e-9
          cos_a = n1.normalize.dot(n2.normalize)
          cos_a =  1.0 if cos_a >  1.0
          cos_a = -1.0 if cos_a < -1.0
          hard[corner] = true if cos_a < cos_threshold
        end
        hard
      end

      def approximate_wall_normal(wall, corner, vert_disp)
        v1, v2, _fn = wall
        edge_vec = Geom::Vector3d.new(
          v2.position.x - v1.position.x,
          v2.position.y - v1.position.y,
          v2.position.z - v1.position.z,
        )
        disp = vert_disp[corner]
        return nil unless disp
        edge_vec.cross(disp)
      end

      # Mode-aware dispatch. :face groups each face individually; :surface
      # groups soft-edge-connected faces into one surface group. The surface
      # branch is a placeholder until the welded-extrusion logic lands.
      def face2group(faces)
        case @mode
        when :face    then face2group_per_face(faces)
        when :surface then face2group_per_surface(faces)
        end
      end

      def face2group_per_face(faces)
        # Coordinated face mode: precompute the equidistant top per world
        # position over the selection (each face its own singleton surface),
        # so shared vertices of neighbouring panels resolve to the same
        # point and the panels meet flush at a miter. Independent mode leaves
        # the map nil and each face just pushpulls along its own normal.
        if @coordinated_extrusion
          precompute_coordinated_surface_data(faces.map { |f| [f] })
        else
          @coord_unit_disp_by_pos = nil
          @coord_dominant_by_pos  = nil
          @coord_miter_disp       = nil
          @coord_miter_disp_inv   = nil
        end

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

      # Group faces by soft-edge connectivity. Each connected component (faces
      # reachable through soft edges only) goes into its own Sketchup::Group,
      # together with all the edges that bound or stitch the surface. Visible
      # (hard) edges remain group boundaries; soft edges are internal to the
      # surface and survive into the lifted top.
      def face2group_per_surface(faces)
        surfaces = group_faces_by_soft_connectivity(faces)

        # In coordinated mode, pre-compute a unified offset per vertex
        # (using every selected face touching it, regardless of which
        # surface group it belongs to) and the set of edges shared between
        # surface groups, both keyed by position so they survive the
        # add_group cloning that follows.
        if @coordinated_extrusion
          precompute_coordinated_surface_data(surfaces)
        else
          @coord_unit_disp_by_pos = nil
          @coord_dominant_by_pos  = nil
          @coord_miter_disp       = nil
          @coord_miter_disp_inv   = nil
          @coord_shared_edge_pos  = nil
        end

        ents = Sketchup.active_model.active_entities

        # rubocop:disable SketchupSuggestions/AddGroup
        surfaces.map do |surface_faces|
          surface_edges = surface_faces.flat_map(&:edges).uniq
          ents.add_group(surface_faces + surface_edges)
        end
        # rubocop:enable SketchupSuggestions/AddGroup
      end

      def precompute_coordinated_surface_data(surfaces)
        data = compute_coord_data_by_position(surfaces)
        @coord_unit_disp_by_pos = data[:unit_disp_by_pos]
        @coord_dominant_by_pos  = data[:dominant_by_pos]
        @coord_miter_disp       = data[:miter_disp]
        @coord_miter_disp_inv   = data[:miter_disp_inv]
        @coord_shared_edge_pos  = data[:shared_edge_pos]
        @coord_shared_edge_hard = data[:shared_edge_hard]
      end

      # Position-keyed coordination data. Walks topology via world coords
      # rather than Edge/Vertex identity, so it works even when "adjacent"
      # surfaces are actually floating geometry that only coincides
      # spatially (common in faceted spheres built segment by segment).
      #
      # The map also pulls in faces from *outside* the selection that
      # touch a selected vertex — that way extruding a single surface
      # tilts its boundary to meet whatever neighbouring geometry is in
      # the model, even if those neighbours aren't being extruded.
      def compute_coord_data_by_position(surfaces)
        # Accumulate raw normals from every face touching each world
        # position. The downstream LSQ (`compute_offset_vertex`) places
        # V_top at perpendicular distance `h` from each plane, and the
        # angular dedup there collapses fan triangulations. Grouping by
        # soft-edge connectivity is tempting but wrong: a soft edge only
        # marks the *visual* absence of a crease (used for cylinder
        # walls, smoothed corners, etc.) and can sit between genuinely
        # perpendicular faces — averaging those would erase the corner.
        # Selected-face normals carry the alignment signal (how many selected
        # faces are coplanar at a vertex); external-context normals are kept
        # apart so a coplanar run can override them — see
        # `coordinated_vertex_normals`.
        pos_to_sel_normals = {}
        pos_to_ctx_normals = {}
        surfaces.each do |sf|
          sf.each do |f|
            f.vertices.each do |v|
              k = pos_key(v.position)
              (pos_to_sel_normals[k] ||= []) << f.normal
              # External source (a): faces outside the selection that touch a
              # selected vertex. Skipped when re-extruding a SurfaceUp group's
              # interior — there we only want the selected geometry to agree
              # with itself, not tilt toward whatever it sits against.
              next if @ignore_external_context
              ctx = (pos_to_ctx_normals[k] ||= [])
              v.faces.each { |adj| ctx << adj.normal }
            end
          end
        end

        # External source (b): normals from already-extruded surfaces in the
        # model. Their original face is tagged with `SURFACE_ATTR_DICT`, so we
        # don't have to guess which face in a group is the bottom — and the
        # stored vector is the pre-reverse outward normal in world coords, so
        # we just read it back. Skipped for the same reason as (a): a second
        # extrusion of a finished shell must not re-read its own (or its
        # neighbours') stored normals and drift.
        unless @ignore_external_context
          Sketchup.active_model.entities.grep(Sketchup::Group).each do |group|
            xform = group.transformation
            group.entities.grep(Sketchup::Face).each do |f|
              stored = f.get_attribute(SURFACE_ATTR_DICT, SURFACE_ATTR_NORMAL)
              next unless stored
              n_world = Geom::Vector3d.new(*stored)
              f.vertices.each do |v|
                k = pos_key(v.position.transform(xform))
                next unless pos_to_sel_normals.key?(k)
                (pos_to_ctx_normals[k] ||= []) << n_world
              end
            end
          end
        end

        # Per position: the dominant normals (a coplanar run of ≥2 selected
        # faces) and the unit displacement. When a run dominates, the offset
        # follows it straight (transverse faces conform); `dominant_by_pos`
        # records the run so the panel mover can tell which faces are
        # subordinate there and keep their own offset (avoiding the bowtie).
        unit_disp_by_pos = {}
        dominant_by_pos  = {}
        pos_to_sel_normals.each do |k, sel|
          base     = Geom::Point3d.new(k[0], k[1], k[2])
          dominant = parallel_clusters_with_counts(sel).select { |c| c[:count] >= 2 }.map { |c| c[:rep] }
          dominant_by_pos[k] = dominant unless dominant.empty?
          ns   = dominant.empty? ? (sel + (pos_to_ctx_normals[k] || [])) : dominant
          top1 = compute_offset_vertex(base, ns, 1.0)
          unit_disp_by_pos[k] = Geom::Vector3d.new(top1.x - base.x, top1.y - base.y, top1.z - base.z)
        end

        # Edge (by position pair) → group indices that contain it as an
        # outer-loop edge. Two groups sharing a position-pair = a seam,
        # regardless of whether their Edge objects are actually the same.
        edge_to_groups = {}
        edge_to_faces  = {}
        surfaces.each_with_index do |sf, gi|
          sf.each do |f|
            f.outer_loop.edges.each do |e|
              k = edge_pos_key(e.start.position, e.end.position)
              (edge_to_groups[k] ||= {})[gi] = true
              (edge_to_faces[k]  ||= {})[gi] = f
            end
          end
        end

        shared_edge_pos     = {}
        shared_edge_hard    = {}
        shared_edge_normals = {}
        cos_threshold       = 0.5
        edge_to_groups.each do |k, gset|
          next if gset.size < 2
          shared_edge_pos[k] = true
          gis = gset.keys
          shared_edge_normals[k] = gis.map { |gi| edge_to_faces[k][gi].normal }
          n1 = edge_to_faces[k][gis[0]].normal
          n2 = edge_to_faces[k][gis[1]].normal
          cos_a = n1.dot(n2)
          cos_a =  1.0 if cos_a >  1.0
          cos_a = -1.0 if cos_a < -1.0
          shared_edge_hard[k] = true if cos_a < cos_threshold
        end

        { unit_disp_by_pos: unit_disp_by_pos, dominant_by_pos: dominant_by_pos,
          miter_disp: compute_wall_miter_disp(surfaces),
          miter_disp_inv: compute_wall_miter_disp(surfaces, true),
          shared_edge_pos: shared_edge_pos, shared_edge_hard: shared_edge_hard,
          shared_edge_normals: shared_edge_normals }
      end

      WALL_NORMAL_Z_TOL = 0.01

      def norm_key(n)
        [n.x.round(4), n.y.round(4), n.z.round(4)]
      end

      # Per-wall miter displacements (unit, at height 1) for *consistent
      # thickness*. Every vertical wall offsets exactly h perpendicular
      # (pushpull already does); at a shared plan vertex a wall's offset corner
      # slides ALONG its own offset line to meet the offset line of its nearest
      # angular neighbour on the offset side. Because the corner stays on the
      # wall's own offset line (perpendicular distance h), thickness is h by
      # construction — unlike one shared equidistant vertex, which can't sit at
      # distance h from 3+ non-coplanar walls at once. Keyed by [plan, normal]
      # (per wall, not shared). Returns {} when the selection isn't wall-like
      # (vertical, rectangular footprint), so callers fall back to the
      # equidistant map. This also subsumes the run/partition logic: collinear
      # walls give parallel offset lines → straight (no chamfer), and a
      # partition's corner lands on the run's offset line → flush.
      # `flip` computes the inverted-extrusion map: every wall thickens toward
      # −n (it extrudes the other way), so the miter geometry runs with negated
      # normals and the resulting displacement is negated back into the
      # base + h·disp convention (move_panel multiplies by the negative h).
      def compute_wall_miter_disp(surfaces, flip = false)
        at = Hash.new { |h, k| h[k] = [] }
        surfaces.each do |sf|
          sf.each do |f|
            n = f.normal
            return {} unless n.z.abs < WALL_NORMAL_Z_TOL
            noff = flip ? Geom::Vector3d.new(-n.x, -n.y, -n.z) : n
            ordered = ordered_footprint(f)   # plan points along the wall (incl. mids)
            next if ordered.size < 2
            ordered.each_with_index do |vtx, i|
              # A vertex with a neighbour on each side is a pass-through (the
              # wall runs straight through a junction sitting mid-span); one
              # neighbour means it's a wall end that gets mitered.
              nbrs = []
              nbrs << ordered[i - 1] if i > 0
              nbrs << ordered[i + 1] if i < ordered.size - 1
              is_end = nbrs.size == 1
              nbrs.each do |op|
                dir = Geom::Vector3d.new(op.x - vtx.x, op.y - vtx.y, 0)
                next if dir.length < 1.0e-9
                dir.normalize!
                at[[vtx.x.round(POS_KEY_DECIMALS), vtx.y.round(POS_KEY_DECIMALS)]] <<
                  { n: noff, kn: n, dir: dir, vtx: vtx, is_end: is_end }
              end
            end
          end
        end

        result = {}
        at.each do |pk, rays|
          rays.each do |w|
            if w[:is_end]
              c  = wall_miter_corner(w, rays)
              dx = c.x - w[:vtx].x; dy = c.y - w[:vtx].y
            else
              dx = w[:n].x; dy = w[:n].y   # pass-through: straight offset
            end
            if flip
              dx = -dx; dy = -dy
            end
            result[[pk, norm_key(w[:kn])]] = Geom::Vector3d.new(dx, dy, 0)
          end
        end
        result
      end

      # Plan-projected footprint vertices of a (vertical) wall face, deduped
      # and ordered along the wall's length — so collinear mid-vertices (a
      # redundant point, or a junction sitting mid-span) are kept in order
      # rather than tripping the rectangular-footprint assumption.
      def ordered_footprint(face)
        seen = {}
        uniq = []
        face.outer_loop.vertices.each do |v|
          p = v.position
          k = [p.x.round(POS_KEY_DECIMALS), p.y.round(POS_KEY_DECIMALS)]
          next if seen[k]
          seen[k] = true
          uniq << Geom::Point3d.new(p.x, p.y, 0)
        end
        return uniq if uniq.size < 2
        a    = uniq.first
        far  = uniq.max_by { |p| (p - a).length }
        axis = far - a
        return uniq if axis.length < 1.0e-9
        axis.normalize!
        uniq.sort_by { |p| (p - a).dot(axis) }
      end

      # Mitered offset corner (unit height) for wall `w` among coincident
      # `walls`: intersect w's offset line with the offset line of its nearest
      # angular neighbour swept from w's direction toward its +normal side.
      # Falls back to a straight offset (V + n) when there's no usable
      # neighbour or the offset lines are parallel (collinear run).
      def wall_miter_corner(w, walls)
        v = w[:vtx]; n = w[:n]; d = w[:dir]
        straight = Geom::Point3d.new(v.x + n.x, v.y + n.y, 0)

        # A collinear run continuation — another wall with the same normal
        # sharing this vertex — keeps the wall straight: the run passes through
        # and a transverse wall miters against IT, not the other way round.
        # Without this the angular sweep can latch onto a transverse neighbour
        # (the sweep direction flips when inverted, negating the normals) and
        # bend a straight run into an angled face.
        return straight if walls.any? { |x| !x.equal?(w) && x[:n].dot(n) > PARALLEL_NORMAL_COS_THRESHOLD }

        ccw = (d.x * n.y - d.y * n.x) > 0   # is n 90° CCW from d?
        best = nil; best_ang = nil
        walls.each do |x|
          next if x.equal?(w)
          dx = x[:dir]
          ang = Math.atan2(d.x * dx.y - d.y * dx.x, d.x * dx.x + d.y * dx.y)
          a = (ccw ? ang : -ang) % (2 * Math::PI)
          next if a < 1.0e-6 || a > 2 * Math::PI - 1.0e-6
          if best_ang.nil? || a < best_ang
            best_ang = a; best = x
          end
        end
        return straight unless best

        # Bisector of the sector between this wall and its neighbour (in the
        # sweep direction). If the neighbour thickens INTO that sector its
        # offset edge bounds it → miter against the neighbour's offset line;
        # otherwise the neighbour only contributes its footprint, so our offset
        # edge butts the neighbour's base line. Using the wrong one is what made
        # 3+ walls overlap.
        half = (ccw ? best_ang : -best_ang) / 2.0
        ch = Math.cos(half); sh = Math.sin(half)
        ux = d.x * ch - d.y * sh
        uy = d.x * sh + d.y * ch
        nb = best[:n]
        thickens_in = (ux * nb.x + uy * nb.y) > 0

        pi = Geom::Point3d.new(v.x + n.x, v.y + n.y, 0)
        pj = thickens_in ? Geom::Point3d.new(v.x + nb.x, v.y + nb.y, 0) : v
        dj = best[:dir]
        det = dj.x * d.y - d.x * dj.y
        return straight if det.abs < 1.0e-9
        s = (-(pj.x - pi.x) * dj.y + dj.x * (pj.y - pi.y)) / det
        Geom::Point3d.new(pi.x + s * d.x, pi.y + s * d.y, 0)
      end

      # Rounded position key — vertices on coincident geometry can have
      # float coordinates that differ by epsilon (e.g., two SketchUp groups
      # built independently sometimes produce 1.0 vs 1.0000000000001).
      # 6 decimals comfortably exceeds SketchUp's 1/1000-inch precision
      # while still collapsing those near-duplicates onto the same key.
      POS_KEY_DECIMALS = 6

      def pos_key(p)
        [p.x.round(POS_KEY_DECIMALS), p.y.round(POS_KEY_DECIMALS), p.z.round(POS_KEY_DECIMALS)]
      end

      def edge_pos_key(p1, p2)
        a = pos_key(p1)
        b = pos_key(p2)
        (a <=> b) <= 0 ? [a, b] : [b, a]
      end

      # In-memory perimeter simplification. For each face, returns the
      # indices of its outer-loop vertices that should drive the wall and
      # top construction. A vertex is dropped when both of its incident
      # outer-loop edges are perimeter edges of the group (no neighbouring
      # in-group face on the other side) and the two edges are collinear.
      # The dropped vertex becomes a welded mid-point on the new long
      # wall, leaving the source mesh untouched while the resulting shell
      # has no spurious verticals/top subdivisions at colinear bumps.
      #
      # When `simplify` is false, every face returns its full index range
      # so callers can rely on the same shape regardless of the setting.
      def compute_active_outer_loop_indices(faces, edge_faces, simplify)
        result = {}
        faces.each do |face|
          verts = face.outer_loop.vertices
          edges = face.outer_loop.edges
          n     = verts.length
          if !simplify || n < 3
            result[face] = (0...n).to_a
            next
          end
          keep = Array.new(n, true)
          n.times do |i|
            e_prev = edges[(i - 1) % n]   # edge ending at verts[i]
            e_next = edges[i]             # edge starting at verts[i]
            next unless edge_faces[e_prev] && edge_faces[e_next]
            next unless edge_faces[e_prev].size == 1 && edge_faces[e_next].size == 1
            next unless e_prev.line[1].parallel?(e_next.line[1])
            keep[i] = false
          end
          active = (0...n).select { |i| keep[i] }
          result[face] = active.empty? ? (0...n).to_a : active
        end
        result
      end

      # Flood-fill `faces` through soft edges only. Faces not in the input
      # selection are never crossed, so adjacent unselected geometry doesn't
      # leak into a surface group.
      def group_faces_by_soft_connectivity(faces)
        face_set = faces.to_set
        visited  = {}
        groups   = []
        faces.each do |start|
          next if visited[start]
          stack = [start]
          group = []
          until stack.empty?
            f = stack.pop
            next if visited[f]
            visited[f] = true
            group << f
            f.edges.each do |edge|
              next unless edge.soft?
              edge.faces.each do |adj|
                next unless face_set.include?(adj)
                next if visited[adj]
                stack << adj
              end
            end
          end
          groups << group
        end
        groups
      end

      # Mode-aware dispatch. :face pushpulls each group's face along its
      # normal; :surface keeps soft-edge-connected faces welded as one body.
      def xtrd_groups(groups, height)
        case @mode
        when :face    then xtrd_groups_per_face(groups, height)
        when :surface then xtrd_groups_per_surface(groups, height)
        end
      end

      def xtrd_groups_per_face(groups, height)
        default_layer = Sketchup.active_model.layers[0]
        align         = CONFIG[:align_to_min_bb]

        groups.each do |group|
          entities = group.entities.to_a
          faces    = entities.grep(Sketchup::Face)

          faces.each                         { |f| f.layer = default_layer }
          entities.grep(Sketchup::Edge).each { |e| e.layer = default_layer }

          next unless faces.first

          # Drop collinear outer-loop vertices before pushpulling — same
          # intent as in SurfaceUp, but here the rebuild happens inside the
          # per-face group so the user's source mesh stays untouched.
          rebuilt = simplify_outer_loop_in_group(group, faces.first)
          faces = group.entities.grep(Sketchup::Face) if rebuilt
          next unless faces.first

          # The profile normal (before pushpull) is the extrusion axis.
          normal = faces.first.normal
          if @coord_unit_disp_by_pos
            # Coordinated mode: cap the panel where its mitered top would fold
            # through itself (matching the preview), pushpull, then slide the
            # top vertices to the shared equidistant position so neighbouring
            # panels meet flush. Independent mode just pushpulls a straight
            # prism, which can never self-intersect, so it skips the cap.
            h = clamp_coordinated_panel_height(group, faces.first, height)
            holes = capture_panel_holes(faces.first)   # before pushpull
            faces.first.pushpull(h)
            move_panel_top_to_coordinated(group, normal, h)
            # The hole top is lifted straight by pushpull, which is what we want
            # for a normal extrusion (it stays a clean perpendicular shaft in the
            # offset plane). ONLY when the panel was capped at a self-intersecting
            # converging tip do we taper the holes toward the collapsing outer —
            # otherwise scaling them toward the outer centroid drags them out of
            # the panel (a self-intersecting protrusion).
            converging = h.to_f.abs < height.to_f.abs - 1.0e-6
            scale_panel_holes(group, normal, h, holes) if holes && converging
          elsif @both_sides
            # Symmetric solid: extrude the full thickness, then slide the body
            # back by half so it straddles the face plane (−h/2 … +h/2). The
            # original face plane ends up internal (no face there), centred.
            total = height.abs
            faces.first.pushpull(total)
            half  = total / 2.0
            shift = Geom::Transformation.translation(
              Geom::Vector3d.new(-half * normal.x, -half * normal.y, -half * normal.z))
            group.entities.transform_entities(shift, group.entities.to_a)
          else
            faces.first.pushpull(height)
          end
          apply_min_bb_alignment(group, normal) if align
        end
      end

      # Snapshot a panel's hole loops (and its outer ring) before pushpull, in
      # the group's local frame, for the post-pushpull hole scaling.
      def capture_panel_holes(face)
        return nil if face.loops.size < 2
        {
          outer:  face.outer_loop.vertices.map(&:position),
          holes:  face.loops.reject(&:outer?).map { |lp| lp.vertices.map(&:position) },
        }
      end

      # Scale each hole's lifted top toward its centre by the factor the
      # coordinated outer contour shrinks (top spread / bottom spread), so the
      # hole tapers together with the panel. s < 1 inward (block narrows), s > 1
      # outward. The lifted hole verts sit at bottom + h·normal after pushpull;
      # we slide them in-plane to the scaled position.
      def scale_panel_holes(group, normal, height, data)
        xform     = group.transformation
        xform_inv = xform.inverse
        inverted  = height.to_f < 0
        fn_world  = normal.transform(xform)
        ob = data[:outer]
        cb = average_position(ob)
        ot = ob.map do |p|
          # Use the SAME displacement move_panel_top_to_coordinated applied to
          # the outer top (miter / subordinate / equidistant) — NOT the raw
          # equidistant @coord_unit_disp_by_pos. When the outer is subordinate
          # (its vertices dominated by a neighbour), the two diverge: the outer
          # stays put while the raw equidistant would contract, so `s` reflected
          # a contraction that never happened and the holes were dragged off the
          # panel (poking out as a self-intersecting protrusion).
          ctx = coordinated_disp_for(pos_key(p.transform(xform)), fn_world, inverted)
          d   = ctx ? ctx.transform(xform_inv) : normal
          p.offset(d, height)
        end
        ct  = average_position(ot)
        den = ob.reduce(0.0) { |a, p| a + p.distance(cb) }
        return if den < 1.0e-9
        s = ot.reduce(0.0) { |a, p| a + p.distance(ct) } / den

        # Scale the holes toward the OUTER top centroid `ct` (the panel's
        # convergence point), not each hole's own centre, by the outer's
        # contraction `s`. That way as the block narrows inward the holes
        # converge toward the same apex the outer does — at the cap everything
        # meets at one point instead of the hole shaft poking through the
        # collapsing outer.
        all = group.entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq
        data[:holes].each do |hole_bottom|
          tops = hole_bottom.map { |p| all.find { |v| v.position == p.offset(normal, height) } }.compact
          next if tops.length < 2
          targets = []
          vectors = []
          tops.each do |v|
            p  = v.position
            np = Geom::Point3d.new(ct.x + s * (p.x - ct.x), ct.y + s * (p.y - ct.y), ct.z + s * (p.z - ct.z))
            targets << v
            vectors << (np - p)
          end
          group.entities.transform_by_vectors(targets, vectors)
        end
      end

      def average_position(pts)
        n = pts.length.to_f
        sx = pts.inject(0.0) { |a, p| a + p.x }
        sy = pts.inject(0.0) { |a, p| a + p.y }
        sz = pts.inject(0.0) { |a, p| a + p.z }
        Geom::Point3d.new(sx / n, sy / n, sz / n)
      end

      # Stop a coordinated panel a hair short of the exact self-intersection,
      # so the converging outer (and the holes converging with it) end in a
      # thin clean tip instead of an exactly-degenerate point. SurfaceUp can
      # weld that point through add_face dedup; FaceUp's pushpull+move can't.
      COORD_FACE_CAP_SAFETY = 0.97

      # Clamp a coordinated panel's pushpull to its self-intersection depth,
      # the same per-panel cap the surface-style preview applies, so what gets
      # built matches what the cursor showed.
      def clamp_coordinated_panel_height(group, face, height)
        unit_disp  = panel_coordinated_unit_disp(group, face, height.to_f < 0)
        edge_faces = Hash.new { |h, k| h[k] = [] }
        face.edges.each { |e| edge_faces[e] << face }
        active = compute_active_outer_loop_indices([face], edge_faces, true)
        capped = clamp_height_to_avoid_flip([face], active, unit_disp, height)
        capped == height ? capped : (capped * COORD_FACE_CAP_SAFETY).to_l
      end

      # Per-vertex coordinated unit displacement for a panel's bottom face, in
      # the panel's local frame (looked up by world position so it agrees with
      # neighbouring panels). Falls back to the face normal for any vertex not
      # in the coordinated map.
      def panel_coordinated_unit_disp(group, face, inverted)
        xform     = group.transformation
        xform_inv = xform.inverse
        fn_world  = face.normal.transform(xform)
        disp = {}
        face.vertices.each do |v|
          unit_ctx = coordinated_disp_for(pos_key(v.position.transform(xform)), fn_world, inverted)
          disp[v]  = unit_ctx ? unit_ctx.transform(xform_inv) : face.normal
        end
        disp
      end

      # In coordinated face mode each panel is pushpulled (which keeps holes
      # and topology), then its top vertices are slid — within the parallel
      # offset plane, so the top stays planar — to the shared equidistant
      # position. Only top vertices whose base sits on a coordinated position
      # move; the rest, and panels with no selected neighbour, stay where
      # pushpull put them. Neighbouring panels resolve a shared vertex to the
      # same world point, so their walls coincide and the panels meet flush.
      def move_panel_top_to_coordinated(group, normal, height)
        xform     = group.transformation
        xform_inv = xform.inverse
        fn_world  = normal.transform(xform)
        inverted  = height.to_f < 0
        # Longitudinal axis of the (vertical) panel — perpendicular to its
        # normal in plan — along which a subordinate base end is trimmed.
        long_world = Geom::Vector3d.new(-fn_world.y, fn_world.x, 0.0)
        verts     = group.entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq
        targets   = []
        vectors   = []
        verts.each do |v|
          base     = v.position.offset(normal, -height)   # bottom counterpart (panel-local)
          unit_ctx = coordinated_disp_for(pos_key(base.transform(xform)), fn_world, inverted)
          if unit_ctx
            unit_local = unit_ctx.transform(xform_inv)
            top = Geom::Point3d.new(base.x + height * unit_local.x,
                                    base.y + height * unit_local.y,
                                    base.z + height * unit_local.z)
            vec = Geom::Vector3d.new(top.x - v.position.x, top.y - v.position.y, top.z - v.position.z)
            next if vec.length < 1.0e-9
            targets << v
            vectors << vec
          elsif inverted
            # Base (bottom) vertex of a subordinate panel: slide it along the
            # panel's length into the neighbour run's offset plane, so its end
            # cap lands flush there (matching the trimmed offset side) instead
            # of staying at the original line and slanting across the run.
            shift = subordinate_base_shift(v.position.transform(xform), fn_world, long_world, height)
            next unless shift
            targets << v
            vectors << shift.transform(xform_inv)
          end
        end
        group.entities.transform_by_vectors(targets, vectors) unless targets.empty?
      end

      # Per-unit version of subordinate_base_shift for the preview: the base
      # slide as a unit vector (per unit of extrusion distance), so the cache
      # stays distance-independent. nil when the vertex isn't subordinate.
      # bottom = vert_pos + dist * this; at dist = h it equals the executor's
      # subordinate_base_shift (s·long, s = h/(long·nD)).
      def preview_base_disp(world_pos, fn, coord)
        dom = coord[:dominant_by_pos] && coord[:dominant_by_pos][pos_key(world_pos)]
        return nil unless dom && dom.any?
        return nil if dom.any? { |dn| dn.parallel?(fn) }
        nd   = dom.first
        long = Geom::Vector3d.new(-fn.y, fn.x, 0.0)
        den  = long.dot(nd)
        return nil if den.abs < 1.0e-9
        Geom::Vector3d.new(long.x / den, long.y / den, 0.0)
      end

      # World shift sliding a subordinate panel's base vertex along the panel's
      # length `long` into the dominant run's offset plane (through V + h·nD,
      # normal nD), or nil if the vertex isn't subordinate. s = h / (long·nD).
      def subordinate_base_shift(world_pos, fn_world, long, height)
        dom = @coord_dominant_by_pos && @coord_dominant_by_pos[pos_key(world_pos)]
        return nil unless dom && dom.any?
        return nil if dom.any? { |dn| dn.parallel?(fn_world) }
        nd  = dom.first
        den = long.dot(nd)
        return nil if den.abs < 1.0e-9
        s = height / den
        Geom::Vector3d.new(s * long.x, s * long.y, s * long.z)
      end

      # In-group perimeter cleanup for face mode. Drops outer-loop
      # vertices whose two incident edges are collinear, then rebuilds
      # the face from the kept positions. Skips faces with inner loops
      # — preserving holes through a full erase/recreate is more work
      # than it's worth here and the user can still simplify by hand.
      # Returns true when the face was rebuilt, false otherwise.
      def simplify_outer_loop_in_group(group, face)
        return false if face.loops.size > 1
        verts = face.outer_loop.vertices
        edges = face.outer_loop.edges
        kept  = simplifiable_kept_indices(verts, edges)
        return false if kept.length == verts.length

        kept_pts = kept.map { |i| verts[i].position }
        return false if kept_pts.size < 3

        original_normal = face.normal
        ents = group.entities
        ents.erase_entities([face, *face.outer_loop.edges])

        new_face = ents.add_face(kept_pts)
        return false unless new_face
        new_face.reverse! if new_face.normal.dot(original_normal) < 0
        true
      end

      # Indices of outer-loop vertices to retain when collapsing runs of
      # collinear edges. A vertex sandwiched between two parallel outer
      # edges sits on the straight run; we drop it. Triangles (n < 4)
      # have nothing to collapse; if every vertex would be dropped (a
      # full straight loop, which shouldn't happen) we bail out with the
      # full index range.
      def simplifiable_kept_indices(verts, edges)
        n = verts.length
        return (0...n).to_a if n < 4
        keep = Array.new(n, true)
        n.times do |i|
          e_prev = edges[(i - 1) % n]
          e_next = edges[i]
          keep[i] = false if e_prev.line[1].parallel?(e_next.line[1])
        end
        kept = (0...n).select { |i| keep[i] }
        kept.size < 3 ? (0...n).to_a : kept
      end

      # Welded extrusion. Each face is lifted along its own normal, but
      # adjacent faces (connected by a soft edge inside the same surface
      # group) share the lifted vertices when they're coplanar — no internal
      # walls — and are stitched by a ridge quad when they aren't. Boundary
      # edges (only one adjacent face inside the group) carry a wall.
      def xtrd_groups_per_surface(groups, height)
        default_layer = Sketchup.active_model.layers[0]
        align         = CONFIG[:align_to_min_bb]

        groups.each do |group|
          extrude_surface(group, height)

          # Stamp the group as a SurfaceUp product so a later re-extrusion of
          # its interior is detected and skips external context.
          group.set_attribute(SURFACE_ATTR_DICT, SURFACE_ATTR_IS_GROUP, true)

          group.entities.grep(Sketchup::Face).each { |f| f.layer = default_layer }
          group.entities.grep(Sketchup::Edge).each { |e| e.layer = default_layer }

          if align
            rep = group.entities.grep(Sketchup::Face).max_by(&:area)
            apply_min_bb_alignment(group, rep.normal) if rep
          end
        end
      end

      def extrude_surface(group, height)
        ents  = group.entities
        faces = ents.grep(Sketchup::Face).to_a
        return if faces.empty?

        # `add_group` shifts geometry into the group's local frame, so
        # vertex positions inside `ents` are local. The coordinated maps
        # are keyed in world coordinates; we convert local→world for
        # lookup and back to local when emitting V_top.
        xform     = group.transformation
        xform_inv = xform.inverse

        # Tag every original surface face with its current (pre-extrusion)
        # normal so a future extrusion of an adjacent surface can find it
        # and coordinate. Two reasons for doing it now:
        #
        # 1. SketchUp re-fits the face plane when new edges connect to its
        #    vertices, which can shift `f.normal` afterwards.
        # 2. `apply_min_bb_alignment` later rotates the group's local axes,
        #    so a stored *local* normal would no longer round-trip through
        #    the group's transformation. We store the *world* normal so the
        #    lookup can use it directly.
        faces.each do |f|
          n_world = f.normal.transform(xform)
          f.set_attribute(SURFACE_ATTR_DICT, SURFACE_ATTR_NORMAL, [n_world.x, n_world.y, n_world.z])
        end

        # Adjacency maps inside the surface group.
        vertex_faces = Hash.new { |h, k| h[k] = [] }
        edge_faces   = Hash.new { |h, k| h[k] = [] }
        faces.each do |face|
          face.vertices.each { |v| vertex_faces[v] << face }
          face.edges.each    { |e| edge_faces[e]   << face }
        end

        # Unit displacement per vertex. In coordinated mode the direction
        # comes from the global precomputed map (so vertices shared
        # between adjacent surface groups land at the same point);
        # otherwise it's the local LSQ over this group's own faces.
        vertex_unit_disp = {}
        vertex_faces.each do |vertex, vfaces|
          p = vertex.position
          if @coord_unit_disp_by_pos
            disp_world = @coord_unit_disp_by_pos[pos_key(p.transform(xform))]
          else
            disp_world = nil
          end
          vertex_unit_disp[vertex] = if disp_world
            disp_world.transform(xform_inv)
          else
            top1 = compute_offset_vertex(p, vfaces.map(&:normal), 1.0)
            Geom::Vector3d.new(top1.x - p.x, top1.y - p.y, top1.z - p.z)
          end
        end

        # Drop collinear outer-loop vertices up front. They are redundant for
        # the offset and, if kept, make the flip clamp bind on a spurious
        # sub-edge — a straight wall with a mid-vertex would otherwise limit
        # the whole extrusion far too early. The same simplified loop drives
        # both the clamp and the wall/top construction below. SketchUp
        # auto-welds the dropped vertices onto the new walls, so manifolding
        # still holds.
        active_indices = compute_active_outer_loop_indices(faces, edge_faces, true)

        # Cap the inward extrusion where the equidistant offset starts to
        # self-intersect. A concave corner's two offset edges cross at a
        # finite depth; past it the shell folds through itself, so we stop
        # there (the corner welds into a sharp miter). Convex corners never
        # self-intersect, so they spike out unclamped.
        height = clamp_height_to_avoid_flip(faces, active_indices, vertex_unit_disp, height)

        vertex_top = {}
        vertex_unit_disp.each do |vertex, d|
          p = vertex.position
          vertex_top[vertex] = Geom::Point3d.new(p.x + height * d.x, p.y + height * d.y, p.z + height * d.z)
        end

        # Lift each face. Vertex order follows the bottom face's outer loop
        # so the natural normal matches; reverse! guards against SketchUp
        # flipping when the new face neighbours already-built geometry.
        faces.each do |face|
          verts = face.outer_loop.vertices
          idx   = active_indices[face]
          pts   = idx.map { |i| vertex_top[verts[i]] }
          hole_loops = face.loops.reject(&:outer?).map do |lp|
            lp.vertices.map { |v| vertex_top[v] }
          end
          add_top_face(ents, face, pts, height, hole_loops)
        end

        # Build walls on every boundary edge of the group — including
        # shared seams with adjacent coordinated groups. Each group's
        # boundary (its full perimeter, seams included) counts as the
        # contour of one of "the two surfaces" the user wants hard.
        boundary_seen  = {}
        boundary_edges = []
        faces.each do |face|
          verts = face.outer_loop.vertices
          idx   = active_indices[face]
          n     = idx.length
          n.times do |k|
            v1 = verts[idx[k]]
            v2 = verts[idx[(k + 1) % n]]
            edge = v1.common_edge(v2)

            if edge
              next unless edge_faces[edge].size == 1
              add_boundary_wall_for(ents, face, v1, v2, vertex_top, xform)
              next if boundary_seen[edge]
              boundary_seen[edge] = true
              boundary_edges << [edge, vertex_top[v1], vertex_top[v2]]
            else
              # Simplified span: no direct Edge object between v1 and v2.
              # Build the wall on the long span anyway — SketchUp welds
              # the intermediate source vertices into the new wall face's
              # outer loop so the bottom face stays manifold.
              add_boundary_wall_for(ents, face, v1, v2, vertex_top, xform)
            end
          end
        end

        # Walls on inner-loop (hole) edges too, so each hole becomes a real
        # through-hole with its own wall instead of a pocket capped by the
        # top. Inner-loop vertices follow the loop's own winding (opposite
        # the outer loop), so the wall ends up facing into the hole.
        faces.each do |face|
          face.loops.each do |loop|
            next if loop.outer?
            lv = loop.vertices
            n  = lv.length
            n.times do |k|
              v1 = lv[k]
              v2 = lv[(k + 1) % n]
              edge = v1.common_edge(v2)
              next unless edge && edge_faces[edge].size == 1
              add_boundary_wall_for(ents, face, v1, v2, vertex_top, xform)
              next if boundary_seen[edge]
              boundary_seen[edge] = true
              boundary_edges << [edge, vertex_top[v1], vertex_top[v2]]
            end
          end
        end

        # If the source carries QuadFaceTools divider edges, propagate
        # each one to its top counterpart so the lifted skin keeps the
        # same quad pairing the user had in the source.
        faces.each do |face|
          face.edges.each do |e|
            next unless e.soft? && e.smooth? && !e.casts_shadows?
            top_edge = find_edge_between(ents, vertex_top[e.start], vertex_top[e.end])
            mark_quad_divider(top_edge) if top_edge
          end
        end

        classify_shell_edges(ents, faces, boundary_edges)

        # For h > 0 the input faces' fronts now face into the shell (the
        # extrusion ran in their normal direction), so we flip them so the
        # bottom skin points outward. For h < 0 the shell sits on the
        # other side; the original orientation is already outward, so we
        # leave them alone.
        faces.each(&:reverse!) if height >= 0
      end

      SURFACE_ATTR_DICT     = 'asm_faceup_surface'.freeze
      SURFACE_ATTR_NORMAL   = 'original_normal'.freeze
      # Marker set on every group SurfaceUp creates. Its presence on the
      # active edit context means we're re-extruding the interior of a
      # finished SurfaceUp shell — see `extruding_surface_group_interior?`.
      SURFACE_ATTR_IS_GROUP = 'is_surface_group'.freeze

      # True when the tool is operating *inside* a group/component that
      # SurfaceUp itself produced (the open instance carries the surface
      # dictionary). That's the "second extrusion" case: the interior must
      # ignore external context. Extruding a fresh face from outside the
      # group leaves a different (unmarked) edit context, so it returns false
      # there and normal coordination still applies.
      def extruding_surface_group_interior?
        path = Sketchup.active_model.active_path
        ctx  = path && path.last
        return false unless ctx
        !ctx.attribute_dictionary(SURFACE_ATTR_DICT).nil?
      end

      # Fraction of an edge's original length below which it counts as
      # self-intersecting at its shortest point. A merely rotating edge
      # (a convex corner spiking outward) keeps its length and is left free.
      COLLAPSE_TOL_SQ = 0.05 * 0.05

      # Cap the extrusion height where the equidistant offset first
      # self-intersects. For each active (collinear-simplified) outer-loop
      # edge, h_min is the height where its top counterpart is shortest; if it
      # shrinks to a near-zero sliver there — a concave corner's offset edges
      # folding through each other — travel must stop at h_min so the corner
      # welds to a sharp miter instead of crossing itself. Edges that only
      # rotate/stretch (convex spikes) never trigger and grow freely; a
      # uniform closed surface (sphere) collapses every edge at the same
      # h_min, so inward inversion is still caught. Returns the requested
      # height when nothing self-intersects in the travel direction.
      def clamp_height_to_avoid_flip(faces, active_indices, vertex_unit_disp, height)
        return height if height.zero?
        hsign = height <=> 0
        safe  = height
        faces.each do |face|
          verts = face.outer_loop.vertices
          idx   = active_indices[face]
          n     = idx.length
          n.times do |k|
            v1 = verts[idx[k]]
            v2 = verts[idx[(k + 1) % n]]
            d1 = vertex_unit_disp[v1]
            d2 = vertex_unit_disp[v2]
            next unless d1 && d2
            edge_vec    = v2.position - v1.position
            edge_len_sq = edge_vec.dot(edge_vec)
            next if edge_len_sq < 1.0e-12
            diff    = Geom::Vector3d.new(d2.x - d1.x, d2.y - d1.y, d2.z - d1.z)
            diff_sq = diff.dot(diff)
            next if diff_sq < 1.0e-12              # endpoints move together: edge rigid
            dot_diff = diff.dot(edge_vec)
            h_min = -dot_diff / diff_sq            # height where the top edge is shortest
            next if (h_min <=> 0) != hsign         # shortest point lies the other way: edge grows
            len_min_sq = edge_len_sq - (dot_diff * dot_diff) / diff_sq
            next if len_min_sq > edge_len_sq * COLLAPSE_TOL_SQ  # edge only rotates: free to spike
            safe = hsign > 0 ? [safe, h_min].min : [safe, h_min].max
          end
        end
        safe
      end

      # Final pass that decides each edge's soft/smooth state. Two kinds of
      # edges are forced hard:
      #
      #   1. Surface contours — the bottom boundary edges (original) and
      #      their top counterparts. These outline the shell and have to
      #      stay visible no matter what their bottom soft flag said.
      #   2. New non-contour edges whose two adjacent faces bend by more
      #      than 60° (i.e. dot product of unit normals < 0.5). Below the
      #      threshold the kink reads as a smooth crease and we soften it.
      #
      # Original bottom-internal edges are left untouched so the operation
      # doesn't reach into geometry the user didn't ask to extrude.
      def classify_shell_edges(ents, bottom_faces, boundary_edges, shared_seam_edges = [])
        bottom_contour = {}
        top_contour    = {}
        boundary_edges.each do |edge, p1, p2|
          bottom_contour[edge] = true
          top_edge = find_edge_between(ents, p1, p2)
          top_contour[top_edge] = true if top_edge
        end

        # Seams between coordinated surface groups follow the same > 60°
        # rule as other internal edges: a sharp crease stays hard so the
        # angle reads, a smooth join goes soft+smooth so the two groups
        # blend into one shell.
        seam_set = {}
        shared_seam_edges.each do |edge, p1, p2, is_hard|
          edge.soft   = !is_hard
          edge.smooth = !is_hard
          seam_set[edge] = true
          top_edge = find_edge_between(ents, p1, p2)
          if top_edge
            top_edge.soft   = !is_hard
            top_edge.smooth = !is_hard
            seam_set[top_edge] = true
          end
        end

        pre_existing = {}
        bottom_faces.each { |f| f.edges.each { |e| pre_existing[e] = true } }

        cos_threshold = 0.5  # cos(60°)

        ents.grep(Sketchup::Edge).each do |e|
          next if seam_set[e]
          # Skip edges already tagged as QFT dividers (triangulation
          # diagonals marked at construction time, and top counterparts
          # of source dividers).
          next if e.soft? && e.smooth? && !e.casts_shadows?
          if bottom_contour[e] || top_contour[e]
            e.soft   = false
            e.smooth = false
            next
          end
          next if pre_existing[e]

          fs = e.faces
          next if fs.size != 2

          cos_a = fs[0].normal.dot(fs[1].normal)
          cos_a =  1.0 if cos_a >  1.0
          cos_a = -1.0 if cos_a < -1.0
          smooth_crease = cos_a >= cos_threshold
          e.soft   = smooth_crease
          e.smooth = smooth_crease
          # We deliberately don't touch `casts_shadows` here: a plain
          # soft+smooth edge gives the user smooth shading without
          # tripping QuadFaceTools, which only counts an edge as a quad
          # divider when *all three* properties (soft + smooth +
          # !casts_shadows) hold. Dividers are set by `mark_quad_divider`
          # at creation time and skipped above.
        end
      end

      # Position of a bottom vertex on the lifted surface. V_top is the
      # point at perpendicular distance `height` from every adjacent
      # face's plane — strict equidistance. For each face we get the
      # constraint n_i · (V_top − V_orig) = h; solving this overdetermined
      # system in the least-squares sense gives
      #     (MᵀM) w = h · Σ n_i,
      # where w = V_top − V_orig and M is the matrix of unit normals.
      # For N=2 (non-collinear normals) the closed-form bisector solution
      # is exact: V_top = V_orig + (h/(1+cos θ))·(n₁+n₂). When the system
      # is singular (all normals coplanar, or anti-parallel pair) we fall
      # back to extruding along the averaged direction.
      def compute_offset_vertex(position, normals, height)
        return position if normals.empty?
        return position.offset(normals.first, height) if normals.size == 1

        # Merge near-parallel normals so a fan triangulation of one planar
        # region doesn't show up as N redundant constraints (which makes
        # MᵀM rank-deficient and biases the LSQ residual).
        normals = dedupe_parallel_normals(normals)
        return position.offset(normals.first, height) if normals.size == 1

        if normals.size == 2
          n1, n2 = normals
          cos_t  = n1.dot(n2)
          # Anti-parallel: planes coincide on opposite sides; the bisector
          # direction is undefined. Pick either normal.
          return position.offset(n1, height) if (1.0 + cos_t).abs < 1e-9
          t = height.to_f / (1.0 + cos_t)
          return Geom::Point3d.new(
            position.x + t * (n1.x + n2.x),
            position.y + t * (n1.y + n2.y),
            position.z + t * (n1.z + n2.z),
          )
        end

        # N ≥ 3: build the 3×3 normal-equation system (MᵀM) w = h · Σ n_i
        # and solve by Cramer. b_i = h here (offset distance) because we
        # solve for the displacement w = V_top − V_orig directly, not for
        # V_top in world coordinates.
        a = Array.new(3) { Array.new(3, 0.0) }
        sum_n = [0.0, 0.0, 0.0]
        normals.each do |n|
          nv = [n.x.to_f, n.y.to_f, n.z.to_f]
          3.times do |j|
            sum_n[j] += nv[j]
            3.times { |k| a[j][k] += nv[j] * nv[k] }
          end
        end
        c = sum_n.map { |s| s * height.to_f }

        w = solve_3x3(a, c)
        if w
          return Geom::Point3d.new(position.x + w.x, position.y + w.y, position.z + w.z)
        end

        # Singular system — every normal lies in a common plane (or the
        # set degenerates). Fall back to the averaged-direction extrusion
        # so we still produce something usable along the dominant axis.
        sum_x, sum_y, sum_z = sum_n
        sum_len = Math.sqrt(sum_x * sum_x + sum_y * sum_y + sum_z * sum_z)
        return position.offset(normals.first, height) if sum_len < 1e-6

        position.offset(
          Geom::Vector3d.new(sum_x / sum_len, sum_y / sum_len, sum_z / sum_len),
          height,
        )
      end

      # Solve a 3×3 linear system A·v = b by Cramer's rule. Returns the
      # solution as a Vector3d, or nil if the system is singular within
      # tolerance. The 1e-12 cutoff is comfortable for the well-scaled
      # MᵀM matrices we feed it (unit normals → entries bounded by N).
      def solve_3x3(a, b)
        det = a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) -
              a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0]) +
              a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
        return nil if det.abs < 1e-12

        inv = 1.0 / det
        x = inv * (b[0]  * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) -
                   b[1]  * (a[0][1] * a[2][2] - a[0][2] * a[2][1]) +
                   b[2]  * (a[0][1] * a[1][2] - a[0][2] * a[1][1]))
        y = inv * (-b[0] * (a[1][0] * a[2][2] - a[1][2] * a[2][0]) +
                   b[1]  * (a[0][0] * a[2][2] - a[0][2] * a[2][0]) -
                   b[2]  * (a[0][0] * a[1][2] - a[0][2] * a[1][0]))
        z = inv * (b[0]  * (a[1][0] * a[2][1] - a[1][1] * a[2][0]) -
                   b[1]  * (a[0][0] * a[2][1] - a[0][1] * a[2][0]) +
                   b[2]  * (a[0][0] * a[1][1] - a[0][1] * a[1][0]))
        Geom::Vector3d.new(x, y, z)
      end

      # Cluster near-parallel unit vectors and return one averaged
      # representative per cluster. The 2° threshold (cos ≈ 0.9994)
      # catches fan triangulations of a planar region (which would
      # otherwise show up as redundant constraints and bias MᵀM) without
      # collapsing genuine creases. Averaging — instead of keeping the
      # first normal of each cluster — keeps the LSQ unbiased when one
      # cluster has more entries than another.
      PARALLEL_NORMAL_COS_THRESHOLD = 0.9994

      # The coordinated unit displacement a panel should use at a world
      # position `k`, or nil if the position isn't coordinated. When a coplanar
      # run (≥2 aligned faces) dominates the vertex and this face isn't part of
      # it, the face is subordinate: it gets a displacement that keeps its full
      # thickness yet cuts its end flush into the run's plane (see
      # `subordinate_disp`), instead of following the run's own displacement
      # (which would shear it into a self-intersecting bowtie).
      def coordinated_disp_for(k, face_normal_world, inverted)
        mm = inverted ? @coord_miter_disp_inv : @coord_miter_disp
        if mm
          md = mm[[[k[0], k[1]], norm_key(face_normal_world)]]
          return md if md
        end
        disp = @coord_unit_disp_by_pos[k]
        return nil unless disp
        dom = @coord_dominant_by_pos && @coord_dominant_by_pos[k]
        if dom && dom.any? && dom.none? { |dn| dn.parallel?(face_normal_world) }
          return subordinate_disp(face_normal_world, dom, inverted)
        end
        disp
      end

      # Displacement for a subordinate panel's dominated vertex: one unit off
      # the panel's own plane (`disp·nI = 1`, so the panel keeps full thickness)
      # and flush into the neighbour run's plane. Which run plane: its base
      # (`disp·nD = 0`) for a forward extrusion, or its *offset* plane
      # (`disp·nD = 1`) when inverted — because then the run slides inward by
      # the distance and the panel's end must follow it, or it leaves a
      # distance-sized gap. Solving `disp·nI = 1`, `disp·nD = t` in the nI–nD
      # plane gives a = (1 − t·c)/(1 − c²), b = t − a·c (c = nI·nD).
      def subordinate_disp(face_normal, dominants, inverted)
        nd    = dominants.first
        c     = face_normal.dot(nd)
        denom = 1.0 - c * c
        return face_normal if denom < 1.0e-6
        t = inverted ? 1.0 : 0.0
        a = (1.0 - t * c) / denom
        b = t - a * c
        Geom::Vector3d.new(a * face_normal.x + b * nd.x,
                           a * face_normal.y + b * nd.y,
                           a * face_normal.z + b * nd.z)
      end

      # Cluster near-parallel vectors, counting how many fell into each.
      def parallel_clusters_with_counts(normals)
        clusters = []
        normals.each do |n|
          c = clusters.find { |cl| cl[:rep].dot(n) > PARALLEL_NORMAL_COS_THRESHOLD }
          if c
            c[:count] += 1
          else
            clusters << { rep: n, count: 1 }
          end
        end
        clusters
      end

      def dedupe_parallel_normals(normals)
        clusters = []
        normals.each do |n|
          c = clusters.find { |cl| cl[:rep].dot(n) > PARALLEL_NORMAL_COS_THRESHOLD }
          if c
            c[:list] << n
            sx = c[:list].inject(0.0) { |a, v| a + v.x }
            sy = c[:list].inject(0.0) { |a, v| a + v.y }
            sz = c[:list].inject(0.0) { |a, v| a + v.z }
            mag = Math.sqrt(sx * sx + sy * sy + sz * sz)
            c[:rep] = Geom::Vector3d.new(sx / mag, sy / mag, sz / mag) if mag > 1e-9
          else
            clusters << { rep: n, list: [n] }
          end
        end
        clusters.map { |c| c[:rep] }
      end

      # Build the lifted face on top. When the top vertices stay coplanar
      # (typical for triangles and for quads on a developable surface) it's
      # one polygon; otherwise the LSQ-solved vertex tops won't sit on a
      # single plane, so we fan-triangulate from the first vertex. The new
      # diagonals are left at default state — `classify_shell_edges` runs
      # at the end and tags them based on the dihedral angle.
      def add_top_face(ents, face, pts, height, hole_loops = [])
        # A negative extrusion can pull adjacent V_tops together (the bowl
        # collapses inward), so dedupe consecutive duplicates and bail out
        # if there's no real polygon left.
        pts = dedupe_consecutive_points(pts)
        return if pts.length < 3

        # For h > 0 the top is on the far side of the bottom face's front:
        # we want its normal aligned with `face.normal`. For h < 0 the
        # top sits behind the bottom face, so the top's outward direction
        # is opposite — we want its normal anti-aligned with `face.normal`.
        want_aligned = height >= 0

        orient = lambda do |f|
          aligned = f.normal.dot(face.normal) > 0
          f.reverse! if aligned != want_aligned
        end

        if pts.length == 3 || coplanar?(pts)
          top = ents.add_face(pts)
          return unless top
          # Cut inner loops (holes) out of the planar top: adding the hole
          # ring splits it off `top`, erasing that ring leaves the hole while
          # keeping its edges for the inner walls to meet.
          cut_top_holes(ents, hole_loops)
          orient.call(top) if top.valid?
          return
        end

        last_i = pts.length - 2
        (1..last_i).each do |i|
          tri_pts = [pts[0], pts[i], pts[i + 1]]
          next if tri_pts[0] == tri_pts[1] || tri_pts[1] == tri_pts[2] || tri_pts[0] == tri_pts[2]
          tri = ents.add_face(tri_pts)
          next unless tri
          orient.call(tri)
          # The shared edge with the *next* fan triangle is the diagonal;
          # on the last iteration that edge is actually the polygon's
          # closing perimeter, so we skip it.
          next if i == last_i
          diag = find_edge_between(ents, tri_pts[0], tri_pts[2])
          mark_quad_divider(diag) if diag
        end
      end

      # Cut each hole loop out of a freshly-built planar top face. Adding the
      # hole ring as a face splits it off the top; erasing the ring leaves
      # the top with the hole and keeps the ring edges for the inner walls.
      def cut_top_holes(ents, hole_loops)
        hole_loops.each do |hpts|
          hpts = dedupe_consecutive_points(hpts)
          next if hpts.length < 3
          ring = ents.add_face(hpts)
          ring.erase! if ring && ring.valid?
        end
      end

      def mark_quad_divider(edge)
        return unless edge
        edge.soft           = true
        edge.smooth         = true
        edge.casts_shadows  = false
      end

      def dedupe_consecutive_points(pts)
        return pts if pts.length < 2
        kept = [pts[0]]
        (1...pts.length).each do |i|
          kept << pts[i] unless pts[i] == kept.last
        end
        kept.pop if kept.length > 1 && kept.first == kept.last
        kept
      end

      def coplanar?(pts, tol = 1.0e-6)
        return true if pts.length < 4
        v1 = pts[1] - pts[0]
        v2 = pts[2] - pts[0]
        n  = v1.cross(v2)
        return true if n.length < 1.0e-9
        n.normalize!
        pts[3..-1].all? { |p| (p - pts[0]).dot(n).abs < tol }
      end

      # Wall on a boundary edge with v1 → v2 in the face's CCW winding so
      # outward = (v2 − v1) × face.normal. The quad [v1, v2, top_v2, top_v1]
      # is CCW from outward; reverse! is belt-and-braces in case SketchUp
      # orients it the other way to match existing geometry.
      def add_boundary_wall_for(ents, face, v1, v2, vertex_top, xform = nil)
        bottom_s = v1.position
        bottom_e = v2.position
        top_s    = vertex_top[v1]
        top_e    = vertex_top[v2]
        outward  = (bottom_e - bottom_s).cross(face.normal)
        # A negative extrusion can collapse top_s onto top_e (or onto a
        # bottom point) when neighbouring V_tops converge. Dedupe before
        # asking SketchUp to build the face — `add_face` rejects arrays
        # with duplicate points.
        pts      = dedupe_consecutive_points([bottom_s, bottom_e, top_e, top_s])
        return if pts.length < 3
        n_world  = xform ? face.normal.transform(xform) : face.normal
        n_attr   = [n_world.x, n_world.y, n_world.z]

        if pts.length == 3 || coplanar?(pts)
          wall = ents.add_face(pts)
          return unless wall
          wall.reverse! if wall.normal.dot(outward) < 0
          wall.set_attribute(SURFACE_ATTR_DICT, SURFACE_ATTR_NORMAL, n_attr)
          return
        end

        tri1 = ents.add_face(pts[0], pts[1], pts[2])
        tri2 = ents.add_face(pts[0], pts[2], pts[3])
        # Wall fan-triangulation diagonal — tag as a QFT divider.
        diag = find_edge_between(ents, pts[0], pts[2])
        mark_quad_divider(diag) if diag
        [tri1, tri2].each do |tri|
          next unless tri
          tri.reverse! if tri.normal.dot(outward) < 0
          tri.set_attribute(SURFACE_ATTR_DICT, SURFACE_ATTR_NORMAL, n_attr)
        end
      end

      def find_edge_between(ents, p1, p2)
        ents.grep(Sketchup::Edge).find do |e|
          (e.start.position == p1 && e.end.position == p2) ||
            (e.start.position == p2 && e.end.position == p1)
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
        @selected_faces      = []
        @preview_cache       = []
        @anchor_set          = false
        @distance_frozen     = false
        @frozen_point        = nil
        @pending_commit_distance = nil
        @axis_lock           = nil
        @normal_lock         = false   # experimental: lock extrusion to a face normal
        @normal_origin       = nil     # the clicked point on the original face (origin)
        @normal_dir          = nil     # that face's world normal (the locked axis)
        @hover_point         = nil     # current snap point on an original face (orange dot)
        @hover_normal        = nil
        @v_ip                = nil
        @inference_lock_held = false
        @flip_direction      = false
        @both_sides          = false
        @operation_open      = false
        Sketchup::set_status_text("", SB_PROMPT)
        UI.start_timer(0) { Sketchup.active_model.select_tool(nil) }
      end

      def update_vcb(label = nil, value = nil)
        label ||= Lang.t(:tools, :faceup, :vcb_label)
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
      # Light blue fill for the original (selected) faces in the preview, so
      # they read apart from the new extruded walls/top (kept gray/white). The
      # original faces and their base edges are blue; the NEW edges the
      # extrusion draws (offset perimeter, wall verticals, internal) are orange.
      ORIGINAL_FACE_BLUE = Sketchup::Color.new(170, 210, 240).freeze

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
        shift:       16,  # VK_SHIFT / CONSTRAIN_MODIFIER_KEY on Windows
        ctrl:        17,  # VK_CONTROL on Windows
      }.freeze

      CIRCLE_SEGMENTS = 16

      # Orange line from anchor to the effective cursor position. Recolors and
      # thickens to the axis color when arrow-key axis lock is engaged. The
      # cursor's own inference marker and from-V/from-anchor axis lines are
      # drawn natively by @cursor_ip.draw(view).
      def draw_orange_line(view)
        # Once the distance is frozen the measurement is done: drop the orange
        # line (and the from-anchor marker) so only the committed preview and
        # the cursor's vertex detection show, ready for a fresh start click.
        return if @distance_frozen
        return unless @anchor_ip.valid?
        cursor_pos = effective_cursor_position(view)
        return unless cursor_pos
        s1 = view.screen_coords(@anchor_ip.position)
        s2 = view.screen_coords(cursor_pos)

        if @axis_lock
          view.line_width    = 3
          view.drawing_color = AXIS_COLORS[@axis_lock]
        else
          view.line_width    = 2
          view.drawing_color = ORANGE
        end
        view.draw2d(GL_LINES,
          Geom::Point3d.new(s1.x, s1.y, 0),
          Geom::Point3d.new(s2.x, s2.y, 0))
        view.line_width = 1

        draw_anchor_dot(view)
        draw_frozen_marker(view, @frozen_point, @anchor_ip.position) if @frozen_point
      end

      # Experimental normal lock: an orange dot where the cursor rests on an
      # original face (before locking), then — once locked — the face normal as
      # a guide line through the origin in both directions, drawn on top.
      def draw_normal_lock(view)
        if @hover_point && !@normal_lock
          draw_inference_circle(view, @hover_point, ORANGE)
          return
        end
        return unless @normal_lock && @normal_origin && @normal_dir
        len = view.pixels_to_model(3000, @normal_origin)
        a   = @normal_origin.offset(@normal_dir,  len)
        b   = @normal_origin.offset(@normal_dir, -len)
        view.line_width    = 1
        view.line_stipple  = "."
        view.drawing_color = Sketchup::Color.new('black')
        view.draw(GL_LINES, a, b)
        view.line_stipple  = ""
        draw_inference_circle(view, @normal_origin, ORANGE)
        # Distance marker: where the cursor projects onto the normal line — the
        # point the extrusion currently reaches. Slides as the mouse moves.
        ecp = effective_cursor_position(view)
        draw_inference_circle(view, ecp, ORANGE) if ecp
      end

      def draw_anchor_dot(view)
        return unless @anchor_ip.valid?
        if @anchor_set
          draw_inference_circle(view, @anchor_ip.position, ORANGE)
        elsif snapped?(@anchor_ip)
          draw_inference_marker(view, @anchor_ip.position, @anchor_ip)
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

      # Cursor position with the arrow-key axis lock applied (hard projection
      # onto anchor + t * AXIS_VECTORS[@axis_lock]). Returns the raw
      # @cursor_ip.position otherwise. SketchUp's native inference lock (Shift)
      # is honored by @cursor_ip itself — no projection needed here.
      def effective_cursor_position(view = nil)
        # Normal lock: map the cursor's SCREEN RAY onto the normal line and take
        # the closest point. Movement is purely along the line — geometry the
        # cursor happens to snap to (vertices/edges/faces off the line) is
        # ignored, so nothing off the line can pull the distance.
        if @normal_lock && @normal_origin && @normal_dir
          v = view || @current_view
          if v && @cursor_screen
            ray = v.pickray(@cursor_screen.x, @cursor_screen.y)
            t   = closest_point_on_axis(@normal_origin, @normal_dir, ray[0], ray[1])
            return @normal_origin.offset(@normal_dir, t)
          end
        end
        return nil unless @cursor_ip.valid?
        return @cursor_ip.position unless @axis_lock && @anchor_ip.valid?

        anchor   = @anchor_ip.position
        axis_vec = AXIS_VECTORS[@axis_lock]
        anchor.offset(axis_vec, (@cursor_ip.position - anchor).dot(axis_vec))
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
        # Normal lock: signed offset along the normal from the origin (so the
        # extrusion runs both ways without needing Tab). Uses the screen-ray
        # projection (effective_cursor_position), not the snapped cursor point.
        if @normal_lock && @normal_origin && @normal_dir
          ecp = effective_cursor_position(@current_view)
          if ecp
            t = (ecp - @normal_origin).dot(@normal_dir)
            return (@flip_direction ? -t : t).to_l
          end
          return @extrusion_distance
        end
        return @extrusion_distance unless @anchor_ip.valid? && target_ip.valid?
        endpoint = effective_cursor_position(@current_view) || target_ip.position
        vec      = endpoint - @anchor_ip.position
        (@flip_direction ? -vec.length : vec.length).to_l
      end

    end # class FaceUpTool

    ### TURBO TOOL ### ------------------------------------------------------------

    class TurboTool

      def self.turbo
        return unless ASM_Extensions::FaceUp.summon_faces
        Sketchup.active_model.select_tool(FaceUpTool.new)
      end

    end # class TurboTool

  end # module FaceUp
end # module ASM_Extensions
