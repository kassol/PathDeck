import Foundation

enum ShellIntegration {
    private static let baseDir: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("in.riverflows.PathDeck", isDirectory: true)
            .appendingPathComponent("shell-integration", isDirectory: true)
    }()

    static let zshDir: URL = baseDir.appendingPathComponent("zsh", isDirectory: true)

    static func prepare() {
        writeZshIntegration()
    }

    private static func writeZshIntegration() {
        try? FileManager.default.createDirectory(at: zshDir, withIntermediateDirectories: true)

        let zshenv = zshDir.appendingPathComponent(".zshenv")
        let zshenvScript = """
        # PathDeck shell integration — .zshenv
        [[ -n "$_PATHDECK_INTEGRATION" ]] && return
        _PATHDECK_INTEGRATION=1
        _pd_orig="${PATHDECK_ORIG_ZDOTDIR:-$HOME}"
        ZDOTDIR="$_pd_orig" source "$_pd_orig/.zshenv" 2>/dev/null
        ZDOTDIR="$PATHDECK_ZDOTDIR"
        """
        try? zshenvScript.write(to: zshenv, atomically: true, encoding: .utf8)

        let zshrc = zshDir.appendingPathComponent(".zshrc")
        let zshrcScript = """
        # PathDeck shell integration — .zshrc
        _pd_orig="${PATHDECK_ORIG_ZDOTDIR:-$HOME}"
        ZDOTDIR="$_pd_orig"
        [[ -f "$_pd_orig/.zshrc" ]] && source "$_pd_orig/.zshrc"

        __pathdeck_osc7() {
          local url_path="${PWD// /%20}"
          url_path="${url_path//#/%23}"
          url_path="${url_path//?/%3F}"
          printf '\\e]7;file://%s%s\\e\\\\' "$HOST" "$url_path"
        }
        autoload -Uz add-zsh-hook 2>/dev/null
        if (( $+functions[add-zsh-hook] )); then
          add-zsh-hook precmd __pathdeck_osc7
          add-zsh-hook chpwd __pathdeck_osc7
        else
          precmd_functions+=(__pathdeck_osc7)
          chpwd_functions+=(__pathdeck_osc7)
        fi
        __pathdeck_osc7
        unset _pd_orig _PATHDECK_INTEGRATION
        """
        try? zshrcScript.write(to: zshrc, atomically: true, encoding: .utf8)

        let zshprofile = zshDir.appendingPathComponent(".zprofile")
        let zshprofileScript = """
        # PathDeck shell integration — .zprofile
        _pd_orig="${PATHDECK_ORIG_ZDOTDIR:-$HOME}"
        [[ -f "$_pd_orig/.zprofile" ]] && ZDOTDIR="$_pd_orig" source "$_pd_orig/.zprofile"
        ZDOTDIR="$PATHDECK_ZDOTDIR"
        """
        try? zshprofileScript.write(to: zshprofile, atomically: true, encoding: .utf8)

        let zshlogin = zshDir.appendingPathComponent(".zlogin")
        let zshloginScript = """
        # PathDeck shell integration — .zlogin
        _pd_orig="${PATHDECK_ORIG_ZDOTDIR:-$HOME}"
        [[ -f "$_pd_orig/.zlogin" ]] && ZDOTDIR="$_pd_orig" source "$_pd_orig/.zlogin"
        """
        try? zshloginScript.write(to: zshlogin, atomically: true, encoding: .utf8)
    }

    static func envVars(for shellPath: String) -> [(key: String, value: String)] {
        var vars: [(key: String, value: String)] = []
        let shell = (shellPath as NSString).lastPathComponent

        if shell == "zsh" {
            let origZdotdir = ProcessInfo.processInfo.environment["ZDOTDIR"] ?? ""
            vars.append(("PATHDECK_ORIG_ZDOTDIR", origZdotdir))
            vars.append(("PATHDECK_ZDOTDIR", zshDir.path(percentEncoded: false)))
            vars.append(("ZDOTDIR", zshDir.path(percentEncoded: false)))
        } else if shell == "bash" {
            let existing = ProcessInfo.processInfo.environment["PROMPT_COMMAND"] ?? ""
            let osc7 = "printf '\\033]7;file://%s%s\\033\\\\' \"$HOSTNAME\" \"${PWD// /%20}\""
            let combined = existing.isEmpty ? osc7 : "\(osc7);\(existing)"
            vars.append(("PROMPT_COMMAND", combined))
        }

        return vars
    }
}
