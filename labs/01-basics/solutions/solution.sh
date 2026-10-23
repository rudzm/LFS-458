#!/usr/bin/env bash
# Rozwiązanie referencyjne laba 01 — dla trenera.
# Uruchamiane też w CI, żeby wyłapać rozjazd między treścią zadań a checkami:
#   ./labs/01-basics/solutions/solution.sh && labctl check 01
set -euo pipefail

CTX="${KUBECONTEXT:-kind-lfs458}"
NS=lfs458-m01
k() { kubectl --context "$CTX" "$@"; }

echo "→ zadanie 1: namespace i etykieta"
k create namespace "$NS" --dry-run=client -o yaml | k apply -f -
k label namespace "$NS" lfs458.io/modul=01 --overwrite

echo "→ zadanie 2: inwentaryzacja klastra"
NODES=$(k get nodes --no-headers | wc -l | tr -d ' ')
CP=$(k get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}')
VER=$(k get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}')
APISERVER=$(k get pods -n kube-system -l component=kube-apiserver -o jsonpath='{.items[0].metadata.name}')
ETCD=$(k get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')
SCHED=$(k get pods -n kube-system -l component=kube-scheduler -o jsonpath='{.items[0].metadata.name}')

ARKUSZ="${ODPOWIEDZI:-$HOME/odpowiedzi}/lab-01.txt"
mkdir -p "$(dirname "$ARKUSZ")"
cat > "$ARKUSZ" <<EOF
liczba-nodow=$NODES
control-plane=$CP
wersja=$VER
apiserver=$APISERVER
etcd=$ETCD
scheduler=$SCHED
EOF

echo "→ zadanie 3: aplikacja w namespace sklep-demo"
POD=$(k get pods -n sklep-demo -l app=kasa -o jsonpath='{.items[0].metadata.name}')
cat >> "$ARKUSZ" <<EOF
pod-nazwa=$POD
pod-node=$(k get pod "$POD" -n sklep-demo -o jsonpath='{.spec.nodeName}')
pod-obraz=$(k get pod "$POD" -n sklep-demo -o jsonpath='{.spec.containers[0].image}')
EOF

echo "→ zadanie 4: Deployment petla i samonaprawa"
k create deployment petla --image=nginx:1.27-alpine --replicas=2 -n "$NS" \
  --dry-run=client -o yaml | k apply -f -
k rollout status deployment/petla -n "$NS" --timeout=180s

POD=$(k get pods -n "$NS" -l app=petla -o jsonpath='{.items[0].metadata.name}')
echo "   usuwam $POD i czekam, aż kontroler go odtworzy"
k delete pod "$POD" -n "$NS"
k wait --for=condition=Available deployment/petla -n "$NS" --timeout=180s

echo "→ zadanie 5 (dodatkowe): skalowanie i adnotacja"
k scale deployment petla -n "$NS" --replicas=4
k rollout status deployment/petla -n "$NS" --timeout=180s
k annotate deployment petla -n "$NS" --overwrite \
  lfs458.io/obserwacja='node wybral kube-scheduler; kubelet tylko uruchomil kontener przez CRI'

echo
echo "Gotowe. Weryfikacja: labctl check 01"
