#!/bin/bash

# VeriNexus Installer Script
# Version: 1.0.0
# Author: VeriNexus
# Copyright (c) 2024 VeriNexus. All rights reserved.

# Base directory for the script
BASE_DIR="/VeriNexus"

# Function to print error messages
print_error() {
    echo "Error: $1"
    exit 1
}

# Ensure the base directory exists
if [ ! -d "$BASE_DIR" ]; then
    mkdir -p "$BASE_DIR" || print_error "Failed to create directory $BASE_DIR"
fi

# Change to the base directory
cd "$BASE_DIR" || print_error "Failed to change directory to $BASE_DIR"

# Update package list
echo "Updating package list..."
sudo apt update || print_error "Failed to update package list"

# Install openssh-server
echo "Installing openssh-server..."
sudo apt install -y openssh-server || print_error "Failed to install openssh-server"

# Enable and start the SSH service
echo "Enabling and starting SSH service..."
sudo systemctl enable ssh || print_error "Failed to enable SSH service"
sudo systemctl start ssh || print_error "Failed to start SSH service"

# Allow SSH through the firewall
echo "Allowing SSH through the firewall..."
sudo ufw allow ssh || print_error "Failed to allow SSH through the firewall"

# Check the status of the SSH service
echo "Checking the status of the SSH service..."
sudo systemctl status ssh || print_error "Failed to check the status of the SSH service"

# GitHub repository raw URL for the script
REPO_RAW_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"

# Destination path for the downloaded script
DEST_SCRIPT="$BASE_DIR/speedtest.sh"

# Download the latest version of speedtest.sh
echo "Downloading the latest version of speedtest.sh..."
curl -o "$DEST_SCRIPT" "$REPO_RAW_URL" || print_error "Failed to download speedtest.sh"

# Make the script executable
echo "Making the script executable..."
chmod +x "$DEST_SCRIPT" || print_error "Failed to make speedtest.sh executable"

echo "Downloaded and installed the latest version of speedtest.sh to $DEST_SCRIPT"