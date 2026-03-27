package installer

import (
	"os"
	"path/filepath"
	"testing"
)

func TestPreferredShellRC(t *testing.T) {
	home := t.TempDir()

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
