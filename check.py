"""
File Name: check.py
Version: 1.5
Date: November 12, 2024
Description:
    This Python script runs on the server to monitor remote nodes posting keepalive updates.
    If they are not, it will proactively mark the node as down unless it is marked as suspended.
    It writes status changes to the database only when the status changes, minimizing database writes.
    It includes a curses-based UI to enhance display and provide real-time status updates.
    Version 1.5 fixes the handling of suspended devices, ensuring they are listed in the UI,
    receive "maintenance" status updates, and reorganizes the UI for better readability.

Changelog:
    Version 1.4 - Added heartbeat write confirmations in the UI, properly handled suspended devices,
                  wrote 'maintenance' status for suspended devices, refreshed suspended devices in the UI,
                  fixed display and logic for suspended devices with no keepalive data, and reorganized the UI.
    Version 1.5 - Fixed retrieval of suspended devices from InfluxDB, updated keepalive checks to include
                  suspended devices without keepalive data, corrected status updates, and tested functionality.
"""

import time
from datetime import datetime, timezone
from influxdb import InfluxDBClient
import curses
import signal
import sys
import logging
from logging.handlers import RotatingFileHandler

# Setup logging with a rotating file handler
log_handler = RotatingFileHandler('verinexus_server_monitoring.log', maxBytes=5*1024*1024, backupCount=3)
logging.basicConfig(
    handlers=[log_handler],
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# InfluxDB Configuration
INFLUXDB_SERVER = "speedtest.verinexus.com"
INFLUXDB_PORT = 8086
INFLUXDB_DB = "speedtest_db_clean"
try:
    influx_client = InfluxDBClient(host=INFLUXDB_SERVER, port=INFLUXDB_PORT, database=INFLUXDB_DB)
    logging.info("Successfully connected to InfluxDB.")
except Exception as e:
    logging.critical(f"Failed to connect to InfluxDB: {e}")
    sys.exit("Failed to connect to InfluxDB. Please check your configuration.")

# Global variables to store node statuses and settings
node_statuses = {}
settings_info = {}
last_status_updates = {}
settings = {}
settings_display = ""
next_keepalive_check_in = 0
next_heartbeat_in = 0
heartbeat_write_confirmations = []
suspended_devices = {}

def get_settings():
    try:
        query = "SELECT LAST(SETTING) FROM settings GROUP BY SETTING_NAME"
        result = influx_client.query(query)
        settings = {}
        if result:
            for series in result.raw.get('series', []):
                setting_name = series['tags']['SETTING_NAME'].strip('"')
                setting_value = series['values'][0][1]
                settings[setting_name] = setting_value
            logging.info("Settings successfully retrieved from InfluxDB.")
            # Create a string representation for UI display
            settings_descriptions = {
                "CHECKALIVE": "Threshold for keepalive expiry (seconds)",
                "HEARTBEAT": "Interval for writing heartbeat status (seconds)",
                "NTP_SERVER": "NTP server for time synchronization",
            }
            relevant_settings = ["CHECKALIVE", "HEARTBEAT", "NTP_SERVER"]
            settings_display_lines = []
            for k in relevant_settings:
                v = settings.get(k, "Not Set")
                description = settings_descriptions.get(k, "No description available")
                settings_display_lines.append(f"{k}: {v} ({description})")
            global settings_display
            settings_display = "\n".join(settings_display_lines)
            return settings
        else:
            logging.error("Settings query returned no results.")
            return None
    except Exception as e:
        logging.error(f"Failed to retrieve settings from InfluxDB: {e}")
        return None

def check_node_status(stdscr):
    try:
        # Initialize curses
        curses.curs_set(0)  # Hide the cursor
        stdscr.nodelay(1)  # Non-blocking input
        stdscr.timeout(1000)  # Refresh every second

        is_running = True

        # Retrieve settings
        global settings
        settings = get_settings()
        if not settings:
            stdscr.addstr(0, 0, "No settings available. Exiting...")
            stdscr.refresh()
            time.sleep(2)
            return

        # Read settings
        try:
            threshold = int(settings.get("CHECKALIVE", "120"))
        except ValueError:
            threshold = 120
            logging.warning("Invalid CHECKALIVE setting. Defaulting to 120 seconds.")

        try:
            heartbeat_interval = int(settings.get("HEARTBEAT", "300"))
        except ValueError:
            heartbeat_interval = 300
            logging.warning("Invalid HEARTBEAT setting. Defaulting to 300 seconds.")

        ntp_server = settings.get("NTP_SERVER", "pool.ntp.org")

        # Timing variables
        last_keepalive_check_time = time.time()
        last_heartbeat_time = time.time()

        while is_running:
            try:
                key = stdscr.getch()
                if key == ord('q'):
                    is_running = False
                    clean_exit(None, None)

                current_time = time.time()

                # Update countdown timers
                global next_keepalive_check_in, next_heartbeat_in
                next_keepalive_check_in = max(0, int(threshold - (current_time - last_keepalive_check_time)))
                next_heartbeat_in = max(0, int(heartbeat_interval - (current_time - last_heartbeat_time)))

                # Perform keepalive check
                if current_time - last_keepalive_check_time >= threshold:
                    perform_keepalive_check(threshold)
                    last_keepalive_check_time = current_time

                # Perform heartbeat write
                if current_time - last_heartbeat_time >= heartbeat_interval:
                    perform_heartbeat_write()
                    last_heartbeat_time = current_time

                # Update UI
                update_ui(stdscr)
                time.sleep(1)
            except Exception as e:
                stdscr.addstr(0, 0, f"Error: {e}")
                stdscr.refresh()
                time.sleep(1)
    except Exception as e:
        stdscr.addstr(0, 0, f"Critical Error: {e}")
        stdscr.refresh()
        time.sleep(2)

def perform_keepalive_check(threshold):
    try:
        logging.info("Performing keepalive check.")
        # Get list of all MAC addresses from keepalive measurement
        keepalive_query = "SELECT LAST(field_mac_address) FROM keepalive GROUP BY tag_mac_address"
        keepalive_result = influx_client.query(keepalive_query)

        # Refresh suspended devices
        refresh_suspended_devices()

        all_devices = set(suspended_devices.keys())

        if keepalive_result:
            for series in keepalive_result.raw.get('series', []):
                mac_address = series['tags']['tag_mac_address']
                all_devices.add(mac_address)

        # Iterate over each device
        for mac_address in all_devices:
            # Check if the device is suspended
            is_suspended = mac_address in suspended_devices

            # If the device is not in keepalive, set time_diff to a large value
            if keepalive_result and any(series['tags']['tag_mac_address'] == mac_address for series in keepalive_result.raw.get('series', [])):
                # Device is in keepalive
                series = next(s for s in keepalive_result.raw.get('series', []) if s['tags']['tag_mac_address'] == mac_address)
                last_keepalive_point = series['values'][0]
                last_keepalive_time_str = last_keepalive_point[0]
                try:
                    # Try parsing timestamp with microseconds
                    last_keepalive_time = datetime.strptime(last_keepalive_time_str, '%Y-%m-%dT%H:%M:%S.%fZ').replace(tzinfo=timezone.utc)
                except ValueError:
                    # Fallback to parsing without microseconds
                    last_keepalive_time = datetime.strptime(last_keepalive_time_str, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
                time_diff = (datetime.utcnow().replace(tzinfo=timezone.utc) - last_keepalive_time).total_seconds()
            else:
                # Device is not in keepalive
                time_diff = float('inf')

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
                node_statuses[mac_address] = new_status
                last_status_updates[mac_address] = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
                logging.info(f"Status for {mac_address} updated to '{new_status}'.")
            else:
                last_status_updates[mac_address] = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")

    except Exception as e:
        logging.error(f"Error during keepalive check: {e}")

def perform_heartbeat_write():
    try:
        logging.info("Performing heartbeat write.")
        heartbeat_write_confirmations.clear()

        # Refresh suspended devices
        refresh_suspended_devices()

        # Get all devices from suspended_devices and device_status
        device_status_query = "SELECT LAST(field_status) FROM device_status GROUP BY tag_mac_address"
        device_status_result = influx_client.query(device_status_query)

        all_devices = set(suspended_devices.keys())

        if device_status_result:
            for series in device_status_result.raw.get('series', []):
                mac_address = series['tags']['tag_mac_address']
                all_devices.add(mac_address)

        now_iso = datetime.utcnow().isoformat() + 'Z'

        # Iterate over all devices
        for mac_address in all_devices:
            is_suspended = mac_address in suspended_devices

            # Determine status
            if is_suspended:
                last_status = 'maintenance'
            else:
                last_status = node_statuses.get(mac_address, 'unknown')

            json_body = [{
                "measurement": "device_status",
                "tags": {
                    "tag_mac_address": mac_address,
                    "tag_external_ip": "unknown"
                },
                "time": now_iso,
                "fields": {
                    "field_status": last_status
                }
            }]
            influx_client.write_points(json_body)
            heartbeat_write_confirmations.append({
                "mac_address": mac_address,
                "status": last_status,
                "timestamp": now_iso
            })
            logging.info(f"Heartbeat status for {mac_address} reaffirmed as '{last_status}'.")

    except Exception as e:
        logging.error(f"Error during heartbeat write: {e}")

def refresh_suspended_devices():
    try:
        suspended_query = "SELECT * FROM suspended_devices"
        suspended_result = influx_client.query(suspended_query)
        suspended_devices.clear()
        if suspended_result:
            for point in suspended_result.get_points():
                mac_address = point.get('tag_mac_address') or point.get('field_mac_address')
                if mac_address:
                    suspended_devices[mac_address] = 'maintenance'
        else:
            logging.info("No suspended devices found.")
    except Exception as e:
        logging.error(f"Error refreshing suspended devices: {e}")

def update_ui(stdscr):
    stdscr.clear()
    stdscr.addstr(0, 0, f"VeriNexus Server Monitoring - Version 1.5".center(100))
    stdscr.addstr(1, 0, "="*100)

    row = 2

    # Node Information
    stdscr.addstr(row, 0, "Node Information:")
    row += 1
    stdscr.addstr(row, 0, f"{'MAC Address':<20} {'Status':<15} {'Last Update':<25}")
    row += 1
    stdscr.addstr(row, 0, "-"*60)
    row += 1

    for mac_address in node_statuses.keys():
        last_status = node_statuses[mac_address]
        last_update = last_status_updates.get(mac_address, 'Unknown')
        stdscr.addstr(row, 0, f"{mac_address:<20} {last_status:<15} {last_update:<25}")
        row += 1

    # Suspended Devices
    row += 1
    stdscr.addstr(row, 0, "Suspended Devices:")
    row += 1
    if suspended_devices:
        stdscr.addstr(row, 0, f"{'MAC Address':<20} {'Status':<15}")
        row += 1
        stdscr.addstr(row, 0, "-"*35)
        row += 1
        for mac_address in suspended_devices.keys():
            stdscr.addstr(row, 0, f"{mac_address:<20} {'maintenance':<15}")
            row += 1
    else:
        stdscr.addstr(row, 0, "No Suspended Devices")
        row += 1

    # Heartbeat Writes
    row += 1
    stdscr.addstr(row, 0, "Heartbeat Writes:")
    row += 1
    if heartbeat_write_confirmations:
        stdscr.addstr(row, 0, f"{'MAC Address':<20} {'Status':<15} {'Timestamp':<25}")
        row += 1
        stdscr.addstr(row, 0, "-"*60)
        row += 1
        for entry in heartbeat_write_confirmations:
            stdscr.addstr(row, 0, f"{entry['mac_address']:<20} {entry['status']:<15} {entry['timestamp']:<25}")
            row += 1
    else:
        stdscr.addstr(row, 0, "No Heartbeat Writes in this interval")
        row += 1

    # Countdown Timers
    row += 1
    stdscr.addstr(row, 0, "Timers:")
    row += 1
    stdscr.addstr(row, 0, f"Next Keepalive Check In: {next_keepalive_check_in} seconds")
    row += 1
    stdscr.addstr(row, 0, f"Next Heartbeat Write In: {next_heartbeat_in} seconds")
    row += 1

    # Settings
    row += 1
    stdscr.addstr(row, 0, "Relevant Settings:")
    settings_lines = settings_display.split('\n')
    for idx, line in enumerate(settings_lines):
        stdscr.addstr(row + idx, 0, line)
    row += len(settings_lines)

    stdscr.addstr(row + 1, 0, "="*100)
    stdscr.addstr(row + 2, 0, "Press 'q' to quit.".center(100))
    stdscr.refresh()

# Function to handle clean exit
def clean_exit(signum, frame):
    logging.info("Exiting gracefully...")
    curses.endwin()
    sys.exit(0)

# Handle clean exit on SIGINT (Ctrl+C)
signal.signal(signal.SIGINT, clean_exit)
signal.signal(signal.SIGTERM, clean_exit)

# Start the monitoring loop with curses
curses.wrapper(check_node_status)
