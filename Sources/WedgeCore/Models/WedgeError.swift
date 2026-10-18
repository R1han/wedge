import Foundation

public enum WedgeError: Error, Equatable {
    case inputNotFound(URL)
    case unsupportedConversion(from: String, to: String)
    case outputExists(URL)
    case resourceLimitExceeded(String)
    case toolFailed(tool: String, code: Int32, message: String)
    case toolNotInstalled(tool: String, installHint: String)
    case cancelled
    case invalidInput(String)
}
