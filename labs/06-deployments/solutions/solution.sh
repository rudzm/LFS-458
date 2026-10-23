#!/usr/bin/env bash
# Rozwiązanie referencyjne laba 06 — dla trenera i dla CI.
set -euo pipefail

CTX="${KUBECONTEXT:-kind-lfs458}"
NS=lfs458-m06
k() { kubectl --context "$CTX" "$@"; }

echo "→ zadanie 1: Deployment sklep w trzech replikach"
k create namespace "$NS" --dry-run=client -o yaml | k apply -f -
k create deployment sklep --image=nginx:1.26-alpine --replicas=3 -n "$NS" \
  --dry-run=client -o yaml | k apply -f -
k rollout status deployment/sklep -n "$NS" --timeout=300s

echo "→ zadanie 2: nowa wersja z powodem zmiany"
k set image deployment/sklep nginx=nginx:1.27-alpine -n "$NS"
k annotate deployment/sklep -n "$NS" --overwrite \
  kubernetes.io/change-cause='podniesienie nginx do 1.27'
k rollout status deployment/sklep -n "$NS" --timeout=300s
k rollout history deployment/sklep -n "$NS"

echo "→ zadanie 3: wycofanie do poprzedniej rewizji"
k rollout undo deployment/sklep -n "$NS"
k rollout status deployment/sklep -n "$NS" --timeout=300s
echo "   obraz po undo: $(k get deploy sklep -n "$NS" -o jsonpath='{.spec.template.spec.containers[*].image}')"
# `rollout undo` przywraca szablon starej rewizji RAZEM z jej adnotacjami,
# wiec change-cause znika. Zapisujemy powod wycofania na nowo.
k annotate deployment/sklep -n "$NS" --overwrite \
  kubernetes.io/change-cause='wycofanie do 1.26 - regresja w 1.27'

echo "→ zadanie 4: strategia bez przestoju + readinessProbe"
k patch deployment sklep -n "$NS" --type=strategic -p '{
  "spec": {
    "strategy": {
      "type": "RollingUpdate",
      "rollingUpdate": {"maxUnavailable": 0, "maxSurge": 1}
    },
    "template": {
      "spec": {
        "containers": [{
          "name": "nginx",
          "readinessProbe": {
            "httpGet": {"path": "/", "port": 80},
            "initialDelaySeconds": 2,
            "periodSeconds": 5
          }
        }]
      }
    }
  }
}'
k rollout status deployment/sklep -n "$NS" --timeout=300s

echo "→ zadanie 5: DaemonSet na wszystkich node'ach"
cat <<'YAML' | k apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: agent
  namespace: lfs458-m06
spec:
  selector:
    matchLabels:
      app: agent
  template:
    metadata:
      labels:
        app: agent
    spec:
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      containers:
        - name: agent
          image: busybox:1.36
          command: ["sleep", "3600"]
YAML
k rollout status ds/agent -n "$NS" --timeout=300s

echo "→ zadanie 6 (dodatkowe): odcięcie Poda od kontrolera"
if [ "$(k get pods -n "$NS" -l app=sklep-debug --no-headers 2>/dev/null | wc -l | tr -d ' ')" = "0" ]; then
  # Po rolloucie część Podów bywa jeszcze w Terminating — etykietujemy tylko
  # taki, który naprawdę działa, inaczej trafimy w znikający obiekt.
  # Czekamy na Deployment, a nie na Pody po selektorze: `kubectl wait` obejmuje
  # tez Pody w stanie Terminating i wtedy nigdy sie nie doczeka.
  k wait --for=condition=Available deployment/sklep -n "$NS" --timeout=300s
  POD=$(k get pods -n "$NS" -l app=sklep \
    -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' \
    | head -1)
  : "${POD:?nie znalazłem działającego Poda Deploymentu sklep}"
  k label pod "$POD" -n "$NS" app=sklep-debug --overwrite
  k rollout status deployment/sklep -n "$NS" --timeout=300s
else
  echo "   odcięty Pod już istnieje"
fi
k wait --for=condition=Available deployment/sklep -n "$NS" --timeout=300s

echo
echo "Gotowe. Weryfikacja: labctl check 06"
