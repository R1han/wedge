import ArgumentParser
import WedgeCore

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor", abstract: "Check the external tools Wedge relies on.")

    /// External tools and how to install each one.
    static let tools: [(name: String, hint: String)] = [
        ("pandoc", "brew install pandoc"),
        ("ffmpeg", "brew install ffmpeg"),
    ]

    func execute(output: CLIOutput) -> Int32 {
        for tool in Self.tools {
            if let url = ToolLocator.shared.path(for: tool.name) {
                output.writeOut("\(tool.name): found at \(url.path)")
            } else {
                output.writeOut("\(tool.name): missing (install with: \(tool.hint))")
            }
        }
        return 0
    }
}
