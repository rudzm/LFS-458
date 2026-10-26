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
3. **Uwierzytelnianie i autoryzacja** — certyfikaty użytkowników, RBAC i ABAC
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
| static token file | linia w pliku CSV na node'ie control plane | testy, laby |

</div>

<div data-marpit-fragment>

```bash
kubectl auth whoami      # kim jestem dla apiservera: nazwa, grupy
```

</div>

<div data-marpit-fragment>

> `Node` autoryzuje kubelety do odczytu tylko tego, co dotyczy **ich** node'a.
> `RBAC` obsługuje całą resztę.

</div>

---

# Użytkownik z certyfikatu — wniosek

<div class="kolumny">
<div>

<div data-marpit-fragment>

```bash
openssl genrsa -out anna.key 2048
openssl req -new -key anna.key \
  -out anna.csr \
  -subj "/CN=anna/O=zespol-sklep"
```

</div>

* `CN` staje się **nazwą** użytkownika, `O` — jego **grupą**
* klucz prywatny zostaje u Ciebie; do klastra trafia tylko wniosek

</div>
<div>

<div data-marpit-fragment>

```yaml
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: anna
spec:
  request: <base64 z anna.csr>
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400   # 24 h
  usages: ["client auth"]
```

</div>

</div>
</div>

<div data-marpit-fragment>

> Certyfikatu **nie da się odwołać** — działa do końca ważności.
> Dlatego `expirationSeconds` ustawia się krótko.

</div>

---

# Administrator akceptuje albo odrzuca

<div data-marpit-fragment>

```bash
kubectl get csr
# NAME   SIGNERNAME                            REQUESTOR          CONDITION
# anna   kubernetes.io/kube-apiserver-client   kubernetes-admin   Pending

kubectl get csr anna -o jsonpath='{.spec.request}' | base64 -d | openssl req -noout -subject
# subject=CN = anna, O = zespol-sklep         ← sprawdź, ZANIM zatwierdzisz

kubectl certificate approve anna               # → Approved,Issued
kubectl certificate deny obcy                  # → Denied, certyfikatu brak
```

</div>

* `REQUESTOR` to **składający** wniosek, nie przyszły użytkownik — kogo dotyczy, mówi dopiero zdekodowany `spec.request`
* grupy `system:masters` nie da się nawet wnioskować:
  `use of kubernetes.io/kube-apiserver-client signer with system:masters group is not allowed`

---

# Kubeconfig i RBAC dla nowego użytkownika

<div data-marpit-fragment>

```bash
kubectl get csr anna -o jsonpath='{.status.certificate}' | base64 -d > anna.crt
kubectl config set-credentials anna --client-certificate=anna.crt --client-key=anna.key --embed-certs
kubectl config set-context anna@lfs458 --cluster=kind-lfs458 --user=anna --namespace=sklep

kubectl --context anna@lfs458 get pods
# Error from server (Forbidden): pods is forbidden: User "anna" cannot list resource "pods" …

kubectl create role czytelnik-podow --verb=get,list,watch --resource=pods -n sklep
kubectl create rolebinding zespol-czyta --role=czytelnik-podow --group=zespol-sklep -n sklep
kubectl --context anna@lfs458 get pods                       # działa
```

</div>

<div data-marpit-fragment>

> Certyfikat mówi, **kim jesteś** — co Ci wolno, decyduje RBAC. Binding na
> grupę z `O` zamiast na osobę: nowa osoba w zespole to nowy certyfikat,
> bez zmian w RBAC.

</div>

---

# LDAP, Kerberos, SSO — przez pośrednika

<div data-marpit-fragment>

Kubernetes **nie rozmawia** z LDAP-em, AD ani Kerberosem — potrzebny jest pośrednik:

</div>

<div data-marpit-fragment>

| Droga | Jak działa | Przykłady narzędzi |
|---|---|---|
| **OIDC** | dostawca tożsamości wystawia token, apiserver go weryfikuje (`--oidc-*`, `--authentication-config`) | Keycloak (LDAP, AD, Kerberos), Dex (LDAP, GitHub, SAML), Entra ID, Okta |
| **webhook** | apiserver pyta zewnętrzną usługę, czyj to token | Guard (LDAP, AD, GitHub) |
| **proxy** | proxy przed apiserverem loguje i przekazuje tożsamość w nagłówkach | Teleport, Pinniped, kube-oidc-proxy |
| **chmura** | konta z IAM dostawcy | EKS: IAM, AKS: Entra ID, GKE: konta Google |

</div>

<div data-marpit-fragment>

> Logowanie w przeglądarce do `kubectl` dokłada plugin `kubelogin`. Każda droga
> kończy się nazwą i grupami — dalej decyduje RBAC, jak przy certyfikatach.

</div>

---

# Static token file — token z pliku

<div class="kolumny">
<div>

<div data-marpit-fragment>

```text
# /etc/kubernetes/tokeny.csv
# token,użytkownik,uid,"grupy"
b4rt3k-t0k3n-9f2c1a7e,bartek,1001,"zespol-sklep,deweloperzy"
```

</div>

<div data-marpit-fragment>

```yaml
    - --token-auth-file=/etc/kubernetes/tokeny.csv
    # + plik podmontowany do static Poda
```

</div>

<div data-marpit-fragment>

```bash
kubectl config set-credentials bartek \
  --token=b4rt3k-t0k3n-9f2c1a7e
```

</div>

</div>
<div>

<div data-marpit-fragment>

```text
$ kubectl auth whoami
Username    bartek
UID         1001
Groups      [zespol-sklep deweloperzy
             system:authenticated]
```

</div>

* klient wysyła token w nagłówku `Authorization: Bearer …`
* zły token → **401**; dobry, ale bez RBAC → **403**

</div>
</div>

---

# Dlaczego static token file to tylko laby

<div data-marpit-fragment>

```text
# z pliku usunięto token bartka i dopisano token celiny — bez restartu apiservera
$ kubectl --token=c3l1n4-… auth whoami
error: You must be logged in to the server (Unauthorized)      ← nowy nie działa
$ kubectl --token=b4rt3k-… auth whoami
Username    bartek                                             ← usunięty działa dalej
```

</div>

* plik czytany jest **tylko przy starcie** — każda zmiana to restart apiservera
* tokeny leżą **jawnym tekstem** na każdym node'ie control plane i **nie wygasają**
* wykradzionego tokenu nie unieważnisz inaczej niż edycją pliku i restartem

<div data-marpit-fragment>

> Ta sama słabość co w ABAC: konfiguracja w pliku zamiast w API. Do ludzi —
> certyfikaty z krótką ważnością albo OIDC; do workloadów — tokeny ServiceAccount.

</div>

---

# Tryby autoryzacji

<div data-marpit-fragment>

| Tryb | Jak decyduje | Gdzie są reguły |
|---|---|---|
| `Node` | kubelet widzi tylko swój node i jego Pody | wbudowane |
| `RBAC` | Role i Bindingi | **obiekty w API** |
| `ABAC` | atrybuty użytkownika i zasobu z polityki | **plik na node'ach control plane** |
| `Webhook` | pyta zewnętrzną usługę | poza klastrem |
| `AlwaysAllow` / `AlwaysDeny` | zawsze tak / zawsze nie | tylko do testów |

</div>

<div data-marpit-fragment>

```text
--authorization-mode=Node,RBAC,ABAC
```

</div>

* tryby pytane są **po kolei** — pierwszy, który zezwoli, kończy sprawę
* żądanie, któremu nie zezwolił żaden, dostaje **403**

---

# ABAC — polityka w pliku

<div data-marpit-fragment>

```json
{"apiVersion": "abac.authorization.kubernetes.io/v1beta1", "kind": "Policy",
 "spec": {"user": "anna", "namespace": "sklep", "resource": "configmaps", "readonly": true}}
```

</div>

* jedna linia pliku to jedna reguła; `readonly: true` = `get`, `list`, `watch`
* plik czyta apiserver — trzeba go podać flagą **i** podmontować do static Poda:

<div data-marpit-fragment>

```yaml
    - --authorization-mode=Node,RBAC,ABAC
    - --authorization-policy-file=/etc/kubernetes/abac/polityka.jsonl
    # + volumeMount i volume hostPath dla /etc/kubernetes/abac
```

</div>

<div data-marpit-fragment>

```text
$ kubectl --context anna@lfs458 auth can-i get configmaps       yes
$ kubectl --context anna@lfs458 auth can-i create configmaps    no - abac: No policy matched.
```

</div>

---

# Dlaczego ABAC jest słaby

<div data-marpit-fragment>

```text
$ echo '{… "resource": "secrets", "readonly": true}}' >> /etc/kubernetes/abac/polityka.jsonl
$ kubectl --context anna@lfs458 auth can-i get secrets          # 20 s później
no - abac: No policy matched.                ← plik czytany tylko przy starcie
```

</div>

* każda zmiana reguł to **restart apiservera**
* reguły leżą w pliku **na każdym** node'ie control plane — nie ma ich w API, więc nie zobaczysz ich `kubectl get`, nie masz historii zmian, a pliki łatwo rozjeżdżają się między node'ami
* nie ma ról do ponownego użycia: każda reguła wprost dla użytkownika albo grupy

<div data-marpit-fragment>

> Dlatego w praktyce działa RBAC: reguły są obiektami w API, zmieniasz je
> `kubectl apply` bez restartu, a sprawdzasz `kubectl auth can-i`.

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

**26 punktów + 3 dodatkowe**

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
Potem zmienisz zestaw pluginów admission, a na koniec wpuścisz do klastra
użytkownika z certyfikatem i dasz mu uprawnienia przez RBAC.

</div>

<div data-marpit-fragment>

> Najważniejsze zadanie to czwarte. Nie wystarczy utworzyć obiekt —
> trzeba sprawdzić, że naprawdę działa.

</div>

---

# Co warto zapamiętać — tożsamość i dostęp

* Kubernetes daje mechanizmy, nie politykę — hardening jest Twoją pracą
* **401** = uwierzytelnianie, **403** = autoryzacja
* użytkownicy nie są obiektami; ServiceAccount jest
* użytkownik z certyfikatu: `CN` = nazwa, `O` = grupa; wniosek zatwierdza
  administrator, a certyfikatu nie da się odwołać
* ABAC i static token file trzymają konfigurację w pliku — każda zmiana to restart
  apiservera; dlatego RBAC, certyfikaty, OIDC i tokeny ServiceAccount

---

# Co warto zapamiętać — admission i sieć

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
