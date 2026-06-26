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
        status_both_sides
        no_faces
        invalid_length
      ].freeze

      SUMMON_FACES_KEYS = %i[
        no_edges
        no_selection
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

      def test_all_tools_faceup_keys_resolve_in_en_us
        Lang.configure("en-US")
        TOOLS_KEYS.each do |key|
          result = Lang.t(:tools, :faceup, key)
          refute_match(/missing:/, result, "en-US missing key: tools.faceup.#{key}")
          refute result.empty?, "en-US tools.faceup.#{key} should not be empty"
        end
      end

      def test_all_tools_faceup_keys_resolve_in_es_es
        Lang.configure("es-ES")
        TOOLS_KEYS.each do |key|
          result = Lang.t(:tools, :faceup, key)
          refute_match(/missing:/, result, "es-ES missing key: tools.faceup.#{key}")
          refute result.empty?, "es-ES tools.faceup.#{key} should not be empty"
        end
      end

      # --- Return type ---

      def test_lang_t_returns_string_for_vcb_label
        Lang.configure("en-US")
        result = Lang.t(:tools, :faceup, :vcb_label)
        assert_instance_of String, result
      end

      # --- Translations are actually different between locales ---

      def test_vcb_label_differs_between_locales
        Lang.configure("en-US")
        en = Lang.t(:tools, :faceup, :vcb_label)
        Lang.configure("es-ES")
        es = Lang.t(:tools, :faceup, :vcb_label)
        refute_equal en, es, "vcb_label should differ between en-US and es-ES"
      end

      def test_status_flipped_differs_between_locales
        Lang.configure("en-US")
        en = Lang.t(:tools, :faceup, :status_flipped)
        Lang.configure("es-ES")
        es = Lang.t(:tools, :faceup, :status_flipped)
        refute_equal en, es, "status_flipped should differ between en-US and es-ES"
      end

      def test_status_idle_differs_between_locales
        Lang.configure("en-US")
        en = Lang.t(:tools, :faceup, :status_idle)
        Lang.configure("es-ES")
        es = Lang.t(:tools, :faceup, :status_idle)
        refute_equal en, es, "status_idle should differ between en-US and es-ES"
      end

      # --- Content sanity ---

      def test_status_flipped_en_contains_flipped
        Lang.configure("en-US")
        assert_match(/FLIPPED/i, Lang.t(:tools, :faceup, :status_flipped))
      end

      def test_status_flipped_es_contains_invertido
        Lang.configure("es-ES")
        assert_match(/INVERTIDO/i, Lang.t(:tools, :faceup, :status_flipped))
      end

      # --- tools.summon_faces keys ---

      def test_all_tools_summon_faces_keys_resolve_in_en_us
        Lang.configure("en-US")
        SUMMON_FACES_KEYS.each do |key|
          result = Lang.t(:tools, :summon_faces, key)
          refute_match(/missing:/, result, "en-US missing key: tools.summon_faces.#{key}")
          refute result.empty?, "en-US tools.summon_faces.#{key} should not be empty"
        end
      end

      def test_all_tools_summon_faces_keys_resolve_in_es_es
        Lang.configure("es-ES")
        SUMMON_FACES_KEYS.each do |key|
          result = Lang.t(:tools, :summon_faces, key)
          refute_match(/missing:/, result, "es-ES missing key: tools.summon_faces.#{key}")
          refute result.empty?, "es-ES tools.summon_faces.#{key} should not be empty"
        end
      end

      def test_en_us_tools_summon_faces_has_all_keys
        summon = Lang.locale_en_us[:tools][:summon_faces]
        SUMMON_FACES_KEYS.each do |key|
          assert summon.key?(key), "en-US tools.summon_faces missing key: #{key}"
        end
      end

      def test_es_es_tools_summon_faces_has_all_keys
        summon = Lang.locale_es_es[:tools][:summon_faces]
        SUMMON_FACES_KEYS.each do |key|
          assert summon.key?(key), "es-ES tools.summon_faces missing key: #{key}"
        end
      end

      def test_summon_faces_keys_differ_between_locales
        SUMMON_FACES_KEYS.each do |key|
          Lang.configure("en-US")
          en = Lang.t(:tools, :summon_faces, key)
          Lang.configure("es-ES")
          es = Lang.t(:tools, :summon_faces, key)
          refute_equal en, es, "tools.summon_faces.#{key} should differ between locales"
        end
      end

      # --- tools section is present in raw locale hashes ---

      def test_en_us_raw_hash_has_tools_key
        assert Lang.locale_en_us.key?(:tools), "en-US locale hash should have :tools key"
      end

      def test_es_es_raw_hash_has_tools_key
        assert Lang.locale_es_es.key?(:tools), "es-ES locale hash should have :tools key"
      end

      def test_en_us_tools_faceup_has_all_keys
        faceup = Lang.locale_en_us[:tools][:faceup]
        TOOLS_KEYS.each do |key|
          assert faceup.key?(key), "en-US tools.faceup missing key: #{key}"
        end
      end

      def test_es_es_tools_faceup_has_all_keys
        faceup = Lang.locale_es_es[:tools][:faceup]
        TOOLS_KEYS.each do |key|
          assert faceup.key?(key), "es-ES tools.faceup missing key: #{key}"
        end
      end

    end
  end
end
