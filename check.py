"""
File Name: check.py
Version: 1.1
Date: November 9, 2024
Description:
    This Python script runs on the server to check that remote nodes are posting keepalive updates.
    If they are not, it will proactively mark the node as down unless it is marked as suspended.
    It writes status changes to the database only when the status changes, minimizing database writes.
    It has been updated to use the keepalive mechanism, handle suspended devices, and avoid duplicate status writes.

Changelog:
    Version 1.0 - Initial release.
    Version 1.1 - Implemented keepalive mechanism, handled suspended devices, optimized database writes.
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
        # Get list of all MAC addresses from keepalive measurement
        keepalive_query = "SELECT LAST(field_mac_address) FROM keepalive GROUP BY tag_mac_address"
        keepalive_result = influx_client.query(keepalive_query)

        if not keepalive_result:
            print("No keepalive data found in the database.")
            return

        # Iterate over each node
        for series in keepalive_result.raw.get('series', []):
            mac_address = series['tags']['tag_mac_address']
            # Get the time from the last keepalive point
            last_keepalive_point = series['values'][0]
            last_keepalive_time_str = last_keepalive_point[0]
            try:
                # Try parsing timestamp with microseconds
                last_keepalive_time = datetime.strptime(last_keepalive_time_str, '%Y-%m-%dT%H:%M:%S.%fZ')
            except ValueError:
                # Fallback to parsing without microseconds
                last_keepalive_time = datetime.strptime(last_keepalive_time_str, '%Y-%m-%dT%H:%M:%SZ')
            time_diff = (datetime.utcnow() - last_keepalive_time).total_seconds()

            # Define the threshold (e.g., 120 seconds)
            threshold = 120  # Adjust as needed

            # Check if the device is suspended
            suspended_query = f"SELECT * FROM suspended_devices WHERE tag_mac_address='{mac_address}'"
            suspended_result = influx_client.query(suspended_query)
            is_suspended = bool(suspended_result)

            # Get the last known status
            status_query = f"SELECT LAST(field_status) FROM device_status WHERE tag_mac_address='{mac_address}'"
            status_result = influx_client.query(status_query)
            if status_result:
                last_status_series = status_result.raw.get('series', [])[0]
                last_status = last_status_series['values'][0][1]
            else:
                last_status = None

            # Determine the new status
            if is_suspended:
                new_status = 'maintenance'
            elif time_diff > threshold:
                new_status = 'down'
            else:
                new_status = 'up'

            # Write the new status only if it has changed
            if last_status != new_status:
                json_body = [{
                    "measurement": "device_status",
                    "tags": {
                        "tag_mac_address": mac_address,
                        "tag_external_ip": "unknown"  # Since we may not have the external IP here
                    },
                    "time": datetime.utcnow().isoformat() + 'Z',
                    "fields": {
                        "field_status": new_status
                    }
                }]
                influx_client.write_points(json_body)
                print(f"Status for MAC address {mac_address} changed to '{new_status}'.")
            else:
                print(f"No status change for MAC address {mac_address} (status: '{last_status}').")
    except Exception as e:
        print(f"Error in check_node_status: {e}")

while True:
    check_node_status()
    # Sleep for 60 seconds before the next check
    time.sleep(60)
