#!/usr/bin/env bash
# Rozwiązanie referencyjne laba 14 — dla trenera i dla CI.
set -euo pipefail

CTX="${KUBECONTEXT:-kind-lfs458}"
NS=lfs458-m14
k() { kubectl --context "$CTX" "$@"; }

echo "→ zadanie 1: utwardzony Pod"
k create namespace "$NS" --dry-run=client -o yaml | k apply -f -
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: utwardzony
  namespace: lfs458-m14
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      image: nginx:1.27-alpine
      command: ["sleep", "3600"]
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
      volumeMounts:
        - {name: cache, mountPath: /var/cache/nginx}
        - {name: run, mountPath: /var/run}
        - {name: tmp, mountPath: /tmp}
  volumes:
    - {name: cache, emptyDir: {}}
    - {name: run, emptyDir: {}}
    - {name: tmp, emptyDir: {}}
YAML
k wait --for=condition=Ready pod/utwardzony -n "$NS" --timeout=180s
echo "   UID procesu w kontenerze: $(k exec -n "$NS" utwardzony -- id -u)"

echo "→ zadanie 2: Pod Security Admission"
k create namespace lfs458-m14-scisly --dry-run=client -o yaml | k apply -f -
k label namespace lfs458-m14-scisly --overwrite \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted
echo "   próba uruchomienia uprzywilejowanego Poda (ma zostać odrzucona):"
k run zly --image=nginx:1.27-alpine -n lfs458-m14-scisly --privileged --dry-run=server 2>&1 | tail -2 || true
ARKUSZ="${ODPOWIEDZI:-$HOME/odpowiedzi}/lab-14.txt"
mkdir -p "$(dirname "$ARKUSZ")"
cat >> "$ARKUSZ" <<EOF
poziom=restricted
EOF

echo "→ zadanie 3: scena do testu izolacji"
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Pod
metadata: {name: serwer, namespace: lfs458-m14, labels: {rola: serwer}}
spec:
  containers:
    - name: echo
      image: hashicorp/http-echo:1.0
      args: ["-text=tajne", "-listen=:5678"]
---
apiVersion: v1
kind: Pod
metadata: {name: dozwolony, namespace: lfs458-m14, labels: {rola: klient-ok}}
spec:
  containers:
    - {name: c, image: "busybox:1.36", command: ["sleep","3600"]}
---
apiVersion: v1
kind: Pod
metadata: {name: zabroniony, namespace: lfs458-m14, labels: {rola: klient-zly}}
spec:
  containers:
    - {name: c, image: "busybox:1.36", command: ["sleep","3600"]}
YAML
k wait --for=condition=Ready pod/serwer pod/dozwolony pod/zabroniony -n "$NS" --timeout=300s
IP=$(k get pod serwer -n "$NS" -o jsonpath='{.status.podIP}')
echo "   przed polityką, zabroniony: $(k exec -n "$NS" zabroniony -- wget -qO- --timeout=4 "http://$IP:5678" 2>&1 | head -1)"

echo "→ zadanie 4: NetworkPolicy i dowód działania"
cat <<'YAML' | k apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tylko-dozwolony
  namespace: lfs458-m14
spec:
  podSelector:
    matchLabels:
      rola: serwer
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              rola: klient-ok
      ports:
        - protocol: TCP
          port: 5678
YAML
sleep 10
echo "   po polityce, dozwolony:  $(k exec -n "$NS" dozwolony -- wget -qO- --timeout=6 "http://$IP:5678" 2>&1 | head -1)"
if k exec -n "$NS" zabroniony -- wget -qO- --timeout=6 "http://$IP:5678" >/dev/null 2>&1; then
  echo "   po polityce, zabroniony: PRZESZEDL (polityka nie dziala!)"
else
  echo "   po polityce, zabroniony: zablokowany"
fi

echo "→ zadanie 5 (dodatkowe): konfiguracja apiservera"
k -n kube-system get pod -l component=kube-apiserver \
  -o jsonpath='{.items[0].spec.containers[0].command}' 2>/dev/null \
  | tr ',' '\n' | grep admission || true
SERWER=$(k config view --minify -o jsonpath='{.clusters[0].cluster.server}')
echo "   odpowiedzi do pytań w labctl lab:"
echo "     --enable-admission-plugins: NodeRestriction (PodSecurity jest wbudowane i włączone domyślnie)"
echo "     zmyślony token: $(curl -sk -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer zmyslony' "$SERWER/api")"
echo "     bez tokena:     $(curl -sk -o /dev/null -w '%{http_code}' "$SERWER/api")"

echo
echo "Gotowe. Weryfikacja: labctl check 14"
