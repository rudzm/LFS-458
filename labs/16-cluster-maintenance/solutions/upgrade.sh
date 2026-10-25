#!/usr/bin/env bash
# Rozwiązanie referencyjne laba 16 — pełny upgrade 1.36 → 1.37.
#
# Uruchamiane z katalogu projektu:
#   bash labs/16-cluster-maintenance/solutions/upgrade.sh
#
# Skrypt istnieje po to, żeby prowadzący mógł w kilka minut doprowadzić
# stanowisko do stanu „po labie" — kursant przechodzi te kroki ręcznie.
set -euo pipefail

CEL="${CEL:-1.37.0-1.1}"          # pełna wersja pakietu
CEL_K8S="${CEL_K8S:-v1.37.0}"     # wersja dla `kubeadm upgrade`
MINOR="${MINOR:-v1.37}"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# kubeconfig jest na maszynie cp — kubectl wykonujemy tam, przez SSH
K()  { "$ROOT/scripts/vm-bin/kubectl" "$@"; }
na() { "$ROOT/scripts/vm-bin/na-maszynie" "$1" "$2"; }

# Po restarcie kubeleta na control plane static Pody wstają od nowa i API
# na chwilę znika. Bez tej pętli kolejny krok trafia w „connection refused" —
# a `drain` przerwany w połowie zostawia node zablokowany.
czekaj_na_api() {
  local pod_rzad=0
  for _ in $(seq 1 120); do
    if K get --raw /healthz >/dev/null 2>&1; then
      pod_rzad=$((pod_rzad + 1))
      [ "$pod_rzad" -ge 5 ] && return 0     # pięć odpowiedzi z rzędu = stabilne
    else
      pod_rzad=0
    fi
    sleep 2
  done
  echo "API nie wróciło w 4 minuty" >&2
  return 1
}

wersja_kubeleta() { K get node "$1" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null; }

echo "=== punkt wyjścia ==="
K get nodes -o wide

echo "=== [1/4] kubeadm 1.37 na control plane ==="
if na cp "kubeadm version -o short" | grep -q "${CEL_K8S%.*}"; then
  echo "   kubeadm jest już w docelowej wersji — pomijam"
else
na cp "sudo sed -i -E 's|/v1[.][0-9]+/|/$MINOR/|' /etc/apt/sources.list.d/kubernetes.list \
       && sudo apt-get update -qq \
       && sudo apt-mark unhold kubeadm \
       && sudo apt-get install -y -qq kubeadm=$CEL \
       && sudo apt-mark hold kubeadm \
       && kubeadm version -o short"
fi

echo "=== [2/4] upgrade control plane ==="
if K version -o json 2>/dev/null | grep -q "\"gitVersion\": \"$CEL_K8S"; then
  echo "   serwer API jest już w docelowej wersji — pomijam"
else
  na cp "sudo kubeadm upgrade apply $CEL_K8S -y"
  czekaj_na_api
fi

echo "=== [3/4] kubelet na control plane ==="
if [ "$(wersja_kubeleta k8s-cp)" = "$CEL_K8S" ]; then
  echo "   kubelet na k8s-cp jest już w docelowej wersji — pomijam"
else
K drain k8s-cp --ignore-daemonsets --timeout=5m
na cp "sudo apt-mark unhold kubelet kubectl \
       && sudo apt-get install -y -qq kubelet=$CEL kubectl=$CEL \
       && sudo apt-mark hold kubelet kubectl \
       && sudo systemctl daemon-reload && sudo systemctl restart kubelet"
czekaj_na_api
K uncordon k8s-cp
fi

echo "=== [4/4] worker node ==="
if [ "$(wersja_kubeleta k8s-worker)" = "$CEL_K8S" ]; then
  echo "   kubelet na k8s-worker jest już w docelowej wersji — pomijam"
else
czekaj_na_api
K drain k8s-worker --ignore-daemonsets --timeout=5m
na worker "sudo sed -i -E 's|/v1[.][0-9]+/|/$MINOR/|' /etc/apt/sources.list.d/kubernetes.list \
       && sudo apt-get update -qq \
       && sudo apt-mark unhold kubeadm \
       && sudo apt-get install -y -qq kubeadm=$CEL \
       && sudo apt-mark hold kubeadm \
       && sudo kubeadm upgrade node \
       && sudo apt-mark unhold kubelet kubectl \
       && sudo apt-get install -y -qq kubelet=$CEL kubectl=$CEL \
       && sudo apt-mark hold kubelet kubectl \
       && sudo systemctl daemon-reload && sudo systemctl restart kubelet"
K uncordon k8s-worker
fi

# Node zgłasza nową wersję dopiero, gdy kubelet przerejestruje się po
# restarcie — bez tej pętli stan końcowy pokazuje jeszcze starą.
echo "=== czekam, aż node'y zgłoszą nową wersję ==="
for _ in $(seq 1 60); do
  [ "$(wersja_kubeleta k8s-cp)" = "$CEL_K8S" ] && \
  [ "$(wersja_kubeleta k8s-worker)" = "$CEL_K8S" ] && break
  sleep 3
done

echo "=== stan końcowy ==="
K get nodes -o wide
K version -o json | python3 -c "import json,sys; print('apiserver:', json.load(sys.stdin)['serverVersion']['gitVersion'])"
