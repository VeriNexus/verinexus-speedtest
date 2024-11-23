#!/bin/bash

# Script Name: setup_wireguard_v1.0_23-11-2024.sh
# Version: 1.0
# Date: 23-11-2024
# Author: Your Script Maintenance Team
# Purpose: Check, install, and configure WireGuard if not present, with robust error handling.

# Define colors for UI messages
RED="\033[1;31m"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RESET="\033[0m"

# Target MAC address for device validation
TARGET_MAC="b8:27:eb:cd:c2:b8"

# WireGuard configuration
WG_CONF="/etc/wireguard/wg0.conf"
WG_SERVICE="wg-quick@wg0"
PRIVATE_KEY="GKkqkWL+2djY6X4AIRgIGdFyPikNsUgMBdoDtDYCrkg="
PUBLIC_KEY="YGgPNq5+kDKy+5V7Z+d5xECiHP1GdjeJftTP4jduJw0="
ADDRESS="172.31.0.6/16"
ENDPOINT="viper.verinexus.com:51820"
ALLOWED_IPS="172.31.0.1/32"
PERSISTENT_KEEPALIVE="25"

log_message() {
    # Function for logging messages with timestamps
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] $1${RESET}"
}

error_message() {
    # Function for logging errors
    echo -e "${RED}ERROR: $1${RESET}" >&2
}

success_message() {
    # Function for logging success messages
    echo -e "${GREEN}SUCCESS: $1${RESET}"
}

# Function to validate target MAC address
check_mac_address() {
    log_message "Checking for target MAC address ($TARGET_MAC)..."
    if ! ip link | grep -iq "$TARGET_MAC"; then
        error_message "Target MAC address not found. Exiting script."
        return 1
    fi
    success_message "Target MAC address found."
    return 0
}

# Function to check and install WireGuard
install_wireguard() {
    log_message "Checking if WireGuard is installed..."
    if ! command -v wg &> /dev/null; then
        log_message "WireGuard not found. Installing..."
        sudo apt update && sudo apt install -y wireguard
        if [ $? -eq 0 ]; then
            success_message "WireGuard installed successfully."
        else
            error_message "WireGuard installation failed."
            return 1
        fi
    else
        success_message "WireGuard is already installed."
    fi
    return 0
}

# Function to create WireGuard configuration
create_wireguard_config() {
    log_message "Creating WireGuard configuration file ($WG_CONF)..."
    sudo bash -c "cat > $WG_CONF" <<EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = $ADDRESS

[Peer]
PublicKey = $PUBLIC_KEY
Endpoint = $ENDPOINT
AllowedIPs = $ALLOWED_IPS
PersistentKeepalive = $PERSISTENT_KEEPALIVE
EOF

    if [ $? -eq 0 ]; then
        success_message "WireGuard configuration file created."
    else
        error_message "Failed to create WireGuard configuration file."
        return 1
    fi

    sudo chmod 600 $WG_CONF
    success_message "Configuration file permissions set to 600."
    return 0
}

# Function to enable and start WireGuard service
start_wireguard_service() {
    log_message "Starting and enabling WireGuard service ($WG_SERVICE)..."
    sudo systemctl enable $WG_SERVICE && sudo systemctl start $WG_SERVICE

    if [ $? -eq 0 ]; then
        success_message "WireGuard service started and enabled."
    else
        error_message "Failed to start WireGuard service."
        return 1
    fi
    return 0
}

# Function to log network information
log_network_info() {
    log_message "Logging network information..."
    MAC_ADDR=$(ip link show | grep -E 'link/ether' | awk '{print $2}' | head -n 1)
    EXTERNAL_IP=$(curl -s https://api.ipify.org)
    log_message "Device MAC Address: $MAC_ADDR"
    log_message "External IP Address: $EXTERNAL_IP"
    return 0
}

# Main script execution
main() {
    log_message "Starting WireGuard setup script..."
    
    # Validate MAC address
    check_mac_address || exit 0

    # Install WireGuard if needed
    install_wireguard || log_message "Proceeding despite WireGuard installation failure."

    # Create WireGuard configuration
    create_wireguard_config || log_message "Proceeding despite configuration failure."

    # Start WireGuard service
    start_wireguard_service || log_message "Proceeding despite service start failure."

    # Log network information
    log_network_info || log_message "Proceeding despite network logging failure."

    log_message "WireGuard setup script completed."
}

# Run the main function
main
