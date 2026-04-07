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
        UI.messagebox(MESSAGES[:no_edges])
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

      PREVIEW_GRAY  = Sketchup::Color.new(220, 220, 220).freeze
      PREVIEW_WHITE = Sketchup::Color.new('white').freeze

      def initialize
        model = Sketchup.active_model
        @selected_faces     = []
        @extrusion_distance = model.get_attribute('ASM_Extensions_FaceUp', 'last_extrusion_distance', 1.m)
        @preview            = false
        @status_text        = ""
        @distance_entered   = false
      end

      def activate
        model = Sketchup.active_model
        selection = model.selection
        @selected_faces = selection.grep(Sketchup::Face)

        if @selected_faces.empty?
          UI.messagebox("No faces selected.")
          UI.start_timer(0) { Sketchup.active_model.select_tool(nil) }
          return
        end

        @show_faces = model.get_attribute('ExtruderTool', 'show_faces', true)
        @preview = true
        update_vcb
        model.active_view.invalidate

        update_status_text
      end

      def deactivate(view)
        @preview = false
        view.invalidate
      end

      def getExtents
        bb = Geom::BoundingBox.new
        @selected_faces.each do |face|
          next unless face && face.valid?
          normal = face.normal
          face.vertices.each do |v|
            pos = v.position
            bb.add(pos)
            bb.add(pos.offset(normal, @extrusion_distance))
          end
        end
        bb
      end

      def enableVCB?
        true
      end

      def suspend(view)
        @preview_on_suspend = @preview
        @preview = false
        view.invalidate
      end

      def resume(view)
        @preview = @preview_on_suspend
        update_vcb(@current_vcb_label, @current_vcb_value)
        Sketchup::set_status_text(@status_text, SB_PROMPT)
        view.invalidate
      end

      def draw(view)
        return unless @preview

        @selected_faces.each do |face|
          next unless face.valid?
          draw_preview(face, view)
        end
      end

      def onKeyDown(key, repeat, flags, view)
        model = Sketchup.active_model
        if key == 9 # TAB key
          @show_faces = !@show_faces
          model.set_attribute('ExtruderTool', 'show_faces', @show_faces)
          update_status_text
          update_vcb
          view.invalidate
        end
      end

      def onMouseMove(flags, x, y, view)
        view.invalidate if @preview
      end

      def onReturn(view)
        if @distance_entered || @extrusion_distance > 0
          extruder(view)
          reset_tool
        else
          Sketchup::set_status_text("Enter a length and press Enter.", SB_PROMPT)
        end
      end

      def onUserText(text, view)
        begin
          distance = text.to_l
          @extrusion_distance = distance
          @distance_entered   = true
          update_vcb(nil, distance.to_s)
          Sketchup::set_status_text("Press Enter to confirm the extrusion.", SB_PROMPT)
          view.invalidate
        rescue ArgumentError
          Sketchup::set_status_text("Invalid length. Please enter a valid distance.", SB_PROMPT)
        end
      end

      private

      def update_status_text
        mode = @show_faces ? "FACE" : "EDGE"
        @status_text = "Extruder: Adjust the extrusion distance | Preview in #{mode} mode (Press TAB to change)"
        Sketchup::set_status_text(@status_text)
      end

      def draw_preview(face, view)
        return unless face && @extrusion_distance

        normal = face.normal
        dist   = @extrusion_distance
        mesh   = face.mesh(7)
        tris   = mesh.polygons

        if @show_faces
          # Build base and top points in a single pass — no double mesh.point_at
          tris_base = tris.map { |tri| tri.map { |i| mesh.point_at(i.abs) } }
          tris_top  = tris_base.map { |pts| pts.map { |p| p.offset(normal, dist) } }

          view.drawing_color = PREVIEW_GRAY
          tris_base.each_with_index do |points, i|
            extruded_points = tris_top[i]
            view.draw(GL_POLYGON, points)
            points.each_index do |j|
              next_j = (j + 1) % points.length
              view.draw(GL_POLYGON, [points[j], points[next_j], extruded_points[next_j], extruded_points[j]])
            end
          end

          view.drawing_color = PREVIEW_WHITE
          tris_top.each { |pts| view.draw(GL_POLYGON, pts) }

          view.drawing_color = 'blue'
          outer_edges = face.outer_loop.edges
          outer_edges.each do |edge|
            sp           = edge.start.position
            ep           = edge.end.position
            extruded_sp  = sp.offset(normal, dist)
            extruded_ep  = ep.offset(normal, dist)
            view.draw(GL_LINES, extruded_sp, extruded_ep)
            view.draw(GL_LINES, sp, extruded_sp)
            view.draw(GL_LINES, ep, extruded_ep)
          end
        else
          outer_edges = face.outer_loop.edges
          view.drawing_color = 'brown'

          start_point    = outer_edges.first.start.position
          extruded_start = start_point.offset(normal, dist)
          view.draw(GL_LINES, start_point, extruded_start)

          outer_edges.each do |edge|
            view.draw(GL_LINES,
              edge.start.position.offset(normal, dist),
              edge.end.position.offset(normal, dist))
          end
        end
      end

      def extruder(view)
        model = Sketchup.active_model

        method_id  = __method__

        op_name    = "Extruder"
        start_time = Time.now if Debug.enabled
        model.start_operation(op_name, true)

        Debug.separator
        Debug.log(self.class, method_id, "Process START")

        begin
          Debug.log(self.class, method_id, "Wrapper ENTER")

          groups = face2group(@selected_faces)
          xtrd_groups(groups, @extrusion_distance)

          model.selection.add(groups)
          model.set_attribute('ASM_Extensions_FaceUp', 'last_extrusion_distance', @extrusion_distance)

          model.commit_operation
          Debug.log(self.class, method_id, "Wrapper LEAVE")
        rescue => e
          model.abort_operation
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

        @preview = false
        view.invalidate
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
        @extrusion_distance = 1.m
        @preview            = false
        @distance_entered   = false
        Sketchup::set_status_text("", SB_PROMPT)
        UI.start_timer(0) { Sketchup.active_model.select_tool(nil) }
      end

      def update_vcb(label = nil, value = nil)
        label ||= "Length: "
        value ||= @extrusion_distance.to_s

        @current_vcb_label = label
        @current_vcb_value = value

        Sketchup::set_status_text(label, SB_VCB_LABEL)
        Sketchup::set_status_text(value, SB_VCB_VALUE)
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
