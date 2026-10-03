# English-first localization

Amid supplies English resources in `Resources/en.lproj`: a static `Localizable.strings` table and `Localizable.stringsdict` count rules. Packaging copies that directory into the app's Resources and declares `CFBundleDevelopmentRegion=en`. English is the only supplied language; no translated release is claimed.

The static table preserves current wording, punctuation, units, uncertainty and stop boundaries. It contains no sampled process identities, names, paths, arguments, environments, endpoints, aliases or payloads. Formatted keys contain placeholders, not runtime values.

## Implemented lookup boundary

`Sources/AmidCore/Localization.swift` exposes:

```swift
localized("Known product-copy key")
localizedFormat("%ld projects", count)
localizedFormat("%@/s", formattedValue, locale: .current)
```

Lookup uses the main bundle's Localizable table with the English key as fallback. Formatting accepts typed arguments and an explicit/default current locale; stringsdict rules supply count-dependent forms. Never pass a user/observed value as the lookup key or format template. Keep aliases, process names, IDs, paths, addresses, volume names and interface names literal.

Destination has a localized display `title` and subtitle; stored `rawValue`/identity remain unchanged. Menu navigation uses that title. Menu-panel product labels and pause/resume controls perform lookup; its project/endpoint/alert summary uses real English plural rules. Formatting helpers localize missing-state labels and duration/throughput templates; percent formatting uses the locale's percent style without changing one-core/total-capacity semantics.

Generic components accept String for compatibility and explicitly render supplied text verbatim. Their caller decides whether a field is product copy or data: `SectionHeading(title: localized("Largest observed applications"))` is correct; an alias remains the original String. Do not blindly localize every SectionHeading/KeyValue title because those components also display user-controlled names. The root integration owner handles other UI creation sites.

SwiftUI literal labels accepting LocalizedStringKey perform lookup automatically. Dynamic String values require explicit lookup at their product-copy origin. Apple's [LocalizedStringKey documentation](https://developer.apple.com/documentation/SwiftUI/LocalizedStringKey) and [view-localization guidance](https://developer.apple.com/documentation/swiftui/preparing-views-for-localization) explain this distinction.

## Current coverage and release limits

AppModel status/error/cadence/coverage messages, destination titles, retention/alert titles, complete alert detail templates, action refusal/result text and custom-component product arguments now use explicit lookup. Dynamic user/observed values remain literal. The group/history RAM-window copy is English and uses complete formatting templates.

The stringsdict supplies count forms; the menu consumes project/listener/alert plurals. English is the only delivered language. Some measurement composites and SwiftUI interpolation keys still need translator-context/plural review before adding another language; no translated or pseudo-localized release is claimed. Do not change stored enum IDs while translating display text.

## Observed verification

- `plutil -lint` passed for both English resources and Info.plist.
- Static keys are unique and preserve matching English values; no rendered interpolation values or absolute-path entries were present.
- A standalone executable using the real helper and a temporary resource bundle printed `0 projects`, `1 project`, `2 projects`; fallback and a literal argument containing percent syntax/path text passed unchanged. This is actual lookup/plural behavior, not merely source inspection.
- Dedicated native `swift build --target AmidApp` passed with exit 0 (28.16 seconds) on arm64 macOS27.0.1 / Xcode27 / Swift6.4 / SDK27. Packaging/rendered lookup, expanded-text/keyboard/VoiceOver checks and other languages must be recorded from actual app observations. No non-English or pseudo-localized behavior is claimed here.
