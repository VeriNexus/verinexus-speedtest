"""
File Name: check.py
Version: 1.2
Date: November 9, 2024
Description:
    This Python script runs on the server to check that remote nodes are posting keepalive updates.
    If they are not, it will proactively mark the node as down unless it is marked as suspended.
    It writes status changes to the database only when the status changes, minimizing database writes.
    It now includes a curses-based UI to avoid excessive scrolling and provides real-time status updates.

Changelog:
    Version 1.0 - Initial release.
    Version 1.1 - Implemented keepalive mechanism, handled suspended devices, optimized database writes.
    Version 1.2 - Added curses-based UI to enhance display and avoid excessive scrolling.
"""

import time
from datetime import datetime, timezone
from influxdb import InfluxDBClient
import curses
import signal
import sys

# InfluxDB Configuration
INFLUXDB_SERVER = "http://speedtest.verinexus.com:8086"
INFLUXDB_DB = "speedtest_db_clean"
influx_client = InfluxDBClient(host="speedtest.verinexus.com", port=8086, database=INFLUXDB_DB)

# Global variable to store node statuses
node_statuses = {}

def check_node_status(stdscr):
    try:
        # Initialize curses
        curses.curs_set(0)  # Hide the cursor
        stdscr.nodelay(1)  # Non-blocking input
        stdscr.timeout(1000)  # Refresh every second

        is_running = True

        while is_running:
            try:
                key = stdscr.getch()
                if key == ord('q'):
                    is_running = False
                    clean_exit(None, None)

                # Get list of all MAC addresses from keepalive measurement
                keepalive_query = "SELECT LAST(field_mac_address) FROM keepalive GROUP BY tag_mac_address"
                keepalive_result = influx_client.query(keepalive_query)

                if not keepalive_result:
                    stdscr.addstr(0, 0, "No keepalive data found in the database.")
                    stdscr.refresh()
                    time.sleep(1)
                    continue

                # Clear the screen
                stdscr.clear()
                stdscr.addstr(0, 0, "="*80)
                stdscr.addstr(1, 0, "VeriNexus Server Monitoring - Press 'q' to quit".center(80))
                stdscr.addstr(2, 0, "="*80)
                stdscr.addstr(3, 0, f"{'MAC Address':<20} {'Status':<15} {'Last Update':<25} {'Info':<20}")
                stdscr.addstr(4, 0, "-"*80)

                row = 5

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
                    if mac_address not in node_statuses or node_statuses[mac_address] != new_status:
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
                        info = f"Status changed to '{new_status}'"
                        node_statuses[mac_address] = new_status
                    else:
                        info = "No status change"

                    # Display node information
                    stdscr.addstr(row, 0, f"{mac_address:<20} {new_status:<15} {last_keepalive_time_str:<25} {info:<20}")
                    row += 1

                stdscr.refresh()
                time.sleep(1)
            except Exception as e:
                stdscr.addstr(row, 0, f"Error: {e}")
                stdscr.refresh()
                time.sleep(1)
    except Exception as e:
        print(f"Error in check_node_status: {e}")

# Function to handle clean exit
def clean_exit(signum, frame):
    curses.endwin()
    sys.exit(0)

# Handle clean exit on SIGINT (Ctrl+C)
signal.signal(signal.SIGINT, clean_exit)
signal.signal(signal.SIGTERM, clean_exit)

# Start the monitoring loop with curses
curses.wrapper(check_node_status)
