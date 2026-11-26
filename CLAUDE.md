# CLAUDE.md

This repo is the example code of *Kubernetes Patterns, 2nd Edition* (Ibryam &
Huß), grouped by pattern category: `foundational/`, `behavioral/`,
`structural/`, `configuration/`, `security/`, `advanced/` (one `cnNN_<Pattern>/`
folder per chapter, each with a `README.adoc`). It also holds the user's own CKA
exam practice in `exam-practice/`. GitHub: `harrylog/k8spatterns` (branch
`main`, SSH remote).

Questions q01–q02 live in the sibling repo `harrylog/cka-guide`
(`~/Downloads/k8s books/cka-study-guide/exam-practice/`). From q03 on they live
**here**. Numbering continues across both repos. Base new questions on a
pattern from this book where it fits the CKA curriculum (e.g. Health Probe →
probe troubleshooting, Managed Lifecycle, Automated Placement → affinity/taints,
Declarative Deployment → rollouts, Elastic Scale → HPA, Access Control → RBAC,
Controller/Operator → CRDs).

## Exam practice questions (`exam-practice/`)

When the user asks for "a CKA question", "next practice scenario" or similar,
create a **new** question here. `exam-practice/README.md` has the index table
listing the topics already covered. Always pick a topic that isn't there yet,
and add a row to the table.

### Layout: one folder per question

```
exam-practice/qNN-<topic>/
├── question.md   # task worded exactly like the real exam
├── setup.sh      # builds the starting state; idempotent (deletes and recreates its namespaces)
├── verify.sh     # grades with [PASS]/[FAIL] lines + "Score: x/y" + "RESULT: PASS|FAIL"
├── solution.md   # in-depth explanation (see below)
└── cleanup.sh    # deletes everything the question created
```

`exam-practice/**/q*.yaml` is gitignored. Those are the user's working files
while solving, so never name a deliverable `qN.yaml`.

### question.md format

- Header `# Question N — Weight: X%` (real exam weights are 4–8%).
- A quoted **Context** block with the "You must connect to the correct host…"
  line and `ssh cka-nodeNN`, plus a practice note saying to run `./setup.sh`.
- A **Task** section using exact names (namespace, resource, labels, ports),
  then a **Note** block with the constraints ("Do not modify…", decoys that
  must not match, etc.).
- Never give hints that reveal the solution. Include traps the real exam uses,
  for example decoy objects in other namespaces, or "don't relabel" so the user
  has to know built-in labels.

### solution.md format (the user wants depth)

1. **Understanding the problem**: how the mechanism works, with ASCII diagrams
   where helpful.
2. **The solution**: complete, valid YAML. **Never use placeholders like
   `[...unchanged...]`**; the user once pasted those literally. Explain where
   each block goes (which YAML path and indentation), how to apply it, and how
   to verify it.
3. **Why**: the reasoning behind each design choice.
4. **Other ways to solve it**: alternatives and why they do or don't satisfy the
   task, with a summary table.
5. **Common mistakes**.
6. **Docs to bookmark**: kubernetes.io links only (allowed in the exam).

### verify.sh conventions

- `set -uo pipefail`, a `check "<desc>" <exit-code>` helper, `jq` for JSON.
- Grade the **real behaviour** (traffic, logs, `auth can-i`…), not just the
  spec. Accept every valid answer, and add checks that catch the classic wrong
  answer.
- Don't trust `kubectl rollout status` alone. It passes on an unchanged
  Deployment.
- `kubectl logs deploy/X` can pick an old terminating Pod. Select a Running Pod
  that has the expected container.

### Workflow before telling the user a question is ready

Test every question end to end on the local cluster:
setup → verify fails → apply the reference solution → verify passes → (ideally)
apply a common wrong answer and confirm verify fails → **re-run setup.sh** so the
task is left fresh for the user. Never leave the solution applied.

## Local environment facts

- Namespaces already used by earlier questions: `mercury` (q01), `venus`/`mars`
  (q02), `saturn` (q03), `jupiter`/`europa`/`ganymede` (q04). Pick a fresh one for each new question.
- Single-node **k3s v1.34** (`kubectl` context `default`). Its NetworkPolicy
  controller is active, so policies are enforced.
- `busybox:stable` is cached locally. Prefer it for test workloads
  (`httpd -f -p PORT -h DIR` makes a quick web server).
- `jq` is installed. `gh` is **not**.
- Image pulls from Docker Hub work. `curlimages/curl:8.11.1` is cached and is a
  working in-cluster API client (busybox `wget` fails TLS against the API server).
- kubeconfig has a single context `default` (namespace `default`). Still pass
  `-n` explicitly in scripts.
- The user's shell is **zsh**: unquoted `$var` doesn't word-split, so wrap
  bash-isms in `bash -c '…'`.
- busybox `tail -f` exits with code 1 if the file doesn't exist yet. `tail -F`
  waits for it.
- Multi-node topics (kubeadm join/upgrade, drain across nodes, etcd on a
  separate control plane) can't be practised for real on this cluster. Say so,
  and simulate where possible.

## Progress

| # | Topic | Domain |
|---|---|---|
| 01 | Sidecar container + emptyDir log streaming | Workloads & Scheduling |
| 02 | NetworkPolicy, per-port / per-source rules | Services & Networking |
| 03 | Broken liveness/readiness probes, startupProbe | Troubleshooting |
| 04 | RBAC: ServiceAccount, ClusterRole + RoleBindings, token automount | Cluster Architecture |

(`exam-practice/README.md` is the source of truth; keep both in sync.)

CKA curriculum weights: Troubleshooting 30%, Cluster Architecture/Installation/
Configuration 25%, Services & Networking 20%, Workloads & Scheduling 15%,
Storage 10%. Domains not covered yet: **Cluster
Architecture** beyond RBAC (Helm/Kustomize, CRDs/operators), **Storage** (PV/PVC/
StorageClass). Also uncovered: Gateway API/Ingress, HPA, PriorityClass,
scheduling (taints/affinity), and CoreDNS.
