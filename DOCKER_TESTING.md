# 🐳 CARS Docker Testing Guide

## ⚠️ IMPORTANT: Always Use Docker for Testing! ⚠️

This script makes significant system modifications. **NEVER run it directly on your host machine unless you're absolutely certain!**

## Quick Start

### Safe Interactive Menu
```bash
chmod +x safe-run.sh
./safe-run.sh
```

### Using Make Commands
```bash
# Quick syntax and function tests
make test-quick

# Run the full CARS script in Docker
make run-script

# Enter container for debugging
make shell

# Clean up
make clean
```

## How It Works

1. **Docker Container Isolation**: All script execution happens inside a Debian Docker container
2. **Visual Warnings**: The script will detect if it's running in Docker and show appropriate warnings
3. **Host Protection**: If accidentally run on host, the script will prompt for confirmation

## Visual Indicators

When running in Docker, you'll see:
```
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║        🐳 RUNNING IN DOCKER CONTAINER - SAFE MODE 🐳       ║
║                                                            ║
║  This script is executing inside a Docker container.      ║
║  All changes will be isolated from your host system.      ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
```

If accidentally run on host, you'll see:
```
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║        ⚠️  WARNING: RUNNING ON HOST SYSTEM! ⚠️              ║
║                                                            ║
║  This script is designed to run in a Docker container.    ║
║  Running it on your host system will modify your OS!      ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
```

## Prerequisites

- Docker installed and running
- docker-compose installed
- User in docker group (or use sudo)

### Add user to docker group (if needed):
```bash
sudo usermod -aG docker $USER
# Log out and back in for changes to take effect
```

## File Structure
```
CARS/
├── cars.sh              # Main script (with Docker detection)
├── Dockerfile           # Container definition
├── docker-compose.yml   # Container orchestration
├── Makefile            # Convenient commands
├── safe-run.sh         # Interactive menu wrapper
└── test-runner.sh      # Automated test suite
```

## Testing Workflow

1. **Edit cars.sh** on your host machine
2. **Test in Docker** using `make test-quick`
3. **Debug** using `make shell` if needed
4. **Run full script** using `make run-script`
5. **Clean up** using `make clean`

## Advanced Usage

### Force host execution (DANGEROUS):
```bash
FORCE_HOST_RUN=1 sudo bash cars.sh
```
**⚠️ Only use this if you know exactly what you're doing!**

### Enable debug mode:
```bash
DEBUG=1 make run-script
```

## Troubleshooting

### Permission Denied Error
If you get Docker permission errors:
```bash
# Option 1: Add sudo to commands
sudo make test-quick

# Option 2: Add user to docker group
sudo usermod -aG docker $USER
# Then log out and back in
```

### Container Already Running
```bash
make clean  # Remove existing containers
make test-quick  # Start fresh
```

## Safety Features

1. **Container Detection**: Script automatically detects Docker environment
2. **Confirmation Prompts**: Requires explicit confirmation to run on host
3. **Visual Warnings**: Clear indicators showing execution environment
4. **Isolation**: All changes confined to container
5. **Easy Cleanup**: Single command removes all traces

## Remember

**Always test in Docker first!** The container provides a safe, isolated environment that protects your host system from unintended modifications.