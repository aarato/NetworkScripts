# Juniper Mist API Scripts

A collection of Python scripts for managing and monitoring Juniper Mist network infrastructure through the Mist API.

## Prerequisites

- Python 3.7+
- Juniper Mist account with API access
- API token with appropriate permissions

## Installation

1. Create a virtual environment:
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

3. Create a `.env` file in this directory with your API credentials (see below).

## Environment Configuration

Create a `.env` file in the JuniperMist directory with the following variables:

```env
# Required for all scripts
API_TOKEN=your_mist_api_token_here
ORG_ID=your_organization_id_here

# Alternative token name used by get_sites.py
MIST_API_TOKEN=your_mist_api_token_here
```

### Getting Your API Token

1. Log into the Juniper Mist portal
2. Go to Organization > Settings > API Tokens
3. Create a new token with appropriate permissions
4. Copy the token to your `.env` file

### Getting Your Organization ID

Run `get_sites.py` first to retrieve your organization information, or check the Mist portal URL when logged in.

## Scripts

### `get_sites.py`
**Purpose:** Retrieves and displays organization information from the Mist API.

**Usage:**
```bash
python get_sites.py
```

**Output:** JSON formatted organization data including org ID, name, and other details.

**Environment Variables:**
- `MIST_API_TOKEN` - Your Mist API token

### `check.py`
**Purpose:** Lists all sites within your organization with their details.

**Usage:**
```bash
python check.py
```

**Output:** Site information including ID, name, and address for each site.

**Environment Variables:**
- `API_TOKEN` - Your Mist API token
- `ORG_ID` - Your organization ID

### `list_devices.py`
**Purpose:** Comprehensive device inventory script that lists all network devices across your organization with pagination support.

**Usage:**
```bash
python list_devices.py
```

**Output:** 
- Device count summary
- Devices grouped by type (AP, Switch, Gateway, etc.)
- For each device: name, model, MAC address, serial number, status, and site ID

**Features:**
- Handles API pagination automatically
- Groups devices by type for better organization
- Includes debug information for troubleshooting
- Error handling for API requests

**Environment Variables:**
- `API_TOKEN` - Your Mist API token
- `ORG_ID` - Your organization ID

## Security Notes

- Never commit your `.env` file to version control
- The `.gitignore` file is configured to exclude sensitive files
- All API credentials are loaded from environment variables
- No hardcoded secrets in the scripts

## Error Handling

All scripts include error handling for:
- Missing environment variables
- API authentication failures
- Network connectivity issues
- Invalid API responses

## API Rate Limits

Be aware of Mist API rate limits when running these scripts frequently. The scripts include basic error handling but do not implement rate limit backoff.