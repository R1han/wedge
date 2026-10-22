import AppKit
import SwiftUI
import WedgeCore

private extension FileFormat {
    var isImage: Bool { category == .image }
}

struct ShelfView: View {
    @ObservedObject var model: ConversionModel
    @ObservedObject var settings: SettingsModel

    @State private var choices = ShelfChoices()
    @State private var quality = 0.8
    @State private var stripMetadata = false
    @State private var maxDimensionText = ""
    @State private var replaceExisting = false
    @State private var isDropTargeted = false

    private var target: FileFormat? {
        if let selected = choices.target, model.targets.contains(selected) { return selected }
        return settings.preferredTarget(among: model.targets) ?? model.targets.first
    }

    private var resolvedOutput: (url: URL?, note: String?) {
        switch choices.output {
        case .nextToOriginals: (nil, nil)
        case .folder(let url): settings.resolveOutputFolder(url)
        case nil: settings.resolveOutputFolder()
        }
    }

    private var outputDirectory: URL? { resolvedOutput.url }

    private var hasConvertibleItems: Bool { model.items.contains(where: \.isConvertible) }
    private var noCommonFormat: Bool { hasConvertibleItems && model.targets.isEmpty }
    private var maxDimension: MaxDimensionInput { MaxDimensionInput.parse(maxDimensionText) }
    private var maxDimensionIsInvalid: Bool {
        guard let target, target.isImage else { return false }
        return maxDimension == .invalid
    }
    private var canConvert: Bool { !maxDimensionIsInvalid && (target.map(model.hasWork(for:)) ?? false) }

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(minWidth: 420, minHeight: 320)
        .onChange(of: model.items.isEmpty) { choices.itemsChanged(isEmpty: $0) }
        .onChange(of: settings.outputFolder) { _ in choices.savedFolderChanged() }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            Task { model.addDropped(await DropHandler.urls(from: providers)) }
            return true
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Drop files here")
                    .font(.title3)
                Button("Add Files\u{2026}", action: addFiles)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(dropHighlight)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.items) { item in
                        ShelfRow(item: item, canRemove: !model.isConverting) { model.remove(item.id) }
                        Divider()
                    }
                }
            }
            .background(dropHighlight)
        }
    }

    private var dropHighlight: some View {
        Color.accentColor.opacity(isDropTargeted ? 0.12 : 0)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let notice = model.notice {
                NoticeText(text: notice)
            }
            if let note = resolvedOutput.note { NoticeText(text: note) }
            if noCommonFormat {
                NoticeText(text: "These files have no common format \u{2014} remove some to continue")
            }
            HStack {
                if model.targets.isEmpty {
                    Text("No format available")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Convert to", selection: Binding(get: { target }, set: { choices.target = $0 })) {
                        ForEach(model.targets, id: \.id) { format in
                            Text(format.id.uppercased()).tag(Optional(format))
                        }
                    }
                    .frame(maxWidth: 200)
                    .disabled(model.isConverting)
                }
                Spacer()
                outputMenu
            }
            if let target, target.isImage { imageOptions(for: target) }
            Toggle("Replace existing files", isOn: $replaceExisting)
                .disabled(model.isConverting)
            if replaceExisting {
                Text("Files with the same name will be overwritten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Add Files\u{2026}", action: addFiles)
                    .disabled(model.isConverting)
                Button("Clear") { model.clear() }
                    .disabled(model.items.isEmpty || model.isConverting)
                Spacer()
                if model.isConverting {
                    Button("Cancel") { model.cancel() }
                } else {
                    Button("Convert", action: convert)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canConvert)
                }
            }
        }
        .padding(12)
    }

    private var outputMenu: some View {
        Menu {
            Toggle("Next to originals", isOn: Binding(get: { outputDirectory == nil }, set: { _ in choices.output = .nextToOriginals }))
            Toggle(
                outputDirectory.map { "Folder: \($0.lastPathComponent)" } ?? "Choose folder\u{2026}",
                isOn: Binding(get: { outputDirectory != nil }, set: { _ in chooseOutputFolder() })
            )
        } label: {
            Text(outputDirectory.map { "Save to \($0.lastPathComponent)" } ?? "Save next to originals")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(outputDirectory?.path ?? "Converted files are saved next to the originals")
        .disabled(model.isConverting)
    }

    private func imageOptions(for target: FileFormat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if target.supportsQuality {
                HStack {
                    Text("Quality")
                    Slider(value: $quality, in: 0...1)
                        .accessibilityLabel("Quality")
                        .accessibilityValue("\(Int(quality * 100)) percent")
                    Text("\(Int(quality * 100))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                        .accessibilityHidden(true)
                }
            }
            HStack {
                Toggle("Strip metadata", isOn: $stripMetadata)
                Spacer()
                TextField("Max size (px)", text: $maxDimensionText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .onChange(of: maxDimensionText) { text in
                        let digits = text.filter { $0.isASCII && $0.isNumber }
                        if digits != text { maxDimensionText = digits }
                    }
            }
            if maxDimensionIsInvalid {
                Text("Enter a whole number from \(MaxDimensionInput.range.lowerBound) to \(MaxDimensionInput.range.upperBound).")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .disabled(model.isConverting)
    }

    private func convert() {
        guard let target else { return }
        var limit: Int?
        if target.isImage, case .valid(let value) = maxDimension { limit = value }
        let options = ConversionOptions(
            quality: target.supportsQuality ? quality : nil,
            maxDimension: limit,
            stripMetadata: target.isImage && stripMetadata,
            force: replaceExisting
        )
        let directory = outputDirectory
        Task { await model.convert(to: target, options: options, outputDirectory: directory) }
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        present(panel) { model.add(panel.urls) }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        present(panel) { panel.url.map { choices.output = .folder($0) } }
    }

    /// Shows the panel as a sheet on the shelf (or free-standing if it has no window), without blocking the run loop.
    private func present(_ panel: NSOpenPanel, onOK: @escaping () -> Void) {
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK { onOK() }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }
}

private struct ShelfRow: View {
    let item: ConversionModel.Item
    let canRemove: Bool
    let onRemove: () -> Void

    @State private var icon: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: icon ?? NSImage())
                    .resizable()
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                    .onAppear { if icon == nil { icon = NSWorkspace.shared.icon(forFile: item.url.path) } }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    stateView
                        .font(.caption)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.url.lastPathComponent), \(Self.description(of: item.state))")
            Spacer()
            if case .done(let outputs, _) = item.state, !outputs.isEmpty {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
                    .controlSize(.small)
                    .accessibilityHint("Output of \(item.url.lastPathComponent)")
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .disabled(!canRemove)
            .accessibilityLabel("Remove \(item.url.lastPathComponent)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var stateView: some View {
        switch item.state {
        case .running(let fraction):
            ProgressView(value: fraction)
                .frame(maxWidth: 160)
        case .failed(let message):
            Text(message).foregroundStyle(.red).lineLimit(2)
        case .unsupported(let reason):
            Text("Can't convert \u{2014} \(reason)").foregroundStyle(.orange)
        default:
            Text(Self.description(of: item.state)).foregroundStyle(.secondary)
        }
    }

    static func description(of state: ConversionModel.ItemState) -> String {
        switch state {
        case .pending: "Ready"
        case .running(let fraction): "Converting, \(Int(fraction * 100)) percent"
        case .done(_, let format): "Converted to \(format.id.uppercased())"
        case .failed(let message): "Failed, \(message)"
        case .cancelled: "Cancelled"
        case .unsupported(let reason): "Can't convert, \(reason)"
        }
    }
}
