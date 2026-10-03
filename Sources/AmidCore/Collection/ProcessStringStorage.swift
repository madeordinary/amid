import Foundation

/// Shares storage only after current values have been freshly collected and validated.
/// Retains strings from one accepted sample, never cached measurements or process samples.
struct ProcessStringStorage: Sendable {
    private struct Fields: Sendable {
        var executable: String
        var name: String
        var runtime: String?
        var workingDirectory: String?
        var projectPath: String?
        var applicationID: String
        var applicationName: String
        var groupingReason: String
        var endpointAddresses: [String]
        init(_ sample: ProcessSample) {
            executable = sample.executable; name = sample.name; runtime = sample.runtime
            workingDirectory = sample.workingDirectory; projectPath = sample.projectPath
            applicationID = sample.applicationID; applicationName = sample.applicationName
            groupingReason = sample.groupingReason; endpointAddresses = sample.endpoints.map(\.address)
        }
    }
    private var previous: [ProcessIdentity: Fields] = [:]
    var retainedIdentityCount: Int { previous.count }
    mutating func reset() { previous.removeAll() }
    mutating func reuseStorage(in samples: inout [ProcessSample]) {
        var next: [ProcessIdentity: Fields] = [:]
        next.reserveCapacity(samples.count)
        for index in samples.indices {
            if let old = previous[samples[index].identity] {
                samples[index].executable = equalStorage(samples[index].executable, old.executable)
                samples[index].name = equalStorage(samples[index].name, old.name)
                samples[index].runtime = equalStorage(samples[index].runtime, old.runtime)
                samples[index].workingDirectory = equalStorage(samples[index].workingDirectory, old.workingDirectory)
                samples[index].projectPath = equalStorage(samples[index].projectPath, old.projectPath)
                samples[index].applicationID = equalStorage(samples[index].applicationID, old.applicationID)
                samples[index].applicationName = equalStorage(samples[index].applicationName, old.applicationName)
                samples[index].groupingReason = equalStorage(samples[index].groupingReason, old.groupingReason)
                for endpoint in samples[index].endpoints.indices where old.endpointAddresses.indices.contains(endpoint) {
                    samples[index].endpoints[endpoint].address = equalStorage(samples[index].endpoints[endpoint].address, old.endpointAddresses[endpoint])
                }
            }
            next[samples[index].identity] = Fields(samples[index])
        }
        previous = next
    }
    private func equalStorage(_ fresh: String, _ old: String) -> String { fresh.utf8.elementsEqual(old.utf8) ? old : fresh }
    private func equalStorage(_ fresh: String?, _ old: String?) -> String? {
        guard let freshValue = fresh, let oldValue = old else { return fresh }
        return equalStorage(freshValue, oldValue)
    }
}
