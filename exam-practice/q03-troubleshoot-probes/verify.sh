#!/usr/bin/env bash
# Grades Question 3.
set -uo pipefail

NS=saturn
DEPLOY=random-api

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then echo "  [PASS] $1"; pass=$((pass+1)); else echo "  [FAIL] $1"; fail=$((fail+1)); fi; }
finish() { echo; echo "Score: $pass/$((pass+fail))"; [ "$fail" -eq 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"; exit 0; }

echo "Question 3 — probes troubleshooting"

dep=$(kubectl -n "$NS" get deploy "$DEPLOY" -o json 2>/dev/null)
if [ -z "$dep" ]; then check "Deployment $NS/$DEPLOY exists" 1; finish; fi
c=$(jq '.spec.template.spec.containers[] | select(.name=="api")' <<<"$dep")
if [ -z "$c" ]; then check "container 'api' exists" 1; finish; fi

# ---------- constraints: things that must NOT change ----------
[ "$(jq -r '.image' <<<"$c")" = "busybox:stable" ]; check "image unchanged (busybox:stable)" $?

jq -e '.command == ["sh","-c"]
       and (.args|length)==1
       and (.args[0]|contains("sleep 25"))
       and (.args[0]|contains("exec httpd -f -v -p 8080 -h /www"))' <<<"$c" >/dev/null
check "command/args unchanged" $?

jq -e '[.ports[] | {name, containerPort}] == [{"name":"web","containerPort":8080}]' <<<"$c" >/dev/null
check "ports unchanged (web -> 8080)" $?

jq -e '.livenessProbe as $l
       | $l.httpGet.path=="/healthz"
       and ($l.httpGet.port==8080 or $l.httpGet.port=="web")
       and ($l.periodSeconds // 10)==5
       and ($l.failureThreshold // 3)==3
       and ($l.initialDelaySeconds // 0)==0
       and ($l.timeoutSeconds // 1)==1' <<<"$c" >/dev/null
check "liveness probe unchanged (httpGet /healthz, period 5, threshold 3, no initial delay)" $?

# ---------- the fixes ----------
# Readiness must still exist and must point at a port that really exists (8080 / 'web')
jq -e '.readinessProbe != null
       and ( (.readinessProbe.exec != null)
             or ([.readinessProbe.httpGet.port, .readinessProbe.tcpSocket.port, .readinessProbe.grpc.port]
                 | map(select(. != null)) | .[0] | (. == 8080 or . == "web")) )' <<<"$c" >/dev/null
check "readiness probe present and targets a port the container really has" $?

# Startup budget: kubelet kills on the Nth consecutive failure, at initialDelay + period*(N-1)
jq -e '.startupProbe != null
       and ((.startupProbe.initialDelaySeconds // 0)
            + (.startupProbe.periodSeconds // 10) * ((.startupProbe.failureThreshold // 3) - 1)) >= 30' <<<"$c" >/dev/null
check "startupProbe protects the container for at least 30s of startup" $?

# ---------- objects that must stay untouched ----------
svc=$(kubectl -n "$NS" get svc random-api -o json 2>/dev/null); svc=${svc:-'{}'}
jq -e '.spec.selector == {"app":"random-api"}
       and (.spec.ports|length)==1
       and .spec.ports[0].port==80
       and .spec.ports[0].targetPort=="web"' <<<"$svc" >/dev/null
check "Service random-api unchanged" $?

jq -e '.metadata.generation==1' <<<"$(kubectl -n "$NS" get deploy random-cache -o json 2>/dev/null || echo '{}')" >/dev/null
check "Deployment random-cache untouched" $?

# ---------- real behaviour ----------
echo "  ... waiting up to 120s for the rollout to settle"
ok=1
for _ in $(seq 1 60); do
  st=$(kubectl -n "$NS" get deploy "$DEPLOY" -o json)
  if jq -e '.status.observedGeneration == .metadata.generation
            and (.status.updatedReplicas // 0)==2
            and (.status.readyReplicas // 0)==2
            and (.status.replicas // 0)==2' <<<"$st" >/dev/null; then ok=0; break; fi
  sleep 2
done
check "both replicas updated and Ready" $ok

# Let a few liveness periods pass, then make sure the live Pods never restarted
sleep 12
pods=$(kubectl -n "$NS" get pods -l app=random-api -o json)
jq -e '[.items[] | select(.metadata.deletionTimestamp == null)] as $p
       | ($p|length)==2
       and all($p[]; (.status.containerStatuses // [] | map(select(.name=="api")) | .[0]
                      | .ready==true and .restartCount==0))' <<<"$pods" >/dev/null
check "running Pods are Ready with 0 restarts" $?

jq -e '[.items[].endpoints[]? | select(.conditions.ready==true)] | length==2' \
  <<<"$(kubectl -n "$NS" get endpointslices -l kubernetes.io/service-name=random-api -o json)" >/dev/null
check "Service random-api has 2 ready endpoints" $?

out=$(kubectl -n "$NS" run "q03-client-$RANDOM" --image=busybox:stable --restart=Never --rm -i --quiet \
      --command -- wget -qO- -T 3 http://random-api.saturn/healthz 2>/dev/null)
[ "$(echo "$out" | tr -d '[:space:]')" = "ok" ]; check "http://random-api.saturn/healthz returns 'ok'" $?

finish
