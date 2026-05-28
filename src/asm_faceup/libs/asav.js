let DEBUG_MODE = false;
window.APP_I18N = window.APP_I18N || { locale: 'en-US', data: {} };

// Cross-extension dark-mode sync. localStorage is shared across UI::HtmlDialog
// webviews in the same SketchUp profile, so we use a single shared key to keep
// every asav.* dialog in lockstep:
//   - hydration prefers the stored value over the per-extension config (so
//     opening FaceUp after toggling Stacks picks up dark mode — and the Vue
//     darkMode prop stays in sync with body.dark-mode, fixing the "dark page
//     + sun icon" mismatch),
//   - the per-extension config is still the persistent fallback (used on
//     fresh installs / cleared localStorage),
//   - a "storage" listener flips open dialogs live when any extension
//     toggles dark mode.
const DARK_MODE_KEY = 'asav_dark_mode';

function readDarkModeFromStorage() {
  try {
    const v = localStorage.getItem(DARK_MODE_KEY);
    return v === null ? null : v === 'true';
  } catch (_) {
    return null;
  }
}

let DARK_MODE_SYNC_WIRED = false;
function wireDarkModeSync() {
  if (DARK_MODE_SYNC_WIRED) return;
  DARK_MODE_SYNC_WIRED = true;
  window.addEventListener('storage', function (e) {
    if (e.key !== DARK_MODE_KEY) return;
    const next = e.newValue === 'true';
    if (window.app && window.app.darkMode !== next) {
      window.app.darkMode = next;   // watcher updates body class + tooltip + icon
    }
  });
}

// Debug Icon
function updateDebugIcon(isDebug) {
  const icon = document.getElementById("settings-icon");
  if (!icon) return;

  icon.classList.remove("text-trimble-yellow");

  if (isDebug) {
    icon.classList.add("text-trimble-yellow");
  }
}

// Debug State
function updateDebugState(isDebug) {
  const nextState = !!isDebug;
  if (DEBUG_MODE === nextState) {
    return;
  }

  DEBUG_MODE = nextState;

  if (window.app) {
    window.app.debugMode = DEBUG_MODE;
  }

  updateDebugIcon(DEBUG_MODE);

  if (DEBUG_MODE) {
    console.log("[DEBUG] JS debug mode is now ON");
  } else {
    console.log("[DEBUG] JS debug mode is now OFF");
  }
}

// Ruby → JS (settings)
function settingsJSON(config) {
  try {
    if (typeof config === "string") {
      config = JSON.parse(config);
    }

    if (window.app) {
      window._settingsLoading = true;

      window.app.settingsTest1       = config.settings_test1;
      window.app.settingsTest2       = config.settings_test2;
      window.app.settingsTest3       = config.settings_test3;
      window.app.settingsLanguage    = config.language;
      window.app.settingsContextMenu = config.context_menu;
      // darkMode: localStorage (cross-extension live state) wins; the
      // per-extension config.dark_mode is the persistent fallback.
      const lsDark = readDarkModeFromStorage();
      window.app.darkMode            = lsDark !== null ? lsDark : !!config.dark_mode;
      window.app.debugMode           = config.debug_mode;

      wireDarkModeSync();

      if (typeof window.onExtensionSettings === "function") {
        window.onExtensionSettings(config);
      }

      window.app.$nextTick(() => {
        window._settingsLoading = false;
        window.app.appReady = true;
      });
    }

    updateDebugState(config.debug_mode);

    // Update the baseline AFTER loading the real config
    window.app.initialSettings = JSON.stringify(window.app.currentSettings());

  } catch (e) {
    console.error("settingsJSON failed:", e, config);
  }
}

// Ruby → JS (i18n)
function i18nJSON(jsonStr) {
  try {
    const payload = JSON.parse(jsonStr);
    window.APP_I18N = payload || window.APP_I18N;

    if (window.app) {
      window.app.i18nLocale = window.APP_I18N.locale || 'en-US';
      window.app.i18nData   = window.APP_I18N.data   || {};
      window.app.i18nReady  = true;
    }
  } catch (e) {
    console.error("i18nJSON parse error:", e);
  }
}

// Debug Trigger
function debugTrigger() {
  const settingsLink = document.getElementById("settings-nav");
  if (!settingsLink) return;

  let clickCount = 0;
  let timer      = null;

  const REQUIRED_CLICKS = 5;
  const TIME_WINDOW_MS  = 1000;

  settingsLink.addEventListener("click", () => {
    clickCount++;

    if (clickCount === REQUIRED_CLICKS) {
      const newState = !DEBUG_MODE;

      updateDebugState(newState);

      if (window.sketchup && typeof sketchup.user_settings === "function") {
        const payload = JSON.stringify({ debug_mode: newState });
        sketchup.user_settings(payload);
      }

      resetSequence();
      return;
    }

    if (!timer) {
      timer = setTimeout(() => {
        resetSequence();
      }, TIME_WINDOW_MS);
    }
  });

  function resetSequence() {
    clickCount = 0;

    if (timer) {
      clearTimeout(timer);
      timer = null;
    }
  }
}

// Debug Loader
function debugLoader() {
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      debugTrigger();
      contextMenu();
    });
  } else {
    debugTrigger();
    contextMenu();
  }
}

// Context menu control (enabled only in debug mode)
function contextMenu() {
  document.addEventListener("contextmenu", function (event) {
    if (!DEBUG_MODE) {
      event.preventDefault();
    }
  });
}

// Persist which accordion panel is open
const ACCORDION_KEY = "faceup:last_open_accordion";
const ACCORDION_ROOT_SEL = "#accordionSettings";
const DEFAULT_PANEL_ID = "collapseTab1";

function getSavedAccordionId() {
  try {
    return localStorage.getItem(ACCORDION_KEY);
  } catch (_) {
    return null;
  }
}

function setSavedAccordionId(id) {
  try {
    localStorage.setItem(ACCORDION_KEY, id);
  } catch (_) {}
}

function clearSavedAccordionId() {
  try {
    localStorage.removeItem(ACCORDION_KEY);
  } catch (_) {}
}

function openAccordionPanelById(id, animate = true) {
  const targetId = (id && document.getElementById(id)) ? id : DEFAULT_PANEL_ID;

  if (animate) {
    $("#" + targetId).collapse("show");
  } else {
    $(ACCORDION_ROOT_SEL + " .collapse")
      .removeClass("show");
    $(ACCORDION_ROOT_SEL + " [data-toggle='collapse']")
      .addClass("collapsed")
      .attr("aria-expanded", "false");

    $("#" + targetId).addClass("show");
    $('[data-target="#' + targetId + '"]')
      .removeClass("collapsed")
      .attr("aria-expanded", "true");
  }
}

let ACCORDION_WIRED = false;

function wireAccordionPersistence() {
  const $root = $(ACCORDION_ROOT_SEL);
  if (!$root.length) return;

  if (ACCORDION_WIRED) {
    const savedId = getSavedAccordionId();
    openAccordionPanelById(savedId, false);
    return;
  }

  $root.off("shown.bs.collapse.asavPersist");
  $root.off("hidden.bs.collapse.asavPersist");

  const savedId = getSavedAccordionId();
  openAccordionPanelById(savedId, false);

  $root.on("shown.bs.collapse.asavPersist", ".collapse", function () {
    setSavedAccordionId(this.id);
  });

  $root.on("hidden.bs.collapse.asavPersist", ".collapse", function () {
    const anyOpen = $root.find(".collapse.show").length > 0;
    if (!anyOpen) clearSavedAccordionId();
  });

  ACCORDION_WIRED = true;
}

debugLoader();
