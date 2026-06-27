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
        
        // Setup gorgeous programmatic app icon
        NSApp.applicationIconImage = createProgrammaticAppIcon()
        
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
    
    private func createProgrammaticAppIcon() -> NSImage {
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()
        
        // Draw rounded squircle
        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 20, dy: 20)
        let path = NSBezierPath(roundedRect: rect, xRadius: 110, yRadius: 110)
        
        // Create a beautiful vibrant magenta-purple gradient background
        let gradient = NSGradient(starting: NSColor(calibratedRed: 0.95, green: 0.25, blue: 0.45, alpha: 1.0),
                                  ending: NSColor(calibratedRed: 0.35, green: 0.15, blue: 0.85, alpha: 1.0))
        gradient?.draw(in: path, angle: 45)
        
        // Draw subtle glass inner glow
        path.lineWidth = 12
        NSColor.white.withAlphaComponent(0.25).setStroke()
        path.stroke()
        
        // Draw elegant overlapping musical note + clock hands
        let center = NSPoint(x: rect.midX, y: rect.midY)
        
        // 1. Clock Circle / Dial
        let clockRect = rect.insetBy(dx: 110, dy: 110)
        let clockPath = NSBezierPath(ovalIn: clockRect)
        clockPath.lineWidth = 14
        NSColor.white.withAlphaComponent(0.5).setStroke()
        clockPath.stroke()
        
        // Clock Hands
        let handsPath = NSBezierPath()
        handsPath.move(to: center)
        handsPath.line(to: NSPoint(x: center.x, y: center.y + 90)) // Minute Hand
        handsPath.move(to: center)
        handsPath.line(to: NSPoint(x: center.x + 60, y: center.y - 20)) // Hour Hand
        handsPath.lineWidth = 16
        handsPath.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.85).setStroke()
        handsPath.stroke()
        
        // 2. Beautiful overlapping music note
        let notePath = NSBezierPath()
        // Left note head
        notePath.appendOval(in: NSRect(x: center.x - 70, y: center.y - 80, width: 45, height: 35))
        // Left stem
        notePath.move(to: NSPoint(x: center.x - 25, y: center.y - 65))
        notePath.line(to: NSPoint(x: center.x - 25, y: center.y + 70))
        // Right note head
        notePath.appendOval(in: NSRect(x: center.x + 15, y: center.y - 50, width: 45, height: 35))
        // Right stem
        notePath.move(to: NSPoint(x: center.x + 60, y: center.y - 35))
        notePath.line(to: NSPoint(x: center.x + 60, y: center.y + 100))
        // Beam
        notePath.move(to: NSPoint(x: center.x - 25, y: center.y + 60))
        notePath.line(to: NSPoint(x: center.x + 60, y: center.y + 90))
        notePath.line(to: NSPoint(x: center.x + 60, y: center.y + 115))
        notePath.line(to: NSPoint(x: center.x - 25, y: center.y + 85))
        notePath.close()
        
        NSColor.white.setFill()
        notePath.fill()
        
        image.unlockFocus()
        return image
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
