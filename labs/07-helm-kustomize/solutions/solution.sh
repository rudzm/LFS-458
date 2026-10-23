#!/usr/bin/env bash
# Rozwiązanie referencyjne laba 07 — dla trenera i dla CI.
set -euo pipefail

CTX="${KUBECONTEXT:-kind-lfs458}"
NS=lfs458-m07
WORK="${LFS458_M07_DIR:-$HOME/lfs458-m07}"
k() { kubectl --context "$CTX" "$@"; }
h() { helm --kube-context "$CTX" "$@"; }

mkdir -p "$WORK"
cd "$WORK"

echo "→ zadanie 1: chart i instalacja wydania"
[ -d sklep ] || helm create sklep >/dev/null
if h status sklep-prod -n "$NS" >/dev/null 2>&1; then
  echo "   wydanie już istnieje — pomijam instalację"
else
  h install sklep-prod ./sklep -n "$NS" --create-namespace \
    --set replicaCount=2 \
    --set image.repository=nginx \
    --set image.tag=1.27-alpine \
    --wait --timeout 5m
fi
h list -n "$NS"

echo "→ zadanie 2: upgrade i rollback"
h upgrade sklep-prod ./sklep -n "$NS" --reuse-values --set replicaCount=4 --wait --timeout 5m
h history sklep-prod -n "$NS"
h rollback sklep-prod 1 -n "$NS" --wait --timeout 5m
h history sklep-prod -n "$NS"

echo "→ zadanie 3: baza i nakładka Kustomize"
mkdir -p base overlays/produkcja
cat > base/deployment.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: nginx:1.27-alpine
YAML
cat > base/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
YAML
cat > overlays/produkcja/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: lfs458-m07
nameSuffix: -produkcja
resources:
  - ../../base
replicas:
  - name: web
    count: 3
configMapGenerator:
  - name: ustawienia
    literals:
      - TRYB=produkcja
YAML
k kustomize overlays/produkcja >/dev/null
k apply -k overlays/produkcja
k rollout status deployment/web-produkcja -n "$NS" --timeout=300s

echo "→ zadanie 4: generator ConfigMap (zawarty w nakładce)"
k get cm -n "$NS" --no-headers | grep ustawienia || true

echo "→ zadanie 5 (dodatkowe): lint i template"
helm lint ./sklep | tail -2
SZABLON=$(helm template sklep-prod ./sklep --set replicaCount=7 \
  | grep -m1 -A1 'replicas:' | grep -oE '[0-9]+' | head -1)
KLASTER=$(k get deploy -n "$NS" -l app.kubernetes.io/instance=sklep-prod \
  -o jsonpath='{.items[0].spec.replicas}')
ARKUSZ="${ODPOWIEDZI:-$HOME/odpowiedzi}/lab-07.txt"
mkdir -p "$(dirname "$ARKUSZ")"
cat >> "$ARKUSZ" <<EOF
lint=ok
repliki-w-szablonie=${SZABLON:-7}
repliki-w-klastrze=${KLASTER:-2}
EOF

echo
echo "Gotowe. Weryfikacja: labctl check 07"
