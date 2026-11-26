# Solution — Question 4 (RBAC: ServiceAccount, ClusterRole, RoleBindings)

> Inspired by the **Access Control** pattern (Kubernetes Patterns, ch. 26,
> `security/AccessControl/`). Key ideas from the chapter: workloads get their
> own ServiceAccount, least privilege, and *ClusterRoles as reusable templates
> that RoleBindings scope to a namespace*.

---

## 1. Understanding the problem

### The four RBAC objects

```
        WHAT may be done                      WHO, and WHERE
┌───────────────────────────┐        ┌──────────────────────────────────┐
│ Role         (namespaced) │◀─roleRef─│ RoleBinding  (namespaced)        │──▶ subjects:
│ ClusterRole  (cluster)    │◀─roleRef─│   → permissions valid ONLY in   │    User / Group /
│                           │          │     the RoleBinding's namespace │    ServiceAccount
│                           │◀─roleRef─│ ClusterRoleBinding (cluster)     │
└───────────────────────────┘        │   → permissions valid EVERYWHERE  │
                                     └──────────────────────────────────┘
```

| roleRef | Binding | Effective scope |
|---|---|---|
| Role | RoleBinding | that namespace |
| **ClusterRole** | **RoleBinding** | **only the RoleBinding's namespace** ← this task |
| ClusterRole | ClusterRoleBinding | all namespaces + cluster-scoped resources |
| Role | ClusterRoleBinding | ❌ not allowed |

So "one set of permissions, granted in exactly two namespaces" means **one
ClusterRole and two RoleBindings**, one in `jupiter` and one in `europa`. Both
bindings point at the ServiceAccount `jupiter/auditor`. A subject can live in a
different namespace than the RoleBinding.

### API groups matter

RBAC rules match on `apiGroups` + `resources`:

| Resource | apiGroup | in YAML |
|---|---|---|
| pods | core | `""` |
| deployments | apps | `"apps"` |

`kubectl api-resources | grep -E '^pods|^deployments'` shows it: `pods v1`,
`deployments apps/v1`.

### The hidden second fault: no token in the Pod

The app reads `/var/run/secrets/kubernetes.io/serviceaccount/token`. The setup
Deployment has:

```yaml
spec:
  template:
    spec:
      automountServiceAccountToken: false
```

With that setting no token is mounted, the app sends `Bearer none`, and the API
server answers **401 Unauthorized**. Status codes tell you which layer is
wrong:

```
401 Unauthorized  → authentication: who are you?  (no / invalid token)
403 Forbidden     → authorization: RBAC says no   (missing rule / binding / wrong apiGroup)
200 OK            → done
```

The logs before the fix show `401` everywhere. If you switch to the new
ServiceAccount without removing `automountServiceAccountToken: false`, it's
still `401`. If the RBAC is wrong, you get `403`.

---

## 2. The solution

### Imperative (fastest in the exam)

```bash
k -n jupiter create serviceaccount auditor

k create clusterrole pod-auditor --verb=get,list,watch --resource=pods,deployments

k -n jupiter create rolebinding auditor-binding --clusterrole=pod-auditor --serviceaccount=jupiter:auditor
k -n europa  create rolebinding auditor-binding --clusterrole=pod-auditor --serviceaccount=jupiter:auditor

k -n jupiter set serviceaccount deployment pod-auditor auditor
```

Then fix token mounting: `k -n jupiter edit deploy pod-auditor`, type
`/automount` and either delete the line (`dd`) or change `false` to `true`.
The field sits in the **Pod spec**, `spec.template.spec`, at the same
indentation as `containers:` and `serviceAccountName:`.

`kubectl create clusterrole` is smart: it resolves `deployments` to the `apps`
group and generates two rules.

### Declarative, complete YAML

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: auditor
  namespace: jupiter
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: pod-auditor
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: auditor-binding
  namespace: jupiter
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: pod-auditor
subjects:
- kind: ServiceAccount
  name: auditor
  namespace: jupiter
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: auditor-binding
  namespace: europa          # binding lives in europa…
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: pod-auditor
subjects:
- kind: ServiceAccount
  name: auditor
  namespace: jupiter         # …subject lives in jupiter
```

And the full Deployment after the change:

```yaml
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
      serviceAccountName: auditor          # NEW
      # automountServiceAccountToken: false   ← REMOVED (or set to true)
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
```

### Verify

```bash
A=system:serviceaccount:jupiter:auditor
k auth can-i list pods             -n jupiter  --as $A   # yes
k auth can-i watch deployments.apps -n europa  --as $A   # yes
k auth can-i list pods             -n ganymede --as $A   # no
k auth can-i delete pods           -n jupiter  --as $A   # no
k auth can-i list pods -A                      --as $A   # no
k auth can-i --list -n europa --as $A                    # full picture

k -n jupiter logs deploy/pod-auditor --tail=2
# 11:30:09 pods/jupiter=200 deployments/jupiter=200 pods/europa=200 deployments/europa=200
```

`deployments.apps` (resource.group) is the unambiguous way to name the
resource in `auth can-i`.

---

## 3. Why

- **Why a ClusterRole when no cluster-wide access is wanted?** It's a
  *template*: defined once, reused in many namespaces through RoleBindings.
  Two Roles (one per namespace) would grant the same thing, but the task asks
  for a ClusterRole. It's also the pattern the book recommends to avoid
  duplicated Roles drifting apart.
- **Why RoleBindings and not a ClusterRoleBinding?** A ClusterRoleBinding
  grants the rules in **every** namespace, including `ganymede`, which the note
  forbids.
- **Why a dedicated ServiceAccount?** Binding to `jupiter:default` would hand
  the permissions to *every* Pod in the namespace that doesn't set a
  ServiceAccount. Least privilege means one identity per workload.
- **Why does automount matter?** RBAC grants permissions to an identity. The
  Pod still has to *prove* that identity with a token. In Kubernetes ≥ 1.22
  that's a short-lived projected token, mounted only if automount is enabled on
  the Pod (or the SA, with the Pod setting winning).

---

## 4. Other ways to solve it

| Approach | Satisfies this task? | Real-life use |
|---|---|---|
| 1 ClusterRole + 2 RoleBindings | ✅ | the standard "same rights in N namespaces" |
| 2 Roles + 2 RoleBindings | ❌ task requires ClusterRole `pod-auditor` | fine when each namespace needs different rules |
| ClusterRole + ClusterRoleBinding | ❌ also grants `ganymede` & all others | cluster-wide controllers/monitoring |
| Bind the built-in `view` ClusterRole | ❌ grants far more (configmaps, services…) | quick read-only access for humans |
| One RoleBinding with the SA listed twice | ❌ a RoleBinding only works in its own namespace | — |
| Bind to `jupiter:default` | ❌ forbidden, over-broad | never for app-specific rights |
| Leave `automountServiceAccountToken: false` + `serviceAccountName` | ❌ 401, no token | when the app never calls the API (security hardening) |
| `automountServiceAccountToken: true` instead of deleting the line | ✅ | explicit is fine |

---

## 5. Common mistakes

1. **`deployments` under `apiGroups: [""]`.** The API server accepts the rule,
   but it matches nothing: logs show `deployments/...=403` while pods are `200`.
2. **ClusterRoleBinding** "because it's a ClusterRole". The binding type
   decides the scope, not the role type.
3. **Wrong subject namespace** in the europa binding (`--serviceaccount=europa:auditor`
   or a missing `namespace:` in YAML). It then refers to a non-existent SA in europa.
4. **Forgetting `automountServiceAccountToken: false`.** RBAC is perfect,
   `auth can-i` says yes, and the app still gets `401`. Always confirm with the
   app's own output, not just `can-i`.
5. **Editing `serviceAccount` instead of `serviceAccountName`**. The former is
   a deprecated alias. `kubectl set serviceaccount` handles it for you.
6. **Granting `*` verbs or the built-in `view`/`edit` roles.** Over-privileged.
7. **Expecting a running Pod to pick up a new ServiceAccount.** A Pod's
   ServiceAccount is immutable. Changing the Deployment template rolls out new Pods.

---

## 6. Docs to bookmark

- Using RBAC Authorization:
  https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- Configure Service Accounts for Pods (incl. opting out of automount):
  https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/
- Service Accounts concept:
  https://kubernetes.io/docs/concepts/security/service-accounts/
- Accessing the API from a Pod:
  https://kubernetes.io/docs/tasks/run-application/access-api-from-pod/
- `kubectl auth can-i`:
  https://kubernetes.io/docs/reference/kubectl/generated/kubectl_auth/kubectl_auth_can-i/
