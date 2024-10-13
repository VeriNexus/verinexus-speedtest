#!/bin/bash

# Update check script version
UPDATE_CHECK_VERSION="1.1.2"

check_for_updates() {
    # Function to check for script updates
    LATEST_MAIN_VERSION="1.1.2"

    echo "DEBUG: Running update check..."
    echo "DEBUG: LATEST_MAIN_VERSION=$LATEST_MAIN_VERSION"
    echo "DEBUG: SCRIPT_VERSION=$SCRIPT_VERSION"

    if [[ "$SCRIPT_VERSION" != "$LATEST_MAIN_VERSION" ]]; then
        echo -e "${YELLOW}Update available for main script: $LATEST_MAIN_VERSION${NC}"
        echo -e "Downloading the latest version..."
        curl -s -o "./speedtest.sh" "https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"
        chmod +x ./speedtest.sh
        echo -e "${GREEN}Update downloaded to version $LATEST_MAIN_VERSION. Please re-run the script.${NC}"
        exit 0
    else
        echo -e "${GREEN}You are using the latest version of the script.${NC}"
    fi
}
