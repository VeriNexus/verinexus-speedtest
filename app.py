from flask import Flask, render_template
from influxdb import InfluxDBClient

app = Flask(__name__)

# Version number of the application
APP_VERSION = "2.0.0"

# InfluxDB configuration
INFLUXDB_SERVER = '82.165.7.116'
INFLUXDB_PORT = 8086
INFLUXDB_DB = 'speedtest_db_clean'

client = InfluxDBClient(host=INFLUXDB_SERVER, port=INFLUXDB_PORT, database=INFLUXDB_DB)

@app.route('/')
def index():
    query = 'SELECT * FROM speedtest'
    result = client.query(query)
    points = list(result.get_points())
    return render_template('index.html', points=points, version=APP_VERSION)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)