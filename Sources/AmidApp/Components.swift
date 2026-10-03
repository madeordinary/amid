import SwiftUI
import AmidCore

// Callers localize product copy explicitly. User/observed fields remain literal.
struct SectionHeading: View {
    var title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: title).font(.title3.weight(.semibold))
            if let subtitle { Text(verbatim: subtitle).font(.callout).foregroundStyle(.secondary) }
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label { Text(verbatim: title) } icon: { Image(systemName: symbol) }.font(.subheadline).foregroundStyle(.secondary)
            Text(verbatim: value).font(.system(size: 29, weight: .medium, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(verbatim: detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 114, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.09)))
        .accessibilityElement(children: .combine)
    }
}

struct Notice: View {
    let title: String
    let detail: String
    var symbol: String = "info.circle"
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.secondary).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: title).font(.subheadline.weight(.semibold))
                Text(verbatim: detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(14).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore).accessibilityLabel(title).accessibilityValue(detail)
    }
}

struct EmptyState: View {
    let title: String
    let detail: String
    let symbol: String
    var body: some View {
        ContentUnavailableView { Label { Text(verbatim: title) } icon: { Image(systemName: symbol) } } description: { Text(verbatim: detail) }
            .frame(maxWidth: .infinity, minHeight: 220)
    }
}

struct KeyValue: View {
    let name: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: name).foregroundStyle(.secondary)
            Spacer()
            Text(verbatim: value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.callout).accessibilityElement(children: .ignore).accessibilityLabel(name).accessibilityValue(value)
    }
}
