# Solution — Question 3 (Troubleshooting: health probes)

> Inspired by the **Health Probe** pattern (Kubernetes Patterns, ch. 4,
> `foundational/cn4_HealthProbe/` in this repo, especially
> `startup-deployment.yml`).

---

## 1. Understanding the problem

### The three probes and what each one does when it fails

| Probe | Question it answers | On failure | Runs when |
|---|---|---|---|
| `startupProbe` | "Has the app finished booting?" | container is **killed** (restartPolicy applies) | first; **liveness and readiness are disabled until it succeeds once** |
| `livenessProbe` | "Is the app still alive / not hung?" | container is **killed and restarted** | after startup succeeded, for the whole life of the container |
| `readinessProbe` | "Can the app take traffic right now?" | Pod is **removed from Service endpoints** (no restart) | after startup succeeded, for the whole life of the container |

```
container start
     │
     ▼
┌──────────────┐ success (once) ┌─────────────────────────────────────────┐
│ startupProbe │ ─────────────▶ │ livenessProbe  → fail ⇒ restart         │
│ (if defined) │                │ readinessProbe → fail ⇒ not in Endpoints│
└──────────────┘                └─────────────────────────────────────────┘
     │ failureThreshold consecutive failures
     ▼
   KILL
```

### When does the kubelet kill a container?

A probe "fails" after `failureThreshold` **consecutive** failures. The first
probe runs after `initialDelaySeconds`, then every `periodSeconds`. So the
container is killed at roughly:

```
t_kill ≈ initialDelaySeconds + periodSeconds × (failureThreshold − 1)
```

### What was broken (two faults, the second hidden behind the first)

```
t=0s        container starts, app is "warming up" (sleep 25), nothing listens on :8080
t=0,5,10s   livenessProbe GET :8080/healthz → connection refused ×3
t≈10-15s    kubelet: "Container api failed liveness probe, will be restarted"
            ... the app never reaches t=25s → restart loop → CrashLoopBackOff
```

**Fault 1: liveness kills the app during startup.** The liveness probe
(`period 5`, `threshold 3`, no delay) gives the container about 10–15 s, but the
app needs up to 30 s. The task forbids touching the liveness probe because its
fast reaction to a hang is wanted. The right tool is a **startupProbe**: it
holds back liveness until the app has started once.

**Fault 2: readiness points to a port name that doesn't exist.**

```yaml
ports:
- name: web            # the only named port
  containerPort: 8080
readinessProbe:
  httpGet:
    port: http         # ← no container port named "http"
```

The API server accepts this because `http` is a valid port *name*. The kubelet
fails at runtime, and the event says so explicitly:

```
Readiness probe errored and resulted in unknown state: strconv.Atoi: parsing "http": invalid syntax
```

So even once the app survives startup, it never becomes Ready, the Service
has no endpoints, and you get `wget: can't connect` / `Connection refused`.

### How to find this in the exam (the troubleshooting flow)

```bash
k -n saturn get pods                      # 0/1 Running, RESTARTS climbing → probes
k -n saturn describe pod <pod>            # Events at the bottom: Liveness/Readiness probe failed
k -n saturn get events --sort-by=.lastTimestamp | grep -i probe
k -n saturn logs <pod> --previous         # app log from the killed container: "warming up..." and nothing more
k -n saturn get endpointslices -l kubernetes.io/service-name=random-api   # endpoints empty / not ready
k -n saturn get svc random-api -o yaml    # targetPort: web → don't touch the port names!
```

`Liveness probe failed … connection refused` plus a log that stops at
"warming up" means the app is killed before it ever listens.

---

## 2. The solution

### Option A: `kubectl edit` (what you'd do in the exam)

```bash
k -n saturn edit deploy random-api
```

In vim, type `/readinessProbe` to jump to the probe. The probes sit under
`spec.template.spec.containers[0]`, so they are indented at the **same level as
`image:`, `ports:`, `livenessProbe:`** (8 spaces in `kubectl edit` output).

1. Under `readinessProbe.httpGet`, change `port: http` to `port: web` (or `port: 8080`).
2. Below the liveness probe block, add a `startupProbe` at the same indentation
   as `livenessProbe:`. Use `:set paste` before pasting so vim doesn't
   auto-indent.

The complete container section after the fix (as `kubectl get -o yaml`
prints it, defaults included):

```yaml
    spec:
      containers:
      - args:
        - |
          echo "$(date) warming up caches (takes ~25s)..."
          sleep 25
          mkdir -p /www
          echo ok    > /www/healthz
          echo ready > /www/ready
          echo "$(date) listening on :8080"
          exec httpd -f -v -p 8080 -h /www
        command:
        - sh
        - -c
        image: busybox:stable
        imagePullPolicy: IfNotPresent
        livenessProbe:
          failureThreshold: 3
          httpGet:
            path: /healthz
            port: 8080
            scheme: HTTP
          periodSeconds: 5
          successThreshold: 1
          timeoutSeconds: 1
        name: api
        ports:
        - containerPort: 8080
          name: web
          protocol: TCP
        readinessProbe:
          failureThreshold: 3
          httpGet:
            path: /ready
            port: web
            scheme: HTTP
          periodSeconds: 5
          successThreshold: 1
          timeoutSeconds: 1
        resources: {}
        startupProbe:
          failureThreshold: 12
          httpGet:
            path: /healthz
            port: 8080
            scheme: HTTP
          periodSeconds: 5
          successThreshold: 1
          timeoutSeconds: 1
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
```

Save with `:wq`. A new ReplicaSet rolls out.

### Option B: the full Deployment as a file

```bash
k -n saturn get deploy random-api -o yaml > q3.yaml   # backup + working copy (gitignored)
```

Or write it clean and `k apply -f`:

```yaml
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
        startupProbe:
          httpGet:
            path: /healthz
            port: 8080
          periodSeconds: 5
          failureThreshold: 12      # up to 5 × 12 = 60 s to start
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          periodSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /ready
            port: web               # was "http", a name that doesn't exist
          periodSeconds: 5
```

### Verify

```bash
k -n saturn get pods -w                  # 0/1 for ~25-30 s, then 1/1, RESTARTS stays 0
k -n saturn get endpointslices -l kubernetes.io/service-name=random-api
k -n saturn run tmp --image=busybox:stable --rm -it --restart=Never -- \
  wget -qO- -T 2 http://random-api.saturn/healthz    # → ok
```

Then run `./verify.sh`.

---

## 3. Why

- **Why a startupProbe instead of a longer liveness delay?**
  `initialDelaySeconds: 30` on liveness would also make the app start. But it
  is (a) forbidden here and (b) worse in general: the delay is fixed. A fast
  start still waits 30 s before liveness protects it, and a slow start (say
  35 s under load) still gets killed. A startupProbe *polls*, so liveness takes
  over the moment the app is up, and it allows a generous maximum
  (`5 s × 12 = 60 s`). This is exactly the "Health Probe" pattern's argument
  for startup probes.
- **Why check the same endpoint as liveness?** "Started" for this app means
  "the HTTP server answers `/healthz`". Reusing the liveness endpoint is the
  common idiom (the book's `startup-deployment.yml` does the same).
- **Why `periodSeconds: 5`, `failureThreshold: 12`?** Kill time
  ≈ `5 × (12 − 1) = 55 s` ≥ 30 s, with margin. A short period means the app is
  marked started at most 5 s after it's actually up.
- **Why fix the probe's port instead of renaming the container port?** The
  Service uses `targetPort: web`. Renaming the container port to `http` would
  make the readiness probe work, but then the Service would point at a port
  name that no longer exists, and traffic would still fail. The note also
  forbids changing `ports`.
- **`port: web` vs `port: 8080`**: both are correct. A named port is more
  robust if the number ever changes, and it's consistent with the Service.

---

## 4. Other ways to solve it

| Approach | Works? | Allowed here? | When it's right in real life |
|---|---|---|---|
| **startupProbe** (httpGet `/healthz`) + fix readiness port | ✅ | ✅ | the standard answer for slow-starting apps |
| startupProbe with `tcpSocket: {port: 8080}` | ✅ (app only listens once ready) | ✅ (verify accepts any type) | when there's no HTTP health endpoint |
| startupProbe with `exec: [test, -f, /www/healthz]` | ✅ | ✅ | non-network apps that write a marker file |
| `livenessProbe.initialDelaySeconds: 30` | ✅ mostly | ❌ changes liveness | old clusters (<1.18) without startup probes |
| raise liveness `failureThreshold` to 7+ | ✅ | ❌ hang detection becomes > 15 s | rarely; it slows hang detection for ever |
| delete the liveness probe | ✅ | ❌ | almost never; hung processes then live for ever |
| rename container port `web` → `http` | ❌ Service breaks | ❌ | never when a Service references the name |
| startupProbe with defaults (`period 10`, `threshold 3`) | ⚠️ kill at ~20 s, before the 30 s worst case | ❌ verify rejects | only if startup is < 20 s |

---

## 5. Common mistakes

1. **Fixing only the visible fault.** After adding the startupProbe the
   restarts stop, but Pods stay `0/1`. Always re-check `READY` and the Service
   endpoints, not only `RESTARTS`.
2. **Assuming the startupProbe budget is `period × threshold`.** The kill comes
   on the N-th *consecutive* failure, at about
   `initialDelay + period × (threshold − 1)`. With defaults (`10 × 3`) that's
   about 20 s, not 30 s.
3. **Putting `startupProbe` at the wrong level.** It belongs to the container
   (`spec.template.spec.containers[].startupProbe`), at the same indentation as
   `livenessProbe`, not under `spec` of the Pod or the Deployment.
4. **Renaming the container port** to match the probe. That fixes readiness and
   breaks the Service (`targetPort: web`).
5. **Believing `kubectl rollout status` alone.** It reports success only once
   the new Pods are Ready, but check `RESTARTS` too: an app can flap between
   Ready and killed.
6. **Reading logs of the wrong container instance.** Use `k logs <pod> --previous`
   to see the log of the container that was killed.
7. **Touching the decoy.** `random-cache` is healthy. Don't "fix" it.

---

## 6. Docs to bookmark

- Configure Liveness, Readiness and Startup Probes:
  https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/
- Probe concepts (Pod lifecycle → container probes):
  https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#container-probes
- Debug Running Pods:
  https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/
- Debug Services:
  https://kubernetes.io/docs/tasks/debug/debug-application/debug-service/
- Probe field reference (`Probe` v1 core):
  https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#lifecycle-1
