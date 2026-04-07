require 'json'

module ASM_Extensions
  module FaceUp
    module Dialogs

      @settings = nil unless instance_variable_defined?(:@settings)

      def self.settings_dialog
        if @settings && @settings.visible?
          push_initial_data(@settings)
          @settings.bring_to_front
          return
        end

        html_file  = File.join(PATH_HTML, 'settings.html')
        html_title = "#{EXT_NAME} #{INFO_VERSION}"

        options = {
          dialog_title:    html_title,
          preferences_key: "asm_extensions.htmldialog.faceup_settings",
          style:           UI::HtmlDialog::STYLE_DIALOG,
          resizable:       false,
          width:           420,
          height:          600,
          use_content_size: true
        }

        dialog = UI::HtmlDialog.new(options)
        dialog.set_file(html_file)
        @settings = dialog

        dialog.add_action_callback("ready") do |_context|
          push_initial_data(dialog)
        end

        dialog.add_action_callback("user_settings") do |_context, settings_json|
          settings = JSON.parse(settings_json, symbolize_names: true)
          ASM_Extensions::FaceUp.user_settings(settings)

          if settings.key?(:language)
            Lang.configure(settings[:language])
            payload = { locale: Lang.locale.to_s, data: Lang.dump }.to_json
            dialog.execute_script("i18nJSON(#{payload.inspect})")
          end
        end

        dialog.center
        dialog.show
      end

      def self.push_initial_data(dialog)
        Lang.configure(CONFIG[:language] || "auto") if Lang.dictionary.empty?
        config  = ASM_Extensions::FaceUp.load_config
        payload = { locale: Lang.locale.to_s, data: Lang.dump }.to_json
        dialog.execute_script("settingsJSON(#{config.to_json.inspect})")
        dialog.execute_script("i18nJSON(#{payload.inspect})")
      end

      def self.refresh_settings_dialog
        return unless @settings && @settings.visible?
        push_initial_data(@settings)
      end

      private_class_method :push_initial_data

    end # module Dialogs
  end # module FaceUp
end # module ASM_Extensions
