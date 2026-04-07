module ASM_Extensions
  module FaceUp
    module Dialogs

      def self.init
        Sketchup.require 'asm_faceup/dialogs/settings_dialog'
        true
      end

    end # module Dialogs
  end # module FaceUp
end # module ASM_Extensions

ASM_Extensions::FaceUp::Dialogs.init
