module ASM_Extensions
  module FaceUp

    def self.groups(e)
      e.grep(Sketchup::Group)
    end

    def self.components(e)
      e.grep(Sketchup::ComponentInstance)
    end

    def self.faces(e)
      e.grep(Sketchup::Face)
    end

    def self.edges(e)
      e.grep(Sketchup::Edge)
    end

    def self.instance?(e)
      e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
    end

    def self.instances(e)
      groups(e) + components(e)
    end

    def self.geometries(e)
      faces(e) + edges(e)
    end

  end # module FaceUp
end # module ASM_Extensions
