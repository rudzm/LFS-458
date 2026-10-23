#!/usr/bin/env bash
# Rozwiązanie referencyjne laba 01 — dla trenera.
# Zadania 1 i 2 to pytania ABCD, odpowiada się na nie w `labctl lab 01`;
# skrypt wypisuje tylko poprawne odpowiedzi do porównania.
# Zadania 3 i 4 wykonuje naprawdę. Obiekty stawia `labctl setup 01`, więc:
#   labctl setup 01 && ./labs/01-basics/solutions/solution.sh && labctl check 01
set -euo pipefail

CTX="${KUBECONTEXT:-kind-lfs458}"
NS=lfs458-m01
k() { kubectl --context "$CTX" "$@"; }

echo "→ zadanie 1: odpowiedzi o klastrze"
APISERVER=$(k get pods -n kube-system -l component=kube-apiserver -o jsonpath='{.items[0].metadata.name}')
echo "   node'ów:       $(k get nodes --no-headers | wc -l | tr -d ' ')"
echo "   control plane: $(k get nodes -l node-role.kubernetes.io/control-plane -o jsonpath='{.items[0].metadata.name}')"
echo "   wersja:        $(k get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}')"
echo "   Pod apiservera: $APISERVER"

echo "→ zadanie 2: aplikacja w namespace sklep-demo"
POD=$(k get pods -n sklep-demo -l app=kasa -o jsonpath='{.items[0].metadata.name}')
echo "   Pod:           $POD"
echo "   obraz:         $(k get pod "$POD" -n sklep-demo -o jsonpath='{.spec.containers[0].image}')"
echo "   node:          $(k get pod "$POD" -n sklep-demo -o jsonpath='{.spec.nodeName}')"
echo "   ReplicaSetów:  $(k get rs -n sklep-demo --no-headers | wc -l | tr -d ' ')"

echo "→ zadanie 3: usunięcie Poda i samonaprawa"
POD=$(k get pods -n "$NS" -l app=petla -o jsonpath='{.items[0].metadata.name}')
echo "   usuwam $POD i czekam, aż kontroler go odtworzy"
k delete pod "$POD" -n "$NS"
k rollout status deployment/petla -n "$NS" --timeout=180s

echo "→ zadanie 4 (dodatkowe): zmiana stanu docelowego"
k scale deployment petla -n "$NS" --replicas=4
k rollout status deployment/petla -n "$NS" --timeout=180s
k get pods -n "$NS" -o wide

echo
echo "Gotowe. Weryfikacja: labctl check 01"
