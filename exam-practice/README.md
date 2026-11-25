# CKA Exam-Style Practice Questions

Each folder is one self-contained, exam-style task.

```
qNN-<topic>/
├── question.md   # The task, worded like the real exam. Read ONLY this first.
├── setup.sh      # Builds the starting state in your cluster (run before attempting)
├── verify.sh     # Grades your work (PASS/FAIL per check)
├── solution.md   # Reference solution + explanation (don't peek!)
└── cleanup.sh    # Removes everything the question created
```

## Workflow

```bash
cd exam-practice/q03-troubleshoot-probes
./setup.sh            # 1. prepare the environment
cat question.md       # 2. read the task, start a timer (~6-8 min per question)
# ... solve it with kubectl / vim, using only kubernetes.io/docs ...
./verify.sh           # 3. grade yourself
./cleanup.sh          # 4. reset when done (or re-run setup.sh to retry)
```

## Exam habits to practise

```bash
alias k=kubectl
export do="--dry-run=client -o yaml"
export now="--force --grace-period 0"
```

- On the real exam every task starts with "connect to host X" / a context
  switch. Here everything runs on your local cluster, so that line is just a reminder.
- Only https://kubernetes.io/docs (and helm.sh/docs, gateway-api docs) are allowed.

## Index

Questions are numbered across both practice repos. q01 and q02 live in
[`harrylog/cka-guide`](https://github.com/harrylog/cka-guide/tree/main/exam-practice)
(CKA Study Guide repo). From q03 on, questions are here and draw on the
*Kubernetes Patterns* examples in this repo.

| #  | Topic                                   | Domain                 | Weight | Repo / pattern |
|----|-----------------------------------------|------------------------|--------|----------------|
| 01 | Sidecar container / shared volume       | Workloads & Scheduling | ~4%    | cka-guide |
| 02 | NetworkPolicy (per-port, per-source)    | Services & Networking  | ~7%    | cka-guide |
| 03 | Broken liveness/readiness, startupProbe | Troubleshooting        | ~7%    | Health Probe (`foundational/cn4_HealthProbe`) |
