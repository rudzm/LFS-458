#!/usr/bin/env bash
# Rozwiązanie referencyjne laba 02 — dla trenera i dla CI.
# Wymaga postawionego środowiska vagrant-kubeadm (`labctl env up vagrant-kubeadm`).
set -euo pipefail

VMDIR="${VMDIR:-env/vm/kubeadm}"
CTX="${CTX:-kubeadm-lfs458}"
POD_CIDR=10.244.0.0/16
CP_IP=192.168.56.10
CILIUM_VER="${CILIUM_VER:-1.20.3}"

vm() { (cd "$VMDIR" && vagrant ssh "$1" -c "$2" 2>/dev/null | tr -d '\r'); }
k()  { kubectl --context "$CTX" "$@"; }

echo "→ zadanie 1: kubeadm init na node'ie control plane"
if vm cp "test -f /etc/kubernetes/admin.conf"; then
  echo "   control plane już istnieje — pomijam init"
else
  vm cp "sudo kubeadm init --pod-network-cidr=${POD_CIDR} --apiserver-advertise-address=${CP_IP}"
  vm cp "mkdir -p \$HOME/.kube && sudo cp -f /etc/kubernetes/admin.conf \$HOME/.kube/config && sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"
fi

echo "→ zadanie 1: eksport kubeconfiga na hosta jako kontekst ${CTX}"
bash labs/02-installation/solutions/export-kubeconfig.sh

echo "→ zadanie 2: sieć Podów (Cilium)"
if k get daemonset -n kube-system cilium >/dev/null 2>&1; then
  echo "   cilium już zainstalowany"
else
  # ipam.mode=kubernetes: bierz wycinek z spec.podCIDR node'a, a nie własną pulę
  vm cp "cilium install --version ${CILIUM_VER} --set ipam.mode=kubernetes"
  vm cp "cilium status --wait"
fi
k wait --for=condition=Ready nodes --all --timeout=300s

echo "→ zadanie 3: dołączenie worker node'a"
if k get node k8s-worker >/dev/null 2>&1; then
  echo "   k8s-worker już w klastrze"
else
  JOIN=$(vm cp "sudo kubeadm token create --print-join-command")
  vm worker "sudo ${JOIN}"
  # Czekamy na konkretny node: tuż po `join` obiekt może jeszcze nie istnieć,
  # a `--all` obejmuje wtedy tylko control plane i wraca natychmiast.
  k wait --for=create node/k8s-worker --timeout=120s
  k wait --for=condition=Ready node/k8s-worker --timeout=300s
fi

echo "→ zadanie 4: inwentaryzacja artefaktów kubeadm"
CA_DATE=$(vm cp "sudo kubeadm certs check-expiration" \
  | awk '/^ca / {print $2, $3, $4}' \
  | sed 's/,//' )
CA_ISO=$(date -d "$CA_DATE" +%Y-%m-%d 2>/dev/null || date -j -f "%b %d %Y" "$CA_DATE" +%Y-%m-%d 2>/dev/null || echo "2036-01-01")

k create namespace lfs458-m02 --dry-run=client -o yaml | k apply -f -
echo "   odpowiedzi do pytań w labctl lab:"
echo "     podcidr: $POD_CIDR"
echo "     endpoint: ${CP_IP}:6443"
echo "     manifesty: /etc/kubernetes/manifests"
echo "     ca-wygasa: $CA_ISO"

echo "→ zadanie 5 (dodatkowe): zdejmuję taint z control plane node'a"
k taint nodes k8s-cp node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null || \
  echo "   taintu już nie było"

echo
echo "Gotowe. Weryfikacja: labctl check 02"
