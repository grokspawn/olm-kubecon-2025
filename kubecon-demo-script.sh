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

# checking ClusterExtensionRevision (CER) after install
kubectl get clusterextensionrevision -A

# upgrading demo ClusterExtension to v0.0.2, with a broken manifest
kubectl apply -f manifests/03_clusterextension-v0.0.2-broken.yaml
sleep 5
kubectl get clusterextension demo-operator -o yaml | yq '.status.conditions[] | select(.type=="Progressing")'

#  ... oops!  We forgot to remove the watch namespace!  Fix that
kubectl apply -f manifests/04_clusterextension-v0.0.2-fixed.yaml

#  status after demo-operator.v0.0.2 fixed installation
kubectl wait --for=jsonpath='{.status.install.bundle.name}="demo-operator.v0.0.2"' clusterextension demo-operator --timeout=30s
kubectl wait --for=condition=Installed clusterextension/demo-operator --timeout=180s

#  ... fixed!
kubectl get clusterextension demo-operator -o yaml | yq '.status.conditions[] | select(.type=="Installed")'

# final status
kubectl get clusterextension -A

# checking the installed validating webhook configuration
kubectl get validatingwebhookconfigurations.admissionregistration.k8s.io -A

# checking the installed mutating webhook configuration
kubectl get mutatingwebhookconfigurations.admissionregistration.k8s.io -A

# inspecting where the validating webhook is running (in-cluster service endpoint)
kubectl describe validatingwebhookconfigurations.admissionregistration.k8s.io vwebhooktest.kb.io | sed -n '/Service:/,/Port:/p'

# inspecting where the mutating webhook is running (in-cluster service endpoint)
kubectl describe mutatingwebhookconfiguration mwebhooktest.kb.io | sed -n '/Service:/,/Port:/p'

# demonstrating webhook behavior: invalid CRs are rejected with an error (expected)
kubectl apply -f samples/invalid.yaml || true

# installing a valid CR which should get accepted and succeed
kubectl apply -f samples/valid.yaml

# checking ClusterExtensionRevisions (CERs) after upgrade
kubectl get clusterextensionrevision -A

# inspecting the diff between two ClusterExtensionRevisions (CERs) and comparing the RBAC
diff -u --color=always <(kubectl get clusterextensionrevision demo-operator-1 -o yaml | yq e '.spec.phases[] | select(.name=="rbac") | .objects[].object | "\(.kind)/\(.metadata.name) \(.rules | tojson)"' -) <(kubectl get clusterextensionrevision demo-operator-2 -o yaml | yq e '.spec.phases[] | select(.name=="rbac") | .objects[].object | "\(.kind)/\(.metadata.name) \(.rules | tojson)"' -)

