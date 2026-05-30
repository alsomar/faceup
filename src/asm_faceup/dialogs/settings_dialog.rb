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

        observe_units(dialog)
        dialog.set_on_closed { unobserve_units }

        dialog.center
        dialog.show
      end

      def self.push_initial_data(dialog)
        Lang.configure(CONFIG[:language] || "auto") if Lang.dictionary.empty?
        config  = ASM_Extensions::FaceUp.load_config
        config[:model_unit] = ASM_Extensions::FaceUp.model_length_unit(Sketchup.active_model)[:abbr]
        payload = { locale: Lang.locale.to_s, data: Lang.dump }.to_json
        dialog.execute_script("settingsJSON(#{config.to_json.inspect})")
        dialog.execute_script("i18nJSON(#{payload.inspect})")
      end

      def self.refresh_settings_dialog
        return unless @settings && @settings.visible?
        push_initial_data(@settings)
      end

      # Live-sync the model's length unit into the open dialog, so the label
      # updates when the user changes units in Model Info without reopening.
      class UnitsObserver < Sketchup::OptionsProviderObserver
        def initialize(&on_change)
          @on_change = on_change
        end

        def onOptionsProviderChanged(_provider, name)
          @on_change.call if name == 'LengthUnit'
        end
      end

      def self.push_model_unit(dialog)
        return unless dialog && dialog.visible?
        abbr = ASM_Extensions::FaceUp.model_length_unit(Sketchup.active_model)[:abbr]
        dialog.execute_script("modelUnitJSON(#{abbr.to_json})")
      end

      def self.observe_units(dialog)
        unobserve_units
        @units_provider = Sketchup.active_model.options['UnitsOptions']
        @units_observer = UnitsObserver.new { push_model_unit(dialog) }
        @units_provider.add_observer(@units_observer)
      end

      def self.unobserve_units
        if @units_provider && @units_observer
          begin
            @units_provider.remove_observer(@units_observer)
          rescue StandardError
          end
        end
        @units_provider = nil
        @units_observer = nil
      end

      private_class_method :push_initial_data

    end # module Dialogs
  end # module FaceUp
end # module ASM_Extensions
