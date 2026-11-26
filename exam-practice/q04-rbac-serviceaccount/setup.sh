#!/usr/bin/env bash
# Builds the starting state for Question 4. Safe to re-run (resets the task).
set -euo pipefail

for ns in jupiter europa ganymede; do
  kubectl delete namespace "$ns" --ignore-not-found --wait=true >/dev/null
done
kubectl delete clusterrole pod-auditor --ignore-not-found >/dev/null
# remove any ClusterRoleBinding a previous attempt created for jupiter:auditor
for crb in $(kubectl get clusterrolebinding -o json | jq -r '.items[] | select(any(.subjects[]?; .namespace=="jupiter")) | .metadata.name'); do
  kubectl delete clusterrolebinding "$crb" >/dev/null
done

for ns in jupiter europa ganymede; do kubectl create namespace "$ns" >/dev/null; done

# Workloads to be audited (and a decoy namespace that must stay out of reach)
kubectl -n europa   create deployment billing  --image=busybox:stable --replicas=2 -- sleep infinity >/dev/null
kubectl -n ganymede create deployment payroll  --image=busybox:stable --replicas=1 -- sleep infinity >/dev/null

kubectl apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pod-auditor
  namespace: jupiter
  labels:
    app: pod-auditor
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pod-auditor
  template:
    metadata:
      labels:
        app: pod-auditor
    spec:
      automountServiceAccountToken: false
      containers:
      - name: auditor
        image: curlimages/curl:8.11.1
        command: ["sh", "-c"]
        args:
        - |
          API=https://kubernetes.default.svc
          SA=/var/run/secrets/kubernetes.io/serviceaccount
          while true; do
            TOKEN=$(cat $SA/token 2>/dev/null || echo none)
            line="$(date +%T)"
            for ns in jupiter europa; do
              p=$(curl -sk -m 3 -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" $API/api/v1/namespaces/$ns/pods)
              d=$(curl -sk -m 3 -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" $API/apis/apps/v1/namespaces/$ns/deployments)
              line="$line pods/$ns=$p deployments/$ns=$d"
            done
            echo "$line"
            sleep 5
          done
YAML

kubectl -n jupiter rollout status deploy/pod-auditor --timeout=180s >/dev/null
kubectl -n europa  rollout status deploy/billing     --timeout=90s  >/dev/null
echo "Setup complete for Question 4 (namespaces: jupiter, europa, ganymede)."
