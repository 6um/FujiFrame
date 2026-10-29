import SwiftUI
import CoreText
#if SWIFT_PACKAGE
import FujiFrameCore
#endif

/// Camera glyphs from Fujifilm's X-T5 manual; see docs/FILM_SIMULATION_ICONS.md.
enum FilmSimulationIcons {
    static let glyphs: [String: (String, Character)] = [
        "PROVIA / 标准": ("fficn30", "c"), "Velvia / 鲜艳": ("fficn30", "d"),
        "ASTIA / 柔和": ("fficn30", "e"), "CLASSIC CHROME": ("fficn32", "i"),
        "REALA ACE": ("fficn33", "c"), "PRO Neg. Hi": ("fficn32", "g"),
        "PRO Neg. Std": ("fficn32", "h"), "CLASSIC Neg.": ("fficn33", "g"),
        "NOSTALGIC Neg.": ("fficn33", "n"), "ETERNA / 电影": ("fficn63", "X"),
        "ETERNA BLEACH BYPASS": ("fficn63", "N"), "ACROS": ("fficn62", "a"),
        "ACROS + Ye": ("fficn62", "d"), "ACROS + R": ("fficn62", "c"),
        "ACROS + G": ("fficn62", "b"), "MONOCHROME": ("fficn30", "b"),
        "MONOCHROME + Ye": ("fficn32", "e"), "MONOCHROME + R": ("fficn32", "d"),
        "MONOCHROME + G": ("fficn32", "f"), "SEPIA": ("fficn30", "f")
    ]

    static let images: [String: NSImage] = glyphs.compactMapValues { name, character in
        #if SWIFT_PACKAGE
        // SwiftPM's generated accessor expects a sibling bundle; the packaged
        // macOS app keeps it in Contents/Resources instead.
        let bundle = Bundle.main.resourceURL
            .flatMap { Bundle(url: $0.appendingPathComponent("FujiFrame_FujiFrame.bundle")) } ?? Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: name, withExtension: "ttf", subdirectory: "FilmSimulationFonts"),
              let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider) else { return nil }
        let ctFont = CTFontCreateWithGraphicsFont(font, 32, nil, nil)
        var code = String(character).utf16.first!
        var glyph: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(ctFont, &code, &glyph, 1),
              let path = CTFontCreatePathForGlyph(ctFont, glyph, nil) else { return nil }
        let bounds = path.boundingBoxOfPath
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let size = NSSize(width: 30, height: 18)
        let scale = min(28 / bounds.width, 16 / bounds.height)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.translateBy(x: (size.width - bounds.width * scale) / 2,
                                y: (size.height - bounds.height * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            context.addPath(path)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            context.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Native menu images remain visible both in the menu and in the selected value.
struct FilmSimulationPicker: NSViewRepresentable {
    @Binding var selection: String
    var emptyTitle = "未记录"
    var emptySystemImage: String? = nil
    var fillsWidth = false

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.setAccessibilityLabel("胶片模拟")
        popup.addItem(withTitle: emptyTitle)
        popup.lastItem?.representedObject = ""
        if let emptySystemImage {
            popup.lastItem?.image = NSImage(systemSymbolName: emptySystemImage, accessibilityDescription: nil)
        }
        popup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        popup.lineBreakMode = .byTruncatingTail
        for film in XT5.films {
            popup.addItem(withTitle: film)
            popup.lastItem?.representedObject = film
            popup.lastItem?.image = FilmSimulationIcons.images[film]
        }
        popup.target = context.coordinator
        popup.action = #selector(Coordinator.changed(_:))
        return popup
    }

    func updateNSView(_ popup: NSPopUpButton, context: Context) {
        context.coordinator.selection = $selection
        popup.selectItem(at: popup.itemArray.firstIndex { ($0.representedObject as? String) == selection } ?? 0)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView popup: NSPopUpButton, context: Context) -> CGSize? {
        if fillsWidth, let width = proposal.width, width.isFinite {
            return CGSize(width: width, height: popup.intrinsicContentSize.height)
        }
        // Size to the selected value, rather than the widest menu item, so the
        // icon and title sit together at the trailing edge of the form row.
        let title = popup.title as NSString
        let textWidth = title.size(withAttributes: [.font: popup.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)]).width
        let imageWidth = popup.selectedItem?.image.map { $0.size.width + 6 } ?? 0
        return CGSize(width: ceil(textWidth + imageWidth + 32), height: popup.intrinsicContentSize.height)
    }

    final class Coordinator: NSObject {
        var selection: Binding<String>
        init(selection: Binding<String>) { self.selection = selection }
        @objc func changed(_ popup: NSPopUpButton) {
            selection.wrappedValue = popup.selectedItem?.representedObject as? String ?? ""
        }
    }
}
