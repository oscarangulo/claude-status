package installer

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPreferredShellRC(t *testing.T) {
	home := t.TempDir()
	t.Setenv("SHELL", "/bin/zsh")

	if got := preferredShellRC(home); got != filepath.Join(home, ".zshrc") {
		t.Fatalf("expected default zshrc, got %s", got)
	}

	bashrc := filepath.Join(home, ".bashrc")
	if err := os.WriteFile(bashrc, []byte(""), 0644); err != nil {
		t.Fatal(err)
	}
	if got := preferredShellRC(home); got != bashrc {
		t.Fatalf("expected bashrc when only bashrc exists, got %s", got)
	}

	zshrc := filepath.Join(home, ".zshrc")
	if err := os.WriteFile(zshrc, []byte(""), 0644); err != nil {
		t.Fatal(err)
	}
	if got := preferredShellRC(home); got != zshrc {
		t.Fatalf("expected zshrc to take priority, got %s", got)
	}
}

func TestEnsureShellPathEntry(t *testing.T) {
	home := t.TempDir()
	installDir := filepath.Join(home, ".local", "bin")
	t.Setenv("SHELL", "/bin/zsh")

	if err := ensureShellPathEntry(home, installDir); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	content, err := os.ReadFile(filepath.Join(home, ".zshrc"))
	if err != nil {
		t.Fatalf("cannot read zshrc: %v", err)
	}

	expected := "export PATH=\"$HOME/.local/bin:$PATH\"\n"
	if string(content) != expected {
		t.Fatalf("expected %q, got %q", expected, string(content))
	}

	if err := ensureShellPathEntry(home, installDir); err != nil {
		t.Fatalf("unexpected error on second run: %v", err)
	}

	content, err = os.ReadFile(filepath.Join(home, ".zshrc"))
	if err != nil {
		t.Fatalf("cannot read zshrc: %v", err)
	}
	if string(content) != expected {
		t.Fatalf("expected no duplicate PATH entry, got %q", string(content))
	}
}

func TestDetectInstallMethod(t *testing.T) {
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("GOBIN", filepath.Join(home, "gobin"))

	tests := []struct {
		name   string
		path   string
		method installMethod
		target string
	}{
		{
			name:   "brew path",
			path:   "/opt/homebrew/bin/claude-status",
			method: installMethodBrew,
			target: "/opt/homebrew/bin/claude-status",
		},
		{
			name:   "go bin path",
			path:   filepath.Join(home, "gobin", "claude-status"),
			method: installMethodGo,
			target: filepath.Join(home, "gobin", "claude-status"),
		},
		{
			name:   "local path",
			path:   filepath.Join(home, ".local", "bin", "claude-status"),
			method: installMethodLocal,
			target: filepath.Join(home, ".local", "bin", "claude-status"),
		},
		{
			name:   "unknown path",
			path:   "/tmp/custom/claude-status",
			method: installMethodUnknown,
			target: "/tmp/custom/claude-status",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			method, target := detectInstallMethod(tt.path)
			if method != tt.method {
				t.Fatalf("expected method %q, got %q", tt.method, method)
			}
			if target != tt.target {
				t.Fatalf("expected target %q, got %q", tt.target, target)
			}
		})
	}
}
