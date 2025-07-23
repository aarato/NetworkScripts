import os
import requests
from dotenv import load_dotenv
import sys

# Load API token from .env
load_dotenv()
API_TOKEN = os.getenv("API_TOKEN")
ORG_ID = os.getenv("ORG_ID")

if not API_TOKEN:
    raise ValueError("Missing API_TOKEN in .env file")

if not ORG_ID:
    raise ValueError("Missing ORG_ID in .env file")

# Set headers
headers = {
    "Authorization": f"Token {API_TOKEN}",
    "Content-Type": "application/json"
}

def get_all_devices(org_id, headers):
    """Fetch all devices with pagination support"""
    devices = []
    url = f"https://api.mist.com/api/v1/orgs/{org_id}/devices"
    
    while url:
        try:
            response = requests.get(url, headers=headers)
            response.raise_for_status()
            
            batch = response.json()
            
            # Debug: Check the response structure
            print(f"Debug: Response type: {type(batch)}")
            if isinstance(batch, list):
                devices.extend(batch)
            elif isinstance(batch, dict):
                # If response is wrapped in an object, look for common keys
                if 'data' in batch:
                    devices.extend(batch['data'])
                elif 'results' in batch:
                    devices.extend(batch['results'])
                else:
                    # If it's a single device object, wrap it in a list
                    devices.append(batch)
            else:
                print(f"Unexpected response format: {batch}")
                break
            
            # Check for pagination (Link header)
            link_header = response.headers.get('Link', '')
            if 'rel="next"' in link_header:
                # Extract next URL from Link header
                for link in link_header.split(','):
                    if 'rel="next"' in link:
                        url = link.split('<')[1].split('>')[0]
                        break
                else:
                    url = None
            else:
                url = None
                
        except requests.exceptions.RequestException as e:
            print(f"Error fetching devices: {e}")
            sys.exit(1)
    
    return devices

def display_devices(devices):
    """Display devices in a formatted way"""
    if not devices:
        print("No devices found.")
        return
    
    print(f"Found {len(devices)} devices in the organization:")
    print("=" * 100)
    
    # Debug: Check device structure
    if devices:
        print(f"Debug: First device type: {type(devices[0])}")
        if isinstance(devices[0], dict):
            print(f"Debug: First device keys: {list(devices[0].keys())}")
    
    # Group by device type
    device_types = {}
    for device in devices:
        # Handle case where device might be a string or unexpected type
        if not isinstance(device, dict):
            print(f"Warning: Unexpected device format: {type(device)} - {device}")
            continue
            
        device_type = device.get('type', 'Unknown')
        if device_type not in device_types:
            device_types[device_type] = []
        device_types[device_type].append(device)
    
    for device_type, type_devices in device_types.items():
        print(f"\n{device_type.upper()} ({len(type_devices)} devices)")
        print("-" * 50)
        
        for device in type_devices:
            name = device.get('name', 'Unnamed')
            model = device.get('model', 'N/A')
            mac = device.get('mac', 'N/A')
            serial = device.get('serial', 'N/A')
            status = device.get('status', 'N/A')
            site_id = device.get('site_id', 'N/A')
            
            print(f"  • {name:<20} | Model: {model:<15} | MAC: {mac} | Status: {status}")
            print(f"    Serial: {serial:<20} | Site ID: {site_id}")
            print()

# Main execution
if __name__ == "__main__":
    devices = get_all_devices(ORG_ID, headers)
    display_devices(devices)