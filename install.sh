#!/usr/bin/env bash
# install.sh - Installer for agentsync

set -e

REPO_URL="https://github.com/rdvo/agentsync.git"
INSTALL_DIR="$HOME/.agentsync"
BIN_PATH="/usr/local/bin/agentsync"

echo "🚀 Installing agentsync..."

# 1. Setup source
if [ -f "$(pwd)/agentsync" ] && [ -d "$(pwd)/.git" ] && grep -q "agentsync" "$(pwd)/.git/config" 2>/dev/null; then
    echo "📂 Local repository detected, using current directory..."
    SOURCE_DIR="$(pwd)"
else
    echo "🌐 Downloading agentsync from GitHub..."
    if [ -d "$INSTALL_DIR" ]; then
        echo "🔄 Updating existing installation..."
        cd "$INSTALL_DIR" && git pull origin main > /dev/null 2>&1
    else
        git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" > /dev/null 2>&1
    fi
    SOURCE_DIR="$INSTALL_DIR"
fi

# 2. Create symlink
echo "🔗 Creating symlink..."
if [[ ! -w "$(dirname "$BIN_PATH")" ]]; then
    echo "🔐 Permission denied. Requesting sudo for symlink..."
    sudo ln -sf "$SOURCE_DIR/agentsync" "$BIN_PATH"
else
    ln -sf "$SOURCE_DIR/agentsync" "$BIN_PATH"
fi

# 3. Ensure executability
chmod +x "$SOURCE_DIR/agentsync"
chmod +x "$SOURCE_DIR/lib/"*.sh 2>/dev/null || true

echo ""
echo "✅ Agentsync installed successfully!"
echo "👉 You can now run 'agentsync init' from any directory."
echo ""
