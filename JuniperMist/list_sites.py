import os
import requests
from dotenv import load_dotenv
import json

# Load API token from .env
load_dotenv()
API_TOKEN = os.getenv("API_TOKEN")
ORG_ID = os.getenv("ORG_ID")

if not API_TOKEN:
    raise ValueError("Missing API_TOKEN in .env file")

# Set headers
headers = {
    "Authorization": f"Token {API_TOKEN}",
    "Content-Type": "application/json"
}

# Step 1: Get Org ID (assumes user belongs to 1 org)
url = f"https://api.mist.com/api/v1/orgs/{ORG_ID}/sites"
response = requests.get(url, headers=headers)
response.raise_for_status()
sites = response.json()
for site in sites:
    print(f'id: {site["id"]} - name: {site["name"]} - address: {site["address"]} ')
    # print(json.dumps(site, indent=2))
