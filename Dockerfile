# Dockerfile for testing CARS script
FROM debian:12-slim

# Install basic dependencies needed for the script
RUN apt-get update && apt-get install -y \
    sudo \
    curl \
    wget \
    git \
    ca-certificates \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Create a test user with sudo privileges
RUN useradd -m -s /bin/bash testuser && \
    echo "testuser:testpass" | chpasswd && \
    usermod -aG sudo testuser && \
    echo "testuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set working directory
WORKDIR /home/testuser

# Copy the script into the container
COPY cars.sh /home/testuser/cars.sh
RUN chmod +x /home/testuser/cars.sh

# Switch to test user
USER testuser

# Default command
CMD ["/bin/bash"]