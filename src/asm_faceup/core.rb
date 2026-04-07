Sketchup.require 'asm_faceup/config/init_config'
Sketchup.require 'asm_faceup/lang/init_lang'
Sketchup.require 'asm_faceup/ops/init_ops'
Sketchup.require 'asm_faceup/dialogs/init_dialogs'

module ASM_Extensions
  module FaceUp

    Lang.configure(CONFIG[:language] || "auto")

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
      cmd = UI::Command.new(Lang.commands.summonfaces.label.to_s) { self.summonfaces_tool }
      cmd.small_icon = self.icon("summon_16")
      cmd.large_icon = self.icon("summon_24")
      cmd.status_bar_text = Lang.commands.summonfaces.status
      cmd.tooltip = Lang.commands.summonfaces.tooltip
      cmd_summonfaces = cmd
      @commands[:summonfaces] = cmd

      cmd = UI::Command.new(Lang.commands.extruder.label.to_s) { self.extruder_tool }
      cmd.small_icon = self.icon("extruder_16")
      cmd.large_icon = self.icon("extruder_24")
      cmd.status_bar_text = Lang.commands.extruder.status
      cmd.tooltip = Lang.commands.extruder.tooltip
      cmd_extruder = cmd
      @commands[:extruder] = cmd

      cmd = UI::Command.new(Lang.commands.turbo.label.to_s) { self.turbo_tool }
      cmd.small_icon = self.icon("turbo_16")
      cmd.large_icon = self.icon("turbo_24")
      cmd.status_bar_text = Lang.commands.turbo.status
      cmd.tooltip = Lang.commands.turbo.tooltip
      cmd_turbo = cmd
      @commands[:turbo] = cmd

      cmd = UI::Command.new(Lang.commands.settings.label.to_s) { self.settings_tool }
      cmd.small_icon = self.icon("settings_16")
      cmd.large_icon = self.icon("settings_24")
      cmd.status_bar_text = Lang.commands.settings.status
      cmd.tooltip = Lang.commands.settings.tooltip
      cmd_settings = cmd
      @commands[:settings] = cmd

      # Menu
      menu = UI.menu('Extensions').add_submenu(EXT_NAME)
      menu.add_item(cmd_summonfaces)
      menu.add_item(cmd_extruder)
      menu.add_separator
      menu.add_item(cmd_turbo)
      menu.add_separator
      menu.add_item(cmd_settings)

      # Context menu
      UI.add_context_menu_handler do |context_menu|
        next unless CONFIG[:context_menu]
        menu = context_menu.add_submenu(EXT_NAME)
        menu.add_separator
        menu.add_item(cmd_summonfaces)
        menu.add_item(cmd_extruder)
        menu.add_separator
        menu.add_item(cmd_turbo)
      end

      # Toolbar
      toolbar = UI::Toolbar.new(EXT_NAME)
      toolbar.add_item(cmd_summonfaces)
      toolbar.add_item(cmd_extruder)
      toolbar.add_separator
      toolbar.add_item(cmd_turbo)
      toolbar.add_separator
      toolbar.add_item(cmd_settings)

      if toolbar.get_last_state == TB_VISIBLE
        toolbar.restore
      else
        toolbar.show
      end

      ## TOOL METHODS ## ---------------------------------------------------------

      def self.summonfaces_tool
        ASM_Extensions::FaceUp.summon_faces
      end

      def self.extruder_tool
        Sketchup.active_model.select_tool(ExtruderTool.new)
      end

      def self.turbo_tool
        ASM_Extensions::FaceUp::TurboTool.turbo
      end

      def self.settings_tool
        ASM_Extensions::FaceUp::Dialogs.settings_dialog
      end

      file_loaded(__FILE__)
    end

  end # module FaceUp
end # module ASM_Extensions
