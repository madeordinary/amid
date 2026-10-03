import XCTest
import Darwin
@testable import AmidCore

final class EndpointScopeTests: XCTestCase {
    private func requireSocketResult(_ result: Int32, ipv6: Bool, operation: String) throws {
        guard result >= 0 else {
            let code = errno
            if ipv6 && [EAFNOSUPPORT, EPROTONOSUPPORT, EADDRNOTAVAIL].contains(code) {
                throw XCTSkip("Owned IPv6 \(operation) unavailable on this host (errno \(code)).")
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey: "Owned socket \(operation) failed"])
        }
    }
    private func checkListener(ipv6: Bool, wildcard: Bool) async throws {
        let fd = socket(ipv6 ? AF_INET6 : AF_INET, SOCK_STREAM, 0)
        try requireSocketResult(fd, ipv6: ipv6, operation: "creation")
        defer { Darwin.close(fd) }
        let port: UInt16
        if ipv6 {
            var v6Only: Int32 = 1
            try requireSocketResult(setsockopt(fd, IPPROTO_IPV6, IPV6_V6ONLY, &v6Only, socklen_t(MemoryLayout<Int32>.size)), ipv6: true, operation: "IPv6-only configuration")
            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            let requested = wildcard ? "::" : "::1"
            XCTAssertEqual(inet_pton(AF_INET6, requested, &address.sin6_addr), 1)
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
            try requireSocketResult(bound, ipv6: true, operation: "bind")
            var size = socklen_t(MemoryLayout<sockaddr_in6>.size)
            let named = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) }
            }
            try requireSocketResult(named, ipv6: true, operation: "port lookup")
            port = UInt16(bigEndian: address.sin6_port)
        } else {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = inet_addr(wildcard ? "0.0.0.0" : "127.0.0.1")
            let bound = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            try requireSocketResult(bound, ipv6: false, operation: "bind")
            var size = socklen_t(MemoryLayout<sockaddr_in>.size)
            let named = withUnsafeMutablePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &size) }
            }
            try requireSocketResult(named, ipv6: false, operation: "port lookup")
            port = UInt16(bigEndian: address.sin_port)
        }
        XCTAssertGreaterThan(port, 0)
        try requireSocketResult(listen(fd, 1), ipv6: ipv6, operation: "listen")
        // No connection, accept, request or payload is created. Inspect only this test process's result.
        let sampler = Sampler()
        let snapshot = await sampler.sample()
        let own = try XCTUnwrap(snapshot.processes.first { $0.identity.pid == getpid() })
        XCTAssertEqual(own.identity.uid, getuid())
        XCTAssertEqual(own.portAvailability, .available)
        let expectedFamily = ipv6 ? "IPv6" : "IPv4"
        let endpoints = own.endpoints.filter { $0.port == port && $0.family == expectedFamily }
        XCTAssertEqual(endpoints.count, 1)
        let endpoint = try XCTUnwrap(endpoints.first)
        XCTAssertEqual(endpoint.address, ipv6 ? (wildcard ? "::" : "::1") : (wildcard ? "0.0.0.0" : "127.0.0.1"))
        XCTAssertEqual(endpoint.scope, wildcard ? "All interfaces" : "Loopback")
        print("OWNED_ENDPOINT_SCOPE", expectedFamily, endpoint.address, endpoint.scope, port, endpoints.count)
    }
    func testOwnedIPv6LoopbackMetadata() async throws { try await checkListener(ipv6: true, wildcard: false) }
    func testOwnedIPv4WildcardMetadata() async throws { try await checkListener(ipv6: false, wildcard: true) }
    func testOwnedIPv6WildcardMetadata() async throws { try await checkListener(ipv6: true, wildcard: true) }
}
