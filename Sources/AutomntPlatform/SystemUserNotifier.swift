import Foundation
import AutomntCore

/// GUI notification channel.
///
/// A helper may not call `UNUserNotificationCenter` directly: outside a resolvable bundle
/// identity (`Contents/Helpers`, `Contents/Library/LoginItems`) that call raises an uncaught
/// exception and aborts with exit 134. The notifier therefore only orchestrates three injected
/// steps, and the default delivery step launches the app's own main executable as a bounded
/// child that owns the notification identity.
public struct SystemUserNotifier: UserNotifier {
    public typealias ForegroundQuery = @Sendable () -> Bool?
    public typealias Executor = any NotificationDeliveryExecutor

    private let soundEnabled: Bool
    private let foreground: ForegroundQuery
    private let executor: Executor

    public init(soundEnabled: Bool,
                foreground: @escaping ForegroundQuery = { ApplicationForegroundQuery.current() },
                executor: Executor = AppNotificationDelivery()) {
        self.soundEnabled = soundEnabled
        self.foreground = foreground
        self.executor = executor
    }

    public func deliver(_ notification: FailureNotification) async -> NotificationDelivery {
        // A foreground Automnt window already shows the failure; no banner and no sound.
        guard let foreground = foreground() else { return .unavailable }
        guard !foreground else { return .suppressedForeground }
        return await executor.deliver(notification, soundEnabled: soundEnabled)
    }
}

/// Resolves the module's SwiftPM resource bundle without `Bundle.module`.
///
/// `Bundle.module` is generated as a `static let` that calls `fatalError` when the bundle is
/// missing, which would turn a packaging mistake into an unrecoverable crash — the same class
/// of failure as the `UNUserNotificationCenter` identity crash this channel already avoids.
/// This resolver searches the same locations and returns nil instead.
///
/// The bundle is produced from `Sources/AutomntPlatform/Resources` and is embedded by Xcode at
/// `Automnt.app/Contents/Resources/Automnt_AutomntPlatform.bundle`, so the app main executable
/// (the only process that renders this copy) resolves it in place, including when it runs as
/// the bounded notification child.
private final class NotificationCatalogBundleToken {}

enum NotificationCatalog {
    /// Plural source of truth for the GUI banner. The system selects the CLDR category.
    static let titleKey = "Automnt: Automatic recovery incomplete"
    static let messageKey = "%lld shared folders could not be mounted automatically. Open Automnt to review."

    static func bundle() -> Bundle? {
        let name = "Automnt_AutomntPlatform"
        let candidates = [Bundle.main.resourceURL,
                          Bundle(for: NotificationCatalogBundleToken.self).resourceURL,
                          Bundle.main.bundleURL]
        for candidate in candidates {
            guard let url = candidate?.appendingPathComponent(name + ".bundle"),
                  let bundle = Bundle(url: url) else { continue }
            return bundle
        }
        return nil
    }

    /// The `.lproj` name inside the catalog for a BCP-47 tag the caller supplied.
    static func tableName(for language: String) -> String {
        let tag = language.lowercased()
        if tag.hasPrefix("zh-hant") || tag.hasPrefix("zh-tw") || tag.hasPrefix("zh-hk") { return "zh-Hant" }
        if tag.hasPrefix("zh") { return "zh-Hans" }
        if tag.hasPrefix("pt") { return "pt-BR" }
        for candidate in ["ja", "ko", "de", "fr", "es"] where tag.hasPrefix(candidate) { return candidate }
        return "en"
    }

    /// Catalog-rendered banner, or nil when the catalog or the language table is unavailable.
    ///
    /// The language table is loaded explicitly: with SwiftPM's generated bundle (which has no
    /// `defaultLocalization`), passing only `locale:` leaves the lookup on the development
    /// language and `fr`/`es`/`pt-BR` silently render English. Measured, not assumed.
    ///
    /// The count is interpolated as an `Int` rather than passed as a literal `%lld` key: the
    /// catalog substitutes and locale-formats the value, whereas `String.LocalizationValue`
    /// built from a plain string returns `%lld` unsubstituted (measured).
    static func text(count: Int, language: String) -> (title: String, message: String)? {
        guard let bundle = bundle() else { return nil }
        let table = tableName(for: language)
        guard let path = bundle.path(forResource: table, ofType: "lproj"),
              let localized = Bundle(path: path) else { return nil }
        let locale = Locale(identifier: table)
        let title = String(localized: String.LocalizationValue(titleKey), bundle: localized, locale: locale)
        // Interpolated, not `String.LocalizationValue(messageKey)`: only the interpolation
        // path substitutes the value and applies locale grouping (measured).
        let message = String(localized: "\(count) shared folders could not be mounted automatically. Open Automnt to review.",
                             bundle: localized, locale: locale)
        // A missing key returns the key itself. For a non-English table that means the lookup
        // failed, so report unavailable and let the caller use its reviewed fallback copy
        // rather than show English in a localized app.
        if table != "en" {
            if title == titleKey || message == messageKey { return nil }
        }
        return (title, message)
    }
}

public enum NotificationCopy {
    /// Languages this channel ships copy for. Anything else falls back to English, matching
    /// the existing selector chain below.
    private static let supportedLanguages = ["en", "zh-hans", "zh-hant", "zh-tw", "zh-hk",
                                            "ja", "ko", "de", "fr", "es", "pt"]

    /// Count rendered with the user's own grouping rules, not `String(describing:)`.
    ///
    /// The separator is chosen by the system's locale data, never by hand: en/ja/ko/zh group
    /// with `,`, de/es/pt-BR with `.`, and fr with a narrow no-break space (U+202F). Writing
    /// a separator by hand would be wrong for eight of the nine languages.
    ///
    /// Scope note: this formats the *numeral* only. Selecting the CLDR plural **category**
    /// (`one`/`many`/`other`, e.g. French `1 000 000 de dossiers`) is a separate concern and
    /// is deliberately not decided here by arithmetic — see the round-3 section of
    /// `release/evidence/notifications.md` and `NotificationPluralCategory` below.
    static func localizedCount(_ value: Int, language: String) -> String {
        let tag = supportedLanguages.first { language.hasPrefix($0) } ?? "en"
        return value.formatted(.number.grouping(.automatic).locale(Locale(identifier: tag)))
    }

    public static func text(count: Int, language: String) -> (title: String, message: String) {
        let number = max(count, 1)
        let language = language.lowercased()
        // Preferred path: the String Catalog, so the CLDR plural category is chosen by the
        // system's locale rules (fr/es/pt-BR `many` included) and the numeral is grouped by
        // the locale. Returns nil only if the catalog bundle or language table is missing.
        if let catalog = NotificationCatalog.text(count: number, language: language) {
            return catalog
        }
        // Fallback: the reviewed literals below. These keep the banner working (and localized)
        // if the resource bundle is ever absent. They express `one`/`other` only, so a
        // fr/es/pt-BR count in the `many` category renders the `other` wording here — the
        // catalog path is what satisfies the plural contract, not this fallback.
        // Resolved once, before any branch: every branch below renders the same numeral.
        let display = localizedCount(number, language: language)
        if language.hasPrefix("zh-hant") || language.hasPrefix("zh-tw") || language.hasPrefix("zh-hk") {
            return ("Automnt：自動復原未完成", "\(display) 個共享檔案夾未能自動掛載。請打開 Automnt 查看詳細資訊。")
        }
        if language.hasPrefix("zh") {
            return ("Automnt：自动恢复未完成", "\(display) 个共享文件夹未能自动挂载。请打开 Automnt 查看详情。")
        }
        if language.hasPrefix("ja") {
            return ("Automnt：自動復旧が完了していません", "\(display) 個の共有フォルダを自動でマウントできませんでした。Automnt を開いて詳細を確認してください。")
        }
        if language.hasPrefix("ko") {
            return ("Automnt: 자동 복구 미완료", "공유 폴더 \(display)개를 자동으로 마운트하지 못했습니다. Automnt를 열어 자세히 확인하세요.")
        }
        if language.hasPrefix("de") {
            return ("Automnt: Automatische Wiederherstellung unvollständig", number == 1 ?
                "Ein freigegebener Ordner konnte nicht automatisch verbunden werden. Öffne Automnt, um die Details zu prüfen." :
                "\(display) freigegebene Ordner konnten nicht automatisch verbunden werden. Öffne Automnt, um die Details zu prüfen.")
        }
        if language.hasPrefix("fr") {
            return ("Automnt : Rétablissement automatique incomplet", number == 1 ?
                "Un dossier partagé n’a pas pu être monté automatiquement. Ouvrez Automnt pour consulter les détails." :
                "\(display) dossiers partagés n’ont pas pu être montés automatiquement. Ouvrez Automnt pour consulter les détails.")
        }
        if language.hasPrefix("es") {
            return ("Automnt: Recuperación automática incompleta", number == 1 ?
                "No se ha podido montar automáticamente una carpeta compartida. Abre Automnt para consultar los detalles." :
                "No se han podido montar automáticamente \(display) carpetas compartidas. Abre Automnt para consultar los detalles.")
        }
        if language.hasPrefix("pt") {
            return ("Automnt: Recuperação automática incompleta", number == 1 ?
                "Não foi possível montar automaticamente uma pasta compartilhada. Abra o Automnt para ver os detalhes." :
                "Não foi possível montar automaticamente \(display) pastas compartilhadas. Abra o Automnt para ver os detalhes.")
        }
        return ("Automnt: Automatic recovery incomplete", number == 1 ?
            "One shared folder could not be mounted automatically. Open Automnt to review." :
            "\(display) shared folders could not be mounted automatically. Open Automnt to review.")
    }
}
