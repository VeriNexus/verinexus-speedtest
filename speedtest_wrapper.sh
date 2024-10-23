#!/bin/bash

# Version number of the wrapper script
WRAPPER_VERSION="1.1.0"

# Base directory for all operations
BASE_DIR="/VeriNexus"

# Main script name
MAIN_SCRIPT="speedtest.sh"

# Full path to the main script
MAIN_SCRIPT_PATH="$BASE_DIR/$MAIN_SCRIPT"

# URL to download the main script from
MAIN_SCRIPT_URL="https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"

# Temporary file to hold the latest main script for comparison
TEMP_MAIN_SCRIPT="$BASE_DIR/latest_speedtest.sh"

# Function to ensure the base directory exists
ensure_base_dir() {
    if [ ! -d "$BASE_DIR" ]; then
        mkdir -p "$BASE_DIR" || {
            echo "Failed to create base directory: $BASE_DIR"
            exit 1
        }
    fi
}

# Function to compare versions using awk
version_gt() {
    awk -v v1="$1" -v v2="$2" '
    BEGIN {
        split(v1, a, ".")
        split(v2, b, ".")
        for (i = 1; i <= 3; i++) {
            a_i = (i in a) ? a[i] : 0
            b_i = (i in b) ? b[i] : 0
            if (a_i > b_i) {
                exit 0  # v1 > v2
            } else if (a_i < b_i) {
                exit 1  # v1 < v2
            }
        }
        exit 1  # v1 == v2
    }'
}

# Function to get the script version from a file
get_script_version() {
    grep -oP 'SCRIPT_VERSION="\K[0-9.]+' "$1" 2>/dev/null
}

# Function to check for updates and download if necessary
check_and_update_main_script() {
    # Download the latest main script to a temporary file
    curl -s -o "$TEMP_MAIN_SCRIPT" "$MAIN_SCRIPT_URL" || {
        echo "Failed to download the main script."
        exit 1
    }

    # Get the version numbers
    LOCAL_VERSION=$(get_script_version "$MAIN_SCRIPT_PATH")
    REMOTE_VERSION=$(get_script_version "$TEMP_MAIN_SCRIPT")

    # If the local script doesn't exist or the remote version is newer, update
    if [ -z "$LOCAL_VERSION" ] || version_gt "$REMOTE_VERSION" "$LOCAL_VERSION"; then
        echo "Updating main script to version $REMOTE_VERSION..."
        mv "$TEMP_MAIN_SCRIPT" "$MAIN_SCRIPT_PATH" || {
            echo "Failed to update the main script."
            exit 1
        }
        chmod +x "$MAIN_SCRIPT_PATH"
    else
        echo "Main script is up to date (version $LOCAL_VERSION)."
        rm "$TEMP_MAIN_SCRIPT"
    fi
}

# Function to run the main script
run_main_script() {
    echo "Running the main script..."
    "$MAIN_SCRIPT_PATH"
}

# Main execution flow
ensure_base_dir
check_and_update_main_script
run_main_script
