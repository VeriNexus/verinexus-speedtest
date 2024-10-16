import os
import subprocess
import pandas as pd
import matplotlib.pyplot as plt
import io
import base64
from flask import Flask, render_template, request

app = Flask(__name__)

# Version number
VERSION = "1.1.1"

# File paths and remote details
results_file_path = '/speedtest/speedtest_results.csv'
remote_server = 'root@88.208.225.250'
remote_results_path = '/speedtest/results/speedtest_results.csv'
ssh_password = '**@p3F_1$t'

def refresh_results_file():
    """Refreshes the speedtest results file by pulling from the remote server."""
    command = f"sshpass -p '{ssh_password}' scp {remote_server}:{remote_results_path} {results_file_path}"
    subprocess.run(command, shell=True, check=True)

def load_data():
    """Loads the speedtest results from the local CSV file."""
    refresh_results_file()
    data = pd.read_csv(results_file_path)
    data['Date'] = pd.to_datetime(data['Date (UK)'], errors='coerce')  # Correct date parsing
    data['DateTime'] = pd.to_datetime(data['Date'].astype(str) + ' ' + data['Time (UK)'], errors='coerce')
    data = data.dropna(subset=['DateTime'])  # Drop rows where DateTime is NaT
    return data

def generate_plot(data):
    """Generates a plot and returns it as a base64 string."""
    fig, ax = plt.subplots(figsize=(12, 6))

    # Plot the data
    ax.plot(data['DateTime'], data['Download Speed (Mbps)'], label='Download Speed', linewidth=1)
    ax.plot(data['DateTime'], data['Upload Speed (Mbps)'], label='Upload Speed', linewidth=1)

    # Shade every other day with a darker color
    for i, (date, group) in enumerate(data.groupby(data['DateTime'].dt.date)):
        if i % 2 == 0:
            ax.axvspan(group['DateTime'].iloc[0], group['DateTime'].iloc[-1], color='blue', alpha=0.2)

    # Format the x-axis to show date and time
    ax.xaxis.set_major_formatter(plt.matplotlib.dates.DateFormatter('%Y-%m-%d %H:%M'))
    ax.xaxis.set_minor_locator(plt.matplotlib.dates.HourLocator(interval=1))  # Add times every hour

    # Rotate date labels for readability
    plt.setp(ax.get_xticklabels(), rotation=45, ha="right")

    # Set labels and title
    ax.set_xlabel('Date and Time')
    ax.set_ylabel('Speed (Mbps)')
    ax.set_title(f'Internet Speed Test Results (Version {VERSION})')

    # Add a legend
    ax.legend()

    # Show the grid for better readability
    ax.grid(True)

    # Adjust layout to ensure date labels are not cropped
    plt.tight_layout()

    # Convert plot to PNG image and then to base64 string
    img = io.BytesIO()
    plt.savefig(img, format='png')
    img.seek(0)
    plot_url = base64.b64encode(img.getvalue()).decode('utf8')
    plt.close(fig)
    return plot_url

@app.route('/', methods=['GET', 'POST'])
def index():
    print(f"Running app version {VERSION}")
    data = load_data()
    mac_addresses = data['MAC Address'].dropna().unique()
    selected_mac = request.form.get('mac_address', None)
    start_date_str = request.form.get('start_date', '')
    end_date_str = request.form.get('end_date', '')
    plot_url = None

    if selected_mac and start_date_str and end_date_str:
        start_date = pd.to_datetime(start_date_str, format="%Y-%m-%d")
        end_date = pd.to_datetime(end_date_str, format="%Y-%m-%d")
        data = data[
            (data['MAC Address'] == selected_mac) &
            (data['DateTime'] >= start_date) &
            (data['DateTime'] <= end_date)
        ]

        # Generate plot URL if there is data to plot
        if not data.empty:
            plot_url = generate_plot(data)

    return render_template('index.html', mac_addresses=mac_addresses, data=data.to_dict('records'), plot_url=plot_url)

if __name__ == '__main__':
    print(f"Starting app version {VERSION}")
    app.run(debug=True, host='0.0.0.0', port=8080)
