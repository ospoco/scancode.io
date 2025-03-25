#!/bin/bash

# Script to fully rebuild and refresh the ScanCode.io container environment
# Set -e to exit on error
set -e

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

echo "==== ScanCode.io Container Rebuild Script ===="
echo "Working from directory: $PROJECT_ROOT"
echo "This script will stop, remove, rebuild, and restart all containers."
echo ""

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Step 1: Stopping all containers${NC}"
podman-compose -f docker-compose.yml -f docker-compose.podman.yml down || echo "No containers were running"

echo -e "${YELLOW}Step 2: Removing all containers${NC}"
podman ps -a -q --filter name=scancodeio | xargs -r podman rm -f || echo "No containers to remove"

echo -e "${YELLOW}Step 3: Preparing for rebuild${NC}"
# Add a command-line flag option for rebuilding images
if [[ "$*" == *"--rebuild-images"* ]]; then
  echo "Removing container images..."
  podman images --filter reference='*scancodeio*' -q | xargs -r podman rmi 2>/dev/null || echo "No images to remove"
  BUILD_ARG="--build"
else
  BUILD_ARG=""
fi

# Add a command-line flag option for pruning volumes
if [[ "$*" == *"--prune-volumes"* ]]; then
  echo -e "${YELLOW}Step 4: Pruning volumes${NC}"
  echo "CAUTION: Removing all volumes - THIS WILL DELETE ALL DATA!"
  podman volume prune -f
else
  echo -e "${YELLOW}Step 4: Skipping volume pruning${NC}"
fi

echo -e "${YELLOW}Step 5: Preparing static directory${NC}"
mkdir -p ${PROJECT_ROOT}/static
chown -R $(id -u):www-data ${PROJECT_ROOT}/static
chmod -R 775 ${PROJECT_ROOT}/static
# Ensure world-readable for nginx
chmod -R o+r ${PROJECT_ROOT}/static

echo -e "${YELLOW}Step 6: Starting containers${NC}"
podman-compose -f docker-compose.yml -f docker-compose.podman.yml up -d $BUILD_ARG db redis web worker clamav

echo -e "${YELLOW}Step 7: Checking container status${NC}"
sleep 3
podman-compose -f docker-compose.yml -f docker-compose.podman.yml ps

echo -e "${GREEN}Container environment rebuilt and restarted!${NC}"
echo "You can watch logs with: podman-compose -f docker-compose.yml -f docker-compose.podman.yml logs -f"

# Check if nginx is already configured before printing the reminder
nginx_check() {
  CONF_SRC="$PROJECT_ROOT/config/scancode-nginx.conf"
  SITES_AVAILABLE="/etc/nginx/sites-available/scancode"
  SITES_ENABLED="/etc/nginx/sites-enabled/scancode"
  
  # Check if both symlinks exist and are valid
  if [ -L "$SITES_AVAILABLE" ] && [ -L "$SITES_ENABLED" ]; then
    if [ "$(readlink -f "$SITES_AVAILABLE")" == "$CONF_SRC" ] && \
       [ "$(readlink -f "$SITES_ENABLED")" == "$SITES_AVAILABLE" ]; then
      return 0  # Already configured
    fi
  fi
  return 1  # Not configured
}

# Only print the reminder if nginx is not yet configured
if ! nginx_check; then
  echo "Remember to set up the nginx configuration if you haven't already: sudo $PROJECT_ROOT/bin/setup-nginx.sh"
fi
