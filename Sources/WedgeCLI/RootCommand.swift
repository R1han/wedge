import ArgumentParser

struct RootCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wedge",
        abstract: "Convert files between formats, offline.",
        subcommands: [ConvertCommand.self, ListCommand.self, DoctorCommand.self])
}
