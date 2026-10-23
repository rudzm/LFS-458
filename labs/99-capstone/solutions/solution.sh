#!/usr/bin/env bash
# Rozwiązanie referencyjne capstone'u — dla trenera i dla CI.
set -euo pipefail

CTX="${KUBECONTEXT:-kind-lfs458}"
NS=sklep-prod
k() { kubectl --context "$CTX" "$@"; }

echo "→ zadanie 1: namespace z ograniczeniami"
k create namespace "$NS" --dry-run=client -o yaml | k apply -f -
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: ResourceQuota
metadata: {name: limity, namespace: sklep-prod}
spec:
  hard:
    pods: "10"
    requests.memory: 2Gi
---
apiVersion: v1
kind: LimitRange
metadata: {name: domyslne, namespace: sklep-prod}
spec:
  limits:
    - type: Container
      defaultRequest:
        cpu: 100m
        memory: 128Mi
YAML

echo "→ zadanie 2: konfiguracja, sekret, ServiceAccount, RBAC"
k create configmap api-config -n "$NS" \
  --from-literal=TRYB=produkcja --from-literal=POZIOM_LOGOW=warn \
  --dry-run=client -o yaml | k apply -f -
k create secret generic api-secret -n "$NS" \
  --from-literal=API_KLUCZ=tajny-klucz-produkcyjny \
  --dry-run=client -o yaml | k apply -f -
k create serviceaccount api -n "$NS" --dry-run=client -o yaml | k apply -f -
k create role api-config-odczyt --verb=get,list --resource=configmaps -n "$NS" \
  --dry-run=client -o yaml | k apply -f -
k create rolebinding api --role=api-config-odczyt \
  --serviceaccount="${NS}:api" -n "$NS" --dry-run=client -o yaml | k apply -f -

echo "→ zadanie 3: Deployment zgodny ze standardem produkcyjnym"
cat <<'YAML' | k apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: {name: api, namespace: sklep-prod}
spec:
  replicas: 2
  selector:
    matchLabels: {app: api}
  template:
    metadata:
      labels: {app: api}
    spec:
      serviceAccountName: api
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
      affinity:
        podAntiAffinity:
          # preferred, nie required: required zakleszczylby rollout z maxSurge: 1,
          # bo nadmiarowa replika nie mialaby wolnego node'a.
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              podAffinityTerm:
                labelSelector:
                  matchLabels: {app: api}
                topologyKey: kubernetes.io/hostname
      containers:
        - name: api
          image: hashicorp/http-echo:1.0
          args: ["-text=api-v1", "-listen=:5678"]
          ports: [{name: http, containerPort: 5678}]
          env:
            - name: TRYB
              valueFrom: {configMapKeyRef: {name: api-config, key: TRYB}}
            - name: API_KLUCZ
              valueFrom: {secretKeyRef: {name: api-secret, key: API_KLUCZ}}
          resources:
            requests: {cpu: 50m, memory: 64Mi}
          readinessProbe:
            httpGet: {path: /, port: 5678}
            initialDelaySeconds: 2
          livenessProbe:
            httpGet: {path: /, port: 5678}
            initialDelaySeconds: 5
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: {drop: ["ALL"]}
YAML
k rollout status deployment/api -n "$NS" --timeout=300s

echo "→ zadanie 4: Service i Ingress"
k expose deployment api --port=80 --target-port=5678 -n "$NS" \
  --dry-run=client -o yaml | k apply -f -
cat <<'YAML' | k apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: api, namespace: sklep-prod}
spec:
  ingressClassName: nginx
  rules:
    - host: sklep.lfs458.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: {service: {name: api, port: {number: 80}}}
YAML
for _ in $(seq 1 40); do
  curl -fsS --max-time 3 -H 'Host: sklep.lfs458.local' http://localhost:8080/ >/dev/null 2>&1 && break
  sleep 3
done
curl -s --max-time 5 -H 'Host: sklep.lfs458.local' http://localhost:8080/

echo "→ zadanie 5: izolacja sieciowa"
cat <<'YAML' | k apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: api-tylko-ingress, namespace: sklep-prod}
spec:
  podSelector:
    matchLabels: {app: api}
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
      ports:
        - protocol: TCP
          port: 5678
---
apiVersion: v1
kind: Pod
metadata: {name: obcy, namespace: sklep-prod}
spec:
  containers:
    - {name: c, image: "busybox:1.36", command: ["sleep","3600"]}
YAML
k wait --for=condition=Ready pod/obcy -n "$NS" --timeout=180s
sleep 10
if k exec -n "$NS" obcy -- wget -qO- --timeout=6 http://api >/dev/null 2>&1; then
  echo "   obcy: PRZESZEDL (polityka nie dziala!)"
else
  echo "   obcy: zablokowany"
fi

echo "→ zadanie 6: PDB, strategia i wydanie api-v2"
cat <<'YAML' | k apply -f -
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: api-pdb, namespace: sklep-prod}
spec:
  minAvailable: 1
  selector:
    matchLabels: {app: api}
YAML
k patch deployment api -n "$NS" --type=strategic -p '{
  "spec": {
    "strategy": {"type":"RollingUpdate","rollingUpdate":{"maxUnavailable":0,"maxSurge":1}},
    "template": {"spec": {"containers": [
      {"name":"api","args":["-text=api-v2","-listen=:5678"]}]}}
  }}'
k annotate deployment api -n "$NS" --overwrite \
  kubernetes.io/change-cause='wydanie api-v2'
k rollout status deployment/api -n "$NS" --timeout=300s

echo "→ zadanie 7 (dodatkowe): warstwa danych"
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: api-dane, namespace: sklep-prod}
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: standard
  resources: {requests: {storage: 100Mi}}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: baza, namespace: sklep-prod}
spec:
  replicas: 1
  selector: {matchLabels: {app: baza}}
  template:
    metadata: {labels: {app: baza}}
    spec:
      volumes:
        - name: dane
          persistentVolumeClaim: {claimName: api-dane}
      containers:
        - name: baza
          image: busybox:1.36
          command: ["sh","-c","[ -f /dane/init.txt ] || echo capstone > /dane/init.txt; sleep 3600"]
          volumeMounts:
            - {name: dane, mountPath: /dane}
YAML
k rollout status deployment/baza -n "$NS" --timeout=300s
k delete pod -n "$NS" -l app=baza --wait=true
k rollout status deployment/baza -n "$NS" --timeout=300s
echo "   zawartość po odtworzeniu: $(k exec -n "$NS" deploy/baza -- cat /dane/init.txt)"

echo
echo "Gotowe. Weryfikacja: labctl check 99"
