import paho.mqtt.client as mqtt
import json
import subprocess

# MQTT configuration - use the IP or hostname of your Grafana server
MQTT_BROKER = "mqtt.verinexus.com"
MQTT_PORT = 1883
MQTT_TOPIC = "speedtest/results"

def run_speedtest():
    try:
        result = subprocess.run(["speedtest-cli", "--json"], capture_output=True, text=True)
        if result.returncode == 0:
            return json.loads(result.stdout)
        else:
            return None
    except Exception as e:
        print(f"Error running speedtest: {e}")
        return None

def publish_results():
    client = mqtt.Client()
    client.connect(MQTT_BROKER, MQTT_PORT, 60)
    
    results = run_speedtest()
    if results:
        client.publish(MQTT_TOPIC, json.dumps(results))
        print("Results published successfully")
    else:
        print("Failed to retrieve or publish results")

    client.disconnect()

if __name__ == "__main__":
    publish_results()
