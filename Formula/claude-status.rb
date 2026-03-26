class ClaudeStatus < Formula
  desc "Real-time token usage and cost monitoring for Claude Code"
  homepage "https://github.com/oscarangulo/claude-status"
  license "MIT"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/oscarangulo/claude-status/releases/latest/download/claude-status-darwin-arm64"
      sha256 "" # Update after release

      def install
        bin.install "claude-status-darwin-arm64" => "claude-status"
      end
    else
      url "https://github.com/oscarangulo/claude-status/releases/latest/download/claude-status-darwin-amd64"
      sha256 "" # Update after release

      def install
        bin.install "claude-status-darwin-amd64" => "claude-status"
      end
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/oscarangulo/claude-status/releases/latest/download/claude-status-linux-arm64"
      sha256 "" # Update after release

      def install
        bin.install "claude-status-linux-arm64" => "claude-status"
      end
    else
      url "https://github.com/oscarangulo/claude-status/releases/latest/download/claude-status-linux-amd64"
      sha256 "" # Update after release

      def install
        bin.install "claude-status-linux-amd64" => "claude-status"
      end
    end
  end

  test do
    assert_match "claude-status", shell_output("#{bin}/claude-status --help")
  end
end
