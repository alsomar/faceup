module ASM_Extensions
  module FaceUp

    def self.init_ops
      Sketchup.require 'asm_faceup/ops/selection'
      Sketchup.require 'asm_faceup/ops/tools'
      true
    end

  end # module FaceUp
end # module ASM_Extensions

ASM_Extensions::FaceUp.init_ops
