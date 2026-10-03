import XCTest
@testable import AmidCore

final class ProfiledSamplerTests: XCTestCase, @unchecked Sendable {
    func testProfiledSamplePreservesRequestedCadenceAndInitialization() async throws {
        let sampler = Sampler()
        let initialized = await sampler.initializedCollectionResources
        XCTAssertFalse(initialized)
        let result = await sampler.profiledSample(cadence: 7, projectBoundaries: [])
        if result.snapshot.availability == .available {
            XCTAssertEqual(result.breakdown.coarse.count, 7)
        } else {
            XCTAssertEqual(Set(result.breakdown.coarse.keys), ["enumeration"])
            XCTAssertTrue(result.snapshot.processes.isEmpty)
            XCTAssertEqual(result.breakdown.coarse["enumeration"]?.calls, 1)
        }
        XCTAssertNil(result.breakdown.incompleteCoarse)
        XCTAssertFalse(result.breakdown.incompleteIteration)
        XCTAssertEqual(result.snapshot.cadence, 7)
        XCTAssertEqual(result.snapshot.expectedCadence, 7)
        XCTAssertGreaterThanOrEqual(result.measurement.wallSeconds, 0)
        if let cpu = result.measurement.cpuSeconds { XCTAssertGreaterThanOrEqual(cpu, 0) }
        let after = await sampler.initializedCollectionResources
        XCTAssertTrue(after)
        // No extra sample or baseline reset: the subsequent normal call still uses its own cadence.
        let next = await sampler.sample(cadence: 11)
        XCTAssertEqual(next.cadence, 11)
        XCTAssertEqual(next.expectedCadence, 11)
    }
}
