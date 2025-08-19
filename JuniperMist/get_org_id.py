import os
import requests
from dotenv import load_dotenv

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

# Get organization info
url = "https://api.mist.com/api/v1/self"
response = requests.get(url, headers=headers)
response.raise_for_status()
data = response.json()

# Extract org ID from the first organization
if data.get("privileges"):
    for privilege in data["privileges"]:
        if privilege.get("scope") == "org":
            org_id = privilege.get("org_id")
            print(f"Organization ID: {org_id}")
            break
    else:
        print("No organization found in user privileges")
else:
    print("No privileges found")