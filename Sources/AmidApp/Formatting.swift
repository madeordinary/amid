import Foundation
import AmidCore

func stopResultDetail(_ result: StopResult) -> String {
    let signals = localizedFormat("Signals sent: %ld.", result.signalsSent)
    let remaining = result.remainingObservationAvailable
        ? localizedFormat("Remaining observed identities: %ld; endpoints: %ld.", result.remainingIdentities.count, result.remainingEndpoints.count)
        : localized("Remaining process and endpoint state is unavailable.")
    return [result.message, signals, remaining].joined(separator: " ")
}

func bytes(_ value: UInt64?) -> String {
    guard let value else { return localized("Unavailable") }
    return ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
}
func percent(_ value: Double?) -> String {
    guard let value, value.isFinite else { return localized("Unavailable") }
    return (value / 100).formatted(.percent.precision(.fractionLength(1)))
}
func batteryPowerDescription(_ battery: BatterySnapshot) -> String {
    if battery.isCharging == true { return localized("Charging") }
    guard let onBattery = battery.onBattery else { return localized("Power source unavailable") }
    return localized(onBattery ? "On battery" : "External power")
}
func historyCadence(_ values: Set<Double>) -> String {
    let measured = values.filter { $0.isFinite && $0 > 0 }
    guard let minimum = measured.min(), let maximum = measured.max() else { return localized("Unavailable") }
    let lower = minimum.formatted(.number.precision(.fractionLength(1)))
    let upper = maximum.formatted(.number.precision(.fractionLength(1)))
    return lower == upper ? localizedFormat("%@ s", lower) : localizedFormat("%@–%@ s", lower, upper)
}
func throughput(_ value: Double?) -> String {
    guard let value, value.isFinite, value >= 0 else { return localized("Awaiting delta") }
    return localizedFormat("%@/s", bytes(UInt64(value)))
}
func duration(_ interval: TimeInterval) -> String {
    let seconds = Int(max(0, interval))
    if seconds < 60 { return localizedFormat("%lds", seconds) }
    if seconds < 3600 { return localizedFormat("%ldm", seconds / 60) }
    return localizedFormat("%ldh %ldm", seconds / 3600, (seconds % 3600) / 60)
}

func collectionStatusMessage(_ status: CollectionStatus?, empty: Bool, volumes: Bool) -> String? {
    switch status {
    case .complete: return empty ? localized(volumes ? "No local volumes observed" : "No network interfaces observed") : nil
    case .partial: return localized(volumes ? "Some volume measurements unavailable" : "Some interface measurements unavailable")
    case .unavailable, nil: return localized(volumes ? "Volume collection unavailable" : "Interface collection unavailable")
    }
}
