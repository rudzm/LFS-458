#!/usr/bin/env bash
# Rozwiązanie referencyjne laba 05 — dla trenera i dla CI.
set -euo pipefail

CTX="${KUBECONTEXT:-kind-lfs458}"
NS=lfs458-m05
k() { kubectl --context "$CTX" "$@"; }

echo "→ zadanie 1: katalog API"
k create namespace "$NS" --dry-run=client -o yaml | k apply -f -
echo "   odpowiedzi do pytań w labctl lab:"
echo "     Job: batch/v1, Role: rbac.authorization.k8s.io/v1, NetworkPolicy: networking.k8s.io/v1"
echo "     PersistentVolume namespaced: false, grupa rdzeniowa: pusta (apiVersion: v1)"

echo "→ zadanie 2: ServiceAccount, Role, RoleBinding"
k create serviceaccount czytelnik -n "$NS" --dry-run=client -o yaml | k apply -f -
k create role podglad-podow --verb=get,list,watch --resource=pods -n "$NS" \
  --dry-run=client -o yaml | k apply -f -
k create rolebinding czytelnik-podglad --role=podglad-podow \
  --serviceaccount="${NS}:czytelnik" -n "$NS" \
  --dry-run=client -o yaml | k apply -f -

echo "→ zadanie 3: rozszerzenie o pods/log i sprawdzenie granic"
k create role podglad-podow --verb=get,list,watch --resource=pods,pods/log -n "$NS" \
  --dry-run=client -o yaml | k apply -f -

SA="system:serviceaccount:${NS}:czytelnik"
echo "   get pods      → $(k auth can-i get pods --as=$SA -n $NS)"
echo "   get pods/log  → $(k auth can-i get pods/log --as=$SA -n $NS)"
echo "   delete pods   → $(k auth can-i delete pods --as=$SA -n $NS)"
echo "   get secrets   → $(k auth can-i get secrets --as=$SA -n $NS)"

echo "→ zadanie 4: ClusterRole i ClusterRoleBinding"
k create clusterrole nody-podglad --verb=get,list --resource=nodes \
  --dry-run=client -o yaml | k apply -f -
k create clusterrolebinding czytelnik-nody --clusterrole=nody-podglad \
  --serviceaccount="${NS}:czytelnik" \
  --dry-run=client -o yaml | k apply -f -
echo "   list nodes    → $(k auth can-i list nodes --as=$SA)"

echo "→ zadanie 5 (dodatkowe): RoleBinding do wbudowanej ClusterRole view"
k create serviceaccount gosc -n "$NS" --dry-run=client -o yaml | k apply -f -
k create rolebinding gosc-view --clusterrole=view \
  --serviceaccount="${NS}:gosc" -n "$NS" \
  --dry-run=client -o yaml | k apply -f -

echo
echo "Gotowe. Weryfikacja: labctl check 05"
