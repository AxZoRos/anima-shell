#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

readonly APP_NAME="anima-shell"
readonly SHELL_REPO="https://github.com/AxZoRos/anima-shell.git"
readonly CLI_REPO="https://github.com/AxZoRos/anima-cli.git"
readonly SHELL_REF="main"
readonly CLI_REF="main"

readonly DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/caelestia-anima"
readonly BACKUP_DIR="$DATA_DIR/backups"
readonly INITIAL_BACKUP_DIR="$DATA_DIR/pre_anima_backup"
readonly PERMANENT_SHELL_SRC="$DATA_DIR/shell"

if [[ -f "$SCRIPT_DIR/shell.qml" && -f "$SCRIPT_DIR/CMakeLists.txt" ]]; then
    SHELL_SRC="$SCRIPT_DIR"
else
    SHELL_SRC="$PERMANENT_SHELL_SRC"
fi

readonly CLI_TEMP_DIR="$(mktemp -d /tmp/anima_cli_XXXXXX)"
readonly LOG_FILE="$(mktemp /tmp/anima_shell_XXXXXX.log)"

readonly SYSTEM_QS_DIR="/etc/xdg/quickshell/caelestia"
readonly CACHE_DIR="$HOME/.cache/caelestia"
readonly STATE_DIR="$HOME/.local/state/caelestia/wallpaper"

readonly INSTALL_TARGET_DIR="$SYSTEM_QS_DIR"
SELECTED_DECODER="vaapi"
ENABLE_BADGES="true"
TRANSITION_STYLE="shapes"
CURRENT_ROLLBACK_TAG=""

cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 && -n "${CURRENT_ROLLBACK_TAG:-}" ]]; then
        perform_rollback "$CURRENT_ROLLBACK_TAG"
    fi
    rm -rf "$CLI_TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

log_section() {
    local title="$1"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    {
        echo ""
        echo "================================================================================"
        echo "[$timestamp] STEP: $title"
        echo "================================================================================"
    } >> "$LOG_FILE"
}

log_to_file() {
    local msg="$1"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] $msg" >> "$LOG_FILE"
}

info() {
    log_to_file "[OK] $*"
    if command -v gum &>/dev/null; then
        gum style --foreground 10 "[ OK ] $*"
    else
        echo -e "\e[32m[ OK ]\e[0m $*"
    fi
}

log_step() {
    log_to_file "[>>] $*"
    if command -v gum &>/dev/null; then
        gum style --foreground 14 "[ >> ] $*"
    else
        echo -e "\e[36m[ >> ]\e[0m $*"
    fi
}

warn() {
    log_to_file "[WARN] $*"
    if command -v gum &>/dev/null; then
        gum style --foreground 11 "[WARN] $*"
    else
        echo -e "\e[33m[WARN]\e[0m $*"
    fi
}

error() {
    log_to_file "[FAIL] $*"
    if command -v gum &>/dev/null; then
        gum style --foreground 9 "[FAIL] $*" >&2
    else
        echo -e "\e[31m[FAIL]\e[0m $*" >&2
    fi
}

spinner() {
    local pid=$1
    local msg=$2
    local delay=0.1
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

    while kill -0 "$pid" 2>/dev/null; do
        for i in 0 1 2 3 4 5 6 7 8 9; do
            printf "\r\e[36m[ %s ]\e[0m %s" "${spin:$i:1}" "$msg"
            sleep $delay
            if ! kill -0 "$pid" 2>/dev/null; then break; fi
        done
    done

    local exit_code=0
    wait "$pid" || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        printf "\r\e[32m[ OK ]\e[0m %s\033[K\n" "$msg"
    else
        printf "\r\e[31m[FAIL]\e[0m %s\033[K\n" "$msg"
        error "An error occurred. Check log for details: $LOG_FILE"
        exit "$exit_code"
    fi
}

run_step() {
    local msg=$1
    shift

    if "$@" &>>"$LOG_FILE"; then
        info "$msg"
    else
        error "Failed: $msg"
        error "Check log file for details: $LOG_FILE"
        exit 1
    fi
}

run_compile_step() {
    local msg=$1
    shift

    printf "\e[36m[ >> ]\e[0m %s..." "$msg"

    local exit_code=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^EXIT_CODE:([0-9]+)$ ]]; then
            exit_code="${BASH_REMATCH[1]}"
            break
        fi

        echo "$line" >> "$LOG_FILE"

        if [[ "$line" =~ \[[[:space:]]*[0-9]+(/[0-9]+|%)\] ]]; then
            local match
            match=$(echo "$line" | grep -oE '\[[[:space:]]*[0-9]+(/[0-9]+|%)\]' | head -n1)
            printf "\r\e[36m[%s]\e[0m %s... \033[K" "$match" "$msg"
        fi
    done < <( "$@" 2>&1; echo "EXIT_CODE:$?" )

    if [ "$exit_code" -eq 0 ]; then
        printf "\r\e[32m[ OK ]\e[0m %s \033[K\n" "$msg"
    else
        printf "\r\e[31m[FAIL]\e[0m %s \033[K\n" "$msg"
        error "An error occurred during build. Check log for details: $LOG_FILE"
        exit 1
    fi
}

confirm() {
    local prompt="$1"
    local default_yes="${2:-false}"
    if command -v gum &>/dev/null; then
        if [[ "$default_yes" == "true" ]]; then
            gum confirm --default=true "$prompt"
        else
            gum confirm --default=false "$prompt"
        fi
    else
        if [[ "$default_yes" == "true" ]]; then
            echo -n "$prompt [Y/n]: "
            read -r resp
            [[ -z "$resp" || "$resp" =~ ^[Yy]$ ]]
        else
            echo -n "$prompt [y/N]: "
            read -r resp
            [[ "$resp" =~ ^[Yy]$ ]]
        fi
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

press_enter() {
    echo ""
    if command -v gum &>/dev/null; then
        gum input --placeholder="Press Enter to return to main menu..." >/dev/null
    else
        read -rp "Press Enter to return to main menu..."
    fi
}

get_version_tag() {
    local ver=""
    if [[ -d "$SHELL_SRC/.git" ]]; then
        ver=$(cd "$SHELL_SRC" && git describe --tags --abbrev=0 2>/dev/null || echo "")
    fi
    if [[ -z "$ver" ]]; then
        ver="v2.4.0"
    fi
    [[ "$ver" != v* ]] && ver="v$ver"
    echo "$ver"
}

print_header() {
    clear
    local ver
    ver=$(get_version_tag)
    if command -v gum &>/dev/null; then
        gum style --border normal --border-foreground 14 --width 50 --align center --bold \
            "ANIMA SHELL ($ver)"
    else
        echo -e "\e[1;36m+--------------------------------------------------+\e[0m"
        printf "\e[1;36m|%*s%s%*s|\e[0m\n" $(( (50 - ${#ver} - 14) / 2 )) "" "ANIMA SHELL ($ver)" $(( (50 - ${#ver} - 13) / 2 )) ""
        echo -e "\e[1;36m+--------------------------------------------------+\e[0m"
    fi
    echo ""
}

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

ensure_sudo() {
    sudo -v || { error "Administrator privileges are required to proceed."; exit 1; }
}

detect_caelestia_shell() {
    if [[ -f "$SYSTEM_QS_DIR/shell.qml" && -d "$SYSTEM_QS_DIR/modules" && -d "$SYSTEM_QS_DIR/services" ]]; then
        return 0
    fi
    return 1
}

detect_caelestia_pkg_path() {
    python3 -c "
import importlib.util, os
spec = importlib.util.find_spec('caelestia')
if spec and spec.submodule_search_locations:
    print(list(spec.submodule_search_locations)[0])
elif spec and spec.origin:
    print(os.path.dirname(spec.origin))
else:
    import site
    pkgs = site.getsitepackages()
    print(os.path.join(pkgs[0], 'caelestia') if pkgs else '')
" 2>/dev/null || echo ""
}

detect_qt6_qml_plugin_path() {
    local qml_dir
    qml_dir=$(qmake6 -query QT_INSTALL_QML 2>/dev/null || qtpaths6 --query-path QT_INSTALL_QML 2>/dev/null || qmake -query QT_INSTALL_QML 2>/dev/null || echo "")

    local candidates=()
    if [[ -n "$qml_dir" && "$qml_dir" != "/" ]]; then
        candidates+=("$qml_dir/Caelestia" "$qml_dir/caelestia")
    fi
    candidates+=(
        "/usr/lib/qt6/qml/Caelestia"
        "/usr/lib/qt6/qml/caelestia"
        "/usr/lib64/qt6/qml/Caelestia"
        "/usr/lib64/qt6/qml/caelestia"
        "/usr/lib/x86_64-linux-gnu/qt6/qml/Caelestia"
        "/usr/lib/x86_64-linux-gnu/qt6/qml/caelestia"
    )

    for dir in "${candidates[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "$dir"
            return 0
        fi
    done

    if [[ -n "$qml_dir" && "$qml_dir" != "/" ]]; then
        echo "$qml_dir/Caelestia"
    else
        echo "/usr/lib/qt6/qml/Caelestia"
    fi
}

safe_wipe_target_dir() {
    local target="$1"

    if [[ -z "$target" ]]; then
        error "safe_wipe_target_dir: Empty target path provided!"
        return 1
    fi

    local real_target
    real_target="$(realpath -m "$target" 2>/dev/null || echo "$target")"

    # Refuse root and critical system directories
    if [[ "$real_target" == "/" || "$real_target" == "/etc" || "$real_target" == "/usr" || "$real_target" == "/home" || "$real_target" == "/root" || "$real_target" == "/tmp" ]]; then
        error "safe_wipe_target_dir: Refusing to wipe forbidden system path ($real_target)!"
        return 1
    fi

    # Must end with 'caelestia'
    if [[ "$(basename "$real_target")" != "caelestia" ]]; then
        error "safe_wipe_target_dir: Target path does not end with 'caelestia' ($real_target)!"
        return 1
    fi

    # Must be under /etc/xdg/quickshell or /tmp
    if [[ "$real_target" != "/etc/xdg/quickshell/caelestia" && "$real_target" != /tmp/* ]]; then
        error "safe_wipe_target_dir: Target path is outside authorized scope ($real_target)!"
        return 1
    fi

    if [[ -d "$real_target" ]]; then
        # Wipes all files and hidden files (.dotfiles) safely using find
        if ! sudo find "$real_target" -mindepth 1 -maxdepth 1 -exec rm -rf {} +; then
            error "safe_wipe_target_dir: Failed to cleanly empty target directory: $real_target"
            return 1
        fi
    else
        if ! sudo mkdir -p "$real_target"; then
            error "safe_wipe_target_dir: Failed to create target directory: $real_target"
            return 1
        fi
    fi
}

perform_rollback() {
    local tag="$1"
    if [[ -z "$tag" ]]; then
        return 0
    fi

    echo ""
    error "================================================================"
    error "  CRITICAL: An error occurred during installation/deployment!"
    error "  Initiating automatic rollback to snapshot ($tag)..."
    error "================================================================"

    local rollback_failed=false

    # 1. Rollback Shell
    if [[ -d "$BACKUP_DIR/shell_$tag" ]]; then
        log_to_file "Rolling back Shell: $BACKUP_DIR/shell_$tag -> $INSTALL_TARGET_DIR"
        if safe_wipe_target_dir "$INSTALL_TARGET_DIR" && sudo cp -r "$BACKUP_DIR/shell_$tag"/. "$INSTALL_TARGET_DIR"/; then
            info "Shell rolled back to snapshot ($tag)."
        else
            error "Failed to cleanly roll back Shell."
            rollback_failed=true
        fi
    fi

    # 2. Rollback Plugin
    if [[ -d "$BACKUP_DIR/plugin_$tag" ]]; then
        local qml_plugin_dir
        qml_plugin_dir=$(detect_qt6_qml_plugin_path)
        if [[ -n "$qml_plugin_dir" ]]; then
            log_to_file "Rolling back C++ Plugin: $BACKUP_DIR/plugin_$tag -> $qml_plugin_dir"
            sudo rm -rf "$qml_plugin_dir"
            if sudo cp -r "$BACKUP_DIR/plugin_$tag" "$qml_plugin_dir" && sudo chown -R root:root "$qml_plugin_dir"; then
                info "C++ Plugin rolled back to snapshot ($tag)."
            else
                error "Failed to cleanly roll back C++ Plugin."
                rollback_failed=true
            fi
        fi
    fi

    # 3. Rollback Python CLI
    if [[ -d "$BACKUP_DIR/cli_$tag" ]]; then
        local py_pkg
        py_pkg=$(detect_caelestia_pkg_path)
        if [[ -n "$py_pkg" ]]; then
            log_to_file "Rolling back Python CLI: $BACKUP_DIR/cli_$tag -> $py_pkg"
            sudo rm -rf "$py_pkg"
            if sudo cp -r "$BACKUP_DIR/cli_$tag" "$py_pkg" && sudo chown -R root:root "$py_pkg"; then
                info "Python CLI rolled back to snapshot ($tag)."
            else
                error "Failed to cleanly roll back Python CLI."
                rollback_failed=true
            fi
        fi
    fi

    CURRENT_ROLLBACK_TAG=""
    restart_shell || true

    if [[ "$rollback_failed" == "false" ]]; then
        warn "Automatic rollback completed successfully. System has been restored to snapshot ($tag)."
    else
        error "Automatic rollback encountered errors. Please check the log and inspect components in Backup Manager."
    fi
    info "Review the detailed installation log at: $LOG_FILE"
}

git_clone_with_retry() {
    local repo="$1"
    local dest="$2"
    local ref="${3:-main}"
    local max_attempts=3
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        rm -rf "$dest"
        local branch_arg=()
        if [[ -n "$ref" ]]; then
            branch_arg=(--branch "$ref")
        fi

        if git clone --depth 1 "${branch_arg[@]}" "$repo" "$dest" &>>"$LOG_FILE"; then
            return 0
        fi
        log_to_file "Git clone attempt $attempt/$max_attempts failed for $repo (ref: $ref). Retrying in 2s..."
        sleep 2
        attempt=$((attempt + 1))
    done
    return 1
}

install_gum_if_needed() {
    if command -v gum &>/dev/null; then
        return 0
    fi

    local mgr
    mgr=$(detect_pkg_mgr)
    local default_gum=true

    echo -e "\e[33m[INFO] Optional: 'gum' is not installed.\e[0m"
    echo -e "\e[33m       The installer works perfectly with standard built-in CLI prompts.\e[0m"
    if [[ "$mgr" == "apt" ]]; then
        default_gum=false
        echo -e "\e[33m       (Note: Installing gum on Debian/Ubuntu requires adding the official Charm apt repository).\e[0m"
    fi

    if confirm "Would you like to install gum for enhanced interactive UI?" "$default_gum"; then
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
            dnf) sudo dnf install -y gum || true ;;
            zypper) sudo zypper install -y gum || true ;;
            xbps-install) sudo xbps-install -y gum || true ;;
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
    ensure_sudo
    log_section "Verifying System Dependencies"

    if ! detect_caelestia_shell; then
        error "Caelestia Shell was not found on this system."
        error "Anima Shell is an enhancement patch designed to work on top of an existing Caelestia Shell installation."
        error "Please install the official Caelestia Shell first before installing Anima Shell."
        exit 1
    fi

    log_step "Checking and installing required dependencies..."
    local mgr
    mgr=$(detect_pkg_mgr)
    local aur
    aur=$(detect_aur_helper)

    case "$mgr" in
        pacman)
            local pkgs=(
                cmake ninja gcc extra-cmake-modules
                ffmpeg
                qt6-base qt6-declarative qt6-multimedia qt6-multimedia-ffmpeg qt6-svg qt6-shadertools
                gst-plugins-good gst-plugins-bad gst-plugins-ugly gst-libav
                python python-pip python-pillow
            )
            (sudo pacman -S --needed --noconfirm "${pkgs[@]}") &>>"$LOG_FILE" &
            spinner $! "Verifying system packages"
            ;;

        dnf)
            (sudo dnf install -y \
                cmake ninja-build gcc-c++ extra-cmake-modules \
                ffmpeg ffmpeg-free \
                qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtmultimedia-devel qt6-qtsvg-devel qt6-qtshadertools-devel \
                gstreamer1-plugins-good gstreamer1-plugins-bad-free gstreamer1-libav \
                python3 python3-pip python3-pillow) &>>"$LOG_FILE" &
            spinner $! "Installing system dependencies"
            ;;

        apt)
            (sudo apt update && sudo apt install -y \
                cmake ninja-build g++ extra-cmake-modules \
                ffmpeg \
                qt6-base-dev qt6-declarative-dev qt6-multimedia-dev libqt6svg6-dev qt6-shadertools \
                gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav \
                python3 python3-pip python3-pil) &>>"$LOG_FILE" &
            spinner $! "Installing system dependencies"
            ;;

        zypper)
            (sudo zypper install -y \
                cmake ninja gcc extra-cmake-modules \
                ffmpeg \
                qt6-base-devel qt6-declarative-devel qt6-multimedia-devel libQt6Svg6 qt6-shadertools \
                gstreamer-plugins-good gstreamer-plugins-bad gstreamer-plugins-libav \
                python3 python3-pip python3-Pillow) &>>"$LOG_FILE" &
            spinner $! "Installing system dependencies"
            ;;

        xbps-install)
            (sudo xbps-install -y \
                cmake ninja gcc extra-cmake-modules \
                ffmpeg \
                qt6-base-devel qt6-declarative-devel qt6-multimedia-devel qt6-svg-devel qt6-shadertools \
                gst-plugins-good1 gst-plugins-bad1 gst-libav1 \
                python3 python3-pip python3-Pillow) &>>"$LOG_FILE" &
            spinner $! "Installing system dependencies"
            ;;

        *)
            warn "Unsupported package manager detected."
            local missing_tools=()
            for tool in cmake ninja gcc ffmpeg python3; do
                command -v "$tool" &>/dev/null || missing_tools+=("$tool")
            done
            if [[ ${#missing_tools[@]} -gt 0 ]]; then
                error "Missing required build/runtime dependencies: ${missing_tools[*]}"
                error "Please install the following dependencies using your distribution's package manager:"
                error "  • Build tools: cmake, ninja, gcc / g++"
                error "  • Qt6 & Multimedia: qt6-base, qt6-declarative, qt6-multimedia, qt6-shadertools"
                error "  • GStreamer / Media: gst-plugins-good, gst-plugins-bad, gst-libav, ffmpeg"
                error "  • Python modules: python3, python3-pip, pillow, materialyoucolor"
                exit 1
            fi
            ;;
    esac

    log_step "Verifying Python runtime dependencies..."
    if ! python3 -c "import materialyoucolor, PIL" &>/dev/null; then
        (
            python3 -m pip install --break-system-packages --user materialyoucolor pillow 2>/dev/null || \
            python3 -m pip install --user materialyoucolor pillow 2>/dev/null || \
            sudo python3 -m pip install --break-system-packages materialyoucolor pillow
        ) &>>"$LOG_FILE" &
        spinner $! "Installing Python dependencies (materialyoucolor, pillow)"
    fi

    if ! python3 -c "import materialyoucolor, PIL" &>/dev/null; then
        error "Failed to install required Python dependencies (materialyoucolor, pillow)."
        error "Please install python-materialyoucolor and python-pillow manually via your package manager."
        exit 1
    fi

    info "All core dependencies verified and ready."
}

clone_or_update_repos() {
    log_section "Fetching / Updating Git Repositories"
    if [[ "$SHELL_SRC" == "$SCRIPT_DIR" ]]; then
        info "Using active Anima Shell workspace at $SHELL_SRC"
    elif [[ -d "$SHELL_SRC/.git" ]]; then
        log_step "Updating shell repository in $SHELL_SRC (branch: $SHELL_REF)..."
        (
            cd "$SHELL_SRC"
            git fetch origin "$SHELL_REF"
            git checkout "$SHELL_REF" 2>/dev/null || true
            git reset --hard "origin/$SHELL_REF"
        ) &>>"$LOG_FILE" &
        spinner $! "Updating shell repository"
    else
        mkdir -p "$DATA_DIR"
        log_step "Cloning shell repository into $SHELL_SRC (ref: $SHELL_REF)..."
        (git_clone_with_retry "$SHELL_REPO" "$SHELL_SRC" "$SHELL_REF") &
        spinner $! "Cloning shell repository"
    fi

    log_step "Cloning Anima CLI into temporary workspace (ref: $CLI_REF)..."
    (git_clone_with_retry "$CLI_REPO" "$CLI_TEMP_DIR" "$CLI_REF") &
    spinner $! "Fetching CLI components"
}

prompt_user_configurations() {
    local step=1
    log_step "Configuration Options"

    while true; do
        case "$step" in
            1)
                echo ""
                echo "Select preferred video hardware decoding backend:"
                echo -e "\e[2m(Can also be changed anytime in Nexus Settings -> Wallpaper & Style)\e[0m"
                local dec_choice
                dec_choice=$(choose \
                    "VA-API (recommended - Intel / AMD / Mesa)" \
                    "NVDEC / CUDA (NVIDIA proprietary drivers)" \
                    "Software (CPU fallback - universal)" \
                    "Cancel and return to main menu")

                if [[ "$dec_choice" == "Cancel and return to main menu" || -z "$dec_choice" ]]; then
                    warn "Configuration cancelled by user."
                    return 1
                fi

                if [[ "$dec_choice" =~ ^VA-API ]]; then
                    SELECTED_DECODER="vaapi"
                elif [[ "$dec_choice" =~ ^NVDEC ]]; then
                    SELECTED_DECODER="cuda"
                else
                    SELECTED_DECODER="none"
                fi
                info "Video Decoder: $SELECTED_DECODER"
                step=2
                ;;

            2)
                echo ""
                echo "Display format, FPS, and bitrate badges on launcher cards?"
                echo -e "\e[2m(Can also be toggled anytime in Nexus Settings or via launcher hover capsule)\e[0m"
                local badge_choice
                badge_choice=$(choose \
                    "Enable Badges (recommended)" \
                    "Disable Badges (clean cards)" \
                    "Back to previous step" \
                    "Cancel and return to main menu")

                if [[ "$badge_choice" == "Back to previous step" ]]; then
                    step=1
                    continue
                elif [[ "$badge_choice" == "Cancel and return to main menu" || -z "$badge_choice" ]]; then
                    warn "Configuration cancelled by user."
                    return 1
                fi

                if [[ "$badge_choice" =~ ^Enable ]]; then
                    ENABLE_BADGES="true"
                else
                    ENABLE_BADGES="false"
                fi
                info "Thumbnail Badges: $ENABLE_BADGES"
                step=3
                ;;

            3)
                echo ""
                echo "Select wallpaper transition effect:"
                echo -e "\e[2m(Can also be changed anytime in Nexus Settings -> Wallpaper & Style)\e[0m"
                local trans_choice
                trans_choice=$(choose \
                    "Material Shape Morph Transitions (recommended)" \
                    "Classic Cross-Fade (minimalist)" \
                    "Back to previous step" \
                    "Cancel and return to main menu")

                if [[ "$trans_choice" == "Back to previous step" ]]; then
                    step=2
                    continue
                elif [[ "$trans_choice" == "Cancel and return to main menu" || -z "$trans_choice" ]]; then
                    warn "Configuration cancelled by user."
                    return 1
                fi

                if [[ "$trans_choice" =~ ^Material ]]; then
                    TRANSITION_STYLE="shapes"
                else
                    TRANSITION_STYLE="crossfade"
                fi
                info "Transition Style: $TRANSITION_STYLE"
                echo ""
                return 0
                ;;
        esac
    done
}

save_initial_backup() {
    mkdir -p "$INITIAL_BACKUP_DIR"

    # 1. System Shell
    if [[ ! -e "$INITIAL_BACKUP_DIR/shell_original" && -d "$SYSTEM_QS_DIR" ]]; then
        log_to_file "Creating protected initial backup of $SYSTEM_QS_DIR -> $INITIAL_BACKUP_DIR/shell_original"
        sudo cp -r "$SYSTEM_QS_DIR" "$INITIAL_BACKUP_DIR/shell_original"
        sudo chown -R "$(id -u):$(id -g)" "$INITIAL_BACKUP_DIR/shell_original"
    fi

    # 2. Python CLI
    local site_pkg
    site_pkg=$(detect_caelestia_pkg_path)
    if [[ ! -e "$INITIAL_BACKUP_DIR/cli_original" && -n "$site_pkg" && -d "$site_pkg" ]]; then
        log_to_file "Creating protected initial backup of $site_pkg -> $INITIAL_BACKUP_DIR/cli_original"
        sudo cp -r "$site_pkg" "$INITIAL_BACKUP_DIR/cli_original"
        sudo chown -R "$(id -u):$(id -g)" "$INITIAL_BACKUP_DIR/cli_original"
    fi

    # 3. Qt6 QML Plugin
    local qml_plugin_dir
    qml_plugin_dir=$(detect_qt6_qml_plugin_path)
    if [[ ! -e "$INITIAL_BACKUP_DIR/plugin_original" && -n "$qml_plugin_dir" && -d "$qml_plugin_dir" ]]; then
        log_to_file "Creating protected initial backup of $qml_plugin_dir -> $INITIAL_BACKUP_DIR/plugin_original"
        sudo cp -r "$qml_plugin_dir" "$INITIAL_BACKUP_DIR/plugin_original"
        sudo chown -R "$(id -u):$(id -g)" "$INITIAL_BACKUP_DIR/plugin_original"
    fi
}

create_shell_backup() {
    local target="$1"
    local tag="${2:-$(date +%Y%m%d_%H%M%S)}"
    mkdir -p "$BACKUP_DIR"

    if [[ -d "$target" && -n "$(ls -A "$target" 2>/dev/null)" ]]; then
        local archive="$BACKUP_DIR/shell_${tag}"
        log_step "Creating safety backup of $target -> $archive..."
        sudo cp -r "$target" "$archive"
        sudo chown -R "$(id -u):$(id -g)" "$archive"
        if [[ ! -d "$archive" ]]; then
            error "Failed to create safety backup of $target. Aborting installation."
            exit 1
        fi
        info "Shell backup verified: $archive"
    fi

    local qml_plugin_dir
    qml_plugin_dir=$(detect_qt6_qml_plugin_path)
    if [[ -n "$qml_plugin_dir" && -d "$qml_plugin_dir" ]]; then
        local plugin_archive="$BACKUP_DIR/plugin_${tag}"
        log_step "Creating safety backup of C++ plugin -> $plugin_archive..."
        sudo cp -r "$qml_plugin_dir" "$plugin_archive"
        sudo chown -R "$(id -u):$(id -g)" "$plugin_archive"
        if [[ ! -d "$plugin_archive" ]]; then
            error "Failed to create safety backup of C++ plugin ($qml_plugin_dir). Aborting installation."
            exit 1
        fi
        info "Plugin backup verified: $plugin_archive"
    fi
}

create_cli_backup() {
    local tag="${1:-$(date +%Y%m%d_%H%M%S)}"
    local site_pkg
    site_pkg=$(detect_caelestia_pkg_path)
    mkdir -p "$BACKUP_DIR"

    if [[ -n "$site_pkg" && -d "$site_pkg" ]]; then
        local cli_archive="$BACKUP_DIR/cli_${tag}"
        log_step "Creating safety backup of Python CLI -> $cli_archive..."
        sudo cp -r "$site_pkg" "$cli_archive"
        sudo chown -R "$(id -u):$(id -g)" "$cli_archive"
        if [[ ! -d "$cli_archive" ]]; then
            error "Failed to create safety backup of Python CLI ($site_pkg). Aborting installation."
            exit 1
        fi
        info "CLI backup verified: $cli_archive"
    fi
}

restore_full_snapshot() {
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        warn "No backups available to restore."
        press_enter
        return 0
    fi

    # Find all unique date tags
    local date_tags=()
    while IFS= read -r tag; do
        [[ -n "$tag" ]] && date_tags+=("$tag")
    done < <(find "$BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | \
             sed -nE 's/.*(shell|cli|plugin)_([0-9]{8}_[0-9]{6})$/\2/p' | sort -ur)

    if [[ ${#date_tags[@]} -eq 0 ]]; then
        warn "No timestamped snapshot sets found in $BACKUP_DIR."
        press_enter
        return 0
    fi

    echo ""
    echo "Select Full Snapshot date to restore (Shell + CLI + Plugin):"
    local menu_items=()
    for tag in "${date_tags[@]}"; do
        local components=()
        [[ -d "$BACKUP_DIR/shell_$tag" ]] && components+=("Shell")
        [[ -d "$BACKUP_DIR/cli_$tag" ]] && components+=("CLI")
        [[ -d "$BACKUP_DIR/plugin_$tag" ]] && components+=("Plugin")

        local comp_str
        comp_str=$(IFS=, ; echo "${components[*]}")

        local human_date="${tag:0:4}-${tag:4:2}-${tag:6:2} ${tag:9:2}:${tag:11:2}:${tag:13:2}"
        menu_items+=("$human_date ($tag) [$comp_str]")
    done

    menu_items+=("Cancel and return")

    local selected
    selected=$(choose "${menu_items[@]}")

    if [[ "$selected" == "Cancel and return" || -z "$selected" ]]; then
        return 0
    fi

    local chosen_tag
    chosen_tag=$(echo "$selected" | grep -oE '[0-9]{8}_[0-9]{6}')

    if [[ -z "$chosen_tag" ]]; then
        error "Could not parse snapshot timestamp."
        press_enter
        return 1
    fi

    local has_shell=false
    [[ -d "$BACKUP_DIR/shell_$chosen_tag" ]] && has_shell=true
    ensure_sudo
    log_section "Restoring Full Snapshot ($chosen_tag)"

    # 1. Restore Shell
    if [[ "$has_shell" == "true" ]]; then
        local dst="$SYSTEM_QS_DIR"
        log_step "Restoring Shell to $dst..."
        safe_wipe_target_dir "$dst"
        sudo cp -r "$BACKUP_DIR/shell_$chosen_tag"/. "$dst"/
        info "Shell QML files restored to $dst"
    fi

    # 2. Restore CLI
    if [[ -d "$BACKUP_DIR/cli_$chosen_tag" ]]; then
        local py_pkg
        py_pkg=$(detect_caelestia_pkg_path)
        if [[ -n "$py_pkg" ]]; then
            log_step "Restoring Python CLI to $py_pkg..."
            sudo rm -rf "$py_pkg"
            sudo cp -r "$BACKUP_DIR/cli_$chosen_tag" "$py_pkg"
            sudo chown -R root:root "$py_pkg"
            info "Python CLI package restored."
        fi
    fi

    # 3. Restore C++ Plugin
    if [[ -d "$BACKUP_DIR/plugin_$chosen_tag" ]]; then
        local qml_plugin_dir
        qml_plugin_dir=$(detect_qt6_qml_plugin_path)
        if [[ -n "$qml_plugin_dir" ]]; then
            log_step "Restoring Qt6 C++ plugin to $qml_plugin_dir..."
            sudo rm -rf "$qml_plugin_dir"
            sudo cp -r "$BACKUP_DIR/plugin_$chosen_tag" "$qml_plugin_dir"
            sudo chown -R root:root "$qml_plugin_dir"
            info "Qt6 C++ plugin restored."
        fi
    fi

    restart_shell

    echo ""
    info "================================================================"
    info "  Full snapshot ($chosen_tag) restored successfully!"
    info "================================================================"
    press_enter
}

restore_single_backup() {
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        warn "No backups available to restore."
        press_enter
        return 0
    fi

    echo ""
    echo "Select backup to restore:"
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

    if [[ "$selected" =~ ^cli_ ]]; then
        local py_pkg
        py_pkg=$(detect_caelestia_pkg_path)
        if [[ -n "$py_pkg" ]]; then
            log_step "Restoring CLI package to $py_pkg..."
            sudo rm -rf "$py_pkg"
            sudo cp -r "$selected_path" "$py_pkg"
            sudo chown -R root:root "$py_pkg"
            info "Python CLI restored successfully from $selected!"
        fi
    elif [[ "$selected" =~ ^plugin_ ]]; then
        local qml_plugin_dir
        qml_plugin_dir=$(detect_qt6_qml_plugin_path)
        if [[ -n "$qml_plugin_dir" ]]; then
            log_step "Restoring C++ plugin to $qml_plugin_dir..."
            sudo rm -rf "$qml_plugin_dir"
            sudo cp -r "$selected_path" "$qml_plugin_dir"
            sudo chown -R root:root "$qml_plugin_dir"
            info "Qt6 C++ plugin restored successfully from $selected!"
            restart_shell
        fi
    else
        local dst="$SYSTEM_QS_DIR"
        ensure_sudo
        log_step "Restoring $selected to $dst (requires sudo)..."
        safe_wipe_target_dir "$dst"
        sudo cp -r "$selected_path"/. "$dst"/
        info "Successfully restored $selected to $dst!"
        restart_shell
    fi

    press_enter
}

delete_single_backup() {
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        warn "No backups available to delete."
        press_enter
        return 0
    fi

    echo ""
    echo "Select backup to delete:"
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

    if confirm "Are you sure you want to permanently delete '$selected'?"; then
        sudo rm -rf "$BACKUP_DIR/$selected" 2>/dev/null || rm -rf "$BACKUP_DIR/$selected"
        info "Deleted backup: $selected"
    else
        warn "Deletion cancelled."
    fi

    press_enter
}

delete_all_backups() {
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        warn "Backup directory is already empty."
        press_enter
        return 0
    fi

    warn "WARNING: This will permanently delete ALL stored backups in $BACKUP_DIR!"
    if confirm "Do you want to proceed and delete ALL backups?"; then
        sudo rm -rf "${BACKUP_DIR:?}"/* 2>/dev/null || rm -rf "${BACKUP_DIR:?}"/* 2>/dev/null || true
        info "All backups successfully purged."
    else
        warn "Purge cancelled."
    fi

    press_enter
}

revert_to_upstream_caelestia() {
    print_header
    warn "Revert / Reset to Stock Upstream Caelestia"
    echo ""
    echo "This will download official upstream Caelestia Shell and CLI from GitHub"
    echo "and install them cleanly, removing all Anima Shell modifications."
    echo ""

    if ! confirm "Are you sure you want to revert to official upstream Caelestia?"; then
        return 0
    fi

    ensure_sudo

    local dst="$INSTALL_TARGET_DIR"
    info "Target Directory: $dst"

    # Create safety backup before performing reset
    local snapshot_tag
    snapshot_tag="$(date +%Y%m%d_%H%M%S)"
    create_shell_backup "$dst" "$snapshot_tag"
    create_cli_backup "$snapshot_tag"

    local stock_shell_tmp
    stock_shell_tmp=$(mktemp -d /tmp/stock_shell_XXXXXX)
    local stock_cli_tmp
    stock_cli_tmp=$(mktemp -d /tmp/stock_cli_XXXXXX)

    # Phase 1: Download latest stable release archives
    log_step "Detecting latest stable upstream releases..."
    local shell_ver
    shell_ver=$(curl -sIL "https://github.com/caelestia-dots/shell/releases/latest" 2>/dev/null | grep -i "^location:" | sed -E 's/.*tag\/v?//' | tr -d '\r\n' || echo "")
    [[ -z "$shell_ver" ]] && shell_ver="2.4.0"

    local cli_ver
    cli_ver=$(curl -sIL "https://github.com/caelestia-dots/cli/releases/latest" 2>/dev/null | grep -i "^location:" | sed -E 's/.*tag\///' | tr -d '\r\n' || echo "")
    [[ -z "$cli_ver" ]] && cli_ver="v1.1.2"

    log_step "Fetching official Caelestia Shell stable archive (v$shell_ver)..."
    (
        curl -sL "https://github.com/caelestia-dots/shell/releases/latest/download/caelestia-shell-latest.tar.gz" | tar -xz -C "$stock_shell_tmp" --strip-components=1
    ) &>>"$LOG_FILE" &
    spinner $! "Downloading and extracting upstream shell (v$shell_ver)"

    log_step "Fetching official Caelestia CLI stable archive ($cli_ver)..."
    (
        curl -sL "https://github.com/caelestia-dots/cli/archive/refs/tags/${cli_ver}.tar.gz" | tar -xz -C "$stock_cli_tmp" --strip-components=1
    ) &>>"$LOG_FILE" &
    spinner $! "Downloading and extracting upstream CLI ($cli_ver)"

    # Phase 2: Build C++ plugins
    log_step "Configuring upstream Caelestia Shell (v$shell_ver)..."
    (
        cmake -B "$stock_shell_tmp/build" -S "$stock_shell_tmp" -G Ninja \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX=/usr \
            -DCMAKE_INSTALL_SYSCONFDIR=/etc \
            -DCMAKE_INSTALL_LIBDIR=lib \
            -DVERSION="$shell_ver" \
            -DGIT_REVISION="$shell_ver"
    ) &>>"$LOG_FILE" &
    spinner $! "CMake configuration"

    run_compile_step "Compiling upstream plugins" cmake --build "$stock_shell_tmp/build"

    # Phase 3: Deploy (only after all downloads and builds succeed)
    CURRENT_ROLLBACK_TAG="$snapshot_tag"
    local install_upstream_plugins
    install_upstream_plugins() {
        sudo cmake --install "$stock_shell_tmp/build"
    }
    run_step "Upstream C++ plugins installed" install_upstream_plugins

    log_step "Deploying upstream shell files to $dst..."
    safe_wipe_target_dir "$dst"
    sudo cp -r "$stock_shell_tmp"/assets "$stock_shell_tmp"/components "$stock_shell_tmp"/modules "$stock_shell_tmp"/services "$stock_shell_tmp"/utils "$stock_shell_tmp"/shell.qml "$dst"/
    info "Upstream shell deployed to $dst"

    local site_pkg
    site_pkg=$(detect_caelestia_pkg_path)

    if [[ -n "$site_pkg" && -d "$site_pkg" ]]; then
        (
            sudo rm -rf "$site_pkg"
            sudo cp -r "$stock_cli_tmp/src/caelestia" "$site_pkg"
            sudo chown -R root:root "$site_pkg"
        ) &>>"$LOG_FILE" &
        spinner $! "Restoring upstream CLI package ($cli_ver)"
    else
        (
            cd "$stock_cli_tmp"
            sudo python3 -m pip install --break-system-packages --no-deps . 2>/dev/null || \
            python3 -m pip install --break-system-packages --user --no-deps . 2>/dev/null || \
            python3 -m pip install --user .
        ) &>>"$LOG_FILE" &
        spinner $! "Installing upstream CLI ($cli_ver)"
    fi

    log_step "Cleaning cache..."
    if confirm "Remove generated video thumbnails and cache ($CACHE_DIR)?"; then
        rm -rf "$CACHE_DIR"
        info "Cache removed."
    fi

    rm -rf "$stock_shell_tmp" "$stock_cli_tmp" 2>/dev/null || true

    restart_shell
    CURRENT_ROLLBACK_TAG=""

    echo ""
    info "================================================================"
    info "  Successfully uninstalled Anima Shell & restored Caelestia!"
    if [[ -d "$INITIAL_BACKUP_DIR" ]]; then
        info "  Original pre-Anima snapshot is preserved at:"
        info "  $INITIAL_BACKUP_DIR"
    fi
    info "================================================================"
    press_enter
}

restore_pre_anima_backup() {
    if [[ ! -d "$INITIAL_BACKUP_DIR" ]] || [[ -z "$(ls -A "$INITIAL_BACKUP_DIR" 2>/dev/null)" ]]; then
        warn "No protected Pre-Anima factory backup found in $INITIAL_BACKUP_DIR."
        press_enter
        return 0
    fi

    echo ""
    warn "Restore Protected Factory Backup (Pre-Anima Snapshot)"
    echo "This will restore the original Shell, CLI, and C++ Plugin from before Anima was installed."
    echo ""

    if ! confirm "Are you sure you want to restore the Pre-Anima factory backup?"; then
        return 0
    fi

    ensure_sudo
    log_section "Restoring Pre-Anima Factory Backup"

    # 1. Restore Shell
    if [[ -d "$INITIAL_BACKUP_DIR/shell_original" ]]; then
        local dst="$SYSTEM_QS_DIR"
        log_step "Restoring original Shell to $dst..."
        safe_wipe_target_dir "$dst"
        sudo cp -r "$INITIAL_BACKUP_DIR/shell_original"/. "$dst"/
        info "Original Shell restored to $dst"
    fi

    # 2. Restore CLI
    if [[ -d "$INITIAL_BACKUP_DIR/cli_original" ]]; then
        local py_pkg
        py_pkg=$(detect_caelestia_pkg_path)
        if [[ -n "$py_pkg" ]]; then
            log_step "Restoring original Python CLI to $py_pkg..."
            sudo rm -rf "$py_pkg"
            sudo cp -r "$INITIAL_BACKUP_DIR/cli_original" "$py_pkg"
            sudo chown -R root:root "$py_pkg"
            info "Original Python CLI package restored."
        fi
    fi

    # 3. Restore Qt6 Plugin
    if [[ -d "$INITIAL_BACKUP_DIR/plugin_original" ]]; then
        local qml_plugin_dir
        qml_plugin_dir=$(detect_qt6_qml_plugin_path)
        if [[ -n "$qml_plugin_dir" ]]; then
            log_step "Restoring original Qt6 C++ plugin to $qml_plugin_dir..."
            sudo rm -rf "$qml_plugin_dir"
            sudo cp -r "$INITIAL_BACKUP_DIR/plugin_original" "$qml_plugin_dir"
            sudo chown -R root:root "$qml_plugin_dir"
            info "Original Qt6 C++ plugin restored."
        fi
    fi

    restart_shell

    echo ""
    info "================================================================"
    info "  Pre-Anima factory backup restored successfully!"
    info "================================================================"
    press_enter
}

manage_backups() {
    while true; do
        print_header
        log_step "Backup Manager & Restore"
        echo ""

        if [[ -d "$INITIAL_BACKUP_DIR" && -n "$(ls -A "$INITIAL_BACKUP_DIR" 2>/dev/null)" ]]; then
            local pre_size
            pre_size="$(du -sh "$INITIAL_BACKUP_DIR" 2>/dev/null | awk '{print $1}')"
            echo -e "\e[1;32m   [Protected Factory Backup]\e[0m $INITIAL_BACKUP_DIR ($pre_size)"
        fi

        local backup_count=0
        if [[ -d "$BACKUP_DIR" ]]; then
            backup_count=$(find "$BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
        fi

        echo "Stored regular backups in $BACKUP_DIR: $backup_count"
        if [[ $backup_count -gt 0 ]]; then
            echo ""
            while IFS= read -r line; do
                local b_name
                b_name="$(basename "$line")"
                local b_size
                b_size="$(du -sh "$line" 2>/dev/null | awk '{print $1}')"
                echo "   • $b_name ($b_size)"
            done < <(find "$BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d | sort -r)
        fi
        echo ""

        local choice
        choice=$(choose \
            "[1] Restore Full Snapshot by Date (Shell + CLI + Plugin)" \
            "[2] Restore Protected Pre-Anima Factory Backup" \
            "[3] Restore Individual Component (Single Backup)" \
            "[4] Delete a Specific Backup" \
            "[5] Delete ALL Regular Backups (Purge)" \
            "[0] Return to Main Menu")

        case "$choice" in
            "[1] Restore Full Snapshot by Date (Shell + CLI + Plugin)")
                restore_full_snapshot
                ;;
            "[2] Restore Protected Pre-Anima Factory Backup")
                restore_pre_anima_backup
                ;;
            "[3] Restore Individual Component (Single Backup)")
                restore_single_backup
                ;;
            "[4] Delete a Specific Backup")
                delete_single_backup
                ;;
            "[5] Delete ALL Regular Backups (Purge)")
                delete_all_backups
                ;;
            "[0] Return to Main Menu"|*)
                return 0
                ;;
        esac
    done
}

build_and_deploy_shell() {
    [[ ! -d "$SHELL_SRC" ]] && { error "Shell repository not found in $SHELL_SRC."; return 1; }

    log_section "Building & Deploying Anima Shell"
    log_to_file "Source Workspace: $SHELL_SRC"
    log_to_file "Target Directory: $INSTALL_TARGET_DIR"

    log_step "Configuring CMake for Caelestia C++ plugin..."
    local build_dir="$SHELL_SRC/build"

    local git_rev
    git_rev=$(cd "$SHELL_SRC" && git rev-parse HEAD 2>/dev/null || echo "main")

    local git_ver
    git_ver=$(cd "$SHELL_SRC" && git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "2.4.0")
    [[ -z "$git_ver" || "$git_ver" =~ [^0-9.] ]] && git_ver="2.4.0"

    log_to_file "Version Tag: $git_ver (Commit: $git_rev)"

    local enable_modules="extras;plugin;shell"

    (
        cmake -B "$build_dir" -S "$SHELL_SRC" -G Ninja \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DCMAKE_INSTALL_PREFIX=/usr \
            -DCMAKE_INSTALL_SYSCONFDIR=/etc \
            -DCMAKE_INSTALL_LIBDIR=lib \
            -DENABLE_MODULES="$enable_modules" \
            -DVERSION="$git_ver" \
            -DGIT_REVISION="$git_rev" \
            -DDISTRIBUTOR="Anima Shell"
    ) &>>"$LOG_FILE" &
    spinner $! "CMake configuration"

    run_compile_step "Compiling C++ plugins" cmake --build "$build_dir"

    install_shell_plugin() {
        sudo cmake --install "$build_dir"
    }
    run_step "C++ plugins installed" install_shell_plugin

    log_step "Deploying shell files to $INSTALL_TARGET_DIR..."
    safe_wipe_target_dir "$INSTALL_TARGET_DIR"
    sudo cp -r "$SHELL_SRC"/assets "$SHELL_SRC"/components "$SHELL_SRC"/modules "$SHELL_SRC"/services "$SHELL_SRC"/utils "$SHELL_SRC"/shell.qml "$INSTALL_TARGET_DIR"/
    [[ -f "$INSTALL_TARGET_DIR/assets/wrap_term_launch.sh" ]] && sudo chmod +x "$INSTALL_TARGET_DIR/assets/wrap_term_launch.sh"

    mkdir -p "$CACHE_DIR/videothumbs" "$CACHE_DIR/wallpapers"
    log_to_file "Deployed QML components to: $INSTALL_TARGET_DIR"
    info "Shell deployed to $INSTALL_TARGET_DIR"
}

install_python_cli() {
    local cli_dir="$CLI_TEMP_DIR"
    [[ ! -d "$cli_dir/src/caelestia" ]] && { error "CLI sources not found in $cli_dir."; return 1; }

    log_section "Patching Python CLI Package"
    log_step "Patching and installing Python CLI into system..."

    local site_pkg
    site_pkg=$(detect_caelestia_pkg_path)

    if [[ -n "$site_pkg" && -d "$site_pkg" ]]; then
        log_to_file "Copying CLI files: $cli_dir/src/caelestia/ -> $site_pkg/"
        (
            sudo cp -a "$cli_dir/src/caelestia/." "$site_pkg/"
            sudo chown -R root:root "$site_pkg"
        ) &>>"$LOG_FILE" &
        spinner $! "Patching system CLI package ($site_pkg)"
    else
        log_to_file "Running pip install from $cli_dir..."
        (
            cd "$cli_dir"
            sudo python3 -m pip install --break-system-packages --no-deps . 2>/dev/null || \
            python3 -m pip install --break-system-packages --user --no-deps . 2>/dev/null || \
            python3 -m pip install --user .
        ) &>>"$LOG_FILE" &
        spinner $! "Installing CLI package"
    fi

    if ! command -v caelestia &>/dev/null; then
        error "Caelestia CLI binary ('caelestia') not found in PATH after installation."
        return 1
    fi

    log_to_file "Verified caelestia binary at: $(command -v caelestia)"
    info "Python CLI ready: $(command -v caelestia)"
}

apply_settings() {
    local force="${1:-false}"
    log_section "Applying Configuration"
    log_step "Writing configuration..."
    mkdir -p "$STATE_DIR" "$CACHE_DIR/videothumbs"

    local ui_state_file="$STATE_DIR/ui_state.json"

    if [[ "$force" != "true" && -f "$ui_state_file" ]]; then
        info "Preserving existing user settings in $ui_state_file"
        return 0
    fi

    local b_mode=0
    if [[ "$ENABLE_BADGES" != "true" ]]; then
        b_mode=1
    fi

    local anim_enabled="True"
    if [[ "$TRANSITION_STYLE" != "shapes" ]]; then
        anim_enabled="False"
    fi

    log_to_file "Writing state to $ui_state_file: decoder=$SELECTED_DECODER, badges=$ENABLE_BADGES, animation=$TRANSITION_STYLE"

    python3 - "$ui_state_file" "$b_mode" "$anim_enabled" "$SELECTED_DECODER" << 'EOF' &>>"$LOG_FILE" || true
import sys, json, os

state_file, b_mode, anim_enabled, decoder = sys.argv[1:5]
state_file = os.path.expanduser(state_file)
data = {}
if os.path.exists(state_file):
    try:
        with open(state_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception:
        pass

data['badgeMode'] = int(b_mode)
data['enableAnimation'] = (anim_enabled.lower() == "true")
data['hwDecoder'] = decoder

with open(state_file, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2)
EOF

    info "Settings configured (decoder: $SELECTED_DECODER, badges: $ENABLE_BADGES, transitions: $TRANSITION_STYLE)"
}

restart_shell() {
    log_step "Restarting Caelestia Shell..."
    (
        caelestia shell -k 2>/dev/null || true
        sleep 1
        caelestia shell -d >/dev/null 2>&1 || true
        sleep 1.5

        if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]]; then
            if pgrep -f "quickshell.*caelestia" >/dev/null 2>&1 || \
               pgrep -f "qs.*caelestia" >/dev/null 2>&1 || \
               pgrep -x "quickshell" >/dev/null 2>&1 || \
               pgrep -x "qs" >/dev/null 2>&1; then
                exit 0
            else
                echo "ERROR: Caelestia shell process failed to start after restart." >> "$LOG_FILE"
                exit 1
            fi
        fi
        exit 0
    ) &>>"$LOG_FILE" &
    spinner $! "Restarting Caelestia Shell"
}

full_installation() {
    print_header
    log_step "Starting Full Installation of Anima Shell..."
    ensure_sudo
    echo ""

    install_dependencies
    clone_or_update_repos
    if ! prompt_user_configurations; then
        press_enter
        return 0
    fi

    # Create protected initial backup on first install
    save_initial_backup

    # Create safety backups before any modifications
    local snapshot_tag
    snapshot_tag="$(date +%Y%m%d_%H%M%S)"
    create_shell_backup "$INSTALL_TARGET_DIR" "$snapshot_tag"
    create_cli_backup "$snapshot_tag"
    CURRENT_ROLLBACK_TAG="$snapshot_tag"

    build_and_deploy_shell
    install_python_cli
    apply_settings "true"
    restart_shell
    CURRENT_ROLLBACK_TAG=""

    echo ""
    info "================================================================"
    info "  Anima Shell has been installed successfully!"
    info "  Wallpapers directory: ~/Pictures/Wallpapers"
    warn "  NOTE: When you open the launcher and video wallpapers are found"
    warn "  in ~/Pictures/Wallpapers, background thumbnail generation will"
    warn "  start automatically (burst mode CPU activity is expected)."
    info "  Full build log available at: $LOG_FILE"
    info "================================================================"
    press_enter
}

update_anima_shell() {
    print_header
    log_step "Updating Anima Shell..."
    ensure_sudo
    echo ""
    info "Target Directory: $INSTALL_TARGET_DIR"

    install_dependencies
    clone_or_update_repos

    # Create safety backups before any modifications
    local snapshot_tag
    snapshot_tag="$(date +%Y%m%d_%H%M%S)"
    create_shell_backup "$INSTALL_TARGET_DIR" "$snapshot_tag"
    create_cli_backup "$snapshot_tag"
    CURRENT_ROLLBACK_TAG="$snapshot_tag"

    build_and_deploy_shell
    install_python_cli
    apply_settings "false"
    restart_shell
    CURRENT_ROLLBACK_TAG=""

    echo ""
    info "================================================================"
    info "  Anima Shell updated successfully!"
    info "  Wallpapers directory: ~/Pictures/Wallpapers"
    warn "  NOTE: When you open the launcher and video wallpapers are found"
    warn "  in ~/Pictures/Wallpapers, background thumbnail generation will"
    warn "  start automatically (burst mode CPU activity is expected)."
    info "  Full build log available at: $LOG_FILE"
    info "================================================================"
    press_enter
}

repair_installation() {
    print_header
    log_step "Repair & Re-apply Patches Mode"
    echo ""

    warn "WARNING: This option will re-apply all Anima Shell patches over the current install."
    echo ""
    echo "If upstream Caelestia was recently updated, proceeding is only safe if none"
    echo "of the following Anima-modified files were rewritten by upstream:"
    echo ""
    echo -e "\e[1;36m  Modified Shell Files:\e[0m"
    echo "   • modules/background/Wallpaper.qml"
    echo "   • modules/launcher/Content.qml"
    echo "   • modules/launcher/WallpaperList.qml"
    echo "   • modules/launcher/items/WallpaperItem.qml"
    echo "   • modules/nexus/common/WallItem.qml"
    echo "   • modules/nexus/pages/WallpaperAndStyle.qml"
    echo "   • services/Wallpapers.qml"
    echo "   • services/Colours.qml"
    echo ""
    echo -e "\e[1;36m  Added Anima Shell Components:\e[0m"
    echo "   • modules/background/VideoWallpaper.qml"
    echo "   • services/WallpaperPauser.qml"
    echo "   • services/WallpaperThumbQueue.qml"
    echo ""
    echo -e "\e[1;36m  Modified Python CLI Files:\e[0m"
    echo "   • src/caelestia/parser.py"
    echo "   • src/caelestia/subcommands/wallpaper.py"
    echo "   • src/caelestia/subcommands/shell.py"
    echo "   • src/caelestia/utils/wallpaper.py"
    echo "   • src/caelestia/utils/paths.py"
    echo ""

    local confirm_repair
    confirm_repair=$(choose \
        "Proceed with Repair (re-apply patches)" \
        "Cancel and return to main menu")

    if [[ "$confirm_repair" != "Proceed with Repair (re-apply patches)" ]]; then
        warn "Repair cancelled by user."
        press_enter
        return 0
    fi

    ensure_sudo
    info "Target Directory: $INSTALL_TARGET_DIR"

    clone_or_update_repos

    # Create safety backups before applying patches
    local snapshot_tag
    snapshot_tag="$(date +%Y%m%d_%H%M%S)"
    create_shell_backup "$INSTALL_TARGET_DIR" "$snapshot_tag"
    create_cli_backup "$snapshot_tag"
    CURRENT_ROLLBACK_TAG="$snapshot_tag"

    log_step "Re-applying Anima QML files to $INSTALL_TARGET_DIR..."
    safe_wipe_target_dir "$INSTALL_TARGET_DIR"
    sudo cp -r "$SHELL_SRC"/assets "$SHELL_SRC"/components "$SHELL_SRC"/modules "$SHELL_SRC"/services "$SHELL_SRC"/utils "$SHELL_SRC"/shell.qml "$INSTALL_TARGET_DIR"/
    [[ -f "$INSTALL_TARGET_DIR/assets/wrap_term_launch.sh" ]] && sudo chmod +x "$INSTALL_TARGET_DIR/assets/wrap_term_launch.sh"
    info "QML files re-applied."

    install_python_cli
    apply_settings "false"
    restart_shell
    CURRENT_ROLLBACK_TAG=""

    echo ""
    info "================================================================"
    info "  Repair completed! Patches successfully re-applied."
    warn "  NOTE: When you open the launcher and video wallpapers are found"
    warn "  in ~/Pictures/Wallpapers, background thumbnail generation will"
    warn "  start automatically (burst mode CPU activity is expected)."
    info "  Full build log available at: $LOG_FILE"
    info "================================================================"
    press_enter
}

uninstall_caelestia() {
    revert_to_upstream_caelestia
}

main_menu() {
    [[ $EUID -eq 0 ]] && { error "Please run this installer as a regular user, not root (sudo will be asked when needed)."; exit 1; }
    command -v git &>/dev/null || { error "git is required. Please install git first."; exit 1; }

    install_gum_if_needed

    while true; do
        print_header

        local choice
        choice=$(choose \
            "[1] Complete Installation (recommended)" \
            "[2] Update Anima Shell" \
            "[3] Repair / Re-apply Patches" \
            "[4] Backup Manager & Restore" \
            "[5] Uninstall Anima / Restore Upstream Caelestia" \
            "[0] Exit")

        case "$choice" in
            "[1] Complete Installation (recommended)")
                full_installation
                ;;
            "[2] Update Anima Shell")
                update_anima_shell
                ;;
            "[3] Repair / Re-apply Patches")
                repair_installation
                ;;
            "[4] Backup Manager & Restore")
                manage_backups
                ;;
            "[5] Uninstall Anima / Restore Upstream Caelestia")
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
