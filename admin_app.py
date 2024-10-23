# Version 1.1

from flask import Flask, request, render_template, redirect, url_for
from influxdb import InfluxDBClient

app = Flask(__name__)

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
    # Switch to the speedtest_db_clean database
    client.switch_database(SPEEDTEST_DB)

    # Get all MAC addresses from the speedtest measurement
    speedtest_query = f'SELECT DISTINCT("tag_mac_address") FROM {SPEEDTEST_MEASUREMENT}'
    speedtest_result = client.query(speedtest_query)
    speedtest_macs = {point['distinct'] for point in speedtest_result.get_points()}

    # Get all MAC addresses from the devices measurement
    devices_query = f'SELECT DISTINCT("tag_mac_address") FROM {DEVICES_MEASUREMENT}'
    devices_result = client.query(devices_query)
    devices_macs = {point['distinct'] for point in devices_result.get_points()}

    # Find unclaimed MAC addresses
    unclaimed_macs = speedtest_macs - devices_macs

    return render_template('claim.html', unclaimed_macs=unclaimed_macs)

@app.route('/claim', methods=['POST'])
def claim_device_post():
    mac_address = request.form['mac_address']
    customer_name = request.form['customer_name']
    friendly_name = request.form['friendly_name']
    location = request.form['location']

    # Switch to the speedtest_db_clean database
    client.switch_database(SPEEDTEST_DB)

    # Add the claimed device to the devices measurement
    json_body = [
        {
            "measurement": DEVICES_MEASUREMENT,
            "tags": {
                "tag_mac_address": mac_address
            },
            "fields": {
                "field_customer_name": customer_name,
                "field_friendly_name": friendly_name,
                "field_location": location,
                "field_mac_address": mac_address
            }
        }
    ]
    client.write_points(json_body)
    return redirect(url_for('claim_device'))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)