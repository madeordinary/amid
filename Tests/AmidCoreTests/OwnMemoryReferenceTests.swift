import XCTest
import Foundation
import Darwin
@testable import AmidCore

final class OwnMemoryReferenceTests: XCTestCase {
    func testOwnedCurrentFootprintMethodReference() async throws {
        guard ProcessInfo.processInfo.environment["AMID_OWN_MEMORY_REFERENCE"] == "1" else {
            throw XCTSkip("Opt-in disposable own-memory reference fixture")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("amid-owned-memory-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("fixture.c"), binary = directory.appendingPathComponent("fixture")
        try Data(Self.fixture.utf8).write(to: source)
        let compiler = Process(); compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compiler.arguments = ["clang", "-arch", "arm64", "-mmacosx-version-min=15.0", source.path, "-o", binary.path]
        try compiler.run(); compiler.waitUntilExit()
        XCTAssertEqual(compiler.terminationStatus, 0)
        guard compiler.terminationStatus == 0 else { return }
        let child = Process(), input = Pipe(), output = Pipe()
        child.executableURL = binary; child.currentDirectoryURL = directory
        child.standardInput = input; child.standardOutput = output
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) == 0 else { XCTFail("Control pipe unavailable"); return }
        try child.run()
        defer { try? input.fileHandleForWriting.close(); child.waitUntilExit(); _ = try? output.fileHandleForReading.readToEnd() }
        func reference() throws -> [UInt64] {
            // Fixture emits one short line, then waits for the next control command.
            var bytes = Data()
            while true {
                guard let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty else { throw NSError(domain: "OwnedReferenceEOF", code: 1) }
                if byte[0] == 10 { break }
                bytes.append(byte)
                guard bytes.count < 160 else { throw NSError(domain: "OwnedReferenceRecord", code: 1) }
            }
            let values = String(decoding: bytes, as: UTF8.self).split(separator: " ").compactMap { UInt64($0) }
            XCTAssertEqual(values.count, 3)
            guard values.count == 3 else { throw NSError(domain: "OwnedReferenceRecord", code: 2) }
            return values
        }
        let before = try reference()
        XCTAssertEqual(before[0], UInt64(child.processIdentifier))
        let resolved = try XCTUnwrap(realpath(binary.path, nil)); let executable = String(cString: resolved); free(resolved)
        let sampler = Sampler()
        let start = ContinuousClock.now
        let first = await sampler.sample()
        let owned = try XCTUnwrap(first.processes.first { $0.identity.pid == child.processIdentifier })
        XCTAssertEqual(owned.identity.uid, getuid()); XCTAssertEqual(owned.executable, executable)
        XCTAssertEqual(owned.memoryMethod, .footprint)
        let measured = try XCTUnwrap(owned.memoryBytes)
        try input.fileHandleForWriting.write(contentsOf: Data("r".utf8))
        let after = try reference()
        XCTAssertEqual(after[0], before[0])
        XCTAssertLessThan(start.duration(to: .now), .seconds(10), "Sample/reference must finish within the child deadline")
        let confirm = await sampler.sample()
        let same = try XCTUnwrap(confirm.processes.first { $0.identity == owned.identity })
        XCTAssertEqual(same.executable, executable); XCTAssertEqual(same.identity.uid, getuid())
        let allowance: UInt64 = 1_048_576
        let lower = min(before[2], after[2]), upper = max(before[2], after[2])
        XCTAssertGreaterThanOrEqual(measured, lower > allowance ? lower - allowance : 0)
        XCTAssertLessThanOrEqual(measured, upper + allowance)
        print("OWNED_MEMORY_REFERENCE allocationBytes=67108864 beforeRSS=\(before[1]) afterRSS=\(after[1]) beforeFootprint=\(before[2]) afterFootprint=\(after[2]) measuredFootprint=\(measured) allowanceBytes=1048576 expectedOwners=1 observedOwners=1")
        try input.fileHandleForWriting.write(contentsOf: Data("x".utf8))
        child.waitUntilExit(); XCTAssertEqual(child.terminationStatus, 0)
    }
    private static let fixture = """
    #include <mach/mach.h>
    #include <mach/task_info.h>
    #include <mach/mach_time.h>
    #include <stddef.h>
    #include <stdint.h>
    #include <stdio.h>
    #include <stdlib.h>
    #include <poll.h>
    #include <unistd.h>
    static int report(void) {
      struct mach_task_basic_info basic={0}; mach_msg_type_number_t bc=MACH_TASK_BASIC_INFO_COUNT;
      task_vm_info_data_t vm={0}; mach_msg_type_number_t vc=TASK_VM_INFO_COUNT;
      if(task_info(mach_task_self(),MACH_TASK_BASIC_INFO,(task_info_t)&basic,&bc)!=KERN_SUCCESS ||
         (size_t)bc*sizeof(natural_t)<offsetof(struct mach_task_basic_info,resident_size)+sizeof(basic.resident_size))return 11;
      if(task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&vm,&vc)!=KERN_SUCCESS ||
         (size_t)vc*sizeof(natural_t)<offsetof(task_vm_info_data_t,phys_footprint)+sizeof(vm.phys_footprint))return 12;
      printf("%d %llu %llu\\n",getpid(),(unsigned long long)basic.resident_size,(unsigned long long)vm.phys_footprint); fflush(stdout); return 0;
    }
    int main(void) {
      const size_t size=64*1024*1024; volatile unsigned char *memory=malloc(size); if(!memory)return 10;
      for(size_t i=0;i<size;i+=(size_t)getpagesize())memory[i]=1;
      int status=report(); if(status)return status;
      // Absolute deadline prevents repeated commands extending fixture lifetime.
      uint64_t deadline=mach_absolute_time(); mach_timebase_info_data_t tb; mach_timebase_info(&tb);
      for(;;) {
        uint64_t delta=mach_absolute_time()-deadline;
        double elapsed=(double)delta*(double)tb.numer/(double)tb.denom/1e9;
        if(elapsed>=15)break;
        struct pollfd control={.fd=STDIN_FILENO,.events=POLLIN};
        int ready=poll(&control,1,(int)((15-elapsed)*1000)); if(ready<=0)break;
        char command; if(read(STDIN_FILENO,&command,1)!=1 || command=='x')break;
        if(command!='r'){status=13;break;} status=report(); if(status)break;
      }
      free((void*)memory); return status;
    }
    """
}
