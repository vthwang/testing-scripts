#!/bin/bash

# Parameters
ks3_version=v1.24.14+k3s1
max_attempts=5
pod_max_attempts=10

function main() {
  # Ensure the script is run as root
  if [ "$(id -u)" != "0" ]; then
     echo "This script must be run as root" 1>&2
     exit 1
  fi

  wait_for_apt && ( apt-get purge -y do-agent >/dev/null 2>&1 || : )

  # Update and Upgrade the System
  echo "Updating and upgrading system packages..."

  apt-get update
  if [ $? -ne 0 ]; then
      echo "E: Checking issue after apt-get update"
      exit 1
  fi


  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  if [ $? -ne 0 ]; then
      echo "E: Checking issue after apt-get upgrade"
      exit 1
  fi

  apt-get autoremove -y
  if [ $? -ne 0 ]; then
      echo "E: Checking issue after apt-get autoremove"
      exit 1
  fi

  apt-get autoclean
  if [ $? -ne 0 ]; then
      echo "E: Checking issue after apt-get autoclean"
      exit 1
  fi

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

          pod_attempt=0

          # Execute the next command if nodes are found
          while [ $pod_attempt -lt $pod_max_attempts ]; do
              echo "Checking if all pods are running or completed (Attempt $((pod_attempt+1))/$pod_max_attempts)..."
              # Needs to have at least 2 running pods and all pods should be in Running or Completed status
              running_count=$(k3s kubectl get pods --all-namespaces | awk '{if(NR>1)print $4}' | grep -c "Running")
              completed_count=$(k3s kubectl get pods --all-namespaces | awk '{if(NR>1)print $4}' | grep -c "Completed")
              error_count=$(k3s kubectl get pods --all-namespaces | awk '{if(NR>1)print $4}' | grep -vE "Running|Completed" | wc -l)
              if [ "$running_count" -lt 5 ] || [ "$completed_count" -lt 2 ] || [ "$error_count" -gt 0 ]; then
                  echo "Some pods are not in Running or Completed status"
                  pod_attempt=$((pod_attempt+1))
                  sleep 10
              else
                  k3s kubectl get pods --all-namespaces
                  echo "All pods are in Running or Completed status. Proceeding to next step. You can execute following commands to make sure all pods are running."
                  echo "k3s kubectl get pods --all-namespaces"
                  exit 0
              fi
          done

          if [ $pod_attempt -eq $pod_max_attempts ]; then
              echo "Not all pods are running or completed after $max_attempts attempts. You can execute following commands to make sure all pods are running."
              echo "k3s kubectl get pods --all-namespaces"
              exit 1
          fi
      fi

      attempt=$((attempt+1))
      sleep 5
  done

  # Show error if no nodes are found after 5 attempts
  echo "Error: Unable to get nodes after $max_attempts attempts."
  exit 1
}

function wait_for_apt() {
	while fuser /var/{lib/{dpkg,apt/lists},cache/apt/archives}/lock >/dev/null 2>&1; do
		echo "Waiting on apt.."
		sleep 2
	done
}