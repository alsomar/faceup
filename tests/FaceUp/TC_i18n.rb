# frozen_string_literal: true

require 'testup/testcase'

module ASM_Extensions
  module FaceUp
    class TC_i18n < TestUp::TestCase

      def setup
        Sketchup.require 'asm_faceup/lang/i18n'
        Sketchup.require 'asm_faceup/lang/locales/en_us'
        Sketchup.require 'asm_faceup/lang/locales/es_es'
        @original_locale = Lang.locale
      end

      def teardown
        Lang.configure(@original_locale)
      end

      # --- Leaf ---

      def test_leaf_returns_value
        leaf = Lang::Leaf.new([:foo], "hello", "fallback")
        assert_equal "hello", leaf.to_s
      end

      def test_leaf_falls_back_when_value_nil
        leaf = Lang::Leaf.new([:foo], nil, "fallback")
        assert_equal "fallback", leaf.to_s
      end

      def test_leaf_shows_missing_marker_when_both_nil
        leaf = Lang::Leaf.new([:foo, :bar], nil, nil)
        assert_match(/missing: foo\.bar/, leaf.to_s)
      end

      def test_leaf_to_str_equals_to_s
        leaf = Lang::Leaf.new([:x], "val", nil)
        assert_equal leaf.to_s, leaf.to_str
      end

      # --- Node ---

      def test_node_returns_leaf_for_scalar_value
        node = Lang::Node.new([], { greeting: "hi" }, {}, nil)
        assert_instance_of Lang::Leaf, node[:greeting]
      end

      def test_node_returns_node_for_nested_hash
        node = Lang::Node.new([], { section: { key: "val" } }, {}, nil)
        assert_instance_of Lang::Node, node[:section]
      end

      def test_node_dot_notation
        node = Lang::Node.new([], { title: "FaceUp" }, {}, nil)
        assert_equal "FaceUp", node.title.to_s
      end

      def test_node_uses_fallback_for_missing_key
        node = Lang::Node.new([], {}, { missing_key: "fb" }, nil)
        assert_equal "fb", node[:missing_key].to_s
      end

      def test_node_deep_traversal
        data = { a: { b: { c: "deep" } } }
        node = Lang::Node.new([], data, {}, nil)
        assert_equal "deep", node.a.b.c.to_s
      end

      # --- Lang.configure ---

      def test_configure_accepts_valid_locale
        Lang.configure("es-ES")
        assert_equal "es-ES", Lang.locale
      end

      def test_configure_falls_back_for_invalid_locale
        Lang.configure("xx-XX")
        assert_equal Lang::DEFAULT_LOCALE, Lang.locale
      end

      def test_configure_falls_back_for_empty_string
        Lang.configure("")
        assert_equal Lang::DEFAULT_LOCALE, Lang.locale
      end

      def test_configure_handles_auto
        Lang.configure("auto")
        assert_includes Lang::AVAILABLE_LOCALES, Lang.locale
      end

      def test_configure_returns_true
        result = Lang.configure("en-US")
        assert_equal true, result
      end

      # --- Lang.t ---

      def test_t_returns_string
        Lang.configure("en-US")
        result = Lang.t(:commands, :summonfaces, :label)
        assert_instance_of String, result
        refute_empty result
      end

      def test_t_missing_key_returns_marker
        Lang.configure("en-US")
        result = Lang.t(:nonexistent_key_xyz)
        assert_match(/missing:/, result)
      end

      # --- Lang.month_name ---

      def test_month_name_returns_long_format_by_default
        Lang.configure("en-US")
        assert_equal "January", Lang.month_name(Time.mktime(2024, 1, 1))
      end

      def test_month_name_returns_short_format
        Lang.configure("en-US")
        assert_equal "Jan", Lang.month_name(Time.mktime(2024, 1, 1), :short)
      end

      def test_month_name_localizes_for_es_es
        Lang.configure("es-ES")
        assert_equal "enero",     Lang.month_name(Time.mktime(2024, 1, 1))
        assert_equal "diciembre", Lang.month_name(Time.mktime(2024, 12, 1))
      end

      def test_month_name_covers_all_12_months
        Lang.configure("en-US")
        (1..12).each do |month|
          result = Lang.month_name(Time.mktime(2024, month, 1))
          assert_instance_of String, result, "Month #{month} should return a String"
          refute_empty result, "Month #{month} should not be empty"
        end
      end

    end
  end
end
