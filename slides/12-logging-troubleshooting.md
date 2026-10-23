---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · rozdział 12 · Logging and Troubleshooting'
---

<!-- _class: tytul -->
<!-- _paginate: false -->

# Logging and Troubleshooting

## Rozdział 12 · lab `12`

Metoda zamiast zgadywania

---

# Plan rozdziału

<div data-marpit-fragment>

1. **Przegląd** — dlaczego kolejność ma znaczenie
2. **Ścieżka diagnozy** — cztery kroki, zawsze te same
3. **Sekwencja startu** — co się dzieje, zanim Pod zacznie działać
4. **Monitoring** — metrics-server i co dalej
5. **Pluginy** — `krew`, `kubectl debug`
6. **Logi** — gdzie są i jak do nich dotrzeć
7. **Gdy pada control plane** — diagnoza bez `kubectl`
8. **Lab 12** — naprawiasz siedem zepsutych rzeczy

</div>

---

<!-- _class: sekcja -->

# 1. Metoda

---

# Zawsze w tej samej kolejności

<div data-marpit-fragment>

```text
   1. STAN        kubectl get pods            ← nazwa stanu nazywa problem
   2. ZDARZENIA   kubectl describe pod        ← dlaczego klaster tak zrobił
   3. LOGI        kubectl logs --previous     ← co mówi sama aplikacja
   4. MANIFEST    kubectl get -o yaml         ← dopiero teraz
```

</div>

<div data-marpit-fragment>

> Najczęstszy błąd diagnozy: zaczynanie od kroku 4. Czytasz manifest,
> szukasz literówki — a stan Poda od początku mówił `ImagePullBackOff`.

</div>

<div data-marpit-fragment>

Dwie zasady, które oszczędzają godziny:

</div>

* **nie zgaduj** — każdy z tych czterech kroków daje twardą informację
* **nie przechodź dalej**, póki bieżący krok czegoś nie wyklucza

---

# Stan Poda nazywa problem

<div data-marpit-fragment>

| Stan | Co znaczy | Gdzie szukać |
|---|---|---|
| `Pending` | nikt go nie zaplanował | `describe` → `FailedScheduling` |
| `ContainerCreating` | kubelet pracuje: obraz, wolumeny, sieć | `describe` → Events |
| `ImagePullBackOff` | nie da się pobrać obrazu | nazwa obrazu, tag, rejestr, limity |
| `CrashLoopBackOff` | startuje i pada w kółko | **`logs --previous`** |
| `Error` / `Completed` | proces się zakończył | `logs`, kod wyjścia |
| `Terminating` *(długo)* | finalizer albo `terminationGracePeriod` | `describe`, finalizery |
| `Running`, ale nie działa | aplikacja albo sieć | `logs`, probes, EndpointSlice |

</div>

<div data-marpit-fragment>

```bash
kubectl get pods -o wide
kubectl get events -n <ns> --sort-by=.lastTimestamp | tail -20
```

</div>

---

<!-- _class: sekcja -->

# 3. Sekwencja startu

---

# Co musi się udać, zanim Pod zadziała

<div data-marpit-fragment>

```text
   scheduler przypisuje node
   kubelet pobiera obraz            ← ImagePullBackOff
   kubelet montuje wolumeny         ← FailedMount
   CNI plugin przydziela adres      ← FailedCreatePodSandBox
   start initContainers (po kolei)  ← Init:Error, Init:CrashLoopBackOff
   start kontenerów + startupProbe
   readinessProbe → wpis do EndpointSlice
   livenessProbe pilnuje dalej
```

</div>

<div data-marpit-fragment>

> Znajomość tej kolejności pozwala od razu zawęzić obszar: `FailedMount`
> znaczy, że obraz **już się pobrał**, więc rejestr jest w porządku.

</div>

---

# Cztery klasy awarii, które wrócą w labie

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Obraz nie istnieje

</div>

<div data-marpit-fragment>

```text
ImagePullBackOff
Failed to pull image …: not found
```
→ literówka w tagu, zły rejestr,
limit pobrań

</div>

<div data-marpit-fragment>

### Aplikacja pada przy starcie

</div>

<div data-marpit-fragment>

```text
CrashLoopBackOff
```
→ `kubectl logs --previous`

</div>

</div>
<div>

<div data-marpit-fragment>

### Service bez backendów

</div>

<div data-marpit-fragment>

```text
Endpoints: <none>
```
→ selektor nie pasuje do etykiet

</div>

<div data-marpit-fragment>

### Pod nie do zaplanowania

</div>

<div data-marpit-fragment>

```text
Pending / FailedScheduling
```
→ zasoby, taint, nodeSelector

</div>

</div>
</div>

<div data-marpit-fragment>

> Te cztery pokrywają zdecydowaną większość zgłoszeń. Rozpoznawanie ich
> **po objawie**, bez czytania manifestu, to główna umiejętność z tego rozdziału.

</div>

---

<!-- _class: sekcja -->

# 4. Monitoring i logi

---

# metrics-server to nie monitoring

<div data-marpit-fragment>

```bash
kubectl top nodes
kubectl top pods -n lfs458-m12
kubectl get apiservices | grep metrics        # v1beta1.metrics.k8s.io
```

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

**metrics-server**

</div>

* zbiera z kubeletów
* trzyma **w pamięci**, bez historii
* zasila `kubectl top` i **HPA**
* na Kindzie wymaga
  `--kubelet-insecure-tls`

</div>
<div>

<div data-marpit-fragment>

**Prawdziwy monitoring**

</div>

* Prometheus + Grafana
* historia, alerty, reguły
* `kube-state-metrics` dla stanu obiektów
* logi: Loki, Elastic, OpenSearch

</div>
</div>

<div data-marpit-fragment>

> `kubectl top` odpowiada na pytanie *„co się dzieje teraz”*.
> Na *„co się działo o 3 w nocy”* odpowie tylko system z historią.

</div>

---

# Gdzie naprawdę są logi

<div data-marpit-fragment>

```bash
kubectl logs <pod> -n <ns>                 # bieżąca instancja kontenera
kubectl logs <pod> -c <kontener> -n <ns>   # konkretny kontener
kubectl logs <pod> --previous              # POPRZEDNIA instancja ← kluczowe
kubectl logs -l app=sklep --tail=50 -f     # po etykiecie, na żywo
```

</div>

<div data-marpit-fragment>

| Warstwa | Gdzie |
|---|---|
| aplikacja | stdout/stderr kontenera → `kubectl logs` |
| kubelet | `journalctl -u kubelet` **na node'ie** |
| control plane | `kubectl logs -n kube-system <pod>` (static Pody) |
| zdarzenia klastra | `kubectl get events`, domyślnie znikają po **godzinie** |

</div>

<div data-marpit-fragment>

> Przy `CrashLoopBackOff` zwykłe `kubectl logs` pokaże logi instancji, która
> dopiero startuje — często puste. Potrzebujesz **`--previous`**.

</div>

---

<!-- _class: sekcja -->

# 5. Narzędzia

---

# Co warto mieć pod ręką

<div data-marpit-fragment>

```bash
kubectl debug -it <pod> --image=busybox:1.36 --target=<kontener>
kubectl debug node/lfs458-worker -it --image=busybox:1.36
kubectl run tymczasowy --rm -it --image=busybox:1.36 --restart=Never -- sh
```

</div>

* `kubectl debug` dokłada **kontener efemeryczny** do działającego Poda —
  ratuje przy obrazach distroless, w których nie ma powłoki
* `kubectl debug node/...` daje dostęp do systemu plików node'a

<div data-marpit-fragment>

| Plugin (`krew`) | Do czego |
|---|---|
| `kubectl krew install ns ctx` | szybkie przełączanie namespace'u i kontekstu |
| `stern` | logi z wielu Podów naraz |
| `kubectl tree` | drzewo `ownerReferences` |
| `kubectl neat` | manifest bez pól dopisanych przez serwer |

</div>

---

<!-- _class: sekcja -->

# 6. Gdy pada control plane

---

# Awaria control plane nie zrzuca aplikacji

<div data-marpit-fragment>

To najważniejsza rzecz, którą trzeba wiedzieć, zanim zacznie się panikować.

</div>

<div data-marpit-fragment>

| Pada | Co przestaje działać | Co nadal działa |
|---|---|---|
| **kube-apiserver** | `kubectl`, wszystkie kontrolery, `etcd` bez klienta | **Pody, Service'y, DNS, ruch użytkowników** |
| **kube-scheduler** | planowanie **nowych** Podów | wszystko, co już stoi |
| **controller-manager** | Deploymenty, odtwarzanie replik, GC | istniejące Pody |
| **kubelet** na node'ie | raport stanu i nowe Pody **na tym node'ie** | reszta klastra |
| **kube-proxy** na node'ie | reguły Service'ów na tym node'ie | Pody na nim nadal działają |

</div>

<div data-marpit-fragment>

Kontenery utrzymuje kubelet, a ruch — reguły już wpisane w jądro.
**Masz czas na spokojną diagnozę**, nie minutę do katastrofy.

</div>

---

# Jak diagnozować bez API

<div data-marpit-fragment>

Jeśli `kubectl` nie odpowiada, zostaje Ci powłoka na node'ie.

</div>

<div data-marpit-fragment>

```bash
ssh cp                                   # u nas: docker exec -it lfs458-control-plane bash

crictl ps -a                             # kontenery na tym node'ie — także te padłe
crictl logs <id>                         # dlaczego kontener nie wstaje
crictl pods                              # Pody widziane przez runtime

journalctl -u kubelet -n 50 --no-pager   # co kubelet myśli o całej sytuacji
systemctl status kubelet
```

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

**`crictl` to nie `docker`**

</div>

<div data-marpit-fragment>

Rozmawia z runtime'em przez **CRI**,
więc działa tam, gdzie Dockera nie ma.
Konfiguracja: `/etc/crictl.yaml`.

</div>

</div>
<div>

<div data-marpit-fragment>

**Kolejność bez API**

</div>

<div data-marpit-fragment>

1. czy kubelet żyje → `systemctl`
2. co mówi → `journalctl`
3. co z kontenerami → `crictl ps -a`
4. dlaczego padł → `crictl logs`

</div>

</div>
</div>

---

# Dlaczego static Pody da się naprawić bez API

<div data-marpit-fragment>

```
/etc/kubernetes/manifests/
├── etcd.yaml
├── kube-apiserver.yaml
├── kube-controller-manager.yaml
└── kube-scheduler.yaml
```

</div>

<div data-marpit-fragment>

**Kubelet czyta ten katalog z dysku, nie z API.** Pilnuje go i startuje
kontenery sam, zanim serwer API w ogóle istnieje — inaczej klaster nie
miałby jak się uruchomić po pierwszym włączeniu.

</div>

<div data-marpit-fragment>

Praktyczne konsekwencje:

</div>

* zapisujesz plik → kubelet podnosi poprawioną wersję **w kilkanaście sekund**,
  bez żadnego `kubectl apply`
* **nie ma `kubectl rollout`** i nie ma czego cofnąć — zrób kopię **przed** edycją
* w `kubectl get pods -n kube-system` widzisz tylko **mirror Pody** —
  odbicie do odczytu, którego skasowanie niczego nie zmienia

---

# Trzy objawy, które trzeba rozpoznać natychmiast

<div class="kolumny">
<div>

<div data-marpit-fragment>

### `kubectl` nie łączy się

</div>

<div data-marpit-fragment>

```
Unable to connect to
the server: EOF
```

</div>

<div data-marpit-fragment>

→ apiserver albo etcd.
Wejdź na node, `crictl logs`
ostatniej próby.
Szukaj linii `command failed`.

</div>

</div>
<div>

<div data-marpit-fragment>

### `Pending` **bez zdarzeń**

</div>

<div data-marpit-fragment>

```
Events:  <none>
```

</div>

<div data-marpit-fragment>

→ **nie żyje scheduler.**
Działający scheduler, który nie
umie zaplanować, **zawsze**
zostawia `FailedScheduling`.
Brak komunikatu jest komunikatem.

</div>

</div>
</div>

<div data-marpit-fragment>

### Node `NotReady`

</div>

<div data-marpit-fragment>

→ kubelet na **tym** node'ie. Nie naprawisz go przez API — to node ma
raportować swój stan. Zwykłe przyczyny: pełny dysk, włączony swap,
rozjechany cgroup driver, wygasłe certyfikaty kubeleta.
Po 5 minutach kontroler zacznie eksmitować z niego Pody.

</div>

---

<!-- _class: lab -->

# Lab 12

<div data-marpit-fragment>

**28 punktów + 3 dodatkowe**

</div>

<div data-marpit-fragment>

```bash
labctl lab 12
```

</div>

<div data-marpit-fragment>

Ten lab działa odwrotnie niż pozostałe: **nie budujesz — naprawiasz**.
Zadania 1–4 to awarie workloadów, zadania **7–9 to awarie klastra**:
apiserver, scheduler, kubelet.

</div>

<div data-marpit-fragment>

**Zadanie 7 zabierze Ci `kubectl`** — i o to chodzi. Diagnozujesz z node'a,
przez `crictl` i `journalctl`, dokładnie tak jak na egzaminie.

</div>

<div data-marpit-fragment>

> Klaster psuje się dopiero w momencie, w którym dochodzisz do zadania.
> `labctl cleanup 12` przywraca wszystko do stanu wyjściowego.

</div>

---

# Co warto zapamiętać

* kolejność: **stan → zdarzenia → logi → manifest**; manifest na końcu
* nazwa stanu Poda zwykle sama nazywa problem
* znajomość sekwencji startu zawęża obszar poszukiwań
* `CrashLoopBackOff` → **`kubectl logs --previous`**
* `Endpoints: <none>` → selektor Service'u nie pasuje do etykiet
* `kubectl top` pokazuje teraźniejszość; historii trzeba szukać gdzie indziej
* `kubectl debug` dokłada powłokę tam, gdzie jej nie ma
* **awaria control plane nie zrzuca aplikacji** — masz czas na diagnozę
* bez API zostają `crictl ps -a`, `crictl logs`, `journalctl -u kubelet`
* static Pody czyta **kubelet z dysku** — naprawisz je bez API, ale
  zrób kopię manifestu, bo nie ma czego cofnąć
* `Pending` **bez zdarzeń** = scheduler; `NotReady` = kubelet na node'ie

<script src="nawigacja.js"></script>
