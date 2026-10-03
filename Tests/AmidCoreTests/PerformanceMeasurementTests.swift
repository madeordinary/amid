import XCTest
@testable import AmidCore

final class PerformanceMeasurementTests: XCTestCase {
    private func counters(cpu: Double? = 1, voluntary: Int64? = 10, interrupts: UInt64? = 20) -> PerformanceMeasurement.Counters {
        .init(cpu: cpu, peakRSS: 8192, voluntary: voluntary, involuntary: 4, interrupts: interrupts, packageIdle: 2)
    }
    func testIntervalDeltasAndRatesUseProvidedMonotonicDuration() {
        var end = counters(cpu: 3, voluntary: 16, interrupts: 30)
        end.involuntary = 7; end.packageIdle = 6
        let report = PerformanceMeasurement.makeReport(elapsed: 4, baseline: counters(), current: end, notes: [])
        XCTAssertEqual(report.cpuSeconds, 2); XCTAssertEqual(report.meanCPUPercentOneCore, 50)
        XCTAssertEqual(report.voluntaryContextSwitches, 6); XCTAssertEqual(report.involuntaryContextSwitches, 3)
        XCTAssertEqual(report.interruptWakeups, 10); XCTAssertEqual(report.interruptWakeupsPerSecond, 2.5)
        XCTAssertEqual(report.packageIdleWakeups, 4); XCTAssertEqual(report.packageIdleWakeupsPerSecond, 1)
        XCTAssertEqual(report.peakResidentBytes, 8192)
        XCTAssertTrue(report.notes.joined().contains("process-lifetime"))
    }
    func testUnavailableAndRegressedCountersRemainUnknown() {
        var end = counters(cpu: 0.5, voluntary: 9, interrupts: 19)
        end.packageIdle = nil; end.peakRSS = nil
        let report = PerformanceMeasurement.makeReport(elapsed: 4, baseline: counters(), current: end, notes: [])
        XCTAssertNil(report.cpuSeconds); XCTAssertNil(report.meanCPUPercentOneCore)
        XCTAssertNil(report.voluntaryContextSwitches); XCTAssertNil(report.interruptWakeups)
        XCTAssertNil(report.packageIdleWakeups); XCTAssertNil(report.packageIdleWakeupsPerSecond)
        XCTAssertNil(report.peakResidentBytes)
        let absentBaseline = PerformanceMeasurement.makeReport(elapsed: 4, baseline: counters(cpu: nil, voluntary: nil, interrupts: nil), current: counters(), notes: [])
        XCTAssertNil(absentBaseline.cpuSeconds); XCTAssertNil(absentBaseline.voluntaryContextSwitches); XCTAssertNil(absentBaseline.interruptWakeups)
    }
    func testInvalidDurationAndNonfiniteCPUDoNotProduceRates() {
        let report = PerformanceMeasurement.makeReport(elapsed: 0, baseline: counters(), current: counters(cpu: .infinity), notes: [])
        XCTAssertNil(report.cpuSeconds); XCTAssertNil(report.meanCPUPercentOneCore)
        XCTAssertNil(report.interruptWakeupsPerSecond); XCTAssertNil(report.packageIdleWakeupsPerSecond)
    }
    func testRealOwnProcessMeasurementAdvancesMonotonically() throws {
        let measurement = PerformanceMeasurement()
        let before = measurement.report(notes: [])
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(5))
        while ContinuousClock.now < deadline { _ = sqrt(123.45) }
        let after = measurement.report(notes: [])
        XCTAssertGreaterThan(after.elapsedSeconds, before.elapsedSeconds)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(after.cpuSeconds), 0)
        XCTAssertGreaterThan(try XCTUnwrap(after.peakResidentBytes), 0)
        _ = try JSONEncoder().encode(after)
    }
}
