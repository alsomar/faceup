module ASM_Extensions
  module FaceUp

    MESSAGES = {
      no_selection:  "There's nothing selected.",
      no_edges:      "Please select some edges.",
      process_done:  "✔ Process done!",
      process_fail:  "✘ Process failed!"
    }.freeze

    # SELECTION METHODS -----------------------------------------------------------

    def self.instances(e)
      e.grep(Sketchup::Group).concat(e.grep(Sketchup::ComponentInstance))
    end

    def self.check_selection(targets)
      method_id = __method__

      if targets.empty?
        UI.messagebox(MESSAGES[:no_selection])
        Debug.log(method_id, "Invalid selection: missing targets.") 
        return false
      end

      true
    end

    module Debug
      def self.enabled
        return false unless defined?(CONFIG) && CONFIG.is_a?(Hash)
        CONFIG[:debug_mode] == true
      end

      def self.log(method_id, msg)
        return unless enabled
        puts "[#{Time.now.strftime('%H:%M:%S.%L')}][#{PLUGIN_NAME}][#{method_id}] #{msg}"
      end

      def self.separator
        puts "" if enabled
      end

    end

  end
end
