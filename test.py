"""
File Name: test.py
Version: 2.8
Date: November 11, 2024
Description:
    This Python script monitors network connectivity to the internet, performs device status checks,
    writes aggregated data to InfluxDB, synchronizes time using NTP, and manages suspended status.
    It uses `curses` for a dynamic display and allows simulating network disconnection and reconnection with key presses.
    It implements efficient data storage and a clean exit mechanism.
    Version 2.8 enhances the UI for better clarity and usability, removes unused settings from the UI,
    fixes missing or incorrect data, and reorganizes the UI for better readability.

Changelog:
    Version 2.7 - Aligned script settings with settings measurement, added external IP to keepalive measurement,
                  enhanced UI with settings display and countdown timers, and updated version and date.
    Version 2.8 - Removed unused settings from the UI, fixed missing or incorrect data fields,
                  reorganized the UI for better presentation, and ensured all functionality is retained.
"""

import time
from datetime import datetime, timezone, timedelta
import logging
from logging.handlers import RotatingFileHandler
from influxdb import InfluxDBClient
import ntplib
import curses
import signal
import netifaces
import sys
import requests
import subprocess

# Setup logging with a rotating file handler
log_handler = RotatingFileHandler('verinexus_monitoring.log', maxBytes=5*1024*1024, backupCount=3)
logging.basicConfig(
    handlers=[log_handler],
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# Global variables to store status information
status_info = {
    "uptime": 0,
    "downtime": 0,
    "last_up": None,
    "last_down": None,
    "last_db_write": None,
    "settings": {},
    "current_status": "unknown",
    "last_write_status": "Not yet written",
    "external_ip": None,
    "local_ip": None,
    "version": "2.8",
    "uptime_percentage_hour": 0.0,
    "uptime_percentage_day": 0.0,
    "uptime_percentage_month": 0.0,
    "is_suspended": False,
    "settings_display": "",
    "next_keepalive_in": 0,
    "next_db_write_in": 0,
    "next_status_check_in": 0,
}

# Local cache for status events
status_events = []

# Function to get the active MAC address
def get_mac_address():
    try:
        for iface in netifaces.interfaces():
            ifaddresses = netifaces.ifaddresses(iface)
            if netifaces.AF_INET in ifaddresses:
                ip = ifaddresses[netifaces.AF_INET][0]['addr']
                if ip != '127.0.0.1':
                    mac = ifaddresses[netifaces.AF_LINK][0]['addr']
                    status_info["local_ip"] = ip  # Store local IP address
                    return mac
        return "unknown"
    except Exception as e:
        logging.error(f"Error retrieving MAC address: {e}")
        return "unknown"

# Function to get external IP address
def get_external_ip():
    try:
        ip = requests.get('https://api.ipify.org', timeout=5).text
        return ip
    except Exception as e:
        logging.error(f"Error retrieving external IP address: {e}")
        return "unknown"

# Use MAC address as device identifier
DEVICE_MAC = get_mac_address()
EXTERNAL_IP = get_external_ip()
status_info["external_ip"] = EXTERNAL_IP

# InfluxDB Configuration
INFLUXDB_SERVER = "speedtest.verinexus.com"
INFLUXDB_PORT = 8086
INFLUXDB_DB = "speedtest_db_clean"

# Initialize InfluxDB Client
try:
    influx_client = InfluxDBClient(host=INFLUXDB_SERVER, port=INFLUXDB_PORT, database=INFLUXDB_DB)
    logging.info("Successfully connected to InfluxDB.")
except Exception as e:
    logging.critical(f"Failed to connect to InfluxDB: {e}")
    sys.exit("Failed to connect to InfluxDB. Please check your configuration.")

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
                if isinstance(setting_value, str):
                    setting_value = setting_value.strip('"')
                settings[setting_name] = setting_value
            logging.info("Settings successfully retrieved from InfluxDB.")
            status_info["settings"] = settings
            # Create a string representation for UI display
            settings_descriptions = {
                "NTP_SERVER": "NTP server for time synchronization",
                "POLL_INTERVAL": "Interval for checking status (seconds)",
                "DETECTION_ENDPOINT": "Endpoint to check for internet connectivity",
                "KEEPALIVE": "Interval for keepalive messages (seconds)",
                "DB_UPDATE": "Interval for updating database (seconds)",
            }
            relevant_settings = ["DETECTION_ENDPOINT", "NTP_SERVER", "KEEPALIVE", "DB_UPDATE", "POLL_INTERVAL"]
            settings_display_lines = []
            for k in relevant_settings:
                v = settings.get(k, "Not Set")
                description = settings_descriptions.get(k, "No description available")
                settings_display_lines.append(f"{k}: {v} ({description})")
            status_info["settings_display"] = "\n".join(settings_display_lines)
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
        logging.info(f"Time synchronized to {ntp_time.isoformat()} using NTP server {ntp_server}")
        # Note: Setting system time requires administrative privileges and is system dependent.
    except Exception as e:
        logging.warning(f"Failed to synchronize time using NTP server {ntp_server}: {e}")

# Function to check if the device is suspended
def check_if_suspended():
    try:
        query = f"SELECT * FROM suspended_devices WHERE tag_mac_address='{DEVICE_MAC}'"
        result = influx_client.query(query)
        if result:
            logging.info(f"Device {DEVICE_MAC} is suspended.")
            return True
        else:
            logging.info(f"Device {DEVICE_MAC} is not suspended.")
            return False
    except Exception as e:
        logging.error(f"Failed to check suspended status: {e}")
        return False

# Function to write keepalive to InfluxDB
def write_keepalive():
    try:
        # Delete old keepalive entries for this MAC address
        delete_query = f"DELETE FROM keepalive WHERE tag_mac_address='{DEVICE_MAC}'"
        influx_client.query(delete_query)
        logging.debug(f"Old keepalive entries deleted for {DEVICE_MAC}.")

        # Write new keepalive with external IP
        json_body = [{
            "measurement": "keepalive",
            "tags": {
                "tag_mac_address": DEVICE_MAC,
                "tag_external_ip": EXTERNAL_IP if EXTERNAL_IP else "unknown"
            },
            "time": datetime.utcnow().isoformat() + 'Z',
            "fields": {
                "field_mac_address": DEVICE_MAC
            }
        }]
        influx_client.write_points(json_body)
        logging.debug(f"Keepalive written for {DEVICE_MAC} with external IP {EXTERNAL_IP}.")
    except Exception as e:
        logging.error(f"Failed to write keepalive: {e}")

# Function to get last status from the database
def get_last_status_from_db():
    try:
        query = f"SELECT LAST(field_status) FROM device_status WHERE tag_mac_address='{DEVICE_MAC}'"
        result = influx_client.query(query)
        if result:
            last_status_series = result.raw.get('series', [])[0]
            db_status = last_status_series['values'][0][1]
            return db_status
        else:
            return None
    except Exception as e:
        logging.error(f"Error retrieving last status from DB: {e}")
        return None

# Function to cache and write status to InfluxDB
def write_status_to_influxdb(force_write=False):
    try:
        if status_events or force_write:
            json_body = []
            for event in status_events:
                json_body.append({
                    "measurement": "device_status",
                    "tags": {
                        "tag_mac_address": DEVICE_MAC,
                        "tag_external_ip": EXTERNAL_IP
                    },
                    "time": event["timestamp"],
                    "fields": {
                        "field_status": event["status"]
                    }
                })
            influx_client.write_points(json_body)
            status_info["last_db_write"] = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
            status_info["last_write_status"] = f"Wrote {len(json_body)} event(s)"
            logging.debug(f"Wrote {len(json_body)} event(s) to InfluxDB.")
            status_events.clear()  # Clear the cache after successful write
        else:
            logging.debug("No status events to write.")
    except Exception as e:
        status_info["last_write_status"] = f"Write failed: {e}"
        logging.error(f"Failed to write status to InfluxDB: {e}")

# Function to check internet connectivity using DETECTION_ENDPOINT
def check_internet_connectivity(endpoint):
    try:
        try:
            subprocess.check_call(["ping", "-c", "1", "-W", "1", endpoint], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
        except subprocess.CalledProcessError:
            return False
    except Exception as e:
        logging.debug(f"Internet connectivity check failed using endpoint {endpoint}: {e}")
        return False

# Function to handle clean exit
def clean_exit(signum, frame):
    logging.info("Exiting gracefully...")
    write_status_to_influxdb(force_write=True)
    curses.endwin()
    sys.exit(0)

# Function to calculate uptime percentages over specific periods
def calculate_uptime_percentages():
    try:
        periods = {
            "hour": 3600,
            "day": 86400,
            "month": 2592000  # 30 days
        }
        for period_name, period_seconds in periods.items():
            now = datetime.utcnow().replace(tzinfo=timezone.utc)
            period_start = now - timedelta(seconds=period_seconds)

            # Query status changes in the period
            query = f"""
                SELECT * FROM device_status
                WHERE time > '{period_start.isoformat()}Z' AND tag_mac_address='{DEVICE_MAC}'
                ORDER BY time ASC
            """
            result = influx_client.query(query)
            points = list(result.get_points())

            if not points:
                current_status = status_info["current_status"]
                uptime_percentage = 100.0 if current_status == 'up' else 0.0
            else:
                total_time = 0
                uptime = 0
                last_time = period_start
                last_status = None

                for point in points:
                    time_point = datetime.strptime(point['time'], '%Y-%m-%dT%H:%M:%S.%fZ').replace(tzinfo=timezone.utc)
                    duration = (time_point - last_time).total_seconds()
                    if last_status == 'up':
                        uptime += duration
                    total_time += duration
                    last_time = time_point
                    last_status = point['field_status']

                # Account for time since last point
                duration = (now - last_time).total_seconds()
                if last_status == 'up':
                    uptime += duration
                total_time += duration

                if total_time > 0:
                    uptime_percentage = (uptime / total_time) * 100
                else:
                    uptime_percentage = 0.0

            status_info[f'uptime_percentage_{period_name}'] = uptime_percentage
    except Exception as e:
        logging.error(f"Error calculating uptime percentages: {e}")
        for period_name in ["hour", "day", "month"]:
            status_info[f'uptime_percentage_{period_name}'] = 0.0

# Monitoring loop with full functionality
def monitor_device(stdscr):
    settings = get_settings()
    if not settings:
        logging.critical("No settings available. Exiting monitoring loop.")
        stdscr.addstr(0, 0, "No settings available. Exiting...")
        stdscr.refresh()
        time.sleep(2)
        return

    # Update settings in status_info
    status_info["settings"] = settings

    # Synchronize time using NTP_SERVER
    ntp_server = settings.get("NTP_SERVER", "pool.ntp.org")
    synchronize_time(ntp_server)

    # Read settings and map them
    detection_endpoint = settings.get("DETECTION_ENDPOINT", "8.8.8.8")
    try:
        status_interval = int(settings.get("POLL_INTERVAL", "2"))
    except ValueError:
        status_interval = 2
        logging.warning("Invalid POLL_INTERVAL setting. Defaulting to 2 seconds.")

    try:
        keepalive_interval = int(settings.get("KEEPALIVE", "60"))
    except ValueError:
        keepalive_interval = 60
        logging.warning("Invalid KEEPALIVE setting. Defaulting to 60 seconds.")

    try:
        write_interval = int(settings.get("DB_UPDATE", "60"))
    except ValueError:
        write_interval = 60
        logging.warning("Invalid DB_UPDATE setting. Defaulting to 60 seconds.")

    # Log settings usage
    logging.info(f"Using NTP_SERVER: {ntp_server}")
    logging.info(f"Using DETECTION_ENDPOINT: {detection_endpoint}")
    logging.info(f"Using POLL_INTERVAL: {status_interval}")
    logging.info(f"Using KEEPALIVE: {keepalive_interval}")
    logging.info(f"Using DB_UPDATE: {write_interval}")

    last_keepalive_time = time.time()
    last_write_time = time.time()
    last_status = None
    last_status_written = False

    # Initialize curses
    curses.curs_set(0)  # Hide the cursor
    stdscr.nodelay(1)  # Non-blocking input
    stdscr.timeout(1000)  # Refresh every second

    simulate_disconnect = False
    is_running = True

    # Check if the device is suspended
    status_info["is_suspended"] = check_if_suspended()

    # Write initial keepalive
    write_keepalive()
    last_keepalive_time = time.time()

    # Get last status from database
    last_db_status = get_last_status_from_db()
    status_info["db_current_status"] = last_db_status if last_db_status else "unknown"

    status_check_timer = time.time()

    while is_running:
        try:
            key = stdscr.getch()
            if key == ord('d'):
                simulate_disconnect = True
            elif key == ord('c'):
                simulate_disconnect = False
            elif key == ord('q'):
                is_running = False
                clean_exit(None, None)

            current_time = datetime.now(timezone.utc).isoformat()
            current_epoch_time = time.time()

            # Update countdown timers
            status_info["next_keepalive_in"] = max(0, int(keepalive_interval - (current_epoch_time - last_keepalive_time)))
            status_info["next_db_write_in"] = max(0, int(write_interval - (current_epoch_time - last_write_time)))
            status_info["next_status_check_in"] = max(0, int(status_interval - (current_epoch_time - status_check_timer)))

            # Write keepalive at the specified interval
            if current_epoch_time - last_keepalive_time >= keepalive_interval:
                write_keepalive()
                last_keepalive_time = current_epoch_time

            # Check internet connectivity at POLL_INTERVAL
            if current_epoch_time - status_check_timer >= status_interval:
                if not simulate_disconnect and check_internet_connectivity(detection_endpoint):
                    status_info["uptime"] += status_interval
                    if status_info["current_status"] != "up":
                        status_info["last_up"] = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
                    current_status = "up"
                else:
                    status_info["downtime"] += status_interval
                    if status_info["current_status"] != "down":
                        status_info["last_down"] = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
                    current_status = "down"

                # Check if the device is suspended
                status_info["is_suspended"] = check_if_suspended()

                # If the device is suspended, set status to 'maintenance'
                if status_info["is_suspended"]:
                    current_status = "maintenance"

                # Get last status from database
                last_db_status = get_last_status_from_db()
                status_info["db_current_status"] = last_db_status if last_db_status else "unknown"

                # Update status_info
                status_info["current_status"] = current_status

                # Aggregate status events only if status changes
                if current_status != last_db_status:
                    status_events.append({"status": current_status, "timestamp": current_time})
                    last_status_written = False

                status_check_timer = current_epoch_time

            # Write to InfluxDB at the specified interval or if status changed
            if current_epoch_time - last_write_time >= write_interval or not last_status_written:
                write_status_to_influxdb()
                last_write_time = current_epoch_time
                last_status_written = True
                status_info["last_db_write"] = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")

            # Calculate uptime percentages over periods
            calculate_uptime_percentages()

            # Update the display
            stdscr.clear()
            stdscr.addstr(0, 0, f"VeriNexus Monitoring System - Version {status_info['version']}".center(80))
            stdscr.addstr(1, 0, "="*80)

            # Device Information
            stdscr.addstr(2, 0, "Device Information:")
            stdscr.addstr(3, 0, f"MAC Address: {DEVICE_MAC}")
            stdscr.addstr(4, 0, f"External IP: {EXTERNAL_IP}")
            stdscr.addstr(5, 0, f"Local IP: {status_info['local_ip']}")
            stdscr.addstr(6, 0, f"Suspended: {'Yes' if status_info['is_suspended'] else 'No'}")

            # Uptime and Downtime
            stdscr.addstr(8, 0, "Uptime and Downtime:")
            stdscr.addstr(9, 0, f"Uptime: {str(timedelta(seconds=status_info['uptime']))}")
            stdscr.addstr(10, 0, f"Downtime: {str(timedelta(seconds=status_info['downtime']))}")
            stdscr.addstr(11, 0, f"Uptime Last Hour: {status_info['uptime_percentage_hour']:.2f}%")
            stdscr.addstr(12, 0, f"Uptime Last Day: {status_info['uptime_percentage_day']:.2f}%")
            stdscr.addstr(13, 0, f"Uptime Last Month: {status_info['uptime_percentage_month']:.2f}%")
            stdscr.addstr(14, 0, f"Last Up: {status_info['last_up']}")
            stdscr.addstr(15, 0, f"Last Down: {status_info['last_down']}")

            # Database Information
            stdscr.addstr(17, 0, "Database Information:")
            stdscr.addstr(18, 0, f"Last DB Write: {status_info['last_db_write']}")
            stdscr.addstr(19, 0, f"Last Write Status: {status_info['last_write_status']}")

            # Timers
            stdscr.addstr(21, 0, "Timers:")
            stdscr.addstr(22, 0, f"Next Keepalive Write: {status_info['next_keepalive_in']}s")
            stdscr.addstr(23, 0, f"Next DB Write: {status_info['next_db_write_in']}s")
            stdscr.addstr(24, 0, f"Next Status Check: {status_info['next_status_check_in']}s")

            # Relevant Settings
            stdscr.addstr(26, 0, "Relevant Settings:")
            settings_lines = status_info["settings_display"].split('\n')
            for idx, line in enumerate(settings_lines):
                stdscr.addstr(27 + idx, 0, line)

            stdscr.addstr(27 + len(settings_lines), 0, "="*80)
            stdscr.addstr(28 + len(settings_lines), 0, "Press 'd' to simulate disconnect, 'c' to reconnect, 'q' to quit.".center(80))
            stdscr.refresh()

            time.sleep(1)
        except Exception as e:
            logging.error(f"Error in monitoring loop: {e}")
            stdscr.addstr(29 + len(settings_lines), 0, f"Error: {e}")
            stdscr.refresh()
            time.sleep(1)

# Handle clean exit on SIGINT (Ctrl+C)
signal.signal(signal.SIGINT, clean_exit)
signal.signal(signal.SIGTERM, clean_exit)

# Start the monitoring loop with curses
curses.wrapper(monitor_device)
