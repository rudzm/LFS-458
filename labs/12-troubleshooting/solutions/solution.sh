#!/usr/bin/env bash
# Rozwiązanie referencyjne laba 12 — dla trenera i dla CI.
# Wymaga wcześniejszego `labctl setup 12`, które celowo psuje cztery rzeczy.
#
# Zadania 7-9 (apiserver, scheduler, kubelet) psują się dopiero w sesji
# `labctl lab 12`, więc tutaj naprawiamy je bezwarunkowo: gdy nic nie było
# zepsute, kroki po prostu nic nie zmieniają.
set -euo pipefail

CTX="${KUBECONTEXT:-kind-lfs458}"
NS=lfs458-m12
k() { kubectl --context "$CTX" "$@"; }

echo "→ zadania 7-9: control plane i kubelet (najpierw — bez API nic innego nie zadziała)"
CRI="${CONTAINER_CLI:-docker}"
W=lfs458-control-plane
for para in "apiserver.oryginal:kube-apiserver.yaml" "scheduler.oryginal:kube-scheduler.yaml"; do
  KOPIA="/etc/kubernetes/${para%%:*}"
  MANIFEST="/etc/kubernetes/manifests/${para##*:}"
  if "$CRI" exec "$W" test -f "$KOPIA" 2>/dev/null; then
    echo "   przywracam ${para##*:}"
    "$CRI" exec "$W" cp "$KOPIA" "$MANIFEST"
    "$CRI" exec "$W" rm -f "$KOPIA"
  fi
done
"$CRI" exec lfs458-worker2 systemctl start kubelet 2>/dev/null || true

echo "   czekam na powrót API i node'ów"
for _ in $(seq 1 60); do k get --raw /healthz >/dev/null 2>&1 && break; sleep 2; done
k wait --for=condition=Ready node --all --timeout=180s >/dev/null

# Pod z zadania 8 — po naprawie schedulera ma dostać node
k run osierocony --image=nginx:1.27-alpine -n "$NS" \
  --dry-run=client -o yaml | k apply -f -
k wait --for=condition=Ready pod/osierocony -n "$NS" --timeout=180s

echo "→ zadanie 1: nieistniejący obraz"
k describe pod -n "$NS" -l app=obrazek 2>/dev/null | sed -n '/Events/,$p' | tail -3 || true
k set image deployment/obrazek web=nginx:1.27-alpine -n "$NS"
k rollout status deployment/obrazek -n "$NS" --timeout=300s

echo "→ zadanie 2: aplikacja padająca w pętli"
POD=$(k get pods -n "$NS" -l app=padajacy -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$POD" ]; then
  echo "   logi poprzedniej instancji:"
  k logs "$POD" -n "$NS" --previous 2>/dev/null || k logs "$POD" -n "$NS" 2>/dev/null || true
fi
ARKUSZ="${ODPOWIEDZI:-$HOME/odpowiedzi}/lab-12.txt"
mkdir -p "$(dirname "$ARKUSZ")"
cat >> "$ARKUSZ" <<EOF
blad=brak zmiennej TRYB, koncze prace
EOF
k patch deployment padajacy -n "$NS" --type=strategic -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"app","command":["sleep","3600"]}]}}}}'
k rollout status deployment/padajacy -n "$NS" --timeout=300s

echo "→ zadanie 3: Service bez backendów"
echo "   selektor przed naprawą: $(k get svc sklep -n "$NS" -o jsonpath='{.spec.selector}')"
k patch svc sklep -n "$NS" -p '{"spec":{"selector":{"app":"sklep"}}}'
k rollout status deployment/sklep -n "$NS" --timeout=300s
for _ in $(seq 1 30); do
  n=$(k get endpointslices -n "$NS" -l kubernetes.io/service-name=sklep \
        -o jsonpath='{.items[*].endpoints[*].addresses[*]}' | wc -w | tr -d ' ')
  [ "$n" -ge 2 ] && break
  sleep 2
done
echo "   backendów po naprawie: $n"

echo "→ zadanie 4: Pod nie do zaplanowania"
k delete pod czekajacy -n "$NS" --ignore-not-found --wait=true
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: czekajacy
  namespace: lfs458-m12
spec:
  containers:
    - name: web
      image: nginx:1.27-alpine
YAML
k wait --for=condition=Ready pod/czekajacy -n "$NS" --timeout=300s

echo "→ zadanie 5 (dodatkowe): metryki"
k top nodes || true
echo "   odpowiedzi do pytań w labctl lab:"
echo "     zrodlo: metrics-server"
echo "     api-grupa: metrics.k8s.io"
echo "     nodow: 3"

echo
echo "Gotowe. Weryfikacja: labctl check 12"
