module ASM_Extensions
  module FaceUp
    module Lang

      AVAILABLE_LOCALES = %w[en-US es-ES].freeze
      DEFAULT_LOCALE = "en-US"

      LINK_SKP_FORUMS    = "<a href=\"https://forums.sketchup.com/\" target=\"_blank\">SketchUp Forums</a>".freeze
      LINK_SUC_FORUMS    = "<a href=\"https://sketchucation.com/forums/\" target=\"_blank\">SketchUcation</a>".freeze
      LINK_EXT_WAREHOUSE = "<a href=\"https://extensions.sketchup.com/\" target=\"_blank\">Extension Warehouse</a>".freeze
      LINK_SKETCHUCATION = "<a href=\"https://sketchucation.com/\" target=\"_blank\">SketchUcation</a>".freeze
      LINK_ALEJANDRO     = "<a href=\"https://alejandrosoriano.xyz\" target=\"_blank\">Alejandro Soriano</a>".freeze
      LINK_MODUS         = "<a href=\"https://modus-bootstrap.trimble.com/\" target=\"_blank\">Trimble Modus Bootstrap</a>".freeze
      LINK_PATREON       = "<a href=\"https://patreon.com/alejandrosoriano\" target=\"_blank\">Patreon</a>".freeze
      LINK_KOFI          = "<a href=\"https://ko-fi.com/alejandrosoriano\" target=\"_blank\">Ko-fi</a>".freeze

      MONTH_NAMES_LONG = {
        "en-US" => %w[January February March April May June July August September October November December],
        "es-ES" => %w[enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre]
      }.freeze

      MONTH_NAMES_SHORT = {
        "en-US" => %w[Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec],
        "es-ES" => %w[ene feb mar abr may jun jul ago sep oct nov dic]
      }.freeze

      @locale   = DEFAULT_LOCALE
      @data     = {}
      @fallback = {}

      # Represents a final translated string with fallback support
      class Leaf
        def initialize(path, value, fallback)
          @path = path
          @value = value
          @fallback = fallback
        end

        def to_s
          return @value.to_s unless @value.nil?
          return @fallback.to_s unless @fallback.nil?
          "⚠ missing: #{@path.join('.')}"
        end

        def to_str
          to_s
        end
      end

      # Navigation node for hierarchical language keys
      class Node
        def initialize(path, data, fallback, debug_proc)
          @path = path
          @data = data.is_a?(Hash) ? data : {}
          @fallback = fallback.is_a?(Hash) ? fallback : {}
          @debug = debug_proc
        end

        def [](key)
          key = key.to_sym

          value = @data.key?(key) ? @data[key] : nil
          fb    = @fallback.key?(key) ? @fallback[key] : nil

          if value.nil? && !fb.nil?
            @debug.call((missing_key_path(key)).join('.'), :fallback) if @debug
            value = fb
          elsif value.nil? && fb.nil?
            @debug.call((missing_key_path(key)).join('.'), :missing) if @debug
          end

          if value.is_a?(Hash) || fb.is_a?(Hash)
            Node.new(@path + [key], value, (fb.is_a?(Hash) ? fb : {}), @debug)
          else
            Leaf.new(@path + [key], value, fb)
          end
        end

        def method_missing(name, *args, &block)
          return super unless args.empty? && block.nil?
          self[name]
        end

        def respond_to_missing?(_name, _include_private = false)
          true
        end

        private

        def missing_key_path(key)
          @path + [key]
        end
      end

      # --- Public API ---

      def self.configure(locale)
        loc = locale.to_s.strip
        loc = DEFAULT_LOCALE if loc.empty?

        if loc == 'auto'
          sys = Sketchup.get_locale rescue DEFAULT_LOCALE
          sys_lang = sys.to_s.split(/[-_]/).first.downcase
          loc = AVAILABLE_LOCALES.find { |av| av.split('-').first.downcase == sys_lang } ||
                DEFAULT_LOCALE
        else
          loc = DEFAULT_LOCALE unless AVAILABLE_LOCALES.include?(loc)
        end

        @locale = loc

        Sketchup.require "asm_faceup/lang/locales/en_us"

        file = @locale.downcase.tr("-", "_")
        Sketchup.require "asm_faceup/lang/locales/#{file}"

        load_locale_files
        @data[:html] ||= {}
        @fallback[:html] ||= {}
        true
      end

      def self.dump
        merged = (dictionary || {}).dup
        merged[:html] ||= {}
        merged[:html] = merged[:html].dup
        merged[:html][:info] = {
          name:      INFO_NAME,
          author:    INFO_AUTHOR,
          version:   INFO_VERSION,
          update:    format_update_date,
          copyright: INFO_COPY
        }.freeze
        merged[:months_long]  = MONTH_NAMES_LONG[@locale]  || MONTH_NAMES_LONG[DEFAULT_LOCALE]
        merged[:months_short] = MONTH_NAMES_SHORT[@locale] || MONTH_NAMES_SHORT[DEFAULT_LOCALE]
        deep_stringify(merged)
      end

      def self.dictionary
        ensure_loaded
        @data
      end

      def self.locale
        @locale
      end

      def self.root
        ensure_loaded
        @root ||= Node.new([], @data, @fallback, debug_proc)
      end

      # Defensive: an Extension Sources reload re-runs `@data = {}` at the
      # module level, so any Lang access after a reload would find an empty
      # dictionary. Re-configure on the fly when that happens. Called from
      # every public entry point that touches @data (root, dictionary, dump).
      def self.ensure_loaded
        return unless @data.nil? || @data.empty?
        lang = (defined?(CONFIG) && CONFIG.is_a?(Hash) ? CONFIG[:language] : nil) || "auto"
        configure(lang)
      end

      def self.commands
        root.commands
      end

      def self.t(*keys)
        keys.reduce(root) { |acc, k| acc[k] }.to_s
      end

      # --- Internals ---

      def self.load_locale_files
        @fallback = load_rb(DEFAULT_LOCALE)
        @data = (@locale == DEFAULT_LOCALE) ? @fallback : load_rb(@locale)
        @root = nil
      end

      def self.load_rb(locale)
        loc = locale.to_s
        mt = :"locale_#{loc.tr('-', '_')}"
        mt = mt.to_s.downcase.to_sym

        return send(mt) if respond_to?(mt)

        debug_proc.call("locale_method_missing: #{mt}", :missing) if debug_proc
        {}
      rescue => e
        debug_proc.call("locale_method_error(#{mt}): #{e.message}", :error) if debug_proc
        {}
      end

      def self.debug_proc
        return nil unless defined?(Debug) && Debug.enabled
        proc { |info, kind| Debug.log(self, :lang, "#{kind}: #{info} (locale=#{@locale})") }
      end

      def self.deep_stringify(obj)
        case obj
        when Hash
          obj.each_with_object({}) { |(k, v), h| h[k.to_s] = deep_stringify(v) }
        when Array
          obj.map { |v| deep_stringify(v) }
        else
          obj
        end
      end

      def self.format_update_date
        parts = INFO_UPDATE.to_s.split("-").map(&:to_i)
        return INFO_UPDATE unless parts.length == 3 && parts[0] > 0

        year, month, day = parts
        name = month_name(Time.mktime(year, month, day), :long)

        case @locale
        when "es-ES"
          "#{day} de #{name} de #{year}"
        else
          "#{name} #{day}, #{year}"
        end
      rescue
        INFO_UPDATE
      end

      private_class_method :deep_stringify
      private_class_method :debug_proc
      private_class_method :load_rb
      private_class_method :load_locale_files
      private_class_method :format_update_date
      private_class_method :ensure_loaded

      def self.month_name(time, format = :long)
        idx  = time.month - 1
        pool = format == :short ? MONTH_NAMES_SHORT : MONTH_NAMES_LONG
        (pool[@locale] || pool[DEFAULT_LOCALE])[idx]
      end

    end # module Lang
  end # module FaceUp
end # module ASM_Extensions
