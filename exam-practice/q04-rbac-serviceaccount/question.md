# Question 4 — Weight: 7%

> **Context**
> You must connect to the correct host. Failure to do so may result in a zero score.
> `[candidate@base] $ ssh cka-node04`
> *(Practice note: just use your local cluster — run `./setup.sh` first.)*

---

**Task**

The Deployment `pod-auditor` in namespace `jupiter` periodically queries the
Kubernetes API for Pods and Deployments in the namespaces `jupiter` and
`europa`. All of its requests are currently rejected.

1. Create a new ServiceAccount `auditor` in namespace `jupiter`.
2. Create a new ClusterRole `pod-auditor` that only allows the verbs `get`,
   `list` and `watch` on the resources `pods` and `deployments`.
3. Grant the ServiceAccount `auditor` the permissions of the ClusterRole
   `pod-auditor` in the namespaces `jupiter` and `europa` **only**.
   Name the binding(s) `auditor-binding`.
4. Update the Deployment `pod-auditor` to run with the ServiceAccount `auditor`.

After your changes, every request logged by the `auditor` container must
succeed (HTTP `200`).

> **Note**
> - The ServiceAccount `auditor` must not be able to access any other
>   namespace, for example `ganymede`, and must not be able to modify any resource.
> - Do not grant any permissions to the `default` ServiceAccount.
> - Do not modify the `command` or `args` of the `auditor` container.
