#!/bin/bash
# CARS Test Runner - Run different test scenarios in Docker

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}CARS Docker Test Runner${NC}"
echo "========================="

# Function to run a test in Docker
run_test() {
    local test_name="$1"
    local test_cmd="$2"
    
    echo -e "\n${YELLOW}Running test: ${test_name}${NC}"
    echo "Command: $test_cmd"
    echo "-----------------------------------"
    
    # Run the test command in the container
    sudo docker exec -it cars-test-container bash -c "$test_cmd" || {
        echo -e "${RED}Test failed: ${test_name}${NC}"
        return 1
    }
    
    echo -e "${GREEN}Test passed: ${test_name}${NC}"
}

# Check if Docker is running
if ! sudo docker info > /dev/null 2>&1; then
    echo -e "${RED}Docker is not running. Please start Docker first.${NC}"
    exit 1
fi

# Build and start the container
echo -e "${YELLOW}Building Docker image...${NC}"
sudo docker-compose build

echo -e "${YELLOW}Starting container...${NC}"
sudo docker-compose up -d

# Wait for container to be ready
sleep 2

# Create test output directory
mkdir -p test-output

echo -e "\n${GREEN}Container is ready. Running tests...${NC}"

# Test 1: Check script syntax
run_test "Syntax Check" "bash -n /home/testuser/cars.sh"

# Test 2: Check if script can be sourced (for function testing)
run_test "Source Check" "bash -c 'source /home/testuser/cars.sh 2>/dev/null; echo Functions loaded'"

# Test 3: Test individual functions (dry run mode)
run_test "Function: check_root" "sudo bash -c 'source /home/testuser/cars.sh; check_root'"

# Test 4: Test package detection
run_test "Function: is_installed" "sudo bash -c 'source /home/testuser/cars.sh; is_installed vim && echo \"vim check passed\"'"

# Test 5: Test command existence check
run_test "Function: cmd_exists" "sudo bash -c 'source /home/testuser/cars.sh; cmd_exists bash && echo \"bash exists\"'"

echo -e "\n${GREEN}Basic tests completed!${NC}"
echo "-----------------------------------"
echo "To run the full script interactively:"
echo "  sudo docker exec -it cars-test-container sudo bash /home/testuser/cars.sh"
echo ""
echo "To enter the container for debugging:"
echo "  sudo docker exec -it cars-test-container bash"
echo ""
echo "To stop and remove the container:"
echo "  sudo docker-compose down"
echo ""
echo "To view container logs:"
echo "  sudo docker-compose logs -f"
