---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · rozdział 16 · Cluster Maintenance'
---

<!-- _class: tytul -->
<!-- _paginate: false -->

# Cluster Maintenance

## Rozdział 16 · lab `16`

Klaster, który postawiłeś, trzeba utrzymać —
a utrzymanie zaczyna się od podnoszenia wersji

---

# Plan rozdziału

<div data-marpit-fragment>

1. **Cykl wydawniczy** — minor kontra patch, jak długo wersje są wspierane
2. **Version skew** — co z czym może działać i co z tego wynika dla kolejności
3. **Breaking changes** — gdzie ich szukać, zanim zabolą
4. **`kubeadm upgrade`** — przebieg krok po kroku, control plane i worker
5. **Lab 16** — podnosisz klaster o jedną wersję minor

</div>

<div data-marpit-fragment>

> Ten rozdział jest **poza sylabusem LFS458**, ale CKA pyta o upgrade wprost,
> a na produkcji to najczęstsza planowa czynność administratora klastra.
> Kopię zapasową i odtwarzanie etcd omówiliśmy w rozdziale 15.

</div>

---

<!-- _class: sekcja -->

# Cykl wydawniczy i upgrade

---

# Jak Kubernetes wydaje wersje

<div data-marpit-fragment>

Numeracja to **semantic versioning**: `v1.37.4`

</div>

<div data-marpit-fragment>

| Element | Co znaczy | Co może się zmienić |
|---|---|---|
| `1` | major | nic — od 2015 roku stoi na 1 |
| `37` | **minor** | nowe funkcje, deprecations, **usunięcia API** |
| `4` | **patch** | wyłącznie poprawki błędów i bezpieczeństwa |

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

**Minor — trzy razy w roku**

</div>

* co ~15 tygodni
* każdy ma swoje release notes
* *tu* mieszkają breaking changes

</div>
<div>

<div data-marpit-fragment>

**Patch — co miesiąc**

</div>

* bez zmian API i bez nowych flag
* podnosisz **bez czytania** changeloga
* CVE trafiają tu w pierwszej kolejności

</div>
</div>

<div data-marpit-fragment>

> Praktyczna reguła: patche bierzesz rutynowo, minory **planujesz**.

</div>

---

# Które wersje jeszcze dostają poprawki

<div data-marpit-fragment>

Poprawki trafiają **tylko do trzech najnowszych** wersji minor.

</div>

<div data-marpit-fragment>

| Wersja | Stan przy aktualnej `1.37` |
|---|---|
| `1.37` | wspierana — bieżąca |
| `1.36` | wspierana |
| `1.35` | wspierana — **ostatnia** |
| `1.34` i starsze | **end of life** — żadnych patchy, także dla CVE |

</div>

<div data-marpit-fragment>

Okno wsparcia jednej wersji minor to **14 miesięcy**: 12 miesięcy patchy
plus 2 miesiące na dokończenie upgrade'u.

</div>

<div data-marpit-fragment>

**Konsekwencja operacyjna:** skoro w roku wychodzą trzy minory, a wspierane są
trzy — żeby nie wypaść z wsparcia, musisz podnosić klaster
**co najmniej dwa razy w roku**. Upgrade to proces cykliczny, nie jednorazowy
projekt.

</div>

---

# Version skew — co z czym może działać

<div data-marpit-fragment>

Komponenty **nie muszą** mieć jednej wersji, ale rozjazd jest limitowany.
Punktem odniesienia jest zawsze **kube-apiserver**.

</div>

<div data-marpit-fragment>

| Komponent | Dopuszczalny rozjazd względem apiservera |
|---|---|
| **kube-apiserver** (HA) | instancje między sobą: maks. **1 minor** |
| **kubelet** | nigdy nowszy; **do 3 minorów starszy** |
| **kube-proxy** | jak kubelet; na node'ie trzymaj go równo z kubeletem |
| **controller-manager**, **scheduler** | nigdy nowszy; **do 1 minora starszego** |
| **kubectl** | **±1 minor** — może być nowszy |

</div>

<div data-marpit-fragment>

Czyli przy apiserverze `1.37`: kubelet `1.34`–`1.37`,
scheduler `1.36`–`1.37`, kubectl `1.36`–`1.38`.

</div>

<div data-marpit-fragment>

> W klastrze HA ze zróżnicowanymi apiserverami skew kubeleta liczysz
> od **najstarszego** apiservera, nie od najnowszego.

</div>

---

# Dlatego kolejność upgrade'u jest sztywna

<div data-marpit-fragment>

Z tabeli skew wynika jedno: **nic nie może być nowsze od apiservera**.

</div>

<div data-marpit-fragment>

1. **kube-apiserver** — wszystkie instancje
2. **controller-manager**, **scheduler**, cloud-controller-manager
3. **kubelet** na kolejnych node'ach
4. **kube-proxy**

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

**Czego nie wolno**

</div>

* przeskoczyć minora
  (`1.35` → `1.37` — **nie**)
* podnieść kubeleta
  przed apiserverem
* cofnąć wersji — **downgrade
  nie jest wspierany**

</div>
<div>

<div data-marpit-fragment>

**Zanim ruszysz**

</div>

* kopia `etcd` (rozdział 15)
* kopia `/etc/kubernetes/`
* sprawdź, czy masz zapas node'ów
  na `drain`

</div>
</div>

---

# Gdzie szukać breaking changes

<div data-marpit-fragment>

Przed każdym minorem **trzy źródła**, w tej kolejności:

</div>

<div data-marpit-fragment>

1. **`CHANGELOG-1.37.md`** w repo `kubernetes/kubernetes` — sekcja
   **„Urgent Upgrade Notes"**. To jedyna sekcja, której nie wolno pominąć:
   trafiają tam usunięte API, zmienione domyślne wartości i zmiany flag.
2. **Deprecated API Migration Guide** — co i w której wersji znika
3. **Release notes** konkretnej wersji — nowe feature gates i ich domyślny stan

</div>

<div data-marpit-fragment>

Ile czasu dostajesz, zanim coś zniknie:

</div>

<div data-marpit-fragment>

| Dojrzałość API | Minimalny okres po deprecation |
|---|---|
| **GA** (`v1`) | 12 miesięcy **lub** 3 wydania — co dłuższe |
| **beta** (`v1beta1`) | 9 miesięcy **lub** 3 wydania |
| **alpha** | brak gwarancji — może zniknąć w kolejnym minorze |

</div>

---

# Jak sprawdzić, czy *Twój* klaster to przeżyje

<div data-marpit-fragment>

Changelog mówi, co zniknęło. To są narzędzia, które mówią, czy Ciebie to dotyczy.

</div>

<div data-marpit-fragment>

```bash
# 1. czy ktokolwiek wciąż woła przestarzałe API — pytasz sam klaster
kubectl get --raw /metrics | grep apiserver_requested_deprecated_apis

# 2. co dokładnie serwuje to API i w jakich wersjach
kubectl api-resources --api-group=policy
kubectl api-versions
```

</div>

<div data-marpit-fragment>

Zwrócony wiersz metryki ma etykietę `removed_release` — dokładną wersję,
w której dane API przestanie istnieć. **To jest Twoja lista zadań.**

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

**Skan manifestów**

</div>

* `kubent` *(kube-no-trouble)*
* `pluto`

<div data-marpit-fragment>

Czytają też releasy Helma.

</div>

</div>
<div>

<div data-marpit-fragment>

**Audit log**

</div>

<div data-marpit-fragment>

Żądania do przestarzałych API dostają
adnotację `k8s.io/deprecated`.
Pokazuje **kto** woła, nie tylko **co**.

</div>

</div>
</div>

---

# kubeadm upgrade — przebieg

<div data-marpit-fragment>

Najpierw **control plane**, potem po kolei node'y.

</div>

<div data-marpit-fragment>

```bash
# repo APT jest przypięte do wersji minor — bez tej zmiany
# nowy pakiet po prostu nie istnieje
sudo sed -i 's|v1.36|v1.37|' /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update

sudo apt-mark unhold kubeadm && sudo apt-get install -y kubeadm=1.37.0-1.1
sudo apt-mark hold kubeadm

kubeadm upgrade plan                  # co się zmieni i czym to grozi
sudo kubeadm upgrade apply v1.37.0    # static Pody + etcd + ConfigMapy
```

</div>

<div data-marpit-fragment>

`upgrade apply` podmienia manifesty static Podów i odnawia certyfikaty.
**Nie dotyka kubeleta** — ten podnosisz pakietem, osobno.

</div>

---

# kubelet na node'ie — zawsze z drain

<div data-marpit-fragment>

```bash
kubectl drain cp --ignore-daemonsets          # zdejmij workloady
sudo apt-mark unhold kubelet kubectl
sudo apt-get install -y kubelet=1.37.0-1.1 kubectl=1.37.0-1.1
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload && sudo systemctl restart kubelet
kubectl uncordon cp                           # wpuść Pody z powrotem
```

</div>

<div data-marpit-fragment>

Na **worker node** zamiast `upgrade apply` idzie:

</div>

<div data-marpit-fragment>

```bash
sudo kubeadm upgrade node     # tylko konfiguracja kubeleta, bez control plane
```

</div>

<div data-marpit-fragment>

> `apt-mark hold` to nie ozdoba. Bez niego zwykły `apt upgrade` podniesie
> kubeleta ponad apiserver i **rozwali skew** — node wypadnie z klastra.

</div>

---

<!-- _class: lab -->

# Lab 16

<div data-marpit-fragment>

**12 punktów + 2 dodatkowe · maszyny Vagranta**

</div>

<div data-marpit-fragment>

```bash
labctl lab 16
```

</div>

<div data-marpit-fragment>

Podniesiesz klaster z **1.36** do **1.37**: `kubeadm upgrade plan`,
`upgrade apply` na control plane, `drain` → kubelet → `uncordon`,
a na worker node `kubeadm upgrade node`.

</div>

<div data-marpit-fragment>

Po drodze zobaczysz **version skew na żywo**: moment, w którym apiserver
ma już 1.37, a kubelet jeszcze 1.36 — i klaster działa, bo tak wolno.

</div>

<div data-marpit-fragment>

> Maszyny stawia `labctl` sam. Jeśli te z laba 02 już nie żyją, postawi nowe —
> to kilkanaście minut, więc warto zacząć od `labctl lab 16` i zrobić kawę.

</div>

---

<!-- _class: lab -->

# Na koniec: capstone

<div data-marpit-fragment>

**28 punktów + 4 dodatkowe · klaster `kind-basic`**

</div>

<div data-marpit-fragment>

```bash
labctl lab 99
```

</div>

<div data-marpit-fragment>

Zadanie zamykające szkolenie: jedna usługa, wdrożona od zera tak, jak
na produkcji — limity namespace'u, konfiguracja i Secret poza obrazem,
utwardzone kontenery, rozproszenie replik, Ingress, NetworkPolicy,
PodDisruptionBudget i wydanie bez przestoju.

</div>

<div data-marpit-fragment>

> Dostajesz **wymagania, nie instrukcje**, a podpowiedzi są skąpsze niż
> zwykle. Tak wygląda zadanie na egzaminie — i w pracy.

</div>

---

# Co warto zapamiętać

* poprawki dostają **trzy najnowsze minory** — upgrade minimum dwa razy w roku
* **nic nie może być nowsze od apiservera**; kubelet do 3 minorów starszy
* **jeden minor na raz**, bez przeskoków i bez downgrade'u
* breaking changes mieszkają w **„Urgent Upgrade Notes"** changeloga;
  czy dotyczą Ciebie, powie metryka `apiserver_requested_deprecated_apis`
* `kubeadm upgrade apply` na control plane, `kubeadm upgrade node` na workerze —
  **kubeleta nie rusza żadne z nich**
* `apt-mark hold` broni klaster przed przypadkowym złamaniem version skew

<script src="nawigacja.js"></script>
