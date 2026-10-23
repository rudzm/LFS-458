#!/usr/bin/env bash
# Rozwiązanie referencyjne laba 03 — dla trenera i dla CI.
set -euo pipefail

CTX="${KUBECONTEXT:-kind-lfs458}"
# Uruchamiane też poza labctl (brama jakości, CI) — wtedy CONTAINER_CLI nie jest ustawione.
CRI="${CONTAINER_CLI:-}"
if [[ -z "$CRI" ]]; then
  for candidate in docker nerdctl podman; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" info >/dev/null 2>&1; then
      CRI="$candidate"; break
    fi
  done
fi
: "${CRI:?nie znalazłem działającego silnika kontenerów (docker/nerdctl/podman)}"
NS=lfs458-m03
WORKER=lfs458-worker
k() { kubectl --context "$CTX" "$@"; }

echo "→ zadanie 1: inwentaryzacja sieci"
k create namespace "$NS" --dry-run=client -o yaml | k apply -f -
CNI=$(k get ds -n kube-system -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -v kube-proxy | head -1)
POD_CIDR_KLASTRA=$(k -n kube-system get cm kubeadm-config -o jsonpath='{.data.ClusterConfiguration}' | awk '/podSubnet/ {print $2}')
POD_CIDR_WORKER=$(k get node "$WORKER" -o jsonpath='{.spec.podCIDR}')
DNS_IP=$(k get svc -n kube-system kube-dns -o jsonpath='{.spec.clusterIP}')
PROXY_MODE=$(k -n kube-system get cm kube-proxy -o yaml | awk -F': *' '/^ *mode:/ {print $2; exit}' | tr -d '"')
[ -n "$PROXY_MODE" ] || PROXY_MODE=iptables

ARKUSZ="${ODPOWIEDZI:-$HOME/odpowiedzi}/lab-03.txt"
mkdir -p "$(dirname "$ARKUSZ")"
cat >> "$ARKUSZ" <<EOF
cni=$CNI
podcidr-klastra=$POD_CIDR_KLASTRA
podcidr-worker=$POD_CIDR_WORKER
dns-ip=$DNS_IP
kube-proxy-tryb=$PROXY_MODE
EOF

echo "→ zadanie 2: Pod z dwoma kontenerami we wspólnej sieci"
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: wspolna-siec
  namespace: lfs458-m03
spec:
  containers:
    - name: serwer
      image: hashicorp/http-echo:1.0
      args: ["-text=architektura", "-listen=:5678"]
    - name: klient
      image: busybox:1.36
      command: ["sleep", "3600"]
YAML
k wait --for=condition=Ready pod/wspolna-siec -n "$NS" --timeout=180s
k exec -n "$NS" wspolna-siec -c klient -- wget -qO- --timeout=5 http://localhost:5678

echo "→ zadanie 3: static Pod na node'ie $WORKER"
"$CRI" exec -i "$WORKER" sh -c 'cat > /etc/kubernetes/manifests/statyczny.yaml' <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: statyczny
spec:
  containers:
    - name: web
      image: nginx:1.27-alpine
YAML

echo "   czekam, aż kubelet podniesie static Poda"
for _ in $(seq 1 60); do
  if k get pod "statyczny-${WORKER}" >/dev/null 2>&1; then break; fi
  sleep 2
done
k wait --for=condition=Ready "pod/statyczny-${WORKER}" --timeout=180s

echo "→ zadanie 4: porty komponentów"
KUBELET_PORT=$(k get node "$WORKER" -o jsonpath='{.status.daemonEndpoints.kubeletEndpoint.Port}')
ARKUSZ="${ODPOWIEDZI:-$HOME/odpowiedzi}/lab-03.txt"
mkdir -p "$(dirname "$ARKUSZ")"
cat >> "$ARKUSZ" <<EOF
apiserver=6443
etcd-klienci=2379
kubelet=$KUBELET_PORT
EOF

echo "→ zadanie 5 (dodatkowe): obserwacja static Poda"
k delete pod "statyczny-${WORKER}" --wait=false >/dev/null 2>&1 || true
sleep 5
for _ in $(seq 1 60); do
  if k get pod "statyczny-${WORKER}" >/dev/null 2>&1; then break; fi
  sleep 2
done
k wait --for=condition=Ready "pod/statyczny-${WORKER}" --timeout=180s

OWNER_KIND=$(k get pod "statyczny-${WORKER}" -o jsonpath='{.metadata.ownerReferences[0].kind}')
OWNER_NAME=$(k get pod "statyczny-${WORKER}" -o jsonpath='{.metadata.ownerReferences[0].name}')
ARKUSZ="${ODPOWIEDZI:-$HOME/odpowiedzi}/lab-03.txt"
mkdir -p "$(dirname "$ARKUSZ")"
cat >> "$ARKUSZ" <<EOF
wlasciciel-kind=$OWNER_KIND
wlasciciel-nazwa=$OWNER_NAME
jak-usunac=/etc/kubernetes/manifests/statyczny.yaml
EOF

echo
echo "Gotowe. Weryfikacja: labctl check 03"
