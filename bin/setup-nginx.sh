#!/bin/bash

# This script sets up the Nginx configuration for ScanCode.io
# It should be run with sudo

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Change to the project root directory
cd "$PROJECT_ROOT" || { echo "Failed to change to project directory"; exit 1; }

# Source environment files if they exist
if [ -f "$PROJECT_ROOT/.env" ]; then
  source "$PROJECT_ROOT/.env"
  echo "Loaded .env file"
fi

if [ -f "$PROJECT_ROOT/.envrc" ]; then
  source "$PROJECT_ROOT/.envrc"
  echo "Loaded .envrc file"
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

# Define variables
CONF_SRC="$PROJECT_ROOT/config/scancode-nginx.conf"
SITES_AVAILABLE="/etc/nginx/sites-available/scancode"
SITES_ENABLED="/etc/nginx/sites-enabled/scancode"

# Check if already configured
is_already_configured() {
  # Check if both symlinks exist and are valid
  if [ -L "$SITES_AVAILABLE" ] && [ -L "$SITES_ENABLED" ]; then
    if [ "$(readlink -f "$SITES_AVAILABLE")" == "$CONF_SRC" ] && \
       [ "$(readlink -f "$SITES_ENABLED")" == "$SITES_AVAILABLE" ]; then
      return 0  # Already configured
    fi
  fi
  return 1  # Not configured
}

# Silently exit if already configured
if is_already_configured; then
  exit 0
fi

# Create a symlink in sites-available
if [ ! -L "$SITES_AVAILABLE" ]; then
  ln -s "$CONF_SRC" "$SITES_AVAILABLE"
  echo "Created symlink in sites-available"
else
  echo "Symlink already exists in sites-available"
fi

# Create a symlink in sites-enabled if it doesn't exist
if [ ! -L "$SITES_ENABLED" ]; then
  ln -s "$SITES_AVAILABLE" "$SITES_ENABLED"
  echo "Created symlink in sites-enabled"
else
  echo "Symlink already exists in sites-enabled"
fi

# Test the configuration
nginx -t
if [ $? -eq 0 ]; then
  echo "Nginx configuration test successful"
  # Reload Nginx
  systemctl reload nginx
  echo "Nginx reloaded"
else
  echo "Nginx configuration test failed - please check your config"
  exit 1
fi

echo "Setup complete!"