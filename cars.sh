#!/usr/bin/env bash

# Chris's Auto Rice Script
#------------------------------
# About this install: The unconventional features, and unique sytle.
# It is inspired by Dylan Araps Pure Bash Bible & his Neofectch shell script.
# https://github.com/LinuxUser255/pure-bash-bible
# https://github.com/dylanaraps/neofetch

# Examples of theses are found in the section called "Code Golf",
# Found on the README.md in the "Pure Bash Bible" repository.
# For example, Short if Syntax, AKA One-liner conditionals.
# "Short-circuit logical expression", "Implicit if logical operators", etc..
# These use "Compound conditionals that use the aformentioned logical operators (&&, ||) in POSIX shell style."
# these operators control execution flow, They look like "if [ condition ]; then...; fi",
# Other styles used are
# Concise for loop syntax. Specifically, C Style for loop syntax.
# Concise Function Declarations.
# Simpler Case Statements to set a variable
# Arrary functions and Arrary Cycling

check_root () {
        [ "$(id -u)" -ne 0 ] && echo "Please run this script as root." && exit 1
}


update_system() {
    printf "\033[1;31m[+] Updating system...\033[0m\n"
    apt update && apt upgrade -y
}

pkgs=(
     vim
     git
     curl
     gcc
     make
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
     setxkbmap
     xdtools
     ffmpeg
     pass
     gpg
     xclip
     xsel
     texlive-full
 )

 # Using C style syntax loop to iterate over array..harder to read, but looks cool.
 install_packages() {
     printf "\033[1;31m[+] Installing packages...\033[0m\n"
     apt install -y "${pkgs[$i:=0}]}"
     ((i=i>=${#pkgs[@]}-1?0:++i))

}

# Cool One-liner If you want to check the shell and nothing more.
#check_shell () {
#        [ "$(command -v zsh)" ] && [ "$(ps -p $$ -o comm=)" = "zsh" ] || { echo "Zsh is either not installed or not your current shell."; exit 1; }
#
#}

# Check for zsh and if not, ask user if they want to build and install it
check_shell () {
        if ! [ "$(command -v zsh)" ] || [ "$(ps -p $$ -o comm=)" != "zsh" ]; then
                printf "\033[1;33m[!] Zsh is either not installed or not your current shell.\033[0m\n"
                read -r -p "It is itegral to this customization.Would you like to build and install zsh from source? (y/n): " choice
                case "$choice" in
                        y|Y )
                                # Runs the build_zsh_from_source function
                                build_zsh_from_source
                                printf "\033[1;33m[!] Please restart the script after logging out and back in.\033[0m\n"
                                exit 0
                                ;;
                        * )
                                printf "\033[1;31m[!] This script requires zsh as the current shell. Exiting.\033[0m\n"
                                exit 1
                                ;;
                esac
        fi
}


# correctly build zsh from source and make it default shell
build_zsh_from_source(){
        printf "\033[1;31m[+] Building Zsh from source...\033[0m\n"
        apt install -y git build-essential ncurses-dev libncursesw5-dev yodl
        git clone https://github.com/zsh-users/zsh.git
        cd zsh || { printf "\033[1;31mError: Failed to clone zsh repository.\033[0m\n"; exit 1; }

        # Configure and build zsh
        ./Util/preconfig
        ./configure --prefix=/usr \
                    --bindir=/bin \
                    --sysconfdir=/etc/zsh \
                    --enable-etcdir=/etc/zsh \
                    --enable-function-subdirs \
                    --enable-site-fndir=/usr/local/share/zsh/site-functions \
                    --enable-fndir=/usr/share/zsh/functions \
                    --with-tcsetpgrp

        # Compile and install
        make -j"$(nproc)"
        make check
        sudo make install

        # Add zsh to /etc/shells if not already there
        grep -q "^/bin/zsh$" /etc/shells || echo "/bin/zsh" | sudo tee -a /etc/shells

        # Make zsh the default shell for the current user
        printf "\033[1;32m[+] Changing default shell to zsh...\033[0m\n"
        sudo chsh -s /bin/zsh $SUDO_USER

        # Return to previous directory
        cd ..

        printf "\033[1;32m[+] Zsh has been built and installed successfully!\033[0m\n"
        printf "\033[1;33m[!] Please log out and log back in for the shell change to take effect.\033[0m\n"
}

# TOD: ADD THESE LATER

#other_tools(){
#- Brave browser, &  yt-dlp
# sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
# sudo chmod a+rx  /usr/local/bin/yt-dlp

#}


#FASTFETCH - build from souce
#   fastfetch_build(){
#
#   }

# Alacritty Terminal, build from source
# build_alacritty(){

# }

#zsh_customize(){
        # ZSH Extras
        # oh-my-zsh
        # https://ohmyz.sh/
        # zsh syntax color
        # https://github.com/zsh-users/zsh-syntax-highlighting
        #
        #- my dot files: .zsh
        #- Alacritty Terminal
        #- Neovim -- build from source
        #- My Neovim config
        #
# }



main() {
    check_root
    check_shell
    update_system
    install_packages  # Add your package installation logic here if needed
    build_zsh_from_source
}

main


