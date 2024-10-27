# Filename: speedtest_mqtt.py
# Version: 1.2.1
# Description: Publishes Speedtest results (Download, Upload, Latency) along with additional info (MAC Address in lowercase, Date, Time) to an MQTT broker.

import paho.mqtt.client as mqtt
import json
import speedtest
import time
import uuid
import datetime
import pytz

# Version Control Information
SCRIPT_VERSION = "1.2.1"

# MQTT configuration
MQTT_BROKER = "mqtt.verinexus.com"
MQTT_PORT = 1883
MQTT_TOPIC = "speedtest/results"

# Function to get MAC address of the active NIC (in lowercase)
def get_mac_address():
    mac = hex(uuid.getnode()).replace('0x', '').lower()  # Convert to lowercase
    return ':'.join(mac[i:i+2] for i in range(0, 12, 2))

# Function to get the current date and time in UK format
def get_uk_datetime():
    # Define the UK timezone (including summer time adjustments)
    uk_timezone = pytz.timezone("Europe/London")
    current_time = datetime.datetime.now(uk_timezone)
    
    # Format date and time separately
    date_str = current_time.strftime("%d/%m/%Y")  # UK format date
    time_str = current_time.strftime("%H:%M:%S")  # UK format time
    
    return date_str, time_str

# Run the speedtest using HTTPS
def run_speedtest():
    try:
        print(f"[INFO] Running speedtest... (Version: {SCRIPT_VERSION})")

        # Create a Speedtest instance
        st = speedtest.Speedtest()
        st.get_best_server()  # Automatically find the best server

        # Perform the download and upload tests
        download_speed = st.download() / 1e6  # Convert to Mbps
        upload_speed = st.upload() / 1e6      # Convert to Mbps
        latency = st.results.ping             # Get ping/latency

        # Get additional info
        mac_address = get_mac_address()
        date_str, time_str = get_uk_datetime()

        # Construct the results dictionary with additional info
        results = {
            "download": round(download_speed, 2),
            "upload": round(upload_speed, 2),
            "latency": round(latency, 2),        # Rename "ping" to "latency"
            "mac_address": mac_address,          # Add MAC address in lowercase
            "date": date_str,                    # Add date in UK format
            "time": time_str                     # Add time in UK format
        }

        # Debugging information
        print(f"[DEBUG] Extracted results: {results}")
        return results

    except Exception as e:
        print(f"[ERROR] Error running speedtest: {e}")
        return None

# Publish speedtest results to MQTT
def publish_results():
    print(f"[INFO] Connecting to MQTT Broker at {MQTT_BROKER}:{MQTT_PORT}...")
    client = mqtt.Client()

    try:
        client.connect(MQTT_BROKER, MQTT_PORT, 60)
        print("[INFO] Connected to MQTT Broker successfully.")
    except Exception as e:
        print(f"[ERROR] Failed to connect to MQTT Broker: {e}")
        return

    results = run_speedtest()
    if results:
        try:
            print("[INFO] Publishing results to MQTT...")
            client.publish(MQTT_TOPIC, json.dumps(results))
            print(f"[INFO] Results published successfully to topic '{MQTT_TOPIC}'")
        except Exception as e:
            print(f"[ERROR] Failed to publish results: {e}")
    else:
        print("[ERROR] No results to publish.")

    client.disconnect()
    print("[INFO] Disconnected from MQTT Broker.")

if __name__ == "__main__":
    print(f"[INFO] Starting speedtest_mqtt.py (Version: {SCRIPT_VERSION})")
    start_time = time.time()
    publish_results()
    elapsed_time = time.time() - start_time
    print(f"[INFO] Script completed in {elapsed_time:.2f} seconds.")
