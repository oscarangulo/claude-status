package installer

import (
	"embed"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// HookFiles must be set by the main package which embeds the hooks directory.
var HookFiles embed.FS

func Install() error {
	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("cannot find home directory: %w", err)
	}

	dataDir := filepath.Join(home, ".claude-status")
	hooksDir := filepath.Join(dataDir, "hooks")
	sessionsDir := filepath.Join(dataDir, "sessions")

	// Create directories
	for _, dir := range []string{hooksDir, sessionsDir} {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return fmt.Errorf("cannot create %s: %w", dir, err)
		}
	}

	// Extract hook scripts
	scripts := []string{"status-line.sh", "task-hook.sh"}
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

	// Read existing settings or start fresh
	settings := make(map[string]json.RawMessage)
	if data, err := os.ReadFile(settingsPath); err == nil {
		if err := json.Unmarshal(data, &settings); err != nil {
			return fmt.Errorf("cannot parse %s: %w", settingsPath, err)
		}
		// Backup
		backupPath := settingsPath + ".backup"
		if err := os.WriteFile(backupPath, data, 0644); err != nil {
			return fmt.Errorf("cannot create backup: %w", err)
		}
		fmt.Printf("  Backed up settings to %s\n", backupPath)
	}

	// Build the shell command depending on the OS
	shellPrefix := shellCommand()
	statusLineCmd := fmt.Sprintf("%s %s", shellPrefix, filepath.Join(hooksDir, "status-line.sh"))
	cmdJSON, _ := json.Marshal(statusLineCmd)
	settings["statusLineCMD"] = json.RawMessage(cmdJSON)

	// Set hooks
	var existingHooks map[string][]json.RawMessage
	if raw, ok := settings["hooks"]; ok {
		json.Unmarshal(raw, &existingHooks)
	}
	if existingHooks == nil {
		existingHooks = make(map[string][]json.RawMessage)
	}

	taskHookCmd := fmt.Sprintf("%s %s", shellPrefix, filepath.Join(hooksDir, "task-hook.sh"))

	postToolHook := map[string]string{
		"matcher": "TodoWrite",
		"command": taskHookCmd,
	}
	postToolJSON, _ := json.Marshal(postToolHook)

	taskCompletedHook := map[string]string{
		"command": taskHookCmd,
	}
	taskCompletedJSON, _ := json.Marshal(taskCompletedHook)

	sessionEndHook := map[string]string{
		"command": taskHookCmd,
	}
	sessionEndJSON, _ := json.Marshal(sessionEndHook)

	existingHooks["PostToolUse"] = appendIfNotPresent(existingHooks["PostToolUse"], postToolJSON, taskHookCmd)
	existingHooks["TaskCompleted"] = appendIfNotPresent(existingHooks["TaskCompleted"], taskCompletedJSON, taskHookCmd)
	existingHooks["SessionEnd"] = appendIfNotPresent(existingHooks["SessionEnd"], sessionEndJSON, taskHookCmd)

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

func Uninstall() error {
	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("cannot find home directory: %w", err)
	}

	dataDir := filepath.Join(home, ".claude-status")
	hooksDir := filepath.Join(dataDir, "hooks")

	// Remove hooks from Claude Code settings
	claudeDir := filepath.Join(home, ".claude")
	settingsPath := filepath.Join(claudeDir, "settings.json")

	if data, err := os.ReadFile(settingsPath); err == nil {
		settings := make(map[string]json.RawMessage)
		if err := json.Unmarshal(data, &settings); err == nil {
			// Backup first
			backupPath := settingsPath + ".backup"
			os.WriteFile(backupPath, data, 0644)
			fmt.Printf("  Backed up settings to %s\n", backupPath)

			// Remove statusLineCMD if it points to our script
			if raw, ok := settings["statusLineCMD"]; ok {
				var cmd string
				if json.Unmarshal(raw, &cmd) == nil && strings.Contains(cmd, ".claude-status") {
					delete(settings, "statusLineCMD")
					fmt.Println("  Removed statusLineCMD")
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

	// Remove hook scripts
	for _, name := range []string{"status-line.sh", "task-hook.sh"} {
		path := filepath.Join(hooksDir, name)
		if err := os.Remove(path); err == nil {
			fmt.Printf("  Removed %s\n", path)
		}
	}
	os.Remove(hooksDir) // remove dir if empty

	fmt.Println("\nUninstall complete. Session data preserved in ~/.claude-status/sessions/")
	fmt.Println("To remove all data: rm -rf ~/.claude-status")

	return nil
}

func shellCommand() string {
	if runtime.GOOS == "windows" {
		// On Windows, Claude Code runs in WSL or Git Bash — both have bash available
		return "bash"
	}
	return "bash"
}

func appendIfNotPresent(existing []json.RawMessage, newHook json.RawMessage, cmdCheck string) []json.RawMessage {
	for _, raw := range existing {
		var h map[string]string
		if err := json.Unmarshal(raw, &h); err == nil {
			if h["command"] == cmdCheck {
				return existing
			}
		}
	}
	return append(existing, newHook)
}

func removeHooksByCommand(hooks []json.RawMessage, pathFragment string) []json.RawMessage {
	var filtered []json.RawMessage
	for _, raw := range hooks {
		var h map[string]string
		if err := json.Unmarshal(raw, &h); err == nil {
			if strings.Contains(h["command"], pathFragment) {
				continue
			}
		}
		filtered = append(filtered, raw)
	}
	return filtered
}
