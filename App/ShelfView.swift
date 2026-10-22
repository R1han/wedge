import AppKit
import SwiftUI
import WedgeCore

private extension FileFormat {
    var isImage: Bool { category == .image }
    var isLossyImage: Bool { isImage && ["jpeg", "heic", "webp"].contains(id) }
}

struct ShelfView: View {
    @ObservedObject var model: ConversionModel

    @State private var selectedTarget: FileFormat?
    @State private var quality = 0.8
    @State private var stripMetadata = false
    @State private var maxDimensionText = ""
    @State private var replaceExisting = false
    @State private var outputDirectory: URL?
    @State private var isDropTargeted = false

    private var target: FileFormat? {
        if let selectedTarget, model.targets.contains(selectedTarget) { return selectedTarget }
        return model.targets.first
    }

    private var hasConvertibleItems: Bool { model.items.contains(where: \.isConvertible) }
    private var noCommonFormat: Bool { hasConvertibleItems && model.targets.isEmpty }
    private var canConvert: Bool { target.map(model.hasWork(for:)) ?? false }

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(minWidth: 420, minHeight: 320)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            Task { model.add(await DropHandler.urls(from: providers)) }
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
            if noCommonFormat {
                Text("These files have no common format \u{2014} remove some to continue")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            HStack {
                Picker("Convert to", selection: Binding(get: { target }, set: { selectedTarget = $0 })) {
                    ForEach(model.targets, id: \.id) { format in
                        Text(format.id.uppercased()).tag(Optional(format))
                    }
                }
                .frame(maxWidth: 200)
                .disabled(model.targets.isEmpty || model.isConverting)
                Spacer()
                outputMenu
            }
            if let target, target.isImage { imageOptions(for: target) }
            Toggle("Replace existing files", isOn: $replaceExisting)
                .disabled(model.isConverting)
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
            Button("Next to originals") { outputDirectory = nil }
            Button("Choose folder\u{2026}", action: chooseOutputFolder)
        } label: {
            Text(outputDirectory.map { "Save to \($0.lastPathComponent)" } ?? "Save next to originals")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.isConverting)
        .accessibilityLabel("Output location")
    }

    private func imageOptions(for target: FileFormat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if target.isLossyImage {
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
                    .accessibilityLabel("Maximum dimension in pixels")
            }
        }
        .disabled(model.isConverting)
    }

    private func convert() {
        guard let target else { return }
        let maxDimension = Int(maxDimensionText.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
        let options = ConversionOptions(
            quality: target.isLossyImage ? quality : nil,
            maxDimension: target.isImage ? maxDimension : nil,
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
        if panel.runModal() == .OK { model.add(panel.urls) }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { outputDirectory = panel.url }
    }
}

private struct ShelfRow: View {
    let item: ConversionModel.Item
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
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
            if case .done(let outputs, _) = item.state {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
                    .controlSize(.small)
                    .accessibilityLabel("Reveal \(item.url.lastPathComponent) output in Finder")
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
