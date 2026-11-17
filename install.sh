#!/bin/zsh
# One-line installer for Touchy:
#   curl -fsSL https://raw.githubusercontent.com/beratclxn/Touchy/main/install.sh | zsh
set -euo pipefail

REPO_URL="https://github.com/beratclxn/Touchy.git"
TARBALL_URL="https://github.com/beratclxn/Touchy/archive/refs/heads/main.tar.gz"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "⚠️  Xcode Command Line Tools are required to build Touchy."
  echo "▶︎ Prompting macOS to install Command Line Tools…"
  xcode-select --install || true
  echo "Please re-run this command once the installation finishes."
  exit 1
fi

WORK_DIR="$(mktemp -d /tmp/touchy-installer.XXXXXX)"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "▶︎ Downloading Touchy from GitHub…"
if command -v git >/dev/null 2>&1; then
  git clone --depth 1 --quiet "$REPO_URL" "$WORK_DIR/Touchy"
else
  mkdir -p "$WORK_DIR/Touchy"
  curl -fsSL "$TARBALL_URL" | tar -xz --strip-components=1 -C "$WORK_DIR/Touchy"
fi

chmod +x "$WORK_DIR/Touchy/build.sh"
"$WORK_DIR/Touchy/build.sh" install
