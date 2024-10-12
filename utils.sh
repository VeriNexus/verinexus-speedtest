#!/bin/bash

# Utility functions version
UTILS_VERSION="1.0.0"

# Function to fetch private IP
get_private_ip() {
    hostname -I | awk '{print $1}'
}

# Function to fetch public IP
get_public_ip() {
    curl -s ifconfig.co
}

# Function to fetch MAC address
get_mac_address() {
    local iface=$(ip route | grep default | awk '{print $5}')
    cat /sys/class/net/$iface/address
}
