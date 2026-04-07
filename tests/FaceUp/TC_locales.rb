# frozen_string_literal: true

require 'testup/testcase'

module ASM_Extensions
  module FaceUp
    class TC_locales < TestUp::TestCase

      def setup
        Sketchup.require 'asm_faceup/lang/locales/en_us'
        Sketchup.require 'asm_faceup/lang/locales/es_es'
      end

      # --- Locale completeness ---

      def test_es_es_has_same_keys_as_en_us
        ref  = flatten_keys(Lang.locale_en_us)
        test = flatten_keys(Lang.locale_es_es)
        missing = ref - test
        extra   = test - ref
        assert missing.empty?, "es-ES missing keys: #{missing.join(', ')}"
        assert extra.empty?,   "es-ES has extra keys: #{extra.join(', ')}"
      end

      # --- Locale values are non-empty strings ---

      def test_en_us_values_are_non_empty_strings
        assert_no_empty_values(Lang.locale_en_us, "en-US")
      end

      def test_es_es_values_are_non_empty_strings
        assert_no_empty_values(Lang.locale_es_es, "es-ES")
      end

      # --- Locale methods exist ---

      def test_en_us_method_exists
        assert Lang.respond_to?(:locale_en_us)
      end

      def test_es_es_method_exists
        assert Lang.respond_to?(:locale_es_es)
      end

      # --- Locale returns frozen hash ---

      def test_en_us_is_frozen
        assert Lang.locale_en_us.frozen?
      end

      def test_es_es_is_frozen
        assert Lang.locale_es_es.frozen?
      end

      private

      def flatten_keys(hash, prefix = nil)
        hash.each_with_object([]) do |(k, v), keys|
          full_key = prefix ? "#{prefix}.#{k}" : k.to_s
          if v.is_a?(Hash)
            keys.concat(flatten_keys(v, full_key))
          else
            keys << full_key
          end
        end
      end

      def assert_no_empty_values(hash, locale_name, prefix = nil)
        hash.each do |k, v|
          full_key = prefix ? "#{prefix}.#{k}" : k.to_s
          if v.is_a?(Hash)
            assert_no_empty_values(v, locale_name, full_key)
          else
            assert v.is_a?(String), "[#{locale_name}] #{full_key} is not a String (#{v.class})"
            refute v.empty?, "[#{locale_name}] #{full_key} is an empty string"
          end
        end
      end

    end
  end
end
