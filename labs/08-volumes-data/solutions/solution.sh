#!/usr/bin/env bash
# Rozwiązanie referencyjne laba 08 — dla trenera i dla CI.
set -euo pipefail

CTX="${KUBECONTEXT:-kind-lfs458}"
NS=lfs458-m08
k() { kubectl --context "$CTX" "$@"; }

echo "→ zadanie 1: emptyDir między dwoma kontenerami"
k create namespace "$NS" --dry-run=client -o yaml | k apply -f -
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: wymiana
  namespace: lfs458-m08
spec:
  volumes:
    - name: robocze
      emptyDir: {}
  containers:
    - name: producent
      image: busybox:1.36
      command: ["sh","-c","echo dane-z-emptydir > /wyjscie/raport.txt && sleep 3600"]
      volumeMounts:
        - name: robocze
          mountPath: /wyjscie
    - name: konsument
      image: busybox:1.36
      command: ["sleep","3600"]
      volumeMounts:
        - name: robocze
          mountPath: /wejscie
YAML
k wait --for=condition=Ready pod/wymiana -n "$NS" --timeout=180s

echo "→ zadanie 2: PVC z dynamicznym provisioningiem"
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dane
  namespace: lfs458-m08
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: standard
  resources:
    requests:
      storage: 100Mi
YAML
if ! k get pod baza -n "$NS" >/dev/null 2>&1 && ! k get pod baza-2 -n "$NS" >/dev/null 2>&1; then
  cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: baza
  namespace: lfs458-m08
spec:
  volumes:
    - name: dane
      persistentVolumeClaim:
        claimName: dane
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh","-c","echo trwale > /dane/stan.txt && sleep 3600"]
      volumeMounts:
        - name: dane
          mountPath: /dane
YAML
  k wait --for=condition=Ready pod/baza -n "$NS" --timeout=300s
fi

echo "→ zadanie 3: ConfigMapa dwoma kanałami"
k create configmap ustawienia -n "$NS" \
  --from-literal=TRYB=produkcja \
  --from-literal=POZIOM_LOGOW=debug \
  --dry-run=client -o yaml | k apply -f -
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: konfiguracja
  namespace: lfs458-m08
spec:
  volumes:
    - name: konf
      configMap:
        name: ustawienia
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep","3600"]
      env:
        - name: TRYB
          valueFrom:
            configMapKeyRef:
              name: ustawienia
              key: TRYB
      volumeMounts:
        - name: konf
          mountPath: /etc/ustawienia
YAML
k wait --for=condition=Ready pod/konfiguracja -n "$NS" --timeout=180s

echo "→ zadanie 4: Secret jako zmienne środowiskowe"
k create secret generic poswiadczenia -n "$NS" \
  --from-literal=uzytkownik=admin \
  --from-literal=haslo=tajne123 \
  --dry-run=client -o yaml | k apply -f -
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: klient-bazy
  namespace: lfs458-m08
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep","3600"]
      env:
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: poswiadczenia
              key: uzytkownik
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: poswiadczenia
              key: haslo
YAML
k wait --for=condition=Ready pod/klient-bazy -n "$NS" --timeout=180s

echo "→ zadanie 5: Secret zamontowany jako pliki"
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: certyfikat
  namespace: lfs458-m08
type: Opaque
stringData:
  klucz.pem: |
    -----BEGIN PRIVATE KEY-----
    to-nie-jest-prawdziwy-klucz
    -----END PRIVATE KEY-----
  cert.pem: |
    -----BEGIN CERTIFICATE-----
    to-nie-jest-prawdziwy-certyfikat
    -----END CERTIFICATE-----
---
apiVersion: v1
kind: Pod
metadata:
  name: czytelnik-sekretu
  namespace: lfs458-m08
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep","3600"]
      volumeMounts:
        - name: tls
          mountPath: /etc/tls
          readOnly: true
  volumes:
    - name: tls
      secret:
        secretName: certyfikat
        defaultMode: 0400
YAML
k wait --for=condition=Ready pod/czytelnik-sekretu -n "$NS" --timeout=180s

echo "→ zadanie 6: dowód trwałości wolumenu"
k delete pod baza -n "$NS" --ignore-not-found --wait=true
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: baza-2
  namespace: lfs458-m08
spec:
  volumes:
    - name: dane
      persistentVolumeClaim:
        claimName: dane
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep","3600"]
      volumeMounts:
        - name: dane
          mountPath: /dane
YAML
k wait --for=condition=Ready pod/baza-2 -n "$NS" --timeout=300s
echo "   zawartość po odtworzeniu Poda: $(k exec -n "$NS" baza-2 -- cat /dane/stan.txt)"

echo "→ zadanie 7 (dodatkowe): statyczny PV i PVC bez klasy"
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: archiwum-pv
spec:
  capacity:
    storage: 500Mi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  hostPath:
    path: /tmp/archiwum
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: archiwum
  namespace: lfs458-m08
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ""
  resources:
    requests:
      storage: 200Mi
YAML
for _ in $(seq 1 30); do
  [ "$(k get pvc archiwum -n "$NS" -o jsonpath='{.status.phase}')" = "Bound" ] && break
  sleep 2
done
k get pv archiwum-pv

echo "→ zadanie 8 (dodatkowe): imagePullSecrets i typ dockerconfigjson"
k create secret docker-registry rejestr -n "$NS" \
  --docker-server=rejestr.firma.local \
  --docker-username=kursant \
  --docker-password=tajne123 \
  --dry-run=client -o yaml | k apply -f -
cat <<'YAML' | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: z-rejestru
  namespace: lfs458-m08
spec:
  imagePullSecrets:
    - name: rejestr
  containers:
    - name: web
      image: nginx:1.27-alpine
YAML
k wait --for=condition=Ready pod/z-rejestru -n "$NS" --timeout=180s

echo
echo "Gotowe. Weryfikacja: labctl check 08"
