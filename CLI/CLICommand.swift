import Foundation

enum CLICommand {
    enum Action: String {
        case open, reveal, terminal
    }

    enum Parsed {
        case command(action: Action, url: URL)
        case help
    }

    enum Failure: Error, CustomStringConvertible {
        case missingPath(String)
        case notFound(String)
        case notDirectory(String)

        var description: String {
            switch self {
            case .missingPath(let cmd): return "\(cmd) requires a path argument"
            case .notFound(let path): return "no such file or directory: \(path)"
            case .notDirectory(let path): return "not a directory: \(path)"
            }
        }
    }

    static func parse(
        _ arguments: [String],
        cwd: String,
        fileExists: (_ path: String) -> (exists: Bool, isDirectory: Bool) = defaultFileExists
    ) throws -> Parsed {
        let args = Array(arguments.dropFirst())

        if args.isEmpty {
            return try makeCommand(.open, path: cwd, requireDirectory: true, fileExists: fileExists)
        }

        let first = args[0]

        if first == "help" || first == "-h" || first == "--help" {
            return .help
        }

        if let action = Action(rawValue: first) {
            switch action {
            case .open:
                let path = args.count > 1 ? resolvePath(args[1], cwd: cwd) : cwd
                return try makeCommand(.open, path: path, requireDirectory: true, fileExists: fileExists)
            case .reveal:
                guard args.count > 1 else { throw Failure.missingPath("reveal") }
                let path = resolvePath(args[1], cwd: cwd)
                return try makeCommand(.reveal, path: path, requireDirectory: false, fileExists: fileExists)
            case .terminal:
                let path = args.count > 1 ? resolvePath(args[1], cwd: cwd) : cwd
                return try makeCommand(.terminal, path: path, requireDirectory: true, fileExists: fileExists)
            }
        }

        let path = resolvePath(first, cwd: cwd)
        let status = fileExists(path)
        guard status.exists else { throw Failure.notFound(first) }
        let action: Action = status.isDirectory ? .open : .reveal
        return .command(action: action, url: buildURL(action: action, path: path))
    }

    static func resolvePath(_ input: String, cwd: String) -> String {
        var path = input
        if path.hasPrefix("~") {
            path = (path as NSString).expandingTildeInPath
        }
        if !path.hasPrefix("/") {
            path = (cwd as NSString).appendingPathComponent(path)
        }
        return (path as NSString).standardizingPath
    }

    static func buildURL(action: Action, path: String) -> URL {
        var components = URLComponents()
        components.scheme = "pathdeck"
        components.host = action.rawValue
        components.queryItems = [URLQueryItem(name: "path", value: path)]
        return components.url!
    }

    static let usage = """
        Usage: pathdeck [command] [path]

        Commands:
          open [path]       Open directory in PathDeck (default: current directory)
          reveal <path>     Reveal file in PathDeck
          terminal [path]   Open terminal at directory (default: current directory)
          help              Show this help message

        If no command is given:
          pathdeck              Open current directory
          pathdeck <directory>  Open directory
          pathdeck <file>       Reveal file
        """

    // MARK: - Private

    private static func makeCommand(
        _ action: Action,
        path: String,
        requireDirectory: Bool,
        fileExists: (_ path: String) -> (exists: Bool, isDirectory: Bool)
    ) throws -> Parsed {
        let status = fileExists(path)
        guard status.exists else { throw Failure.notFound(path) }
        if requireDirectory && !status.isDirectory {
            throw Failure.notDirectory(path)
        }
        return .command(action: action, url: buildURL(action: action, path: path))
    }

    static func defaultFileExists(_ path: String) -> (exists: Bool, isDirectory: Bool) {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return (exists, isDir.boolValue)
    }
}
