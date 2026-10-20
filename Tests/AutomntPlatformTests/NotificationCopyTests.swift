import Foundation
import Testing
@testable import AutomntPlatform

struct NotificationCopyTests {
    private let languages = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "es", "pt-BR"]

    /// Phrases the GUI banner must never use: they name a "remount now" action that
    /// only the CLI has. The GUI has to point at the app itself instead.
    private let absentActions = [
        "Remount", "remount",
        "立即重新挂载", "立即重新掛載",
        "今すぐ再マウント", "지금 다시 마운트",
        "erneut verbinden", "Jetzt erneut",
        "Reconnecter", "Reconectar", "Volver a conectar", "Reconectar agora",
    ]

    @Test func nineLanguagesHaveCompleteCountOnlyGuidance() {
        let texts = languages.map { NotificationCopy.text(count: 3, language: $0) }
        #expect(Set(texts.map(\.title)).count == 9)
        for text in texts {
            #expect(!text.title.isEmpty && !text.message.isEmpty)
            #expect(text.message.contains("3"))
            #expect(text.message.contains("Automnt"))
            #expect(!text.message.contains("smb://") && !text.message.contains("/Volumes/"))
        }
        for language in ["en", "de", "fr", "es", "pt-BR"] {
            #expect(NotificationCopy.text(count: 1, language: language).message != NotificationCopy.text(count: 2, language: language).message)
        }
        #expect(NotificationCopy.text(count: 3, language: "zh-TW").message == NotificationCopy.text(count: 3, language: "zh-Hant").message)
        #expect(NotificationCopy.text(count: 3, language: "unknown").message == NotificationCopy.text(count: 3, language: "en").message)
    }

    /// The GUI channel shows `Automnt`; lowercase `automnt` is the shared CLI baseline
    /// (contracts/core-and-channels.md) and must not leak into the banner.
    ///
    /// The text is Unicode-normalized (NFKC) but deliberately *not* lowercased, so a
    /// full-width lookalike (`ａｕｔｏｍｎｔ`) is caught while the correct `Automnt` is
    /// not. This mirrors the localization gate, which should not be the stronger of the two.
    @Test func guiChannelUsesCapitalizedBrandOnly() {
        for language in languages {
            for count in [1, 2, 1_000_000] {
                let text = NotificationCopy.text(count: count, language: language)
                #expect(text.title.contains("Automnt"))
                #expect(text.message.contains("Automnt"))
                let normalized = Self.normalize(text.title) + "\n" + Self.normalize(text.message)
                #expect(!normalized.contains("automnt"),
                        "\(language) uses the lowercase CLI brand in the GUI channel")
            }
        }
    }

    /// The banner may not promise an action the GUI does not offer. A "retry" entry
    /// point in the GUI is T032/T033 scope; until it exists the copy says "open Automnt".
    @Test func guiBannerDoesNotPromiseAnActionTheAppLacks() {
        for language in languages {
            for count in [1, 2, 1_000_000] {
                let text = NotificationCopy.text(count: count, language: language)
                // Case-insensitive and normalized, matching the gate's action wordlist.
                let folded = Self.normalize(text.title).lowercased() + "\n"
                    + Self.normalize(text.message).lowercased()
                for phrase in absentActions {
                    #expect(!folded.contains(Self.normalize(phrase).lowercased()),
                            "\(language) advertises a missing action: \(phrase)")
                }
            }
        }
    }

    /// NFKC folds full-width forms onto ASCII. Case is handled by the caller: the brand
    /// check must stay case-sensitive, the action wordlist must not.
    private static func normalize(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping
    }

    /// Language-neutral shape of a string: interpolations, digits and punctuation are
    /// erased so singular/plural variants compare equal. Mirrors the localization gate.
    private static func skeleton(_ value: String) -> String {
        var folded = value.precomposedStringWithCompatibilityMapping.lowercased()
        folded = folded.replacingOccurrences(of: #"\\\([^)]*\)"#, with: " ", options: .regularExpression)
        folded = folded.replacingOccurrences(of: #"\d+"#, with: " ", options: .regularExpression)
        folded = String(folded.map { $0.isLetter || $0.isNumber || $0.isWhitespace ? $0 : " " })
        return folded.split(separator: " ").joined(separator: " ")
    }

    /// es must use the catalog baseline term `recuperación`, not `restauración`.
    /// de/fr/pt-BR titles must keep the same recovery term as the catalog.
    @Test func recoveryTerminologyMatchesTheCatalogBaseline() {
        let es = NotificationCopy.text(count: 3, language: "es")
        #expect(es.title.lowercased().contains("recuperación"))
        #expect(!es.title.lowercased().contains("restauración"))
        #expect(!es.message.lowercased().contains("restaurar"))
        #expect(!es.message.lowercased().contains("restauración"))

        #expect(NotificationCopy.text(count: 3, language: "de").title.contains("Automatische Wiederherstellung"))
        #expect(NotificationCopy.text(count: 3, language: "fr").title.contains("Rétablissement automatique"))
        #expect(NotificationCopy.text(count: 3, language: "pt-BR").title.contains("Recuperação automática"))
    }

    /// Message bodies must be genuinely translated, not inherited from English.
    /// Titles were already required to be distinct, but messages had no such check:
    /// replacing four languages' messages with the English sentence kept every
    /// assertion green in both this suite and the localization gate (F7).
    @Test func messageBodiesAreTranslatedAndDistinctPerLanguage() {
        // count = 1 selects the singular form in en/de/fr/es/pt-BR, which is a
        // separate literal from the plural form. Both must be checked: testing only
        // plural counts left the singular untranslated case undetected.
        for count in [1, 2, 7] {
            let texts = languages.map { ($0, NotificationCopy.text(count: count, language: $0)) }
            // No two languages may share a message body at the same count.
            let bodies = texts.map(\.1.message)
            #expect(Set(bodies).count == languages.count,
                    "messages are not distinct across languages at count \(count)")
            // English is the fallback source, so every other language must differ —
            // from the English message *and* from the English title. Comparing only
            // against the message let a translated message be replaced by the English
            // title unnoticed (F9). Comparing exact strings only let "the English
            // sentence plus decoration" through (F10), so compare normalized
            // skeletons and reject containment in either direction.
            let english = NotificationCopy.text(count: count, language: "en")
            for (language, text) in texts where language != "en" {
                #expect(text.message != english.message,
                        "\(language) reuses the English message verbatim")
                #expect(text.title != english.title,
                        "\(language) reuses the English title verbatim")
                #expect(text.message != english.title,
                        "\(language) uses the English title as its message")
                for value in [text.title, text.message] {
                    let sk = Self.skeleton(value)
                    #expect(sk != Self.skeleton(english.title),
                            "\(language) repeats the English title: \(value)")
                    #expect(!sk.contains(Self.skeleton(english.title)),
                            "\(language) embeds the English title: \(value)")
                    #expect(!sk.contains(Self.skeleton(english.message)),
                            "\(language) embeds the English message: \(value)")
                }
            }
        }
    }

    /// Counts and counts only: no share name, address or path may reach the banner.
    @Test func payloadStaysCountOnlyAndRedacted() {
        let forbidden = ["/Volumes", "smb://", "@", "://", "/Users"]
        for language in languages {
            for count in [1, 7, 1_000_000] {
                let text = NotificationCopy.text(count: count, language: language)
                let combined = "\(text.title)\n\(text.message)"
                // en/de/fr/es/pt-BR spell out "one" instead of the digit; every other
                // count and language carries the numeral itself.
                //
                // The numeral is now rendered with the *locale's* grouping rules, so the
                // message contains "1,000,000" / "1.000.000" / "1 000 000" rather than the
                // bare "1000000" this assertion used to require. Comparing against the raw
                // `\(count)` was therefore no longer a valid statement about the product —
                // but dropping the check would lose the "the right count is present"
                // guarantee, so it is strengthened instead: strip grouping characters and
                // require the exact digit sequence, which is independent of which separator
                // the locale chose.
                if count != 1 || !["en", "de", "fr", "es", "pt-BR"].contains(language) {
                    let digitsOnly = combined.filter { $0.isNumber }
                    // The message may contain other digits (e.g. "1" inside a word), so
                    // check the count's digit sequence appears, not that it is the only one.
                    #expect(digitsOnly.contains("\(count)"),
                            "\(language) count=\(count) lost its numeral: \(combined)")
                }
                #expect(!combined.isEmpty)
                for token in forbidden {
                    #expect(!combined.contains(token), "\(language) leaked \(token)")
                }
            }
        }
    }

    /// The numeral must use the locale's grouping rules, not `String(describing:)`.
    /// A bare `1000000` is what the old implementation produced for every language.
    @Test func numeralUsesLocaleGroupingRules() {
        // Each entry is the separator the system locale data selects for that language.
        let expectedSeparator: [String: Character] = [
            "en": ",", "ja": ",", "ko": ",", "zh-Hans": ",", "zh-Hant": ",",
            "de": ".", "es": ".", "pt-BR": ".",
            // French groups with a narrow no-break space (U+202F), not a plain space.
            "fr": "\u{202F}",
        ]
        for language in languages {
            let expected = expectedSeparator[language]!
            let message = NotificationCopy.text(count: 1_000_000, language: language).message
            #expect(!message.contains("1000000"),
                    "\(language) rendered an ungrouped numeral: \(message)")
            #expect(message.contains("1\(expected)000\(expected)000"),
                    "\(language) did not use '\(expected)' as its group separator: \(message)")
        }
    }

    /// The fallback path's own numeral formatting, checked directly.
    ///
    /// The assertions above run through the String Catalog, whose `%lld` substitution does the
    /// grouping itself. That means a regression in `localizedCount` — the formatting used when
    /// the catalog bundle is unavailable — was invisible to every end-to-end test: replacing
    /// its body with `String(value)` left the whole suite green (measured as mutation M4). This
    /// test exercises the formatter on its own so that path is guarded too.
    @Test func fallbackNumeralFormattingIsLocaleAware() {
        let expectedSeparator: [String: String] = [
            "en": ",", "ja": ",", "ko": ",", "zh-hans": ",", "zh-hant": ",",
            "de": ".", "es": ".", "pt-br": ".", "fr": "\u{202F}",
        ]
        for (language, separator) in expectedSeparator {
            let rendered = NotificationCopy.localizedCount(1_000_000, language: language)
            #expect(rendered == "1\(separator)000\(separator)000",
                    "\(language) fallback numeral is not locale-grouped: \(rendered)")
        }
        #expect(NotificationCopy.localizedCount(7, language: "en") == "7")
        // An unrecognised tag falls back to English grouping rather than dropping separators.
        #expect(NotificationCopy.localizedCount(1_000_000, language: "unknown") == "1,000,000")
        // Regional and mixed-case tags resolve to the same rules as their base language.
        #expect(NotificationCopy.localizedCount(1_000_000, language: "zh-TW")
            == NotificationCopy.localizedCount(1_000_000, language: "zh-Hant"))
        #expect(NotificationCopy.localizedCount(1_000_000, language: "pt-BR")
            == NotificationCopy.localizedCount(1_000_000, language: "pt-br"))
    }

    /// fr/es/pt-BR have a CLDR `many` category (positive multiples of a million) whose
    /// wording differs from `other` — French additionally inserts "de" before the noun.
    /// The category must be selected by the system's plural rules, not by arithmetic in
    /// business code, so this test asserts the *observable* outcome of the catalog path.
    @Test func millionUsesTheManyCategoryWording() {
        // The `many` wording is required; the `other` wording is what a missing branch shows.
        let many: [String: String] = [
            "fr": "de dossiers partagés",
            "es": "de carpetas compartidas",
            "pt-BR": "de pastas compartilhadas",
        ]
        for (language, required) in many {
            let million = NotificationCopy.text(count: 1_000_000, language: language).message
            #expect(million.contains(required),
                    "\(language) @1,000,000 did not select the many branch: \(million)")
            // A count in the `other` category must NOT take the `many` wording, which is
            // what proves the branch is selected by rules rather than applied always.
            for other in [2, 3, 1_000, 999_999] {
                let text = NotificationCopy.text(count: other, language: language).message
                #expect(!text.contains(required),
                        "\(language) @\(other) wrongly took the many wording: \(text)")
                // `de` only belongs to the `many` form; `other` must not gain it.
                #expect(!text.contains(" de dossiers partagés")
                            && !text.contains(" de carpetas compartidas")
                            && !text.contains(" de pastas compartilhadas"),
                        "\(language) @\(other) inserted the many-branch preposition: \(text)")
            }
        }
    }

    /// Counts in the `one` category keep singular wording, and count 0 is clamped to 1.
    ///
    /// `text(count:)` intentionally clamps 0 to 1: the core never delivers a failure
    /// notification at N = 0 (`design/localization.md`: "N = 0 不生成失败通知"), and the
    /// banner must never render "0 failures". So the observable contract for 0 is "the same
    /// text as 1", not "the locale's zero category" — asserting the latter would encode a
    /// behavior this API deliberately does not have.
    @Test func oneCategoryKeepsSingularAndZeroClampsToOne() {
        for (language, singular) in ["en": "One shared folder", "de": "Ein freigegebener Ordner",
                                     "fr": "Un dossier partagé", "es": "una carpeta compartida",
                                     "pt-BR": "uma pasta compartilhada"] {
            let one = NotificationCopy.text(count: 1, language: language).message
            #expect(one.contains(singular), "\(language) @1 is not singular: \(one)")
        }
        for language in languages {
            let zero = NotificationCopy.text(count: 0, language: language)
            let one = NotificationCopy.text(count: 1, language: language)
            #expect(zero.message == one.message && zero.title == one.title,
                    "\(language) @0 must clamp to the N=1 wording, never show a zero count")
            #expect(!zero.message.contains("0"), "\(language) @0 rendered a zero: \(zero.message)")
        }
    }
}
