import Foundation
import Darwin
let fd = socket(AF_INET, SOCK_STREAM, 0)
precondition(fd >= 0)
var address = sockaddr_in()
address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
address.sin_family = sa_family_t(AF_INET)
address.sin_addr.s_addr = inet_addr("127.0.0.1")
let bound = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
}
precondition(bound == 0 && listen(fd, 8) == 0)
var length = socklen_t(MemoryLayout<sockaddr_in>.size)
_ = withUnsafeMutablePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
}
let memory = UnsafeMutableRawPointer.allocate(byteCount: 16 * 1024 * 1024, alignment: 4096)
memset(memory, 1, 16 * 1024 * 1024)
let record: [String: Any] = ["pid": getpid(), "port": UInt16(bigEndian: address.sin_port), "runtime": "swift", "project": FileManager.default.currentDirectoryPath, "memoryBytes": 16 * 1024 * 1024]
print(String(data: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), encoding: .utf8)!)
fflush(stdout)
let lifetime = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 0 : 8
precondition(lifetime >= 1 && lifetime <= 3600)
let began = Date()
while Date().timeIntervalSince(began) < lifetime {
    let elapsed = Date().timeIntervalSince(began)
    if elapsed > 1.5 && elapsed < 3 {
        let end = Date().addingTimeInterval(0.025)
        while Date() < end { _ = sqrt(Double.random(in: 1...10000)) }
    }
    usleep(75000)
}
close(fd)
memory.deallocate()
