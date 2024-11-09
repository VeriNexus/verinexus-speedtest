"""
File Name: check.py
Version: 1.3
Date: November 10, 2024
Description:
    This Python script runs on the server to check that remote nodes are posting keepalive updates.
    If they are not, it will proactively write the last known status to the database after a specified heartbeat interval.
    It writes status changes to the database only when the status changes, minimizing database writes.
    It now includes a curses-based UI to avoid excessive scrolling, provides real-time status updates,
    displays settings from the 'settings' measurement, and uses these settings within the script.

Changelog:
    Version 1.0 - Initial release.
    Version 1.1 - Implemented keepalive mechanism, handled suspended devices, optimized database writes.
    Version 1.2 - Added curses-based UI to enhance display and avoid excessive scrolling.
    Version 1.3 - Displayed settings in UI, utilized settings from 'settings' measurement, implemented HEARTBEAT setting, and improved overall script reliability.
"""

import time
from datetime import datetime, timezone
from influxdb import InfluxDBClient
import curses
import signal
import sys
import ntplib

# InfluxDB Configuration
INFLUXDB_SERVER = "speedtest.verinexus.com"
INFLUXDB_PORT = 8086
INFLUXDB_DB = "speedtest_db_clean"
influx_client = InfluxDBClient(host=INFLUXDB_SERVER, port=INFLUXDB_PORT, database=INFLUXDB_DB)

# Global variable to store node statuses and settings
node_statuses = {}
settings_info = {}

# Function to read settings from InfluxDB in key-value format
def get_settings():
    try:
        query = "SELECT LAST(*) FROM settings"
        result = influx_client.query(query)
        settings = {}
        if result:
            for point in result.get_points():
                for key in point:
                    if key.startswith('field_'):
                        setting_name = key.replace('field_', '')
                        settings[setting_name] = point[key]
        return settings
    except Exception as e:
        print(f"Failed to retrieve settings from InfluxDB: {e}")
        return None

# Function to synchronize time using NTP
def synchronize_time(ntp_server):
    try:
        client = ntplib.NTPClient()
        response = client.request(ntp_server, version=3)
        ntp_time = datetime.fromtimestamp(response.tx_time, timezone.utc)
        print(f"Time synchronized to {ntp_time.isoformat()}")
        # Note: Setting system time requires administrative privileges and is system dependent.
    except Exception as e:
        print(f"Failed to synchronize time using NTP: {e}")

def check_node_status(stdscr):
    try:
        # Initialize curses
        curses.curs_set(0)  # Hide the cursor
        stdscr.nodelay(1)  # Non-blocking input
        stdscr.timeout(1000)  # Refresh every second

        is_running = True

        # Retrieve settings
        settings = get_settings()
        if not settings:
            stdscr.addstr(0, 0, "No settings available. Exiting...")
            stdscr.refresh()
            time.sleep(2)
            return

        # Synchronize time using NTP_SERVER
        ntp_server = settings.get("NTP_SERVER", "pool.ntp.org")
        synchronize_time(ntp_server)

        heartbeat_interval = int(settings.get("HEARTBEAT", "120"))
        settings_info["display"] = "\n".join([f"{k}: {v}" for k, v in settings.items()])

        while is_running:
            try:
                key = stdscr.getch()
                if key == ord('q'):
                    is_running = False
                    clean_exit(None, None)

                # Get list of all MAC addresses from device_status measurement
                device_status_query = "SELECT LAST(field_status) FROM device_status GROUP BY tag_mac_address"
                device_status_result = influx_client.query(device_status_query)

                if not device_status_result:
                    stdscr.addstr(0, 0, "No device status data found in the database.")
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
                for series in device_status_result.raw.get('series', []):
                    mac_address = series['tags']['tag_mac_address']
                    # Get the time and status from the last device_status point
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

                    # HEARTBEAT interval from settings
                    heartbeat = heartbeat_interval

                    # Check if the device is suspended
                    suspended_query = f"SELECT * FROM suspended_devices WHERE tag_mac_address='{mac_address}'"
                    suspended_result = influx_client.query(suspended_query)
                    is_suspended = bool(suspended_result)

                    # Determine the new status
                    if is_suspended:
                        new_status = 'maintenance'
                    elif time_diff > heartbeat:
                        new_status = last_status  # Use last known status
                    else:
                        new_status = last_status

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
                        info = f"Status updated to '{new_status}'"
                        node_statuses[mac_address] = new_status
                    else:
                        info = "No status change"

                    # Display node information
                    stdscr.addstr(row, 0, f"{mac_address:<20} {new_status:<15} {last_time_str:<25} {info:<20}")
                    row += 1

                # Display settings
                stdscr.addstr(row + 1, 0, "="*80)
                stdscr.addstr(row + 2, 0, "Settings:")
                stdscr.addstr(row + 3, 0, settings_info["display"])
                stdscr.addstr(row + 4, 0, "="*80)

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
