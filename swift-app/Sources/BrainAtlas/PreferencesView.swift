import SwiftUI
import AppKit
import Foundation

// MARK: - AppSettings

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var sourceDir: String {
        didSet { UserDefaults.standard.set(sourceDir, forKey: Keys.sourceDir) }
    }
    @Published var bridgePort: Int {
        didSet { UserDefaults.standard.set(bridgePort, forKey: Keys.bridgePort) }
    }
    @Published var httpPort: Int {
        didSet { UserDefaults.standard.set(httpPort, forKey: Keys.httpPort) }
    }

    private enum Keys {
        static let sourceDir  = "BrainAtlas.sourceDir"
        static let bridgePort = "BrainAtlas.bridgePort"
        static let httpPort   = "BrainAtlas.httpPort"
    }

    private init() {
        let storedDir   = UserDefaults.standard.string(forKey: Keys.sourceDir)
        let storedBridge = UserDefaults.standard.integer(forKey: Keys.bridgePort)
        let storedHttp   = UserDefaults.standard.integer(forKey: Keys.httpPort)

        sourceDir   = storedDir?.isEmpty == false ? storedDir! : "~/Documents/notes"
        bridgePort  = storedBridge > 0 ? storedBridge : 8766
        httpPort    = storedHttp > 0   ? storedHttp   : 8765
    }

    // MARK: Computed

    var sourceDirURL: URL? {
        let expanded = (sourceDir as NSString).expandingTildeInPath
        guard !expanded.isEmpty else { return nil }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    var isConfigured: Bool {
        guard !sourceDir.isEmpty, let url = sourceDirURL else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: Persistence

    func save() {
        UserDefaults.standard.set(sourceDir,  forKey: Keys.sourceDir)
        UserDefaults.standard.set(bridgePort, forKey: Keys.bridgePort)
        UserDefaults.standard.set(httpPort,   forKey: Keys.httpPort)
        writeConfigJSON()
    }

    private func writeConfigJSON() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("BrainAtlas", isDirectory: true)

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let config: [String: Any] = [
            "sourceDir":   sourceDir,
            "bridgePort":  bridgePort,
            "httpPort":    httpPort
        ]
        let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try? data?.write(to: dir.appendingPathComponent("config.json"))
    }

    // MARK: Onboarding

    static func showOnboardingIfNeeded() {
        guard !shared.isConfigured else { return }
        DispatchQueue.main.async {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - PreferencesView

struct PreferencesView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var saveState: SaveState = .idle

    private enum SaveState {
        case idle, success, error(String)
    }

    // Palette
    private let bg         = Color(hex: "#0B0F19")
    private let accent     = Color(hex: "#4cc3ff")
    private let dimText    = Color(hex: "#6b7593")
    private let surface    = Color(white: 1, opacity: 0.05)
    private let border     = Color(white: 1, opacity: 0.08)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(border)
                form
                Divider().background(border)
                footer
            }
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(.dark)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain")
                .font(.system(size: 36, weight: .thin))
                .foregroundColor(accent)
                .padding(.top, 28)

            Text("Brain Atlas")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            Text("Configurações do visualizador")
                .font(.system(size: 12))
                .foregroundColor(dimText)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Source directory
            fieldGroup(label: "Pasta de notas") {
                HStack(spacing: 8) {
                    TextField("~/Documents/notes", text: $settings.sourceDir)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(surface)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(border, lineWidth: 1)
                        )

                    Button("Escolher…") { pickDirectory() }
                        .buttonStyle(AccentButtonStyle(accent: accent))
                }

                statusLabel
            }

            // Bridge port
            fieldGroup(label: "Porta do Bridge (app nativo)") {
                portField(value: $settings.bridgePort,
                          placeholder: "8766",
                          helpText: "Servidor WebSocket embutido no app Swift")
            }

            // HTTP port
            fieldGroup(label: "Porta HTTP (arquivos estáticos)") {
                portField(value: $settings.httpPort,
                          placeholder: "8765",
                          helpText: "Servidor iniciado pelo start.sh")
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            feedbackLabel
            Spacer()
            Button("Salvar") { performSave() }
                .buttonStyle(PrimaryButtonStyle(accent: accent))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }

    // MARK: Sub-views

    private var statusLabel: some View {
        HStack(spacing: 5) {
            if settings.isConfigured {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Configurado")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text("sourceDir não encontrado")
                    .foregroundColor(.yellow)
            }
        }
        .font(.system(size: 11))
    }

    @ViewBuilder
    private var feedbackLabel: some View {
        switch saveState {
        case .idle:
            EmptyView()
        case .success:
            Label("Salvo com sucesso", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.green)
                .transition(.opacity)
        case .error(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.red)
                .transition(.opacity)
        }
    }

    // MARK: Helpers

    @ViewBuilder
    private func fieldGroup<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(dimText)
            content()
        }
    }

    @ViewBuilder
    private func portField(value: Binding<Int>, placeholder: String, helpText: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField(placeholder, value: value, formatter: portFormatter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(width: 100)
                    .background(surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(border, lineWidth: 1)
                    )

                Text(helpText)
                    .font(.system(size: 11))
                    .foregroundColor(dimText)
            }
        }
    }

    private var portFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 1024
        f.maximum = 65535
        return f
    }

    private func pickDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Escolher pasta de notas"
        panel.message = "Selecione a pasta que contém seus arquivos .md"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.sourceDirURL ?? FileManager.default.homeDirectoryForCurrentUser

        if panel.runModal() == .OK, let url = panel.url {
            // Store as tilde-abbreviated path when possible
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let path = url.path
            settings.sourceDir = path.hasPrefix(home)
                ? "~" + path.dropFirst(home.count)
                : path
        }
    }

    private func performSave() {
        guard settings.bridgePort >= 1024, settings.bridgePort <= 65535,
              settings.httpPort   >= 1024, settings.httpPort   <= 65535 else {
            withAnimation { saveState = .error("Porta fora do intervalo 1024–65535") }
            return
        }
        settings.save()
        withAnimation { saveState = .success }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { saveState = .idle }
        }
    }
}

// MARK: - Button Styles

private struct AccentButtonStyle: ButtonStyle {
    let accent: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(accent.opacity(configuration.isPressed ? 0.15 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(accent.opacity(0.3), lineWidth: 1)
            )
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    let accent: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color(hex: "#0B0F19"))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(accent.opacity(configuration.isPressed ? 0.75 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - Color hex helper

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >>  8) & 0xFF) / 255
            b = Double( int        & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}

