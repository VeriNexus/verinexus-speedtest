"""
File Name: check.py
Version: 2.0
Date: November 10, 2024
Description:
    This Python script runs on the server to monitor remote nodes posting keepalive updates.
    If a node fails to post a keepalive within a specified NODE_UPDATE interval, the script
    proactively updates the node's status to 'down' or 'maintenance' in the database, depending
    on whether the node is suspended. It also ensures that if there is no status update within
    the HEARTBEAT interval, it writes the same status as the last known status.
    The script writes status changes only when necessary to minimize database writes.
    It includes a curses-based UI for real-time status display, utilizes settings from the
    'settings' measurement, and adheres to consistent database field and tag naming conventions.
    Version 2.0 fixes issues with node status display, initializes node statuses on startup,
    adds detailed reporting and debugging information, and ensures accurate time handling.

Changelog:
    Version 1.9 - Fixed node status display, removed extra quotation marks in settings, corrected time handling,
                  ensured accurate 'up'/'down' status based on `keepalive` entries.
    Version 2.0 - Initialized node statuses on startup, added detailed reporting and debugging information,
                  included data from `suspended_devices` and `keepalive`, improved time handling,
                  and updated version and date.
"""

import time
from datetime import datetime, timezone, timedelta
from influxdb import InfluxDBClient
import curses
import signal
import sys
import ntplib
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

# Global variable to store node statuses and settings
node_statuses = {}
settings_info = {}
last_status_updates = {}
suspended_devices = set()
keepalive_info = {}

# Function to read settings from InfluxDB in key-value format
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
            return settings
        else:
            logging.error("Settings query returned no results.")
            return None
    except Exception as e:
        logging.error(f"Failed to retrieve settings from InfluxDB: {e}")
        return None

# Function to synchronize time using NTP
def synchronize_time(ntp_server):
    try:
        client = ntplib.NTPClient()
        response = client.request(ntp_server, version=3)
        ntp_time = datetime.fromtimestamp(response.tx_time, timezone.utc)
        logging.info(f"Time synchronized to {ntp_time.isoformat()}")
        # Note: Setting system time requires administrative privileges and is system dependent.
    except Exception as e:
        logging.warning(f"Failed to synchronize time using NTP: {e}")

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

        heartbeat_interval = int(settings.get("HEARTBEAT", "300"))
        node_update_interval = int(settings.get("NODE_UPDATE", "120"))

        settings_info["display"] = "\n".join([f"{k}: {v}" for k, v in settings.items()])

        # Timing variables
        last_node_check_time = time.time()
        last_heartbeat_check_time = time.time()

        # Countdown timers
        next_node_check = node_update_interval
        next_heartbeat_check = heartbeat_interval

        # Initialize node statuses
        initialize_node_statuses()

        while is_running:
            try:
                key = stdscr.getch()
                if key == ord('q'):
                    is_running = False
                    clean_exit(None, None)

                current_time = time.time()

                # Update countdown timers
                next_node_check = max(0, int(node_update_interval - (current_time - last_node_check_time)))
                next_heartbeat_check = max(0, int(heartbeat_interval - (current_time - last_heartbeat_check_time)))

                # Perform NODE_UPDATE check
                if current_time - last_node_check_time >= node_update_interval:
                    process_node_update(node_update_interval)
                    last_node_check_time = current_time

                # Perform HEARTBEAT check
                if current_time - last_heartbeat_check_time >= heartbeat_interval:
                    process_heartbeat()
                    last_heartbeat_check_time = current_time

                # Update UI
                update_ui(stdscr, next_node_check, next_heartbeat_check)
                time.sleep(1)
            except Exception as e:
                logging.error(f"Error in monitoring loop: {e}")
                stdscr.addstr(0, 0, f"Error: {e}")
                stdscr.refresh()
                time.sleep(1)
    except Exception as e:
        logging.error(f"Error in check_node_status: {e}")
        stdscr.addstr(0, 0, f"Critical Error: {e}")
        stdscr.refresh()
        time.sleep(2)

# Function to initialize node statuses on startup
def initialize_node_statuses():
    try:
        # Get latest statuses from device_status measurement
        device_status_query = "SELECT LAST(field_status) FROM device_status GROUP BY tag_mac_address"
        device_status_result = influx_client.query(device_status_query)
        if device_status_result:
            for series in device_status_result.raw.get('series', []):
                if 'tags' in series and 'tag_mac_address' in series['tags']:
                    mac_address = series['tags']['tag_mac_address']
                    last_status = series['values'][0][1]
                    node_statuses[mac_address] = last_status
                    last_status_time_str = series['values'][0][0]
                    try:
                        last_status_time = datetime.strptime(last_status_time_str, '%Y-%m-%dT%H:%M:%S.%fZ').replace(tzinfo=timezone.utc)
                    except ValueError:
                        last_status_time = datetime.strptime(last_status_time_str, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
                    last_status_updates[mac_address] = last_status_time
            logging.info("Node statuses initialized from device_status measurement.")
        else:
            logging.warning("No device status entries found during initialization.")

        # Fetch suspended devices
        fetch_suspended_devices()

        # Fetch keepalive information
        fetch_keepalive_info()
    except Exception as e:
        logging.error(f"Error during initialization: {e}")

# Function to fetch suspended devices
def fetch_suspended_devices():
    try:
        suspended_query = "SELECT * FROM suspended_devices"
        suspended_result = influx_client.query(suspended_query)
        suspended_devices.clear()
        if suspended_result:
            for series in suspended_result.raw.get('series', []):
                if 'tags' in series and 'tag_mac_address' in series['tags']:
                    mac_address = series['tags']['tag_mac_address']
                    suspended_devices.add(mac_address)
            logging.info("Suspended devices fetched successfully.")
        else:
            logging.info("No suspended devices found.")
    except Exception as e:
        logging.error(f"Error fetching suspended devices: {e}")

# Function to fetch keepalive information
def fetch_keepalive_info():
    try:
        keepalive_query = "SELECT * FROM keepalive"
        keepalive_result = influx_client.query(keepalive_query)
        keepalive_info.clear()
        if keepalive_result:
            for series in keepalive_result.raw.get('series', []):
                if 'tags' in series and 'tag_mac_address' in series['tags']:
                    mac_address = series['tags']['tag_mac_address']
                    last_time_str = series['values'][0][0]
                    try:
                        last_time = datetime.strptime(last_time_str, '%Y-%m-%dT%H:%M:%S.%fZ').replace(tzinfo=timezone.utc)
                    except ValueError:
                        last_time = datetime.strptime(last_time_str, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)
                    keepalive_info[mac_address] = last_time
            logging.info("Keepalive information fetched successfully.")
        else:
            logging.warning("No keepalive entries found.")
    except Exception as e:
        logging.error(f"Error fetching keepalive information: {e}")

# Function to process NODE_UPDATE
def process_node_update(node_update_interval):
    logging.info("Performing NODE_UPDATE check.")
    now_utc = datetime.utcnow().replace(tzinfo=timezone.utc)
    fetch_keepalive_info()
    fetch_suspended_devices()
    all_macs = set(node_statuses.keys()).union(keepalive_info.keys())

    for mac_address in all_macs:
        last_keepalive_time = keepalive_info.get(mac_address, None)
        time_since_keepalive = (now_utc - last_keepalive_time).total_seconds() if last_keepalive_time else None

        is_suspended = mac_address in suspended_devices

        # Get last known status
        last_status = node_statuses.get(mac_address, 'unknown')

        # Determine the new status
        if is_suspended:
            new_status = 'maintenance'
        elif last_keepalive_time and time_since_keepalive <= node_update_interval:
            new_status = 'up'
        else:
            new_status = 'down'

        # Write the new status only if it has changed
        if last_status != new_status:
            json_body = [{
                "measurement": "device_status",
                "tags": {
                    "tag_mac_address": mac_address,
                    "tag_external_ip": "unknown"
                },
                "time": datetime.utcnow().isoformat() + 'Z',
                "fields": {
                    "field_status": new_status
                }
            }]
            influx_client.write_points(json_body)
            node_statuses[mac_address] = new_status
            last_status_updates[mac_address] = datetime.utcnow().replace(tzinfo=timezone.utc)
            logging.info(f"Status for {mac_address} updated to '{new_status}' due to NODE_UPDATE check.")
        else:
            logging.debug(f"No status change for {mac_address} during NODE_UPDATE check.")

# Function to process HEARTBEAT
def process_heartbeat():
    logging.info("Performing HEARTBEAT check.")
    now_utc = datetime.utcnow().replace(tzinfo=timezone.utc)
    for mac_address in node_statuses.keys():
        last_status = node_statuses[mac_address]
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
        last_status_updates[mac_address] = now_utc
        logging.info(f"Status for {mac_address} reaffirmed as '{last_status}' due to HEARTBEAT check.")

# Function to update the UI
def update_ui(stdscr, next_node_check, next_heartbeat_check):
    stdscr.clear()
    stdscr.addstr(0, 0, "="*100)
    stdscr.addstr(1, 0, "VeriNexus Server Monitoring - Press 'q' to quit".center(100))
    stdscr.addstr(2, 0, "="*100)
    stdscr.addstr(3, 0, f"{'MAC Address':<20} {'Status':<15} {'Last Update':<25} {'Keepalive':<25} {'Info':<15}")
    stdscr.addstr(4, 0, "-"*100)

    row = 5

    now_utc = datetime.utcnow().replace(tzinfo=timezone.utc)

    # Display node information
    for mac_address in node_statuses.keys():
        last_status = node_statuses[mac_address]
        last_status_time = last_status_updates.get(mac_address, None)
        last_status_time_str = last_status_time.strftime('%Y-%m-%d %H:%M:%S') if last_status_time else 'Unknown'

        last_keepalive_time = keepalive_info.get(mac_address, None)
        last_keepalive_time_str = last_keepalive_time.strftime('%Y-%m-%d %H:%M:%S') if last_keepalive_time else 'No Keepalive'

        info = ''
        if mac_address in suspended_devices:
            info = 'Suspended'
        elif last_status == 'down':
            info = 'No recent keepalive'
        else:
            time_since_keepalive = (now_utc - last_keepalive_time).total_seconds() if last_keepalive_time else None
            if time_since_keepalive is not None:
                info = f'{int(time_since_keepalive)}s since keepalive'
            else:
                info = 'No keepalive info'

        stdscr.addstr(row, 0, f"{mac_address:<20} {last_status:<15} {last_status_time_str:<25} {last_keepalive_time_str:<25} {info:<15}")
        row += 1

    # Display suspended devices
    if suspended_devices:
        stdscr.addstr(row + 1, 0, f"Suspended Devices:")
        row += 2
        for mac in suspended_devices:
            stdscr.addstr(row, 0, f"{mac}")
            row += 1
    else:
        stdscr.addstr(row + 1, 0, "No Suspended Devices")
        row += 2

    # Display countdown timers
    stdscr.addstr(row, 0, f"Next NODE_UPDATE check in: {next_node_check} seconds")
    stdscr.addstr(row + 1, 0, f"Next HEARTBEAT check in: {next_heartbeat_check} seconds")

    # Display settings
    stdscr.addstr(row + 3, 0, "="*100)
    stdscr.addstr(row + 4, 0, "Settings:")
    settings_lines = settings_info["display"].split('\n')
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