#!/usr/bin/env bash

set -e
USE_SUDO=0

echo "Installing Shardeum Validator..."

# Default values
NODEHOME=~/shardeum
DASHPORT=8116
SHMEXT=9161
SHMINT=65166
DASHBOARD_PASSWORD="Asdasdasd3@"

# Create and resolve the node directory
mkdir -p "$NODEHOME"
NODEHOME=$(realpath "$NODEHOME")

# Check Docker availability
command -v docker >/dev/null 2>&1 || { echo >&2 "Docker is not installed on this machine but is required to run the Shardeum validator. Please install Docker before continuing."; exit 1; }

docker-safe() {
  if ! command -v docker &>/dev/null; then
    echo "docker is not installed on this machine"
    exit 1
  fi

  if ! docker "$@"; then
    echo "Trying again with sudo..." >&2
    USE_SUDO=1
    sudo docker "$@"
  fi
}

if [[ $(docker-safe info 2>&1) == *"Cannot connect to the Docker daemon"* ]]; then
  echo "Docker daemon is not running, please start the Docker daemon and try again."
  exit 1
else
  echo "Docker daemon is running."
fi

# Set up ownership of the node directory
set +e
mkdir -p "${NODEHOME}"
OWNER_UID=$(stat -c '%u' "$NODEHOME")
TARGET_UID=1000

if [ "$OWNER_UID" -ne "$TARGET_UID" ]; then
  echo "Changing ownership of $NODEHOME to UID $TARGET_UID..."
  if ! chown "$TARGET_UID" "$NODEHOME" && ! sudo chown "$TARGET_UID" "$NODEHOME"; then
    echo "Failed to change ownership of $NODEHOME."
    exit 1
  fi
else
  echo "Ownership of $NODEHOME is already UID $TARGET_UID."
fi
set -e

echo "Downloading the Shardeum Validator image and starting the validator container..."

# Pull the latest image and run the validator
docker-safe pull ghcr.io/shardeum/shardeum-validator:latest
docker-safe run \
    --name shardeum-validator \
    -p ${DASHPORT}:${DASHPORT} \
    -p ${SHMEXT}:${SHMEXT} \
    -p ${SHMINT}:${SHMINT} \
    -e RUNDASHBOARD=y \
    -e DASHPORT=${DASHPORT} \
    -e EXT_IP=auto \
    -e INT_IP=auto \
    -e SERVERIP=auto \
    -e LOCALLANIP=auto \
    -e SHMEXT=${SHMEXT} \
    -e SHMINT=${SHMINT} \
    -v ${NODEHOME}:/home/node/config \
    --restart=always \
    --detach \
    ghcr.io/shardeum/shardeum-validator

echo "Waiting for the container to be available (max 60 seconds)..."
timeout=60
elapsed=0

while [ ! -f "${NODEHOME}/set-password.sh" ]; do
  sleep 1
  elapsed=$((elapsed + 1))
  if [ "$elapsed" -ge "$timeout" ]; then
    echo "Timeout: set-password.sh not found after 60 seconds."
    exit 1
  fi
done

# Set the preconfigured password
echo "Setting up the dashboard password..."
echo "${DASHBOARD_PASSWORD}" | "${NODEHOME}/set-password.sh"

echo "Shardeum Validator is now running. Access the dashboard at:"
echo "https://$(curl -s https://api.ipify.org):${DASHPORT}/"
echo "Or https://localhost:${DASHPORT}/ if running locally."
