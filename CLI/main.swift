import Foundation

do {
    let parsed = try CLICommand.parse(
        CommandLine.arguments,
        cwd: FileManager.default.currentDirectoryPath
    )

    switch parsed {
    case .help:
        print(CLICommand.usage)

    case .command(_, let url):
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [url.absoluteString]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            exit(2)
        }
    }
} catch {
    FileHandle.standardError.write(Data("pathdeck: \(error)\n".utf8))
    exit(1)
}
