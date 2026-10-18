import ArgumentParser
import WedgeCore

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list", abstract: "List supported conversions.")

    func execute(output: CLIOutput) -> Int32 {
        for pair in Wedge.defaultRegistry().pairs() {
            output.writeOut("\(pair.from.id) -> \(pair.to.id)")
        }
        return 0
    }
}
