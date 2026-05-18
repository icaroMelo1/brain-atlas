import AppKit
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private(set) var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only — sem ícone no Dock
        NSApp.setActivationPolicy(.accessory)

        // Inicia o servidor embutido ANTES de abrir a janela
        // para que o HTML consiga chamar localhost:8766 imediatamente
        let port = AppSettings.shared.bridgePort > 0 ? AppSettings.shared.bridgePort : 8766
        Task { await BridgeServer.shared.start(port: port) }

        setupMenuBar()
        openMainWindow()
        AppSettings.showOnboardingIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "brain", accessibilityDescription: "Brain Atlas")
            button.action = #selector(handleStatusItemClick)
            button.target = self
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Abrir Brain Atlas", action: #selector(openMainWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferências…", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Encerrar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func handleStatusItemClick() {
        if let window = mainWindow, window.isVisible {
            window.orderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            openMainWindow()
        }
    }

    // MARK: - Windows

    @objc func openMainWindow() {
        if let existing = mainWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Brain Atlas"
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 0.043, green: 0.059, blue: 0.098, alpha: 1)
        window.contentView = NSHostingView(rootView: ContentView())
        window.center()
        window.setFrameAutosaveName("BrainAtlasMain")
        window.makeKeyAndOrderFront(nil)

        mainWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openPreferences() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
