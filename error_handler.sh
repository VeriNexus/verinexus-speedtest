#!/bin/bash

# Error handler script version
ERROR_HANDLER_VERSION="1.0.0"

# Initialize error log
ERROR_LOG=""

log_error() {
    local error_message="$1"
    ERROR_LOG+="===============================\n"
    ERROR_LOG+="Timestamp: $(TZ='Europe/London' date +"%Y-%m-%d %H:%M:%S")\n"
    ERROR_LOG+="Script Version: $SCRIPT_VERSION\n"
    ERROR_LOG+="Error: $error_message\n"
    ERROR_LOG+="===============================\n"
    echo -e "${RED}Error: $error_message${NC}"
}

upload_error_log() {
    if [ -n "$ERROR_LOG" ]; then
        echo -e "$ERROR_LOG" | sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "cat >> $ERROR_LOG_PATH"
        echo -e "${GREEN}All errors logged and uploaded.${NC}"
    fi
}
