import Darwin
import Foundation
import os

private let logger = Logger(subsystem: "com.oc-notch.app", category: "ProcessScanner")

/// Scans running processes to find OpenCode instances with HTTP servers.
///
/// All discovery is done via `libproc` (`proc_listpids`, `proc_pidinfo`,
/// `proc_pidfdinfo`) plus `devname()` for TTY resolution — no shell-out to
/// `ps` / `lsof`. This avoids per-PID `fork`/`exec` overhead and removes the
/// fragility of parsing tool output.
actor ProcessScanner {
    /// Find all opencode processes that are listening on a port.
    func findInstances() -> [OCInstance] {
        let pids = findOpenCodePIDs()
        guard pids.isEmpty == false else {
            logger.notice("No opencode processes found")
            return []
        }

        logger.notice("Found \(pids.count) opencode processes")

        var instances: [OCInstance] = []
        for pid in pids {
            if let port = findListeningPort(pid: pid) {
                let instance = OCInstance(
                    id: "pid-\(pid)",
                    pid: pid,
                    port: port,
                    hostname: "127.0.0.1",
                    directory: getCWD(pid: pid),
                    tty: getTTY(pid: pid)
                )
                instances.append(instance)
                logger.notice("Found OpenCode instance: PID \(pid) on port \(port)")
            }
        }

        return instances
    }

    func countProcesses() -> Int {
        findOpenCodePIDs().count
    }

    func findActiveDirectories() -> [String] {
        findOpenCodePIDs().compactMap { getCWD(pid: $0) }
    }

    // MARK: - PID enumeration

    private func findOpenCodePIDs() -> [Int32] {
        // First call with NULL buffer returns the size needed.
        let bufSize = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufSize > 0 else { return [] }

        let capacity = Int(bufSize) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: capacity)
        let written = pids.withUnsafeMutableBufferPointer { buf in
            proc_listpids(
                UInt32(PROC_ALL_PIDS),
                0,
                buf.baseAddress,
                Int32(buf.count * MemoryLayout<pid_t>.size)
            )
        }
        guard written > 0 else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let count = Int(written) / MemoryLayout<pid_t>.size

        var result: [Int32] = []
        for pid in pids.prefix(count) {
            guard pid > 0, pid != ownPID else { continue }
            if procName(pid: pid) == "opencode" {
                result.append(pid)
            }
        }
        return result
    }

    private func procName(pid: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let ret = proc_name(pid, &buf, UInt32(buf.count))
        guard ret > 0 else { return nil }
        return buf.withUnsafeBufferPointer { ptr in
            ptr.baseAddress.map { String(cString: $0) }
        }
    }

    // MARK: - Per-PID lookups

    /// Working directory via `PROC_PIDVNODEPATHINFO` (`pvi_cdir.vip_path`).
    private func getCWD(pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size)
        guard ret == size else { return nil }

        return withUnsafePointer(to: &info.pvi_cdir.vip_path) { tuplePtr in
            tuplePtr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { ptr in
                let str = String(cString: ptr)
                return str.isEmpty ? nil : str
            }
        }
    }

    /// Controlling terminal name via `PROC_PIDTBSDINFO.e_tdev` resolved by
    /// `devname()`. Returns `nil` for processes with no controlling TTY.
    private func getTTY(pid: Int32) -> String? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard ret == size else { return nil }

        let dev = dev_t(bitPattern: info.e_tdev)
        // NODEV (~0) signals "no controlling terminal".
        guard dev != dev_t(bitPattern: ~0) else { return nil }

        guard let namePtr = devname(dev, mode_t(S_IFCHR)) else { return nil }
        let name = String(cString: namePtr)
        guard name.isEmpty == false, name != "??" else { return nil }
        return "/dev/\(name)"
    }

    /// First TCP socket in `LISTEN` state owned by `pid`, via
    /// `PROC_PIDLISTFDS` + `PROC_PIDFDSOCKETINFO`. Returns the host-order
    /// local port, matching what the previous `lsof` parser produced.
    private func findListeningPort(pid: Int32) -> Int? {
        // First call: how many file descriptors does the process have?
        let listSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard listSize > 0 else { return nil }

        let capacity = Int(listSize) / MemoryLayout<proc_fdinfo>.size
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: capacity)
        let written = fds.withUnsafeMutableBufferPointer { buf in
            proc_pidinfo(
                pid,
                PROC_PIDLISTFDS,
                0,
                buf.baseAddress,
                Int32(buf.count * MemoryLayout<proc_fdinfo>.size)
            )
        }
        guard written > 0 else { return nil }
        let count = Int(written) / MemoryLayout<proc_fdinfo>.size

        for entry in fds.prefix(count) {
            guard entry.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) else { continue }

            var sockInfo = socket_fdinfo()
            let sockSize = Int32(MemoryLayout<socket_fdinfo>.size)
            let got = proc_pidfdinfo(
                pid,
                entry.proc_fd,
                PROC_PIDFDSOCKETINFO,
                &sockInfo,
                sockSize
            )
            guard got == sockSize else { continue }
            guard sockInfo.psi.soi_protocol == IPPROTO_TCP else { continue }

            let tcp = sockInfo.psi.soi_proto.pri_tcp
            guard tcp.tcpsi_state == TSI_S_LISTEN else { continue }

            // `insi_lport` is stored in network byte order, packed into an int.
            let netOrder = UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport)
            let port = Int(CFSwapInt16BigToHost(netOrder))
            if port > 0 { return port }
        }
        return nil
    }
}
