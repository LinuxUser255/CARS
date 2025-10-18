#!/usr/bin/env bash

set -euo pipefail
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
        [ "$(id -u)" -ne 0 ] && echo "Please run this script as root." && exit 1
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
     ack-grep
     build-essential
     arandr
     chromium
     ninja-build
     gettext
     unzip
     x11-xserver-utils
     setxkbmap
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
     libfreetype6-dev
     libxcb-xfixes0-dev
     libxkbcommon-dev
     libxcb1-dev
     libxcb-render0-dev
     libxcb-shape0-dev
)

install_packages() {
        info "Installing packages..."
        local -a to_install=()
        for pkg in "${pkgs[@]}"; do
                is_installed "$pkg" && { info "Package $pkg is already installed."; continue; } || to_install+=("$pkg")
        done
        ((${#to_install[@]}==0)) && { success "All packages already installed"; return 0; }
        apt-get install -y "${to_install[@]}" && success "Installed: ${to_install[*]}" || error "Failed to install: ${to_install[*]}"
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

build_zsh_from_source() {
        cmd_exists zsh && { info "Zsh already installed."; return 0; }
        info "Building Zsh from source..."
        apt-get install -y build-essential ncurses-dev libncursesw5-dev yodl || error "Failed to install Zsh build deps."
        local build_dir
        build_dir=$(mktemp -d) || error "Failed to create temporary directory."
        trap 'rm -rf "$build_dir"' EXIT
        cd "$build_dir" || error "cd failed"
        git clone https://github.com/zsh-users/zsh.git || error "clone failed"
        cd zsh || error "cd zsh failed"
        ./Util/preconfig || error "preconfig failed"
        ./configure --prefix=/usr \
                --bindir=/bin \
                --sysconfdir=/etc/zsh \
                --enable-etcdir=/etc/zsh \
                --enable-function-subdirs \
                --enable-site-fndir=/usr/local/share/zsh/site-functions \
                --enable-fndir=/usr/share/zsh/functions \
                --with-tcsetpgrp || error "configure failed"
        make -j "$(nproc)" || error "make failed"
        make check || warning "some tests failed"
        make install || error "install failed"
        rg -F -x -q "/bin/zsh" /etc/shells || echo "/bin/zsh" | tee -a /etc/shells >/dev/null || error "add to /etc/shells failed"
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
                rg -q '^plugins=\(' "$zshrc" || echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> "$zshrc"
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
        build_dir=$(mktemp -d) || error "Failed to create temporary directory"
        trap 'rm -rf "$build_dir"' EXIT
        cd "$build_dir" || error "cd failed"
        git clone https://github.com/alacritty/alacritty.git || error "clone failed"
        cd alacritty || error "cd alacritty failed"
        git fetch --tags || error "fetch tags failed"
        local latest_tag
        latest_tag=$(git tag -l 'v*' | sort -V | tail -n1 || true)
        [ -n "$latest_tag" ] && git checkout "$latest_tag" || info "No version tag found; building default branch"
        cargo build --release || error "cargo build failed"
        cp target/release/alacritty /usr/local/bin/ || error "copy binary failed"
        install_desktop_files "$PWD"
        local user="${SUDO_USER:-$USER}"
        local user_home
        user_home=$(getent passwd "$user" | cut -d: -f6)
        local config_dir="$user_home/.config/alacritty"
        mkdir -p "$config_dir" || error "mkdir config failed"
        curl -L "https://raw.githubusercontent.com/LinuxUser255/alacritty/master/alacritty_config/alacritty.toml" -o "$config_dir/alacritty.toml" || error "download config failed"
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
        apt-get install -y ninja-build gettext cmake curl build-essential || error "nvim deps failed"
        local build_dir
        build_dir=$(mktemp -d) || error "mktemp failed"
        trap 'rm -rf "$build_dir"' EXIT
        cd "$build_dir" || error "cd failed"
        git clone https://github.com/neovim/neovim.git || error "clone failed"
        cd neovim || error "cd failed"
        git checkout stable || error "checkout failed"
        make -j"$(nproc)" CMAKE_BUILD_TYPE=RelWithDebInfo || error "make failed"
        make install || error "install failed"
        info "Neovim built and installed successfully."
}

install_brave() {
        info "Installing Brave browser..."
        cmd_exists brave-browser && { info "Brave is already installed."; return 0; }
        apt-get install -y apt-transport-https curl gnupg gnupg2 || error "deps failed"
        curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg | gpg --dearmor | tee /usr/share/keyrings/brave-browser-archive-keyring.gpg >/dev/null || error "key import failed"
        echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null || error "apt source failed"
        apt-get update && apt-get install -y brave-browser || error "install failed"
        success "Brave browser installed successfully."
}

fastfetch_build(){
        info "Building fastfetch from source..."
        cmd_exists fastfetch && { info "fastfetch is already installed."; return 0; }
        local build_dir
        build_dir=$(mktemp -d) || error "mktemp failed"
        trap 'rm -rf "$build_dir"' EXIT
        cd "$build_dir" || error "cd failed"
        git clone --depth=1 https://github.com/fastfetch-cli/fastfetch.git || error "clone failed"
        cd fastfetch || error "cd failed"
        mkdir -p build && cd build || error "build dir failed"
        cmake .. || error "cmake configure failed"
        cmake --build . -j"$(nproc)" || error "cmake build failed"
        cmake --install . || error "cmake install failed"
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
        ((${#pids[@]})) && wait "${pids[@]}"
        chmod +x /usr/local/bin/fff /usr/local/bin/fast_grep.sh /usr/local/bin/pwsearch.sh /usr/local/bin/faster.sh /usr/local/bin/gclone.sh
        chown -R "${SUDO_USER:-$USER}:$(id -gn "${SUDO_USER:-$USER}")" /usr/local/bin/fff /usr/local/bin/fast_grep.sh /usr/local/bin/pwsearch.sh /usr/local/bin/faster.sh /usr/local/bin/gclone.sh || true
}

main() {
        check_root
        update_system
        install_packages
        check_shell
        build_zsh_from_source
        install_zsh_extras
        build_alacritty
        build_neovim
        install_brave
        fastfetch_build
        lazy_scripts
}

main
