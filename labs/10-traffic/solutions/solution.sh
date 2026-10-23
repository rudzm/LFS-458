#!/usr/bin/env bash
# Rozwiązanie referencyjne laba 10 — dla trenera i dla CI.
# Wymaga uruchomionego wcześniej `labctl setup 10`.
set -euo pipefail

CTX="${KUBECONTEXT:-kind-lfs458}"
NS=lfs458-m10
k() { kubectl --context "$CTX" "$@"; }

echo "→ zadanie 1: dwie aplikacje i Ingress po hoście"
k create namespace "$NS" --dry-run=client -o yaml | k apply -f -
for a in sklep blog; do
  k create deployment "$a" --image=hashicorp/http-echo:1.0 -n "$NS" \
    --dry-run=client -o yaml -- /http-echo -text="to-jest-$a" -listen=:5678 | k apply -f -
  k expose deployment "$a" --port=5678 -n "$NS" --dry-run=client -o yaml | k apply -f -
done
k rollout status deployment/sklep -n "$NS" --timeout=300s
k rollout status deployment/blog -n "$NS" --timeout=300s

cat <<'YAML' | k apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: firma
  namespace: lfs458-m10
spec:
  ingressClassName: nginx
  rules:
    - host: sklep.lfs458.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: {service: {name: sklep, port: {number: 5678}}}
    - host: blog.lfs458.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: {service: {name: blog, port: {number: 5678}}}
YAML

echo "   czekam, aż Ingress zacznie odpowiadać"
for _ in $(seq 1 40); do
  curl -fsS --max-time 3 -H 'Host: sklep.lfs458.local' http://localhost:8080/ >/dev/null 2>&1 && break
  sleep 3
done
curl -s --max-time 5 -H 'Host: sklep.lfs458.local' http://localhost:8080/

echo "→ zadanie 2: Ingress po ścieżce z przepisywaniem"
cat <<'YAML' | k apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: sciezki
  namespace: lfs458-m10
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
    - host: firma.lfs458.local
      http:
        paths:
          - path: /sklep(/|$)(.*)
            pathType: ImplementationSpecific
            backend: {service: {name: sklep, port: {number: 5678}}}
          - path: /blog(/|$)(.*)
            pathType: ImplementationSpecific
            backend: {service: {name: blog, port: {number: 5678}}}
YAML
for _ in $(seq 1 30); do
  curl -fsS --max-time 3 -H 'Host: firma.lfs458.local' http://localhost:8080/sklep >/dev/null 2>&1 && break
  sleep 3
done

echo "→ zadanie 3: TLS"
if ! k get secret sklep-tls -n "$NS" >/dev/null 2>&1; then
  tmpdir=$(mktemp -d)
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$tmpdir/tls.key" -out "$tmpdir/tls.crt" \
    -subj "/CN=bezpieczny.lfs458.local" \
    -addext "subjectAltName=DNS:bezpieczny.lfs458.local" 2>/dev/null
  k create secret tls sklep-tls --cert="$tmpdir/tls.crt" --key="$tmpdir/tls.key" -n "$NS"
  rm -rf "$tmpdir"
fi
# Osobny Ingress i osobny host: wlaczenie TLS wlacza tez przekierowanie
# HTTP->HTTPS, ktore zepsuloby sprawdzenia zadania 1 na tych samych hostach.
cat <<'YAML' | k apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: bezpieczny
  namespace: lfs458-m10
spec:
  ingressClassName: nginx
  tls:
    - hosts: [bezpieczny.lfs458.local]
      secretName: sklep-tls
  rules:
    - host: bezpieczny.lfs458.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: {service: {name: sklep, port: {number: 5678}}}
YAML
for _ in $(seq 1 30); do
  curl -fsSk --max-time 3 -H 'Host: bezpieczny.lfs458.local' https://localhost:8443/ >/dev/null 2>&1 && break
  sleep 3
done

echo "→ zadanie 4: Gateway API"
GWCLASS=$(k get gatewayclass -o jsonpath='{.items[0].metadata.name}')
: "${GWCLASS:?brak GatewayClass — uruchom najpierw: labctl setup 10}"
echo "   klasa bramy: $GWCLASS"
cat <<YAML | k apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: brama
  namespace: lfs458-m10
spec:
  gatewayClassName: ${GWCLASS}
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: sklep
  namespace: lfs458-m10
spec:
  parentRefs:
    - name: brama
  hostnames: ["sklep.lfs458.local"]
  rules:
    - matches:
        - path: {type: PathPrefix, value: /}
      backendRefs:
        - name: sklep
          port: 5678
YAML
k wait --for=condition=Programmed gateway/brama -n "$NS" --timeout=300s

# Adres bramy przydziela cloud-provider-kind — czytamy go ze statusu obiektu.
BRAMA=""
for _ in $(seq 1 40); do
  BRAMA=$(k get gateway brama -n "$NS" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null)
  [ -n "$BRAMA" ] && curl -fsS --max-time 3 -H 'Host: sklep.lfs458.local' \
    "http://${BRAMA}/" >/dev/null 2>&1 && break
  sleep 3
done
echo "   brama pod adresem: ${BRAMA:-brak}"
[ -n "$BRAMA" ] && curl -s --max-time 5 -H 'Host: sklep.lfs458.local' "http://${BRAMA}/"

echo "→ zadanie 5 (dodatkowe): podział ruchu 90/10"
k create deployment sklep-v2 --image=hashicorp/http-echo:1.0 -n "$NS" \
  --dry-run=client -o yaml -- /http-echo -text=to-jest-sklep-v2 -listen=:5678 | k apply -f -
k expose deployment sklep-v2 --port=5678 -n "$NS" --dry-run=client -o yaml | k apply -f -
k rollout status deployment/sklep-v2 -n "$NS" --timeout=300s
k patch httproute sklep -n "$NS" --type=merge -p '{
  "spec": {"rules": [{
    "matches": [{"path": {"type": "PathPrefix", "value": "/"}}],
    "backendRefs": [
      {"name": "sklep",    "port": 5678, "weight": 90},
      {"name": "sklep-v2", "port": 5678, "weight": 10}
    ]
  }]}
}'

echo
echo "Gotowe. Weryfikacja: labctl check 10"
