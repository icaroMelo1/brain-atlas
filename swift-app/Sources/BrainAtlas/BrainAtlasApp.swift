import SwiftUI

@main
struct BrainAtlasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Preferences window (⌘,) — wired in Fase 3
        Settings {
            PreferencesPlaceholderView()
        }
    }
}

// Placeholder until PreferencesView.swift is implemented in Fase 3
private struct PreferencesPlaceholderView: View {
    var body: some View {
        Text("Preferências em breve")
            .frame(width: 400, height: 200)
    }
}
