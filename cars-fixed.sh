#!/usr/bin/env bash

# Chris's Auto Rice Script - FIXED VERSION
#------------------------------
# This rice script is for Debian-based distros.

# Better error handling
set -eo pipefail  # Exit on error and pipe failures

# Add a debug function
debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo "DEBUG: $*" >&2
    fi
}

# Add progress tracking
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

# Function to print Success messages
success() {
    print_msg "$GREEN" "Success: $1" >&2
}

# Function to print informational messages
info() {
    print_msg "$BLUE" "Info: $1"
}

# Function to print warning messages
warning() {
    print_msg "$YELLOW" "Warning: $1"
}

# Check for root privileges
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        error "Please run this script as root or with sudo."
    fi
    info "Running as root - OK"
}

# Update system packages
update_system() {
    printf "\033[1;31m[+] Updating system...\033[0m\n"
    apt-get update -y && apt-get upgrade -y || error "System update failed"
}

# Function to check if a package is installed
is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# Check if command exists
cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Detect system architecture
get_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l|armhf) echo "armhf" ;;
        *) echo "$arch" ;;
    esac
}

# Check disk space (in GB)
check_disk_space() {
    local required_gb="${1:-5}"  # Default 5GB
    local available_gb
    available_gb=$(df / | awk 'NR==2 {print int($4/1048576)}')
    
    if [[ "$available_gb" -lt "$required_gb" ]]; then
        error "Insufficient disk space. Required: ${required_gb}GB, Available: ${available_gb}GB"
    fi
    info "Disk space check passed: ${available_gb}GB available"
}

# Retry function for network operations
retry_network_operation() {
    local max_attempts=3
    local delay=5
    local attempt=1
    local command="$@"
    
    while [[ $attempt -le $max_attempts ]]; do
        if eval "$command"; then
            return 0
        fi
        
        warning "Attempt $attempt failed. Retrying in ${delay} seconds..."
        sleep "$delay"
        ((attempt++))
    done
    
    return 1
}

# Packages array (FIXED package names)
pkgs=(
    vim
    git
    curl
    gcc
    make
    cmake
    ripgrep
    python3-pip
    exuberant-ctags
    ack-grep
    build-essential
    arandr
    ninja-build
    gettext
    unzip
    x11-xserver-utils    # Fixed from x11-server-utils
    i3
    x11-xkb-utils       # Contains setxkbmap
    xdotool             # Fixed from xdtool
    ffmpeg
    pass
    gpg
    xclip
    xsel
    # texlive-full  # Uncomment if needed
)

# Function to install packages
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
            if apt install -y "$pkg" >/dev/null 2>&1; then
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

# Install Brave browser with retry
install_brave() {
    info "Installing Brave browser..."
    
    if cmd_exists brave-browser; then
        info "Brave is already installed."
        return
    fi
    
    # Install Brave dependencies
    apt install -y apt-transport-https curl gnupg gnupg2 ||
        error "Failed to install Brave dependencies."
    
    # Import Brave's GPG key with retry
    retry_network_operation "curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg | gpg --dearmor | tee /usr/share/keyrings/brave-browser-archive-keyring.gpg >/dev/null" ||
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

# Install Golang (FIXED with latest version)
install_golang() {
    info "Installing Golang..."
    
    # Check if Go is already installed
    if cmd_exists go; then
        info "Go is already installed."
        return
    fi
    
    local arch
    arch=$(get_arch)
    local go_version="1.23.2"  # Updated to latest stable
    
    # Download and install Go with architecture detection
    retry_network_operation "curl -fsSL https://go.dev/dl/go${go_version}.linux-${arch}.tar.gz | tar -C /usr/local -xzf -" ||
        error "Failed to download and install Go."
    
    success "Go installed successfully."
    info "To use Go, add the following line to your ~/.bashrc or ~/.zshrc:"
    info "export PATH=\$PATH:/usr/local/go/bin"
}

# Main function
main() {
    progress "Starting CARS installation script..."
    
    # Check disk space (requires at least 10GB for all builds)
    progress "Checking disk space..."
    check_disk_space 10
    
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
    
    # Add more installation steps as needed...
    
    success "Installation completed successfully!"
}

# Cleanup on exit
trap 'echo "Script interrupted. Cleaning up..."; exit 1' INT TERM

# Call main function
main "$@"