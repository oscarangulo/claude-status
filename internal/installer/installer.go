package installer

import (
	"embed"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
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

	// Set status line command
	statusLineCmd := fmt.Sprintf("bash %s", filepath.Join(hooksDir, "status-line.sh"))
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

	taskHookCmd := fmt.Sprintf("bash %s", filepath.Join(hooksDir, "task-hook.sh"))

	// PostToolUse hook for TodoWrite
	postToolHook := map[string]string{
		"matcher": "TodoWrite",
		"command": taskHookCmd,
	}
	postToolJSON, _ := json.Marshal(postToolHook)

	// TaskCompleted hook
	taskCompletedHook := map[string]string{
		"command": taskHookCmd,
	}
	taskCompletedJSON, _ := json.Marshal(taskCompletedHook)

	// SessionEnd hook
	sessionEndHook := map[string]string{
		"command": taskHookCmd,
	}
	sessionEndJSON, _ := json.Marshal(sessionEndHook)

	// Only add if not already present (check by command)
	existingHooks["PostToolUse"] = appendIfNotPresent(existingHooks["PostToolUse"], postToolJSON, taskHookCmd)
	existingHooks["TaskCompleted"] = appendIfNotPresent(existingHooks["TaskCompleted"], taskCompletedJSON, taskHookCmd)
	existingHooks["SessionEnd"] = appendIfNotPresent(existingHooks["SessionEnd"], sessionEndJSON, taskHookCmd)

	hooksJSON, _ := json.Marshal(existingHooks)
	settings["hooks"] = json.RawMessage(hooksJSON)

	// Write settings
	output, err := json.MarshalIndent(settings, "", "  ")
	if err != nil {
		return fmt.Errorf("cannot marshal settings: %w", err)
	}
	if err := os.WriteFile(settingsPath, output, 0644); err != nil {
		return fmt.Errorf("cannot write settings: %w", err)
	}
	fmt.Printf("  Updated %s\n", settingsPath)

	fmt.Println("\nInstallation complete! Restart Claude Code to activate.")
	fmt.Println("Run 'claude-status' in another terminal to see the dashboard.")

	return nil
}

func appendIfNotPresent(existing []json.RawMessage, newHook json.RawMessage, cmdCheck string) []json.RawMessage {
	for _, raw := range existing {
		var h map[string]string
		if err := json.Unmarshal(raw, &h); err == nil {
			if h["command"] == cmdCheck {
				return existing // already present
			}
		}
	}
	return append(existing, newHook)
}
