let DEBUG_MODE = false;

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
    // No change, nothing to do
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
      window.app.settingsTest1       = config.settings_test1;
      window.app.settingsTest2       = config.settings_test2;
      window.app.settingsTest3       = config.settings_test3;
      window.app.settingsLanguage    = config.language;
      window.app.settingsContextMenu = config.context_menu;
      window.app.debugMode           = config.debug_mode;
    }
    
    // Update the baseline AFTER loading the real config
    if (window.app) {
      window.app.initialSettings = JSON.stringify(window.app.currentSettings());
    }

    // Sync local state + icon
    updateDebugState(config.debug_mode);

  } catch (e) {
    console.error("settingsJSON failed:", e, config);
  }
}

// Ruby → JS (info)
function infoJSON(meta) {
  try {
    if (typeof meta === "string") {
      meta = JSON.parse(meta);
    }

    if (!window.app) return;

    var name        = meta.name        || "";
    var version     = meta.version     || "";
    var description = meta.description || "";
    var copyright   = meta.copyright   || "";
    var release     = meta.release     || "";
    var update      = meta.update      || "";
    var url_ew      = meta.url_ew      || "";
    var url_su      = meta.url_su      || "";
    var url_gh      = meta.url_gh      || "";

    window.app.extName        = name;
    window.app.extDescription = description;
    window.app.extVersion     = version;
    window.app.extCopyright   = copyright;
    window.app.extRelease     = release;
    window.app.extUpdate      = update;
    window.app.extEW          = url_ew;
    window.app.extSU          = url_su;
    window.app.extGH          = url_gh;

  } catch (e) {
    console.error("infoJSON failed:", e, meta);
  }
}

// Thanks content
function thanksContent() {
  var selectedValue   = document.getElementById("formSelect").value;
  var contentPrefix   = "content_";
  var contentElements = document.querySelectorAll('[id^="' + contentPrefix + '"]');

  contentElements.forEach(function(contentElement) {
    contentElement.style.display = "none";
  });

  var selectedContent = document.getElementById(contentPrefix + selectedValue);
  if (selectedContent) {
    selectedContent.style.display = "block";
  }
}

// Debug Trigger
function debugTrigger() {
  // Target: the Settings navigation link
  const settingsLink = document.getElementById("settings-nav");
  if (!settingsLink) return;

  let clickCount = 0;
  let timer      = null;

  const REQUIRED_CLICKS = 5;      // Number of clicks required to trigger debug mode
  const TIME_WINDOW_MS  = 1000;   // Time window (in ms) to perform all clicks

  settingsLink.addEventListener("click", () => {
    clickCount++;

    // User completed the hidden click sequence
    if (clickCount === REQUIRED_CLICKS) {
      // Toggle local debug state
      const newState = !DEBUG_MODE;

      // Update UI and internal state (updates DEBUG_MODE + icon)
      updateDebugState(newState);

      // Send only debug_mode to Ruby using user_settings callback
      if (window.sketchup && typeof sketchup.user_settings === "function") {
        const payload = JSON.stringify({ debug_mode: newState });
        sketchup.user_settings(payload);
      }

      resetSequence();
      return;
    }

    // Start timeout when the first click is detected
    if (!timer) {
      timer = setTimeout(() => {
        resetSequence();
      }, TIME_WINDOW_MS);
    }
  });

  function resetSequence() {
    // Reset the click counter
    clickCount = 0;

    // Clear the timer
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
    // When debug mode is OFF, prevent the default Chromium context menu
    if (!DEBUG_MODE) {
      event.preventDefault();
    }
  });
}

debugLoader();
