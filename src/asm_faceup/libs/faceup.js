// FaceUp — extension-specific JS

window.onExtensionSettings = function(config) {
  if (!window.app) return;
  window.app.settingsUseLastExtrusion     = config.use_last_extrusion;
  window.app.settingsDefaultExtrusion     = String(config.default_extrusion != null ? config.default_extrusion : '0');
  window.app.settingsDefaultExtrusionUnit = config.default_extrusion_unit || 'model';
};
