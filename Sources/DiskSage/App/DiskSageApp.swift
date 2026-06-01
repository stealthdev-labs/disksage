import SwiftUI
import AppKit

@main
struct DiskSageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    @StateObject private var license = LicenseManager()

    var body: some Scene {
        WindowGroup("DiskSage") {
            ContentView()
                .environmentObject(state)
                .environmentObject(license)
                .frame(minWidth: 1000, minHeight: 680)
        }
        .windowToolbarStyle(.unified(showsTitle: true))

        Settings {
            SettingsView()
                .environmentObject(state)
                .environmentObject(license)
                .frame(width: 520, height: 460)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launched as an unbundled SPM executable during development: force a
        // normal, focusable, dock-visible app instead of a background accessory.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
