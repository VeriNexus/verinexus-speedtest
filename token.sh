#!/bin/bash

# Dependency check function
install_if_missing() {
    if ! command -v "$1" &> /dev/null; then
        echo "[INFO] $1 not found, installing..."
        sudo apt-get update
        sudo apt-get install -y "$1"
    else
        echo "[INFO] $1 is already installed."
    fi
}

echo "[INFO] Checking dependencies..."
install_if_missing "curl"
install_if_missing "openssl"
install_if_missing "cat"
install_if_missing "tr"
install_if_missing "jq"

# Remove any entry in crontab that refers to token.sh
echo "[INFO] Removing any crontab entry that refers to token.sh..."
crontab -l | grep -v 'token.sh' | crontab -

# Define the last 4 characters of each valid MAC
MAC_SUFFIXES=("f206" "c2b8" "897f" "5362" "bdfd")

# Encrypted PATs for each device (multi-line strings handled by echo -e)
ENCRYPTED_PAT_f206="U2FsdGVkX18nF5H6FgkssWdWh6u9zymG73NCgh/H27PIWOfS5GIXT8X6T722L+Py\ngv7/wvmvLSBVnZSZHtFjcA=="
ENCRYPTED_PAT_c2b8="U2FsdGVkX1/lgdmAA83FLS8SpRn9lmuB1PsEp3KMEwkFvMzAqBBpakMW6XLun6Yk\n0IQkSk3K/NllnlxKdPqXQQ=="
ENCRYPTED_PAT_897f="U2FsdGVkX1/Ov6GGps9qX0Ft8n5MgVaEw+20w5jYAmsthVOsq4NWuuxwDrMzjbKB\n9YStB+R25/kEO6kOVUIb3g=="
ENCRYPTED_PAT_5362="U2FsdGVkX1/KealiugRB33f10HkGL8EixYI228VvkM2qVJXZszJLcNGR7iN0Msmc\naTMhTsqpcErH60LvkqZ3+A=="
ENCRYPTED_PAT_bdfd="U2FsdGVkX1830/HLVha1J028UGgtquE0QxeFnye1PplRkyr14NQmRCtYpL3JYcRz\n7GineScjLABxYNU+fGoBBw=="

# Automatically detect the primary network interface's MAC address
echo "[INFO] Detecting primary network interface..."
PRIMARY_INTERFACE=$(ip route | awk '/default/ { print $5 }')
if [ -z "$PRIMARY_INTERFACE" ]; then
    echo "[ERROR] No active network interface detected. Exiting."
    exit 1
fi
echo "[INFO] Primary network interface detected: $PRIMARY_INTERFACE"

# Retrieve and normalize MAC address
MAC_ADDRESS=$(cat /sys/class/net/"$PRIMARY_INTERFACE"/address 2>/dev/null | tr -d ':-' | tr '[:upper:]' '[:lower:]')
if [ -z "$MAC_ADDRESS" ]; then
    echo "[ERROR] Failed to retrieve MAC address. Exiting."
    exit 1
fi
echo "[INFO] MAC address detected: $MAC_ADDRESS"

# Extract the last 4 characters of the MAC
MAC_SUFFIX="${MAC_ADDRESS: -4}"
echo "[INFO] MAC suffix extracted: $MAC_SUFFIX"

# Check if the last 4 characters match any known suffix
if [[ " ${MAC_SUFFIXES[@]} " =~ " $MAC_SUFFIX " ]]; then
    # Select the encrypted PAT based on MAC suffix
    echo "[INFO] Authorized MAC suffix detected, selecting encrypted PAT..."
    case "$MAC_SUFFIX" in
        "f206") ENCRYPTED_PAT="$ENCRYPTED_PAT_f206" ;;
        "c2b8") ENCRYPTED_PAT="$ENCRYPTED_PAT_c2b8" ;;
        "897f") ENCRYPTED_PAT="$ENCRYPTED_PAT_897f" ;;
        "5362") ENCRYPTED_PAT="$ENCRYPTED_PAT_5362" ;;
        "bdfd") ENCRYPTED_PAT="$ENCRYPTED_PAT_bdfd" ;;
        *) echo "[ERROR] Unauthorized device. Exiting."; exit 1 ;;
    esac

    # Define the PAT file path
    PAT_FILE="/var/lib/token.sh/pat_$MAC_SUFFIX.txt"

    # Ensure the directory exists
    mkdir -p /var/lib/token.sh

    # Check if the PAT file already exists and is valid
    if [ -f "$PAT_FILE" ]; then
        echo "[INFO] PAT file already exists. Validating..."
        PAT=$(cat "$PAT_FILE")
        if curl -H "Authorization: token $PAT" -o /tmp/validate "https://raw.githubusercontent.com/VeriNexus/speedtestsecure/refs/heads/main/validate?token=GHSAT0AAAAAACZZVSSEOVU2XXAMGOLT6RDEZZH54OA"; then
            echo "[INFO] PAT file is valid. Exiting."
            rm /tmp/validate
            exit 0
        else
            echo "[WARNING] PAT file is invalid. Re-decrypting PAT..."
        fi
    fi

    # Decrypt the PAT using the full normalized MAC as the key
    echo "[INFO] Decrypting PAT..."
    PAT=$(echo -e "$ENCRYPTED_PAT" | openssl enc -aes-256-cbc -d -a -pbkdf2 -pass pass:"$MAC_ADDRESS" 2>/dev/null)

    # Check if decryption was successful
    if [[ $? -ne 0 || -z "$PAT" ]]; then
        echo "[ERROR] Decryption failed. Exiting."
        exit 1
    fi
    echo "[INFO] PAT decrypted successfully."

    # Save the decrypted PAT to a file
    echo "$PAT" > "$PAT_FILE"
    echo "[INFO] PAT saved to $PAT_FILE."

    # Download the validation file from the secure repository using the correct URL
    echo "[INFO] Downloading validation file..."
    if curl -H "Authorization: token $PAT" -o /tmp/validate "https://raw.githubusercontent.com/VeriNexus/speedtestsecure/refs/heads/main/validate?token=GHSAT0AAAAAACZZVSSEOVU2XXAMGOLT6RDEZZH54OA"; then
        echo "[INFO] Validation file downloaded successfully."

        # Show the content of the validation file for debugging
        echo "[INFO] Content of /tmp/validate:"
        cat /tmp/validate

        # Extract the content from the validation file
        VALIDATION_WORD=$(head -n 1 /tmp/validate)
        echo "[INFO] Extracted validation word: '$VALIDATION_WORD'"
        
        # Check if VALIDATION_WORD is not empty
        if [[ -n "$VALIDATION_WORD" ]]; then
            # Get the external IP address
            echo "[INFO] Retrieving external IP address..."
            EXTERNAL_IP=$(curl -s ifconfig.me)
            echo "[INFO] External IP address: $EXTERNAL_IP"

            # Create the InfluxDB database if it doesn't exist
            echo "[INFO] Creating InfluxDB database 'validate' if it does not exist..."
            curl -XPOST 'http://82.165.7.116:8086/query' --data-urlencode "q=CREATE DATABASE validate"
            echo "[INFO] Database 'validate' verified."

            # Log the results to InfluxDB
            echo "[INFO] Writing data to InfluxDB..."
            curl -i -XPOST 'http://82.165.7.116:8086/write?db=validate' --data-binary "validation,mac_address=$MAC_ADDRESS,external_ip=$EXTERNAL_IP validation_word=\"$VALIDATION_WORD\""
        else
            echo "[WARNING] Validation word is empty. Not writing to InfluxDB."
        fi

        # Clean up temporary validation file
        echo "[INFO] Cleaning up validation file..."
        rm /tmp/validate
    else
        echo "[ERROR] Failed to download the validation file. Exiting."
    fi

    # Clean up sensitive information
    unset PAT ENCRYPTED_PAT
    echo "[INFO] Cleanup complete."
else
    echo "[ERROR] MAC address does not match any authorized device. Exiting."
    exit 1
fi