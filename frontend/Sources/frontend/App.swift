import SwiftUI
import AppKit
import Foundation

@main
struct AudioSchedulerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .frame(minWidth: 1050, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Force the application to show in the Dock and have menu bar
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        // Start Python backend
        BackendManager.shared.start()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Ensure child backend is terminated
        BackendManager.shared.stop()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

class BackendManager {
    static let shared = BackendManager()
    private var process: Process?
    let port: Int = 18088
    
    private init() {}
    
    private func locateBackendExecutable() -> (path: String, args: [String]) {
        // 1. Try to find the compiled binary inside the app bundle
        if let bundlePath = Bundle.main.path(forResource: "backend", ofType: nil) {
            return (bundlePath, [])
        }
        
        // Alternate app bundle path (Contents/MacOS/backend)
        let mainBundleURL = Bundle.main.bundleURL
        let macosDir = mainBundleURL.appendingPathComponent("Contents/MacOS")
        let backendInMacos = macosDir.appendingPathComponent("backend").path
        if FileManager.default.fileExists(atPath: backendInMacos) {
            return (backendInMacos, [])
        }
        
        // 2. Fallback to development folders relative to current working directory
        let workingDirectory = FileManager.default.currentDirectoryPath
        let scriptPath = "\(workingDirectory)/backend/main.py"
        let venvPython = "\(workingDirectory)/backend/venv/bin/python3"
        
        if FileManager.default.fileExists(atPath: venvPython) && FileManager.default.fileExists(atPath: scriptPath) {
            return (venvPython, [scriptPath])
        }
        
        if FileManager.default.fileExists(atPath: scriptPath) {
            return ("/usr/bin/env", ["python3", scriptPath])
        }
        
        // Fallback default
        return ("/usr/bin/env", ["python3", "main.py"])
    }
    
    func start() {
        let (execPath, baseArgs) = locateBackendExecutable()
        print("Starting backend from: \(execPath) with args: \(baseArgs)")
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: execPath)
        proc.arguments = baseArgs + ["--port", String(port)]
        
        // Suppress stdout/stderr to prevent console flooding unless troubleshooting
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                print("[Backend Output]: \(str.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }
        
        do {
            try proc.run()
            self.process = proc
            print("Backend process started successfully with PID: \(proc.processIdentifier)")
        } catch {
            print("Failed to execute backend process: \(error)")
        }
    }
    
    func stop() {
        guard let proc = self.process, proc.isRunning else {
            return
        }
        print("Terminating backend process (PID: \(proc.processIdentifier))...")
        proc.terminate()
        proc.waitUntilExit()
        print("Backend process terminated.")
        self.process = nil
    }
}
