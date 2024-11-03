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

# Define the last 4 characters of the remaining valid MAC
MAC_SUFFIXES=("5362")

# Encrypted PAT for the remaining device (multi-line string handled by echo -e)
ENCRYPTED_PAT_5362="U2FsdGVkX1/KealiugRB33f10HkGL8EixYI228VvkM2qVJXZszJLcNGR7iN0Msmc\naTMhTsqpcErH60LvkqZ3+A=="

# Detect the primary network interface with a valid MAC address
echo "[INFO] Detecting primary network interface..."
PRIMARY_INTERFACE=""
for iface in $(ip -o -4 route show to default | awk '{print $5}'); do
    MAC_ADDRESS=$(cat /sys/class/net/"$iface"/address 2>/dev/null | tr -d ':-' | tr '[:upper:]' '[:lower:]')
    if [[ -n "$MAC_ADDRESS" ]]; then
        PRIMARY_INTERFACE="$iface"
        echo "[INFO] Primary network interface detected: $PRIMARY_INTERFACE"
        break
    fi
done

if [ -z "$PRIMARY_INTERFACE" ]; then
    echo "[ERROR] No active network interface with a MAC address detected. Exiting."
    exit 1
fi

# Retrieve and normalize MAC address
echo "[INFO] MAC address detected: $MAC_ADDRESS"

# Extract the last 4 characters of the MAC
MAC_SUFFIX="${MAC_ADDRESS: -4}"
echo "[INFO] MAC suffix extracted: $MAC_SUFFIX"

# Check if the last 4 characters match the known suffix
if [[ " ${MAC_SUFFIXES[@]} " =~ " $MAC_SUFFIX " ]]; then
    # Check if the MAC address already has an entry with field_validation_word = hocuspocus
    echo "[INFO] Checking if the MAC address already has an entry with validation_word = hocuspocus..."
    QUERY_RESULT=$(curl -s -G 'http://82.165.7.116:8086/query' --data-urlencode "db=validate" --data-urlencode "q=SELECT * FROM validation WHERE mac_address='$MAC_ADDRESS' AND validation_word='hocuspocus'")
    if echo "$QUERY_RESULT" | jq -e '.results[0].series[0].values' > /dev/null 2>&1; then
        echo "[INFO] MAC address already has an entry with validation_word = hocuspocus. Exiting."
        exit 0
    fi

    # Select the encrypted PAT based on MAC suffix
    echo "[INFO] Authorized MAC suffix detected, selecting encrypted PAT..."
    case "$MAC_SUFFIX" in
        "5362") ENCRYPTED_PAT="$ENCRYPTED_PAT_5362" ;;
        *) echo "[ERROR] Unauthorized device. Exiting."; exit 1 ;;
    esac

    # Decrypt the PAT using the full normalized MAC as the key
    echo "[INFO] Decrypting PAT..."
    PAT=$(echo -e "$ENCRYPTED_PAT" | openssl enc -aes-256-cbc -d -a -pbkdf2 -pass pass:"$MAC_ADDRESS" 2>/dev/null)

    # Check if decryption was successful
    if [[ $? -ne 0 || -z "$PAT" ]]; then
        echo "[ERROR] Decryption failed. Exiting."
        exit 1
    fi
    echo "[INFO] PAT decrypted successfully."

    # Download the validation file from the secure repository using the correct URL
    echo "[INFO] Downloading validation..."
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