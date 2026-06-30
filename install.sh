#!/data/data/com.termux/files/usr/bin/bash

WHITE="\033[0;37m"
BRIGHT_WHITE="\033[1;37m"
GREY="\033[0;90m"
NC="\033[0m"

get_status() {
    local ver
    ver=$(opencode --version 2>/dev/null) || ver="Not Installed"
    echo "$ver"
}

print_header() {
    clear
    echo -e "${BRIGHT_WHITE}========================================${NC}"
    echo -e "${BRIGHT_WHITE}          OPENCODE INSTALLER            ${NC}"
    echo -e "${BRIGHT_WHITE}========================================${NC}"
    echo -e "${GREY}Repository: ${WHITE}duckesteles/termux-opencode-installer${NC}"
    echo -e "${GREY}Status:     ${WHITE}$(get_status)${NC}"
    echo -e "${BRIGHT_WHITE}----------------------------------------${NC}"
}

print_step() {
    echo -e "\n${GREY}[$1]${NC} ${WHITE}$2${NC}"
}

print_error() {
    echo -e "\n${GREY}[!]${NC} ${BRIGHT_WHITE}$1${NC}"
}

safe_git_clone_or_pull() {
    local repo_url=$1
    local target_dir=$2
    if [ ! -d "$target_dir" ]; then
        git clone "$repo_url" "$target_dir" > /dev/null 2>&1
    else
        cd "$target_dir" || return 1
        git reset --hard HEAD > /dev/null 2>&1
        git pull > /dev/null 2>&1
    fi
}

fix_wrapper_args() {
    local wrapper="$PREFIX/bin/opencode"
    if [ -f "$wrapper" ]; then
        local real_bin
        real_bin=$(dpkg -L opencode 2>/dev/null | while read -r f; do
            [ -f "$f" ] && [ -x "$f" ] && [ "$f" != "$wrapper" ] && head -c 4 "$f" 2>/dev/null | grep -q "^ELF" && echo "$f" && break
        done)
        
        if [ -n "$real_bin" ]; then
            cat > "$wrapper" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
export TMPDIR="$PREFIX/tmp"
export XDG_STATE_HOME="\${XDG_STATE_HOME:-$PREFIX/var/lib}"
trap 'stty sane' EXIT
exec "$real_bin" "\$@"
EOF
            chmod +x "$wrapper"
        fi
    fi
}

core_build_process() {
    print_step "*" "Installing build dependencies"
    pkg install -y git make patchelf binutils wget jq curl python
    
    BUILD_DIR="$HOME/tmp/opencode-termux-build"
    mkdir -p "$HOME/tmp"
    
    print_step "*" "Syncing repositories"
    safe_git_clone_or_pull "https://github.com/Hope2333/opencode-termux.git" "$BUILD_DIR"
    
    LOADER_DIR="$BUILD_DIR/third-party/bun-termux-loader"
    safe_git_clone_or_pull "https://github.com/Hope2333/bun-termux-loader.git" "$LOADER_DIR"
    
    print_step "*" "Fetching latest version"
    UPSTREAM_REPO="anomalyco/opencode"
    JSON_DATA=$(curl -s "https://api.github.com/repos/$UPSTREAM_REPO/releases/latest")
    LATEST_VER=$(echo "$JSON_DATA" | jq -r '.tag_name' | sed 's/v//')
    
    if [ -z "$LATEST_VER" ] || [ "$LATEST_VER" == "null" ]; then
        print_error "Could not resolve version"
        return 1
    fi
    
    print_step "*" "Preparing build environment ($LATEST_VER)"
    cd "$BUILD_DIR" || return 1
    make clean > /dev/null 2>&1
    rm -rf artifacts/* staged/* packaging/dpkg/work 2>/dev/null
    
    print_step "*" "Compiling binary"
    make all VER="$LATEST_VER" PKG=deb
    
    DEB_FILE="$BUILD_DIR/packaging/dpkg/opencode_${LATEST_VER}_aarch64.deb"
    
    if [ -f "$DEB_FILE" ]; then
        print_step "*" "Deploying package"
        pkg install --reinstall -y "$DEB_FILE"
        fix_wrapper_args
        make clean > /dev/null 2>&1
        rm -rf "$BUILD_DIR/.work" 2>/dev/null
    else
        print_error "Build failed"
        return 1
    fi
}

do_install_fresh() {
    print_step "1/3" "Updating system packages"
    pkg update -y && pkg upgrade -y
    
    print_step "2/3" "Installing glibc repository"
    pkg install -y glibc-repo jq curl
    
    print_step "3/3" "Installing core dependencies"
    pkg install -y glibc openssl-glibc bash ncurses
    
    core_build_process
    
    if [ $? -eq 0 ]; then
        print_step "*" "Installation completed"
    else
        print_error "Installation failed"
    fi
    read -p "Press Enter to continue..."
}

do_update() {
    if ! command -v opencode >/dev/null 2>&1; then
        print_error "OpenCode not installed"
        read -p "Press Enter to continue..."
        return
    fi
    
    core_build_process
    
    if [ $? -eq 0 ]; then
        print_step "*" "Update completed"
    else
        print_error "Update failed"
    fi
    read -p "Press Enter to continue..."
}

do_uninstall() {
    if ! command -v opencode >/dev/null 2>&1 && ! dpkg -l opencode >/dev/null 2>&1; then
        print_error "OpenCode not installed"
        read -p "Press Enter to continue..."
        return
    fi
    
    print_step "*" "Removing package"
    pkg remove -y opencode
    
    print_step "*" "Cleaning cache"
    rm -rf "$HOME/tmp/opencode-termux-build" 2>/dev/null
    
    print_step "*" "Uninstall completed"
    read -p "Press Enter to continue..."
}

main_menu() {
    local choice
    while true; do
        print_header
        echo -e "${WHITE}[1]${NC} ${GREY}Fresh Installation${NC}"
        echo -e "${WHITE}[2]${NC} ${GREY}Auto Update${NC}"
        echo -e "${WHITE}[3]${NC} ${GREY}Uninstall${NC}"
        echo -e "${WHITE}[4]${NC} ${GREY}Exit${NC}"
        echo -e "${BRIGHT_WHITE}----------------------------------------${NC}"
        echo -ne "${WHITE}Select operation:${NC} "
        read -r choice
        
        case $choice in
            1) do_install_fresh ;;
            2) do_update ;;
            3) do_uninstall ;;
            4) clear; exit 0 ;;
            *) ;;
        esac
    done
}

clear
main_menu
