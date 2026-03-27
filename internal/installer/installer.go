package installer

import (
	"embed"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// HookFiles must be set by the main package which embeds the hooks directory.
var HookFiles embed.FS

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

func Install() error {
	home, err := os.UserHomeDir()
	if err != nil {
		return fmt.Errorf("cannot find home directory: %w", err)
	}

	dataDir := filepath.Join(home, ".claude-status")
	hooksDir := filepath.Join(dataDir, "hooks")
	sessionsDir := filepath.Join(dataDir, "sessions")

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

	// PostToolUse hook for TodoWrite
	postToolHook := hookEntry{
		Matcher: "TodoWrite",
		Hooks:   []hookAction{{Type: "command", Command: taskHookCmd}},
	}
	postToolJSON, _ := json.Marshal(postToolHook)

	existingHooks["PostToolUse"] = appendIfNotPresent(existingHooks["PostToolUse"], postToolJSON, taskHookCmd)

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

	for _, name := range []string{"status-line.sh", "task-hook.sh"} {
		path := filepath.Join(hooksDir, name)
		if err := os.Remove(path); err == nil {
			fmt.Printf("  Removed %s\n", path)
		}
	}
	os.Remove(hooksDir)

	fmt.Println("\nUninstall complete. Session data preserved in ~/.claude-status/sessions/")
	fmt.Println("To remove all data: rm -rf ~/.claude-status")

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
