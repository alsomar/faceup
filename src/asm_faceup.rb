require 'json'
require 'sketchup'

module ASM_Extensions
  module FaceUp

    unless file_loaded?(__FILE__)
      extension_id  = File.basename(__FILE__, '.*')
      extension_dir = File.join(__dir__, extension_id)
      loader      = File.join(plugin_dir, 'main')
      info_file   = File.join(plugin_dir, 'info.json')
      info_hash   = JSON.parse(File.read(info_file), symbolize_names: true)

      EXTENSION   = info_hash.freeze

      name        = EXTENSION[:name]
      version     = EXTENSION[:version]
      description = EXTENSION[:description]
      creator     = EXTENSION[:creator]
      copyright   = EXTENSION[:copyright]

      @ext = SketchupExtension.new(name, loader)
      @ext.version     = version
      @ext.description = description
      @ext.creator     = creator
      @ext.copyright   = copyright

      Sketchup.register_extension(@ext, true)
      file_loaded(__FILE__)
    end

    def self.extension
      @ext
    end

  end
end
