import Foundation

/// Lookup only known product-copy keys. Observed values and user aliases are not localization keys.
public func localized(_ key: String, bundle: Bundle = .main) -> String {
    bundle.localizedString(forKey: key, value: key, table: "Localizable")
}

/// Locale-aware formatting of a known product template, including stringsdict plural rules.
/// Keep arguments in their original types and never use observed/user strings as format templates.
public func localizedFormat(_ key: String, _ arguments: CVarArg..., locale: Locale = .current, bundle: Bundle = .main) -> String {
    String(format: localized(key, bundle: bundle), locale: locale, arguments: arguments)
}
