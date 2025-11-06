#!/bin/bash
# Safe wrapper for CARS script - ensures Docker container usage

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

clear

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                            ║${NC}"
echo -e "${BLUE}║           🐳 CARS Script - Docker Safe Runner 🐳           ║${NC}"
echo -e "${BLUE}║                                                            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker is not installed!${NC}"
    echo "Please install Docker first: https://docs.docker.com/get-docker/"
    exit 1
fi

# Check if docker-compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}❌ docker-compose is not installed!${NC}"
    echo "Please install docker-compose first."
    exit 1
fi

# Check if we have the necessary files
if [[ ! -f "Dockerfile" ]] || [[ ! -f "docker-compose.yml" ]] || [[ ! -f "cars.sh" ]]; then
    echo -e "${RED}❌ Missing required files!${NC}"
    echo "Please ensure you're in the CARS directory with:"
    echo "  - Dockerfile"
    echo "  - docker-compose.yml"
    echo "  - cars.sh"
    exit 1
fi

echo -e "${GREEN}✓ Docker is installed${NC}"
echo -e "${GREEN}✓ Required files found${NC}"
echo ""

# Menu options
echo -e "${YELLOW}What would you like to do?${NC}"
echo "1) Run quick tests (syntax & function checks)"
echo "2) Run the full CARS installation script"
echo "3) Enter Docker container shell for debugging"
echo "4) View container logs"
echo "5) Clean up (remove containers)"
echo "6) Exit"
echo ""

read -p "Enter your choice [1-6]: " choice

case $choice in
    1)
        echo -e "${BLUE}Running quick tests...${NC}"
        make test-quick
        ;;
    2)
        echo -e "${YELLOW}⚠️  This will run the FULL installation script in Docker.${NC}"
        echo -e "${YELLOW}It may take a while to complete.${NC}"
        read -p "Continue? (y/n): " confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
            make run-script
        else
            echo "Cancelled."
        fi
        ;;
    3)
        echo -e "${BLUE}Entering container shell...${NC}"
        echo -e "${YELLOW}Type 'exit' to leave the container${NC}"
        make shell
        ;;
    4)
        echo -e "${BLUE}Showing container logs (Ctrl+C to exit)...${NC}"
        make logs
        ;;
    5)
        echo -e "${YELLOW}Cleaning up Docker containers...${NC}"
        make clean
        echo -e "${GREEN}✓ Cleanup complete${NC}"
        ;;
    6)
        echo -e "${GREEN}Goodbye!${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}Invalid choice!${NC}"
        exit 1
        ;;
esac