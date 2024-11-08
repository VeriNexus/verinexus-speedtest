"""
File Name: check.py
Version: 1.0
Date: November 8, 2024
Description:
    This Python script monitors runs on the server to check that remote nodes are posting update states
    and if they are not, will proactively mark the node as down until such time that the node is back
    up and writes it's on up/down status

Changelog:
    Version 1.0 - Initial release
"""

import time
from datetime import datetime, timezone
from influxdb import InfluxDBClient

# InfluxDB Configuration
INFLUXDB_SERVER = "http://speedtest.verinexus.com:8086"
INFLUXDB_DB = "speedtest_db_clean"
influx_client = InfluxDBClient(host="speedtest.verinexus.com", port=8086, database=INFLUXDB_DB)

def check_node_status():
    try:
        # Query to get the last field_status per tag_mac_address
        query = "SELECT LAST(field_status) FROM device_status GROUP BY tag_mac_address"
        result = influx_client.query(query)
        
        # Check if there are any results
        if not result:
            print("No data found in the database.")
            return

        # Iterate over each series (grouped by tag_mac_address)
        for series in result.raw.get('series', []):
            mac_address = series['tags']['tag_mac_address']
            # Get the time and status from the last point
            last_point = series['values'][0]
            last_time_str = last_point[0]
            last_status = last_point[1]
            try:
                # Try parsing timestamp with microseconds
                last_time = datetime.strptime(last_time_str, '%Y-%m-%dT%H:%M:%S.%fZ')
            except ValueError:
                # Fallback to parsing without microseconds
                last_time = datetime.strptime(last_time_str, '%Y-%m-%dT%H:%M:%SZ')
            time_diff = (datetime.utcnow() - last_time).total_seconds()
            # Define the threshold (e.g., 120 seconds)
            threshold = 120  # Adjust as needed
            if time_diff > threshold and last_status != 'down':
                # Write a 'down' status to the database
                json_body = [{
                    "measurement": "device_status",
                    "tags": {
                        "tag_mac_address": mac_address,
                        "tag_external_ip": "unknown"  # Since we don't have the external IP here
                    },
                    "time": datetime.utcnow().isoformat() + 'Z',
                    "fields": {
                        "field_status": "down"
                    }
                }]
                influx_client.write_points(json_body)
                print(f"Wrote 'down' status for MAC address {mac_address} due to inactivity.")
            else:
                print(f"MAC address {mac_address} is active. Last status: {last_status}, Last time: {last_time_str}")
    except Exception as e:
        print(f"Error in check_node_status: {e}")

while True:
    check_node_status()
    # Sleep for 60 seconds before the next check
    time.sleep(60)
