# CARS Testing Makefile
.PHONY: help build test shell clean logs run-script test-quick

help:
	@echo "CARS Docker Testing Commands:"
	@echo "  make build       - Build the Docker image"
	@echo "  make test        - Run automated tests"
	@echo "  make test-quick  - Quick syntax and function tests"
	@echo "  make shell       - Enter the container shell"
	@echo "  make run-script  - Run the full CARS script in container"
	@echo "  make logs        - View container logs"
	@echo "  make clean       - Stop and remove containers"
	@echo ""

build:
	@echo "Building Docker image..."
	sudo docker-compose build

test: build
	@echo "Starting test container..."
	sudo docker-compose up -d
	@sleep 2
	@echo "Running tests..."
	@chmod +x test-runner.sh
	sudo ./test-runner.sh

test-quick: build
	@echo "═══════════════════════════════════════════════════════"
	@echo "🐳 Running tests in Docker container (SAFE MODE) 🐳"
	@echo "═══════════════════════════════════════════════════════"
	@echo "Running quick tests..."
	sudo docker-compose up -d
	@sleep 1
	@echo "Syntax check..."
	@sudo docker exec cars-test-container bash -n /home/testuser/cars.sh && echo "✓ Syntax OK"
	@echo "Testing functions..."
	@sudo docker exec cars-test-container sudo bash -c 'source /home/testuser/cars.sh; check_root' && echo "✓ check_root OK"
	@echo "═══════════════════════════════════════════════════════"
	@echo "✅ Tests completed in Docker container"
	@echo "═══════════════════════════════════════════════════════"

shell:
	@echo "═══════════════════════════════════════════════════════"
	@echo "🐳 Entering Docker container shell... 🐳"
	@echo "═══════════════════════════════════════════════════════"
	@sudo docker-compose up -d
	@sudo docker exec -it cars-test-container bash

run-script:
	@echo "╔════════════════════════════════════════════════════════════╗"
	@echo "║                                                            ║"
	@echo "║     🐳 RUNNING CARS SCRIPT IN DOCKER CONTAINER 🐳         ║"
	@echo "║                                                            ║"
	@echo "║  All changes will be isolated from your host system.      ║"
	@echo "║  This is a SAFE testing environment.                      ║"
	@echo "║                                                            ║"
	@echo "╚════════════════════════════════════════════════════════════╝"
	@echo ""
	@sudo docker-compose up -d
	@echo "Starting CARS script in container..."
	@echo ""
	@sudo docker exec -it cars-test-container sudo bash /home/testuser/cars.sh

logs:
	@sudo docker-compose logs -f

clean:
	@echo "Cleaning up..."
	@sudo docker-compose down -v
	@rm -rf test-output
