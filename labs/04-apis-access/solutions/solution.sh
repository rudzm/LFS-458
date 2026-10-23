#!/usr/bin/env bash
# Rozwiązanie referencyjne laba 04 — dla trenera i dla CI.
set -euo pipefail

CTX="${KUBECONTEXT:-kind-lfs458}"
NS=lfs458-m04
k() { kubectl --context "$CTX" "$@"; }

echo "→ zadanie 1: namespace i Pod z manifestu"
k create namespace "$NS" --dry-run=client -o yaml | k apply -f -
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: prosty
  namespace: lfs458-m04
  labels:
    app: lab04
    warstwa: web
spec:
  containers:
    - name: nginx
      image: nginx:1.27-alpine
      ports:
        - name: http
          containerPort: 80
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          memory: 128Mi
YAML
k wait --for=condition=Ready pod/prosty -n "$NS" --timeout=180s

echo "→ zadanie 2: adnotacje i etykieta"
k annotate pod prosty -n "$NS" --overwrite \
  lfs458.io/wlasciciel='zespol-platformy@example.com'
k annotate pod prosty -n "$NS" --overwrite \
  lfs458.io/opis='Pod demonstracyjny modulu 04 — sluzy do cwiczen z API, etykiet i adnotacji'
k label pod prosty -n "$NS" --overwrite wersja=v1

echo "   dowód: selektor po adnotacji nic nie zwraca"
k get pods -n "$NS" -l lfs458.io/wlasciciel --no-headers 2>/dev/null | wc -l

echo "→ zadanie 3: odpytanie API"
k get --raw "/api/v1/namespaces/${NS}/pods" | head -c 120; echo
KIND=$(k get --raw "/api/v1/namespaces/${NS}/pods" | sed -n 's/.*"kind":"\([A-Za-z]*\)".*/\1/p' | head -1)
ARKUSZ="${ODPOWIEDZI:-$HOME/odpowiedzi}/lab-04.txt"
mkdir -p "$(dirname "$ARKUSZ")"
cat >> "$ARKUSZ" <<EOF
sciezka-podow=/api/v1/namespaces/${NS}/pods
kind-odpowiedzi=${KIND:-PodList}
grupa-deploymentow=apps/v1
EOF

echo "→ zadanie 4: metadane zasobów"
ARKUSZ="${ODPOWIEDZI:-$HOME/odpowiedzi}/lab-04.txt"
mkdir -p "$(dirname "$ARKUSZ")"
cat >> "$ARKUSZ" <<EOF
pod-skrot=po
node-namespaced=false
restartpolicy-domyslna=Always
ingress-apiversion=networking.k8s.io/v1
EOF

echo "→ zadanie 5 (dodatkowe): Pod utworzony przez surowe API"
if k get pod przez-api -n "$NS" >/dev/null 2>&1; then
  echo "   przez-api już istnieje"
else
  tmp=$(mktemp -t przezapi.XXXXXX.json)
  cat > "$tmp" <<'JSON'
{
  "apiVersion": "v1",
  "kind": "Pod",
  "metadata": {
    "name": "przez-api",
    "namespace": "lfs458-m04",
    "annotations": {"lfs458.io/utworzony": "raw-api"}
  },
  "spec": {
    "containers": [{"name": "nginx", "image": "nginx:1.27-alpine"}]
  }
}
JSON
  k create --raw "/api/v1/namespaces/${NS}/pods" -f "$tmp" >/dev/null
  rm -f "$tmp"
fi
k wait --for=condition=Ready pod/przez-api -n "$NS" --timeout=180s

echo
echo "Gotowe. Weryfikacja: labctl check 04"
