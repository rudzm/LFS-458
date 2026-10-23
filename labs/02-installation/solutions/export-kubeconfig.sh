#!/usr/bin/env bash
# Ściąga kubeconfig z maszyny control plane i scala go z kubeconfigiem hosta
# pod nazwą kontekstu `kubeadm-lfs458` — tego kontekstu używa weryfikator.
set -euo pipefail

VMDIR="${VMDIR:-env/vm/kubeadm}"
CTX="${CTX:-kubeadm-lfs458}"
KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"

if [[ ! -f "$VMDIR/Vagrantfile" ]]; then
  echo "nie widzę $VMDIR/Vagrantfile — uruchom skrypt z katalogu głównego repozytorium" >&2
  exit 1
fi

tmp=$(mktemp -t kubeadm-lfs458.XXXXXX)
trap 'rm -f "$tmp" "$tmp.merged"' EXIT

echo "→ pobieram /etc/kubernetes/admin.conf z maszyny cp"
(cd "$VMDIR" && vagrant ssh cp -c "sudo cat /etc/kubernetes/admin.conf" 2>/dev/null) \
  | tr -d '\r' > "$tmp"

if ! grep -q 'kind: Config' "$tmp"; then
  echo "pobrany plik nie wygląda na kubeconfig — czy `kubeadm init` się powiódł?" >&2
  exit 1
fi

echo "→ nazywam klaster, użytkownika i kontekst jako $CTX"
sed -i.bak \
  -e "s/^\( *cluster: \)kubernetes$/\1$CTX/" \
  -e "s/^\( *name: \)kubernetes$/\1$CTX/" \
  -e "s/kubernetes-admin@kubernetes/$CTX/" \
  -e "s/kubernetes-admin/$CTX-admin/" \
  -e "s/^\( *user: \)$CTX-admin$/\1$CTX-admin/" \
  "$tmp"
rm -f "$tmp.bak"

echo "→ usuwam poprzednie wpisy $CTX, jeśli zostały"
# `kubectl config view --flatten` daje pierwszeństwo PIERWSZEMU plikowi z listy
# KUBECONFIG. Gdyby został wpis z poprzedniej generacji maszyn, przeżyłby
# scalanie i przykrył świeży certyfikat — kubectl zgłaszałby wtedy
# „x509: certificate signed by unknown authority" przy sprawnym klastrze.
kubectl config delete-context "$CTX"       >/dev/null 2>&1 || true
kubectl config delete-cluster "$CTX"       >/dev/null 2>&1 || true
kubectl config delete-user    "$CTX-admin" >/dev/null 2>&1 || true

echo "→ scalam z $KUBECONFIG_PATH"
mkdir -p "$(dirname "$KUBECONFIG_PATH")"
touch "$KUBECONFIG_PATH"
KUBECONFIG="$KUBECONFIG_PATH:$tmp" kubectl config view --flatten > "$tmp.merged"
cp "$KUBECONFIG_PATH" "$KUBECONFIG_PATH.bak-$(date +%s)"
mv "$tmp.merged" "$KUBECONFIG_PATH"

echo "→ gotowe"
kubectl --context "$CTX" get nodes
