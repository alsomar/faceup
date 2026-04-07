module ASM_Extensions
  module FaceUp

    def self.init_config
      Sketchup.require "asm_faceup/config/debug"
      Sketchup.require "asm_faceup/config/paths"
      Sketchup.require "asm_faceup/config/environment"
      Sketchup.require "asm_faceup/config/settings"
      true
    end

  end # module FaceUp
end # module ASM_Extensions

ASM_Extensions::FaceUp.init_config
