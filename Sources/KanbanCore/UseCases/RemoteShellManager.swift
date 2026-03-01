import Foundation

/// Deploys the remote-shell.sh wrapper and provides shell/environment overrides
/// for projects configured with remote execution.
public enum RemoteShellManager {

    // MARK: - Public API

    /// Deploy the remote shell script and create the zsh symlink.
    /// Call once at app startup (idempotent — overwrites with latest version).
    public static func deploy() throws {
        let fm = FileManager.default
        let remoteDir = Self.remoteDir()
        try fm.createDirectory(atPath: remoteDir, withIntermediateDirectories: true)

        // Write the shell script
        let scriptPath = Self.scriptPath()
        try remoteShellScript.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        // Create symlink: ~/.kanban/remote/zsh -> remote-shell.sh
        let symlinkPath = Self.symlinkPath()
        if fm.fileExists(atPath: symlinkPath) || (try? fm.attributesOfItem(atPath: symlinkPath)) != nil {
            try? fm.removeItem(atPath: symlinkPath)
        }
        try fm.createSymbolicLink(atPath: symlinkPath, withDestinationPath: scriptPath)
        // Ensure the symlink target is executable (already set above, but belt-and-suspenders)
    }

    /// Returns the path to use as SHELL override for remote execution.
    public static func shellOverridePath() -> String {
        symlinkPath()
    }

    /// Returns environment variables needed for remote execution.
    public static func setupEnvironment(remote: RemoteSettings, projectPath: String) -> [String: String] {
        [
            "KANBAN_REMOTE_HOST": remote.host,
            "KANBAN_REMOTE_PATH": remote.remotePath,
            "KANBAN_LOCAL_PATH": remote.localPath,
            "KANBAN_MUTAGEN_LABEL": "kanban-\(sanitizeLabel(projectPath))",
        ]
    }

    // MARK: - Paths

    private static func remoteDir() -> String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".kanban/remote")
    }

    private static func scriptPath() -> String {
        (remoteDir() as NSString).appendingPathComponent("remote-shell.sh")
    }

    private static func symlinkPath() -> String {
        (remoteDir() as NSString).appendingPathComponent("zsh")
    }

    /// Sanitize a project path into a safe label component.
    private static func sanitizeLabel(_ path: String) -> String {
        let name = (path as NSString).lastPathComponent
        // Replace non-alphanumeric characters with dashes
        return name.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : Character("-") }
            .map(String.init)
            .joined()
            .lowercased()
    }

    // MARK: - Embedded Script

    private static let remoteShellScript = """
    #!/usr/bin/env bash
    # Remote shell wrapper for Claude Code.
    # Intercepts shell commands and runs them on a remote host via SSH.
    # Designed to be used as $SHELL override: SHELL=/path/to/remote-shell.sh claude
    #
    # Features:
    # - SSH ControlMaster for connection reuse
    # - Working directory tracking via MARKER pattern
    # - Path replacement (local <-> remote)
    # - Pre/post Mutagen sync flush
    # - Local fallback with state file + notification
    #
    # Configuration via environment variables:
    #   KANBAN_REMOTE_HOST     - SSH host (required)
    #   KANBAN_REMOTE_PATH     - Remote base path (required)
    #   KANBAN_LOCAL_PATH      - Local base path (required)
    #   KANBAN_MUTAGEN_LABEL   - Mutagen sync label (optional)
    #   KANBAN_STATE_DIR       - State directory (default: ~/.kanban/remote)

    set -euo pipefail

    # Configuration
    REMOTE_HOST="${KANBAN_REMOTE_HOST:-}"
    REMOTE_PATH="${KANBAN_REMOTE_PATH:-}"
    LOCAL_PATH="${KANBAN_LOCAL_PATH:-}"
    MUTAGEN_LABEL="${KANBAN_MUTAGEN_LABEL:-}"
    STATE_DIR="${KANBAN_STATE_DIR:-${HOME}/.kanban/remote}"
    MARKER="__KANBAN_CWD_MARKER__"

    # SSH ControlMaster settings
    SSH_CONTROL_DIR="${STATE_DIR}/ssh"
    SSH_CONTROL_PATH="${SSH_CONTROL_DIR}/control-%h-%p-%r"
    SSH_OPTS=(-o "ControlMaster=auto" -o "ControlPath=${SSH_CONTROL_PATH}" -o "ControlPersist=600" -o "ServerAliveInterval=30")

    mkdir -p "$STATE_DIR" "$SSH_CONTROL_DIR"

    # ---------- Helpers ----------

    log() {
        echo "[kanban-remote] $*" >&2
    }

    replace_paths_to_remote() {
        local cmd="$1"
        echo "${cmd//$LOCAL_PATH/$REMOTE_PATH}"
    }

    replace_paths_to_local() {
        local output="$1"
        echo "${output//$REMOTE_PATH/$LOCAL_PATH}"
    }

    flush_mutagen() {
        if [ -n "$MUTAGEN_LABEL" ]; then
            mutagen sync flush --label-selector="$MUTAGEN_LABEL" 2>/dev/null || true
        fi
    }

    check_remote() {
        ssh "${SSH_OPTS[@]}" -o "ConnectTimeout=5" "$REMOTE_HOST" "echo ok" 2>/dev/null
    }

    write_status() {
        local status="$1"
        local file="${STATE_DIR}/status-${REMOTE_HOST}.json"
        local ts
        ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        if [ "$status" = "offline" ]; then
            printf '{"status":"offline","since":"%s"}\\n' "$ts" > "$file"
        else
            printf '{"status":"online"}\\n' > "$file"
        fi
    }

    notify_fallback() {
        local msg="$1"
        write_status "offline"
        log "$msg"
    }

    # ---------- Modes ----------

    # Interactive mode: called when Claude spawns our "shell"
    run_interactive() {
        if [ -z "$REMOTE_HOST" ] || [ -z "$REMOTE_PATH" ] || [ -z "$LOCAL_PATH" ]; then
            log "Remote not configured, running locally"
            exec /bin/zsh "$@"
        fi

        # Check connectivity
        if ! check_remote; then
            notify_fallback "Cannot reach $REMOTE_HOST, falling back to local"
            exec /bin/zsh "$@"
        fi

        write_status "online"
        flush_mutagen

        # Start remote shell with working directory tracking
        local remote_cwd
        remote_cwd=$(replace_paths_to_remote "$(pwd)")

        ssh "${SSH_OPTS[@]}" -t "$REMOTE_HOST" \\
            "cd '$remote_cwd' 2>/dev/null || cd '$REMOTE_PATH'; exec /bin/bash"
    }

    # Command mode: called as `$SHELL -c "command"`
    run_command() {
        local cmd="$1"

        if [ -z "$REMOTE_HOST" ] || [ -z "$REMOTE_PATH" ] || [ -z "$LOCAL_PATH" ]; then
            exec /bin/zsh -c "$cmd"
        fi

        # Check connectivity
        if ! check_remote; then
            notify_fallback "Cannot reach $REMOTE_HOST, running locally"
            exec /bin/zsh -c "$cmd"
        fi

        write_status "online"

        # Pre-sync
        flush_mutagen

        # Replace local paths with remote paths
        local remote_cmd
        remote_cmd=$(replace_paths_to_remote "$cmd")

        local remote_cwd
        remote_cwd=$(replace_paths_to_remote "$(pwd)")

        # Execute remotely with CWD marker
        local output
        output=$(ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" \\
            "cd '$remote_cwd' 2>/dev/null || cd '$REMOTE_PATH'; $remote_cmd; echo '${MARKER}'\\$(pwd)" 2>&1) || true

        # Extract CWD from marker
        local new_cwd=""
        if [[ "$output" == *"${MARKER}"* ]]; then
            new_cwd="${output##*${MARKER}}"
            output="${output%${MARKER}*}"
            new_cwd=$(replace_paths_to_local "$new_cwd")
        fi

        # Post-sync
        flush_mutagen

        # Replace remote paths back to local in output
        local local_output
        local_output=$(replace_paths_to_local "$output")
        echo "$local_output"

        # Track working directory changes
        if [ -n "$new_cwd" ]; then
            echo "$new_cwd" > "${STATE_DIR}/cwd"
        fi
    }

    # ---------- Main ----------

    if [ "$#" -eq 0 ]; then
        run_interactive
    elif [ "$1" = "-c" ] && [ "$#" -ge 2 ]; then
        shift
        run_command "$*"
    elif [ "$1" = "-l" ] || [ "$1" = "--login" ]; then
        run_interactive
    else
        # Pass through to local shell
        exec /bin/zsh "$@"
    fi
    """
}
