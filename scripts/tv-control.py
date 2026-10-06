import sys
import time
import requests
from datetime import datetime

TV_IP = <YOUR_TV_IP>
PSK = <YOUR_TV_PSK>

def set_power(status: bool):
    url = f"http://{TV_IP}/sony/system"
    headers = {
        "Content-Type": "application/json",
        "X-Auth-PSK": PSK,
    }
    payload = {
        "method": "setPowerStatus",
        "params": [{"status": status}],
        "id": 1,
        "version": "1.0",
    }
    resp = requests.post(url, json=payload, headers=headers, timeout=5)
    resp.raise_for_status()

def set_hdmi_input():
    url = f"http://{TV_IP}/sony/avContent"
    headers = {
        "Content-Type": "application/json",
        "X-Auth-PSK": PSK,
    }
    payload = {
        "method": "setPlayContent",
        "params": [{"uri": "extInput:hdmi?port=4"}],
        "id": 1,
        "version": "1.0",
    }
    resp = requests.post(url, json=payload, headers=headers, timeout=5)
    resp.raise_for_status()

def set_power_with_retry(status: bool, attempts=10, delay=3):
    for i in range(attempts):
        try:
            set_power(status)
            print(f"[{datetime.now()}] Succeeded on attempt {i+1}")
            return
        except requests.exceptions.ConnectionError as e:
            print(f"[{datetime.now()}] Attempt {i+1} failed: {e}")
            if i == attempts - 1:
                raise
            time.sleep(delay)

def set_hdmi_input_with_retry(attempts=5, delay=2):
    for i in range(attempts):
        try:
            set_hdmi_input()
            print(f"[{datetime.now()}] HDMI switch succeeded on attempt {i+1}")
            return
        except requests.exceptions.RequestException as e:
            print(f"[{datetime.now()}] HDMI switch attempt {i+1} failed: {e}")
            if i == attempts - 1:
                raise
            time.sleep(delay)

if __name__ == "__main__":
    set_power_with_retry(sys.argv[1] == "on")
    if sys.argv[1] == "on":
        set_hdmi_input_with_retry()