#!/usr/bin/env bash

# Chris's Auto Rice Script
#------------------------------
# This rice script is for Debian - based distros.
# About this install:
# The unconventional features, and unique sytle.
# It is inspired by Dylan Araps Pure Bash Bible & his Neofectch shell script.
# https://github.com/LinuxUser255/pure-bash-bible
# https://github.com/dylanaraps/neofetch

# Strict mode
set -euo pipefail
IFS=$'\n\t'

# Text formatting
readonly BOLD="\e[1m"
readonly RESET="\e[0m"
readonly RED="\e[31m"
readonly GREEN="\e[32m"
readonly YELLOW="\e[33m"
readonly BLUE="\e[34m"


# Function to print colored output
print_msg() {
        local color="$1"
        local msg="$2"
        printf "${color}${BOLD}%s${RESET}\n" "$msg"
}

# Function to print error messages
error(){
        print_msg "$RED" "Error: $1" >&2
        exit 1
}

# Function to print Success messages
success(){
        print_msg "$GREEN" "Success: $1" >&2
}

# Function to print informational messages
info(){
        print_msg "$BLUE" "Info: $1"
}


# Function to print warning messages
warning(){
       print_msg "$YELLOW" "Warning: $1"
}


check_root () {
        [ "$(id -u)" -ne 0 ] && echo "Please run this script as root." && exit 1
}


update_system() {
        printf "\033[1;31m[+] Updating system...\033[0m\n"
        apt update && apt upgrade -y
}

# Function to check if a package is installed
is_installed() {
        dpkg-query -W "$1" >/dev/null 2>&1 | grep -q "installed"
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
     mulvad
     ripgrep
     python3-pip
     exuberant-ctags
     ack-grep
     build-essential
     arandr
     chromium
     ninja-build
     gettext
     unzip
     x11-server-utils
     i3
     setxkbmap
     xdtools
     ffmpeg
     pass
     gpg
     xclip
     xsel
     # install LaTeX later
     #texlive-full
 )

# Function to install packages
install_packages() {
        info "Installing packages..."
        local total=${#pkgs[@]}
        local count=0
        local failed=0

        for pkg in "${pkgs[@]}"; do
            ((count++))
            if ! is_installed "$pkg"; then
                printf "Installing (%d/%d): %s\n" "$count" "$total" "$pkg"
                if apt install -y "$pkg" &>/dev/null; then
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
        else
            success "All packages installed successfully"
        fi

}

# Install Brave browser
install_brave() {
        info "Installing Brave browser..."

        if cmd_exists brave-browser; then
            info "Brave is already installed."
            return
        fi

        # Install Brave dependencies
        apt install -y apt-transport-https curl gnupg gnupg2 ||
            error "Failed to install Brave dependencies."

        # Import Brave's GPG key
        curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg | gpg --dearmor |
            tee /usr/share/keyrings/brave-browser-archive-keyring.gpg >/dev/null ||
            error "Failed to import Brave's GPG key."

        # Add Brave repository to APT sources
        echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" |
            tee /etc/apt/sources.list.d/brave-browser-release.list ||
            error "Failed to add Brave repository to APT sources."

        # Update APT sources and install Brave
        { apt update && apt install -y brave-browser; } ||
            error "Failed to update APT sources or install Brave browser."

        success "Brave browser installed successfully."
}

# Check for zsh and if not, ask user if they want to build and install it
check_shell () {
        # Either zsh is not installed or not the current shell is not zsh
        if ! [ "$(command -v zsh)" ] || [ "$(ps -p $$ -o comm=)" != "zsh" ]; then
            warning "ZSH is either not installed or not the current shell."

            read -r -p "Do you want to build and install Zsh? (y/n): " choice
            choice=${choice:-Y}

            case "${choice,,}" in # convert to lowercase
                y|yes)
                    build_zsh_from_source
                    ;;
                *)
                    error "This script requires zsh as the current shell. Exiting."
                    ;;
        esac
    else
        success "Zsh is already installed and is the current shell."
    fi
}

# Build and install Zsh from source with error handling
build_zsh_from_source() {
        # zsh_version=5.9
        info "Building Zsh from source..."
        apt install -y build-essential ncurses-dev libncursesw5-dev yodl ||
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
        if [[ -n "$SUDO_USER" ]]; then
                chsh -s /bin/zsh "$SUDO_USER" ||
                        error "Failed to change default shell to zsh for $SUDO_USER."
        else
                chsh -s /bin/zsh ||
                        error "Failed to change default shell to zsh."
        fi

        success "Zsh built and installed successfully."
        info "IMPORTANT: You must log out and log back in for the shell change to take effect."
        info "After logging back in with Zsh, run this script again to continue the installation."

        # Exit the script to force user logout/login
        exit 0
}

# Function to install oh-my-zsh and plugins
install_zsh_extras() {
        local user
        user="${SUDO_USER:-$USER}"

        local user_home
        user_home=$(getent passwd "$user" | cut -d: -f6)

        info "Installing oh-my-zsh for $user..."

        # Install oh-my-zsh
        if [[ ! -d "$user_home/.oh-my-zsh" ]]; then
            su - "$user" -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended ||
               error "Failed to install oh-my-zsh for $user"
            success "Installed oh-my-zsh for $user"
        else
            info "oh-my-zsh for $user is already installed"
        fi

        # Install zsh-syntax-highlighting
        if [[ ! -d "$user_home/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]]; then
            su - "$user" -c "git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${user_home}/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ||
               error "Failed to install zsh-syntax-highlighting for $user"
            success "Installed zsh-syntax-highlighting for $user"
        else
            info "zsh-syntax-highlighting for $user is already installed"
        fi


        # Install autosuggestion and zsh-autosuggestions
        if [[ ! -d "$user_home/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]]; then
            su - "$user" -c "git clone https://github.com/zsh-users/zsh-autosuggestions ${user_home}/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ||
                error "Failed to install zsh-autosuggestions for $user"
            success "Installed zsh-autosuggestions for $user"
        else
            info "zsh-autosuggestions for $user is already installed"
        fi

        # Update the .zshrc to use plugins
        local zshrc="$user_home/.zshrc"
       # backup_zshrc="${zshrc}.backup"

        # use sed to update plugins line
        if [[ -f "$zshrc" ]]; then
            sed -i '/^plugins=(/s/$/ zsh-syntax-highlighting zsh-autosuggestions/' "$zshrc" ||
                warning "Failed to update plugins in $zshrc"
        fi
        success "Updated plugins in $zshrc"
}


# Install Rust and build Alacritty from source
build_alacritty() {
        info "Building Alacritty from source..."

        # Check if Alacritty is already installed
        if cmd_exists alacritty; then
            info "Alacritty is already installed."
            return
        fi

        # First ensure Rust is installed
        install_rustup_and_compiler

        # Create a temporary directory for building Alacritty
        local build_dir

        build_dir=$(mktemp -d) ||
                error "Failed to create temporary directory for building Alacritty."

        # Ensure clean up after build
        trap 'rm -rf $build_dir' EXIT

        # Clone and build Alacritty
        cd "$build_dir" ||
                error "Failed to change directory to $build_dir."

        git clone https://github.com/alacritty/alacritty.git ||
                error "Failed to clone Alacritty repository."

        cd alacritty ||
                error "Failed to change directory to Alacritty source code."

        # Build Alacritty
        cargo build --release ||
                error "Failed to build Alacritty."

        # Copy the alacritty binary to PATH
        cp target/release/alacritty /usr/local/bin/ ||
                error "Failed to copy alacritty binary to /usr/local/bin."

        # Create desktop entry and install terminfo
        install_desktop_files

        # Create config directory for the user
        local user="${SUDO_USER:-$USER}"
        local user_home
        user_home=$(getent passwd "$user" | cut -d: -f6)
        local config_dir="$user_home/.config/alacritty"

        # Create config directory if it doesn't exist
        mkdir -p "$config_dir" ||
                error "Failed to create $config_dir."

        # Download configuration file
        curl -L "https://raw.githubusercontent.com/LinuxUser255/alacritty/master/alacritty_config/alacritty.toml" \
             -o "$config_dir/alacritty.toml" ||
                error "Failed to download Alacritty configuration file."

        # Set proper ownership
        chown -R "$user:$(id -gn "$user")" "$config_dir"

        success "Alacritty built and installed successfully."
}

# Install desktop files and terminfo for Alacritty
install_desktop_files() {
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

        # Install manual page
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

# Build Neovim from source
build_neovim() {
        info "Building Neovim from source..."

        # Check if Neovim is already installed
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

        # Clone Neovim repository
        cd "$build_dir" ||
                error "Failed to change directory to $build_dir."

        git clone https://github.com/neovim/neovim.git ||
                error "Failed to clone Neovim repository."

        # Navigate to the cloned Neovim repository
        cd neovim ||
                error "Failed to change directory to neovim."

        # Checkout the stable branch
        git checkout stable ||
                error "Failed to checkout stable branch."

        # Build Neovim
        make CMAKE_BUILD_TYPE=RelWithDebInfo ||
                error "Failed to build Neovim."

        # Install Neovim
        sudo make install ||
                error "Failed to install Neovim."

        info "Neovim built and installed successfully."
}

# My Neovim configuration
install_neovim_config() {
    curl -LO https://raw.githubusercontent.com/LinuxUser255/nvim/refs/heads/main/install.sh && chmod +x install.sh && ./install.sh

}


# My lazy scripts
lazy_scripts(){
        # place all the downloaded scripts in /usr/local/bin
        # print message in bold blue that says "Curling lasy scripts..."
        printf "\e[1m\e[34mCurling lazy scripts...\e[0m\n"

        curl -L https://raw.githubusercontent.com/LinuxUser255/BashAndLinux/refs/heads/main/ShortCuts/fff -o /usr/local/bin/fff
        curl -L https://raw.githubusercontent.com/LinuxUser255/BashAndLinux/refs/heads/main/ShortCuts/fast_grep.sh -o /usr/local/bin/fast_grep.sh
        curl -LO https://raw.githubusercontent.com/LinuxUser255/BashAndLinux/refs/heads/main/ShortCuts/pwsearch.sh -o /usr/local/bin/pwsearch.sh
        curl -LO https://raw.githubusercontent.com/LinuxUser255/BashAndLinux/refs/heads/main/ShortCuts/faster.sh -o /usr/local/bin/faster.sh
        curl -LO https://raw.githubusercontent.com/LinuxUser255/BashAndLinux/refs/heads/main/ShortCuts/gclone.sh -o /usr/local/bin/gclone.sh

        # Make all scripts executable
        chmod +x /usr/local/bin/fff /usr/local/bin/fast_grep.sh /usr/local/bin/pwsearch.sh /usr/local/bin/faster.sh /usr/local/bin/gclone.sh

        # chown current user ownership of the scripts
        sudo chown -R "$USER":"$USER" /usr/local/bin/fff /usr/local/bin/fast_grep.sh /usr/local/bin/pwsearch.sh /usr/local/bin/faster.sh /usr/local/bin/gclone.sh
}

# install Golang
install_golang() {
        info "Installing Golang..."

        # Check if Go is already installed
        if cmd_exists go; then
            info "Go is already installed."
            return
        fi

        # Download and install Go
        curl -fsSL https://golang.org/dl/go1.18.linux-amd64.tar.gz \
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

        # Download .zshrc file to user's home directory
        curl -fsSL "https://raw.githubusercontent.com/LinuxUser255/ShellScripting/refs/heads/main/dotfiles/.zshrc" \
             -o "$user_home/.zshrc" ||
            error "Failed to download .zshrc file"

        # Set proper ownership for .zshrc
        chown "$user:$(id -gn "$user")" "$user_home/.zshrc" ||
            warning "Failed to set ownership for .zshrc"

        success ".zshrc installed successfully"
}


main() {

        check_root
        update_system
        install_packages
        install_brave
        check_shell

        # Only call build_zsh_from_source if zsh is not installed
        # The function exits the script, so we need to handle this differently
        if ! cmd_exists zsh; then
            build_zsh_from_source
            # This will exit the script, so code below won't run
        fi

        # Only proceed if zsh is available
        if cmd_exists zsh; then
            install_zsh_extras
        fi

        build_neovim
        install_neovim_config

        # Only call build_alacritty if install_rustup_and_compiler function exists
        if declare -f install_rustup_and_compiler >/dev/null; then
            build_alacritty
        else
            warning "Skipping Alacritty build - install_rustup_and_compiler function not found"
        fi

        lazy_scripts
        install_golang
        install_nodejs
        my_dot_files
}

main

