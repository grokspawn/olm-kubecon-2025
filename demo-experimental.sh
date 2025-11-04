#!/usr/bin/env bash
#
# KubeCon 2025 – OLMv1 Demo
# Demonstrating OLMv1 features 
#
set -euo pipefail
trap 'trap - SIGTERM && kill -- -"$$"' SIGINT SIGTERM EXIT

MANIFEST_DIR="./manifests"

# ----------------------------------------------------------------------
# Setup paths
# ----------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPERATOR_CONTROLLER_DIR="${REPO_ROOT}/../operator-controller"

echo "Cleaning up any previous kind cluster..."
kind delete cluster || true
echo "--------------------------------------------------"

# ----------------------------------------------------------------------
# Clone operator-controller and install OLMv1 in experimental mode
# ----------------------------------------------------------------------
if [ ! -d "${OPERATOR_CONTROLLER_DIR}" ]; then
  echo "Cloning operator-controller repository..."
  git clone https://github.com/operator-framework/operator-controller.git "${OPERATOR_CONTROLLER_DIR}"
else
  echo "operator-controller repo already present. Pulling latest..."
  (cd "${OPERATOR_CONTROLLER_DIR}" && git pull)
fi

echo "--------------------------------------------------"
echo "Starting KIND cluster and enabling experimental OLMv1 features..."
make -C "${OPERATOR_CONTROLLER_DIR}" run-experimental
echo "Waiting for operator controller deployment to complete..."
kubectl rollout status -n olmv1-system deployment/operator-controller-controller-manager
echo "--------------------------------------------------"

echo "Inspecting installed CRDs..."
kubectl get crds -A
echo "--------------------------------------------------"

echo "Checking for existing ClusterCatalogs..."
kubectl get clustercatalog -A || true
echo "--------------------------------------------------"

echo "Installing demo ClusterCatalog (from local manifests directory)..."
kubectl apply -f "$MANIFEST_DIR/00_clustercatalog.yaml"
echo "--------------------------------------------------"

echo "Verifying that ClusterCatalog has been created..."
kubectl get clustercatalog -A
echo "--------------------------------------------------"

echo "Waiting for ClusterCatalog to reach Serving state..."
kubectl wait --for=condition=Serving clustercatalog/olm-kubecon2025-demo --timeout=60s || true
echo "--------------------------------------------------"

echo "Detailed ClusterCatalog status:"
kubectl describe clustercatalog olm-kubecon2025-demo
echo "--------------------------------------------------"

echo "✅ OLMv1 installed and serving demo catalog."
echo ""

# ----------------------------------------------------------------------
# Install ClusterExtensions
# ----------------------------------------------------------------------

echo "--------------------------------------------------"
echo "Step 1: Installing setup ClusterExtension..."
kubectl apply -f "$MANIFEST_DIR/01_clusterextension-setup.yaml"
sleep 5
echo "--------------------------------------------------"

echo ""
echo "Step 2: Installing first version (v0.0.1)..."
kubectl apply -f "$MANIFEST_DIR/02_clusterextension-v0.0.1.yaml"
echo "--------------------------------------------------"
sleep 5
echo "...Waiting for ClusterExtension demo-operator to report Installed=True..."
kubectl wait --for=condition=Installed clusterextension/demo-operator --timeout=180s
echo "Status after v0.0.1 installation:"
kubectl get clusterextension demo-operator -o yaml | grep -A5 conditions
kubectl describe clusterextension demo-operator
echo "--------------------------------------------------"

echo ""
echo "Step 3: Installing a broken update (v0.0.2-broken)..."
kubectl apply -f "$MANIFEST_DIR/03_clusterextension-v0.0.2-broken.yaml"
echo "--------------------------------------------------"
sleep 5
echo "Inspecting broken ClusterExtension (Progressing=True, errors expected):"
kubectl get clusterextension demo-operator -o yaml | grep -A10 conditions
kubectl describe clusterextension demo-operator || true
echo "--------------------------------------------------"

echo ""
echo "Step 4: Fixing the broken extension (v0.0.2-fixed)..."
kubectl apply -f "$MANIFEST_DIR/04_clusterextension-v0.0.2-fixed.yaml"
sleep 5
echo "...Waiting for fixed ClusterExtension to report Installed=True..."
kubectl wait --for=condition=Installed clusterextension/demo-operator --timeout=180s
echo "Status after v0.0.2-fixed installation:"
kubectl get clusterextension demo-operator -o yaml | grep -A10 conditions
kubectl describe clusterextension demo-operator
echo "--------------------------------------------------"

echo ""
echo "Final state of all ClusterExtensions:"
kubectl get clusterextension -A
echo "--------------------------------------------------"

echo ""
echo "--------------------------------------------------"
echo "✅ All ClusterExtensions installed and reconciled successfully."
