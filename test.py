"""
File Name: test.py
Version: 2.4
Date: October 30, 2023
Description:
    This Python script monitors network connectivity to the internet, performs device status checks,
    writes aggregated data to InfluxDB, synchronizes time using NTP, and sends email alerts when necessary.
    It uses `curses` for a static display and allows simulating network disconnection and reconnection with key presses.
    It implements efficient data storage and a clean exit mechanism.
    It has been updated to fix MAC address retrieval, improve data writing efficiency, enhance script termination,
    and include uptime statistics and version display in the UI.

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
    "version": "2.4",
    "db_write_details": "",
    "uptime_last_hour": 0,
    "uptime_last_day": 0,
    "uptime_last_month": 0
}

# Local cache for status events
status_events = []

# Function to get the active MAC address
def get_mac_address():
    try:
        for iface in netifaces.interfaces():
            ifaddresses = netifaces.ifaddresses(iface)
            if netifaces.AF_INET in ifaddresses:
                if ifaddresses[netifaces.AF_INET][0]['addr'] != '127.0.0.1':
                    mac = ifaddresses[netifaces.AF_LINK][0]['addr']
                    return mac
        return "unknown"
    except Exception as e:
        logging.error(f"Error retrieving MAC address: {e}")
        return "unknown"

# Function to get external IP address
def get_external_ip():
    try:
        ip = requests.get('https://api.ipify.org').text
        return ip
    except Exception as e:
        logging.error(f"Error retrieving external IP address: {e}")
        return "unknown"

# Use MAC address as device identifier
DEVICE_MAC = get_mac_address()
EXTERNAL_IP = get_external_ip()
status_info["external_ip"] = EXTERNAL_IP

# InfluxDB Configuration
INFLUXDB_SERVER = "http://speedtest.verinexus.com:8086"
INFLUXDB_DB = "speedtest_db_clean"

# Initialize InfluxDB Client
try:
    influx_client = InfluxDBClient(host="speedtest.verinexus.com", port=8086, database=INFLUXDB_DB)
    logging.info("Successfully connected to InfluxDB.")
except Exception as e:
    logging.critical(f"Failed to connect to InfluxDB: {e}")
    sys.exit("Failed to connect to InfluxDB. Please check your configuration.")

# Function to read settings from InfluxDB in key-value format
def get_settings():
    try:
        query = "SELECT * FROM settings ORDER BY time DESC LIMIT 1"
        result = influx_client.query(query)
        settings = {}
        if result:
            for point in result.get_points():
                settings[point["SETTING_NAME"]] = point["SETTING"]
        logging.info("Settings successfully retrieved from InfluxDB.")
        return settings
    except Exception as e:
        logging.error(f"Failed to retrieve settings from InfluxDB: {e}")
        return None

# Function to synchronize time using NTP
def synchronize_time(ntp_server):
    try:
        client = ntplib.NTPClient()
        response = client.request(ntp_server, version=3)
        logging.info("Time successfully synchronized using NTP.")
        return response.tx_time  # NTP time in UTC
    except Exception as e:
        logging.warning(f"Failed to synchronize time using NTP: {e}")
        return time.time()  # Fallback to local time

# Function to cache and write status to InfluxDB
def write_status_to_influxdb():
    try:
        if status_events:
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
            logging.debug(f"Wrote {len(json_body)} event(s) to InfluxDB.")
            status_events.clear()  # Clear the cache after successful write
        else:
            logging.debug("No status events to write.")
    except Exception as e:
        status_info["last_write_status"] = f"Write failed: {e}"
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

# Function to check internet connectivity
def check_internet_connectivity():
    try:
        subprocess.check_call(["ping", "-c", "1", "-W", "1", "8.8.8.8"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except subprocess.CalledProcessError:
        return False

# Function to handle clean exit
def clean_exit(signum, frame):
    logging.info("Exiting gracefully...")
    write_status_to_influxdb()
    curses.endwin()
    sys.exit(0)

# Function to calculate uptime statistics
def calculate_uptime_statistics():
    try:
        now = datetime.utcnow()
        queries = {
            "last_hour": f"SELECT COUNT(field_status) FROM device_status WHERE time > now() - 1h AND tag_mac_address='{DEVICE_MAC}' AND field_status='up'",
            "last_day": f"SELECT COUNT(field_status) FROM device_status WHERE time > now() - 24h AND tag_mac_address='{DEVICE_MAC}' AND field_status='up'",
            "last_month": f"SELECT COUNT(field_status) FROM device_status WHERE time > now() - 30d AND tag_mac_address='{DEVICE_MAC}' AND field_status='up'"
        }
        for period, query in queries.items():
            result = influx_client.query(query)
            points = list(result.get_points())
            if points:
                count = points[0]['count']
                status_info[f'uptime_{period}'] = count * status_info["settings"].get("STATUS_INTERVAL", 2)
            else:
                status_info[f'uptime_{period}'] = 0
    except Exception as e:
        logging.error(f"Error calculating uptime statistics: {e}")

# Monitoring loop with full functionality
def monitor_device(stdscr):
    settings = get_settings()
    if not settings:
        logging.critical("No settings available. Exiting monitoring loop.")
        return

    status_info["settings"] = settings
    ntp_server = settings.get("NTP_SERVER", "pool.ntp.org")
    alert_threshold = int(settings.get("ALERT_THRESHOLD", "120"))
    status_interval = int(settings.get("STATUS_INTERVAL", "2"))
    write_interval = int(settings.get("WRITE_INTERVAL", "60"))
    email_subject = settings.get("EMAIL_SUBJECT", "Alert")
    email_recipients = settings.get("MAIL_RECIPIENT", "").split(",")
    smtp_settings = {
        "smtp_server": settings.get("SMTP_SERVER"),
        "smtp_port": settings.get("SMTP_PORT"),
        "smtp_login": settings.get("SMTP_LOGIN", ""),
        "smtp_password": settings.get("SMTP_PASSWORD", ""),
        "email_from": settings.get("EMAIL_FROM")
    }

    last_heartbeat = time.time()
    alert_triggered = False
    last_alert_time = 0  # To implement cooldown for alerts
    alert_cooldown = 300  # 5-minute cooldown period
    last_write_time = time.time()
    last_stats_time = time.time()

    # Initialize curses
    curses.curs_set(0)  # Hide the cursor
    stdscr.nodelay(1)  # Non-blocking input
    stdscr.timeout(1000)  # Refresh every second

    simulate_disconnect = False
    is_running = True

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
            if time.time() - last_heartbeat > alert_threshold and not alert_triggered:
                if time.time() - last_alert_time > alert_cooldown:
                    send_email_alert(smtp_settings, email_subject, f"Device {DEVICE_MAC} is down.", email_recipients)
                    last_alert_time = time.time()
                alert_triggered = True

            # Check internet connectivity
            if not simulate_disconnect and check_internet_connectivity():
                last_heartbeat = time.time()
                status_info["uptime"] += status_interval
                status_info["last_up"] = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
                alert_triggered = False
                status_info["current_status"] = "up"
            else:
                status_info["downtime"] += status_interval
                status_info["last_down"] = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
                status_info["current_status"] = "down"

            # Aggregate status events
            if not status_events or status_events[-1]["status"] != status_info["current_status"]:
                status_events.append({"status": status_info["current_status"], "timestamp": current_time})

            # Write to InfluxDB at the specified interval
            if time.time() - last_write_time >= write_interval:
                write_status_to_influxdb()
                last_write_time = time.time()

            # Calculate uptime statistics every 5 minutes
            if time.time() - last_stats_time >= 300:
                calculate_uptime_statistics()
                last_stats_time = time.time()

            # Update the display
            stdscr.clear()
            stdscr.addstr(0, 0, "="*70)
            stdscr.addstr(1, 0, f"VeriNexus Monitoring System - Version {status_info['version']}".center(70))
            stdscr.addstr(2, 0, "="*70)
            stdscr.addstr(3, 0, f"MAC Address: {DEVICE_MAC}")
            stdscr.addstr(4, 0, f"External IP: {EXTERNAL_IP}")
            stdscr.addstr(5, 0, f"Uptime: {status_info['uptime']} seconds")
            stdscr.addstr(6, 0, f"Downtime: {status_info['downtime']} seconds")
            stdscr.addstr(7, 0, f"Last Up: {status_info['last_up']}")
            stdscr.addstr(8, 0, f"Last Down: {status_info['last_down']}")
            stdscr.addstr(9, 0, f"Last DB Write: {status_info['last_db_write']}")
            stdscr.addstr(10, 0, f"Last Write Status: {status_info['last_write_status']}")
            stdscr.addstr(11, 0, f"Current Status: {status_info['current_status']}")
            stdscr.addstr(12, 0, f"Uptime Last Hour: {status_info.get('uptime_last_hour', 0)} seconds")
            stdscr.addstr(13, 0, f"Uptime Last Day: {status_info.get('uptime_last_day', 0)} seconds")
            stdscr.addstr(14, 0, f"Uptime Last Month: {status_info.get('uptime_last_month', 0)} seconds")
            stdscr.addstr(15, 0, f"DB Write Details: {status_info['db_write_details']}")
            stdscr.addstr(16, 0, "="*70)
            stdscr.addstr(17, 0, "Press 'd' to simulate disconnect, 'c' to reconnect, 'q' to quit.".center(70))
            stdscr.refresh()

            time.sleep(status_interval)
        except Exception as e:
            logging.error(f"Error in monitoring loop: {e}")

# Handle clean exit on SIGINT (Ctrl+C)
signal.signal(signal.SIGINT, clean_exit)
signal.signal(signal.SIGTERM, clean_exit)

# Start the monitoring loop with curses
curses.wrapper(monitor_device)
