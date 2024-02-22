require 'asm_faceup/data.rb'

module ASM_Extensions
  module FaceUp

    ### MENU & TOOLBARS ### ------------------------------------------------------

    unless file_loaded?(__FILE__)

      @commands = {}
      def self.commands
        @commands
      end

      @file_ext = Sketchup.platform == :platform_win ? 'svg' : 'pdf'
      def self.icon(basename)
        File.join(PATH_ICONS, "#{basename}.#{@file_ext}")
      end

      # Commands
      cmd = UI::Command.new('Summon Faces') {self.summonfaces_tool}
      cmd.small_icon = self.icon("summon_16")
      cmd.large_icon = self.icon("summon_24")
      cmd.status_bar_text = 'Generates faces for selected edges and orients them to face up.'
      cmd.tooltip = 'Summon Faces'
      cmd_summonfaces = cmd
      @commands[:summonfaces] = cmd

      cmd = UI::Command.new('Extruder') {self.extruder_tool}
      cmd.small_icon = self.icon("extruder_16")
      cmd.large_icon = self.icon("extruder_24")
      cmd.status_bar_text = 'Generates solid volumes from selected faces using a user-defined length.'
      cmd.tooltip = 'Extruder'
      cmd_extruder = cmd
      @commands[:extruder] = cmd

      cmd = UI::Command.new('Summon + Extruder') {self.turbo_tool}
      cmd.small_icon = self.icon("turbo_16")
      cmd.large_icon = self.icon("turbo_24")
      cmd.status_bar_text = 'This one stands for Summon + Extruder.'
      cmd.tooltip = 'Summon + Extruder'
      cmd_turbo = cmd
      @commands[:turbo] = cmd

      # Menu
      menu = UI.menu('Extensions').add_submenu(PLUGIN_NAME)
      menu.add_item(cmd_summonfaces)
      menu.add_item(cmd_extruder)
      menu.add_separator
      menu.add_item(cmd_turbo)

      # Context menu
      UI.add_context_menu_handler { |context_menu|
        menu = context_menu.add_submenu(PLUGIN_NAME)
        menu.add_separator
        menu.add_item(cmd_summonfaces)
        menu.add_item(cmd_extruder)
        menu.add_separator
        menu.add_item(cmd_turbo)
      }

      # Toolbar
      toolbar = UI::Toolbar.new (PLUGIN_NAME)
      toolbar.add_item(cmd_summonfaces)
      toolbar.add_item(cmd_extruder)
      toolbar.add_separator
      toolbar.add_item(cmd_turbo)

    end

    ### MAIN SCRIPT ### ----------------------------------------------------------

    def self.summonfaces_tool
      ASM_Extensions::FaceUp::SummonFacesTool.summonfaces
    end

    def self.extruder_tool
      Sketchup.active_model.select_tool(ExtruderTool.new)
    end

    def self.turbo_tool
      ASM_Extensions::FaceUp::TurboTool.turbo
    end

  end # module FaceUp
end # module ASM_Extensions

file_loaded(__FILE__)
