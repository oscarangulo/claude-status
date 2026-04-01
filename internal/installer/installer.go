package installer

import (
	"bufio"
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// HookFiles must be set by the main package which embeds the hooks directory.
var HookFiles embed.FS

const moduleInstallTarget = "github.com/oscarangulo/claude-status/cmd/claude-status@latest"

// Claude Code hook format:
// {"matcher": "ToolName", "hooks": [{"type": "command", "command": "bash /path/to/script.sh"}]}
type hookEntry struct {
	Matcher string       `json:"matcher,omitempty"`
	Hooks   []hookAction `json:"hooks"`
}

type hookAction struct {
	Type    string `json:"type"`
	Command string `json:"command"`
}

type UninstallMode string

const (
	UninstallModeSetup UninstallMode = "setup"
	UninstallModeData  UninstallMode = "data"
	UninstallModeFull  UninstallMode = "full"
)

type UninstallOptions struct {
	Mode UninstallMode
	Yes  bool
	In   io.Reader
	Out  io.Writer
}

func Install() error {
	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("cannot find home directory: %w", err)
	}

	binaryPath, err := ensureBinaryAvailable(home)
	if err != nil {
		return err
	}
	fmt.Printf("  Binary ready at %s\n", binaryPath)

	dataDir := filepath.Join(home, ".claude-status")
	hooksDir := filepath.Join(dataDir, "hooks")
	sessionsDir := filepath.Join(dataDir, "sessions")

	for _, dir := range []string{hooksDir, sessionsDir} {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return fmt.Errorf("cannot create %s: %w", dir, err)
		}
	}

	// Extract hook scripts
	scripts := []string{"status-line.sh", "task-hook.sh", "snapshot-hook.sh"}
	for _, name := range scripts {
		data, err := HookFiles.ReadFile("hooks/" + name)
		if err != nil {
			return fmt.Errorf("cannot read embedded %s: %w", name, err)
		}
		dest := filepath.Join(hooksDir, name)
		if err := os.WriteFile(dest, data, 0755); err != nil {
			return fmt.Errorf("cannot write %s: %w", dest, err)
		}
		fmt.Printf("  Installed %s\n", dest)
	}

	// Update Claude Code settings
	claudeDir := filepath.Join(home, ".claude")
	settingsPath := filepath.Join(claudeDir, "settings.json")

	if err := os.MkdirAll(claudeDir, 0755); err != nil {
		return fmt.Errorf("cannot create %s: %w", claudeDir, err)
	}

	settings := make(map[string]json.RawMessage)
	if data, err := os.ReadFile(settingsPath); err == nil {
		if err := json.Unmarshal(data, &settings); err != nil {
			return fmt.Errorf("cannot parse %s: %w", settingsPath, err)
		}
		backupPath := settingsPath + ".backup"
		if err := os.WriteFile(backupPath, data, 0644); err != nil {
			return fmt.Errorf("cannot create backup: %w", err)
		}
		fmt.Printf("  Backed up settings to %s\n", backupPath)
	}

	// Status line — uses the object format: {"type": "command", "command": "..."}
	statusLineObj := map[string]string{
		"type":    "command",
		"command": fmt.Sprintf("bash %s", filepath.Join(hooksDir, "status-line.sh")),
	}
	statusJSON, _ := json.Marshal(statusLineObj)
	settings["statusLine"] = json.RawMessage(statusJSON)
	delete(settings, "statusLineCMD") // remove old key if present

	// Parse existing hooks
	var existingHooks map[string][]json.RawMessage
	if raw, ok := settings["hooks"]; ok {
		json.Unmarshal(raw, &existingHooks)
	}
	if existingHooks == nil {
		existingHooks = make(map[string][]json.RawMessage)
	}

	taskHookCmd := fmt.Sprintf("bash %s", filepath.Join(hooksDir, "task-hook.sh"))
	snapshotHookCmd := fmt.Sprintf("bash %s", filepath.Join(hooksDir, "snapshot-hook.sh"))

	// PostToolUse hook for TodoWrite (task tracking)
	postToolHook := hookEntry{
		Matcher: "TodoWrite",
		Hooks:   []hookAction{{Type: "command", Command: taskHookCmd}},
	}
	postToolJSON, _ := json.Marshal(postToolHook)
	existingHooks["PostToolUse"] = appendIfNotPresent(existingHooks["PostToolUse"], postToolJSON, taskHookCmd)

	// PostToolUse hook for all tools (snapshot from native session data)
	snapshotHook := hookEntry{
		Hooks: []hookAction{{Type: "command", Command: snapshotHookCmd}},
	}
	snapshotJSON, _ := json.Marshal(snapshotHook)
	existingHooks["PostToolUse"] = appendIfNotPresent(existingHooks["PostToolUse"], snapshotJSON, snapshotHookCmd)

	hooksJSON, _ := json.Marshal(existingHooks)
	settings["hooks"] = json.RawMessage(hooksJSON)

	output, err := json.MarshalIndent(settings, "", "  ")
	if err != nil {
		return fmt.Errorf("cannot marshal settings: %w", err)
	}
	if err := os.WriteFile(settingsPath, output, 0644); err != nil {
		return fmt.Errorf("cannot write settings: %w", err)
	}
	fmt.Printf("  Updated %s\n", settingsPath)

	fmt.Println("\nInstallation complete! Restart Claude Code to activate.")
	return nil
}

func Update(refreshOnly bool) error {
	if refreshOnly {
		fmt.Println("Updating hook scripts...")
		return Install()
	}

	currentPath, err := currentExecutablePath()
	if err != nil {
		return err
	}

	method, targetPath := detectInstallMethod(currentPath)
	if err := selfUpdate(method, targetPath); err != nil {
		return err
	}

	updatedPath, err := resolveUpdatedBinaryPath(method, currentPath, targetPath)
	if err != nil {
		return err
	}

	fmt.Printf("Running refreshed binary at %s\n\n", updatedPath)
	return runBinary(updatedPath, "update", "--refresh-only")
}

func Uninstall(opts UninstallOptions) error {
	if opts.In == nil {
		opts.In = os.Stdin
	}
	if opts.Out == nil {
		opts.Out = os.Stdout
	}
	if opts.Mode == "" {
		if opts.Yes {
			opts.Mode = UninstallModeSetup
		} else {
			mode, err := promptUninstallMode(opts.In, opts.Out)
			if err != nil {
				return err
			}
			opts.Mode = mode
		}
	}
	if !isValidUninstallMode(opts.Mode) {
		return fmt.Errorf("invalid uninstall mode %q", opts.Mode)
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("cannot find home directory: %w", err)
	}

	dataDir := filepath.Join(home, ".claude-status")
	hooksDir := filepath.Join(dataDir, "hooks")

	if err := removeClaudeSetup(home, hooksDir); err != nil {
		return err
	}

	if opts.Mode == UninstallModeData || opts.Mode == UninstallModeFull {
		if err := os.RemoveAll(dataDir); err == nil {
			fmt.Printf("  Removed %s\n", dataDir)
		}
	}

	if opts.Mode == UninstallModeFull {
		for _, path := range installedBinaryPaths(home) {
			if err := os.Remove(path); err == nil {
				fmt.Printf("  Removed %s\n", path)
			}
		}
		if cleaned, err := removeShellPathEntry(home); err == nil && cleaned != "" {
			fmt.Printf("  Removed %s from %s\n", filepath.Join(home, ".local", "bin"), cleaned)
		}
		for _, path := range installedExtensionPaths(home) {
			if err := os.RemoveAll(path); err == nil {
				fmt.Printf("  Removed %s\n", path)
			}
		}
	}

	fmt.Fprintln(opts.Out)
	switch opts.Mode {
	case UninstallModeSetup:
		fmt.Fprintln(opts.Out, "Uninstall complete. Session data preserved in ~/.claude-status/sessions/")
		fmt.Fprintln(opts.Out, "To remove all data: run 'claude-status uninstall --mode data --yes'")
	case UninstallModeData:
		fmt.Fprintln(opts.Out, "Uninstall complete. Claude Code setup and local session data were removed.")
	case UninstallModeFull:
		fmt.Fprintln(opts.Out, "Full cleanup complete. Claude Code setup, local data, local binaries, and local IDE extensions were removed.")
	}

	return nil
}

func removeClaudeSetup(home, hooksDir string) error {
	claudeDir := filepath.Join(home, ".claude")
	settingsPath := filepath.Join(claudeDir, "settings.json")

	if data, err := os.ReadFile(settingsPath); err == nil {
		settings := make(map[string]json.RawMessage)
		if err := json.Unmarshal(data, &settings); err == nil {
			backupPath := settingsPath + ".backup"
			os.WriteFile(backupPath, data, 0644)
			fmt.Printf("  Backed up settings to %s\n", backupPath)

			// Remove statusLine if it points to our script
			if raw, ok := settings["statusLine"]; ok {
				var sl map[string]string
				if json.Unmarshal(raw, &sl) == nil && strings.Contains(sl["command"], ".claude-status") {
					delete(settings, "statusLine")
					fmt.Println("  Removed statusLine")
				}
			}
			// Also clean up old key name if present
			if raw, ok := settings["statusLineCMD"]; ok {
				var cmd string
				if json.Unmarshal(raw, &cmd) == nil && strings.Contains(cmd, ".claude-status") {
					delete(settings, "statusLineCMD")
				}
			}

			// Remove our hooks
			if raw, ok := settings["hooks"]; ok {
				var hooks map[string][]json.RawMessage
				if json.Unmarshal(raw, &hooks) == nil {
					hookPath := filepath.Join(hooksDir, "task-hook.sh")
					for event, hookList := range hooks {
						hooks[event] = removeHooksByCommand(hookList, hookPath)
						if len(hooks[event]) == 0 {
							delete(hooks, event)
						}
					}
					if len(hooks) == 0 {
						delete(settings, "hooks")
					} else {
						hooksJSON, _ := json.Marshal(hooks)
						settings["hooks"] = json.RawMessage(hooksJSON)
					}
					fmt.Println("  Removed hooks")
				}
			}

			output, _ := json.MarshalIndent(settings, "", "  ")
			os.WriteFile(settingsPath, output, 0644)
			fmt.Printf("  Updated %s\n", settingsPath)
		}
	}

	for _, name := range []string{"status-line.sh", "task-hook.sh", "snapshot-hook.sh"} {
		path := filepath.Join(hooksDir, name)
		if err := os.Remove(path); err == nil {
			fmt.Printf("  Removed %s\n", path)
		}
	}
	os.Remove(hooksDir)
	return nil
}

// appendIfNotPresent checks if a hook with the same command already exists.
// Handles both old format {"command": "..."} and new format {"hooks": [{"command": "..."}]}
func appendIfNotPresent(existing []json.RawMessage, newHook json.RawMessage, cmdCheck string) []json.RawMessage {
	for _, raw := range existing {
		if containsCommand(raw, cmdCheck) {
			return existing
		}
	}
	return append(existing, newHook)
}

// removeHooksByCommand removes entries containing the given path fragment.
// Handles both old and new hook formats.
func removeHooksByCommand(hooks []json.RawMessage, pathFragment string) []json.RawMessage {
	var filtered []json.RawMessage
	for _, raw := range hooks {
		if containsCommandFragment(raw, pathFragment) {
			continue
		}
		filtered = append(filtered, raw)
	}
	return filtered
}

func containsCommand(raw json.RawMessage, cmd string) bool {
	// Try new format: {"hooks": [{"command": "..."}]}
	var entry hookEntry
	if json.Unmarshal(raw, &entry) == nil {
		for _, h := range entry.Hooks {
			if h.Command == cmd {
				return true
			}
		}
	}
	// Try old format: {"command": "..."}
	var old map[string]string
	if json.Unmarshal(raw, &old) == nil {
		if old["command"] == cmd {
			return true
		}
	}
	return false
}

func containsCommandFragment(raw json.RawMessage, fragment string) bool {
	// Try new format
	var entry hookEntry
	if json.Unmarshal(raw, &entry) == nil {
		for _, h := range entry.Hooks {
			if strings.Contains(h.Command, fragment) {
				return true
			}
		}
	}
	// Try old format
	var old map[string]string
	if json.Unmarshal(raw, &old) == nil {
		if strings.Contains(old["command"], fragment) {
			return true
		}
	}
	return false
}

func ensureBinaryAvailable(home string) (string, error) {
	exePath, err := currentExecutablePath()
	if err != nil {
		return "", err
	}

	exeDir := filepath.Dir(exePath)
	if dirInPath(exeDir) {
		return exePath, nil
	}

	installDir := filepath.Join(home, ".local", "bin")
	if err := os.MkdirAll(installDir, 0755); err != nil {
		return "", fmt.Errorf("cannot create %s: %w", installDir, err)
	}

	dest := filepath.Join(installDir, "claude-status")
	if exePath != dest {
		if err := copyExecutable(exePath, dest); err != nil {
			return "", fmt.Errorf("cannot install binary to %s: %w", dest, err)
		}
	}

	if err := ensureShellPathEntry(home, installDir); err != nil {
		return "", err
	}

	return dest, nil
}

func promptUninstallMode(in io.Reader, out io.Writer) (UninstallMode, error) {
	fmt.Fprintln(out, "Choose what to remove:")
	fmt.Fprintln(out, "  1) Claude Code setup only (keep sessions and binaries)")
	fmt.Fprintln(out, "  2) Setup + local data (~/.claude-status)")
	fmt.Fprintln(out, "  3) Full cleanup (setup + data + local binaries + local IDE extensions)")
	fmt.Fprint(out, "Enter 1, 2, or 3 [1]: ")

	reader := bufio.NewReader(in)
	choice, err := reader.ReadString('\n')
	if err != nil && err != io.EOF {
		return "", fmt.Errorf("cannot read uninstall choice: %w", err)
	}

	switch strings.TrimSpace(choice) {
	case "", "1":
		return UninstallModeSetup, nil
	case "2":
		return UninstallModeData, nil
	case "3":
		return UninstallModeFull, nil
	default:
		return "", fmt.Errorf("invalid choice %q", strings.TrimSpace(choice))
	}
}

func isValidUninstallMode(mode UninstallMode) bool {
	switch mode {
	case UninstallModeSetup, UninstallModeData, UninstallModeFull:
		return true
	default:
		return false
	}
}

func resolvePath(path string) string {
	resolved, err := filepath.EvalSymlinks(path)
	if err == nil {
		return resolved
	}
	return path
}

func currentExecutablePath() (string, error) {
	exePath, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("cannot locate current executable: %w", err)
	}
	return resolvePath(exePath), nil
}

func dirInPath(target string) bool {
	target = resolvePath(target)
	for _, part := range filepath.SplitList(os.Getenv("PATH")) {
		if part == "" {
			continue
		}
		if resolvePath(part) == target {
			return true
		}
	}
	return false
}

func ensureShellPathEntry(home, installDir string) error {
	shellRC := preferredShellRC(home)
	content, err := os.ReadFile(shellRC)
	if err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("cannot read %s: %w", shellRC, err)
	}

	pathExport := fmt.Sprintf(`export PATH="$HOME/.local/bin:$PATH"`)
	if strings.Contains(string(content), installDir) || strings.Contains(string(content), pathExport) {
		return nil
	}

	f, err := os.OpenFile(shellRC, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return fmt.Errorf("cannot update %s: %w", shellRC, err)
	}
	defer f.Close()

	if len(content) > 0 && !strings.HasSuffix(string(content), "\n") {
		if _, err := f.WriteString("\n"); err != nil {
			return fmt.Errorf("cannot update %s: %w", shellRC, err)
		}
	}

	if _, err := f.WriteString(pathExport + "\n"); err != nil {
		return fmt.Errorf("cannot update %s: %w", shellRC, err)
	}

	fmt.Printf("  Added %s to PATH in %s\n", installDir, shellRC)
	return nil
}

func removeShellPathEntry(home string) (string, error) {
	installDir := filepath.Join(home, ".local", "bin")
	pathExport := `export PATH="$HOME/.local/bin:$PATH"`
	candidates := []string{
		filepath.Join(home, ".zshrc"),
		filepath.Join(home, ".bashrc"),
	}

	for _, shellRC := range candidates {
		content, err := os.ReadFile(shellRC)
		if err != nil {
			if os.IsNotExist(err) {
				continue
			}
			return "", fmt.Errorf("cannot read %s: %w", shellRC, err)
		}

		lines := strings.Split(string(content), "\n")
		kept := make([]string, 0, len(lines))
		changed := false
		for _, line := range lines {
			trimmed := strings.TrimSpace(line)
			if trimmed == pathExport || strings.Contains(trimmed, installDir) {
				changed = true
				continue
			}
			kept = append(kept, line)
		}
		if !changed {
			continue
		}

		updated := strings.TrimRight(strings.Join(kept, "\n"), "\n") + "\n"
		if err := os.WriteFile(shellRC, []byte(updated), 0644); err != nil {
			return "", fmt.Errorf("cannot update %s: %w", shellRC, err)
		}
		return shellRC, nil
	}

	return "", nil
}

func preferredShellRC(home string) string {
	zshrc := filepath.Join(home, ".zshrc")
	if _, err := os.Stat(zshrc); err == nil {
		return zshrc
	}

	bashrc := filepath.Join(home, ".bashrc")
	if _, err := os.Stat(bashrc); err == nil {
		return bashrc
	}

	if strings.Contains(os.Getenv("SHELL"), "bash") {
		return bashrc
	}
	return zshrc
}

func installedBinaryPaths(home string) []string {
	paths := []string{
		filepath.Join(home, ".local", "bin", "claude-status"),
		filepath.Join(home, "go", "bin", "claude-status"),
	}
	if gobin := strings.TrimSpace(os.Getenv("GOBIN")); gobin != "" {
		paths = append(paths, filepath.Join(gobin, "claude-status"))
	}
	return uniqueExistingPaths(paths)
}

func installedExtensionPaths(home string) []string {
	patterns := []string{
		filepath.Join(home, ".cursor", "extensions", "oscarangulo.claude-status-*"),
		filepath.Join(home, ".cursor", "extensions", "OscarAngulo.claude-status-*"),
		filepath.Join(home, ".vscode", "extensions", "oscarangulo.claude-status-*"),
		filepath.Join(home, ".vscode", "extensions", "OscarAngulo.claude-status-*"),
		filepath.Join(home, ".cursor-insiders", "extensions", "oscarangulo.claude-status-*"),
		filepath.Join(home, ".cursor-insiders", "extensions", "OscarAngulo.claude-status-*"),
		filepath.Join(home, ".vscode-insiders", "extensions", "oscarangulo.claude-status-*"),
		filepath.Join(home, ".vscode-insiders", "extensions", "OscarAngulo.claude-status-*"),
	}
	var paths []string
	for _, pattern := range patterns {
		matches, _ := filepath.Glob(pattern)
		paths = append(paths, matches...)
	}
	return uniqueExistingPaths(paths)
}

func uniqueExistingPaths(paths []string) []string {
	seen := make(map[string]bool)
	var result []string
	for _, path := range paths {
		if path == "" {
			continue
		}
		resolved := resolvePath(path)
		if seen[resolved] {
			continue
		}
		if _, err := os.Stat(path); err == nil {
			seen[resolved] = true
			result = append(result, path)
		}
	}
	return result
}

type installMethod string

const (
	installMethodBrew    installMethod = "brew"
	installMethodGo      installMethod = "go"
	installMethodLocal   installMethod = "local"
	installMethodUnknown installMethod = "unknown"
)

func detectInstallMethod(currentPath string) (installMethod, string) {
	home, _ := os.UserHomeDir()
	currentPath = resolvePath(currentPath)

	if strings.Contains(currentPath, "/Cellar/") ||
		currentPath == "/opt/homebrew/bin/claude-status" ||
		currentPath == "/usr/local/bin/claude-status" {
		return installMethodBrew, currentPath
	}

	if gopath := strings.TrimSpace(os.Getenv("GOBIN")); gopath != "" {
		goBinPath := filepath.Join(gopath, "claude-status")
		if resolvePath(goBinPath) == currentPath {
			return installMethodGo, goBinPath
		}
	}

	goPath := strings.TrimSpace(goEnv("GOPATH"))
	if goPath != "" {
		goBinPath := filepath.Join(goPath, "bin", "claude-status")
		if resolvePath(goBinPath) == currentPath {
			return installMethodGo, goBinPath
		}
	}

	localPath := filepath.Join(home, ".local", "bin", "claude-status")
	if resolvePath(localPath) == currentPath {
		return installMethodLocal, localPath
	}

	return installMethodUnknown, currentPath
}

func selfUpdate(method installMethod, targetPath string) error {
	switch method {
	case installMethodBrew:
		fmt.Println("Updating claude-status via Homebrew...")
		return runCommand("", "brew", "upgrade", "claude-status")
	case installMethodGo:
		fmt.Println("Updating claude-status via go install...")
		return runCommand("", "go", "install", moduleInstallTarget)
	case installMethodLocal, installMethodUnknown:
		fmt.Println("Updating claude-status via go install and syncing local binary...")
		if err := runCommand("", "go", "install", moduleInstallTarget); err != nil {
			return fmt.Errorf("cannot self-update automatically from this installation. Try upgrading manually, then run 'claude-status update --refresh-only': %w", err)
		}
		src := installedGoBinaryPath()
		if src == "" {
			return fmt.Errorf("cannot locate binary installed by go install")
		}
		if err := copyExecutable(src, targetPath); err != nil {
			return fmt.Errorf("cannot copy updated binary into %s: %w", targetPath, err)
		}
		return nil
	default:
		return nil
	}
}

func resolveUpdatedBinaryPath(method installMethod, currentPath, targetPath string) (string, error) {
	switch method {
	case installMethodBrew:
		path, err := exec.LookPath("claude-status")
		if err != nil {
			return "", fmt.Errorf("cannot locate updated claude-status after brew upgrade: %w", err)
		}
		return resolvePath(path), nil
	case installMethodGo:
		path := installedGoBinaryPath()
		if path == "" {
			return "", fmt.Errorf("cannot locate updated claude-status after go install")
		}
		return path, nil
	case installMethodLocal, installMethodUnknown:
		return resolvePath(targetPath), nil
	default:
		return currentPath, nil
	}
}

func installedGoBinaryPath() string {
	if gobin := strings.TrimSpace(os.Getenv("GOBIN")); gobin != "" {
		path := filepath.Join(gobin, "claude-status")
		if _, err := os.Stat(path); err == nil {
			return resolvePath(path)
		}
	}

	goPath := strings.TrimSpace(goEnv("GOPATH"))
	if goPath == "" {
		return ""
	}

	path := filepath.Join(goPath, "bin", "claude-status")
	if _, err := os.Stat(path); err == nil {
		return resolvePath(path)
	}
	return ""
}

func goEnv(key string) string {
	cmd := exec.Command("go", "env", key)
	output, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(output))
}

func runBinary(path string, args ...string) error {
	cmd := exec.Command(path, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	return cmd.Run()
}

func runCommand(dir, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin
	return cmd.Run()
}

func copyExecutable(src, dest string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	info, err := in.Stat()
	if err != nil {
		return err
	}

	out, err := os.OpenFile(dest, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0755)
	if err != nil {
		return err
	}

	_, copyErr := io.Copy(out, in)
	closeErr := out.Close()
	if copyErr != nil {
		return copyErr
	}
	if closeErr != nil {
		return closeErr
	}

	if info.Mode()&0111 != 0 {
		return os.Chmod(dest, 0755)
	}
	return os.Chmod(dest, 0644)
}
