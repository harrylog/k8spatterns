#!/usr/bin/env bash
kubectl delete namespace jupiter europa ganymede --ignore-not-found
kubectl delete clusterrole pod-auditor --ignore-not-found
for crb in $(kubectl get clusterrolebinding -o json | jq -r '.items[] | select(any(.subjects[]?; .namespace=="jupiter")) | .metadata.name'); do
  kubectl delete clusterrolebinding "$crb"
done
