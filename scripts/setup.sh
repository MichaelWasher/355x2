#!/bin/bash

set -x
# Add Resources
oc apply -f ./manifests/ns.yaml

oc project 355x2
oc apply -f ./manifests/svc.yaml
oc apply -f ./manifests/dispursed-pods.yaml
oc apply -f ./manifests/collector-pods.yaml

# Wait for Pods to be ready
while [[ $(kubectl get pods -l app=receiver -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for receiver pod" && sleep 1; done
while [[ $(kubectl get pods -l app=requester -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for requester pod" && sleep 1; done
