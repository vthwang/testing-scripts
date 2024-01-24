#!/bin/bash

# Parameters
ks3_version=v1.24.14+k3s1
max_attempts=5

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Update and Upgrade the System
echo "Updating and upgrading system packages..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
apt-get autoremove -y
apt-get autoclean

# Install k3s
echo "Installing k3s..."
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$ks3_version sh -s - server --cluster-init

# Wait for 5 seconds
echo "Waiting for 5 seconds..."
sleep 5

# Check for nodes
attempt=0

while [ $attempt -lt $max_attempts ]; do
    echo "Attempting to get nodes (Attempt $((attempt+1))/$max_attempts)..."
    if k3s kubectl get nodes | awk '{if(NR>1)print $2}' | grep -qw "Ready"; then
        echo "Node is in Ready status. Proceeding to next step."
        k3s kubectl get nodes
        # Execute the next command if nodes are found
        echo "Executing 'getting pods'..."
        sleep 5
        k3s kubectl get pods --all-namespaces
        exit 0
    fi

    attempt=$((attempt+1))
    sleep 5
done

# Show error if no nodes are found after 5 attempts
echo "Error: Unable to get nodes after $max_attempts attempts."
exit 1
