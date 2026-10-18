import Foundation
import WedgeCLI

exit(await WedgeCLI.run(Array(CommandLine.arguments.dropFirst())))
