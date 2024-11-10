"""
File Name: check.py
Version: 1.3
Date: November 10, 2024
Description:
    This Python script runs on the server to monitor remote nodes posting keepalive updates.
    If they are not, it will proactively mark the node as down unless it is marked as suspended.
    It writes status changes to the database only when the status changes, minimizing database writes.
    It includes a curses-based UI to enhance display and provide real-time status updates.
    Version 1.3 aligns script settings with the InfluxDB settings measurement, replaces the hardcoded threshold with CHECKALIVE setting,
    adds periodic status writes based on the HEARTBEAT setting, and enhances the UI with settings display and countdown timers.

Changelog:
    Version 1.2 - Added curses-based UI to enhance display and avoid excessive scrolling.
    Version 1.3 - Aligned script settings with settings measurement, replaced hardcoded threshold with CHECKALIVE setting,
                  added periodic status writes based on HEARTBEAT setting, enhanced UI with settings display and countdown timers,
                  and updated version and date.
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
            settings_display_lines = []
            for k, v in settings.items():
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

        if not keepalive_result:
            logging.warning("No keepalive data found in the database.")
            return

        # Iterate over each node
        for series in keepalive_result.raw.get('series', []):
            mac_address = series['tags']['tag_mac_address']
            # Get the time from the last keepalive point
            last_keepalive_point = series['values'][0]
            last_keepalive_time_str = last_keepalive_point[0]
            try:
                # Try parsing timestamp with microseconds
                last_keepalive_time = datetime.strptime(last_keepalive_time_str, '%Y-%m-%dT%H:%M:%S.%fZ').replace(tzinfo=timezone.utc)
            except ValueError:
                # Fallback to parsing without microseconds
                last_keepalive_time = datetime.strptime(last_keepalive_time_str, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
            time_diff = (datetime.utcnow().replace(tzinfo=timezone.utc) - last_keepalive_time).total_seconds()

            # Check if the device is suspended
            suspended_query = f"SELECT * FROM suspended_devices WHERE tag_mac_address='{mac_address}'"
            suspended_result = influx_client.query(suspended_query)
            is_suspended = bool(suspended_result.raw.get('series', []))

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
                last_status_updates[mac_address] = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
                logging.info(f"Status for {mac_address} updated to '{new_status}'.")
            else:
                info = "No status change"
                last_status_updates[mac_address] = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")

    except Exception as e:
        logging.error(f"Error during keepalive check: {e}")

def perform_heartbeat_write():
    try:
        logging.info("Performing heartbeat write.")
        # Get all nodes from device_status measurement
        device_status_query = "SELECT LAST(field_status) FROM device_status GROUP BY tag_mac_address"
        device_status_result = influx_client.query(device_status_query)

        if not device_status_result:
            logging.warning("No device status data found in the database.")
            return

        # Iterate over each node
        for series in device_status_result.raw.get('series', []):
            mac_address = series['tags']['tag_mac_address']
            last_status = series['values'][0][1]
            json_body = [{
                "measurement": "device_status",
                "tags": {
                    "tag_mac_address": mac_address,
                    "tag_external_ip": "unknown"
                },
                "time": datetime.utcnow().isoformat() + 'Z',
                "fields": {
                    "field_status": last_status
                }
            }]
            influx_client.write_points(json_body)
            logging.info(f"Heartbeat status for {mac_address} reaffirmed as '{last_status}'.")
    except Exception as e:
        logging.error(f"Error during heartbeat write: {e}")

def update_ui(stdscr):
    stdscr.clear()
    stdscr.addstr(0, 0, "="*100)
    stdscr.addstr(1, 0, "VeriNexus Server Monitoring - Press 'q' to quit".center(100))
    stdscr.addstr(2, 0, "="*100)
    stdscr.addstr(3, 0, f"{'MAC Address':<20} {'Status':<15} {'Last Update':<25} {'Info':<35}")
    stdscr.addstr(4, 0, "-"*100)

    row = 5

    # Display node information
    for mac_address in node_statuses.keys():
        last_status = node_statuses[mac_address]
        last_update = last_status_updates.get(mac_address, 'Unknown')
        info = f"Last checked at {last_update}"
        stdscr.addstr(row, 0, f"{mac_address:<20} {last_status:<15} {last_update:<25} {info:<35}")
        row += 1

    # Display suspended devices
    suspended_query = "SELECT * FROM suspended_devices"
    suspended_result = influx_client.query(suspended_query)
    suspended_macs = []
    if suspended_result:
        for series in suspended_result.raw.get('series', []):
            if 'tags' in series and 'tag_mac_address' in series['tags']:
                mac_address = series['tags']['tag_mac_address']
                suspended_macs.append(mac_address)

    if suspended_macs:
        stdscr.addstr(row + 1, 0, f"Suspended Devices:")
        row += 2
        for mac in suspended_macs:
            stdscr.addstr(row, 0, f"{mac}")
            row += 1
    else:
        stdscr.addstr(row + 1, 0, "No Suspended Devices")
        row += 2

    # Display countdown timers
    stdscr.addstr(row, 0, f"Next Keepalive Check In: {next_keepalive_check_in} seconds")
    stdscr.addstr(row + 1, 0, f"Next Heartbeat Write In: {next_heartbeat_in} seconds")

    # Display settings
    stdscr.addstr(row + 3, 0, "="*100)
    stdscr.addstr(row + 4, 0, "Settings:")
    settings_lines = settings_display.split('\n')
    for idx, line in enumerate(settings_lines):
        stdscr.addstr(row + 5 + idx, 0, line)
    stdscr.addstr(row + 5 + len(settings_lines), 0, "="*100)

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
