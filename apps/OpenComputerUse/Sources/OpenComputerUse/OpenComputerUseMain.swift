import AppKit
import Darwin
import Foundation
import OpenComputerUseKit

@main
enum OpenComputerUseMain {
    static func main() throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command: OpenComputerUseCLICommand

        do {
            command = try parseOpenComputerUseCLI(arguments: arguments)
        } catch let error as OpenComputerUseCLIError {
            writeToStandardError(error.errorDescription ?? error.message)
            exit(EXIT_FAILURE)
        }

        switch command {
        case .mcp:
            let service = ComputerUseService()
            let server = StdioMCPServer(service: service)
            if VisualCursorSupport.isEnabled {
                try MainActor.assumeIsolated {
                    try MCPAppRuntime.run(server: server)
                }
            } else {
                try server.run()
            }
        case .doctor:
            let permissions = PermissionDiagnostics.current()
            print(permissions.summary)
            if !permissions.missingPermissions.isEmpty {
                PermissionOnboardingApp.launch()
            }
        case .listApps:
            let service = ComputerUseService()
            print(service.listApps().primaryText ?? "")
        case let .snapshot(app):
            let service = ComputerUseService()
            print(try service.getAppState(app: app).primaryText ?? "")
        case .turnEnded:
            print("turn-ended acknowledged")
        case let .help(command):
            print(openComputerUseHelpText(command: command))
        case .version:
            print(resolvedOpenComputerUseVersion())
        case .launchOnboarding:
            PermissionOnboardingApp.launch()
        }
    }

    private static func writeToStandardError(_ message: String) {
        guard let data = (message + "\n").data(using: .utf8) else {
            return
        }

        FileHandle.standardError.write(data)
    }
}
