// The side panels beside the page: how much they grow on a big window (the web's `dockScale`).

/// The rail with the arrow, and the panel (their width before any growth).
const dockRailWidth = 48.0;
const dockPanelWidth = 240.0;

/// The page column (max-w-3xl); what is left over on either side is room for a dock.
const _pageWidth = 768.0;

/// From this window width the panels are docked beside the page instead of opening as drawers.
const dockBreakpoint = 1340.0;

/// 1 at the breakpoint, more on bigger windows so the panels use the room beside the page instead of sitting small in
/// it, up to 1.7. They take about 80% of the room that is left on each side.
double dockScale(double viewportWidth) {
  if (!viewportWidth.isFinite || viewportWidth < dockBreakpoint) return 1;
  final room = (viewportWidth - _pageWidth) / 2;
  final scale = (room * 0.8) / (dockRailWidth + dockPanelWidth);
  return (scale.clamp(1.0, 1.7) * 100).floorToDouble() / 100;
}
