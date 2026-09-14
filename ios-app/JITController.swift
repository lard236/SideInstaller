import Foundation
import JavaScriptCore
import SideInstallerFFI

enum JITError: Error, LocalizedError {
    case notConnected
    case notSimulatingLocation
    case invalidResponse(String)
    case scriptExecution(String)
    case ffiError(String)
    case ddiNotMounted
    
    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to device."
        case .notSimulatingLocation: return "Location simulation not active."
        case .invalidResponse(let r): return "Invalid response from debug server: \(r)"
        case .scriptExecution(let e): return "Script execution failed: \(e)"
        case .ffiError(let e): return "FFI Error: \(e)"
        case .ddiNotMounted: return "Developer Disk Image is not mounted."
        }
    }
}

@MainActor
final class JITController: ObservableObject {
    enum State: Equatable {
        case idle
        case preparing
        case launching
        case attaching
        case enabling
        case detaching
        case completed
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var logs: [String] = []
    
    private let engine: Engine
    private let targetBundleID: String
    
    init(engine: Engine, targetBundleID: String) {
        self.engine = engine
        self.targetBundleID = targetBundleID
    }
    
    func log(_ message: String) {
        let timestamp = Date().formatted(Date.FormatStyle(time: .standard))
        logs.append("[\(timestamp)] \(message)")
        engine.log("JIT [\(targetBundleID)]: \(message)")
    }
    
    func enableJIT() async {
        guard state == .idle || case .failed = state else { return }
        state = .preparing
        logs.removeAll()
        
        do {
            log("Ensuring device is paired and tunnel is connected...")
            try await engine.ensurePairingConnection()
            
            log("Ensuring DDI is mounted...")
            let mounted = try await engine.onDeviceQueue { try self.engine.connection.mountedDeveloperImageCount() }
            if mounted == 0 {
                // Not downloading here. We expect DDI to be downloaded via LocationView logic,
                // but if it's already there we mount it.
                if DeveloperDiskImage.isDownloaded {
                    log("Mounting DDI from disk...")
                    try await engine.onDeviceQueue {
                        try self.engine.connection.mountPersonalizedDeveloperImage(
                            imagePath: DeveloperDiskImage.imagePath,
                            trustcachePath: DeveloperDiskImage.trustcachePath,
                            manifestPath: DeveloperDiskImage.manifestPath,
                            progress: { _ in }
                        )
                    }
                } else {
                    log("DDI not found locally. Triggering download...")
                    try await DeveloperDiskImage.downloadMissing { _ in }
                    try await engine.onDeviceQueue {
                        try self.engine.connection.mountPersonalizedDeveloperImage(
                            imagePath: DeveloperDiskImage.imagePath,
                            trustcachePath: DeveloperDiskImage.trustcachePath,
                            manifestPath: DeveloperDiskImage.manifestPath,
                            progress: { _ in }
                        )
                    }
                }
            }
            
            state = .launching
            log("Launching \(targetBundleID)...")
            let pid = try await launchApp(bundleID: targetBundleID)
            log("Launched with PID: \(pid)")
            
            state = .attaching
            let txm = ProcessInfo.processInfo.txmPresence
            log("TXM presence: \(txm.isPresent == true ? "Present" : "Absent")")
            
            try await runJITScript(pid: pid, useScript: txm == .present)
            
            state = .completed
            log("JIT enabled successfully!")
            
        } catch {
            let errorMsg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            log("Failed: \(errorMsg)")
            state = .failed(errorMsg)
        }
    }
    
    private func launchApp(bundleID: String) async throws -> Int32 {
        try await engine.onDeviceQueue {
            return try self.engine.connection.launchAppForJIT(bundleID: bundleID)
        }
    }
    
    private func runJITScript(pid: Int32, useScript: Bool) async throws {
        try await engine.onDeviceQueue {
            try self.engine.connection.runJITSession(pid: pid, useScript: useScript) { [weak self] msg in
                Task { @MainActor in
                    self?.log(msg)
                }
            }
        }
    }
}
