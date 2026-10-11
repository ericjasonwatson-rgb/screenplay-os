# Initial ScreenplayOS logo

User-supplied artwork, adopted September 12, 2026.

Source: https://chatgpt.com/s/m_6aa5af5e6b648191bfa415d50aff4010

The original downloaded PNG is retained in Sources/ScreenplayOSApp/Resources/ScreenplayOSLogo.png. No cropping, redrawing, recoloring or text changes were made. ScreenplayOSAppIcon.png is the Dock-icon derivative with the exterior white surround removed; the dark rounded square and interior logo remain. ScreenplayOS.icns contains the standard macOS sizes converted from that derivative with sips and iconutil. The original artwork remains unchanged for the About view and website. The packaging script copies the ICNS without requiring an image library.

The logo appears as the packaged app icon (Finder/Dock), a persistent 24pt About button in both the main and writing-only editor headers, and an 18pt macOS menu-bar item. Development launches explicitly install the same branded application icon. The header replaces the older native-toolbar logo so it remains visible without duplicating it in two adjacent bars. The About window displays the complete image at a readable size. The header button, application menu, and menu-bar item open the same About window; none alters the screenplay. The small images are identity markers, not readable wordmarks. The menu-bar item also brings windows forward and quits through the existing safe-close path. The main WindowGroup remains the primary scene.

All in-app surfaces now load `ScreenplayOSAppIcon.png`, whose exterior pixels are
transparent. This includes the menu-bar item, persistent About buttons, and About
window. The packaged application icon continues to use the size-specific ICNS,
generated from the same transparent master. The original opaque PNG is retained as
source history but is no longer displayed by the app.


Validation, 2026-10-08: the initial change passed all 291 Swift tests, 37 importer checks, and 14 self-tests. After retaining the WindowGroup as the first scene and activating the app when opening About, the final code passed six native-editor tests plus the importer checks and self-tests. An isolated ad-hoc review bundle launched successfully with a separate identifier, and computer-use inspection verified the visible header icon and its About action. Menu-bar visual inspection was not completed because the SystemUIServer UI tool timed out; Dock appearance was not independently captured. Packaging still copies the existing ICNS and PNG and declares CFBundleIconFile. The website already uses the same PNG for its header, hero, and favicon. The temporary review process was confirmed closed and its bundle removed; no installed app or public release was replaced.

Icon correction, 2026-10-08: used the built-in image editing tool with the instruction “Remove ONLY the white outer surround and its gray cast shadow outside the dark rounded square; preserve the opaque dark square and interior artwork.” Saved the derivative as Sources/ScreenplayOSApp/Resources/ScreenplayOSAppIcon.png and regenerated all ten standard ICNS representations. This source correction does not replace the installed app or the notarized build 27 download.
