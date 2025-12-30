#!/usr/bin/env bash
# install.sh - Installer for agentsync

set -e

REPO_URL="https://github.com/rdvo/agentsync.git"
INSTALL_DIR="$HOME/.agentsync"
DEFAULT_BIN="/usr/local/bin/agentsync"

echo "🚀 Installing agentsync..."

# 1. Setup source
# Check if we are running inside the repo (Dev Mode)
if [ -f "$(pwd)/agentsync" ] && [ -d "$(pwd)/.git" ]; then
    echo "📂 Local repository detected, using current directory..."
    SOURCE_DIR="$(pwd)"
else
    # User Mode: Clone/Update from GitHub
    echo "🌐 Downloading agentsync from GitHub..."
    if [ -d "$INSTALL_DIR" ]; then
        echo "🔄 Updating existing installation..."
        # Try to pull, but don't fail if dirty
        cd "$INSTALL_DIR" && git pull origin main > /dev/null 2>&1 || true
    else
        git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" > /dev/null 2>&1
    fi
    SOURCE_DIR="$INSTALL_DIR"
fi

# 2. Determine Bin Path
# Prefer /usr/local/bin, fallback to ~/.local/bin if writable and in PATH
BIN_PATH="$DEFAULT_BIN"
BIN_DIR=$(dirname "$DEFAULT_BIN")

if [[ ! -w "$BIN_DIR" ]]; then
    # /usr/local/bin is not writable. Check for alternatives.
    if [[ -d "$HOME/.local/bin" ]] && [[ ":$PATH:" == *":$HOME/.local/bin:"* ]] && [[ -w "$HOME/.local/bin" ]]; then
        BIN_PATH="$HOME/.local/bin/agentsync"
        echo "📝 Using user-local path: $BIN_PATH"
    fi
fi

# 3. Create symlink
echo "📦 Installing 'agentsync' command to $BIN_PATH..."
TARGET_DIR=$(dirname "$BIN_PATH")

if [[ -w "$TARGET_DIR" ]]; then
    ln -sf "$SOURCE_DIR/agentsync" "$BIN_PATH"
else
    echo "🔐 Permission needed for $TARGET_DIR"
    
    # Check if we have sudo
    if command -v sudo >/dev/null; then
        # Check if running interactively
        if [ -t 0 ]; then
            sudo ln -sf "$SOURCE_DIR/agentsync" "$BIN_PATH"
        else
            # Non-interactive (e.g. pipe): Can't prompt for password
            echo ""
            echo "⚠️  sudo password required, but no terminal detected."
            echo "👉 Please run this command manually to finish installation:"
            echo ""
            echo "    sudo ln -sf \"$SOURCE_DIR/agentsync\" \"$BIN_PATH\""
            echo ""
            exit 0
        fi
    else
        echo "❌ Cannot write to $BIN_PATH and 'sudo' is not available."
        exit 1
    fi
fi

# 4. Ensure executability
chmod +x "$SOURCE_DIR/agentsync"
chmod +x "$SOURCE_DIR/lib/"*.sh 2>/dev/null || true

echo ""
echo "✅ Agentsync installed successfully!"
echo "👉 Run 'agentsync init' to get started."
echo ""
