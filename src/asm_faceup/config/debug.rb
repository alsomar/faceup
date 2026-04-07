module ASM_Extensions
  module FaceUp
    module Debug

      def self.enabled
        return false unless defined?(CONFIG) && CONFIG.is_a?(Hash)
        CONFIG[:debug_mode] == true
      end

      def self.log(mod, method_id, msg)
        return unless enabled
        context = "#{mod.name.split('::').reject { |p| p == 'ASM_Extensions' }.join('::')}.#{method_id}"
        puts "[#{Time.now.strftime('%H:%M:%S')}][#{context}] #{msg}"
      end

      def self.separator
        puts "" if enabled
      end

    end # module Debug
  end # module FaceUp
end # module ASM_Extensions
