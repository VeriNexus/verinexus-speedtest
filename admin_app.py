# admin_app.py
# Version: 1.23.0
# Date: 06/11/2024
# Description:
# Flask application for managing devices in the VeriNexus Speed Test system.
# Changes:
# - Assigned a unique ID to each endpoint stored as a tag for deletion purposes.
# - Modified delete functionality to use the unique ID tag.
# - Kept all other data stored as fields.
# - UI updated to a professional and security-focused design.
# - All routes and code are included without any omissions.

import logging
from flask import Flask, request, render_template, redirect, url_for, flash, jsonify, session
from influxdb import InfluxDBClient
import ipaddress
import re
import uuid
from datetime import datetime

app = Flask(__name__)
app.secret_key = 'your_secret_key_here'  # Needed for flash messages and sessions

# Configure logging
logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)

# InfluxDB configuration
INFLUXDB_SERVER = '82.165.7.116'
INFLUXDB_PORT = 8086

# Database and Measurement Names
ENDPOINTS_DB = 'speedtest_db_clean'
ENDPOINTS_MEASUREMENT = 'endpoints'
SPEEDTEST_DB = 'speedtest_db_clean'
DEVICES_MEASUREMENT = 'devices'
SPEEDTEST_MEASUREMENT = 'speedtest'

client = InfluxDBClient(host=INFLUXDB_SERVER, port=INFLUXDB_PORT)

def create_database_if_not_exists(db_name):
    databases = client.get_list_database()
    if not any(db['name'] == db_name for db in databases):
        client.create_database(db_name)
        logger.info(f"Database '{db_name}' created.")
    else:
        logger.info(f"Database '{db_name}' already exists.")

    # Add example.com entry in the correct format if measurement is empty
    client.switch_database(db_name)
    measurement_query = f'SELECT COUNT(*) FROM "{ENDPOINTS_MEASUREMENT}"'
    result = client.query(measurement_query)
    if not list(result.get_points()):
        unique_id = str(uuid.uuid4())
        test_data = [
            {
                "measurement": ENDPOINTS_MEASUREMENT,
                "tags": {
                    "tag_id": unique_id
                },
                "fields": {
                    "field_type": "FQDN",
                    "field_endpoint": "example.com",
                    "field_check_ping": True,
                    "field_check_name_resolution": True,
                    "field_check_dns_server": True,
                    "field_check_traceroute": True
                }
            }
        ]
        client.write_points(test_data)
        logger.info("Added default endpoint 'example.com' with unique ID.")

# Ensure the endpoints database exists
create_database_if_not_exists(ENDPOINTS_DB)

@app.route('/')
def home():
    return render_template('home.html', version='1.22.0')

@app.route('/endpoints')
def index():
    client.switch_database(ENDPOINTS_DB)  # Ensure we're on the correct database
    query = f'SELECT * FROM "{ENDPOINTS_MEASUREMENT}"'
    result = client.query(query)
    points = []
    for point in result.get_points():
        endpoint = point.get('field_endpoint')
        unique_id = point.get('tag_id')
        point_data = {
            'id': unique_id,
            'endpoint': endpoint,
            'type': point.get('field_type'),
            'check_ping': point.get('field_check_ping'),
            'check_name_resolution': point.get('field_check_name_resolution'),
            'check_dns_server': point.get('field_check_dns_server'),
            'check_traceroute': point.get('field_check_traceroute')
        }
        points.append(point_data)

    # Retrieve any stored form data from session
    form_data = session.pop('form_data', {})

    return render_template('index.html', points=points, version='1.22.0', form_data=form_data)

@app.route('/add', methods=['POST'])
def add_endpoint():
    endpoint = request.form['endpoint'].strip()
    endpoint_type = request.form['endpoint_type']  # 'IP' or 'FQDN'
    check_ping = 'check_ping' in request.form
    check_name_resolution = 'check_name_resolution' in request.form
    check_dns_server = 'check_dns_server' in request.form
    check_traceroute = 'check_traceroute' in request.form

    # Store form data in session to remember inputs
    session['form_data'] = {
        'endpoint': endpoint,
        'endpoint_type': endpoint_type,
        'check_ping': check_ping,
        'check_name_resolution': check_name_resolution,
        'check_dns_server': check_dns_server,
        'check_traceroute': check_traceroute
    }

    # Validate that at least one test is selected
    if not any([check_ping, check_name_resolution, check_dns_server, check_traceroute]):
        flash("Please select at least one test to be undertaken.", "error")
        return redirect(url_for('index'))

    # Validate the endpoint
    if endpoint_type == 'IP':
        # Validate IP address
        try:
            ipaddress.ip_address(endpoint)
        except ValueError:
            flash("Invalid IP address.", "error")
            return redirect(url_for('index'))
        # For IP addresses, name resolution is not applicable
        check_name_resolution = False
    elif endpoint_type == 'FQDN':
        # Adjusted FQDN validation to allow single-word hostnames
        fqdn_regex = r'^(?=.{1,253}$)(?!:\/\/)[a-zA-Z0-9][a-zA-Z0-9\-\.]{0,251}[a-zA-Z0-9]$'
        if not re.match(fqdn_regex, endpoint):
            flash("Invalid FQDN.", "error")
            return redirect(url_for('index'))
        # Ensure the endpoint does not contain IP addresses or schemes
        try:
            ipaddress.ip_address(endpoint)
            flash("FQDN cannot be an IP address.", "error")
            return redirect(url_for('index'))
        except ValueError:
            pass  # Not an IP address, which is good
        if any(scheme in endpoint.lower() for scheme in ['http://', 'https://']):
            flash("FQDN should not contain 'http://' or 'https://'.", "error")
            return redirect(url_for('index'))
    else:
        flash("Invalid endpoint type.", "error")
        return redirect(url_for('index'))

    client.switch_database(ENDPOINTS_DB)  # Ensure we're on the correct database

    # Check if endpoint already exists
    existing_query = f'SELECT * FROM "{ENDPOINTS_MEASUREMENT}" WHERE "field_endpoint" = \'{endpoint}\' AND "field_type" = \'{endpoint_type}\''
    existing_result = client.query(existing_query)
    existing_points = list(existing_result.get_points())
    if existing_points:
        flash("Endpoint already exists.", "error")
        return redirect(url_for('index'))

    # Generate a unique ID for the endpoint
    unique_id = str(uuid.uuid4())

    # Store endpoint data with unique ID as a tag
    json_body = [
        {
            "measurement": ENDPOINTS_MEASUREMENT,
            "tags": {
                "tag_id": unique_id
            },
            "fields": {
                "field_type": endpoint_type,
                "field_endpoint": endpoint,
                "field_check_ping": check_ping,
                "field_check_name_resolution": check_name_resolution,
                "field_check_dns_server": check_dns_server,
                "field_check_traceroute": check_traceroute
            }
        }
    ]
    client.write_points(json_body)
    flash("Endpoint added successfully.", "success")

    # Remember the type selection for the next entry
    session['form_data'] = {'endpoint_type': endpoint_type}

    return redirect(url_for('index'))

@app.route('/delete', methods=['POST'])
def delete_endpoint():
    endpoint_id = request.form['endpoint_id']
    client.switch_database(ENDPOINTS_DB)  # Ensure we're on the correct database

    logger.debug(f"Attempting to delete endpoint with ID '{endpoint_id}'")

    # Delete the point based on the unique ID tag
    delete_query = f'DELETE FROM "{ENDPOINTS_MEASUREMENT}" WHERE "tag_id" = \'{endpoint_id}\''
    client.query(delete_query)
    logger.debug(f"Deleted endpoint with ID '{endpoint_id}'")

    flash("Endpoint deleted successfully.", "success")
    return redirect(url_for('index'))

@app.route('/claim', methods=['GET'])
def claim_device():
    # Existing code remains unchanged...
    client.switch_database(SPEEDTEST_DB)
    logger.debug(f"Switched to database: {SPEEDTEST_DB}")

    # Get all MAC addresses from the speedtest measurement
    speedtest_query = f'SHOW TAG VALUES FROM "{SPEEDTEST_MEASUREMENT}" WITH KEY = "tag_mac_address"'
    logger.debug(f"Speedtest query: {speedtest_query}")
    speedtest_result = client.query(speedtest_query)
    speedtest_points = list(speedtest_result.get_points())

    if speedtest_points:
        # tag_mac_address is a tag
        speedtest_macs = {point['value'] for point in speedtest_points}
        logger.debug("Retrieved MAC addresses as tags.")
    else:
        # tag_mac_address might be a field
        logger.debug("No MAC addresses found as tags. Trying to retrieve as fields.")
        speedtest_query = f'SELECT DISTINCT("tag_mac_address") FROM "{SPEEDTEST_MEASUREMENT}"'
        speedtest_result = client.query(speedtest_query)
        speedtest_points = list(speedtest_result.get_points())
        speedtest_macs = {point['distinct'] for point in speedtest_points if point['distinct']}
        logger.debug(f"MAC addresses from speedtest measurement: {speedtest_macs}")

    # Get all MAC addresses from the devices measurement
    devices_query = f'SHOW TAG VALUES FROM "{DEVICES_MEASUREMENT}" WITH KEY = "tag_mac_address"'
    logger.debug(f"Devices query: {devices_query}")
    devices_result = client.query(devices_query)
    devices_points = list(devices_result.get_points())

    if devices_points:
        devices_macs = {point['value'] for point in devices_points}
        logger.debug("Retrieved devices MAC addresses as tags.")
    else:
        logger.debug("No devices MAC addresses found as tags. Trying to retrieve as fields.")
        devices_query = f'SELECT DISTINCT("tag_mac_address") FROM "{DEVICES_MEASUREMENT}"'
        devices_result = client.query(devices_query)
        devices_points = list(devices_result.get_points())
        devices_macs = {point['distinct'] for point in devices_points if point['distinct']}
        logger.debug(f"MAC addresses from devices measurement: {devices_macs}")

    # Find unclaimed MAC addresses
    unclaimed_macs = speedtest_macs - devices_macs
    logger.debug(f"Unclaimed MAC addresses: {unclaimed_macs}")

    # Get all devices data from the devices measurement
    devices_data_query = f'SELECT "field_customer_id", "field_customer_name", "field_location" FROM "{DEVICES_MEASUREMENT}"'
    devices_data_result = client.query(devices_data_query)
    devices_data_points = list(devices_data_result.get_points())

    # Build customers dictionary and locations per customer
    customers = {}
    locations = {}
    for point in devices_data_points:
        customer_id = point.get('field_customer_id')
        customer_name = point.get('field_customer_name')
        location = point.get('field_location')
        if customer_id is not None and customer_name:
            customer_id_str = str(int(customer_id))  # Ensure customer_id is treated as integer
            customers[customer_id_str] = customer_name
            if customer_id_str not in locations:
                locations[customer_id_str] = set()
            if location:
                locations[customer_id_str].add(location)

    # Convert sets to lists for JSON serialization
    for customer_id in locations:
        locations[customer_id] = list(locations[customer_id])

    if not unclaimed_macs:
        flash("No MAC addresses available to claim.", "info")

    # Switch back to ENDPOINTS_DB for subsequent operations
    client.switch_database(ENDPOINTS_DB)

    # Pass the data to the template
    return render_template('claim.html', unclaimed_macs=unclaimed_macs, customers=customers, locations=locations, version='1.22.0')

@app.route('/claim', methods=['POST'])
def claim_device_post():
    # Existing code remains unchanged...
    try:
        mac_address = request.form['mac_address']
        customer_option = request.form['customer_option']
        friendly_name = request.form['friendly_name']

        # Switch to the speedtest_db_clean database
        client.switch_database(SPEEDTEST_DB)

        # Initialize variables
        customer_id = None
        customer_name = None
        location = None

        # Handle customer
        if customer_option == 'existing':
            customer_id = request.form['existing_customer_id']
            customer_id = float(customer_id)  # Ensure customer_id is a float for comparison

            # Retrieve customer_name based on customer_id
            customer_query = f'SELECT "field_customer_name" FROM "{DEVICES_MEASUREMENT}" WHERE "field_customer_id" = {customer_id} LIMIT 1'
            customer_result = client.query(customer_query)
            customer_points = list(customer_result.get_points())
            if customer_points:
                customer_name = customer_points[0]['field_customer_name']
            else:
                # Handle error
                logger.error(f"Customer ID {customer_id} not found.")
                flash("Customer not found.", "error")
                return redirect(url_for('claim_device'))

            # Handle location
            location_option = request.form['location_option']
            if location_option == 'existing':
                location = request.form['existing_location']
            elif location_option == 'new':
                location = request.form['new_location_name']
                if not location:
                    logger.error("New location name is required but not provided.")
                    flash("New location name is required.", "error")
                    return redirect(url_for('claim_device'))
            else:
                logger.error("Invalid location option selected.")
                flash("Invalid location option.", "error")
                return redirect(url_for('claim_device'))

        elif customer_option == 'new':
            customer_name = request.form['new_customer_name']
            if not customer_name:
                logger.error("New customer name is required but not provided.")
                flash("New customer name is required.", "error")
                return redirect(url_for('claim_device'))
            # Generate new customer_id
            customer_id_query = f'SELECT MAX("field_customer_id") FROM "{DEVICES_MEASUREMENT}"'
            customer_id_result = client.query(customer_id_query)
            customer_id_points = list(customer_id_result.get_points())
            max_customer_id = 0
            if customer_id_points:
                max_customer_id = customer_id_points[0]['max']
                if max_customer_id is None:
                    max_customer_id = 0
                else:
                    max_customer_id = int(max_customer_id)  # Ensure max_customer_id is treated as integer
            customer_id = max_customer_id + 1

            # For new customer, location is always new
            location = request.form['new_customer_location_name']
            if not location:
                logger.error("Location name is required for new customer but not provided.")
                flash("Location name is required for new customer.", "error")
                return redirect(url_for('claim_device'))
        else:
            logger.error("Invalid customer option selected.")
            flash("Invalid customer option.", "error")
            return redirect(url_for('claim_device'))

        # Validate that friendly_name is unique per customer
        friendly_name_query = f'SELECT * FROM "{DEVICES_MEASUREMENT}" WHERE "field_customer_id" = {customer_id} AND "field_friendly_name" = \'{friendly_name}\''
        friendly_name_result = client.query(friendly_name_query)
        friendly_name_points = list(friendly_name_result.get_points())
        if friendly_name_points:
            # Friendly name already exists for this customer
            logger.error(f"Friendly name '{friendly_name}' already exists for customer ID {customer_id}.")
            flash(f"Friendly name '{friendly_name}' already exists for this customer.", "error")
            return redirect(url_for('claim_device'))

        # Add the claimed device to the devices measurement
        json_body = [
            {
                "measurement": DEVICES_MEASUREMENT,
                "tags": {
                    "tag_mac_address": mac_address
                },
                "fields": {
                    "field_customer_id": float(customer_id),
                    "field_customer_name": customer_name,
                    "field_friendly_name": friendly_name,
                    "field_location": location,
                    "field_mac_address": mac_address
                }
            }
        ]
        client.write_points(json_body)
        logger.info(f"Device with MAC {mac_address} claimed successfully for customer '{customer_name}' (ID: {customer_id}).")
        flash("Device claimed successfully.", "success")

        # Switch back to ENDPOINTS_DB
        client.switch_database(ENDPOINTS_DB)

        return redirect(url_for('claim_device'))
    except Exception as e:
        logger.exception("An error occurred while processing the claim.")
        flash(f"Error: {str(e)}", "error")
        return redirect(url_for('claim_device'))

@app.route('/get_locations', methods=['GET'])
def get_locations():
    # Existing code remains unchanged...
    customer_id = request.args.get('customer_id')
    if not customer_id:
        return jsonify({'locations': []})
    client.switch_database(SPEEDTEST_DB)
    devices_data_query = f'SELECT DISTINCT("field_location") FROM "{DEVICES_MEASUREMENT}" WHERE "field_customer_id" = {float(customer_id)}'
    devices_data_result = client.query(devices_data_query)
    devices_data_points = list(devices_data_result.get_points())
    locations = [point['distinct'] for point in devices_data_points if point['distinct']]

    # Switch back to ENDPOINTS_DB
    client.switch_database(ENDPOINTS_DB)

    return jsonify({'locations': locations})

@app.route('/revoke', methods=['GET'])
def revoke_device_get():
    # Existing code remains unchanged...
    client.switch_database(SPEEDTEST_DB)
    # Retrieve all claimed devices
    devices_query = f'SELECT * FROM "{DEVICES_MEASUREMENT}"'
    devices_result = client.query(devices_query)
    devices_points = list(devices_result.get_points())

    # Prepare data for template
    devices = []
    for point in devices_points:
        devices.append({
            'time': point.get('time'),
            'mac_address': point.get('field_mac_address'),
            'customer_id': int(point.get('field_customer_id')) if point.get('field_customer_id') else '',
            'customer_name': point.get('field_customer_name'),
            'friendly_name': point.get('field_friendly_name'),
            'location': point.get('field_location')
        })

    # Get filter and sort parameters from query string
    filter_column = request.args.get('filter_column')
    filter_value = request.args.get('filter_value', '').strip()
    sort_column = request.args.get('sort_column')
    sort_order = request.args.get('sort_order', 'asc')

    # Apply filtering
    if filter_column and filter_value:
        devices = [device for device in devices if filter_value.lower() in str(device.get(filter_column, '')).lower()]

    # Apply sorting
    if sort_column and sort_order != 'none':
        devices = sorted(devices, key=lambda x: x.get(sort_column, ''), reverse=(sort_order == 'desc'))

    if not devices:
        flash("No devices to revoke.", "info")

    # Switch back to ENDPOINTS_DB
    client.switch_database(ENDPOINTS_DB)

    return render_template('revoke.html', devices=devices, version='1.22.0', filter_column=filter_column, filter_value=filter_value, sort_column=sort_column, sort_order=sort_order)

@app.route('/revoke', methods=['POST'])
def revoke_device_post():
    # Existing code remains unchanged...
    try:
        client.switch_database(SPEEDTEST_DB)
        selected_macs = request.form.getlist('selected_macs')
        if not selected_macs:
            logger.error("No devices selected for revocation.")
            flash("No devices selected.", "error")
            return redirect(url_for('revoke_device_get'))

        for mac in selected_macs:
            # Delete device from devices measurement
            query = f'DELETE FROM "{DEVICES_MEASUREMENT}" WHERE "tag_mac_address" = \'{mac}\''
            client.query(query)
            logger.info(f"Device with MAC {mac} revoked successfully.")

        flash("Selected devices have been revoked.", "success")

        # Switch back to ENDPOINTS_DB
        client.switch_database(ENDPOINTS_DB)

        return redirect(url_for('revoke_device_get'))
    except Exception as e:
        logger.exception("An error occurred while revoking devices.")
        flash(f"Error: {str(e)}", "error")
        return redirect(url_for('revoke_device_get'))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
