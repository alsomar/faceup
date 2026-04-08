# frozen_string_literal: true

module ASM_Extensions
  module FaceUp
    module Lang
      def self.locale_es_es
        {
          commands: {
            summonfaces: {
              label:   "Invocar Caras",
              tooltip: "Invocar Caras",
              status:  "Genera caras para las aristas seleccionadas y las orienta hacia arriba."
            },
            extruder: {
              label:   "Extrusor",
              tooltip: "Extrusor",
              status:  "Genera volúmenes sólidos a partir de caras seleccionadas usando una longitud definida por el usuario."
            },
            turbo: {
              label:   "Invocar + Extrusor",
              tooltip: "Invocar + Extrusor",
              status:  "Ejecuta Invocar Caras seguido de Extrusor."
            },
            settings: {
              label:   "Ajustes de #{EXT_NAME}",
              tooltip: "Ajustes de #{EXT_NAME}",
              status:  "Abrir los ajustes de #{EXT_NAME}."
            }
          },

          html: {
            settings: {
              title:              "Ajustes",
              tooltip:            "Ajustes",
              dark_mode_tooltip:  "Cambiar a modo claro",
              light_mode_tooltip: "Cambiar a modo oscuro",
              second_tab:         "Opciones de prueba",
              test_button_1:      "Opción de prueba 1",
              test_button_2:      "Opción de prueba 2",
              test_button_3:      "Opción de prueba 3",
              extruder_options:       "Opciones del extrusor",
              use_last_extrusion:     "Usar última extrusión como valor inicial",
              default_extrusion:      "Valor de extrusión por defecto",
              unit_model:             "Unidades del modelo",
              unit_mm:                "Milímetros",
              unit_cm:                "Centímetros",
              unit_m:                 "Metros",
              unit_inch:              "Pulgadas",
              unit_feet:              "Pies",
              general_options:        "Opciones generales",
              language_selection: "Selección de idioma",
              language_hint:      "Puede ser necesario reiniciar SketchUp para aplicar los ajustes de idioma.",
              system_language:    "(idioma del sistema)",
              context_menu:       "Mostrar menú contextual",
              reset_button:       "Mostrar botón de reinicio",
              reset_settings:     "Restablecer ajustes",
              reset_confirm_body: "Esto restablecerá todos los ajustes a sus valores predeterminados. ¿Estás seguro?",
              reset_confirm_yes:  "Sí, restablecer",
              reset_confirm_no:   "Cancelar"
            },
            about: {
              title:       "Info",
              tooltip:     "Info",
              version:     "Versión ",
              designed_by: "Diseñado y desarrollado por #{LINK_ALEJANDRO}.",
              uses:        "Esta extensión utiliza #{LINK_MODUS}.",
              warning:     "<b>¡#{EXT_NAME} es gratis!</b> Confía sólo en #{LINK_EXT_WAREHOUSE} y #{LINK_SKETCHUCATION} para descargarlo de forma segura."
            },
            thanks: {
              title:   "Gracias",
              tooltip: "Gracias",
              txt1:    "Gracias a las comunidades de #{LINK_SKP_FORUMS} y #{LINK_SUC_FORUMS} por compartir su conocimiento y tender la mano a nuevos desarrolladores.",
              txt2:    "El apoyo de la comunidad es lo que hace posible proyectos como #{EXT_NAME}. Si puedes, considera contribuir a través de #{LINK_PATREON} o #{LINK_KOFI}.",
              txt3:    "¡Gracias por tu generosidad!",
              txt4:    "Atentamente,"
            },
            buttons: {
              save_settings:  "Guardar ajustes",
              settings_saved: "Ajustes guardados"
            }
          }

        }.freeze
      end
    end
  end
end
