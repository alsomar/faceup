module ASM_Extensions
  module FaceUp
    Sketchup.require(File.join(__dir__, "#{PLUGIN_ID}_data"))

    def self.activate_extruder
      Sketchup.active_model.select_tool(ExtruderTool.new)
    end

    def self.activate_summonfaces
      ASM_Extensions::FaceUp::SummonFaces.summonfaces
    end

    def self.activate_turbo
      model = Sketchup.active_model
      model.start_operation('FaceUp: Summon + Extruder', true)

      begin
        activate_summonfaces
        activate_extruder
      ensure
        model.commit_operation
      end
    end

    def self.add_context_menu_handler
      UI.add_context_menu_handler do |context_menu|
        model = Sketchup.active_model
        selection = model.selection

        if selection.grep(Sketchup::Edge).any? || selection.grep(Sketchup::Face).any?
          faceup_menu = context_menu.add_submenu("FaceUp")

          faceup_menu.add_separator
          faceup_menu.add_item("Summon Faces") { activate_summonfaces }
          faceup_menu.add_item("Extruder") { activate_extruder }
          faceup_menu.add_item("Summon + Extruder") { activate_turbo }
        end
      end
    end

    unless file_loaded?(__FILE__)
      menu = UI.menu('Extensions').add_submenu("FaceUp")
      menu.add_item('Summon Faces') { activate_summonfaces }
      menu.add_item('Face Extruder') { activate_extruder }
      menu.add_item('Summon + Extruder') { activate_turbo }
      file_loaded(__FILE__)
    end

    add_context_menu_handler
  end
end