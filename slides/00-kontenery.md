---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · rozdział 0 · Kontenery — skąd się wzięły'
---

<!-- _class: tytul -->
<!-- _paginate: false -->

# Kontenery

## Rozdział 0 · lab `00`

Skąd się wzięły, co dokładnie izolują
i dlaczego potrzebują orkiestratora

---

# Po co ten rozdział

<div data-marpit-fragment>

Kubernetes **uruchamia kontenery** — i zakłada, że wiesz, czym one są.

</div>

<div data-marpit-fragment>

Ten rozdział wyrównuje punkt startu: jeśli pracujesz z kontenerami
od lat, potraktuj go jako powtórkę pojęć, których będziemy używać
przez cztery dni.

</div>

<div data-marpit-fragment>

1. Co było przed kontenerami i jaki problem rozwiązują
2. Czym kontener **nie** jest
3. Z czego naprawdę jest zrobiony
4. Obraz, warstwy, rejestr
5. Standardy: OCI i CRI
6. Dlaczego sam kontener to za mało

</div>

---

<!-- _class: sekcja -->

# 1. Problem, który rozwiązują

---

<!-- fragmenty: ręcznie -->

# Trzy sposoby na uruchomienie aplikacji

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Bare metal

- **jedna** aplikacja na cały serwer
- uruchomienie: **minuty**
- dwie aplikacje potrzebujące różnych
  wersji tej samej biblioteki —
  **drugi serwer**

</div>

<div data-marpit-fragment>

### Maszyna wirtualna

- własne **jądro** i cały system
- uruchomienie: **dziesiątki sekund**
- **kilkanaście** na serwer — każda
  zajmuje gigabajty pamięci

</div>

</div>
<div>

<div data-marpit-fragment>

### Kontener

- **współdzielone jądro** hosta
- uruchomienie: **milisekundy**
- **setki** na tym samym serwerze
- zajmuje tyle, co zwykły proces
- izolacja: namespace'y i cgroups

</div>

</div>
</div>

<div data-marpit-fragment>

> Kontener to **proces na hoście**, któremu jądro pokazuje okrojony widok
> systemu. Nie ma własnego jądra i nie jest maszyną.

</div>

---

# „U mnie działa”

<div data-marpit-fragment>

Problem nie polega na tym, że aplikacja nie chce się uruchomić.
Polega na tym, że **działa gdzie indziej niż u Ciebie**.

</div>

* inna wersja biblioteki systemowej
* inna ścieżka do konfiguracji
* inny zestaw zmiennych środowiskowych
* inna wersja interpretera

<div data-marpit-fragment>

Kontener pakuje aplikację **razem z jej zależnościami** w jeden,
niezmienny artefakt. Ten sam obraz jedzie przez laptopa, CI,
środowisko testowe i produkcję.

</div>

<div data-marpit-fragment>

*To jest cała idea. Reszta to szczegóły implementacji.*

</div>

---

<!-- _class: sekcja -->

# 2. Historia

---

# Czterdzieści lat izolacji

<div data-marpit-fragment>

| Rok | Co się pojawiło | Co wniosło |
|---|---|---|
| 1979 | `chroot` w Uniksie V7 | zmiana widocznego katalogu głównego |
| 2000 | FreeBSD **Jails** | izolacja procesów, sieci i użytkowników |
| 2004 | Solaris **Zones** | kompletne „strefy” z limitami zasobów |
| 2006–07 | **cgroups** (Google) → jądro Linuksa | limity CPU, pamięci, I/O |
| 2008 | **LXC** | namespace'y + cgroups w jednym narzędziu |
| 2013 | **Docker** | obraz, rejestr, `Dockerfile` — *ergonomia* |
| 2014 | **Kubernetes** (Google → CNCF) | orkiestracja wielu hostów |
| 2015 | **OCI** | standard obrazu i runtime'u |

</div>

---

# Czym naprawdę był przełom Dockera

<div data-marpit-fragment>

Technologia istniała od lat — namespace'y i cgroups były w jądrze
**przed** Dockerem. Docker dołożył trzy rzeczy, których brakowało:

</div>

<div data-marpit-fragment>

1. **Format obrazu** — warstwowy, adresowany skrótem, powtarzalny
2. **Rejestr** — jedno miejsce, z którego każdy pobiera to samo
3. **Prosty opis budowania** — `Dockerfile` zamiast skryptów

</div>

<div data-marpit-fragment>

> Dlatego Kubernetes dziś **nie potrzebuje Dockera**, ale potrzebuje
> jego formatu obrazu. Ten format jest teraz standardem OCI.

</div>

---

<!-- _class: sekcja -->

# 3. Z czego jest zrobiony kontener

---

# Dwa mechanizmy jądra i nic więcej

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Namespaces — *co widzisz*

</div>

<div data-marpit-fragment>

| Namespace | Izoluje |
|---|---|
| `pid` | drzewo procesów |
| `net` | interfejsy, porty |
| `mnt` | punkty montowania |
| `uts` | hostname |
| `ipc` | pamięć współdzielona |
| `user` | mapowanie UID |

</div>

</div>
<div>

<div data-marpit-fragment>

### cgroups — *ile możesz*

</div>

* limit **CPU**
* limit **pamięci**
* limit **I/O**
* zliczanie zużycia

<div data-marpit-fragment>

Z tego Kubernetes buduje `requests`
i `limits`, które zobaczysz
w rozdziałach 4 i 11.

</div>

</div>
</div>

<div data-marpit-fragment>

> Trzeci element to **system plików**: `pivot_root` na warstwy obrazu.
> Trzy mechanizmy razem dają coś, co *wygląda* jak osobna maszyna.

</div>

---

# Zobacz to z hosta

<div data-marpit-fragment>

Kontener nie ukrywa się przed systemem — to po prostu proces:

</div>

<div data-marpit-fragment>

```bash
docker run -d --name demo nginx:1.27-alpine

ps -ef | grep nginx            # widać go w procesach hosta
ls -l /proc/$(pgrep -f 'nginx: master')/ns/   # jego namespace'y
cat /sys/fs/cgroup/.../memory.max             # jego limit pamięci
```

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

**Wewnątrz kontenera**

</div>

<div data-marpit-fragment>

```bash
docker exec demo ps -ef
# PID 1 to nginx
```

</div>

</div>
<div>

<div data-marpit-fragment>

**Na hoście**

</div>

<div data-marpit-fragment>

```bash
ps -ef | grep nginx
# PID 48213, zwykły proces
```

</div>

</div>
</div>

<div data-marpit-fragment>

*Ten sam proces, dwa różne widoki — na tym polega namespace `pid`.*

</div>

---

<!-- _class: sekcja -->

# 4. Obraz, warstwy, rejestr

---

# Obraz to nie plik, to stos warstw

<div data-marpit-fragment>

```text
  ┌─────────────────────────────┐  warstwa zapisu (kontener)   ← ulotna
  ├─────────────────────────────┤
  │ COPY app.jar /app/          │  warstwa 3  \
  ├─────────────────────────────┤              |  tylko do odczytu,
  │ RUN apt-get install -y jre  │  warstwa 2   |  współdzielone między
  ├─────────────────────────────┤              |  kontenerami
  │ FROM debian:12              │  warstwa 1  /
  └─────────────────────────────┘
```

</div>

* każda warstwa to **różnica** wobec poprzedniej, adresowana skrótem SHA-256
* dziesięć kontenerów z tego samego obrazu dzieli te same warstwy na dysku
* **warstwa zapisu ginie razem z kontenerem** — stąd biorą się wolumeny,
  którym poświęcimy cały rozdział 8

---

# Obraz vs kontener

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Obraz

</div>

* **niezmienny** szablon
* wersjonowany tagiem i skrótem
* leży w rejestrze
* `nginx:1.27-alpine`

</div>
<div>

<div data-marpit-fragment>

### Kontener

</div>

* **działająca instancja** obrazu
* ma warstwę zapisu i stan
* ma cykl życia
* `docker ps`

</div>
</div>

<div data-marpit-fragment>

> Analogia, która nie myli: obraz jest jak **plik wykonywalny**,
> a kontener jak **uruchomiony proces**. Z jednego pliku możesz
> uruchomić wiele procesów.

</div>

<div data-marpit-fragment>

Dlatego tag `latest` jest pułapką: wskazuje **co innego** w zależności
od tego, kiedy pobierasz. W produkcji przypina się konkretną wersję,
a najlepiej skrót: `nginx@sha256:a1ed56…`

</div>

---

<!-- _class: sekcja -->

# 5. Standardy: OCI i CRI

---

# Dwa standardy, które warto rozróżniać

<div class="kolumny">
<div>

<div data-marpit-fragment>

### OCI
**Open Container Initiative**

</div>

* **image spec** — jak wygląda obraz
* **runtime spec** — jak go uruchomić
* referencyjna implementacja: `runc`

<div data-marpit-fragment>

Dzięki temu obraz zbudowany Dockerem
uruchomi `containerd`, CRI-O i Podman.

</div>

</div>
<div>

<div data-marpit-fragment>

### CRI
**Container Runtime Interface**

</div>

* API, przez które **kubelet** rozmawia
  z runtime'em
* implementują je `containerd` i CRI-O
* Docker go **nie** implementował

</div>
</div>

<div data-marpit-fragment>

> W Kubernetesie 1.24 usunięto `dockershim` — warstwę tłumaczącą CRI na
> API Dockera. Nagłówki krzyczały „Kubernetes porzuca Dockera”, ale
> **obrazy zbudowane Dockerem działają dalej**, bo są zgodne z OCI.
> Zmienił się tylko komponent uruchamiający je na node'ie.

</div>

---

# Co z tego wynika w praktyce

<div data-marpit-fragment>

Na node'ach klastra, który postawimy, zobaczysz `containerd` — nie Dockera:

</div>

<div data-marpit-fragment>

```bash
kubectl get nodes -o wide          # kolumna CONTAINER-RUNTIME
# containerd://2.3.4
```

</div>

* `docker` na stanowisku służy do **budowania** obrazów i uruchamiania Kinda
* na node'ie kontenery uruchamia `containerd` przez CRI
* do debugowania na node'ie używa się `crictl`, nie `docker`

<div data-marpit-fragment>

*Wrócimy do tego w rozdziale 3, zaglądając do środka node'a.*

</div>

---

<!-- _class: sekcja -->

# 6. Dlaczego sam kontener to za mało

---

# Czego kontener nie robi

<div data-marpit-fragment>

Masz obraz i polecenie `docker run`. Działa. Na **jednym** serwerze.

</div>

<div data-marpit-fragment>

| Pytanie | Odpowiedź Dockera |
|---|---|
| Co, gdy proces padnie o 3 w nocy? | `--restart` — jeśli żyje host |
| Co, gdy padnie cały serwer? | nic |
| Jak uruchomić 20 kopii na 5 serwerach? | ręcznie, 20 razy |
| Jak je zaadresować jedną nazwą? | własny load balancer |
| Jak wydać nową wersję bez przestoju? | własny skrypt |
| Jak podać hasła, nie wkładając ich w obraz? | własny mechanizm |

</div>

<div data-marpit-fragment>

> Każde z tych pytań ma w Kubernetesie **wbudowaną odpowiedź**.
> To jest dokładnie ta luka, którą wypełnia orkiestrator.

</div>

---

# Od kontenera do klastra

<div data-marpit-fragment>

```text
   kontener        →      Pod       →   Deployment  →    Service
   proces z              jeden lub      ile kopii,       stabilny adres
   izolacją              więcej         jak wydawać      i równoważenie
                         kontenerów     wersje
```

</div>

* **Pod** to najmniejsza jednostka w Kubernetesie — nie kontener
* kontenery w jednym Podzie dzielą sieć i mogą dzielić dyski
* wszystko wyżej działa w **reconciliation loop**: stan docelowy kontra faktyczny

<div data-marpit-fragment>

*Każde z tych pojęć rozbierzemy osobno — Pod w rozdziale 4,
Deployment w 6, Service w 9.*

</div>

---

<!-- _class: lab -->

# Lab 00

<div data-marpit-fragment>

**12 punktów**

</div>

<div data-marpit-fragment>

```bash
labctl lab 00
```

</div>

<div data-marpit-fragment>

Uruchomisz kontener i zobaczysz **ten sam proces z dwóch stron**,
postawisz mu limit pamięci w cgroupie, zostawisz ślad w warstwie zapisu
i zajrzysz do środka node'a Kinda — gdzie kontenery uruchamia `containerd`.

</div>

---

# Co warto zapamiętać

* kontener to **proces hosta** z okrojonym widokiem, nie maszyna wirtualna
* izolację dają **namespaces** (co widzisz) i **cgroups** (ile możesz)
* obraz jest **niezmienny i warstwowy**; warstwa zapisu ginie z kontenerem
* **OCI** standaryzuje obrazy, **CRI** — sposób rozmowy kubeleta z runtime'em
* usunięcie `dockershim` nie unieważniło obrazów budowanych Dockerem
* kontener rozwiązuje problem **pakowania**, nie problem **skali
  i niezawodności** — od tego jest Kubernetes

<script src="nawigacja.js"></script>
