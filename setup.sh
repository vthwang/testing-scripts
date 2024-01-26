#!/bin/bash

server_ip=$1
dns_name=$2
email=$3
password=$4
config_name="k3s-murm-rancher"
cert_manager_version="v1.13.3"

# Ensure has 4 parameters
if [ $# -ne 4 ]; then
    echo "Usage: $0 <server_ip> <dns_name> <email> <password>"
    exit 1
fi

# Ensure docker is running, if not show error and exit
echo "Checking if docker is running..."
if [ "$(ps aux | grep -v grep | grep -c docker)" -lt 1 ]; then
    echo "Docker is not running. Please start docker and try again."
    exit 1
fi

# Ensure the .kube directory exists
mkdir -p ~/.kube

# Copy the file from the remote server
scp root@$server_ip:/etc/rancher/k3s/k3s.yaml ~/.kube/${config_name}

# Edit the file to replace localhost with dns_name
perl -pi -e "s/127.0.0.1/${dns_name}/g" ~/.kube/${config_name}
# Replace all default into $config_name
perl -pi -e "s/default/${config_name}/g" ~/.kube/${config_name}

# Set KUBECONFIG environment variable
export KUBECONFIG=~/.kube/config:~/.kube/${config_name}

# Merge the kubeconfig files and backup the original
kubectl config view --merge --flatten > ~/.kube/merged_kubeconfig
mv ~/.kube/config ~/.kube/config_backup
mv ~/.kube/merged_kubeconfig ~/.kube/config

chmod 600 ~/.kube/config

# Deploy Rancher with Helm
kubectl config use-context ${config_name}

# Add Helm repositories
helm repo add rancher-stable https://releases.rancher.com/server-charts/stable
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Wait for five seconds
echo "Waiting for 5 seconds..."
sleep 5

# Install Cert-Manager
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version ${cert_manager_version} \
  --set installCRDs=true

echo "Waiting for 20 seconds to complete cert-manager installation..."
for (( i=1; i<=20; i++ ))
do
   sleep 1
   echo -n "."
done

# Install Rancher
helm install rancher rancher-stable/rancher \
  --namespace cattle-system \
  --create-namespace \
  --set hostname=${dns_name} \
  --set replicas=1 \
  --set bootstrapPassword=${password} \
  --set ingress.tls.source=letsEncrypt \
  --set letsEncrypt.email=${email} \
  --set letsEncrypt.ingress.class=traefik

# Instructions to access Rancher
echo "Access Rancher at https://$dns_name/dashboard/?setup=$password"
