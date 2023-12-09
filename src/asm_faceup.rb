require 'extensions'

module ASM_Extensions
  module FaceUp

    # Variables
    PLUGIN_NAME = 'FaceUp'.freeze
    PLUGIN_VERSION = '1.0.0'.freeze
    PLUGIN_DESCRIPTION = 'Streamlined face creation from edges and efficient face extrusion.'.freeze
    PLUGIN_AUTHOR = 'Alejandro Soriano'.freeze
    PLUGIN_ID = File.basename(__FILE__, '.*')

    # Paths
    PATH_ROOT = File.dirname(__FILE__)
    FILE_DATA = File.join(PATH_ROOT, PLUGIN_ID, "#{PLUGIN_ID}_data")
    FILE_MAIN = File.join(PATH_ROOT, PLUGIN_ID, "#{PLUGIN_ID}_main")

    # Extension Initialization
    EXT_DATA = SketchupExtension.new(PLUGIN_NAME, FILE_MAIN)

    # Some nice info
    EXT_DATA.creator = PLUGIN_AUTHOR
    EXT_DATA.version = PLUGIN_VERSION
    EXT_DATA.copyright = "2022-#{Time.now.year}, #{PLUGIN_AUTHOR}"
    EXT_DATA.description = PLUGIN_DESCRIPTION

    # Register and load the extension on first install
    Sketchup.register_extension(EXT_DATA, true)

  end # module FaceUp
end # module ASM_Extensions