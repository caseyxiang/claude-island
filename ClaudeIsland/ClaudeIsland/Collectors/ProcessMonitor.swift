import Foundation
import OSLog

/// Periodically checks if tracked processes are still alive.
final class ProcessMonitor {
    private let logger = Logger(subsystem: "com.claudeisland", category: "ProcessMonitor")
    private var timer: Timer?

    /// Callback with PID of a process that has died
    var onProcessDied: ((Int) -> Void)?

    /// PIDs currently being monitored
    private var monitoredPids: Set<Int> = []

    func addPid(_ pid: Int) {
        monitoredPids.insert(pid)
    }

    func removePid(_ pid: Int) {
        monitoredPids.remove(pid)
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkProcesses()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkProcesses() {
        for pid in monitoredPids {
            let alive = kill(Int32(pid), 0) == 0
            if !alive {
                logger.info("Process \(pid) is no longer alive")
                monitoredPids.remove(pid)
                onProcessDied?(pid)
            }
        }
    }
}
