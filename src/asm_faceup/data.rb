
module ASM_Extensions
  module FaceUp

    def self.summonfaces
      model = Sketchup.active_model
      selection = model.selection
      presel_faces = selection.grep(Sketchup::Face)
      presel_edges = selection.grep(Sketchup::Edge)

      unless presel_edges.empty?
        model.start_operation("FaceUp: Summon Faces", true)
        new_faces = create_faces(presel_edges)
        orient_faces(new_faces)
        update_selection(selection, presel_faces, new_faces)
        model.commit_operation
      else
        UI.messagebox("Please select some edges.")
      end
    end

    def self.create_faces(presel_edges)
      new_faces = []
      presel_edges.each do |edge|
        edge.find_faces
        edge.faces.each { |face| new_faces << face unless new_faces.include?(face) }
      end
      new_faces.uniq
    end

    def self.orient_faces(new_faces)
      camera = Sketchup.active_model.active_view.camera
      view_vector = camera.eye - camera.target
      view_orientation = view_vector.normalize

      new_faces.each do |face|
        angle = face.normal.angle_between(view_orientation)
        face.reverse! if angle.abs > Math::PI / 2
      end
    end

    def self.update_selection(selection, presel_faces, new_faces)
      selection.clear
      final_faces = presel_faces + new_faces
      selection.add(final_faces)
      final_edges = final_faces.map(&:edges).flatten.uniq
      selection.add(final_edges)
    end

    class ExtruderTool

      def initialize
        model = Sketchup.active_model
        @selected_faces = []
        @extrusion_distance = model.get_attribute('ASM_Extensions_FaceUp', 'last_extrusion_distance', 1.m)
        @preview = false
        @status_text = ""
        @distance_entered = false
      end

      def activate
        model = Sketchup.active_model
        selection = model.selection
        @selected_faces = selection.grep(Sketchup::Face)

        if @selected_faces.empty?
          UI.messagebox("No faces selected.")
          Sketchup.active_model.select_tool(nil)
          return
        end

        @show_faces = model.get_attribute('ExtruderTool', 'show_faces', true)
        @preview = true
        update_vcb
        model.active_view.invalidate if @preview

        update_status_text
      end

      def deactivate(view)
        @preview = false
        view.invalidate
      end

      def suspend(view)
        @preview_on_suspend = @preview

        @preview = false
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
        if key == 9 # Tecla TAB
          @show_faces = !@show_faces
          model.set_attribute('ExtruderTool', 'show_faces', @show_faces)
          update_status_text  # Actualizar la barra de estado
          update_vcb          # Actualiza el VCB
          view.invalidate     # Actualiza la vista
        end
      end

      def onMouseMove(flags, x, y, view)
        if @preview
          view.invalidate
        end
      end

      def onReturn(view)
        if @distance_entered || @extrusion_distance > 0
          apply_extrusion(view)
          reset_tool
        else
          Sketchup::set_status_text("Enter a length and press Enter.", SB_PROMPT)
        end
      end

      def onUserText(text, view)
        begin
          distance = text.to_l
          @extrusion_distance = distance
          @distance_entered = true
          Sketchup::set_status_text("Press Enter to confirm the extrusion.", SB_PROMPT)
          view.invalidate
        end
      end

      def update_status_text
        mode = @show_faces ? "FACE" : "EDGE"
        @status_text = "Extruder: Adjust the extrusion distance | Preview in #{mode} mode (Press TAB to change)"
        Sketchup::set_status_text(@status_text)
      end

      private

      def draw_preview(face, view)
        return unless face && @extrusion_distance

        mesh = face.mesh(7)
        tris = mesh.polygons

        # Modo Caras
        if @show_faces
          # Pre-calcula los puntos extruidos para cada triángulo
          extruded_tris_points = tris.map do |tri|
            tri.map { |index| mesh.point_at(index.abs).offset(face.normal, @extrusion_distance) }
          end

          # Dibuja la cara original y las caras laterales en gris
          view.drawing_color = Sketchup::Color.new(220, 220, 220)
          tris.each_with_index do |tri, i|
            points = tri.map { |index| mesh.point_at(index.abs) }
            extruded_points = extruded_tris_points[i]

            view.draw(GL_POLYGON, points)

            points.each_index do |j|
              next_point_index = (j + 1) % points.length
              lateral_face = [points[j], points[next_point_index], extruded_points[next_point_index], extruded_points[j]]
              view.draw(GL_POLYGON, lateral_face)
            end
          end

          # Cambia el color a blanco solo para la cara superior extruida
          view.drawing_color = Sketchup::Color.new('white')
          extruded_tris_points.each do |extruded_points|
            view.draw(GL_POLYGON, extruded_points)
          end

          # Establece el color de las aristas a azul
          view.drawing_color = 'blue'
          # Pre-calcula los puntos extruidos para las aristas
          extruded_edge_points = face.outer_loop.edges.map do |edge|
            [edge.start.position.offset(face.normal, @extrusion_distance),
             edge.end.position.offset(face.normal, @extrusion_distance)]
          end

          face.outer_loop.edges.each_with_index do |edge, i|
            start_point, end_point = extruded_edge_points[i]

            # Arista superior extruida
            view.draw(GL_LINES, start_point, end_point)

            # Arista vertical desde cada punto de la arista
            view.draw(GL_LINES, edge.start.position, start_point)
            view.draw(GL_LINES, edge.end.position, end_point)
          end
        end

        # Modo Aristas
        unless @show_faces
          view.drawing_color = 'brown'

          # Pre-calcula los puntos extruidos para las aristas
          extruded_edge_points = face.outer_loop.edges.map do |edge|
          [edge.start.position.offset(face.normal, @extrusion_distance),
          edge.end.position.offset(face.normal, @extrusion_distance)]
          end

          # Selecciona y dibuja una arista vertical representativa.
          # Considera si necesitas dibujar esta arista específica o si sería mejor mostrar todas.
          start_point = face.outer_loop.edges.first.start.position
          extruded_start = start_point.offset(face.normal, @extrusion_distance)
          view.draw(GL_LINES, start_point, extruded_start)

          # Dibuja el contorno de la cara superior utilizando los puntos extruidos precalculados.
          extruded_edge_points.each do |start_point, end_point|
          view.draw(GL_LINES, start_point, end_point)
          end
        end
      end

      def apply_extrusion(view)
        model = Sketchup.active_model
        model.start_operation('FaceUp: Extruder', true)

        groups = face2group(@selected_faces)
        xtrd_groups(groups, @extrusion_distance)
        model.selection.add(groups)

        model.set_attribute('ASM_Extensions_FaceUp', 'last_extrusion_distance', @extrusion_distance)

        model.commit_operation
        @preview = false
        view.invalidate
      end

      def face2group(faces)
        faces_with_inner_edges = []
        faces_without_inner_edges = []

        faces.each do |face|
        outer_edges = face.outer_loop.edges
          if face.edges.any? { |edge| !outer_edges.include?(edge) }
            faces_with_inner_edges << face
          else
            faces_without_inner_edges << face
          end
        end

        groups_with_inner_edges = faces_with_inner_edges.sort_by { |face| -face.area }.map do |face|
        Sketchup.active_model.entities.add_group([face, *face.edges])
        end

        groups_without_inner_edges = faces_without_inner_edges.map do |face|
        Sketchup.active_model.entities.add_group(face)
        end

        groups_with_inner_edges + groups_without_inner_edges
      end

      def xtrd_groups(groups, height)
        default_layer = Sketchup.active_model.layers[0]

        groups.each do |group|
          group.entities.grep(Sketchup::Face).each { |face| face.layer = default_layer }
          group.entities.grep(Sketchup::Edge).each { |edge| edge.layer = default_layer }

          face = group.entities.grep(Sketchup::Face).first
          face.pushpull(height) if face
        end
      end

      def reset_tool
        @selected_faces = []
        @extrusion_distance = 1.m
        @preview = false
        @distance_entered = false
        Sketchup::set_status_text("", SB_PROMPT)
        Sketchup.active_model.select_tool(nil)
      end

      def update_vcb(label=nil, value = nil)
        label ||= "Length: "
        value ||= @extrusion_distance.to_s

        Sketchup::set_status_text(label,SB_VCB_LABEL)
        Sketchup::set_status_text(value,SB_VCB_VALUE)
      end

    end # class ExtruderTool

    class TurboTool

      def self.turbo_step1
        ASM_Extensions::FaceUp::SummonFacesTool.summonfaces
      end

      def self.turbo_step2
        Sketchup.active_model.select_tool(ExtruderTool.new)
      end

      def self.turbo
        model = Sketchup.active_model

        begin
          turbo_step1
          turbo_step2
        end
      end

    end # class TurboTool

    def self.settings_dialog
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end

      html_file = File.join(PATH_HTML, 'index.html')
      html_title = "#{PLUGIN_NAME} #{PLUGIN_VERSION}"

      width = 15 + 400 + 15
      height = 15 + 600 + 15

      if Sketchup.version.to_f < 21.1
        width += 20
        height += 40
      end

      options = {
        dialog_title: html_title,
        preferences_key: "asm_extensions.htmldialog.faceup",
        style: UI::HtmlDialog::STYLE_DIALOG,
        resizable: true,
        width: width,
        height: height,
        use_content_size: true
      }

      @dialog ||= UI::HtmlDialog.new(options)
      @dialog.set_file(html_file)

      @dialog.add_action_callback("userSettings") do |action_context, context_menu, user_language|
        userSettings(context_menu, user_language)
      end

      @dialog.center
      @dialog.show
    end

  end # module FaceUp
end # module ASM_Extensions
