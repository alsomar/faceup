module ASM_Extensions
  module FaceUp
    module Lang

      def self.init
        Sketchup.require "asm_faceup/lang/i18n"
        true
      end

    end # module Lang
  end # module FaceUp
end # module ASM_Extensions

ASM_Extensions::FaceUp::Lang.init
