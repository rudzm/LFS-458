#!/usr/bin/env bash
# Rozwiązanie referencyjne laba 09 — dla trenera i dla CI.
set -euo pipefail

CTX="${KUBECONTEXT:-kind-lfs458}"
NS=lfs458-m09
k() { kubectl --context "$CTX" "$@"; }

echo "→ zadanie 1: Deployment i Service ClusterIP"
k create namespace "$NS" --dry-run=client -o yaml | k apply -f -
k create deployment web --image=nginx:1.27-alpine --replicas=3 -n "$NS" \
  --dry-run=client -o yaml | k apply -f -
k rollout status deployment/web -n "$NS" --timeout=300s
k expose deployment web --port=80 --target-port=80 -n "$NS" \
  --dry-run=client -o yaml | k apply -f -

echo "→ zadanie 2: NodePort na 30080"
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Service
metadata:
  name: web-nodeport
  namespace: lfs458-m09
spec:
  type: NodePort
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
YAML

echo "   czekam, aż usługa odpowie z hosta"
for _ in $(seq 1 30); do
  IP1=$(k get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
  curl -fsS --max-time 3 "http://$IP1:30080/" >/dev/null 2>&1 && break
  sleep 2
done
for IP in $(k get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}'); do
  printf '   %s -> %s\n' "$IP" "$(curl -s --max-time 5 "http://$IP:30080/" | grep -o '<title>.*</title>')"
done

echo "→ zadanie 3: Pod klient i rozwiązywanie nazw"
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: klient
  namespace: lfs458-m09
spec:
  containers:
    - name: klient
      image: busybox:1.36
      command: ["sleep", "3600"]
YAML
k wait --for=condition=Ready pod/klient -n "$NS" --timeout=180s
k exec -n "$NS" klient -- wget -qO- --timeout=5 http://web | head -2
k exec -n "$NS" klient -- wget -qO- --timeout=5 http://web.lfs458-m09.svc.cluster.local | head -2

echo "→ zadanie 4: Service headless"
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Service
metadata:
  name: web-headless
  namespace: lfs458-m09
spec:
  clusterIP: None
  selector:
    app: web
  ports:
    - port: 80
      targetPort: 80
YAML
k exec -n "$NS" klient -- nslookup web-headless || true

echo "→ zadanie 5 (dodatkowe): alias ExternalName"
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Service
metadata:
  name: zewnetrzna-baza
  namespace: lfs458-m09
spec:
  type: ExternalName
  externalName: db.example.com
YAML

echo
echo "Gotowe. Weryfikacja: labctl check 09"
