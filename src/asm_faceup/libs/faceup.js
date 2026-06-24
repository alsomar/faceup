// FaceUp — extension-specific JS

window.onExtensionSettings = function(config) {
  if (!window.app) return;
  window.app.settingsUseLastExtrusion     = config.use_last_extrusion;
  window.app.settingsDefaultExtrusion     = String(config.default_extrusion != null ? config.default_extrusion : '0');
  window.app.settingsModelUnit            = config.model_unit || '';
  window.app.settingsAlignBoundingBox     = !!config.align_to_min_bb;
  window.app.settingsRepairEdgesBefore    = !!config.repair_edges_before;
};

// Live push of the active model's length unit — used when units change while
// the settings dialog is open, so the label updates without reopening.
window.modelUnitJSON = function(unit) {
  if (window.app) window.app.settingsModelUnit = unit || '';
};
