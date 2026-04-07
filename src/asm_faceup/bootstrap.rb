module ASM_Extensions
  module FaceUp

    SKP_VERSION = Sketchup.version.to_i
    SKP_MINIMUM = 17

    version_check = Sketchup.read_default(EXT_ID, "VersionCheck", true)
    unsupported = version_check && SKP_VERSION < SKP_MINIMUM

    if unsupported
      version_name = "20#{SKP_MINIMUM}"
      message = "#{EXT_NAME} requires SketchUp #{version_name} or newer."
      message_open = false

      UI.start_timer(0, false) {
        unless message_open
          message_open = true
          UI.messagebox(message)
          extension.uncheck
        end
      }
    end

    begin
      Sketchup.require "asm_faceup/core" unless unsupported
    rescue StandardError => e
      puts "#{EXT_NAME} Failed to load. #{e.class}: #{e.message}"
      puts e.backtrace.join("\n")
    end

  end # module FaceUp
end # module ASM_Extensions
