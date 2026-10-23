#!/usr/bin/env bash
# Dodatki do klastra kind-basic. Wywoływane przy stawianiu środowiska.
# Idempotentne — można puścić ponownie na działającym klastrze.
#
# Co dokłada i dlaczego:
#   ingress-nginx   — moduły 09 i 99 wpuszczają ruch przez Ingress
#   metrics-server  — moduł 11 (`kubectl top`) i moduł 01 (szukanie dodatków)
set -euo pipefail

CTX="${KUBECONTEXT:-kind-lfs458}"
K="kubectl --context ${CTX}"

INGRESS_VER="${INGRESS_VER:-controller-v1.15.1}"
METRICS_VER="${METRICS_VER:-v0.9.0}"

echo "→ ingress-nginx (${INGRESS_VER})"
$K apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_VER}/deploy/static/provider/kind/deploy.yaml"

# Manifest kindowy ingress-nginx od wersji 1.1x NIE ma już nodeSelectora
# `ingress-ready`, tylko tolerancje taintu control plane. Bez przypięcia
# kontroler może wylądować na dowolnym węźle — a `hostPort: 80/443` jest
# zmapowany na hosta wyłącznie z węzła control plane (patrz lfs458.yaml).
# Wtedy curl na localhost:8080 nie trafia nigdzie i wszystkie checki
# Ingressa w modułach 09 i 99 są czerwone. Dlatego przypinamy jawnie.
echo "   przypinam kontroler do węzła z etykietą ingress-ready=true"
$K -n ingress-nginx patch deployment ingress-nginx-controller --type=strategic -p '{
  "spec": {"template": {"spec": {"nodeSelector": {
    "kubernetes.io/os": "linux",
    "ingress-ready": "true"
  }}}}
}'

echo "→ metrics-server (${METRICS_VER})"
$K apply -f "https://github.com/kubernetes-sigs/metrics-server/releases/download/${METRICS_VER}/components.yaml"

# Kubelety w kindzie mają certyfikaty serwerowe podpisane przez CA klastra,
# których metrics-server domyślnie nie akceptuje — bez tej flagi `kubectl top`
# zwraca „metrics not available" i moduł 11 nie da się zaliczyć.
echo "   dokładam --kubelet-insecure-tls"
$K -n kube-system patch deployment metrics-server --type=json -p '[
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-",
   "value": "--kubelet-insecure-tls"}
]' 2>/dev/null || echo "   (flaga już była)"

echo "→ czekam, aż dodatki wstaną"
$K -n ingress-nginx wait --for=condition=Available deployment/ingress-nginx-controller --timeout=300s
$K -n kube-system  wait --for=condition=Available deployment/metrics-server          --timeout=300s

# Job admission-webhooka ingress-nginx musi się dokończyć, inaczej pierwszy
# `kubectl apply` Ingressa w module 09 odbije się od niegotowego webhooka.
$K -n ingress-nginx wait --for=condition=Complete job/ingress-nginx-admission-create --timeout=180s 2>/dev/null || true
$K -n ingress-nginx wait --for=condition=Complete job/ingress-nginx-admission-patch  --timeout=180s 2>/dev/null || true

echo
echo "gotowe. Kontroler Ingress stoi na:"
$K -n ingress-nginx get pod -l app.kubernetes.io/component=controller \
  -o custom-columns=POD:.metadata.name,WEZEL:.spec.nodeName --no-headers
