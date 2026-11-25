# Question 3 — Weight: 7%

> **Context**
> You must connect to the correct host. Failure to do so may result in a zero score.
> `[candidate@base] $ ssh cka-node03`
> *(Practice note: just use your local cluster — run `./setup.sh` first.)*

---

**Task**

The Deployment `random-api` in namespace `saturn` was recently rolled out, but
the Service `random-api` in the same namespace does not serve any traffic and
the Pods of the Deployment keep restarting.

The application in container `api` needs up to **30 seconds** to start. After
startup it answers HTTP requests on port `8080`.

Troubleshoot and fix the Deployment `random-api` so that:

- both replicas become `Ready` and stay running without further restarts,
- the Service `random-api` serves requests on port `80`, for example
  `http://random-api.saturn/healthz`,
- a container that hangs **after** it has started is still restarted by its
  liveness probe within 15 seconds, exactly as it is configured now.

> **Note**
> - Do not modify the Service `random-api` or the Deployment `random-cache`.
> - Do not change the container image, `command`, `args` or `ports` of the `api` container.
> - Do not remove the existing liveness and readiness probes, and do not change
>   any setting of the existing liveness probe.
