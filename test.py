"""
File Name: test.py
Version: 2.7
Date: November 10, 2024
Description:
    This Python script monitors network connectivity to the internet, performs device status checks,
    writes aggregated data to InfluxDB, synchronizes time using NTP, and sends email alerts when necessary.
    It uses `curses` for a dynamic display and allows simulating network disconnection and reconnection with key presses.
    It implements efficient data storage and a clean exit mechanism.
    It has been updated to display settings from the InfluxDB 'settings' measurement, utilize these settings in the script,
    fix the availability calculations, and enhance the UI for better clarity and aesthetics.

Changelog:
    Version 1.0 - Initial release with console-based output and simulated monitoring logic.
    Version 1.1 - Added full functionality: InfluxDB integration, NTP sync, email alerts, and improved error handling.
    Version 1.2 - Implemented static console display and added logging to verify InfluxDB writes.
    Version 1.3 - Replaced scrolling output with a static display using `curses`.
    Version 1.4 - Added local caching and efficient InfluxDB writes.
    Version 1.5 - Replaced `curses` with simple print statements for debugging.
    Version 2.0 - Improved efficiency, added network disconnection handling, and enhanced alerting system.
    Version 2.1 - Integrated `curses` for static display and added key press handling for simulating network disconnection and reconnection.
    Version 2.2 - Implemented efficient data storage, clean exit mechanism, and used MAC address as device ID.
    Version 2.3 - Fixed MAC address retrieval, improved data writing efficiency, enhanced script termination, and removed redundant fields.
    Version 2.4 - Added version display in UI, detailed database write information, and uptime statistics over last hour, day, and month.
    Version 2.5 - Optimized database writes, implemented keepalive mechanism, handled suspended devices, improved caching, fixed uptime calculations, and enhanced UI.
    Version 2.6 - Deleted old keepalives upon writing new ones, wrote current status at startup, calculated uptime percentages over specific periods, enhanced UI with status write info, displayed DB status and local IP, and improved overall UI aesthetics.
    Version 2.7 - Displayed settings in UI, utilized settings from 'settings' measurement, fixed availability calculations, used NTP_SERVER for time sync, used DETECTION_ENDPOINT for connectivity checks, and improved overall script reliability.
"""

import time
import threading
from datetime import datetime, timezone, timedelta
import logging
from logging.handlers import RotatingFileHandler
from influxdb import InfluxDBClient
import ntplib
from email.mime.text import MIMEText
import smtplib
import subprocess
import curses
import signal
import netifaces
import sys
import os
import requests

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
    "version": "2.7",
    "db_write_details": "",
    "uptime_percentage_hour": 0.0,
    "uptime_percentage_day": 0.0,
    "uptime_percentage_month": 0.0,
    "is_suspended": False,
    "db_current_status": "unknown",
    "status_write_info": "",
    "settings_display": "",
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
        query = "SELECT LAST(*) FROM settings"
        result = influx_client.query(query)
        settings = {}
        if result:
            for point in result.get_points():
                for key in point:
                    if key.startswith('field_'):
                        setting_name = key.replace('field_', '')
                        settings[setting_name] = point[key]
        logging.info("Settings successfully retrieved from InfluxDB.")
        status_info["settings"] = settings
        # Create a string representation for UI display
        settings_display = "\n".join([f"{k}: {v}" for k, v in settings.items()])
        status_info["settings_display"] = settings_display
        return settings
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
        # On Unix systems, you might use: subprocess.call(['sudo', 'date', '-s', ntp_time.isoformat()])
    except Exception as e:
        logging.warning(f"Failed to synchronize time using NTP: {e}")

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

        # Write new keepalive
        json_body = [{
            "measurement": "keepalive",
            "tags": {
                "tag_mac_address": DEVICE_MAC
            },
            "time": datetime.utcnow().isoformat() + 'Z',
            "fields": {
                "field_mac_address": DEVICE_MAC
            }
        }]
        influx_client.write_points(json_body)
        logging.debug(f"Keepalive written for {DEVICE_MAC}.")
    except Exception as e:
        logging.error(f"Failed to write keepalive: {e}")

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
            status_info["db_write_details"] = f"Events: {status_events}"
            status_info["status_write_info"] = "Status written due to change or startup."
            logging.debug(f"Wrote {len(json_body)} event(s) to InfluxDB.")
            status_events.clear()  # Clear the cache after successful write
        else:
            status_info["status_write_info"] = "No status change; data not written."
            logging.debug("No status events to write.")
    except Exception as e:
        status_info["last_write_status"] = f"Write failed: {e}"
        status_info["status_write_info"] = f"Failed to write status: {e}"
        logging.error(f"Failed to write status to InfluxDB: {e}")

# Function to send email alerts with cooldown
def send_email_alert(smtp_settings, subject, message, recipients):
    try:
        msg = MIMEText(message)
        msg["Subject"] = subject
        msg["From"] = smtp_settings["email_from"]
        msg["To"] = ", ".join(recipients)
        with smtplib.SMTP(smtp_settings["smtp_server"], int(smtp_settings["smtp_port"])) as server:
            server.starttls()
            server.login(smtp_settings["smtp_login"], smtp_settings["smtp_password"])
            server.sendmail(smtp_settings["email_from"], recipients, msg.as_string())
        logging.info(f"Email alert sent to {', '.join(recipients)}.")
    except Exception as e:
        logging.error(f"Failed to send email alert: {e}")

# Function to check internet connectivity using DETECTION_ENDPOINT
def check_internet_connectivity(endpoint):
    try:
        response = requests.get(endpoint, timeout=5)
        return response.status_code == 200
    except Exception as e:
        logging.debug(f"Internet connectivity check failed: {e}")
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
            "hour": "1h",
            "day": "24h",
            "month": "30d"
        }
        for period_name, period_duration in periods.items():
            query = f"""
                SELECT COUNT(field_status) FROM device_status
                WHERE time > now() - {period_duration} AND tag_mac_address='{DEVICE_MAC}' AND field_status='up'
            """
            total_query = f"""
                SELECT COUNT(field_status) FROM device_status
                WHERE time > now() - {period_duration} AND tag_mac_address='{DEVICE_MAC}'
            """
            up_result = influx_client.query(query)
            total_result = influx_client.query(total_query)

            up_points = list(up_result.get_points())
            total_points = list(total_result.get_points())

            up_count = up_points[0]['count'] if up_points else 0
            total_count = total_points[0]['count'] if total_points else 0

            if total_count > 0:
                uptime_percentage = (up_count / total_count) * 100
            else:
                uptime_percentage = 0.0

            status_info[f'uptime_percentage_{period_name}'] = uptime_percentage
    except Exception as e:
        logging.error(f"Error calculating uptime percentages: {e}")
        for period_name in ["hour", "day", "month"]:
            status_info[f'uptime_percentage_{period_name}'] = 0.0

# Function to get current status from the database
def get_db_current_status():
    try:
        query = f"SELECT LAST(field_status) FROM device_status WHERE tag_mac_address='{DEVICE_MAC}'"
        result = influx_client.query(query)
        if result:
            last_status_series = result.raw.get('series', [])[0]
            db_status = last_status_series['values'][0][1]
            status_info["db_current_status"] = db_status
        else:
            status_info["db_current_status"] = "unknown"
    except Exception as e:
        logging.error(f"Error retrieving DB current status: {e}")
        status_info["db_current_status"] = "unknown"

# Monitoring loop with full functionality
def monitor_device(stdscr):
    settings = get_settings()
    if not settings:
        logging.critical("No settings available. Exiting monitoring loop.")
        return

    # Update settings in status_info
    status_info["settings"] = settings

    # Synchronize time using NTP_SERVER
    ntp_server = settings.get("NTP_SERVER", "pool.ntp.org")
    synchronize_time(ntp_server)

    # Read settings
    detection_endpoint = settings.get("DETECTION_ENDPOINT", "https://www.google.com")
    status_interval = int(settings.get("STATUS_INTERVAL", "2"))
    keepalive_interval = int(settings.get("KEEPALIVE", "30"))
    node_update_interval = int(settings.get("NODE_UPDATE", "60"))

    # Other settings
    alert_threshold = int(settings.get("ALERT_THRESHOLD", "120"))
    email_subject = settings.get("EMAIL_SUBJECT", "Alert")
    email_recipients = settings.get("MAIL_RECIPIENT", "").split(",")
    smtp_settings = {
        "smtp_server": settings.get("SMTP_SERVER", ""),
        "smtp_port": settings.get("SMTP_PORT", "587"),
        "smtp_login": settings.get("SMTP_LOGIN", ""),
        "smtp_password": settings.get("SMTP_PASSWORD", ""),
        "email_from": settings.get("EMAIL_FROM", "")
    }

    last_heartbeat = time.time()
    alert_triggered = False
    last_alert_time = 0  # To implement cooldown for alerts
    alert_cooldown = 300  # 5-minute cooldown period
    last_write_time = time.time()
    last_keepalive_time = time.time()
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

    # Write initial keepalive and status
    write_keepalive()
    current_time = datetime.now(timezone.utc).isoformat()
    initial_status = "up" if check_internet_connectivity(detection_endpoint) else "down"
    status_events.append({"status": initial_status, "timestamp": current_time})
    write_status_to_influxdb(force_write=True)
    get_db_current_status()

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

            # Write keepalive at the specified interval
            if time.time() - last_keepalive_time >= keepalive_interval:
                write_keepalive()
                last_keepalive_time = time.time()

            if time.time() - last_heartbeat > alert_threshold and not alert_triggered:
                if time.time() - last_alert_time > alert_cooldown:
                    send_email_alert(smtp_settings, email_subject, f"Device {DEVICE_MAC} is down.", email_recipients)
                    last_alert_time = time.time()
                alert_triggered = True

            # Check internet connectivity using DETECTION_ENDPOINT
            if not simulate_disconnect and check_internet_connectivity(detection_endpoint):
                last_heartbeat = time.time()
                status_info["uptime"] += status_interval
                status_info["last_up"] = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
                alert_triggered = False
                current_status = "up"
            else:
                status_info["downtime"] += status_interval
                status_info["last_down"] = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
                current_status = "down"

            # Update status_info
            status_info["current_status"] = current_status

            # Check if the device is suspended
            status_info["is_suspended"] = check_if_suspended()

            # If the device is suspended, do not send status updates
            if status_info["is_suspended"]:
                current_status = "maintenance"

            # Aggregate status events only if status changes
            if current_status != last_status:
                status_events.append({"status": current_status, "timestamp": current_time})
                last_status = current_status
                last_status_written = False
            else:
                status_info["status_write_info"] = "No status change; data not written."

            # Write to InfluxDB at the specified interval or if status changed
            if time.time() - last_write_time >= node_update_interval or not last_status_written:
                write_status_to_influxdb()
                last_write_time = time.time()
                last_status_written = True
                get_db_current_status()

            # Calculate uptime percentages over periods
            calculate_uptime_percentages()

            # Update the display
            stdscr.clear()
            stdscr.addstr(0, 0, "="*80)
            stdscr.addstr(1, 0, f"VeriNexus Monitoring System - Version {status_info['version']}".center(80))
            stdscr.addstr(2, 0, "="*80)
            stdscr.addstr(3, 0, f"MAC Address: {DEVICE_MAC}")
            stdscr.addstr(4, 0, f"External IP: {EXTERNAL_IP}")
            stdscr.addstr(5, 0, f"Local IP: {status_info['local_ip']}")
            stdscr.addstr(6, 0, f"Uptime: {str(timedelta(seconds=status_info['uptime']))}")
            stdscr.addstr(7, 0, f"Downtime: {str(timedelta(seconds=status_info['downtime']))}")
            stdscr.addstr(8, 0, f"Uptime Last Hour: {status_info['uptime_percentage_hour']:.2f}%")
            stdscr.addstr(9, 0, f"Uptime Last Day: {status_info['uptime_percentage_day']:.2f}%")
            stdscr.addstr(10, 0, f"Uptime Last Month: {status_info['uptime_percentage_month']:.2f}%")
            stdscr.addstr(11, 0, f"Last Up: {status_info['last_up']}")
            stdscr.addstr(12, 0, f"Last Down: {status_info['last_down']}")
            stdscr.addstr(13, 0, f"Last DB Write: {status_info['last_db_write']}")
            stdscr.addstr(14, 0, f"Last Write Status: {status_info['last_write_status']}")
            stdscr.addstr(15, 0, f"Status Write Info: {status_info['status_write_info']}")
            stdscr.addstr(16, 0, f"Current Status: {status_info['current_status']}")
            stdscr.addstr(17, 0, f"DB Status: {status_info['db_current_status']}")
            stdscr.addstr(18, 0, f"Suspended: {'Yes' if status_info['is_suspended'] else 'No'}")
            stdscr.addstr(19, 0, "="*80)
            stdscr.addstr(20, 0, "Settings:")
            stdscr.addstr(21, 0, status_info["settings_display"])
            stdscr.addstr(22, 0, "="*80)
            stdscr.addstr(23, 0, "Press 'd' to simulate disconnect, 'c' to reconnect, 'q' to quit.".center(80))
            stdscr.refresh()

            time.sleep(status_interval)
        except Exception as e:
            logging.error(f"Error in monitoring loop: {e}")

# Handle clean exit on SIGINT (Ctrl+C)
signal.signal(signal.SIGINT, clean_exit)
signal.signal(signal.SIGTERM, clean_exit)

# Start the monitoring loop with curses
curses.wrapper(monitor_device)
