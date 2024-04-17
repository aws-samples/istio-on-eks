#!/bin/bash
for CRD in 'secrets-store.csi.x-k8s.io' 'cert-manager' 'gatekeeper'; do
    kubectl get crd -o go-template='{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' | grep $CRD | xargs kubectl delete crd
done