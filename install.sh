#!/usr/bin/env bash

## ==============================================================================
## Anima Shell - Installer & Deployment Script
## Dynamic Video Wallpapers, Hardware Acceleration & Fluid Desktop Suite
## Repository: https://github.com/AxZoRos/anima-shell
## CLI Repo:   https://github.com/AxZoRos/anima-cli
## ==============================================================================

set -euo pipefail

# Script Constants
readonly APP_NAME="anima-shell"
readonly SHELL_REPO="https://github.com/AxZoRos/anima-shell.git"
readonly CLI_REPO="https://github.com/AxZoRos/anima-cli.git"

readonly SRC_DIR="$HOME/.local/src"
readonly SHELL_SRC="$SRC_DIR/anima-shell"
readonly CLI_SRC="$SRC_DIR/anima-cli"

readonly BACKUP_DIR="$HOME/.local/share/caelestia-anima/backups"
readonly SYSTEM_QS_DIR="/etc/xdg/quickshell/caelestia"
readonly USER_QS_DIR="$HOME/.config/quickshell/caelestia"
readonly CACHE_DIR="$HOME/.cache/caelestia"

readonly DATE_TAG=$(date +%Y%m%d_%H%M%S)

# Selected configuration variables
INSTALL_TARGET_DIR="$SYSTEM_QS_DIR"
SELECTED_DECODER="vaapi"
ENABLE_BADGES="true"
TRANSITION_STYLE="shapes"

# ------------------------------------------------------------------------------
# Logging and Output Functions (ASCII style, strictly no emojis)
# ------------------------------------------------------------------------------

info() {
    if command -v gum &>/dev/null; then
        gum style --foreground 10 "[ OK ] $*"
    else
        echo -e "\e[32m[ OK ]\e[0m $*"
    fi
}

log_step() {
    if command -v gum &>/dev/null; then
        gum style --foreground 14 "[ >> ] $*"
    else
        echo -e "\e[36m[ >> ]\e[0m $*"
    fi
}

warn() {
    if command -v gum &>/dev/null; then
        gum style --foreground 11 "[WARN] $*"
    else
        echo -e "\e[33m[WARN]\e[0m $*"
    fi
}

error() {
    if command -v gum &>/dev/null; then
        gum style --foreground 9 "[FAIL] $*" >&2
    else
        echo -e "\e[31m[FAIL]\e[0m $*" >&2
    fi
}

# ------------------------------------------------------------------------------
# UI Helpers with gum / terminal fallback
# ------------------------------------------------------------------------------

confirm() {
    local prompt="$1"
    if command -v gum &>/dev/null; then
        gum confirm "$prompt"
    else
        echo -n "$prompt [y/N]: "
        read -r resp
        [[ "$resp" =~ ^[Yy]$ ]]
    fi
}

choose() {
    if command -v gum &>/dev/null; then
        gum choose --cursor=">> " --cursor.foreground 14 --header="" "$@"
    else
        local PS3="Please select an option: "
        select opt in "$@"; do
            if [[ -n "$opt" ]]; then
                echo "$opt"
                break
            fi
        done
    fi
}

spin() {
    local title="$1"
    shift
    if command -v gum &>/dev/null; then
        gum spin --spinner="line" --title="[ .. ] $title" -- "$@"
    else
        echo -e "\e[36m[ .. ] $title\e[0m"
        "$@"
    fi
}

press_enter() {
    echo ""
    if command -v gum &>/dev/null; then
        gum input --placeholder="Press Enter to return to main menu..." >/dev/null
    else
        read -rp "Press Enter to return to main menu..."
    fi
}

print_header() {
    clear
    if command -v gum &>/dev/null; then
        gum style --border normal --border-foreground 14 --padding "0 2" --bold \
            "+-------------------------------------------------------------+" \
            "|                       ANIMA SHELL                           |" \
            "|      Dynamic Video Wallpaper, C++ Plugins & Desktop Suite   |" \
            "+-------------------------------------------------------------+"
    else
        echo -e "\e[1;36m+-------------------------------------------------------------+\e[0m"
        echo -e "\e[1;36m|                       ANIMA SHELL                           |\e[0m"
        echo -e "\e[1;36m|      Dynamic Video Wallpaper, C++ Plugins & Desktop Suite   |\e[0m"
        echo -e "\e[1;36m+-------------------------------------------------------------+\e[0m"
    fi
    echo ""
}

# ------------------------------------------------------------------------------
# Package Manager & System Dependency Detection
# ------------------------------------------------------------------------------

detect_pkg_mgr() {
    for mgr in pacman dnf apt zypper xbps-install; do
        if command -v "$mgr" &>/dev/null; then
            echo "$mgr"
            return 0
        fi
    done
    echo "unknown"
}

detect_aur_helper() {
    for helper in paru yay; do
        if command -v "$helper" &>/dev/null; then
            echo "$helper"
            return 0
        fi
    done
    echo ""
}

install_gum_if_needed() {
    if command -v gum &>/dev/null; then
        return 0
    fi

    echo -e "\e[33m[INFO] 'gum' is not installed. It provides an enhanced interactive UI.\e[0m"
    if confirm "Would you like to install gum now?"; then
        local mgr
        mgr=$(detect_pkg_mgr)
        local aur
        aur=$(detect_aur_helper)

        case "$mgr" in
            pacman)
                if [[ -n "$aur" ]]; then
                    "$aur" -S --needed gum
                else
                    sudo pacman -S --needed gum || true
                fi
                ;;
            dnf)
                sudo dnf install -y gum || true
                ;;
            zypper)
                sudo zypper install -y gum || true
                ;;
            xbps-install)
                sudo xbps-install -y gum || true
                ;;
            apt)
                sudo mkdir -p /etc/apt/keyrings
                curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
                echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
                sudo apt update && sudo apt install -y gum || true
                ;;
        esac
    fi
}

install_dependencies() {
    log_step "Detecting package manager and installing core dependencies..."
    local mgr
    mgr=$(detect_pkg_mgr)
    local aur
    aur=$(detect_aur_helper)

    info "Detected package manager: $mgr"

    case "$mgr" in
        pacman)
            local pacman_pkgs=(
                cmake ninja gcc extra-cmake-modules
                ffmpeg
                qt6-base qt6-declarative qt6-multimedia qt6-multimedia-ffmpeg qt6-svg qt6-shadertools
                gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav
                python python-pip python-pillow
            )
            sudo pacman --needed -S "${pacman_pkgs[@]}"

            if ! command -v quickshell &>/dev/null; then
                if [[ -n "$aur" ]]; then
                    info "Installing quickshell via $aur..."
                    "$aur" -S --needed quickshell-git || "$aur" -S --needed quickshell
                else
                    warn "quickshell not found in standard repositories. Please install quickshell via AUR (e.g. paru -S quickshell-git)."
                fi
            fi
            ;;

        dnf)
            sudo dnf install -y \
                cmake ninja-build gcc-c++ extra-cmake-modules \
                ffmpeg ffmpeg-free \
                qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtmultimedia-devel qt6-qtsvg-devel qt6-qtshadertools-devel \
                gstreamer1-plugins-good gstreamer1-plugins-bad-free gstreamer1-libav \
                python3 python3-pip python3-pillow
            ;;

        apt)
            sudo apt update
            sudo apt install -y \
                cmake ninja-build g++ extra-cmake-modules \
                ffmpeg \
                qt6-base-dev qt6-declarative-dev qt6-multimedia-dev libqt6svg6-dev qt6-shadertools \
                gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav \
                python3 python3-pip python3-pil
            ;;

        zypper)
            sudo zypper install -y \
                cmake ninja gcc-c++ extra-cmake-modules \
                ffmpeg \
                qt6-base-devel qt6-declarative-devel qt6-multimedia-devel libQt6Svg6 qt6-shadertools \
                gstreamer-plugins-good gstreamer-plugins-bad gstreamer-plugins-libav \
                python3 python3-pip python3-Pillow
            ;;

        xbps-install)
            sudo xbps-install -y \
                cmake ninja gcc extra-cmake-modules \
                ffmpeg \
                qt6-base-devel qt6-declarative-devel qt6-multimedia-devel qt6-svg-devel qt6-shadertools \
                gst-plugins-good1 gst-plugins-bad1 gst-libav1 \
                python3 python3-pip python3-Pillow
            ;;

        *)
            warn "Unsupported package manager. Please ensure cmake, ninja, qt6-multimedia, ffmpeg, and python-pillow are installed manually."
            ;;
    esac

    # Ensure materialyoucolor and pillow are present for python CLI
    python3 -m pip install --break-system-packages --user materialyoucolor pillow 2>/dev/null || \
    python3 -m pip install --user materialyoucolor pillow 2>/dev/null || true

    info "Core dependencies verified and installed."
}

# ------------------------------------------------------------------------------
# Repository Clone & Update Logic
# ------------------------------------------------------------------------------

clone_or_update_repos() {
    mkdir -p "$SRC_DIR"

    # Clone/update shell repository
    if [[ -d "$SHELL_SRC/.git" ]]; then
        log_step "Updating existing shell repository in $SHELL_SRC..."
        (cd "$SHELL_SRC" && git pull --rebase) || warn "Failed to update $SHELL_SRC, keeping existing sources"
    else
        [[ -d "$SHELL_SRC" ]] && rm -rf "$SHELL_SRC"
        log_step "Cloning shell repository from $SHELL_REPO..."
        spin "Cloning caelestia-shell-live..." git clone --depth 1 "$SHELL_REPO" "$SHELL_SRC"
    fi

    # Clone/update cli repository
    if [[ -d "$CLI_SRC/.git" ]]; then
        log_step "Updating existing cli repository in $CLI_SRC..."
        (cd "$CLI_SRC" && git pull --rebase) || warn "Failed to update $CLI_SRC, keeping existing sources"
    else
        [[ -d "$CLI_SRC" ]] && rm -rf "$CLI_SRC"
        log_step "Cloning cli repository from $CLI_REPO..."
        spin "Cloning caelestia-cli-live..." git clone --depth 1 "$CLI_REPO" "$CLI_SRC"
    fi

    info "Repositories synchronized in $SRC_DIR"
}

# ------------------------------------------------------------------------------
# Interactive Configuration Questions
# ------------------------------------------------------------------------------

prompt_user_configurations() {
    echo ""
    log_step "Configuration Options"

    # 1. Target Directory Choice
    echo ""
    echo "Select shell destination directory:"
    local dir_choice
    dir_choice=$(choose \
        "/etc/xdg/quickshell/caelestia (default - system-wide)" \
        "~/.config/quickshell/caelestia (user config)")

    if [[ "$dir_choice" =~ ^/etc ]]; then
        INSTALL_TARGET_DIR="$SYSTEM_QS_DIR"
    else
        INSTALL_TARGET_DIR="$USER_QS_DIR"
    fi
    info "Target Directory: $INSTALL_TARGET_DIR"

    # 2. Hardware Video Decoder Choice
    echo ""
    echo "Select preferred video hardware decoding backend:"
    echo "(Note: You can change this anytime later in settings)"
    local dec_choice
    dec_choice=$(choose \
        "VA-API (recommended - Intel / AMD / Mesa)" \
        "NVDEC / CUDA (NVIDIA proprietary drivers)" \
        "Software (CPU fallback - universal)")

    if [[ "$dec_choice" =~ ^VA-API ]]; then
        SELECTED_DECODER="vaapi"
    elif [[ "$dec_choice" =~ ^NVDEC ]]; then
        SELECTED_DECODER="cuda"
    else
        SELECTED_DECODER="software"
    fi
    info "Video Decoder: $SELECTED_DECODER"

    # 3. Badges on Thumbnails Choice
    echo ""
    echo "Display format, FPS, and bitrate badges on launcher wallpaper cards?"
    echo "(Note: You can toggle and cycle badge corners anytime in the launcher)"
    local badge_choice
    badge_choice=$(choose \
        "Enable Badges (recommended)" \
        "Disable Badges (clean cards)")

    if [[ "$badge_choice" =~ ^Enable ]]; then
        ENABLE_BADGES="true"
    else
        ENABLE_BADGES="false"
    fi
    info "Thumbnail Badges: $ENABLE_BADGES"

    # 4. Wallpaper Transition Style Choice
    echo ""
    echo "Select wallpaper transition effect:"
    echo "(Note: You can toggle this in background settings)"
    local trans_choice
    trans_choice=$(choose \
        "Material Shape Morph Transitions (recommended)" \
        "Classic Cross-Fade (minimalist)")

    if [[ "$trans_choice" =~ ^Material ]]; then
        TRANSITION_STYLE="shapes"
    else
        TRANSITION_STYLE="crossfade"
    fi
    info "Transition Style: $TRANSITION_STYLE"
}

# ------------------------------------------------------------------------------
# Backup & Restore Logic
# ------------------------------------------------------------------------------

create_backup() {
    local target="$1"
    if [[ -d "$target" ]]; then
        mkdir -p "$BACKUP_DIR"
        local archive="$BACKUP_DIR/caelestia_backup_${DATE_TAG}"
        log_step "Creating backup of existing $target -> $archive..."
        if [[ "$target" =~ ^/etc ]]; then
            sudo cp -r "$target" "$archive"
        else
            cp -r "$target" "$archive"
        fi
        info "Backup created at: $archive"
    fi
}

restore_backup() {
    print_header
    log_step "Restore Previous Backup"

    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        warn "No backups found in $BACKUP_DIR."
        press_enter
        return 0
    fi

    echo "Available backups:"
    local backups=()
    while IFS= read -r line; do
        backups+=("$(basename "$line")")
    done < <(find "$BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d | sort -r)

    backups+=("Cancel and return")

    local selected
    selected=$(choose "${backups[@]}")

    if [[ "$selected" == "Cancel and return" || -z "$selected" ]]; then
        return 0
    fi

    local selected_path="$BACKUP_DIR/$selected"
    echo "Restore target directory:"
    local restore_target
    restore_target=$(choose \
        "/etc/xdg/quickshell/caelestia (default - system-wide)" \
        "~/.config/quickshell/caelestia (user config)")

    local dst
    if [[ "$restore_target" =~ ^/etc ]]; then
        dst="$SYSTEM_QS_DIR"
        log_step "Restoring $selected to $dst (requires sudo)..."
        sudo rm -rf "$dst"
        sudo mkdir -p "$(dirname "$dst")"
        sudo cp -r "$selected_path" "$dst"
    else
        dst="$USER_QS_DIR"
        log_step "Restoring $selected to $dst..."
        rm -rf "$dst"
        mkdir -p "$(dirname "$dst")"
        cp -r "$selected_path" "$dst"
    fi

    info "Successfully restored $selected to $dst!"
    press_enter
}

# ------------------------------------------------------------------------------
# Build & Installation Steps
# ------------------------------------------------------------------------------

build_and_deploy_shell() {
    [[ ! -d "$SHELL_SRC" ]] && { error "Shell repository not found in $SHELL_SRC. Clone it first."; return 1; }

    log_step "Configuring and compiling Caelestia C++ plugin..."
    local build_dir="$SHELL_SRC/build"

    local git_rev
    git_rev=$(cd "$SHELL_SRC" && git rev-parse HEAD 2>/dev/null || echo "live")

    # Run CMake configuration and build
    cmake -B "$build_dir" -S "$SHELL_SRC" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DVERSION="live" \
        -DGIT_REVISION="$git_rev"

    spin "Compiling plugin & dependencies..." cmake --build "$build_dir"

    # Install C++ plugin system-wide so QML engine can load Caelestia and M3Shapes plugins
    log_step "Installing compiled C++ plugins (requires sudo for /usr/lib/qt6/qml)..."
    sudo cmake --install "$build_dir" --component plugin 2>/dev/null || \
    sudo cmake --install "$build_dir" || true

    # Create backup before deploying QML configs
    create_backup "$INSTALL_TARGET_DIR"

    # Deploy QML shell files to target destination
    log_step "Deploying shell files to $INSTALL_TARGET_DIR..."
    if [[ "$INSTALL_TARGET_DIR" =~ ^/etc ]]; then
        sudo mkdir -p "$INSTALL_TARGET_DIR"
        sudo cp -r "$SHELL_SRC"/assets "$SHELL_SRC"/components "$SHELL_SRC"/modules "$SHELL_SRC"/services "$SHELL_SRC"/utils "$SHELL_SRC"/shell.qml "$INSTALL_TARGET_DIR"/
        [[ -f "$SHELL_SRC/LICENSE" ]] && sudo cp "$SHELL_SRC/LICENSE" "$INSTALL_TARGET_DIR"/
        sudo chmod +x "$INSTALL_TARGET_DIR/assets/wrap_term_launch.sh" 2>/dev/null || true
    else
        mkdir -p "$INSTALL_TARGET_DIR"
        cp -r "$SHELL_SRC"/assets "$SHELL_SRC"/components "$SHELL_SRC"/modules "$SHELL_SRC"/services "$SHELL_SRC"/utils "$SHELL_SRC"/shell.qml "$INSTALL_TARGET_DIR"/
        [[ -f "$SHELL_SRC/LICENSE" ]] && cp "$SHELL_SRC/LICENSE" "$INSTALL_TARGET_DIR"/
        chmod +x "$INSTALL_TARGET_DIR/assets/wrap_term_launch.sh" 2>/dev/null || true
    fi

    # Initialize cache directories
    mkdir -p "$CACHE_DIR/videothumbs" "$CACHE_DIR/wallpapers"

    info "Caelestia Shell successfully deployed to $INSTALL_TARGET_DIR"
}

install_python_cli() {
    [[ ! -d "$CLI_SRC" ]] && { error "CLI repository not found in $CLI_SRC. Clone it first."; return 1; }

    log_step "Installing Caelestia Python CLI..."
    (
        cd "$CLI_SRC"
        python3 -m pip install --break-system-packages --user -e . 2>/dev/null || \
        python3 -m pip install --user -e .
    )

    # Verify caelestia executable
    if command -v caelestia &>/dev/null; then
        info "Python CLI installed successfully: $(command -v caelestia)"
    elif [[ -f "$HOME/.local/bin/caelestia" ]]; then
        info "Python CLI installed in $HOME/.local/bin/caelestia"
        warn "Make sure $HOME/.local/bin is added to your PATH in ~/.bashrc or ~/.zshrc."
    fi
}

apply_settings() {
    log_step "Writing initial configuration..."
    local config_dir="$HOME/.config/caelestia"
    mkdir -p "$config_dir"

    # Pre-generate thumbnail cache directory
    mkdir -p "$CACHE_DIR/videothumbs"
    info "Cache initialized at $CACHE_DIR"
}

# ------------------------------------------------------------------------------
# Full Complete Installation Flow
# ------------------------------------------------------------------------------

full_installation() {
    print_header
    log_step "Starting Full Installation of Caelestia Live..."

    install_dependencies
    clone_or_update_repos
    prompt_user_configurations
    build_and_deploy_shell
    install_python_cli
    apply_settings

    echo ""
    info "================================================================"
    info "  Caelestia Live has been installed successfully!"
    info "  You can start or restart the shell with: caelestia shell"
    info "================================================================"
    press_enter
}

# ------------------------------------------------------------------------------
# Uninstaller
# ------------------------------------------------------------------------------

uninstall_caelestia() {
    print_header
    warn "Uninstall Caelestia Live"
    if ! confirm "Are you sure you want to remove Caelestia Live components?"; then
        return 0
    fi

    log_step "Removing installed shell configs..."
    [[ -d "$USER_QS_DIR" ]] && rm -rf "$USER_QS_DIR" && info "Removed $USER_QS_DIR"
    if [[ -d "$SYSTEM_QS_DIR" ]]; then
        sudo rm -rf "$SYSTEM_QS_DIR" && info "Removed $SYSTEM_QS_DIR"
    fi

    log_step "Uninstalling Python CLI..."
    python3 -m pip uninstall -y caelestia 2>/dev/null || true

    log_step "Cleaning cache..."
    if confirm "Remove generated video thumbnails and cache ($CACHE_DIR)?"; then
        rm -rf "$CACHE_DIR"
        info "Cache removed."
    fi

    info "Caelestia Live uninstalled. Backups remain intact in $BACKUP_DIR."
    press_enter
}

# ------------------------------------------------------------------------------
# Main Menu Loop
# ------------------------------------------------------------------------------

main_menu() {
    [[ $EUID -eq 0 ]] && { error "Please run this installer as a regular user, not root (sudo will be asked when needed)."; exit 1; }
    command -v git &>/dev/null || { error "git is required. Please install git first."; exit 1; }

    install_gum_if_needed

    while true; do
        print_header

        local choice
        choice=$(choose \
            "[1] Complete Installation (recommended)" \
            "[2] Install / Verify Dependencies" \
            "[3] Clone / Update Repositories" \
            "[4] Build & Deploy Shell" \
            "[5] Install / Update Python CLI" \
            "[6] Restore Previous Backup" \
            "[7] Uninstall Caelestia Live" \
            "[0] Exit")

        case "$choice" in
            "[1] Complete Installation (recommended)")
                full_installation
                ;;
            "[2] Install / Verify Dependencies")
                print_header
                install_dependencies
                press_enter
                ;;
            "[3] Clone / Update Repositories")
                print_header
                clone_or_update_repos
                press_enter
                ;;
            "[4] Build & Deploy Shell")
                print_header
                prompt_user_configurations
                build_and_deploy_shell
                press_enter
                ;;
            "[5] Install / Update Python CLI")
                print_header
                install_python_cli
                press_enter
                ;;
            "[6] Restore Previous Backup")
                restore_backup
                ;;
            "[7] Uninstall Caelestia Live")
                uninstall_caelestia
                ;;
            "[0] Exit"|*)
                info "Exiting installer. Goodbye!"
                exit 0
                ;;
        esac
    done
}

main_menu "$@"
