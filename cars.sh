#!/usr/bin/env bash

# Remove 'set -e' to allow script to continue on errors
# Keep other safety settings
set -uo pipefail
IFS=$'\n\t'

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

error(){
        print_msg "$RED" "Error: $1" >&2
        # Don't exit, just log the error
        return 1
}

fatal_error(){
        print_msg "$RED" "Fatal Error: $1" >&2
        exit 1
}

success(){
        print_msg "$GREEN" "Success: $1"
}

info(){
        print_msg "$BLUE" "Info: $1"
}

warning(){
        print_msg "$YELLOW" "Warning: $1"
}

check_root () {
        [ "$(id -u)" -ne 0 ] && { echo "Please run this script as root."; exit 1; }
}

is_installed() {
        dpkg -s "$1" >/dev/null 2>&1
}

cmd_exists() {
        command -v "$1" >/dev/null 2>&1
}

update_system() {
        printf "\033[1;31m[+] Updating system...\033[0m\n"
        apt-get update && apt-get upgrade -y
}

pkgs=(
     vim
     git
     curl
     gcc
     make
     ripgrep
     python3-pip
     universal-ctags
     ack  # Changed from ack-grep
     build-essential
     arandr
     chromium
     ninja-build
     gettext
     unzip
     x11-xserver-utils  # This includes setxkbmap
     xdotool
     ffmpeg
     pass
     gpg
     xclip
     xsel
     desktop-file-utils
     pkg-config
     cmake
     libfontconfig1-dev
     libfreetype-dev  # Changed from libfreetype6-dev
     libxcb-xfixes0-dev
     libxkbcommon-dev
     libxcb1-dev
     libxcb-render0-dev
     libxcb-shape0-dev
)

install_packages() {
        info "Installing packages..."
        local -a to_install=()
        local -a failed_packages=()
        
        for pkg in "${pkgs[@]}"; do
                is_installed "$pkg" && { info "Package $pkg is already installed."; continue; } || to_install+=("$pkg")
        done
        
        ((${#to_install[@]}==0)) && { success "All packages already installed"; return 0; }
        
        # Try batch installation first
        if ! apt-get install -y "${to_install[@]}" 2>/dev/null; then
                warning "Batch installation failed, trying individual packages..."
                
                # Install packages one by one
                for pkg in "${to_install[@]}"; do
                        info "Attempting to install: $pkg"
                        if apt-get install -y "$pkg" 2>/dev/null; then
                                success "Installed: $pkg"
                        else
                                warning "Failed to install: $pkg (package might not exist or have a different name)"
                                failed_packages+=("$pkg")
                        fi
                done
        else
                success "Batch installation completed successfully"
        fi
        
        # Handle critical tools that failed
        for pkg in "${failed_packages[@]}"; do
                case "$pkg" in
                        ripgrep)
                                info "ripgrep not found in repos, will build from source later"
                                ;;
                esac
        done
        
        # Report results
        if ((${#failed_packages[@]} > 0)); then
                warning "The following packages could not be installed: ${failed_packages[*]}"
                warning "The script will continue with available packages."
        else
                success "All requested packages installed successfully!"
        fi
        
        return 0  # Always return success to continue script
}

check_shell () {
        local user
        user="${SUDO_USER:-$USER}"
        local shell_path
        shell_path=$(getent passwd "$user" | cut -d: -f7 || true)
        local shell_name
        shell_name="${shell_path##*/}"
        cmd_exists zsh || { warning "Zsh is not installed yet."; return 0; }
        local action
        case "$shell_name" in
                zsh)
                        : "KEEP"
                ;;
                bash|sh|dash|ash|fish|tcsh|ksh|zsh*)
                        : "CHSH"
                ;;
                *)
                        : "CHSH"
                ;;
        esac
        action="$_"
        case "$action" in
                KEEP)
                        info "Zsh is already the default shell for $user."
                        return 0
                ;;
                CHSH)
                        info "Setting default shell to zsh for $user..."
                        chsh -s /bin/zsh "$user" && success "Default shell changed to zsh for $user" || warning "Failed to change default shell for $user"
                        info "You may need to log out and back in for the default shell change to take effect."
                ;;
        esac
}

build_ripgrep() {
        info "Building ripgrep from source..."
        cmd_exists rg && { info "ripgrep is already installed."; return 0; }
        
        # Ensure Rust is installed
        if ! cmd_exists cargo; then
                info "Installing Rust toolchain for ripgrep build..."
                curl https://sh.rustup.rs -sSf | sh -s -- -y || { warning "Failed to install Rust"; return 1; }
                export PATH="$HOME/.cargo/bin:$PATH"
                source "$HOME/.cargo/env" 2>/dev/null || true
        fi
        
        local build_dir
        build_dir=$(mktemp -d) || { warning "Failed to create temp dir for ripgrep"; return 1; }
        trap 'rm -rf "$build_dir"' EXIT
        
        cd "$build_dir" || { warning "cd failed"; return 1; }
        
        # Method 1: Try downloading pre-built binary first
        info "Attempting to download pre-built ripgrep binary..."
        local rg_version="14.1.0"
        local rg_archive="ripgrep-${rg_version}-x86_64-unknown-linux-musl.tar.gz"
        
        if curl -LO "https://github.com/BurntSushi/ripgrep/releases/download/${rg_version}/${rg_archive}" 2>/dev/null; then
                tar xzf "${rg_archive}" && \
                cp "ripgrep-${rg_version}-x86_64-unknown-linux-musl/rg" /usr/local/bin/ && \
                chmod +x /usr/local/bin/rg && \
                success "ripgrep installed from pre-built binary" && \
                return 0
        fi
        
        # Method 2: Build from source
        warning "Pre-built binary download failed, building from source..."
        git clone https://github.com/BurntSushi/ripgrep.git || { warning "clone failed"; return 1; }
        cd ripgrep || { warning "cd ripgrep failed"; return 1; }
        
        # Build with release optimizations
        cargo build --release || { warning "cargo build failed"; return 1; }
        
        # Install the binary
        cp target/release/rg /usr/local/bin/ || { warning "Failed to copy rg binary"; return 1; }
        chmod +x /usr/local/bin/rg
        
        # Install man page if possible
        if [[ -f target/release/build/ripgrep-*/out/rg.1 ]]; then
                mkdir -p /usr/local/share/man/man1
                cp target/release/build/ripgrep-*/out/rg.1 /usr/local/share/man/man1/ 2>/dev/null || true
        fi
        
        success "ripgrep built and installed successfully"
        return 0
}

build_zsh_from_source() {
        cmd_exists zsh && { info "Zsh already installed."; return 0; }
        info "Building Zsh from source..."
        apt-get install -y build-essential ncurses-dev libncursesw5-dev yodl || { warning "Failed to install Zsh build deps, skipping zsh build."; return 1; }
        local build_dir
        build_dir=$(mktemp -d) || { warning "Failed to create temporary directory for zsh build."; return 1; }
        trap 'rm -rf "$build_dir"' EXIT
        cd "$build_dir" || { warning "cd failed"; return 1; }
        git clone https://github.com/zsh-users/zsh.git || { warning "clone failed"; return 1; }
        cd zsh || { warning "cd zsh failed"; return 1; }
        ./Util/preconfig || { warning "preconfig failed"; return 1; }
        ./configure --prefix=/usr \
                --bindir=/bin \
                --sysconfdir=/etc/zsh \
                --enable-etcdir=/etc/zsh \
                --enable-function-subdirs \
                --enable-site-fndir=/usr/local/share/zsh/site-functions \
                --enable-fndir=/usr/share/zsh/functions \
                --with-tcsetpgrp || { warning "configure failed"; return 1; }
        make -j "$(nproc)" || { warning "make failed"; return 1; }
        make check || warning "some tests failed"
        make install || { warning "install failed"; return 1; }
        rg -F -x -q "/bin/zsh" /etc/shells || echo "/bin/zsh" | tee -a /etc/shells >/dev/null || warning "add to /etc/shells failed"
        if [[ -n "$SUDO_USER" ]]; then
                chsh -s /bin/zsh "$SUDO_USER" || warning "chsh failed for $SUDO_USER"
        else
                chsh -s /bin/zsh || warning "chsh failed"
        fi
        success "Zsh built and installed"
        info "Log out and back in to use zsh as default."
}

install_zsh_extras() {
        local user
        user="${SUDO_USER:-$USER}"
        local user_home
        user_home=$(getent passwd "$user" | cut -d: -f6)
        info "Installing oh-my-zsh for $user..."

        local act_omz
        case $([[ -d "$user_home/.oh-my-zsh" ]] && echo present || echo missing) in
                present) : "KEEP" ;;
                *)       : "INSTALL" ;;
        esac
        act_omz="$_"
        [[ "$act_omz" == INSTALL ]] && su - "$user" -c "git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh" && success "Installed oh-my-zsh for $user" || info "oh-my-zsh already installed"

        [[ -f "$user_home/.zshrc" ]] || su - "$user" -c "cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc" || warning "create .zshrc failed"

        local -a pids=()
        local act_syn
        case $([[ -d "$user_home/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]] && echo present || echo missing) in
                present) : "KEEP" ;;
                *)       : "INSTALL" ;;
        esac
        act_syn="$_"
        [[ "$act_syn" == INSTALL ]] && { su - "$user" -c "git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" & pids+=($!); } || info "zsh-syntax-highlighting already installed"

        local act_sug
        case $([[ -d "$user_home/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]] && echo present || echo missing) in
                present) : "KEEP" ;;
                *)       : "INSTALL" ;;
        esac
        act_sug="$_"
        [[ "$act_sug" == INSTALL ]] && { su - "$user" -c "git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions" & pids+=($!); } || info "zsh-autosuggestions already installed"

        ((${#pids[@]})) && wait "${pids[@]}"

        local zshrc="$user_home/.zshrc"
        [[ -f "$zshrc" ]] && {
                rg -q '^plugins=(' "$zshrc" || echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> "$zshrc"
                rg -F -q 'zsh-autosuggestions' "$zshrc" || sed -i 's/^plugins=(/plugins=(zsh-autosuggestions /' "$zshrc"
                rg -F -q 'zsh-syntax-highlighting' "$zshrc" || sed -i 's/^plugins=(/plugins=(zsh-syntax-highlighting /' "$zshrc"
                sed -i -E 's/^plugins=\((.*)zsh-syntax-highlighting(.*)\)/plugins=(\1\2 zsh-syntax-highlighting)/' "$zshrc" || true
        }
        chown "$user:$(id -gn "$user")" "$zshrc" 2>/dev/null || true
        success "Updated plugins in $zshrc"
}

build_alacritty() {
        info "Building Alacritty from source..."
        cmd_exists alacritty && { info "Alacritty is already installed."; return 0; }
        cmd_exists cargo || curl https://sh.rustup.rs -sSf | sh -s -- -y
        export PATH="$HOME/.cargo/bin:$PATH"
        local build_dir
        build_dir=$(mktemp -d) || { warning "Failed to create temporary directory for Alacritty"; return 1; }
        trap 'rm -rf "$build_dir"' EXIT
        cd "$build_dir" || { warning "cd failed"; return 1; }
        git clone https://github.com/alacritty/alacritty.git || { warning "clone failed"; return 1; }
        cd alacritty || { warning "cd alacritty failed"; return 1; }
        git fetch --tags || warning "fetch tags failed"
        local latest_tag
        latest_tag=$(git tag -l 'v*' | sort -V | tail -n1 || true)
        [ -n "$latest_tag" ] && git checkout "$latest_tag" || info "No version tag found; building default branch"
        cargo build --release || { warning "cargo build failed"; return 1; }
        cp target/release/alacritty /usr/local/bin/ || { warning "copy binary failed"; return 1; }
        install_desktop_files "$PWD"
        local user="${SUDO_USER:-$USER}"
        local user_home
        user_home=$(getent passwd "$user" | cut -d: -f6)
        local config_dir="$user_home/.config/alacritty"
        mkdir -p "$config_dir" || warning "mkdir config failed"
        curl -L "https://raw.githubusercontent.com/LinuxUser255/alacritty/master/alacritty_config/alacritty.toml" -o "$config_dir/alacritty.toml" || warning "download config failed"
        chown -R "$user:$(id -gn "$user")" "$config_dir"
        success "Alacritty built and installed"
}

install_desktop_files() {
        local alacritty_dir="$1"
        [[ -d "$alacritty_dir" ]] || return 0
        infocmp alacritty &>/dev/null || {
                cd "$alacritty_dir" || return 0
                tic -xe alacritty,alacritty-direct extra/alacritty.info || warning "terminfo install failed"
        }
        cd "$alacritty_dir" || return 0
        cp extra/logo/alacritty-term.svg /usr/share/pixmaps/Alacritty.svg || warning "logo copy failed"
        desktop-file-install extra/linux/Alacritty.desktop || warning "desktop entry failed"
        update-desktop-database || warning "desktop db update failed"
        mkdir -p /usr/local/share/man/man1
        gzip -c extra/alacritty.man > /usr/local/share/man/man1/alacritty.1.gz || warning "man install failed"
        mkdir -p /usr/share/bash-completion/completions /usr/share/zsh/vendor-completions
        cp extra/completions/alacritty.bash /usr/share/bash-completion/completions/alacritty || warning "bash completion failed"
        cp extra/completions/_alacritty /usr/share/zsh/vendor-completions/ || warning "zsh completion failed"
}

build_neovim() {
        info "Building Neovim from source..."
        cmd_exists nvim && { info "Neovim is already installed."; return 0; }
        apt-get install -y ninja-build gettext cmake curl build-essential || { warning "nvim deps failed"; return 1; }
        local build_dir
        build_dir=$(mktemp -d) || { warning "mktemp failed"; return 1; }
        trap 'rm -rf "$build_dir"' EXIT
        cd "$build_dir" || { warning "cd failed"; return 1; }
        git clone https://github.com/neovim/neovim.git || { warning "clone failed"; return 1; }
        cd neovim || { warning "cd failed"; return 1; }
        git checkout stable || { warning "checkout failed"; return 1; }
        make -j"$(nproc)" CMAKE_BUILD_TYPE=RelWithDebInfo || { warning "make failed"; return 1; }
        make install || { warning "install failed"; return 1; }
        info "Neovim built and installed successfully."
}

install_brave() {
        info "Installing Brave browser..."
        cmd_exists brave-browser && { info "Brave is already installed."; return 0; }
        apt-get install -y apt-transport-https curl gnupg gnupg2 || { warning "deps failed"; return 1; }
        curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg | gpg --dearmor | tee /usr/share/keyrings/brave-browser-archive-keyring.gpg >/dev/null || { warning "key import failed"; return 1; }
        echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null || { warning "apt source failed"; return 1; }
        apt-get update && apt-get install -y brave-browser || { warning "install failed"; return 1; }
        success "Brave browser installed successfully."
}

fastfetch_build(){
        info "Building fastfetch from source..."
        cmd_exists fastfetch && { info "fastfetch is already installed."; return 0; }
        local build_dir
        build_dir=$(mktemp -d) || { warning "mktemp failed"; return 1; }
        trap 'rm -rf "$build_dir"' EXIT
        cd "$build_dir" || { warning "cd failed"; return 1; }
        git clone --depth=1 https://github.com/fastfetch-cli/fastfetch.git || { warning "clone failed"; return 1; }
        cd fastfetch || { warning "cd failed"; return 1; }
        mkdir -p build && cd build || { warning "build dir failed"; return 1; }
        cmake .. || { warning "cmake configure failed"; return 1; }
        cmake --build . -j"$(nproc)" || { warning "cmake build failed"; return 1; }
        cmake --install . || { warning "cmake install failed"; return 1; }
        success "fastfetch built and installed successfully."
}

lazy_scripts(){
        printf "\e[1m\e[34mCurling lazy scripts...\e[0m\n"
        local -a pids=()
        curl -fsSL -o /usr/local/bin/fff https://raw.githubusercontent.com/LinuxUser255/BashAndLinux/refs/heads/main/ShortCuts/fff & pids+=($!)
        curl -fsSL -o /usr/local/bin/fast_grep.sh https://raw.githubusercontent.com/LinuxUser255/BashAndLinux/refs/heads/main/ShortCuts/fast_grep.sh & pids+=($!)
        curl -fsSL -o /usr/local/bin/pwsearch.sh https://raw.githubusercontent.com/LinuxUser255/BashAndLinux/refs/heads/main/ShortCuts/pwsearch.sh & pids+=($!)
        curl -fsSL -o /usr/local/bin/faster.sh https://raw.githubusercontent.com/LinuxUser255/BashAndLinux/refs/heads/main/ShortCuts/faster.sh & pids+=($!)
        curl -fsSL -o /usr/local/bin/gclone.sh https://raw.githubusercontent.com/LinuxUser255/BashAndLinux/refs/heads/main/ShortCuts/gclone.sh & pids+=($!)
        # curl down my .zshrc
        ((${#pids[@]})) && wait "${pids[@]}"
        chmod +x /usr/local/bin/fff /usr/local/bin/fast_grep.sh /usr/local/bin/pwsearch.sh /usr/local/bin/faster.sh /usr/local/bin/gclone.sh
        chown -R "${SUDO_USER:-$USER}:$(id -gn "${SUDO_USER:-$USER}")" /usr/local/bin/fff /usr/local/bin/fast_grep.sh /usr/local/bin/pwsearch.sh /usr/local/bin/faster.sh /usr/local/bin/gclone.sh || true
}

# Track installation results
declare -a SUCCESSES=()
declare -a FAILURES=()

track_result() {
        local task="$1"
        local result="$2"
        if [[ $result -eq 0 ]]; then
                SUCCESSES+=("$task")
        else
                FAILURES+=("$task")
        fi
}

print_summary() {
        echo ""
        print_msg "$BLUE" "========== INSTALLATION SUMMARY =========="
        
        if ((${#SUCCESSES[@]} > 0)); then
                print_msg "$GREEN" "✓ Successfully completed:"
                for task in "${SUCCESSES[@]}"; do
                        echo "  - $task"
                done
        fi
        
        if ((${#FAILURES[@]} > 0)); then
                echo ""
                print_msg "$YELLOW" "⚠ Failed or skipped:"
                for task in "${FAILURES[@]}"; do
                        echo "  - $task"
                done
        fi
        
        echo ""
        if ((${#FAILURES[@]} == 0)); then
                print_msg "$GREEN" "All tasks completed successfully!"
        else
                print_msg "$YELLOW" "Script completed with some warnings. Please review the failed items above."
        fi
        echo ""
}

main() {
        check_root
        
        update_system
        track_result "System update" $?
        
        install_packages
        track_result "Package installation" $?
        
        # Build ripgrep if it's not available
        if ! cmd_exists rg && ! cmd_exists ripgrep; then
                build_ripgrep
                track_result "ripgrep build" $?
        fi
        
        check_shell
        track_result "Shell check" $?
        
        build_zsh_from_source
        track_result "Zsh build" $?
        
        install_zsh_extras
        track_result "Zsh extras" $?
        
        build_alacritty
        track_result "Alacritty build" $?
        
        build_neovim
        track_result "Neovim build" $?
        
        install_brave
        track_result "Brave browser" $?
        
        fastfetch_build
        track_result "Fastfetch build" $?
        
        lazy_scripts
        track_result "Lazy scripts" $?
        
        print_summary
}

main
