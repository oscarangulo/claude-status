# Contributing to claude-status

Thanks for your interest in contributing! This project is in early development and contributions are welcome.

## Getting started

```bash
git clone https://github.com/oscarangulo/claude-status.git
cd claude-status
make build
make test
```

### Requirements

- Go 1.22+
- [jq](https://jqlang.github.io/jq/) (for testing hook scripts)

## How to contribute

### Reporting bugs

Open an [issue](https://github.com/oscarangulo/claude-status/issues) with:
- What you expected to happen
- What actually happened
- Your OS and Claude Code version
- Steps to reproduce

### Suggesting features

Open an issue with the `enhancement` label. Describe the use case and why it would be useful.

### Submitting code

1. Fork the repo
2. Create a branch: `git checkout -b my-feature`
3. Make your changes
4. Run tests: `make test`
5. Build and verify: `make build`
6. Commit with a clear message
7. Push and open a pull request

### Code style

- Follow standard Go conventions (`gofmt`, `go vet`)
- Keep shell scripts POSIX-compatible where possible
- Test on macOS and Linux if you can

### Areas where help is needed

- **Windows testing** — hook scripts with Git Bash / WSL
- **More optimization tips** — new heuristics in `internal/analyzer/`
- **Better token breakdown** — per-tool-call cost tracking
- **Localization** — translate tips and output
- **Packaging** — Homebrew formula, AUR package, etc.

## Code of conduct

Be respectful and constructive. We're all here to build something useful.
