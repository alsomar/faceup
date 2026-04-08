# frozen_string_literal: true

module ASM_Extensions
  module FaceUp
    module Lang
      def self.locale_en_us
        {
          commands: {
            summonfaces: {
              label:   "Summon Faces",
              tooltip: "Summon Faces",
              status:  "Generates faces for selected edges and orients them to face up."
            },
            extruder: {
              label:   "Extruder",
              tooltip: "Extruder",
              status:  "Generates solid volumes from selected faces using a user-defined length."
            },
            turbo: {
              label:   "Summon + Extruder",
              tooltip: "Summon + Extruder",
              status:  "Runs Summon Faces followed by Extruder."
            },
            settings: {
              label:   "#{EXT_NAME} Settings",
              tooltip: "#{EXT_NAME} Settings",
              status:  "Open #{EXT_NAME} settings."
            }
          },

          html: {
            settings: {
              title:              "Settings",
              tooltip:            "Settings",
              dark_mode_tooltip:  "Switch to light mode",
              light_mode_tooltip: "Switch to dark mode",
              second_tab:         "Test Options",
              test_button_1:      "Test Option 1",
              test_button_2:      "Test Option 2",
              test_button_3:      "Test Option 3",
              extruder_options:       "Extruder Options",
              use_last_extrusion:     "Use last extrusion as initial value",
              default_extrusion:      "Default extrusion value",
              unit_model:             "Model units",
              unit_mm:                "Millimeters",
              unit_cm:                "Centimeters",
              unit_m:                 "Meters",
              unit_inch:              "Inches",
              unit_feet:              "Feet",
              general_options:        "General Options",
              language_selection: "Language selection",
              language_hint:      "You may need to restart SketchUp to update the language settings.",
              system_language:    "(system language)",
              context_menu:       "Display context menu",
              reset_button:       "Show reset button",
              reset_settings:     "Reset settings",
              reset_confirm_body: "This will reset all settings to their default values. Are you sure?",
              reset_confirm_yes:  "Yes, reset",
              reset_confirm_no:   "Cancel"
            },
            about: {
              title:       "Info",
              tooltip:     "Info",
              version:     "Version ",
              designed_by: "Designed and developed by #{LINK_ALEJANDRO}.",
              uses:        "This extension uses #{LINK_MODUS}.",
              warning:     "<b>#{EXT_NAME} is free!</b> Trust only #{LINK_EXT_WAREHOUSE} and #{LINK_SKETCHUCATION} to download it."
            },
            thanks: {
              title:   "Thanks",
              tooltip: "Thanks",
              txt1:    "Thanks to the developer communities at #{LINK_SKP_FORUMS} and #{LINK_SUC_FORUMS} for sharing their knowledge and lending a hand to new developers.",
              txt2:    "Community support is what makes independent projects like #{EXT_NAME} possible. If you can, please consider making a contribution through #{LINK_PATREON} or #{LINK_KOFI}. Thank you so much in advance!",
              txt3:    "Thank you for your generosity!",
              txt4:    "Sincerely,"
            },
            buttons: {
              save_settings:  "Save Settings",
              settings_saved: "Settings Saved"
            }
          },

          tools: {
            extruder: {
              vcb_label:      "Length: ",
              status_idle:    "Extruder: Enter distance or click to set origin | Tab to flip direction | Enter/DblClick to confirm | Space to cancel",
              status_pick:    "Extruder: Click to set distance | Tab to flip direction | ESC to reset origin | Space to cancel",
              status_adjust:  "Extruder: Click to adjust | Tab to flip direction | Enter/DblClick to confirm | ESC to reset origin | Space to cancel",
              status_flipped: " [FLIPPED]",
              no_faces:       "No faces selected.",
              invalid_length: "Invalid length. Please enter a valid distance.",
            }
          }

        }.freeze

      end
    end
  end
end
