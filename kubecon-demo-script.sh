#!/usr/bin/env bash

#
# Welcome to the kubecon-NA 2025 demo
#
trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT

# assumes it's running from a local clone of operator-framework/operator-controller
make -C ../../operator-framework/operator-controller/ run-experimental
sleep 10

# waiting for operator-controller deployment to complete
kubectl rollout status -n olmv1-system deployment/operator-controller-controller-manager

# checking catalogd controller is available
kubectl wait --for=condition=Available -n olmv1-system deploy/catalogd-controller-manager --timeout=1m

# inspect crds (clustercatalog)
kubectl get crds -A

# installing demo ClusterCatalog
kubectl apply -f manifests/00_clustercatalog.yaml

#  checking clustercatalog is serving
kubectl wait --for=condition=Serving clustercatalog/olm-kubecon2025-demo --timeout=60s
#  checking clustercatalog is finished unpacking
kubectl wait --for=condition=Progressing=True clustercatalog/olm-kubecon2025-demo --timeout=60s

# inspecting the demo catalog
kubectl describe clustercatalog olm-kubecon2025-demo

# installing demo namespaces (install|watch), service accounts
kubectl apply -f manifests/01_clusterextension-setup.yaml

# installing demo ClusterExtension, pinned to v0.0.1, watching namespace 'demo'
kubectl apply -f manifests/02_clusterextension-v0.0.1.yaml

# waiting for demo-operator.v0.0.1 to report Installed=True
kubectl wait --for=condition=Installed clusterextension/demo-operator --timeout=180s

# checking status on demo-operator.v0.0.1
kubectl get clusterextensions.olm.operatorframework.io demo-operator -o yaml | yq '.spec'
kubectl get clusterextensions.olm.operatorframework.io demo-operator -o yaml | yq '.status.conditions[]| select(.type == "Installed")'

## check the webhooks
## exercise webhooks with invalid/valid manifests
## show validating/mutating webhooks

# upgrading demo ClusterExtension to v0.0.2, with a broken manifest
kubectl apply -f manifests/03_clusterextension-v0.0.2-broken.yaml
sleep 5
kubectl get clusterextension demo-operator -o yaml | yq '.status.conditions[] | select(.type=="Progressing")'

#  ... oops!  We forgot to remove the watch namespace!  Fix that
kubectl apply -f manifests/04_clusterextension-v0.0.2-fixed.yaml
#  status after demo-operator.v0.0.2 fixed installation
kubectl wait --for=jsonpath='{.status.install.bundle.name}="demo-operator.v0.0.2"' clusterextension demo-operator --timeout=30s
kubectl wait --for=condition=Installed clusterextension/demo-operator --timeout=180s

## worth mentioning that the existing application isn't broken during this process, just not proceeding...

#  ... fixed!
kubectl get clusterextension demo-operator -o yaml | yq '.status.conditions[] | select(.type=="Installed")'

# final status
kubectl get clusterextension -A

## check the webhooks
##
## display CERs (once before upgrade, and once after?)
##
