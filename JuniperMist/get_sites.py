import os
import requests
from dotenv import load_dotenv
import json

# Load API token from .env
load_dotenv()
API_TOKEN = os.getenv("API_TOKEN")

if not API_TOKEN:
    raise ValueError("Missing API_TOKEN in .env file")

# Set headers
headers = {
    "Authorization": f"Token {API_TOKEN}",
    "Content-Type": "application/json"
}

# Step 1: Get Org ID (assumes user belongs to 1 org)
url = "https://api.mist.com/api/v1/orgs"
response = requests.get(url, headers=headers)
response.raise_for_status()
data = response.json()

print(json.dumps(data, indent=2))
