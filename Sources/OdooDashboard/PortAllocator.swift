import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Ports packages/core/src/ports.ts -- linear scan from BASE_PORT, skipping
/// ports already recorded in the registry, testing freedom with a raw bind.
enum PortAllocator {
    static func isPortFree(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let result = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    static func allocatePort(usedPorts: Set<Int>) throws -> Int {
        for port in Config.basePort..<(Config.basePort + Config.portRangeSize) {
            if usedPorts.contains(port) { continue }
            if isPortFree(port) { return port }
        }
        throw ProcessError(message: "No free port found in range \(Config.basePort)-\(Config.basePort + Config.portRangeSize - 1)")
    }
}
