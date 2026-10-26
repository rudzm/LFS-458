#!/usr/bin/env bash
# Rozwiązanie referencyjne laba 11 — dla trenera i dla CI.
set -euo pipefail

CTX="${KUBECONTEXT:-kind-lfs458}"
NS=lfs458-m11
k() { kubectl --context "$CTX" "$@"; }

echo "→ zadanie 1: etykieta node'a i nodeSelector"
k create namespace "$NS" --dry-run=client -o yaml | k apply -f -
k label node lfs458-worker2 dysk=ssd --overwrite
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: na-ssd
  namespace: lfs458-m11
spec:
  nodeSelector:
    dysk: ssd
  containers:
    - name: web
      image: nginx:1.27-alpine
YAML
k wait --for=condition=Ready pod/na-ssd -n "$NS" --timeout=180s

echo "→ zadanie 2: Pod nie do zaplanowania"
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: za-duzy
  namespace: lfs458-m11
spec:
  containers:
    - name: web
      image: nginx:1.27-alpine
      resources:
        requests:
          memory: 200Gi
YAML
echo "   czekam, aż scheduler odmówi"
for _ in $(seq 1 30); do
  reason=$(k get pod za-duzy -n "$NS" -o jsonpath='{.status.conditions[?(@.type=="PodScheduled")].reason}' 2>/dev/null)
  [ "$reason" = "Unschedulable" ] && break
  sleep 2
done
k describe pod za-duzy -n "$NS" | sed -n '/Events/,$p' | tail -5
ARKUSZ="${ODPOWIEDZI:-$HOME/odpowiedzi}/lab-11.txt"
mkdir -p "$(dirname "$ARKUSZ")"
cat >> "$ARKUSZ" <<EOF
powod=Insufficient memory
EOF

echo "→ zadanie 3: rozproszenie replik"
cat <<'YAML' | k apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rozproszony
  namespace: lfs458-m11
spec:
  replicas: 2
  selector:
    matchLabels:
      app: rozproszony
  template:
    metadata:
      labels:
        app: rozproszony
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector:
                matchLabels:
                  app: rozproszony
              topologyKey: kubernetes.io/hostname
      containers:
        - name: web
          image: nginx:1.27-alpine
YAML
k rollout status deployment/rozproszony -n "$NS" --timeout=300s
k get pods -n "$NS" -l app=rozproszony -o wide --no-headers

echo "→ zadanie 4: taint i toleration"
k taint node lfs458-worker2 gpu=true:NoSchedule --overwrite
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: z-gpu
  namespace: lfs458-m11
spec:
  nodeSelector:
    dysk: ssd
  tolerations:
    - key: gpu
      operator: Equal
      value: "true"
      effect: NoSchedule
  containers:
    - name: web
      image: nginx:1.27-alpine
YAML
k wait --for=condition=Ready pod/z-gpu -n "$NS" --timeout=180s

echo "→ zadanie 5 (dodatkowe): preferencja preferred"
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: preferowany
  namespace: lfs458-m11
spec:
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 50
          preference:
            matchExpressions:
              - key: dysk
                operator: In
                values: [nvme]
  containers:
    - name: web
      image: nginx:1.27-alpine
YAML
k wait --for=condition=Ready pod/preferowany -n "$NS" --timeout=180s

echo "→ zadanie 7: HPA (Deployment skalowany przygotowuje labctl przed zadaniem)"
cat <<'YAML' | k apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: {name: skalowany, namespace: lfs458-m11}
spec:
  replicas: 1
  selector: {matchLabels: {app: skalowany}}
  template:
    metadata: {labels: {app: skalowany}}
    spec:
      containers:
        - name: web
          image: nginx:1.27-alpine
          resources: {requests: {cpu: 20m}}
---
apiVersion: v1
kind: Service
metadata: {name: skalowany, namespace: lfs458-m11}
spec:
  selector: {app: skalowany}
  ports: [{port: 80}]
YAML
k rollout status deployment/skalowany -n "$NS" --timeout=180s
k autoscale deployment skalowany -n "$NS" --cpu=50% --min=1 --max=5 2>/dev/null || true
k run obciazenie -n "$NS" --image=busybox:1.36 --restart=Never -- \
  /bin/sh -c "while true; do wget -q -O- http://skalowany >/dev/null; done" 2>/dev/null || true
echo "   czekam, aż HPA dołoży repliki"
until [ "$(k get hpa skalowany -n "$NS" -o jsonpath='{.status.desiredReplicas}' 2>/dev/null)" -gt 1 ] 2>/dev/null; do sleep 10; done
k get hpa skalowany -n "$NS"
k delete pod obciazenie -n "$NS" --wait=false

echo
echo "Gotowe. Weryfikacja: labctl check 11"
