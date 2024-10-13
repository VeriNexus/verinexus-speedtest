#!/bin/bash

# Update check script version
UPDATE_CHECK_VERSION="1.1.3"

check_for_updates() {
    # Function to check for script updates
    LATEST_MAIN_VERSION="1.1.2"

    echo "DEBUG: Running update check..."
    echo "DEBUG: LATEST_MAIN_VERSION=$LATEST_MAIN_VERSION"
    echo "DEBUG: SCRIPT_VERSION=$SCRIPT_VERSION"

    if [[ "$SCRIPT_VERSION" != "$LATEST_MAIN_VERSION" ]]; then
        echo -e "${YELLOW}Update available for main script: $LATEST_MAIN_VERSION${NC}"
        echo -e "Downloading the latest version..."

        # Download the new version of the script
        curl -s -o "./speedtest.sh" "https://raw.githubusercontent.com/VeriNexus/verinexus-speedtest/main/speedtest.sh"
        chmod +x ./speedtest.sh

        # Debug: Confirming download completion
        echo -e "${GREEN}Update downloaded to version $LATEST_MAIN_VERSION.${NC}"

        # Re-run the updated script
        echo -e "${YELLOW}Re-running the updated script...${NC}"
        exec ./speedtest.sh
    else
        echo -e "${GREEN}You are using the latest version of the script.${NC}"
    fi
}
