#!/bin/bash

# Base directory for the script
BASE_DIR="/VeriNexus"

# Ensure the base directory exists
if [ ! -d "$BASE_DIR" ]; then
    mkdir -p "$BASE_DIR"
fi

# Change to the base directory
cd "$BASE_DIR" || { echo "Failed to change directory to $BASE_DIR"; exit 1; }

# Update package list
sudo apt update

# Install openssh-server
sudo apt install -y openssh-server

# Enable and start the SSH service
sudo systemctl enable ssh
sudo systemctl start ssh

# Allow SSH through the firewall
sudo ufw allow ssh

# Check the status of the SSH service
sudo systemctl status ssh

# GitHub repository raw URL for the script
REPO_RAW_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"

# Destination path for the downloaded script
DEST_SCRIPT="$BASE_DIR/speedtest.sh"

# Download the latest version of speedtest.sh
curl -o "$DEST_SCRIPT" "$REPO_RAW_URL"

# Make the script executable
chmod +x "$DEST_SCRIPT"

echo "Downloaded and installed the latest version of speedtest.sh to $DEST_SCRIPT"