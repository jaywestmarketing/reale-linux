#!/usr/bin/env bash
# Motorola Moto G Power — Root Helper Setup
# Installs ADB, fastboot, and Magisk tools for rooting via bootloader unlock.
# Usage: chmod +x setup.sh && ./setup.sh

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*"; exit 1; }

WORK_DIR="$HOME/moto-root-tools"

# ── Check OS ──────────────────────────────────────────────────────────────────
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    else
        error "Unsupported OS. This script supports Debian/Ubuntu, Fedora, Arch, and macOS."
    fi
    info "Detected OS: $OS"
}

# ── Install platform tools (adb + fastboot) ──────────────────────────────────
install_platform_tools() {
    info "Installing Android platform tools (adb & fastboot)..."
    case "$OS" in
        ubuntu|debian|linuxmint|pop)
            sudo apt-get update -qq
            sudo apt-get install -y android-tools-adb android-tools-fastboot curl unzip
            ;;
        fedora)
            sudo dnf install -y android-tools curl unzip
            ;;
        arch|manjaro)
            sudo pacman -Sy --noconfirm android-tools curl unzip
            ;;
        macos)
            if ! command -v brew &>/dev/null; then
                error "Homebrew required. Install from https://brew.sh"
            fi
            brew install android-platform-tools curl unzip
            ;;
        *)
            error "Unsupported distro: $OS"
            ;;
    esac
    info "adb version: $(adb version | head -1)"
    info "fastboot version: $(fastboot --version | head -1)"
}

# ── Download Magisk ───────────────────────────────────────────────────────────
download_magisk() {
    info "Downloading latest Magisk APK..."
    mkdir -p "$WORK_DIR"

    MAGISK_URL=$(curl -s https://api.github.com/repos/topjohnwu/Magisk/releases/latest \
        | grep "browser_download_url.*Magisk-.*\.apk" \
        | head -1 \
        | cut -d '"' -f 4)

    if [[ -z "$MAGISK_URL" ]]; then
        warn "Could not auto-detect Magisk URL."
        warn "Download manually from: https://github.com/topjohnwu/Magisk/releases"
    else
        curl -L -o "$WORK_DIR/Magisk.apk" "$MAGISK_URL"
        info "Magisk saved to $WORK_DIR/Magisk.apk"
    fi
}

# ── Create rooting guide ─────────────────────────────────────────────────────
create_guide() {
    cat > "$WORK_DIR/ROOT_GUIDE.txt" << 'GUIDE'
=============================================================
  Motorola Moto G Power — Rooting Guide
=============================================================

PREREQUISITES
  - USB cable
  - Motorola Moto G Power with developer options & OEM unlock enabled
  - Computer with adb & fastboot (installed by this script)

STEP 1: Enable Developer Options
  Settings → About Phone → Tap "Build Number" 7 times
  Settings → System → Developer Options → Enable "OEM Unlocking"

STEP 2: Unlock Bootloader
  a) Connect phone via USB
  b) Run:  adb reboot bootloader
  c) Run:  fastboot oem get_unlock_data
  d) Paste the unlock data at:
     https://motorola.com/unlocking-bootloader
  e) Motorola emails you an unlock key
  f) Run:  fastboot oem unlock <KEY_FROM_EMAIL>
  ⚠  This factory-resets your phone!

STEP 3: Get Stock Boot Image
  a) Find your exact firmware at:
     https://mirrors.lolinet.com/firmware/motorola/
     (match your model number from Settings → About Phone)
  b) Extract boot.img from the firmware ZIP
  c) Copy boot.img to your phone:
     adb push boot.img /sdcard/Download/

STEP 4: Patch with Magisk
  a) Install Magisk.apk on your phone (from ~/moto-root-tools/)
     adb install Magisk.apk
  b) Open Magisk → Install → Select and Patch a File
  c) Select /sdcard/Download/boot.img
  d) Magisk creates: /sdcard/Download/magisk_patched-XXXXX.img

STEP 5: Flash Patched Boot Image
  a) Pull patched image:
     adb pull /sdcard/Download/magisk_patched-*.img .
  b) Reboot to bootloader:
     adb reboot bootloader
  c) Flash:
     fastboot flash boot magisk_patched-XXXXX.img
  d) Reboot:
     fastboot reboot

STEP 6: Verify Root
  a) Open Magisk app — should show "Installed" with version
  b) Install a root checker app to confirm

DONE! Your Moto G Power is rooted.
=============================================================
GUIDE
    info "Rooting guide saved to $WORK_DIR/ROOT_GUIDE.txt"
}

# ── Flash helper script ──────────────────────────────────────────────────────
create_flash_script() {
    cat > "$WORK_DIR/flash-root.sh" << 'FLASH'
#!/usr/bin/env bash
# Flash a Magisk-patched boot image to your Moto G Power.
# Usage: ./flash-root.sh <magisk_patched.img>

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <path-to-magisk_patched.img>"
    exit 1
fi

IMG="$1"
if [[ ! -f "$IMG" ]]; then
    echo "Error: File not found: $IMG"
    exit 1
fi

echo "[1/4] Checking device connection..."
adb devices | grep -q "device$" || { echo "No device found. Connect via USB and enable USB debugging."; exit 1; }

echo "[2/4] Rebooting to bootloader..."
adb reboot bootloader
sleep 10

echo "[3/4] Flashing patched boot image..."
fastboot flash boot "$IMG"

echo "[4/4] Rebooting device..."
fastboot reboot

echo "Done! Open Magisk app to verify root."
FLASH
    chmod +x "$WORK_DIR/flash-root.sh"
    info "Flash helper saved to $WORK_DIR/flash-root.sh"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo "============================================="
    echo "  Moto G Power — Root Helper Setup"
    echo "============================================="
    echo

    detect_os
    install_platform_tools
    download_magisk
    create_guide
    create_flash_script

    echo
    info "All tools installed to: $WORK_DIR"
    info "Next steps:"
    echo "  1. Read the guide:  cat $WORK_DIR/ROOT_GUIDE.txt"
    echo "  2. Connect your phone via USB"
    echo "  3. Follow the guide step by step"
    echo "  4. Use flash-root.sh to flash the patched image"
    echo
}

main "$@"
