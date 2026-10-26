#!/usr/bin/env bash
# Rozwiązanie referencyjne laba 14 — dla trenera i dla CI.
set -euo pipefail

CTX="${KUBECONTEXT:-kind-lfs458}"
NS=lfs458-m14
k() { kubectl --context "$CTX" "$@"; }

echo "→ zadanie 1: zabezpieczony Pod"
k create namespace "$NS" --dry-run=client -o yaml | k apply -f -
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: zabezpieczony
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
k wait --for=condition=Ready pod/zabezpieczony -n "$NS" --timeout=180s
echo "   UID procesu w kontenerze: $(k exec -n "$NS" zabezpieczony -- id -u)"

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
SERWER=$(k config view --minify -o jsonpath='{.clusters[0].cluster.server}')
echo "   odpowiedzi do pytań w labctl lab:"
echo "     --enable-admission-plugins: $(k -n kube-system get pod -l component=kube-apiserver -o json | jq -r '.items[0].spec.containers[0].command[] | select(startswith("--enable-admission-plugins="))' | cut -d= -f2-)"
echo "     zmyślony token: $(curl -sk -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer zmyslony' "$SERWER/api")"
echo "     bez tokena:     $(curl -sk -o /dev/null -w '%{http_code}' "$SERWER/api")"
echo "     bramka przy 403: autoryzacja"

echo "→ zadanie 7: pluginy admission (kopię manifestu robi labctl przed zadaniem)"
docker exec lfs458-control-plane test -f /etc/kubernetes/apiserver.lab14 \
  || docker exec lfs458-control-plane cp /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/apiserver.lab14
if ! docker exec lfs458-control-plane grep -q AlwaysPullImages /etc/kubernetes/manifests/kube-apiserver.yaml; then
  docker exec lfs458-control-plane sed -i \
    's|--enable-admission-plugins=NodeRestriction$|--enable-admission-plugins=NodeRestriction,AlwaysPullImages\n    - --disable-admission-plugins=LimitRanger|' \
    /etc/kubernetes/manifests/kube-apiserver.yaml
fi
echo "   czekam na apiserver z nowymi flagami"
until k -n kube-system get pod -l component=kube-apiserver -o yaml 2>/dev/null | grep -q AlwaysPullImages; do sleep 5; done
until k get --raw /healthz >/dev/null 2>&1; do sleep 3; done
k create namespace lfs458-m14-wtyczki --dry-run=client -o yaml | k apply -f - >/dev/null
cat <<'YAML' | k apply -f - >/dev/null
apiVersion: v1
kind: LimitRange
metadata: {name: domyslne, namespace: lfs458-m14-wtyczki}
spec:
  limits:
    - type: Container
      defaultRequest: {cpu: 100m, memory: 128Mi}
YAML
k delete pod sprawdzian -n lfs458-m14-wtyczki --ignore-not-found >/dev/null
k run sprawdzian -n lfs458-m14-wtyczki --image=nginx:1.27-alpine --image-pull-policy=IfNotPresent
k get pod sprawdzian -n lfs458-m14-wtyczki -o jsonpath='   {.spec.containers[0].imagePullPolicy} {.spec.containers[0].resources}{"\n"}'

echo "→ zadanie 8: użytkownik z certyfikatu"
ROB=$(mktemp -d)
openssl genrsa -out "$ROB/anna.key" 2048 2>/dev/null
openssl req -new -key "$ROB/anna.key" -out "$ROB/anna.csr" -subj "/CN=anna/O=zespol-sklep"
cat <<YAML | k apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: lfs458-anna
spec:
  request: $(base64 -w0 < "$ROB/anna.csr")
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages: ["client auth"]
YAML
k certificate approve lfs458-anna
until k get csr lfs458-anna -o jsonpath='{.status.certificate}' 2>/dev/null | grep -q .; do sleep 1; done
k get csr lfs458-anna -o jsonpath='{.status.certificate}' | base64 -d > "$ROB/anna.crt"
k create role czytelnik-podow --verb=get,list,watch --resource=pods -n "$NS" 2>/dev/null || true
k create rolebinding zespol-czyta --role=czytelnik-podow --group=zespol-sklep -n "$NS" 2>/dev/null || true
kubectl config set-credentials anna --client-certificate="$ROB/anna.crt" --client-key="$ROB/anna.key" --embed-certs >/dev/null
kubectl config set-context anna@lfs458 --cluster=kind-lfs458 --user=anna --namespace="$NS" >/dev/null
echo "   anna: get pods → $(kubectl --context anna@lfs458 auth can-i list pods), delete → $(kubectl --context anna@lfs458 auth can-i delete pods)"

echo
echo "Gotowe. Weryfikacja: labctl check 14"
