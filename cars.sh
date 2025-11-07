#!/usr/bin/env bash

# Chris's Auto Rice Script
#------------------------------
# This rice script is for Debian - based distros.

# Better error handling - allow undefined variables but catch other errors
# set -eo pipefail  # Exit on error and pipe failures, but allow undefined vars

# Check if running in Docker container
check_docker_environment() {
    local in_docker=false

    # Multiple checks to detect if you're in a container
    if [[ -f /.dockerenv ]]; then
        in_docker=true
    elif [[ -f /run/.containerenv ]]; then
        in_docker=true
    elif grep -q 'docker\|lxc\|containerd' /proc/1/cgroup 2>/dev/null; then
        in_docker=true
    fi

    if [[ "$in_docker" == "true" ]]; then
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║                                                            ║"
        echo "║         RUNNING IN DOCKER CONTAINER - SAFE MODE            ║"
        echo "║                                                            ║"
        echo "║  This script is executing inside a Docker container.       ║"
        echo "║  All changes will be isolated from your host system.       ║"
        echo "║                                                            ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        return 0
    else
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║                                                            ║"
        echo "║          WARNING: RUNNING ON HOST SYSTEM!                  ║"
        echo "║                                                            ║"
        echo "║  This script is designed to run in a Docker container.     ║"
        echo "║  Running it on your host system will modify your OS!       ║"
        echo "║                                                            ║"
        echo "║  To run safely in Docker:                                  ║"
        echo "║    make test-quick   (for quick tests)                     ║"
        echo "║    make run-script   (for full script)                     ║"
        echo "║                                                            ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""

        # Check if FORCE_HOST_RUN is set (for advanced users)
        if [[ "${FORCE_HOST_RUN:-0}" != "1" ]]; then
            read -r -p "Do you REALLY want to run this on your HOST SYSTEM? (type 'yes' to continue): " response
            if [[ "$response" != "yes" ]]; then
                echo "Aborting. Please use Docker for safe testing."
                exit 1
            fi
            echo "⚠️  Proceeding with HOST SYSTEM execution at your own risk! ⚠️"
            echo ""
        fi
        return 1
    fi
}

debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo "DEBUG: $*" >&2
    fi
}

progress() {
    echo "PROGRESS: $*"
}

# Enhanced error function that doesn't always exit
error() {
    print_msg "$RED" "Error: $1" >&2
    if [[ "${FATAL_ERROR:-1}" == "1" ]]; then
        exit 1
    fi
}

# Non-fatal error function
warning_error() {
    print_msg "$YELLOW" "Error: $1" >&2
    return 1
}

readonly BOLD="\e[1m"
readonly RESET="\e[0m"
readonly RED="\e[31m"
readonly GREEN="\e[32m"
readonly YELLOW="\e[33m"
readonly BLUE="\e[34m"

print_msg() {
        local color="$1"
        local msg="$2"
        printf "${color}${BOLD}%s${RESET}\n" "$msg"
}

success(){
        print_msg "$GREEN" "Success: $1" >&2
}

info(){
        print_msg "$BLUE" "Info: $1"
}

warning(){
       print_msg "$YELLOW" "Warning: $1"
}

check_root () {
    if [[ "$(id -u)" -ne 0 ]]; then
        error "Please run this script as root or with sudo."
    fi
    info "Running as root - OK"
}

update_system() {
        printf "\033[1;31m[+] Updating system...\033[0m\n"
        apt-get update && apt-get upgrade -y  # Fixed: was "apt get-upgrade"
}

is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

cmd_exists() {
        command -v "$1" >/dev/null 2>&1
}

pkgs=(
    vim
    git
    curl
    gcc
    make
    cmake
    # mullvad - This package doesn't exist in standard repos, remove or handle separately
    ripgrep
    python3-pip
    exuberant-ctags
    ack-grep
    build-essential
    arandr
    #chromium
    ninja-build
    gettext
    unzip
    x11-xserver-utils     # Fixed: was "x11-server-utils"
    i3
    # setxkbmap - This is part of x11-xkb-utils
    # x11-xkb-utils       # Contains setxkbmap
    xdotool               # Fixed: was "xdtool"
    ffmpeg
    pass
    gpg
    xclip
    xsel
    # install LaTeX later
    #texlive-full
)


install_packages() {
    info "Installing packages..."
    local total=${#pkgs[@]}
    local count=0
    local failed=()

    for pkg in "${pkgs[@]}"; do
        ((count++))
        progress "Checking package ($count/$total): $pkg"

        if ! is_installed "$pkg"; then
            info "Installing $pkg..."
            if apt install -y "$pkg" 2>&1; then
                success "Installed $pkg"
            else
                warning "Failed to install $pkg"
                failed+=("$pkg")
            fi
        else
            info "Package $pkg is already installed."
        fi
    done

    if ((${#failed[@]} > 0)); then
        warning "Failed to install ${#failed[@]} packages: ${failed[*]}"
        info "You may need to install these manually later"
    else
        success "All packages installed successfully"
    fi
}

install_brave() {
        info "Installing Brave browser..."

        if cmd_exists brave-browser; then
            info "Brave is already installed."
            return
        fi

        apt install -y apt-transport-https curl gnupg gnupg2 ||
            error "Failed to install Brave dependencies."

        curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg | gpg --dearmor |
            tee /usr/share/keyrings/brave-browser-archive-keyring.gpg >/dev/null ||
            error "Failed to import Brave's GPG key."

        echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" |
            tee /etc/apt/sources.list.d/brave-browser-release.list ||
            error "Failed to add Brave repository to APT sources."

        { apt update && apt install -y brave-browser; } ||
            error "Failed to update APT sources or install Brave browser."

        success "Brave browser installed successfully."
}

check_shell() {
    local current_shell
    local zsh_available=false
    local using_zsh=false

    # Check if zsh is available
    if command -v zsh >/dev/null 2>&1; then
        zsh_available=true
        info "Zsh is available on the system."
    else
        info "Zsh is not installed on the system."
    fi

    # Improved shell detection - use safer variable checking
    # Check if we're running in zsh by testing the ZSH_VERSION variable safely
    if [[ "${ZSH_VERSION+set}" == "set" ]] && [[ -n "$ZSH_VERSION" ]]; then
        # Most reliable - ZSH_VERSION is only set in zsh
        using_zsh=true
        current_shell="zsh"
        info "Currently running in Zsh shell."
    elif [[ "$0" == *"zsh"* ]] || [[ "${SHELL:-}" == *"zsh"* ]]; then
        # Secondary check - script invoked with zsh or default shell is zsh
        using_zsh=true
        current_shell="zsh"
        info "Currently running in Zsh shell."
    else
        # Check the parent shell (before sudo) if SUDO_USER is set
        if [[ -n "${SUDO_USER:-}" ]]; then
            local user_shell
            user_shell=$(getent passwd "${SUDO_USER}" | cut -d: -f7)
            if [[ "$user_shell" == *"zsh"* ]]; then
                using_zsh=true
                current_shell="zsh (user default)"
                info "User $SUDO_USER has zsh as default shell."
            else
                # Fallback to process detection
                current_shell=$(ps -p $$ -o comm= 2>/dev/null || echo "unknown")
                if [[ "$current_shell" == "zsh" ]]; then
                    using_zsh=true
                    info "Currently running in Zsh shell."
                else
                    using_zsh=false
                    info "Current shell: $current_shell (not Zsh)"
                fi
            fi
        else
            # Fallback to process detection
            current_shell=$(ps -p $$ -o comm= 2>/dev/null || echo "unknown")
            if [[ "$current_shell" == "zsh" ]]; then
                using_zsh=true
                info "Currently running in Zsh shell."
            else
                using_zsh=false
                info "Current shell: $current_shell (not Zsh)"
            fi
        fi
    fi

    # Decision logic
    if [[ "$zsh_available" == true ]] && [[ "$using_zsh" == true ]]; then
        success "Zsh is installed and is the current shell."
        return 0
    elif [[ "$zsh_available" == true ]] && [[ "$using_zsh" == false ]]; then
        warning "Zsh is installed but not the current shell."
        info "Current shell: $current_shell"
        info "Since you're running with sudo, the script will continue."
        info "Make sure zsh is your default shell for the best experience."
        return 0  # Allow script to continue when running with sudo
    else
        warning "Zsh is not installed."
        read -r -p "Do you want to build and install Zsh? (y/n): " choice
        choice=${choice:-y}

        case "${choice,,}" in # convert to lowercase
            y|yes)
                build_zsh_from_source
                ;;
            *)
                error "This script requires zsh. Exiting."
                ;;
        esac
    fi
}

build_zsh_from_source() {
        # zsh_version=5.9
        info "Building Zsh from source..."
        apt install -y build-essential ncurses-dev libncursesw5-dev yodl autoconf autotools-dev ||
                error "Failed to install required dependencies for building Zsh."

        # Create a temporary directory for building Zsh
        local build_dir
        build_dir=$(mktemp -d) ||
                error "Failed to create temporary directory for building Zsh."

        # Ensure clean up after build
        trap 'rm -rf "$build_dir"' EXIT

        # Download and extract Zsh source code
        cd "$build_dir" ||
                error "Failed to change directory to $build_dir."
        git clone https://github.com/zsh-users/zsh.git ||
                error "Failed to clone zsh repository"
        cd zsh ||
                error "Failed to change directory to zsh source code."

        # Configure and build Zsh
        ./Util/preconfig ||
                error "Preconfig failed."
        ./configure --prefix=/usr \
                --bindir=/bin \
                --sysconfdir=/etc/zsh \
                --enable-etcdir=/etc/zsh \
                --enable-function-subdirs \
                --enable-site-fndir=/usr/local/share/zsh/site-functions \
                --enable-fndir=/usr/share/zsh/functions \
                --with-tcsetpgrp ||
                error "Configure failed."

        # Compile with all available cores
        make -j "$(nproc)" ||
                error "Make failed."
        make check ||
                warning "Some tests failed, but continuing with the installation."
        make install ||
                error "Installation failed."

        # Add zsh to the list of shells
        if ! grep -q "^/bin/zsh$" /etc/shells; then
                echo "/bin/zsh" | tee -a /etc/shells ||
                        error "Failed to add zsh to /etc/shells."
        fi

        # Change the default shell to zsh for the user
        if [[ -n "${SUDO_USER:-}" ]]; then
                chsh -s /bin/zsh "$SUDO_USER" ||
                        error "Failed to change default shell to zsh for $SUDO_USER."
        else
                chsh -s /bin/zsh ||
                        error "Failed to change default shell to zsh."
        fi

        success "Zsh built and installed successfully."
        info "IMPORTANT: Zsh is now installed and set as the default shell."
        info "The script will continue with the remaining installations."
        info "For the shell change to fully take effect, you may need to log out and log back in after the script completes."

        # Don't exit - let the script continue
        return 0
}

# Installing oh-my-zsh and zsh plugins
install_zsh_extras() {
        local user
        user="${SUDO_USER:-$USER}"

        local user_home
        user_home=$(getent passwd "$user" | cut -d: -f6)

        info "Installing oh-my-zsh for $user..."
        info "User home directory: $user_home"

        # Install oh-my-zsh with proper unattended installation
        if [[ ! -d "$user_home/.oh-my-zsh" ]]; then
            info "Installing oh-my-zsh..."
            # Set environment variables for unattended installation
            export RUNZSH=no
            export CHSH=no

            if su - "$user" -c 'export RUNZSH=no; export CHSH=no; sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'; then
                success "Installed oh-my-zsh for $user"
            else
                error "Failed to install oh-my-zsh for $user"
            fi
        else
            info "oh-my-zsh for $user is already installed"
        fi

        # Install zsh-syntax-highlighting
        info "Installing zsh-syntax-highlighting..."
        local syntax_dir="$user_home/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
        if [[ ! -d "$syntax_dir" ]]; then
            if su - "$user" -c "git clone https://github.com/zsh-users/zsh-syntax-highlighting.git '$syntax_dir'"; then
                success "Installed zsh-syntax-highlighting for $user"
            else
                error "Failed to install zsh-syntax-highlighting for $user"
            fi
        else
            info "zsh-syntax-highlighting for $user is already installed"
        fi

        # Install zsh-autosuggestions
        info "Installing zsh-autosuggestions..."
        local autosuggestions_dir="$user_home/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
        if [[ ! -d "$autosuggestions_dir" ]]; then
            if su - "$user" -c "git clone https://github.com/zsh-users/zsh-autosuggestions '$autosuggestions_dir'"; then
                success "Installed zsh-autosuggestions for $user"
            else
                error "Failed to install zsh-autosuggestions for $user"
            fi
        else
            info "zsh-autosuggestions for $user is already installed"
        fi

        # Create a proper .zshrc file with oh-my-zsh configuration
        local zshrc="$user_home/.zshrc"
        info "Creating .zshrc file at: $zshrc"

        # Backup existing .zshrc if it exists
        if [[ -f "$zshrc" ]]; then
            cp "$zshrc" "$zshrc.backup.$(date +%Y%m%d_%H%M%S)" || warning "Failed to create backup of .zshrc"
        fi

        # Create a new .zshrc with proper oh-my-zsh configuration
        cat > "$zshrc" << 'EOF'
# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load
ZSH_THEME="robbyrussell"

# Which plugins would you like to load?
plugins=(git zsh-syntax-highlighting zsh-autosuggestions)

# Load oh-my-zsh
source $ZSH/oh-my-zsh.sh

# User configuration
export PATH=$PATH:/usr/local/go/bin
export PATH=$PATH:$HOME/.cargo/bin

# NVM configuration
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias vim='nvim'
alias vi='nvim'
EOF

        # Set proper ownership
        chown "$user:$(id -gn "$user")" "$zshrc" ||
            warning "Failed to set ownership for .zshrc"

        success "Created .zshrc file with proper oh-my-zsh configuration"
        info "Zsh extras installation completed successfully"
}

build_alacritty() {
        info "Building Alacritty from source..."

        # Check if Alacritty is already installed
        if cmd_exists alacritty; then
            info "Alacritty is already installed."
            return
        fi

        # Install Alacritty build dependencies first
        info "Installing Alacritty build dependencies..."
        apt install -y \
            pkg-config \
            libfontconfig1-dev \
            libfreetype6-dev \
            libxcb-xfixes0-dev \
            libxkbcommon-dev \
            python3 ||
            error "Failed to install Alacritty build dependencies."

        # First ensure Rust is installed
        install_rustup_and_compiler

        # Get user information
        local user="${SUDO_USER:-$USER}"
        local user_home
        user_home=$(getent passwd "$user" | cut -d: -f6)

        # Create a temporary directory in user's home with proper permissions
        local build_dir="$user_home/tmp_alacritty_build"

        # Remove any existing build directory
        rm -rf "$build_dir"

        # Create build directory as the user
        su - "$user" -c "mkdir -p '$build_dir'" ||
                error "Failed to create temporary directory for building Alacritty."

        # Ensure clean up after build
        trap "rm -rf '$build_dir'" EXIT

        # Clone Alacritty repository as the user
        info "Cloning Alacritty repository..."
        su - "$user" -c "cd '$build_dir' && git clone --depth=1 https://github.com/alacritty/alacritty.git" ||
                error "Failed to clone Alacritty repository."

        # Build Alacritty as the user with proper environment
        info "Building Alacritty with cargo..."
        su - "$user" -c "cd '$build_dir/alacritty' && source '$user_home/.cargo/env' && PKG_CONFIG_ALLOW_SYSTEM_LIBS=1 PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=1 cargo build --release" ||
                error "Failed to build Alacritty."

        cp "$build_dir/alacritty/target/release/alacritty" /usr/local/bin/ ||
                error "Failed to copy alacritty binary to /usr/local/bin."

        chmod +x /usr/local/bin/alacritty ||
                error "Failed to make alacritty executable."

        install_desktop_files "$build_dir"

        # Create config directory for the user
        local config_dir="$user_home/.config/alacritty"

        # Create config directory if it doesn't exist
        su - "$user" -c "mkdir -p '$config_dir'" ||
                error "Failed to create $config_dir."

        # Download configuration file as the user
        su - "$user" -c "curl -L 'https://raw.githubusercontent.com/LinuxUser255/alacritty/master/alacritty_config/alacritty.toml' -o '$config_dir/alacritty.toml'" ||
                error "Failed to download Alacritty configuration file."

        success "Alacritty built and installed successfully."
}

install_desktop_files() {
        local build_dir="$1"

        # Install terminfo files for Alacritty
        if ! infocmp alacritty &>/dev/null; then
            cd "$build_dir/alacritty" || return

            # Install terminfo entry
            tic -xe alacritty,alacritty-direct extra/alacritty.info ||
                    warning "Failed to install terminfo for Alacritty."
        fi

        # Install desktop entry
        cd "$build_dir/alacritty" || return

        # Create desktop entry
        cp extra/logo/alacritty-term.svg /usr/share/pixmaps/Alacritty.svg ||
                warning "Failed to copy Alacritty logo."

        desktop-file-install extra/linux/Alacritty.desktop ||
                warning "Failed to install desktop entry."

        update-desktop-database ||
                warning "Failed to update desktop database."

        mkdir -p /usr/local/share/man/man1
        gzip -c extra/alacritty.man > /usr/local/share/man/man1/alacritty.1.gz ||
                warning "Failed to install manual page."

        # Install shell completions for the user
        local user="${SUDO_USER:-$USER}"
        local user_home
        user_home=$(getent passwd "$user" | cut -d: -f6)

        # Bash
        mkdir -p /usr/share/bash-completion/completions
        cp extra/completions/alacritty.bash /usr/share/bash-completion/completions/alacritty ||
                warning "Failed to install Bash completion."

        # Zsh
        mkdir -p /usr/share/zsh/vendor-completions
        cp extra/completions/_alacritty /usr/share/zsh/vendor-completions/ ||
                warning "Failed to install Zsh completion."
}

build_neovim() {
        info "Building Neovim from source..."

        if cmd_exists nvim; then
            info "Neovim is already installed."
            return
        fi

        # Install build prerequisites
        info "Installing Neovim build dependencies..."
        apt install -y ninja-build gettext cmake curl build-essential ||
                error "Failed to install Neovim build dependencies."

        # Create a temporary directory for building Neovim
        local build_dir
        build_dir=$(mktemp -d) ||
                error "Failed to create temporary directory for building Neovim."

        # Ensure clean up after build
        trap 'rm -rf "$build_dir"' EXIT

        cd "$build_dir" ||
                error "Failed to change directory to $build_dir."

        git clone https://github.com/neovim/neovim.git ||
                error "Failed to clone Neovim repository."

        cd neovim ||
                error "Failed to change directory to neovim."

        git checkout stable ||
                error "Failed to checkout stable branch."

        make CMAKE_BUILD_TYPE=RelWithDebInfo ||
                error "Failed to build Neovim."

        make install ||
                error "Failed to install Neovim."

        info "Neovim built and installed successfully."
}

install_neovim_config() {
        local user="${SUDO_USER:-$USER}"
        local user_home
        user_home=$(getent passwd "$user" | cut -d: -f6)

        info "Installing Neovim configuration for $user..."

        # Create the .config directory if it doesn't exist
        su - "$user" -c "mkdir -p '$user_home/.config'" ||
            error "Failed to create .config directory"

        # Remove existing nvim config if it exists
        if [[ -d "$user_home/.config/nvim" ]]; then
            info "Backing up existing Neovim configuration..."
            su - "$user" -c "mv '$user_home/.config/nvim' '$user_home/.config/nvim.backup.$(date +%Y%m%d_%H%M%S)'" ||
                warning "Failed to backup existing Neovim configuration"
        fi

        # Clone the Neovim configuration as the user
        info "Cloning Neovim configuration repository..."
        su - "$user" -c "git clone https://github.com/LinuxUser255/nvim.git '$user_home/.config/nvim'" ||
            error "Failed to clone Neovim configuration repository"

        # Ensure proper ownership (should already be correct, but just in case)
        chown -R "$user:$(id -gn "$user")" "$user_home/.config/nvim" ||
            warning "Failed to set ownership for Neovim configuration"

        success "Neovim configuration installed successfully for $user"
        info "Configuration installed to: $user_home/.config/nvim"
}

lazy_scripts(){
        # place all the downloaded scripts in /usr/local/bin
        # print message in bold blue that says "Curling lasy scripts..."
        printf "\e[1m\e[34mCurling lazy scripts...\e[0m\n"

        curl -LO https://raw.githubusercontent.com/LinuxUser255/BashAndLinux/refs/heads/main/ShortCuts/fff
        chmod +x fff
        sudo mv fff -t /usr/local/bin/

        curl -LO https://raw.githubusercontent.com/LinuxUser255/BashAndLinux/refs/heads/main/ShortCuts/fast_grep.sh
        chmod +x fast_grep.sh
        sudo mv fast_grep.sh -t /usr/local/bin/

        curl -LO https://raw.githubusercontent.com/LinuxUser255/BashAndLinux/refs/heads/main/ShortCuts/pwsearch.sh
        chmod +x pwsearch.sh
        sudo mv pwsearch.sh -t /usr/local/bin/

        curl -LO https://raw.githubusercontent.com/LinuxUser255/BashAndLinux/refs/heads/main/ShortCuts/faster.sh
        chmod +x faster.sh
        sudo mv faster.sh -t /usr/local/bin/

        curl -LO https://raw.githubusercontent.com/LinuxUser255/BashAndLinux/refs/heads/main/ShortCuts/gclone.sh
        chmod +x gclone.sh
        sudo mv gclone.sh -t /usr/local/bin/

        # chown current user ownership of the scripts
      #  sudo chown -R "$USER":"$USER" /usr/local/bin/fff /usr/local/bin/fast_grep.sh /usr/local/bin/pwsearch.sh /usr/local/bin/faster.sh /usr/local/bin/gclone.sh
}

install_golang() {
        info "Installing Golang..."

        # Check if Go is already installed
        if cmd_exists go; then
            info "Go is already installed."
            return
        fi

        curl -fsSL https://go.dev/dl/go1.23.2.linux-amd64.tar.gz \
             | tar -C /usr/local -xzf - ||
                error "Failed to download and install Go."

        success "Go installed successfully."
        info "To use Go, add the following line to your ~/.bashrc or ~/.zshrc:"
        info "export PATH=$PATH:/usr/local/go/bin"
}

install_nodejs() {
        local user="${SUDO_USER:-$USER}"
        local user_home
        user_home=$(getent passwd "$user" | cut -d: -f6)

        info "Installing Node.js via NVM for $user..."

        # Check if Node.js is already installed
        if cmd_exists node; then
            info "Node.js is already installed."
            return
        fi

        # Check if NVM is already installed
        if [[ -f "$user_home/.nvm/nvm.sh" ]]; then
            info "NVM is already installed."
        else
            info "Installing NVM..."
            # Download and install nvm as the user
            su - "$user" -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash' ||
                error "Failed to install NVM"
            success "NVM installed successfully"
        fi

        # Install Node.js as the user
        info "Installing Node.js version 22..."
        su - "$user" -c 'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"; nvm install 22 && nvm use 22 && nvm alias default 22' ||
            error "Failed to install Node.js"

        # Verify installation
        info "Verifying Node.js installation..."
        su - "$user" -c 'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"; echo "Node.js version: $(node -v)"; echo "NPM version: $(npm -v)"; echo "Current NVM version: $(nvm current)"' ||
            warning "Failed to verify Node.js installation"

        success "Node.js installed successfully for $user"
}

install_rustup_and_compiler() {
        info "Installing Rust and Cargo..."

        # Check if Rust is already installed
        if cmd_exists rustc && cmd_exists cargo; then
            info "Rust and Cargo are already installed."
            return
        fi

        local user="${SUDO_USER:-$USER}"
        local user_home
        user_home=$(getent passwd "$user" | cut -d: -f6)

        # Install Rust using rustup as the user
        info "Installing Rust via rustup for $user..."
        su - "$user" -c 'curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y' ||
            error "Failed to install Rust"

        # Source the cargo environment
        su - "$user" -c 'source "$HOME/.cargo/env"' ||
            warning "Failed to source cargo environment"

        # Verify installation
        info "Verifying Rust installation..."
        su - "$user" -c 'source "$HOME/.cargo/env"; echo "Rust version: $(rustc --version)"; echo "Cargo version: $(cargo --version)"' ||
            warning "Failed to verify Rust installation"

        success "Rust and Cargo installed successfully for $user"
}

my_dot_files(){
        # i3 window manager config file
        local user="${SUDO_USER:-$USER}"
        local user_home
        user_home=$(getent passwd "$user" | cut -d: -f6)

        info "Setting up dotfiles for $user..."

        # Create i3 config directory
        mkdir -p "$user_home/.config/i3" ||
            error "Failed to create i3 config directory"

        # Download i3 config file
        curl -fsSL "https://raw.githubusercontent.com/LinuxUser255/ShellScripting/refs/heads/main/ConfigFiles/config" \
             -o "$user_home/.config/i3/config" ||
            error "Failed to download i3 config file"

        # Set proper ownership
        chown -R "$user:$(id -gn "$user")" "$user_home/.config/i3" ||
            warning "Failed to set ownership for i3 config"

        success "i3 config installed successfully"

        # Don't overwrite .zshrc if it already exists (from install_zsh_extras)
        if [[ ! -f "$user_home/.zshrc" ]]; then
            # Download .zshrc file to user's home directory
            curl -fsSL "https://raw.githubusercontent.com/LinuxUser255/ShellScripting/refs/heads/main/dotfiles/.zshrc" \
                 -o "$user_home/.zshrc" ||
                error "Failed to download .zshrc file"

            # Set proper ownership for .zshrc
            chown "$user:$(id -gn "$user")" "$user_home/.zshrc" ||
                warning "Failed to set ownership for .zshrc"

            success ".zshrc installed successfully"
        else
            info ".zshrc already exists, skipping download to preserve oh-my-zsh configuration"
        fi
}


main() {
    # First check if in Docker or on host
    check_docker_environment

    progress "Starting CARS installation script..."

    progress "Checking root privileges..."
    check_root
    progress "Root check completed"

    progress "Updating system..."
    update_system
    progress "System update completed"

    progress "Installing packages..."
    install_packages
    progress "Package installation completed"

    progress "Installing Brave browser..."
    install_brave
    progress "Brave installation completed"

    progress "Checking shell configuration..."
    check_shell
    progress "Shell check completed"

    # Only proceed if zsh is available
    if cmd_exists zsh; then
        progress "Zsh is available, proceeding with installations..."

        progress "Starting zsh extras installation..."
        install_zsh_extras
        progress "Zsh extras installation finished"

        progress "Starting Alacritty build..."
        build_alacritty
        progress "Alacritty build finished"

        progress "Starting Neovim build..."
        build_neovim
        progress "Neovim build finished"

        progress "Installing Neovim config..."
        install_neovim_config
        progress "Neovim config installation finished"

        progress "Installing lazy scripts..."
        lazy_scripts
        progress "Lazy scripts installation finished"

        progress "Installing Golang..."
        install_golang
        progress "Golang installation finished"

        progress "Installing Node.js..."
        install_nodejs
        progress "Node.js installation finished"

        progress "Setting up dotfiles..."
        my_dot_files
        progress "Dotfiles setup finished"

        success "All installations completed successfully!"
    else
        error "Zsh is required but not available. Please install zsh and run the script again."
    fi
}

main "$@"
