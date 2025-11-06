# CARS - Chris's Auto Rice Script

> **Automated Debian Linux Development Environment Setup**

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Debian](https://img.shields.io/badge/Debian-12%2B-red.svg)](https://www.debian.org/)
[![Shell Script](https://img.shields.io/badge/Shell-Bash-green.svg)](https://www.gnu.org/software/bash/)

CARS is a comprehensive shell script that automates the installation and configuration of a complete development environment on Debian-based Linux systems. It transforms a fresh Debian installation into a fully-equipped development workstation with a single command.

## Features

### Shell Environment
- **Zsh** - Built from source with latest features
- **Oh-My-Zsh** - Pre-configured with essential plugins
- **Zsh Plugins**:
  - [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) - Command syntax highlighting
  - [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) - Intelligent command suggestions

### Terminal & Editor
- **[Alacritty](https://github.com/alacritty/alacritty)** - GPU-accelerated terminal emulator (built from source)
- **[Neovim](https://neovim.io/)** - Hyperextensible text editor (built from source)
- **Custom Neovim Configuration** - Pre-configured with plugins and settings

### Web Browsers
- **Brave Browser** - Privacy-focused Chromium-based browser
- **Complete ad-blocking and privacy settings**

### Development Tools

#### Programming Languages
- **Rust** - Systems programming language with Cargo
- **Go 1.23.2** - Latest stable version
- **Node.js v22** - Via NVM for version management
- **Python 3** - With pip and essential packages

#### Essential Packages
- `vim`, `git`, `curl`, `gcc`, `make`, `cmake`
- `ripgrep` - Lightning-fast grep alternative
- `build-essential` - Compilation tools
- `python3-pip`, `exuberant-ctags`, `ack-grep`
- `ninja-build`, `gettext`, `unzip`

### Desktop Environment
- **i3 Window Manager** - Tiling window manager configuration
- **X11 Utilities** - Display management tools
- `arandr` - GUI for xrandr
- `xdotool` - X11 automation tool

### System Utilities
- **Password Management**: `pass`, `gpg`
- **Clipboard Tools**: `xclip`, `xsel`
- **Media Tools**: `ffmpeg`
- **Custom Shell Scripts**:
  - Fast file search utilities
  - Git helpers
  - System shortcuts

## Quick Start

### Prerequisites
- Fresh Debian 12 (Bookworm) or compatible distribution
- Root/sudo access
- Internet connection
- At least 10GB free disk space

### Installation

#### Option 1: Direct Installation (Production)
```bash
# Clone the repository
git clone https://github.com/LinuxUser255/CARS.git
cd CARS

# Run the script
sudo bash cars.sh
```

#### Option 2: Docker Testing (Recommended for first-time users)
```bash
# Clone the repository
git clone https://github.com/LinuxUser255/CARS.git
cd CARS

# Use the interactive safe runner
./safe-run.sh

# Or use make commands
make test-quick  # Quick syntax tests
make run-script  # Full installation in Docker
make shell       # Enter container for debugging
```

## Docker Testing Environment

CARS includes a complete Docker testing infrastructure to ensure safe testing before deployment:

```bash
# Quick test
make test-quick

# Full installation test
make run-script

# Interactive shell
make shell

# Cleanup
make clean
```

See [DOCKER_TESTING.md](DOCKER_TESTING.md) for detailed testing documentation.

## What Gets Installed

### Core Components
| Component | Version | Build Method |
|-----------|---------|-------------|
| Zsh | Latest | Source |
| Neovim | Stable | Source |
| Alacritty | Latest | Source |
| Rust | Latest | Rustup |
| Go | 1.23.2 | Binary |
| Node.js | v22 | NVM |

### Configuration Files
- `.zshrc` - Optimized Zsh configuration
- `.config/nvim/` - Complete Neovim setup
- `.config/alacritty/` - Alacritty configuration
- `.config/i3/` - i3 window manager config

## Safety Features

- **Docker Environment Detection** - Warns if running on host system
- **Confirmation Prompts** - Requires explicit confirmation for host execution
- **Error Handling** - Comprehensive error checking and recovery
- **Backup Creation** - Automatically backs up existing configurations
- **Non-destructive** - Preserves existing installations when possible

## Project Structure

```
CARS/
├── cars.sh              # Main installation script
├── Dockerfile           # Docker container definition
├── docker-compose.yml   # Docker orchestration
├── Makefile            # Convenient commands
├── safe-run.sh         # Interactive Docker menu
├── test-runner.sh      # Automated test suite
├── DOCKER_TESTING.md   # Testing documentation
└── README.md           # This file
```

## Configuration

The script is modular and can be customized by commenting out unwanted sections:

```bash
# Edit cars.sh to customize packages
vim cars.sh

# Comment out unwanted packages in the pkgs array
# Skip specific installation functions in main()
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Test your changes in Docker
4. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
5. Push to the branch (`git push origin feature/AmazingFeature`)
6. Open a Pull Request

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Oh-My-Zsh](https://ohmyz.sh/) - Framework for Zsh
- [Neovim](https://neovim.io/) - Vim-based text editor
- [Alacritty](https://github.com/alacritty/alacritty) - Terminal emulator
- [Brave](https://brave.com/) - Privacy-focused browser

## Contact

**Chris** - [LinuxUser255](https://github.com/LinuxUser255)

Project Link: [https://github.com/LinuxUser255/CARS](https://github.com/LinuxUser255/CARS)

---

<p align="center">Made with dedication for the Linux community</p>
