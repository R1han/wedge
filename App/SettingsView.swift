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

/// A message with an icon, so its meaning does not rest on colour alone.
struct NoticeText: View {
    enum Kind { case warning, error }

    let text: String
    var kind: Kind = .warning

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: kind == .error ? "xmark.octagon" : "exclamationmark.triangle")
                .foregroundStyle(kind == .error ? .red : .orange)
                .accessibilityLabel(kind == .error ? "Error" : "Warning")
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
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
                .help("Used when a batch can be converted to it; otherwise the first available format is selected")

                outputRow
            }
            Section("Launch at Login") { launchRow }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settings.refreshLaunchAtLogin()
        }
    }

    private var outputRow: some View {
        let resolved = settings.resolveOutputFolder()
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Save converted files")
                Spacer()
                Text(settings.outputFolder?.path ?? "Next to originals")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 200, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            HStack {
                Spacer()
                if settings.outputFolder != nil {
                    Button("Use Next to Originals") { settings.setOutputFolder(nil) }
                }
                Button("Choose Folder\u{2026}", action: chooseFolder)
            }
            if let note = resolved.note { NoticeText(text: note) }
        }
    }

    @ViewBuilder
    private var launchRow: some View {
        let status = settings.launchAtLogin
        Toggle("Open Wedge when I log in", isOn: Binding(
            get: { status == .enabled || status == .requiresApproval },
            set: { settings.setLaunchAtLogin($0) }
        ))
        if status == .requiresApproval {
            VStack(alignment: .leading, spacing: 6) {
                NoticeText(text: "macOS needs your approval before Wedge can open at login.")
                Button("Open Login Items Settings", action: settings.openLoginItemsSettings)
            }
        }
        if status == .notFound {
            NoticeText(text: "macOS can\u{2019}t find Wedge as a login item yet. If turning this on fails, move Wedge to the Applications folder and reopen it.")
        }
        if let error = settings.launchAtLoginError {
            NoticeText(text: error, kind: .error)
        }
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
