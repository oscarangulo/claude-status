package config

import (
	"os"
	"path/filepath"
	"sort"
)

type Config struct {
	DataDir    string
	SessionDir string
	HooksDir   string
}

func Default() Config {
	home, _ := os.UserHomeDir()
	dataDir := filepath.Join(home, ".claude-status")
	return Config{
		DataDir:    dataDir,
		SessionDir: filepath.Join(dataDir, "sessions"),
		HooksDir:   filepath.Join(dataDir, "hooks"),
	}
}

func (c Config) EnsureDirs() error {
	if err := os.MkdirAll(c.SessionDir, 0755); err != nil {
		return err
	}
	return os.MkdirAll(c.HooksDir, 0755)
}

// SessionFiles returns .jsonl files in the sessions directory, sorted by modification time (newest first).
func (c Config) SessionFiles() ([]string, error) {
	entries, err := os.ReadDir(c.SessionDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}

	type fileInfo struct {
		path    string
		modTime int64
	}

	var files []fileInfo
	for _, e := range entries {
		if e.IsDir() || filepath.Ext(e.Name()) != ".jsonl" {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		files = append(files, fileInfo{
			path:    filepath.Join(c.SessionDir, e.Name()),
			modTime: info.ModTime().UnixNano(),
		})
	}

	sort.Slice(files, func(i, j int) bool {
		return files[i].modTime > files[j].modTime
	})

	paths := make([]string, len(files))
	for i, f := range files {
		paths[i] = f.path
	}
	return paths, nil
}

// ActiveSessionFile returns the most recently modified session file.
func (c Config) ActiveSessionFile() (string, error) {
	files, err := c.SessionFiles()
	if err != nil {
		return "", err
	}
	if len(files) == 0 {
		return "", nil
	}
	return files[0], nil
}
