#!/usr/bin/env bash
# Builds the starting state for Question 3. Safe to re-run (resets the task).
set -euo pipefail

NS=saturn

kubectl delete namespace "$NS" --ignore-not-found --wait=true >/dev/null
kubectl create namespace "$NS" >/dev/null

kubectl apply -f - >/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: random-api
  namespace: saturn
  labels:
    app: random-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: random-api
  template:
    metadata:
      labels:
        app: random-api
        tier: backend
    spec:
      containers:
      - name: api
        image: busybox:stable
        command: ["sh", "-c"]
        args:
        - |
          echo "$(date) warming up caches (takes ~25s)..."
          sleep 25
          mkdir -p /www
          echo ok    > /www/healthz
          echo ready > /www/ready
          echo "$(date) listening on :8080"
          exec httpd -f -v -p 8080 -h /www
        ports:
        - name: web
          containerPort: 8080
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          periodSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: http
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: random-api
  namespace: saturn
spec:
  selector:
    app: random-api
  ports:
  - name: http
    port: 80
    targetPort: web
YAML

# Decoy: a healthy Deployment in the same namespace that must stay untouched
kubectl -n "$NS" create deployment random-cache --image=busybox:stable --replicas=1 \
  -- sh -c 'mkdir -p /www && echo cache > /www/index.html && exec httpd -f -p 8080 -h /www' >/dev/null

kubectl -n "$NS" rollout status deploy/random-cache --timeout=90s >/dev/null
echo "Setup complete for Question 3 (namespace: $NS)."
echo "Give it ~30s and look around: kubectl -n $NS get pods"
