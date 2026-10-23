#!/usr/bin/env bash
# Rozwiązanie referencyjne laba 15 — dla trenera i dla CI.
# Wymaga klastra kind-ha (`labctl env up kind-ha`).
set -euo pipefail

CTX="${KUBECONTEXT:-kind-lfs458-ha}"
NS=lfs458-m15
k() { kubectl --context "$CTX" "$@"; }

ETCD_FLAGS=(
  --endpoints=https://127.0.0.1:2379
  --cacert=/etc/kubernetes/pki/etcd/ca.crt
  --cert=/etc/kubernetes/pki/etcd/server.crt
  --key=/etc/kubernetes/pki/etcd/server.key
)

echo "→ zadanie 1: topologia i kworum"
k create namespace "$NS" --dry-run=client -o yaml | k apply -f -
CP=$(k get nodes -l node-role.kubernetes.io/control-plane --no-headers | wc -l | tr -d ' ')
ALL=$(k get nodes --no-headers | wc -l | tr -d ' ')
KWORUM=$(( CP / 2 + 1 ))
PRZEZYJE=$(( CP - KWORUM ))
echo "   control plane: $CP, razem: $ALL, kworum: $KWORUM, przeżyje awarii: $PRZEZYJE"
echo "   odpowiedzi do pytań w labctl lab:"
echo "     nodow-cp: $CP"
echo "     nodow-razem: $ALL"
echo "     instancji etcd: $(k get pods -n kube-system -l component=etcd --no-headers | wc -l | tr -d ' ')"
echo "     kworum: $KWORUM"
echo "     przezyje-awarii: $PRZEZYJE"

echo "→ zadanie 2: członkowie etcd"
POD=$(k -n kube-system get pod -l component=etcd -o jsonpath='{.items[0].metadata.name}')
echo "   Pod etcd: $POD"
k -n kube-system exec "$POD" -- etcdctl "${ETCD_FLAGS[@]}" member list -w table
CZLONKOW=$(k -n kube-system exec "$POD" -- etcdctl "${ETCD_FLAGS[@]}" member list 2>/dev/null | grep -c started)
ARKUSZ="${ODPOWIEDZI:-$HOME/odpowiedzi}/lab-15.txt"
mkdir -p "$(dirname "$ARKUSZ")"
cat >> "$ARKUSZ" <<EOF
czlonkow=$CZLONKOW
port-klientow=2379
EOF

echo "→ zadanie 3: kopia zapasowa etcd"
k -n kube-system exec "$POD" -- etcdctl "${ETCD_FLAGS[@]}" snapshot save /tmp/etcd-backup.db
k -n kube-system exec "$POD" -- etcdutl snapshot status /tmp/etcd-backup.db -w table || \
  k -n kube-system exec "$POD" -- etcdutl snapshot status /tmp/etcd-backup.db
ARKUSZ="${ODPOWIEDZI:-$HOME/odpowiedzi}/lab-15.txt"
mkdir -p "$(dirname "$ARKUSZ")"
cat >> "$ARKUSZ" <<EOF
sciezka=/tmp/etcd-backup.db
czego-nie-obejmuje=PersistentVolume
EOF

echo "→ zadanie 4 (dodatkowe): PodDisruptionBudget"
# Klaster HA nie ma worker node'ow — zdejmujemy taint, zeby workloady mialy gdzie stanac.
k taint node lfs458-ha-control-plane node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null || true
k create deployment wazna-usluga --image=nginx:1.27-alpine --replicas=3 -n "$NS" \
  --dry-run=client -o yaml | k apply -f -
k rollout status deployment/wazna-usluga -n "$NS" --timeout=300s
cat <<'YAML' | k apply -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: wazna-pdb
  namespace: lfs458-m15
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: wazna-usluga
YAML
sleep 5
k get pdb -n "$NS"

echo
echo "Gotowe. Weryfikacja: labctl check 15"
