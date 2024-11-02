# admin_app.py
# Version: 1.9.1
# Date: 02/11/2024
# Description:
# Flask application for managing devices in the VeriNexus Speed Test system.
# Provides routes for claiming and revoking devices.
# Includes enhanced debugging and logging.
# Adjusted queries to retrieve MAC addresses from fields if necessary.

import logging
from flask import Flask, request, render_template, redirect, url_for
from influxdb import InfluxDBClient

app = Flask(__name__)

# Configure logging
logging.basicConfig(level=logging.DEBUG)

# InfluxDB configuration
INFLUXDB_SERVER = '82.165.7.116'
INFLUXDB_PORT = 8086
INFLUXDB_DB = 'test_db'
INFLUXDB_MEASUREMENT = 'endpoints'
SPEEDTEST_DB = 'speedtest_db_clean'
DEVICES_MEASUREMENT = 'devices'
SPEEDTEST_MEASUREMENT = 'speedtest'

client = InfluxDBClient(host=INFLUXDB_SERVER, port=INFLUXDB_PORT)

def create_database_if_not_exists(db_name):
    databases = client.get_list_database()
    if not any(db['name'] == db_name for db in databases):
        client.create_database(db_name)
        # Add example.com entry in the correct format
        test_data = [
            {
                "measurement": INFLUXDB_MEASUREMENT,
                "tags": {
                    "tag_endpoint": "example.com"
                },
                "fields": {
                    "field_value": 1
                }
            }
        ]
        client.switch_database(db_name)
        client.write_points(test_data)

# Ensure the test_db exists and the measurement is correctly formatted
create_database_if_not_exists(INFLUXDB_DB)
client.switch_database(INFLUXDB_DB)  # Switch to the correct database

@app.route('/')
def index():
    query = f'SELECT * FROM {INFLUXDB_MEASUREMENT}'
    result = client.query(query)
    points = list(result.get_points())
    return render_template('index.html', points=points)

@app.route('/add', methods=['POST'])
def add_endpoint():
    endpoint = request.form['endpoint']
    json_body = [
        {
            "measurement": INFLUXDB_MEASUREMENT,
            "tags": {
                "tag_endpoint": endpoint
            },
            "fields": {
                "field_value": 1
            }
        }
    ]
    client.write_points(json_body)
    return redirect(url_for('index'))

@app.route('/delete', methods=['POST'])
def delete_endpoint():
    endpoint = request.form['endpoint']
    query = f"DELETE FROM {INFLUXDB_MEASUREMENT} WHERE \"tag_endpoint\"='{endpoint}'"
    client.query(query)
    return redirect(url_for('index'))

@app.route('/dropdb', methods=['POST'])
def drop_database():
    client.drop_database(INFLUXDB_DB)
    return redirect(url_for('index'))

@app.route('/claim', methods=['GET'])
def claim_device():
    client.switch_database(SPEEDTEST_DB)
    app.logger.debug(f"Switched to database: {SPEEDTEST_DB}")

    # Get all MAC addresses from the speedtest measurement
    speedtest_query = f'SHOW TAG VALUES FROM "{SPEEDTEST_MEASUREMENT}" WITH KEY = "tag_mac_address"'
    app.logger.debug(f"Speedtest query: {speedtest_query}")
    speedtest_result = client.query(speedtest_query)
    speedtest_points = list(speedtest_result.get_points())

    if speedtest_points:
        # tag_mac_address is a tag
        speedtest_macs = {point['value'] for point in speedtest_points}
        app.logger.debug("Retrieved MAC addresses as tags.")
    else:
        # tag_mac_address might be a field
        app.logger.debug("No MAC addresses found as tags. Trying to retrieve as fields.")
        speedtest_query = f'SELECT DISTINCT("tag_mac_address") FROM "{SPEEDTEST_MEASUREMENT}"'
        speedtest_result = client.query(speedtest_query)
        speedtest_points = list(speedtest_result.get_points())
        speedtest_macs = {point['distinct'] for point in speedtest_points if point['distinct']}
        app.logger.debug(f"MAC addresses from speedtest measurement: {speedtest_macs}")

    # Get all MAC addresses from the devices measurement
    devices_query = f'SHOW TAG VALUES FROM "{DEVICES_MEASUREMENT}" WITH KEY = "tag_mac_address"'
    app.logger.debug(f"Devices query: {devices_query}")
    devices_result = client.query(devices_query)
    devices_points = list(devices_result.get_points())

    if devices_points:
        devices_macs = {point['value'] for point in devices_points}
        app.logger.debug("Retrieved devices MAC addresses as tags.")
    else:
        app.logger.debug("No devices MAC addresses found as tags. Trying to retrieve as fields.")
        devices_query = f'SELECT DISTINCT("tag_mac_address") FROM "{DEVICES_MEASUREMENT}"'
        devices_result = client.query(devices_query)
        devices_points = list(devices_result.get_points())
        devices_macs = {point['distinct'] for point in devices_points if point['distinct']}
        app.logger.debug(f"MAC addresses from devices measurement: {devices_macs}")

    # Find unclaimed MAC addresses
    unclaimed_macs = speedtest_macs - devices_macs
    app.logger.debug(f"Unclaimed MAC addresses: {unclaimed_macs}")

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
            customer_id = str(int(customer_id))  # Ensure customer_id is treated as an integer
            customers[customer_id] = customer_name
            if customer_id not in locations:
                locations[customer_id] = set()
            if location:
                locations[customer_id].add(location)

    # Convert sets to lists for JSON serialization
    for customer_id in locations:
        locations[customer_id] = list(locations[customer_id])

    # Pass the data to the template
    return render_template('claim.html', unclaimed_macs=unclaimed_macs, customers=customers, locations=locations)

@app.route('/claim', methods=['POST'])
def claim_device_post():
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
            # Retrieve customer_name based on customer_id
            customer_query = f'SELECT "field_customer_name" FROM "{DEVICES_MEASUREMENT}" WHERE "field_customer_id" = \'{customer_id}\' LIMIT 1'
            customer_result = client.query(customer_query)
            customer_points = list(customer_result.get_points())
            if customer_points:
                customer_name = customer_points[0]['field_customer_name']
            else:
                # Handle error
                app.logger.error(f"Customer ID {customer_id} not found.")
                return "Error: Customer not found", 400

            # Handle location
            location_option = request.form['location_option']
            if location_option == 'existing':
                location = request.form['existing_location']
            elif location_option == 'new':
                location = request.form['new_location_name']
                if not location:
                    app.logger.error("New location name is required but not provided.")
                    return "Error: New location name is required", 400
            else:
                app.logger.error("Invalid location option selected.")
                return "Error: Invalid location option", 400

        elif customer_option == 'new':
            customer_name = request.form['new_customer_name']
            if not customer_name:
                app.logger.error("New customer name is required but not provided.")
                return "Error: New customer name is required", 400
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
                    max_customer_id = int(max_customer_id)  # Ensure max_customer_id is treated as an integer
            customer_id = max_customer_id + 1

            # For new customer, location is always new
            location = request.form['new_customer_location_name']
            if not location:
                app.logger.error("Location name is required for new customer but not provided.")
                return "Error: Location name is required for new customer", 400
        else:
            app.logger.error("Invalid customer option selected.")
            return "Error: Invalid customer option", 400

        # Validate that friendly_name is unique per customer
        friendly_name_query = f'SELECT * FROM "{DEVICES_MEASUREMENT}" WHERE "field_customer_id" = \'{customer_id}\' AND "field_friendly_name" = \'{friendly_name}\''
        friendly_name_result = client.query(friendly_name_query)
        friendly_name_points = list(friendly_name_result.get_points())
        if friendly_name_points:
            # Friendly name already exists for this customer
            app.logger.error(f"Friendly name '{friendly_name}' already exists for customer ID {customer_id}.")
            return f"Error: Friendly name '{friendly_name}' already exists for this customer", 400

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
        app.logger.info(f"Device with MAC {mac_address} claimed successfully for customer '{customer_name}' (ID: {customer_id}).")
        return redirect(url_for('claim_device'))
    except Exception as e:
        app.logger.exception("An error occurred while processing the claim.")
        return f"Error: {str(e)}", 500

@app.route('/revoke', methods=['GET'])
def revoke_device_get():
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
            'customer_id': point.get('field_customer_id'),
            'customer_name': point.get('field_customer_name'),
            'friendly_name': point.get('field_friendly_name'),
            'location': point.get('field_location')
        })

    return render_template('revoke.html', devices=devices)

@app.route('/revoke', methods=['POST'])
def revoke_device_post():
    try:
        client.switch_database(SPEEDTEST_DB)
        selected_macs = request.form.getlist('selected_macs')
        if not selected_macs:
            app.logger.error("No devices selected for revocation.")
            return "Error: No devices selected", 400

        for mac in selected_macs:
            # Delete device from devices measurement
            query = f'DELETE FROM "{DEVICES_MEASUREMENT}" WHERE "tag_mac_address" = \'{mac}\''
            client.query(query)
            app.logger.info(f"Device with MAC {mac} revoked successfully.")

        return redirect(url_for('revoke_device_get'))
    except Exception as e:
        app.logger.exception("An error occurred while revoking devices.")
        return f"Error: {str(e)}", 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)