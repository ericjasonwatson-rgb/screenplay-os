import AppKit
import Testing
@testable import ScreenplayOSApp

@Suite("Application branding")
struct AppBrandingTests {
    @MainActor
    @Test func everyDisplayedBrandImageHasTransparentCorners() throws {
        for image in [AppBranding.logo, AppBranding.menuBarIcon, AppBranding.appIcon] {
            let data = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: data))
            #expect(bitmap.hasAlpha)
            let corners = [(0, 0), (bitmap.pixelsWide - 1, 0),
                           (0, bitmap.pixelsHigh - 1), (bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1)]
            for (x, y) in corners {
                #expect((bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 1) == 0)
            }
        }
        #expect(AppBranding.menuBarIcon.size == NSSize(width: 18, height: 18))
    }
}
