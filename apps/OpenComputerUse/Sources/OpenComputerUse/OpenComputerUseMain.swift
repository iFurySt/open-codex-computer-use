import AppKit
import Foundation
import OpenComputerUseKit

@main
enum OpenComputerUseMain {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let service = ComputerUseService()

        switch arguments.first {
        case "mcp":
            try StdioMCPServer(service: service).run()
        case "doctor":
            let permissions = PermissionDiagnostics.current()
            print(permissions.summary)
        case "list-apps":
            print(service.listApps().primaryText ?? "")
        case "snapshot":
            guard arguments.count >= 2 else {
                throw ComputerUseError.invalidArguments("snapshot requires an app name or bundle identifier")
            }
            print(try service.getAppState(app: arguments[1]).primaryText ?? "")
        case "turn-ended":
            print("turn-ended acknowledged")
        default:
            if arguments.first == "help" || arguments.first == "--help" || arguments.first == "-h" {
                print(
                    """
                    OpenComputerUse

                    Usage:
                      OpenComputerUse
                      OpenComputerUse mcp
                      OpenComputerUse doctor
                      OpenComputerUse list-apps
                      OpenComputerUse snapshot <app>
                      OpenComputerUse turn-ended
                    """
                )
            } else {
                PermissionOnboardingApp.launch()
            }
        }
    }
}
