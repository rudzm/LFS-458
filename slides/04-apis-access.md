---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · rozdział 4 · APIs and Access'
---

<!-- _class: tytul -->
<!-- _paginate: false -->

# APIs and Access

## Rozdział 4 · lab `04`

Jak wygląda rozmowa z klastrem, gdy odłożysz `kubectl`

---

# Plan rozdziału

<div data-marpit-fragment>

1. **Dostęp do API** — ścieżki, grupy, wersje
2. **Adnotacje** — i czym różnią się od etykiet
3. **Prosty Pod** — anatomia manifestu, kilka kontenerów i ich wzorce
4. **kubectl a API** — co naprawdę leci po sieci
5. **Swagger i OpenAPI** — klaster dokumentuje sam siebie
6. **Lab 04** — rozmawiasz z API bez `kubectl`

</div>

---

<!-- _class: sekcja -->

# 1. Dostęp do API

---

# Dwie ścieżki, które trzeba rozróżniać

<div data-marpit-fragment>

| Ścieżka | Co tam jest | Przykład |
|---|---|---|
| `/api/v1` | **grupa core** | Pod, Service, ConfigMap, Node |
| `/apis/<grupa>/<wersja>` | wszystkie pozostałe grupy | `/apis/apps/v1`, `/apis/batch/v1` |

</div>

<div data-marpit-fragment>

```bash
kubectl get --raw /api/v1/namespaces/default/pods | jq '.kind'
# PodList
```

</div>

* grupa core powstała **przed** podziałem na grupy — stąd wyjątek
* w manifeście: `apiVersion: v1` (core) kontra `apiVersion: apps/v1`
* w regule RBAC core rdzeniowa to **pusty łańcuch** `""`, a nie `v1`

<div data-marpit-fragment>

> Ta ostatnia różnica odpowiada za sporą część niedziałających reguł RBAC.
> Wrócimy do niej w rozdziale 5.

</div>

---

# Wersje mówią o stabilności

<div data-marpit-fragment>

| Wersja | Co oznacza | Czy używać na produkcji |
|---|---|---|
| `v1alpha1` | może zniknąć bez ostrzeżenia, domyślnie wyłączone | nie |
| `v1beta1` | API może się zmienić, dane przetrwają | ostrożnie |
| `v1` | stabilne, gwarancja wstecznej zgodności | tak |

</div>

<div data-marpit-fragment>

```bash
kubectl api-resources                 # co klaster umie
kubectl api-versions                  # jakie grupy i wersje są włączone
kubectl explain deployment.spec.strategy   # dokumentacja pola
```

</div>

<div data-marpit-fragment>

Ten sam obiekt bywa dostępny w kilku wersjach jednocześnie — apiserver
konwertuje go w locie, a w `etcd` trzyma w **jednej** wersji
(`storage: true` w CRD z rozdziału 13).

</div>

---

<!-- _class: sekcja -->

# 2. Adnotacje

---

# Etykieta kontra adnotacja

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Labels

</div>

* służą do **wybierania** obiektów
* selektory działają tylko na nich
* wartość: **maks. 63 znaki**
* dozwolony ograniczony zestaw znaków

<div data-marpit-fragment>

```bash
kubectl get pods -l app=sklep
```

</div>

</div>
<div>

<div data-marpit-fragment>

### Annotations

</div>

* służą do **przechowywania** informacji
* selektory ich **nie widzą**
* wartość: praktycznie dowolna długość
* dowolne znaki

<div data-marpit-fragment>

```bash
kubectl annotate pod x \
  opis='dowolny długi tekst…'
```

</div>

</div>
</div>

<div data-marpit-fragment>

> **W skrócie:** jeśli po tym **wybierasz** — etykieta. Jeśli to informacja
> dla człowieka albo narzędzia — adnotacja.

</div>

<div data-marpit-fragment>

Adnotacje w praktyce: `kubernetes.io/change-cause` (historia wydań),
konfiguracja kontrolera Ingress, `last-applied-configuration` po `kubectl apply`.

</div>

---

<!-- _class: sekcja -->

# 3. Prosty Pod — i nie tylko prosty

---

# Anatomia manifestu

<div data-marpit-fragment>

```yaml
apiVersion: v1                 # grupa i wersja
kind: Pod                      # rodzaj obiektu
metadata:                      # kim jest
  name: prosty
  namespace: lfs458-m04
  labels: {app: lab04}
spec:                          # jak MA być  ← piszesz to Ty
  containers:
    - name: nginx
      image: nginx:1.27-alpine
      ports: [{name: http, containerPort: 80}]
      resources:
        requests: {cpu: 50m, memory: 64Mi}
        limits:   {memory: 128Mi}
status:                        # jak JEST   ← wypełnia klaster
  phase: Running
```

</div>

<div data-marpit-fragment>

Te cztery pola ma **każdy** obiekt: `spec` to desired state,
`status` — actual state.

</div>

---

# Kilka kontenerów, jeden Pod

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Dzielą

</div>

* adres IP i `localhost` *(rozdział 3)*
* porty — **nie mogą się dublować**
* wolumeny, które zamontują
* node i czas życia Poda

</div>
<div>

<div data-marpit-fragment>

### Nie dzielą

</div>

* systemu plików obrazu
* `resources` — limity są **per kontener**
* restartów — kubelet restartuje
  pojedynczy kontener, nie Pod
* procesów — chyba że
  `shareProcessNamespace: true`

</div>
</div>

<div data-marpit-fragment>

> **Jeden Pod to jedna aplikacja.** Drugi kontener dokładasz tylko wtedy,
> gdy **pomaga** pierwszemu i bez niego nie ma sensu. Aplikacja i baza
> w jednym Podzie to błąd: skalują się, aktualizują i padają razem.

</div>

---

# Trzy klasyczne wzorce

<div data-marpit-fragment>

| Wzorzec | Co robi | Przykład |
|---|---|---|
| **Sidecar** | rozszerza aplikację, nie zmieniając jej kodu | wysyłka logów, przeładowanie konfiguracji, odnawianie certyfikatów |
| **Ambassador** *(proxy)* | pośredniczy w ruchu **wychodzącym** — aplikacja mówi do `localhost`, poświadczenia ma **tylko proxy** | Cloud SQL Auth Proxy, klient shardowanego Redisa |
| **Adapter** | tłumaczy **wyjście** aplikacji na format, którego oczekuje świat | exporter Prometheusa obok nginx-a albo bazy |

</div>

<div data-marpit-fragment>

```text
 ambassador   app ─(bez hasła)─► localhost:5432 ─► [proxy + klucz] ─TLS─► baza
 adapter      Prometheus ──► [exporter] ──► localhost ──► app (format własny)
```

</div>

<div data-marpit-fragment>

> Secret montujesz **tylko w kontenerze proxy** — `volumeMounts` są per kontener,
> więc aplikacja klucza nie widzi. Ambassador i adapter to odmiany sidecara.
> **Proxy service mesh** *(rozdział 10)* robi jedno i drugie naraz:
> przejmuje cały ruch Poda, wchodzący i wychodzący.

</div>

---

# Init containers — zanim wystartuje aplikacja

<div data-marpit-fragment>

```yaml
spec:
  initContainers:                  # po kolei, każdy musi zakończyć się kodem 0
    - name: czekaj-na-baze
      image: busybox:1.36
      command: ["sh", "-c", "until nc -z baza 5432; do sleep 2; done"]
    - name: przygotuj
      image: busybox:1.36
      command: ["sh", "-c", "echo gotowe > /www/index.html"]
      volumeMounts: [{name: www, mountPath: /www}]
  containers:
    - {name: web, image: nginx:1.27-alpine,
       volumeMounts: [{name: www, mountPath: /usr/share/nginx/html}]}
  volumes: [{name: www, emptyDir: {}}]     # rozdział 8
```

</div>

<div data-marpit-fragment>

```text
web   0/1   Init:0/2          0   1s     ← czeka na bazę
web   0/1   Init:1/2          0   15s    ← baza nasłuchuje, przygotowuje pliki
web   1/1   Running           0   16s
```

</div>

---

# Na co są init containers

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Typowe zadania

</div>

* czekanie na zależność
* migracja schematu bazy
* pobranie konfiguracji albo
  danych do `emptyDir`
* `chown` katalogu, zanim wejdzie
  aplikacja bez roota

</div>
<div>

<div data-marpit-fragment>

### Zasady

</div>

* startują **po kolei**, następny
  dopiero po sukcesie poprzedniego
* błąd → restart według
  `restartPolicy` Poda
* bez `livenessProbe`
  i `readinessProbe`
* mogą mieć **inny obraz** —
  narzędzia nie trafiają do aplikacji

</div>
</div>

<div data-marpit-fragment>

> Czekaj na **port**, nie na nazwę. `nslookup baza` sprawdzi tylko, że
> istnieje Service, a nie że baza przyjmuje połączenia. Utknięty init
> container to status `Init:0/2` albo `Init:CrashLoopBackOff` *(rozdział 12)*.

</div>

---

# Sidecar jako zwykły kontener — trzy kłopoty

<div data-marpit-fragment>

Kontenery z listy `containers` startują **razem** i nic nie wie,
który z nich jest pomocnikiem:

</div>

<div data-marpit-fragment>

1. **brak kolejności** — aplikacja wstaje przed proxy i pierwsze
   połączenia padają
2. **Job się nie kończy** — praca skończona, ale sidecar działa dalej
3. **zła kolejność przy zamykaniu** — proxy znika, zanim aplikacja
   dokończy żądania

</div>

<div data-marpit-fragment>

```bash
kubectl get pods
# NAME                   READY   STATUS     RESTARTS   AGE
# raport-stary-mjjbr     1/2     NotReady   0          25m   ← i tak już zostanie
```

</div>

<div data-marpit-fragment>

> Job to obiekt, który uruchamia Pod **do zakończenia** — omawiamy go
> w rozdziale 5. Tu wystarczy, że czeka, aż **wszystkie** kontenery skończą.

</div>

---

# Natywny sidecar — `restartPolicy: Always`

<div data-marpit-fragment>

```yaml
spec:
  initContainers:
    - name: logi-na-stdout
      image: busybox:1.36
      restartPolicy: Always          # ← to jedno pole robi z niego sidecara
      command: ["sh", "-c", "tail -F /logi/app.log"]
      volumeMounts: [{name: logi, mountPath: /logi}]
  containers:
    - name: app                      # stara aplikacja, pisze tylko do pliku
      image: busybox:1.36
      command: ["sh", "-c", "while true; do date >> /logi/app.log; sleep 5; done"]
      volumeMounts: [{name: logi, mountPath: /logi}]
```

</div>

<div data-marpit-fragment>

* startuje **przed** aplikacją, kończy się **po** niej — nie blokuje Joba
* może mieć probes, liczy się w kolumnie READY (`2/2`); stabilne od **1.33**

</div>

<div data-marpit-fragment>

> Sidecar musi obsłużyć SIGTERM — inaczej Job czeka 30 s, aż zostanie zabity.

</div>

---

# Który kontener? `-c` i adnotacja

<div data-marpit-fragment>

```bash
kubectl logs web
# Defaulted container "web" out of: web, czekaj-na-baze (init), przygotuj (init)

kubectl logs z-sidecarem -c logi-na-stdout       # konkretny kontener
kubectl logs z-sidecarem --all-containers        # wszystkie naraz
kubectl exec -it z-sidecarem -c app -- sh
```

</div>

<div data-marpit-fragment>

Bez `-c` kubectl bierze **pierwszy** kontener z `containers` — chyba że
Pod wskaże inny **adnotacją**:

</div>

<div data-marpit-fragment>

```yaml
metadata:
  annotations:
    kubectl.kubernetes.io/default-container: app
```

</div>

<div data-marpit-fragment>

> Wzorcowa adnotacja z sekcji 2: selektor jej nie widzi, Kubernetes jej
> nie czyta — to wskazówka dla **narzędzia**.

</div>

---

<!-- _class: sekcja -->

# 4. kubectl a API

---

# Zobacz, co naprawdę leci po sieci

<div data-marpit-fragment>

```bash
kubectl get pods -v=6 2>&1 | grep round_trippers
# round_trippers.go:632] "Response" verb="GET"
#   url="https://192.168.56.10:6443/api/v1/namespaces/default/pods?limit=500"
```

</div>

<div data-marpit-fragment>

| Poziom | Co pokazuje |
|---|---|
| `-v=6` | adres żądania i status |
| `-v=7` | osobno żądanie i odpowiedź, z czasem |
| `-v=8` | nagłówki + `body` obcięte do **1 KiB** |
| `-v=9` | gotowe polecenie `curl` + `body` do **10 KiB** |
| `-v=10` | `body` w całości, bez limitu |

</div>

<div data-marpit-fragment>

> `-v=9` wypisuje **gotowe `curl`** do odtworzenia żądania — najszybszy sposób,
> żeby to samo zapytanie powtórzyć poza `kubectl`.

</div>

---

# Trzy sposoby na to samo zapytanie

<div data-marpit-fragment>

```bash
kubectl get pods -n lfs458-m04                         # normalnie

kubectl get --raw /api/v1/namespaces/lfs458-m04/pods   # bez warstwy klienta

kubectl proxy --port=8001 &                            # i potem zwykłym curlem
curl -s localhost:8001/api/v1/namespaces/lfs458-m04/pods | jq '.kind'
```

</div>

<div data-marpit-fragment>

Każdy z nich kończy się tym samym żądaniem HTTP do apiservera. Różnią się
tylko tym, **ile warstw klienta** stoi po drodze — i dlatego `--raw`
oraz `proxy` są nieocenione, gdy podejrzewasz, że to `kubectl` coś zmienia.

</div>

---

# Skąd kubectl wie, gdzie dzwonić

<div data-marpit-fragment>

```bash
kubectl config view --minify          # bieżący kontekst
kubectl config get-contexts
kubectl config use-context kind-lfs458
```

</div>

<div data-marpit-fragment>

Kubeconfig to trzy listy i wskaźnik:

</div>

<div data-marpit-fragment>

| Sekcja | Co opisuje |
|---|---|
| `clusters` | adres apiservera i jego CA |
| `users` | poświadczenia: certyfikat, token, exec plugin |
| `contexts` | para *klaster + użytkownik* (+ domyślny namespace) |
| `current-context` | której pary używać teraz |

</div>

<div data-marpit-fragment>

> Zmienna `KUBECONFIG` przyjmuje **listę plików** rozdzieloną dwukropkami —
> tak scala się dostęp do kilku klastrów w jednym `kubectl`.

</div>

---

<!-- _class: sekcja -->

# 5. Swagger i OpenAPI

---

# Klaster dokumentuje sam siebie

<div data-marpit-fragment>

```bash
kubectl get --raw /openapi/v2 | jq '.info.version'
kubectl get --raw /openapi/v3 | jq 'keys[]' | head
```

</div>

<div data-marpit-fragment>

Z tego samego opisu korzystają:

</div>

* `kubectl explain` — dokumentacja pól prosto z klastra
* walidacja po stronie klienta i serwera (`--dry-run=server`)
* generatory klientów dla Go, Pythona, Javy
* podpowiedzi pól w edytorach

<div data-marpit-fragment>

```bash
kubectl explain pod.spec.containers.resources
kubectl explain pod.spec.restartPolicy       # na końcu: wartość domyślna
```

</div>

<div data-marpit-fragment>

> Dzięki temu dokumentacja **nigdy się nie rozjeżdża** z wersją klastra:
> opisuje dokładnie to API, z którym właśnie rozmawiasz — razem z CRD-ami.

</div>

---

<!-- _class: lab -->

# Lab 04

<div data-marpit-fragment>

**12 punktów + 3 dodatkowe**

</div>

<div data-marpit-fragment>

```bash
labctl lab 04
```

</div>

<div data-marpit-fragment>

Napiszesz manifest Poda od zera (bez `kubectl run`), dołożysz adnotacje
i przekonasz się, że selektor ich nie widzi, odpytasz API `curl`-em
przez `kubectl proxy`, a na koniec **utworzysz Pod, wysyłając JSON**
metodą POST — bez `apply` i bez `create -f`.

</div>

---

# Co warto zapamiętać

* grupa core to `/api/v1`; reszta to `/apis/<grupa>/<wersja>`
* w RBAC grupa core zapisuje się jako `""`, nie `v1`
* **etykieta** = wybieranie, **adnotacja** = przechowywanie; 63 znaki to limit etykiety
* `spec` to desired state, `status` to actual state — i tak jest w każdym obiekcie
* kontenery Poda dzielą adres i wolumeny, **nie** dzielą limitów ani restartów
* sidecar rozszerza, ambassador pośredniczy w ruchu wychodzącym, adapter tłumaczy wyjście
* `initContainers` startują po kolei i muszą się **zakończyć**; z `restartPolicy: Always`
  stają się natywnym sidecarem
* `kubectl -v=8` pokazuje prawdziwe żądania HTTP
* `kubectl explain` czyta OpenAPI **z Twojego klastra**, więc nie kłamie

<script src="nawigacja.js"></script>
