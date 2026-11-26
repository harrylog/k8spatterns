#!/usr/bin/env bash
# Grades Question 4.
set -uo pipefail

NS=jupiter
SA=auditor
AS="system:serviceaccount:$NS:$SA"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then echo "  [PASS] $1"; pass=$((pass+1)); else echo "  [FAIL] $1"; fail=$((fail+1)); fi; }
can()    { [ "$(kubectl auth can-i "$@" 2>/dev/null)" = "yes" ]; }
cannot() { ! can "$@"; }

echo "Question 4 — RBAC for a ServiceAccount"

kubectl -n "$NS" get sa "$SA" >/dev/null 2>&1; check "ServiceAccount $NS/$SA exists" $?

# ---------- ClusterRole ----------
cr=$(kubectl get clusterrole pod-auditor -o json 2>/dev/null); cr=${cr:-'{}'}
jq -e '.kind=="ClusterRole"' <<<"$cr" >/dev/null; check "ClusterRole pod-auditor exists" $?
# Only read verbs, only pods (core) and deployments (apps); no wildcards
jq -e '(.rules // []) as $r
       | ($r|length) > 0
       and all($r[]; all(.verbs[]; IN("get","list","watch")))
       and all($r[]; all(.resources[]; IN("pods","deployments")))
       and all($r[]; all(.apiGroups[]; IN("","apps")))
       and ([$r[] | (.resourceNames // []) | length] | add // 0) == 0' <<<"$cr" >/dev/null
check "ClusterRole only allows get/list/watch on pods and deployments (no wildcards)" $?
jq -e '.kind=="ClusterRole" and .aggregationRule == null' <<<"$cr" >/dev/null; check "ClusterRole is not an aggregated role" $?

# ---------- bindings ----------
for ns in jupiter europa; do
  rb=$(kubectl -n "$ns" get rolebinding auditor-binding -o json 2>/dev/null); rb=${rb:-'{}'}
  jq -e --arg ns "$NS" --arg sa "$SA" '
        .roleRef.kind=="ClusterRole" and .roleRef.name=="pod-auditor"
        and any(.subjects[]?; .kind=="ServiceAccount" and .name==$sa and .namespace==$ns)' <<<"$rb" >/dev/null
  check "RoleBinding $ns/auditor-binding binds ClusterRole pod-auditor to $NS:$SA" $?
done

n=$(kubectl get clusterrolebinding -o json | jq --arg ns "$NS" --arg sa "$SA" \
    '[.items[] | select(any(.subjects[]?; .kind=="ServiceAccount" and .name==$sa and .namespace==$ns))] | length')
[ "$n" -eq 0 ]; check "no ClusterRoleBinding grants anything to $NS:$SA" $?

# ---------- effective permissions (real authorizer) ----------
ok=0
for ns in jupiter europa; do
  for v in get list watch; do
    can "$v" pods -n "$ns" --as "$AS" || ok=1
    can "$v" deployments.apps -n "$ns" --as "$AS" || ok=1
  done
done
check "$SA can get/list/watch pods and deployments in jupiter and europa" $ok

ok=0
cannot list pods -n ganymede --as "$AS"            || ok=1
cannot list deployments.apps -n ganymede --as "$AS" || ok=1
cannot list pods -n default --as "$AS"             || ok=1
cannot list pods -A --as "$AS"                     || ok=1
check "$SA cannot read other namespaces (ganymede, default, cluster-wide)" $ok

ok=0
for ns in jupiter europa; do
  for v in create update patch delete deletecollection; do
    cannot "$v" pods -n "$ns" --as "$AS" || ok=1
    cannot "$v" deployments.apps -n "$ns" --as "$AS" || ok=1
  done
  cannot get secrets -n "$ns" --as "$AS"   || ok=1
  cannot create pods/exec -n "$ns" --as "$AS" || ok=1
done
check "$SA cannot modify anything, read secrets or exec" $ok

ok=0
for ns in jupiter europa; do
  cannot list pods -n "$ns" --as "system:serviceaccount:$NS:default" || ok=1
done
check "ServiceAccount $NS:default gained no permissions" $ok

# ---------- the Deployment ----------
dep=$(kubectl -n "$NS" get deploy pod-auditor -o json 2>/dev/null); dep=${dep:-'{}'}
jq -e --arg sa "$SA" '.spec.template.spec.serviceAccountName==$sa' <<<"$dep" >/dev/null
check "Deployment pod-auditor uses serviceAccountName: $SA" $?
jq -e '.spec.template.spec.containers[] | select(.name=="auditor")
       | .command==["sh","-c"] and (.args[0]|contains("for ns in jupiter europa"))' <<<"$dep" >/dev/null
check "command/args unchanged" $?

# Real behaviour: a Running Pod of the current template, running as auditor, logging 200s
echo "  ... waiting up to 90s for the auditor to log successful requests"
ok=1
for _ in $(seq 1 30); do
  for p in $(kubectl -n "$NS" get pods -l app=pod-auditor -o json | jq -r --arg sa "$SA" '
        .items[] | select(.metadata.deletionTimestamp==null and .status.phase=="Running"
                          and .spec.serviceAccountName==$sa) | .metadata.name'); do
    last=$(kubectl -n "$NS" logs "$p" -c auditor --tail=1 2>/dev/null)
    if grep -q 'pods/jupiter=200 deployments/jupiter=200 pods/europa=200 deployments/europa=200' <<<"$last"; then ok=0; break 2; fi
  done
  sleep 3
done
check "auditor container logs HTTP 200 for every request" $ok
[ "$ok" -ne 0 ] && echo "        last log line: ${last:-<none>}"

echo; echo "Score: $pass/$((pass+fail))"
[ "$fail" -eq 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
