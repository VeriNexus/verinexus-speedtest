#!/bin/bash

# Base directory for all operations
BASE_DIR="/VeriNexus"
SCRIPT_PATH="$BASE_DIR/speedtest.sh"
REPO_RAW_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"

# Download the latest script
curl -s -o "$SCRIPT_PATH" "$REPO_RAW_URL"
chmod +x "$SCRIPT_PATH"
