---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · rozdział 14 · Security'
---

<!-- _class: tytul -->
<!-- _paginate: false -->

# Security

## Rozdział 14 · lab `14`

Świeżo postawiony Kubernetes nie jest zabezpieczony —
i to jest świadoma decyzja projektowa

---

# Plan rozdziału

<div data-marpit-fragment>

1. **Przegląd** — co jest domyślnie otwarte
2. **Dostęp do API** — trzy bramki, przez które przechodzi żądanie
3. **Uwierzytelnianie i autoryzacja** — kim jesteś, co możesz
4. **Admission controllers** — ostatnie słowo przed zapisem, limity namespace'u
5. **Network policies** — izolacja ruchu między Podami
6. **Lab 14** — zabezpieczasz klaster

</div>

---

<!-- _class: sekcja -->

# 1. Co jest domyślnie otwarte

---

# Świeży klaster — stan wyjściowy

<div data-marpit-fragment>

| Domyślnie | Konsekwencja |
|---|---|
| kontenery działają jako **root** | wyjście z kontenera = root na node'ie |
| **każdy Pod gada z każdym** | brak izolacji sieciowej między aplikacjami |
| Secrety w etcd **otwartym tekstem** | dostęp do etcd = wszystkie hasła |
| brak limitów zasobów | jeden Pod może zagłodzić node |
| `ServiceAccount` montowany do Poda | token API wewnątrz każdego kontenera |

</div>

<div data-marpit-fragment>

> To nie są błędy. Kubernetes dostarcza **mechanizmy**, nie gotową politykę —
> bo polityka zależy od tego, co i dla kogo uruchamiasz.
> Hardening jest Twoją pracą.

</div>

---

<!-- _class: sekcja -->

# 2. Trzy bramki

---

# Droga żądania do etcd

<div data-marpit-fragment>

```text
   żądanie
      │
      ▼  1. AUTHENTICATION      kim jesteś?        → 401
      ▼  2. AUTHORIZATION       czy ci wolno?      → 403
      ▼  3. ADMISSION           czy to dopuszczalne?  → 400 / odrzucenie
      ▼     walidacja schematu
      ▼     zapis do etcd
```

</div>

<div data-marpit-fragment>

| Kod | Która bramka | Znaczenie |
|---|---|---|
| **401** | uwierzytelnianie | *nie wiem, kim jesteś* |
| **403** | autoryzacja | *wiem, kim jesteś, i nie wolno ci* |

</div>

<div data-marpit-fragment>

> Rozróżnienie 401 od 403 to pierwsze pytanie przy diagnozie problemu
> z dostępem — kieruje w zupełnie inne miejsca konfiguracji.

</div>

---

<!-- _class: sekcja -->

# 3. Uwierzytelnianie i autoryzacja

---

# Kim jesteś

<div data-marpit-fragment>

Kubernetes **nie ma obiektu „użytkownik”**. Tożsamość przychodzi z zewnątrz:

</div>

<div data-marpit-fragment>

| Metoda | Jak wygląda | Typowe użycie |
|---|---|---|
| certyfikat klienta | CN = nazwa, O = grupy | administratorzy, kubeadm |
| **ServiceAccount token** | JWT montowany do Poda | workloady w klastrze |
| OIDC | token od dostawcy tożsamości | ludzie w organizacji |
| webhook | zewnętrzna usługa decyduje | integracje nietypowe |

</div>

<div data-marpit-fragment>

```bash
kubectl auth whoami
kubectl -n kube-system get pod -l component=kube-apiserver \
  -o jsonpath='{.items[0].spec.containers[0].command}' | tr ',' '\n' | grep authoriz
# --authorization-mode=Node,RBAC
```

</div>

<div data-marpit-fragment>

> `Node` autoryzuje kubelety do odczytu tylko tego, co dotyczy **ich** node'a.
> `RBAC` obsługuje całą resztę.

</div>

---

<!-- _class: sekcja -->

# 4. Admission controllers

---

# Ostatnie słowo przed zapisem

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Mutating

</div>

<div data-marpit-fragment>

**zmieniają** obiekt w locie

</div>

* `DefaultStorageClass`
* `ServiceAccount` — montuje token
* `LimitRanger` — dokłada domyślne
  `requests`
* webhooki service mesh wstrzykujące
  sidecar

</div>
<div>

<div data-marpit-fragment>

### Validating

</div>

<div data-marpit-fragment>

**przyjmują albo odrzucają**

</div>

* `PodSecurity` *(wbudowany od 1.25)*
* `ResourceQuota`
* `NamespaceLifecycle`
* własne webhooki polityk
  (OPA Gatekeeper, Kyverno)

</div>
</div>

<div data-marpit-fragment>

> Mutating idą **przed** validating. Dlatego `LimitRanger` może dołożyć
> `requests`, zanim `ResourceQuota` sprawdzi, czy mieszczą się w limicie —
> i dlatego Pod bez `requests` w ogóle przechodzi.

</div>

---

# Pluginy, których nie widać we flagach

<div data-marpit-fragment>

```bash
kubectl -n kube-system get pod -l component=kube-apiserver -o yaml | grep admission
#     - --enable-admission-plugins=NodeRestriction
```

</div>

<div data-marpit-fragment>

We flagach jest **jeden** plugin, a działa ich ponad dwadzieścia. Reszta jest
**włączona domyślnie** i nie trzeba jej wymieniać:

</div>

<div data-marpit-fragment>

```text
NamespaceLifecycle, LimitRanger, ServiceAccount, PodSecurity, Priority,
DefaultTolerationSeconds, DefaultStorageClass, StorageObjectInUseProtection,
RuntimeClass, DefaultIngressClass, MutatingAdmissionWebhook,
ValidatingAdmissionWebhook, ValidatingAdmissionPolicy, ResourceQuota, …
```

</div>

<div data-marpit-fragment>

> Dlatego `PodSecurity` z laba działa, choć nikt go nie włączał. Pełną listę
> domyślnych dla Twojej wersji podaje sam apiserver: `kube-apiserver --help`,
> opis flagi `--enable-admission-plugins`.

</div>

---

# Włączanie i wyłączanie pluginów

<div data-marpit-fragment>

| Flaga | Działanie |
|---|---|
| `--enable-admission-plugins=A,B` | włącza **dodatkowo**, poza domyślnymi |
| `--disable-admission-plugins=C` | wyłącza plugin z listy domyślnych |

</div>

<div data-marpit-fragment>

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml na node'ie control plane
    - --enable-admission-plugins=NodeRestriction,AlwaysPullImages
    - --disable-admission-plugins=LimitRanger
```

</div>

* kubelet podnosi apiserver z nowymi flagami po **kilkudziesięciu sekundach** — do tego czasu odpowiada stary
* czy zmiana weszła, widać we flagach mirror Poda apiservera, nie po tym, że `kubectl` działa
* kopia manifestu — **poza** katalogiem `manifests`: każdy plik w nim kubelet uruchamia

<div data-marpit-fragment>

> `AlwaysPullImages` wymusza `imagePullPolicy: Always` na każdym nowym Podzie —
> nikt nie uruchomi cudzego prywatnego obrazu z cache node'a bez poświadczeń.

</div>

---

# ResourceQuota i LimitRange

<div class="kolumny">
<div>

<div data-marpit-fragment>

### ResourceQuota — ile **razem**

</div>

<div data-marpit-fragment>

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: limity
spec:
  hard:
    pods: "10"
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.memory: 4Gi
```

</div>

<div data-marpit-fragment>

Budżet **całego namespace'u** — suma
wszystkich jego Podów.

</div>

</div>
<div>

<div data-marpit-fragment>

### LimitRange — ile **każdy**

</div>

<div data-marpit-fragment>

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: domyslne
spec:
  limits:
    - type: Container
      defaultRequest:
        cpu: 100m
        memory: 128Mi
      default:
        cpu: 500m
        memory: 256Mi
      max:
        memory: 1Gi
```

</div>

<div data-marpit-fragment>

Wartości domyślne i granice
**dla jednego kontenera**.

</div>

</div>
</div>

---

# Co się dzieje z Podem bez `requests`

<div data-marpit-fragment>

| W namespace jest | Pod bez `requests` i `limits` |
|---|---|
| sama `ResourceQuota` | **odrzucony** — quota nie ma czego policzyć |
| `ResourceQuota` + `LimitRange` | przyjęty z `requests: 100m / 128Mi`, `limits: 500m / 256Mi` |
| `LimitRange` z `max: 1Gi`, Pod chce `2Gi` | **odrzucony** — ponad granicę kontenera |

</div>

<div data-marpit-fragment>

```text
pods "bez-requests" is forbidden: failed quota: limity: must specify
limits.memory for: bez-requests; requests.cpu for: bez-requests; …
```

</div>

<div data-marpit-fragment>

```bash
kubectl describe quota limity -n produkcja
# Resource         Used   Hard
# requests.memory  128Mi  2Gi
```

</div>

<div data-marpit-fragment>

> Quota liczy **`requests` i `limits` z manifestów**, nie faktyczne zużycie —
> tak samo jak scheduler w rozdziale 11.

</div>

---

# Pod Security Admission

<div data-marpit-fragment>

```bash
kubectl label namespace produkcja \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted
```

</div>

<div data-marpit-fragment>

| Poziom | Co dopuszcza |
|---|---|
| `privileged` | wszystko — brak ograniczeń |
| `baseline` | blokuje najgroźniejsze: `privileged`, `hostNetwork`, `hostPath` |
| `restricted` | dodatkowo wymusza non-root, `drop ALL`, `seccomp` |

</div>

---

# Trzy tryby — można je łączyć

<div data-marpit-fragment>

| Tryb | Działanie |
|---|---|
| `enforce` | **odrzuca** Pody łamiące zasady |
| `audit` | wpisuje do dziennika audytu |
| `warn` | ostrzega osobę wydającą polecenie |

</div>

<div data-marpit-fragment>

```bash
kubectl run zly --image=nginx -n produkcja --privileged --dry-run=server
# Error: violates PodSecurity "restricted:latest"
```

</div>

<div data-marpit-fragment>

> Typowe wdrożenie zaczyna się od `warn` i `audit` na istniejących
> namespace'ach — żeby zobaczyć skalę problemu, zanim `enforce` zacznie
> odrzucać Pody. `--dry-run=server` sprawdza politykę bez zapisu.

</div>

---

# Hardening kontenera

<div data-marpit-fragment>

```yaml
spec:
  securityContext:                    # poziom Poda
    runAsNonRoot: true
    runAsUser: 10001
    seccompProfile: {type: RuntimeDefault}
  containers:
    - name: app
      securityContext:                # poziom kontenera
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: {drop: ["ALL"]}
```

</div>

<div data-marpit-fragment>

Pięć ustawień, pięć różnych klas ataku — rozbierzmy je po kolei.

</div>

---

# Przed czym chroni każde z nich

<div data-marpit-fragment>

| Ustawienie | Przed czym chroni |
|---|---|
| `runAsNonRoot` | root w kontenerze = root na node'ie po ucieczce |
| `allowPrivilegeEscalation: false` | `setuid`, `sudo` wewnątrz kontenera |
| `readOnlyRootFilesystem` | trwała modyfikacja systemu plików |
| `capabilities: drop ALL` | uprawnienia jądra, których aplikacja nie potrzebuje |
| `seccompProfile: RuntimeDefault` | ogranicza dostępne wywołania systemowe |

</div>

<div data-marpit-fragment>

> Cena jest realna: aplikacja pisząca do `/var/cache` potrzebuje `emptyDir`,
> a port poniżej 1024 staje się niedostępny.

</div>

---

<!-- _class: sekcja -->

# 5. Network policies

---

# Domyślnie każdy gada z każdym

<div data-marpit-fragment>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: tylko-dozwolony, namespace: lfs458-m14}
spec:
  podSelector:
    matchLabels: {rola: serwer}        # KOGO bronimy
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector:
            matchLabels: {rola: klient-ok}
      ports: [{protocol: TCP, port: 5678}]
```

</div>

* polityka **domyślnie zabrania** wszystkiego, czego nie dopuści wprost
* selektor `{}` obejmuje **wszystkie** Pody w namespace; polityki się **sumują**
* namespace wybiera się przez `namespaceSelector` i etykietę
  `kubernetes.io/metadata.name`

---

# Polityka bez wsparcia CNI milczy

<div data-marpit-fragment>

> `NetworkPolicy` to **obiekt w API**. Egzekwuje ją CNI plugin.
> Jeśli CNI plugin tego nie obsługuje, obiekt zostanie przyjęty,
> nie zgłosi błędu — **i nie zrobi nic**.

</div>

<div data-marpit-fragment>

```bash
IP=$(kubectl get pod serwer -n lfs458-m14 -o jsonpath='{.status.podIP}')
kubectl exec -n lfs458-m14 dozwolony  -- wget -qO- --timeout=4 http://$IP:5678
kubectl exec -n lfs458-m14 zabroniony -- wget -qO- --timeout=4 http://$IP:5678
```

</div>

<div data-marpit-fragment>

| Wtyczka | NetworkPolicy |
|---|---|
| Calico, Cilium | tak, z rozszerzeniami |
| kindnet *(nasz klaster)* | tak, od kind 0.26 |
| Flannel | **nie** |

</div>

<div data-marpit-fragment>

**Utworzenie obiektu nie jest dowodem. Dowodem jest timeout u zabronionego.**

</div>

---

<!-- _class: lab -->

# Lab 14

<div data-marpit-fragment>

**22 punkty + 3 dodatkowe**

</div>

<div data-marpit-fragment>

```bash
labctl lab 14
```

</div>

<div data-marpit-fragment>

Zabezpieczysz Poda pełnym `securityContext`, włączysz Pod Security Admission
na poziomie `restricted` i sprawdzisz, że namespace odrzuca uprzywilejowany
Pod, a potem zbudujesz scenę z trzema Podami i **doświadczalnie udowodnisz**,
że NetworkPolicy blokuje jednego klienta, a drugiego przepuszcza.
Na koniec zmienisz zestaw pluginów admission i zobaczysz skutek na Podzie.

</div>

<div data-marpit-fragment>

> Najważniejsze zadanie to czwarte. Nie wystarczy utworzyć obiekt —
> trzeba sprawdzić, że naprawdę działa.

</div>

---

# Co warto zapamiętać

* Kubernetes daje mechanizmy, nie politykę — hardening jest Twoją pracą
* **401** = uwierzytelnianie, **403** = autoryzacja
* użytkownicy nie są obiektami; ServiceAccount jest
* admission: najpierw mutating, potem validating
* większość pluginów admission działa **domyślnie**, choć nie ma ich we flagach;
  `--enable-admission-plugins` dokłada, `--disable-admission-plugins` wyłącza
* `ResourceQuota` to budżet namespace'u, `LimitRange` — domyślne wartości
  kontenera; sama quota odrzuca Pody bez `requests`
* `PodSecurity` jest wbudowany; włącza się **etykietą namespace'u**
* `--dry-run=server` sprawdza politykę bez zapisu
* NetworkPolicy domyślnie zabrania tego, czego nie dopuści; polityki się sumują
* **bez wsparcia CNI polityka nie robi nic i nie zgłasza błędu**

<script src="nawigacja.js"></script>
