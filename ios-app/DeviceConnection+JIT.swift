import Foundation
import SideInstallerFFI
import JavaScriptCore

extension DeviceConnection {
    func launchAppForJIT(bundleID: String) throws -> Int32 {
        guard let adapter, let handshake else { throw fail("not connected") }
        
        var server: OpaquePointer?
        try check(remote_server_connect_rsd(adapter, handshake, &server),
                  "remote_server_connect_rsd failed (is the developer disk image mounted?)")
        guard let server else { throw fail("remote server handle was null") }
        defer { remote_server_free(server) }
        
        var processControl: OpaquePointer?
        try check(process_control_new(server, &processControl), "process_control_new failed")
        guard let processControl else { throw fail("process control handle was null") }
        defer { process_control_free(processControl) }
        
        var pid: UInt64 = 0
        let envs = ["MallocGuardEdges=1", "MallocScribble=1"]
        let mutCEnvs: [UnsafeMutablePointer<CChar>?] = envs.map { strdup($0) }
        let cEnvs: [UnsafePointer<CChar>?] = mutCEnvs.map { UnsafePointer($0) }
        defer { for p in mutCEnvs { free(p) } }
        
        let err = bundleID.withCString { bid in
            cEnvs.withUnsafeBufferPointer { envBuf in
                // process_control_launch_app(client, bundle_id, env_vars, env_count, args, args_count, suspend, kill_existing, pid)
                process_control_launch_app(processControl, bid, envBuf.baseAddress, UInt(envBuf.count), nil, 0, true, false, &pid)
            }
        }
        try check(err, "process_control_launch_app failed")
        return Int32(pid)
    }
    
    func runJITSession(pid: Int32, useScript: Bool, progress: @escaping (String) -> Void) throws {
        guard let adapter, let handshake else { throw fail("not connected") }
        
        var debugProxy: OpaquePointer?
        try check(debug_proxy_connect_rsd(adapter, handshake, &debugProxy), "debug_proxy_connect_rsd failed")
        guard let debugProxy else { throw fail("debug_proxy handle was null") }
        defer { debug_proxy_free(debugProxy) }
        
        if useScript {
            let runner = JITScriptRunner(targetPID: pid, debugProxy: debugProxy, progress: progress)
            try runner.run()
        } else {
            progress("Attaching to pid \(pid). TXM is not present, so the attach alone enables JIT and the script is skipped.")
            _ = sendCommand("vAttach;\(String(pid, radix: 16))", over: debugProxy)
            _ = sendCommand("D", over: debugProxy)
            progress("JIT enabled (debugger attached and detached).")
        }
    }
    
    private func sendCommand(_ command: String, over debugProxy: OpaquePointer) -> String? {
        guard let handle = command.withCString({ debugserver_command_new($0, nil, 0) }) else { return nil }
        defer { debugserver_command_free(handle) }
        var response: UnsafeMutablePointer<CChar>?
        if debug_proxy_send_command(debugProxy, handle, &response) != nil {
            return nil
        }
        guard let response else { return "" }
        defer { idevice_string_free(response) }
        return String(cString: response)
    }
}
