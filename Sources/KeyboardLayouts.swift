import Carbon
import Foundation

/// Letter rows, hint characters, and currency symbol for one physical-layout family of the on-screen keyboard.
struct KeyboardLayoutSpec: Equatable {
    let code: String
    let row1: [String]
    let row2: [String]
    let row3: [String]
    let hints1: [String]
    let hints2: [String]
    let hints3: [String]
    let currency: String

    var locale: Locale { Locale(identifier: code) }
}

/// Maps the keyboard layouts enabled in macOS (System Settings → Keyboard → Input Sources) to on-screen layouts.
enum KeyboardLayouts {
    private static let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private static let latinHints2 = ["@", "#", "$", "&", "*", "(", ")", "'", "\""]
    private static let latinHints3 = ["%", "-", "+", "=", "/", ";", ":", "!", "?"]

    static func spec(forLanguage language: String) -> KeyboardLayoutSpec {
        switch language {
        case "tr":
            return KeyboardLayoutSpec(
                code: "tr",
                row1: ["q", "w", "e", "r", "t", "y", "u", "ı", "o", "p", "ğ", "ü"],
                row2: ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ş", "i"],
                row3: ["z", "x", "c", "v", "b", "n", "m", "ö", "ç", ",", "."],
                hints1: digits + ["*", "-"],
                hints2: ["@", "#", "$", "&", "_", "(", ")", "'", "\"", "+", ";"],
                hints3: ["%", "-", "+", "/", ":", ";", "!", "?", "/", "!", "?"],
                currency: "₺"
            )
        case "de":
            return KeyboardLayoutSpec(
                code: "de",
                row1: ["q", "w", "e", "r", "t", "z", "u", "i", "o", "p", "ü"],
                row2: ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ö", "ä"],
                row3: ["y", "x", "c", "v", "b", "n", "m", ",", "."],
                hints1: digits,
                hints2: latinHints2,
                hints3: latinHints3,
                currency: "€"
            )
        case "fr":
            return KeyboardLayoutSpec(
                code: "fr",
                row1: ["a", "z", "e", "r", "t", "y", "u", "i", "o", "p"],
                row2: ["q", "s", "d", "f", "g", "h", "j", "k", "l", "m"],
                row3: ["w", "x", "c", "v", "b", "n", ",", "."],
                hints1: digits,
                hints2: latinHints2,
                hints3: latinHints3,
                currency: "€"
            )
        case "es":
            return KeyboardLayoutSpec(
                code: "es",
                row1: ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
                row2: ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ñ"],
                row3: ["z", "x", "c", "v", "b", "n", "m", ",", "."],
                hints1: digits,
                hints2: latinHints2,
                hints3: latinHints3,
                currency: "€"
            )
        case "it":
            return KeyboardLayoutSpec(
                code: "it",
                row1: ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
                row2: ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
                row3: ["z", "x", "c", "v", "b", "n", "m", ",", "."],
                hints1: digits,
                hints2: latinHints2,
                hints3: latinHints3,
                currency: "€"
            )
        case "ru":
            return KeyboardLayoutSpec(
                code: "ru",
                row1: ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х", "ъ"],
                row2: ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
                row3: ["я", "ч", "с", "м", "и", "т", "ь", "б", "ю"],
                hints1: digits,
                hints2: latinHints2,
                hints3: latinHints3,
                currency: "₽"
            )
        default:
            return KeyboardLayoutSpec(
                code: "en",
                row1: ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
                row2: ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
                row3: ["z", "x", "c", "v", "b", "n", "m", ",", "."],
                hints1: digits,
                hints2: latinHints2,
                hints3: latinHints3,
                currency: "$"
            )
        }
    }

    /// The keyboard layout macOS is currently using.
    static func current() -> (spec: KeyboardLayoutSpec, title: String) {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return (spec(forLanguage: "en"), "English")
        }
        return describe(source)
    }

    /// Every keyboard layout enabled in macOS, reduced to one entry per on-screen layout family.
    static func enabled() -> [(spec: KeyboardLayoutSpec, title: String)] {
        let filter: [String: Any] = [
            kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String,
            kTISPropertyInputSourceIsSelectCapable as String: true,
            kTISPropertyInputSourceIsEnabled as String: true,
        ]
        guard let list = TISCreateInputSourceList(filter as CFDictionary, false)?.takeRetainedValue() else {
            return []
        }
        var result: [(spec: KeyboardLayoutSpec, title: String)] = []
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let source = Unmanaged<TISInputSource>.fromOpaque(raw).takeUnretainedValue()
            let entry = describe(source)
            if !result.contains(where: { $0.spec.code == entry.0.code }) {
                result.append(entry)
            }
        }
        return result
    }

    private static func describe(_ source: TISInputSource) -> (KeyboardLayoutSpec, String) {
        let languages = property(source, kTISPropertyInputSourceLanguages) as? [String]
        let language = (languages?.first ?? "en").split(separator: "-").first.map(String.init) ?? "en"
        let title = property(source, kTISPropertyLocalizedName) as? String ?? language
        return (spec(forLanguage: language), title)
    }

    private static func property(_ source: TISInputSource, _ key: CFString) -> Any? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue()
    }
}
