#!/bin/bash

# Speedtest script version
RUN_SPEEDTEST_VERSION="1.1.1"

run_speed_test() {
    echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}  Step 1: Running Speed Test  ${CYAN}│${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"

    # Run the speed test
    SPEEDTEST_OUTPUT=$(speedtest-cli --csv --secure --share)
    if [ $? -eq 0 ]; then
        echo -e "${CHECKMARK} Speed Test completed successfully."
    else
        log_error "Speed Test failed."
        return 1
    fi

    # Fetch and process date and time in UK timezone
    echo -e "${CYAN}┌──────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${NC}  Step 2: Fetching Date and Time (UK Time)  ${CYAN}│${NC}"
    echo -e "${CYAN}└──────────────────────────────────────────┘${NC}"

    UK_DATE=$(TZ="Europe/London" date +"%Y-%m-%d")
    UK_TIME=$(TZ="Europe/London" date +"%H:%M:%S")
    echo -e "${CHECKMARK} Date (UK): ${YELLOW}$UK_DATE${NC}, Time (UK): ${YELLOW}$UK_TIME${NC}"

    # Clean up special characters in hostname if necessary
    CLEAN_HOSTNAME=$(hostname | tr -d '[:space:][:punct:]')

    # Prepare the data to write to the file, including speed test output
    SPEEDTEST_OUTPUT_WITH_METADATA="${SPEEDTEST_OUTPUT},$CLEAN_HOSTNAME,$UK_DATE,$UK_TIME"

    # Debug the SSH command
    echo "Running SSH command: sshpass -p '$REMOTE_PASS' ssh -o StrictHostKeyChecking=no $REMOTE_USER@$REMOTE_HOST \"echo '$SPEEDTEST_OUTPUT_WITH_METADATA' >> $REMOTE_PATH\""

    # Upload the result to the remote server
    sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "echo \"$SPEEDTEST_OUTPUT_WITH_METADATA\" >> \"$REMOTE_PATH\""
    
    if [ $? -eq 0 ]; then
        echo -e "${CHECKMARK} Results saved to the remote server."
    else
        log_error "Failed to save results to the remote server."
    fi
}
