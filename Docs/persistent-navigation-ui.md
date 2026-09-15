# Persistent Mode and Workspace controls

Mode and Workspace now sit in a fixed bar above the main work surface. Document information, metrics, recent documents and contextual navigation remain in the collapsible left panel. The bar stays visible while the panel is hidden, when switching modes, and in Focus mode. Its panel button restores navigation from Focus mode. The existing native sidebar toggle and Workspace menu remain available.

The main NavigationSplitView remains mounted when hiding the sidebar rather than replacing the entire editor branch. This preserves the native editor instance during panel toggles. No screenplay data or save format changes are included.

Minimal package windows display persistent Mode: Script and Workspace: Editor context. These are labels for the currently supported package surface, not controls that silently operate on the legacy document behind it. Full mode/workspace switching inside minimal packages remains future integration work.

Validation: release build passed. Native checks on 2026-09-14 hid/restored the panel, changed Script to Outline with the panel hidden, checked Focus mode, returned to Script, and checked the package context labels. Final screenshots confirmed the main bar occupies its own layout space and does not cover the document header; hiding the panel leaves the bar and writing surface visible. The editor retained text focus during the panel toggle. No screenplay text was edited during this verification.
