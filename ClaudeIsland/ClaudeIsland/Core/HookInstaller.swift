import Foundation
import OSLog

/// Manages hook script installation and settings.json configuration.
/// Merges Claude Island hooks with existing hooks (coexists with Claude Notifier, Vibe Island, etc.)
struct HookInstaller {
    private static let logger = Logger(subsystem: "com.claudeisland", category: "HookInstaller")

    private static var claudeSettingsPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/settings.json"
    }

    private static var hookInstallDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.claude/hooks/claude-island"
    }

    // MARK: - Install

    static func install() throws {
        try installHookScripts()
        try mergeHooksIntoSettings()
        logger.info("Hook installation complete")
    }

    // MARK: - Uninstall

    static func uninstall() throws {
        try removeHooksFromSettings()
        try? FileManager.default.removeItem(atPath: hookInstallDir)
        logger.info("Hooks uninstalled")
    }

    // MARK: - Check if installed

    static var isInstalled: Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: claudeSettingsPath),
              let data = fm.contents(atPath: claudeSettingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        // Check if our hooks are present
        return containsOurHook(in: hooks, event: "Stop")
            && containsOurHook(in: hooks, event: "PermissionRequest")
            && containsOurHook(in: hooks, event: "PreToolUse")
    }

    // MARK: - Private: Install hook scripts to Application Support

    private static func installHookScripts() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: hookInstallDir, withIntermediateDirectories: true)

        let scripts = ["on-stop.sh", "on-permission.sh", "on-question.sh"]
        for script in scripts {
            guard let sourceURL = Bundle.main.url(forResource: script, withExtension: nil, subdirectory: "hooks")
                    ?? Bundle.main.url(forResource: String(script.dropLast(3)), withExtension: "sh") else {
                // If not bundled, write a default script
                let destPath = "\(hookInstallDir)/\(script)"
                if !fm.fileExists(atPath: destPath) {
                    try defaultScript(for: script).write(toFile: destPath, atomically: true, encoding: .utf8)
                    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath)
                }
                continue
            }
            let destPath = "\(hookInstallDir)/\(script)"
            if fm.fileExists(atPath: destPath) {
                try fm.removeItem(atPath: destPath)
            }
            try fm.copyItem(atPath: sourceURL.path, toPath: destPath)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath)
        }

        logger.info("Hook scripts installed to \(hookInstallDir)")
    }

    // MARK: - Private: Merge hooks into settings.json

    private static func mergeHooksIntoSettings() throws {
        let fm = FileManager.default
        var settings: [String: Any] = [:]

        // Read existing settings
        if let data = fm.contents(atPath: claudeSettingsPath),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = existing
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        // Add our hooks — append to existing arrays, don't replace
        appendHook(to: &hooks, event: "Stop", command: "\(hookInstallDir)/on-stop.sh")
        appendHook(to: &hooks, event: "PermissionRequest", command: "\(hookInstallDir)/on-permission.sh")
        appendPreToolUseHook(to: &hooks, command: "\(hookInstallDir)/on-question.sh")

        settings["hooks"] = hooks

        // Write back
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: claudeSettingsPath))
        logger.info("Hooks merged into \(claudeSettingsPath)")
    }

    private static func appendHook(to hooks: inout [String: Any], event: String, command: String) {
        var eventArray = hooks[event] as? [[String: Any]] ?? []

        // Check if our hook already exists
        let alreadyExists = eventArray.contains { entry in
            guard let hooksList = entry["hooks"] as? [[String: Any]] else { return false }
            return hooksList.contains { h in
                (h["command"] as? String)?.contains("ClaudeIsland") == true
            }
        }
        guard !alreadyExists else { return }

        let entry: [String: Any] = [
            "hooks": [
                [
                    "type": "command",
                    "command": command
                ]
            ]
        ]
        eventArray.append(entry)
        hooks[event] = eventArray
    }

    private static func appendPreToolUseHook(to hooks: inout [String: Any], command: String) {
        var eventArray = hooks["PreToolUse"] as? [[String: Any]] ?? []

        // Check if our hook already exists
        let alreadyExists = eventArray.contains { entry in
            guard let hooksList = entry["hooks"] as? [[String: Any]] else { return false }
            return hooksList.contains { h in
                (h["command"] as? String)?.contains("ClaudeIsland") == true
            }
        }
        guard !alreadyExists else { return }

        let entry: [String: Any] = [
            "matcher": "AskUserQuestion",
            "hooks": [
                [
                    "type": "command",
                    "command": command
                ]
            ]
        ]
        eventArray.append(entry)
        hooks["PreToolUse"] = eventArray
    }

    // MARK: - Private: Remove hooks from settings

    private static func removeHooksFromSettings() throws {
        let fm = FileManager.default
        guard let data = fm.contents(atPath: claudeSettingsPath),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = settings["hooks"] as? [String: Any] else {
            return
        }

        for event in ["Stop", "PermissionRequest", "PreToolUse"] {
            guard var eventArray = hooks[event] as? [[String: Any]] else { continue }
            eventArray.removeAll { entry in
                guard let hooksList = entry["hooks"] as? [[String: Any]] else { return false }
                return hooksList.contains { h in
                    (h["command"] as? String)?.contains("ClaudeIsland") == true
                }
            }
            if eventArray.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = eventArray
            }
        }

        settings["hooks"] = hooks.isEmpty ? nil : hooks
        let newData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try newData.write(to: URL(fileURLWithPath: claudeSettingsPath))
    }

    // MARK: - Helpers

    private static func containsOurHook(in hooks: [String: Any], event: String) -> Bool {
        guard let eventArray = hooks[event] as? [[String: Any]] else { return false }
        return eventArray.contains { entry in
            guard let hooksList = entry["hooks"] as? [[String: Any]] else { return false }
            return hooksList.contains { h in
                (h["command"] as? String)?.contains("ClaudeIsland") == true
            }
        }
    }

    private static func defaultScript(for name: String) -> String {
        let type: String
        switch name {
        case "on-stop.sh": type = "stop"
        case "on-permission.sh": type = "permission"
        case "on-question.sh": type = "question"
        default: type = "unknown"
        }

        return """
        #!/bin/bash
        # Claude Island — \(name)
        INPUT=$(cat)
        SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null)
        echo "{\\"type\\":\\"\(type)\\",\\"sessionId\\":\\"${SESSION_ID}\\"}" | nc -U /tmp/claude-island.sock 2>/dev/null
        exit 0
        """
    }
}
