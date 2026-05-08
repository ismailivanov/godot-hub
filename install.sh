#!/usr/bin/env bash
set -e

REPO="ismailivanov/godot-hub"
INSTALL_DIR="$HOME/.local/bin"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
DESKTOP_DIR="$HOME/.local/share/applications"
APP_NAME="godot-hub"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}=>${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}✓${RESET} $*"; }
error()   { echo -e "${RED}${BOLD}✗${RESET} $*" >&2; exit 1; }

# Check dependencies
for cmd in curl unzip; do
    command -v "$cmd" &>/dev/null || error "Required command not found: $cmd"
done

# Fetch latest release info
info "Fetching latest release..."
RELEASE_JSON=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest")
VERSION=$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep '"browser_download_url"' | grep 'Linux.zip' | cut -d'"' -f4)

[ -z "$VERSION" ]      && error "Could not fetch release info. Check your internet connection."
[ -z "$DOWNLOAD_URL" ] && error "Could not find Linux download URL."

info "Installing Godot Hub ${VERSION}..."

# Create directories
mkdir -p "$INSTALL_DIR" "$ICON_DIR" "$DESKTOP_DIR"

# Download and extract binary
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

info "Downloading binary..."
curl -fsSL "$DOWNLOAD_URL" -o "$TMP_DIR/Linux.zip"
unzip -q "$TMP_DIR/Linux.zip" -d "$TMP_DIR"
install -m755 "$TMP_DIR/GodotHub.x86_64" "$INSTALL_DIR/$APP_NAME"

# Download icon
info "Downloading icon..."
curl -fsSL "https://raw.githubusercontent.com/${REPO}/${VERSION}/icon.png" \
    -o "$ICON_DIR/$APP_NAME.png"

# Create desktop entry
info "Creating desktop entry..."
cat > "$DESKTOP_DIR/$APP_NAME.desktop" << EOF
[Desktop Entry]
Name=Godot Hub
GenericName=Godot Version Manager
Comment=Desktop app for managing Godot Engine versions and projects
Exec=$INSTALL_DIR/$APP_NAME
Icon=$APP_NAME
Terminal=false
PrefersNonDefaultGPU=true
Type=Application
Categories=Development;IDE;
StartupWMClass=Godot Hub
EOF

# Refresh icon/desktop caches
update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
gtk-update-icon-cache -q -t -f "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

# Ensure ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo ""
    echo -e "${CYAN}${BOLD}Note:${RESET} Add the following to your shell config (~/.bashrc, ~/.zshrc, etc.):"
    echo -e "  ${BOLD}export PATH=\"\$HOME/.local/bin:\$PATH\"${RESET}"
fi

echo ""
success "Godot Hub ${VERSION} installed successfully!"
echo -e "  Run with: ${BOLD}godot-hub${RESET}"
echo -e "  Or launch from your application menu."
