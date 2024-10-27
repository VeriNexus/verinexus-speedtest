import paho.mqtt.client as mqtt
import subprocess
import json
import uuid
import logging

# Version number
VERSION = "1.0.0"
FILENAME = "mqtt_speedtest.py"

# Set up logging for full debugging and progress information
logging.basicConfig(level=logging.DEBUG, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(FILENAME)

# Function to get the MAC address of the device
def get_mac_address():
    mac = ':'.join(['{:02x}'.format((uuid.getnode() >> elements) & 0xff) for elements in range(0, 2*6, 8)][::-1])
    return mac

# Get the MAC address
mac_address = get_mac_address()
logger.info(f"MAC Address: {mac_address}")

# Define the MQTT broker details
MQTT_BROKER = "dashboard.verinexus.com"
MQTT_PORT = 1883

# Define the topics
ALL_TOPICS = "#"

# Function to run speedtest
def run_speedtest():
    logger.info("Starting speedtest...")
    result = subprocess.run(["speedtest-cli", "--json"], capture_output=True, text=True)
    logger.info("Speedtest completed.")
    return json.loads(result.stdout)

# The callback for when a message is received on any topic
def on_message(client, userdata, msg):
    logger.debug(f"Message received on topic {msg.topic}: {msg.payload}")
    # Add your message handling logic here
    if msg.topic.endswith("/trigger"):
        logger.info("Trigger received, running speedtest...")
        # Run the speedtest
        speedtest_result = run_speedtest()
        # Publish the results
        result_topic = msg.topic.replace("/trigger", "/result")
        client.publish(result_topic, json.dumps(speedtest_result))
        logger.info(f"Speedtest results published to {result_topic}.")

# Initialize the MQTT client
client = mqtt.Client()
client.on_message = on_message

# Connect to the broker and subscribe to all topics
logger.info(f"Connecting to MQTT Broker at {MQTT_BROKER}:{MQTT_PORT}")
client.connect(MQTT_BROKER, MQTT_PORT, 60)
client.subscribe(ALL_TOPICS)
logger.info(f"Subscribed to all topics {ALL_TOPICS}")

# Start the MQTT client loop to listen for messages
logger.info("Starting MQTT client loop...")
client.loop_forever()