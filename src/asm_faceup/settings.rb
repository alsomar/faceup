require 'json'
require 'fileutils'
require 'sketchup'

module ASM_Extensions
  module FaceUp

    @settings = nil

    # Settings paths
    PATH = __dir__.freeze

    PATH_VENDOR = File.join(PATH, 'vendor').freeze
    PATH_ICONS  = File.join(PATH, 'icons').freeze
    PATH_HTML   = File.join(PATH, 'html').freeze

    EXT_ID      = File.basename(PATH).freeze

    # User config
    config_root =
      if Sketchup.platform == :platform_win
        ENV["LOCALAPPDATA"] || Dir.home
      else
        File.expand_path("~/Library/Application Support")
      end

    CONFIG_FOLDER = File.join(config_root, 'ASM_Extensions', EXT_ID).freeze
    FileUtils.mkdir_p(CONFIG_FOLDER)

    CONFIG_FILE = File.join(CONFIG_FOLDER, ".#{EXT_ID}.json").freeze
    File.write(CONFIG_FILE, '{}') unless File.exist?(CONFIG_FILE)

    # SETTINGS -------------------------------------------------------------------

    DEFAULT_CONFIG = {
      # Test Settings
      settings_test1: true,
      settings_test2: false,
      settings_test3: false,

      # General Options
      language: "eng",
      context_menu: false,

      # Debug
      debug_mode: false
    }.freeze

    def self.load_config
      method_id = __method__

      begin
        loaded = JSON.parse(File.read(CONFIG_FILE), symbolize_names: true)
        DEFAULT_CONFIG.merge(loaded)
      rescue => e
        debug_log(method_id, "Config load failed: #{e.message}")
        DEFAULT_CONFIG.dup
      end
    end

    CONFIG = load_config

    def self.save_config(config_hash)
      method_id = __method__

      begin
        File.write(CONFIG_FILE, JSON.pretty_generate(config_hash))
      rescue => e
        debug_log(method_id, "Failed to save config: #{e.message}")
      end
    end

    def self.user_settings(settings)
      method_id = __method__
      current = load_config

      # Filter only the settings that actually changed
      changed = {}

      settings.each do |key, new_value|
        old_value = current[key]
        next if old_value == new_value  # skip if the value is unchanged
        changed[key] = new_value
      end

      if changed.empty?
        debug_log(method_id, "All values already up-to-date.")
        return
      end

      # Save only the updated settings to the config file
      merged = current.merge(changed)
      save_config(merged)

      # Update the in-memory context only with the changed entries
      CONFIG.merge!(changed)

      # Special log for debug_mode, always visible
      if changed.key?(:debug_mode)
        state = changed[:debug_mode] ? "ON" : "OFF"
        puts "[#{PLUGIN_NAME}][#{method_id}] DEBUG mode is #{state}"
      end

      # Log each updated setting (except debug_mode, que ya hemos logueado arriba)
      changed.each do |key, new_value|
        next if key == :debug_mode
        debug_log(method_id, "#{key}: #{new_value.inspect}")
      end
    end

    # HTML DIALOGS ---------------------------------------------------------------

    PLUGIN_NAME        = EXTENSION[:name]
    PLUGIN_VERSION     = EXTENSION[:version]

    def self.settings_dialog
      if @settings && @settings.visible?
        @settings.bring_to_front
        return
      end

      html_file  = File.join(PATH_HTML, 'settings.html')
      html_title = "#{PLUGIN_NAME} #{PLUGIN_VERSION}"

      options = {
        dialog_title: html_title,
        preferences_key: "asm_extensions.htmldialog.testext_settings",
        style: UI::HtmlDialog::STYLE_DIALOG,
        resizable: false,
        width: 420,
        height: 600,
        use_content_size: true
      }

      @settings = UI::HtmlDialog.new(options)
      @settings.set_file(html_file)

      # Sends current config to the dialog
      @settings.add_action_callback("ready") do |_context|
        config = load_config

        @settings.execute_script("settingsJSON(#{config.to_json.inspect})")
        @settings.execute_script("infoJSON(#{EXTENSION.to_json.inspect})")
      end

      # Receives updated settings from JS and saves them
      @settings.add_action_callback("user_settings") do |_context, settings_json|
        settings = JSON.parse(settings_json, symbolize_names: true)
        user_settings(settings)
      end

      @settings.center
      @settings.show
    end

  end
end
