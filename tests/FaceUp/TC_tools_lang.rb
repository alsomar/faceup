# frozen_string_literal: true

require 'testup/testcase'

module ASM_Extensions
  module FaceUp
    class TC_tools_lang < TestUp::TestCase

      TOOLS_KEYS = %i[
        vcb_label
        status_idle
        status_pick
        status_adjust
        status_flipped
        no_faces
        invalid_length
      ].freeze

      def setup
        Sketchup.require 'asm_faceup/lang/i18n'
        Sketchup.require 'asm_faceup/lang/locales/en_us'
        Sketchup.require 'asm_faceup/lang/locales/es_es'
        @original_locale = Lang.locale
      end

      def teardown
        Lang.configure(@original_locale)
      end

      # --- Key presence via Lang.t ---

      def test_all_tools_extruder_keys_resolve_in_en_us
        Lang.configure("en-US")
        TOOLS_KEYS.each do |key|
          result = Lang.t(:tools, :extruder, key)
          refute_match(/missing:/, result, "en-US missing key: tools.extruder.#{key}")
          refute result.empty?, "en-US tools.extruder.#{key} should not be empty"
        end
      end

      def test_all_tools_extruder_keys_resolve_in_es_es
        Lang.configure("es-ES")
        TOOLS_KEYS.each do |key|
          result = Lang.t(:tools, :extruder, key)
          refute_match(/missing:/, result, "es-ES missing key: tools.extruder.#{key}")
          refute result.empty?, "es-ES tools.extruder.#{key} should not be empty"
        end
      end

      # --- Return type ---

      def test_lang_t_returns_string_for_vcb_label
        Lang.configure("en-US")
        result = Lang.t(:tools, :extruder, :vcb_label)
        assert_instance_of String, result
      end

      # --- Translations are actually different between locales ---

      def test_vcb_label_differs_between_locales
        Lang.configure("en-US")
        en = Lang.t(:tools, :extruder, :vcb_label)
        Lang.configure("es-ES")
        es = Lang.t(:tools, :extruder, :vcb_label)
        refute_equal en, es, "vcb_label should differ between en-US and es-ES"
      end

      def test_status_flipped_differs_between_locales
        Lang.configure("en-US")
        en = Lang.t(:tools, :extruder, :status_flipped)
        Lang.configure("es-ES")
        es = Lang.t(:tools, :extruder, :status_flipped)
        refute_equal en, es, "status_flipped should differ between en-US and es-ES"
      end

      def test_status_idle_differs_between_locales
        Lang.configure("en-US")
        en = Lang.t(:tools, :extruder, :status_idle)
        Lang.configure("es-ES")
        es = Lang.t(:tools, :extruder, :status_idle)
        refute_equal en, es, "status_idle should differ between en-US and es-ES"
      end

      # --- Content sanity ---

      def test_status_flipped_en_contains_flipped
        Lang.configure("en-US")
        assert_match(/FLIPPED/i, Lang.t(:tools, :extruder, :status_flipped))
      end

      def test_status_flipped_es_contains_invertido
        Lang.configure("es-ES")
        assert_match(/INVERTIDO/i, Lang.t(:tools, :extruder, :status_flipped))
      end

      # --- tools section is present in raw locale hashes ---

      def test_en_us_raw_hash_has_tools_key
        assert Lang.locale_en_us.key?(:tools), "en-US locale hash should have :tools key"
      end

      def test_es_es_raw_hash_has_tools_key
        assert Lang.locale_es_es.key?(:tools), "es-ES locale hash should have :tools key"
      end

      def test_en_us_tools_extruder_has_all_keys
        extruder = Lang.locale_en_us[:tools][:extruder]
        TOOLS_KEYS.each do |key|
          assert extruder.key?(key), "en-US tools.extruder missing key: #{key}"
        end
      end

      def test_es_es_tools_extruder_has_all_keys
        extruder = Lang.locale_es_es[:tools][:extruder]
        TOOLS_KEYS.each do |key|
          assert extruder.key?(key), "es-ES tools.extruder missing key: #{key}"
        end
      end

    end
  end
end
