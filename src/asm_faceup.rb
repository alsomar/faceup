require 'json'
require 'sketchup'
require 'extensions'

module ASM_Extensions
  module FaceUp

    file = __FILE__.dup
    folder_name = File.basename(file, '.*')

    # Paths
    PATH_ROOT = File.dirname(file).freeze
    PATH = File.join(PATH_ROOT, folder_name).freeze
    PATH_VENDOR = File.join(PATH, "vendor").freeze
    PATH_ICONS = File.join(PATH, "icons").freeze
    PATH_HTML = File.join(PATH, "html").freeze

    # Loads and parses extension.json
    extension_json_file = File.join(PATH, "extension.json")
    extension_json = File.read(extension_json_file)
    EXTENSION = ::JSON.parse(extension_json, symbolize_names: true).freeze

    PLUGIN = self
    PLUGIN_NAME = EXTENSION[:name]
    PLUGIN_VERSION = EXTENSION[:version]
    PLUGIN_DESCRIPTION = EXTENSION[:description]
    PLUGIN_AUTHOR = EXTENSION[:creator]
    PLUGIN_COPYRIGHT = EXTENSION[:copyright]

    # Prepares the extension for registration
    unless file_loaded?(__FILE__)
      loader = File.join(PATH, "main")

      @ext = SketchupExtension.new(EXTENSION[:name], loader)
      @ext.description = PLUGIN_DESCRIPTION
      @ext.version = PLUGIN_VERSION
      @ext.copyright = PLUGIN_COPYRIGHT
      @ext.creator = PLUGIN_AUTHOR

      Sketchup.register_extension(@ext, true)
    end

    # Provides access to the extension instance
    def self.extension
      @ext
    end

  end # module FaceUp
end # module ASM_Extensions
