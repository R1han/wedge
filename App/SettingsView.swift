import AppKit
import SwiftUI
import WedgeCore

private extension FormatCategory {
    var title: String {
        switch self {
        case .image: "Images"
        case .document: "Documents"
        case .audio: "Audio"
        case .video: "Video"
        case .archive: "Archives"
        case .data: "Data"
        case .other: "Other"
        }
    }

    static let displayOrder: [FormatCategory] = [.image, .document, .audio, .video, .archive, .data, .other]
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsModel

    private var groupedFormats: [(FormatCategory, [FileFormat])] {
        FormatCategory.displayOrder.compactMap { category in
            let formats = FileFormat.known.filter { $0.category == category }.sorted { $0.id < $1.id }
            return formats.isEmpty ? nil : (category, formats)
        }
    }

    var body: some View {
        Form {
            Section("General") {
                Picker("Default format", selection: Binding(get: { settings.defaultFormat }, set: { settings.setDefaultFormat($0) })) {
                    Text("First available").tag(FileFormat?.none)
                    ForEach(groupedFormats, id: \.0) { category, formats in
                        Section(category.title) {
                            ForEach(formats, id: \.id) { format in
                                Text(format.id.uppercased()).tag(Optional(format))
                            }
                        }
                    }
                }
                .accessibilityLabel("Default format")
                .help("Used when a batch can be converted to it; otherwise the first available format is selected")

                outputRow
            }
            Section("Launch at Login") { launchRow }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settings.refreshLaunchAtLogin()
        }
    }

    private var outputRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Save converted files")
                Spacer()
                Text(settings.outputFolder.map { $0.path } ?? "Next to originals")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 200, alignment: .trailing)
                    .accessibilityLabel("Output location")
                    .accessibilityValue(settings.outputFolder?.path ?? "Next to originals")
            }
            HStack {
                Spacer()
                if settings.outputFolder != nil {
                    Button("Use Next to Originals") { settings.setOutputFolder(nil) }
                        .accessibilityLabel("Save converted files next to the originals")
                }
                Button("Choose Folder\u{2026}", action: chooseFolder)
                    .accessibilityLabel("Choose output folder")
            }
            if let note = settings.outputFolderNote {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var launchRow: some View {
        let status = settings.launchAtLogin
        Toggle("Open Wedge when I log in", isOn: Binding(
            get: { status == .enabled || status == .requiresApproval },
            set: { settings.setLaunchAtLogin($0) }
        ))
        .disabled(isUnavailable(status))
        .accessibilityLabel("Launch at login")
        if status == .requiresApproval {
            VStack(alignment: .leading, spacing: 6) {
                Text("macOS needs your approval before Wedge can open at login.")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Button("Open Login Items Settings", action: settings.openLoginItemsSettings)
                    .accessibilityLabel("Open Login Items Settings")
            }
        }
        if case .unavailable(let reason) = status {
            Text(reason)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if let error = settings.launchAtLoginError {
            Text(error)
                .font(.callout)
                .foregroundStyle(.red)
        }
    }

    private func isUnavailable(_ status: LoginItemStatus) -> Bool {
        if case .unavailable = status { return true }
        return false
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url { settings.setOutputFolder(url) }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }
}
