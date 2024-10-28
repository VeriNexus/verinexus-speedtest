#!/usr/bin/env python3

import sys
import subprocess
import json
import uuid
import logging
import time
import datetime

# Version number
VERSION = "1.0.3"
FILENAME = "mqtt_speedtest.py"

# Set up logging for full debugging and progress information
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(FILENAME)

# Dependency check and installation
required_packages = ['paho-mqtt', 'influxdb']
for package in required_packages:
    try:
        __import__(package.replace('-', '_'))
    except ImportError:
        logger.warning(f"Package '{package}' not found. Installing...")
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install", package])
            logger.info(f"Package '{package}' installed successfully.")
        except Exception as e:
            logger.error(f"Failed to install package '{package}': {e}")
            sys.exit(1)

try:
    import paho.mqtt.client as mqtt
    from influxdb import InfluxDBClient
except ImportError as e:
    logger.error(f"Import error: {e}")
    sys.exit(1)

# Function to get the MAC address of the device
def get_mac_address():
    mac_num = hex(uuid.getnode()).replace('0x', '').zfill(12)
    mac = ':'.join(mac_num[i:i+2] for i in range(0, 12, 2))
    return mac

# Get the MAC address
mac_address = get_mac_address()
logger.info(f"MAC Address: {mac_address}")

# Define the MQTT broker details
MQTT_BROKER = "mqtt.verinexus.com"
MQTT_PORT = 1883

# Define the topics
TRIGGER_TOPIC = f"speedtest/pi/{mac_address}/trigger"
ALL_TOPICS = TRIGGER_TOPIC

# InfluxDB settings
INFLUXDB_HOST = 'speedtest.verinexus.com'
INFLUXDB_PORT = 8086
INFLUXDB_USERNAME = ''  # Replace with your username if authentication is enabled
INFLUXDB_PASSWORD = ''  # Replace with your password if authentication is enabled
INFLUXDB_DATABASE = 'speedtest_db_clean'
INFLUXDB_MEASUREMENT = 'ondemand'

# Initialize InfluxDB client
try:
    influxdb_client = InfluxDBClient(
        host=INFLUXDB_HOST,
        port=INFLUXDB_PORT,
        username=INFLUXDB_USERNAME,
        password=INFLUXDB_PASSWORD,
        database=INFLUXDB_DATABASE
    )
    logger.info("Connected to InfluxDB.")
except Exception as e:
    logger.error(f"Failed to connect to InfluxDB: {e}")
    sys.exit(1)

# Check if database exists; if not, create it
def check_create_database(client, dbname):
    databases = client.get_list_database()
    if not any(db['name'] == dbname for db in databases):
        logger.info(f"Database '{dbname}' does not exist. Creating database.")
        client.create_database(dbname)
    else:
        logger.info(f"Database '{dbname}' already exists.")

check_create_database(influxdb_client, INFLUXDB_DATABASE)

# Function to run speedtest
def run_speedtest():
    logger.info("Starting speedtest...")
    try:
        result = subprocess.run(
            ["speedtest-cli", "--json"],
            capture_output=True,
            text=True,
            timeout=300
        )
        if result.returncode != 0:
            logger.error(f"Speedtest failed: {result.stderr}")
            return None
        logger.info("Speedtest completed.")
        speedtest_data = json.loads(result.stdout)
    except subprocess.TimeoutExpired:
        logger.error("Speedtest timed out.")
        return None
    except Exception as e:
        logger.error(f"Unexpected error running speedtest: {e}")
        return None

    # Convert download and upload speeds to Mbps
    speedtest_data['download_mbps'] = speedtest_data['download'] / 1_000_000  # Convert bps to Mbps
    speedtest_data['upload_mbps'] = speedtest_data['upload'] / 1_000_000      # Convert bps to Mbps

    # Add additional data
    speedtest_data['mac_address'] = mac_address
    current_time = datetime.datetime.now(datetime.timezone.utc)
    iso_time = current_time.isoformat()
    speedtest_data['human_readable_time'] = iso_time
    speedtest_data['timestamp'] = int(current_time.timestamp())
    return speedtest_data

# Function to write data to InfluxDB
def write_to_influxdb(data):
    # Prepare the data for InfluxDB
    json_body = {
        "measurement": INFLUXDB_MEASUREMENT,
        "tags": {
            "tag_mac_address": data['mac_address'],
            "tag_client_ip": data['client']['ip'],
            "tag_client_isp": data['client']['isp'],
            "tag_client_country": data['client']['country'],
            "tag_server_id": data['server']['id'],
            "tag_server_sponsor": data['server']['sponsor'],
            "tag_server_name": data['server']['name'],
            "tag_server_country": data['server']['country'],
            "tag_server_host": data['server'].get('host', ''),
        },
        "fields": {
            "field_mac_address": data['mac_address'],
            "field_download": data['download_mbps'],
            "field_upload": data['upload_mbps'],
            "field_ping": data['ping'],
            "field_timestamp": data['timestamp'],
            "field_human_readable_time": data['human_readable_time'],
            "field_share": data.get('share', ''),
            "field_server_distance": float(data['server']['d']),
            "field_server_latency": data['server']['latency']
        },
        "time": int(data['timestamp'] * 1e9)  # Convert to nanoseconds
    }

    # Write to InfluxDB
    try:
        influxdb_client.write_points([json_body])
        logger.info("Data written to InfluxDB successfully.")
    except Exception as e:
        logger.error(f"Failed to write data to InfluxDB: {e}")

# The callback for when a message is received on any topic
def on_message(client, userdata, msg):
    logger.debug(f"Message received on topic {msg.topic}: {msg.payload}")
    # Handle trigger message
    if msg.topic == TRIGGER_TOPIC:
        payload = msg.payload.decode('utf-8')
        if payload == "run":
            logger.info("Trigger received, running speedtest...")
            # Run the speedtest
            speedtest_result = run_speedtest()
            if speedtest_result:
                # Write the results to InfluxDB
                write_to_influxdb(speedtest_result)
                logger.info("Speedtest results stored in InfluxDB.")

                # Output results to UI
                print("\nSpeedtest Results:")
                print(f"Download Speed: {speedtest_result['download_mbps']:.2f} Mbps")
                print(f"Upload Speed  : {speedtest_result['upload_mbps']:.2f} Mbps")
                print(f"Latency       : {speedtest_result['ping']} ms")
                print(f"MAC Address   : {speedtest_result['mac_address']}")
                print(f"Test DateTime : {speedtest_result['human_readable_time']}")
                print(f"Test Server   : {speedtest_result['server']['name']}\n")

                logger.info("Returning to MQTT client loop.")
            else:
                logger.error("No speedtest results to store.")
        else:
            logger.warning(f"Unknown payload: {payload}")

# Initialize the MQTT client
client = mqtt.Client()
client.on_message = on_message

# Connect to the broker and subscribe to the trigger topic
try:
    logger.info(f"Connecting to MQTT Broker at {MQTT_BROKER}:{MQTT_PORT}")
    client.connect(MQTT_BROKER, MQTT_PORT, 60)
    client.subscribe(ALL_TOPICS)
    logger.info(f"Subscribed to topic {ALL_TOPICS}")
except Exception as e:
    logger.error(f"Failed to connect to MQTT Broker: {e}")
    sys.exit(1)

# Start the MQTT client loop to listen for messages
logger.info("Starting MQTT client loop...")
try:
    client.loop_forever()
except KeyboardInterrupt:
    logger.info("MQTT client loop interrupted by user.")
except Exception as e:
    logger.error(f"Unexpected error in MQTT client loop: {e}")
