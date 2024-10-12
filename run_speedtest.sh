#!/bin/bash

# Speedtest script version
RUN_SPEEDTEST_VERSION="1.0.0"

run_speed_test() {
    echo -e "${CYAN}Running Speed Test...${NC}"

    SPEEDTEST_OUTPUT=$(speedtest-cli --csv --secure --share)
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Speed Test completed successfully.${NC}"
    else
        log_error "Speed Test failed."
    fi
}
