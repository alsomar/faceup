require 'json'
require 'sketchup'

module ASM_Extensions
  module FaceUp

    unless file_loaded?(__FILE__)
      ext_id      = File.basename(__FILE__, '.*')
      ext_dir     = File.join(__dir__, ext_id)
      loader      = File.join(ext_dir, 'main')
      info_file   = File.join(ext_dir, 'info.json')
      info_hash   = JSON.parse(File.read(info_file), symbolize_names: true)

      EXTENSION   = info_hash.freeze

      name        = EXTENSION[:name]
      version     = EXTENSION[:version]
      description = EXTENSION[:description]
      creator     = EXTENSION[:creator]
      copyright   = EXTENSION[:copyright]

      ext = SketchupExtension.new(name, loader)
      ext.version     = version
      ext.description = description
      ext.creator     = creator
      ext.copyright   = copyright

      Sketchup.register_extension(ext, true)
      file_loaded(__FILE__)
    end

  end
end
