# frozen_string_literal: true

require 'testup/testcase'

module ASM_Extensions
  module FaceUp
    class TC_dump < TestUp::TestCase

      HTML_INFO_KEYS = %w[name author version update copyright].freeze

      def setup
        Sketchup.require 'asm_faceup/lang/i18n'
        Sketchup.require 'asm_faceup/lang/locales/en_us'
        Sketchup.require 'asm_faceup/lang/locales/es_es'
        @original_locale = Lang.locale
        Lang.configure("en-US")
      end

      def teardown
        Lang.configure(@original_locale)
      end

      # --- Return type ---

      def test_dump_returns_hash
        assert_instance_of Hash, Lang.dump
      end

      # --- All keys are strings (deep_stringify) ---

      def test_dump_has_no_symbol_keys
        assert_no_symbol_keys(Lang.dump)
      end

      # --- Top-level structure ---

      def test_dump_has_html_key
        assert Lang.dump.key?("html"), "dump should have 'html' key"
      end

      def test_dump_has_months_long
        assert Lang.dump.key?("months_long"), "dump should have 'months_long' key"
      end

      def test_dump_has_months_short
        assert Lang.dump.key?("months_short"), "dump should have 'months_short' key"
      end

      # --- html.info contract ---

      def test_dump_html_info_exists
        assert Lang.dump["html"].key?("info"), "dump['html'] should have 'info' key"
      end

      def test_dump_html_info_has_all_keys
        info = Lang.dump["html"]["info"]
        HTML_INFO_KEYS.each do |key|
          assert info.key?(key), "html.info missing key: #{key}"
        end
      end

      def test_dump_html_info_values_are_non_empty_strings
        info = Lang.dump["html"]["info"]
        HTML_INFO_KEYS.each do |key|
          val = info[key]
          assert_instance_of String, val, "html.info.#{key} should be a String"
          refute val.empty?, "html.info.#{key} should not be empty"
        end
      end

      # --- months arrays ---

      def test_dump_months_long_has_12_entries
        assert_equal 12, Lang.dump["months_long"].length
      end

      def test_dump_months_short_has_12_entries
        assert_equal 12, Lang.dump["months_short"].length
      end

      def test_dump_months_are_non_empty_strings
        dump = Lang.dump
        (dump["months_long"] + dump["months_short"]).each_with_index do |m, i|
          assert_instance_of String, m, "Month entry #{i} should be a String"
          refute m.empty?, "Month entry #{i} should not be empty"
        end
      end

      # --- Locale affects output ---

      def test_dump_months_differ_by_locale
        dump_en = Lang.dump
        Lang.configure("es-ES")
        dump_es = Lang.dump
        refute_equal dump_en["months_long"], dump_es["months_long"],
          "months_long should differ between en-US and es-ES"
      end

      # --- format_update_date ---

      def test_format_update_date_en_us
        Lang.configure("en-US")
        update = Lang.dump["html"]["info"]["update"]
        assert_instance_of String, update
        refute update.empty?
      end

      def test_format_update_date_es_es
        Lang.configure("es-ES")
        update = Lang.dump["html"]["info"]["update"]
        assert_instance_of String, update
        refute update.empty?
      end

      def test_format_update_date_differs_by_locale
        Lang.configure("en-US")
        update_en = Lang.dump["html"]["info"]["update"]
        Lang.configure("es-ES")
        update_es = Lang.dump["html"]["info"]["update"]
        refute_equal update_en, update_es,
          "update date format should differ between en-US and es-ES"
      end

      private

      def assert_no_symbol_keys(obj, path = "root")
        case obj
        when Hash
          obj.each do |k, v|
            assert_instance_of String, k, "Symbol key found at #{path}: #{k.inspect}"
            assert_no_symbol_keys(v, "#{path}.#{k}")
          end
        when Array
          obj.each_with_index { |v, i| assert_no_symbol_keys(v, "#{path}[#{i}]") }
        end
      end

    end
  end
end
