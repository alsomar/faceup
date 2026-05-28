# frozen_string_literal: true

require 'testup/testcase'

module ASM_Extensions
  module FaceUp
    class TC_config < TestUp::TestCase

      EXPECTED_KEYS = %i[
        settings_test1 settings_test2 settings_test3
        use_last_extrusion default_extrusion align_to_min_bb
        language context_menu dark_mode debug_mode
      ].freeze

      # Keys sent by the frontend's currentSettings() — debug_mode is excluded intentionally
      FRONTEND_KEYS = (EXPECTED_KEYS - %i[debug_mode]).freeze

      # --- DEFAULT_CONFIG ---

      def test_default_config_is_frozen
        assert DEFAULT_CONFIG.frozen?
      end

      def test_default_config_has_all_expected_keys
        EXPECTED_KEYS.each do |key|
          assert DEFAULT_CONFIG.key?(key), "Missing key: #{key}"
        end
      end

      def test_default_config_boolean_values
        bool_keys = %i[
          settings_test1 settings_test2 settings_test3
          use_last_extrusion context_menu dark_mode debug_mode
        ]
        bool_keys.each do |key|
          val = DEFAULT_CONFIG[key]
          assert [true, false].include?(val), "#{key} should be boolean, got #{val.class}"
        end
      end

      def test_default_config_default_extrusion_is_numeric
        val = DEFAULT_CONFIG[:default_extrusion]
        assert val.is_a?(Numeric), "default_extrusion should be Numeric, got #{val.class}"
      end

      def test_default_config_language_is_string
        assert_instance_of String, DEFAULT_CONFIG[:language]
      end

      def test_default_config_language_is_auto
        assert_equal "auto", DEFAULT_CONFIG[:language]
      end

      def test_frontend_keys_match_default_config
        FRONTEND_KEYS.each do |key|
          assert DEFAULT_CONFIG.key?(key), "DEFAULT_CONFIG missing frontend key: #{key}"
        end
        assert_equal FRONTEND_KEYS.sort, (DEFAULT_CONFIG.keys - %i[debug_mode]).sort,
          "Mismatch between frontend keys and DEFAULT_CONFIG keys (excluding debug_mode)"
      end

      # --- user_settings ---

      def test_user_settings_noop_when_unchanged
        current = FaceUp.load_config
        content_before = File.read(CONFIG_FILE)
        FaceUp.user_settings(current)
        content_after = File.read(CONFIG_FILE)
        assert_equal content_before, content_after, "user_settings should not write when nothing changed"
      end

      def test_user_settings_ignores_unknown_keys
        FaceUp.user_settings({ unknown_xyz: "injected" })
        result = FaceUp.load_config
        refute result.key?(:unknown_xyz), "user_settings should not save unknown keys"
      end

      # --- ensure_config ---

      def test_ensure_config_creates_file_if_missing
        FileUtils.rm_f(CONFIG_FILE)
        refute File.exist?(CONFIG_FILE), "Config file should be absent before test"
        FaceUp.ensure_config
        assert File.exist?(CONFIG_FILE), "ensure_config should create the config file"
      end

      # --- load_config ---

      def test_load_config_returns_hash
        result = load_config
        assert_instance_of Hash, result
      end

      def test_load_config_includes_all_default_keys
        result = load_config
        EXPECTED_KEYS.each do |key|
          assert result.key?(key), "load_config missing key: #{key}"
        end
      end

      def test_load_config_symbolizes_keys
        result = load_config
        result.each_key do |key|
          assert_instance_of Symbol, key, "Key #{key.inspect} should be a Symbol"
        end
      end

      private

      def setup
        @config_backup = File.exist?(CONFIG_FILE) ? File.read(CONFIG_FILE) : nil
      end

      def teardown
        if @config_backup
          File.write(CONFIG_FILE, @config_backup)
          CONFIG.replace(JSON.parse(@config_backup, symbolize_names: true))
        else
          FileUtils.rm_f(CONFIG_FILE)
        end
      end

      def load_config
        FaceUp.load_config
      end

    end
  end
end
