---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · rozdział 15 · High Availability'
---

<!-- _class: tytul -->
<!-- _paginate: false -->

# High Availability

## Rozdział 15 · lab `15`

Ile awarii przeżyje Twój klaster —
i co zrobić, zanim się o tym przekonasz

---

# Plan rozdziału

<div data-marpit-fragment>

1. **Przegląd** — co właściwie ma być dostępne
2. **Kworum** — matematyka, która decyduje o liczbie node'ów
3. **Stacked etcd** — etcd na control plane node'ach
4. **External etcd** — etcd osobno
5. **Kopia zapasowa** — i czego nie obejmuje
6. **Odtwarzanie** — co naprawdę robi `snapshot restore`
7. **Lab 15** — kworum i migawka etcd

</div>

---

<!-- _class: sekcja -->

# 1. Co ma być dostępne

---

# Dwie bardzo różne awarie

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Pada **worker node**

</div>

* Pody są odtwarzane gdzie indziej
* aplikacja przeżywa
* **to działa na jednym control plane**

</div>
<div>

<div data-marpit-fragment>

### Pada **control plane**

</div>

* działające Pody **działają dalej**
* ale: nic nowego nie powstanie,
  nic się nie odtworzy, `kubectl`
  nie odpowiada

</div>
</div>

<div data-marpit-fragment>

> Klaster bez control plane nie umiera natychmiast — zamarza.
> Kontenery chodzą, kubelety pracują, ale klaster przestaje reagować
> na cokolwiek: awarię, skalowanie, wydanie.

</div>

<div data-marpit-fragment>

HA control plane oznacza dwie rzeczy naraz:

</div>

<div data-marpit-fragment>

1. **wiele instancji** apiservera za load balancerem
2. **kworum etcd**, które przetrwa utratę instancji

</div>

---

<!-- _class: sekcja -->

# 2. Kworum

---

# Dlaczego zawsze nieparzyście

<div data-marpit-fragment>

Kworum to `n/2 + 1` — tyle instancji musi się zgodzić, żeby **zapisać**.

</div>

<div data-marpit-fragment>

| Instancji | Kworum | Przeżyje awarii | Komentarz |
|---|---|---|---|
| 1 | 1 | **0** | brak HA |
| 2 | 2 | **0** | gorzej niż 1 — dwa razy więcej okazji do awarii |
| **3** | 2 | **1** | typowy wybór |
| 4 | 3 | 1 | koszt czwartego node'a, zero zysku |
| **5** | 3 | **2** | duże klastry |

</div>

<div data-marpit-fragment>

> Dwa node'y to **gorsze** rozwiązanie niż jeden: kworum wynosi 2,
> więc awaria dowolnego z nich zatrzymuje zapisy. Przy jednym node'ie
> ryzyko awarii jest o połowę mniejsze.

</div>

---

# Co się dzieje po utracie kworum

<div data-marpit-fragment>

Po utracie kworum etcd przechodzi w tryb **tylko do odczytu** — chroni
spójność danych kosztem dostępności.

</div>

<div data-marpit-fragment>

To świadomy wybór: gdy sieć się rozerwie, system rozproszony może albo
odpowiadać **zawsze** (ryzykując nieaktualne dane), albo odpowiadać
**poprawnie** (odmawiając, gdy nie ma pewności). **etcd wybiera to drugie** —
w nomenklaturze twierdzenia CAP jest systemem **CP**.

</div>

<div data-marpit-fragment>

> Dla Ciebie znaczy to jedno: klaster przestaje przyjmować **zmiany**,
> ale **nie przestaje działać**. Istniejące Pody pracują dalej, bo do pracy
> nie potrzebują API. Masz czas, żeby spokojnie przywrócić kworum.

</div>

---

<!-- _class: sekcja -->

# 3 i 4. Gdzie postawić etcd

---

# Stacked kontra external

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Stacked

</div>

<div data-marpit-fragment>

```text
  ┌──────────────────┐
  │ cp1: apiserver   │
  │      + etcd      │
  ├──────────────────┤
  │ cp2: apiserver   │
  │      + etcd      │
  └──────────────────┘
```

</div>

* mniej maszyn, prostsze
* `kubeadm` robi to domyślnie
* **awaria node'a = utrata obu ról**

</div>
<div>

<div data-marpit-fragment>

### External

</div>

<div data-marpit-fragment>

```text
  ┌─────────┐   ┌──────────┐
  │ cp1,2,3 │──►│ etcd ×3  │
  └─────────┘   └──────────┘
```

</div>

* etcd skaluje się niezależnie
* awaria control plane nie dotyka bazy
* **dwa razy więcej maszyn**
  i osobne PKI

</div>
</div>

<div data-marpit-fragment>

> `kubeadm init --upload-certs` plus `kubeadm join --control-plane` buduje
> wariant stacked. Przed apiserverami zawsze stoi **load balancer** — jego
> adres trafia do `controlPlaneEndpoint` i to on ląduje w kubeconfigach.

</div>

---

<!-- _class: sekcja -->

# 5. Kopia zapasowa

---

# Cały stan klastra to jedna baza

<div data-marpit-fragment>

```bash
POD=$(kubectl -n kube-system get pod -l component=etcd \
  -o jsonpath='{.items[0].metadata.name}')

kubectl -n kube-system exec "$POD" -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /tmp/etcd-backup.db
```

</div>

<div data-marpit-fragment>

> Obraz etcd jest distroless — nie ma w nim powłoki, zostają same binarki etcd.

</div>

---

# Migawka to za mało — trzeba ją sprawdzić

<div data-marpit-fragment>

```bash
kubectl -n kube-system exec "$POD" -- \
  etcdutl snapshot status /tmp/etcd-backup.db -w table
```

</div>

<div data-marpit-fragment>

| Narzędzie | Do czego |
|---|---|
| `etcdctl` | rozmowa z **działającym** etcd: `member list`, `snapshot save` |
| `etcdutl` | praca na **pliku** migawki: `status`, `restore` |

</div>

<div data-marpit-fragment>

> Kopia, której nikt nigdy nie odtworzył, jest hipotezą, nie kopią.
> `snapshot status` to minimum: pokazuje liczbę kluczy i sumę kontrolną.

</div>

---

# Czego kopia etcd NIE obejmuje

<div data-marpit-fragment>

| Jest w migawce | Nie ma w migawce |
|---|---|
| wszystkie obiekty API | **dane z PersistentVolume** |
| Deploymenty, Service'y, ConfigMapy | obrazy kontenerów |
| Secrety *(otwartym tekstem!)* | certyfikaty z `/etc/kubernetes/pki` |
| RBAC, CRD i obiekty własne | stan aplikacji poza klastrem |

</div>

<div data-marpit-fragment>

> To jest najważniejsza rzecz z tego rozdziału. Migawka etcd przywróci
> **opis** aplikacji — nie jej dane. Do danych służy Velero albo migawki
> macierzy.

</div>

<div data-marpit-fragment>

Pełny plan odtworzenia wymaga trzech rzeczy: migawki etcd,
kopii `/etc/kubernetes/pki` (inaczej stare certyfikaty nie pasują)
oraz kopii danych z wolumenów.

</div>

---

# Odtwarzanie nie jest wgraniem pliku

<div data-marpit-fragment>

Najczęstsze nieporozumienie: `restore` **nie wrzuca** migawki do działającego
etcd. Buduje z niej **nowy katalog danych**, na który trzeba etcd przestawić.

</div>

<div data-marpit-fragment>

```bash
etcdutl snapshot restore /var/backups/etcd-2026-10-21.db \
  --data-dir=/var/lib/etcd-odtworzone
```

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

**`etcdctl` kontra `etcdutl`**

</div>

<div data-marpit-fragment>

| | |
|---|---|
| `etcdctl` | rozmawia z **żywym** etcd |
| `etcdutl` | pracuje na **pliku** |

</div>

<div data-marpit-fragment>

`snapshot restore` należy do
`etcdutl` — etcd w tym momencie
ma nie działać.

</div>

</div>
<div>

<div data-marpit-fragment>

**`--data-dir` musi nie istnieć**

</div>

<div data-marpit-fragment>

`etcdutl` odmówi nadpisania — i dobrze:
inaczej jednym poleceniem kasowałbyś
oryginał, do którego możesz chcieć
wrócić, gdy odtwarzanie pójdzie źle.

</div>

</div>
</div>

---

# Przebieg na node'ie control plane

<div data-marpit-fragment>

```bash
# 1. zatrzymaj control plane — wystarczy wynieść manifesty static Podów
mkdir -p /tmp/wylaczone
mv /etc/kubernetes/manifests/*.yaml /tmp/wylaczone/

# 2. odtwórz migawkę do nowego katalogu
etcdutl snapshot restore /var/backups/etcd.db --data-dir=/var/lib/etcd-odtworzone

# 3. przestaw etcd na ten katalog
#    w /tmp/wylaczone/etcd.yaml: hostPath /var/lib/etcd → /var/lib/etcd-odtworzone

# 4. wróć manifestami — kubelet podniesie control plane z nowych danych
mv /tmp/wylaczone/*.yaml /etc/kubernetes/manifests/
```

</div>

<div data-marpit-fragment>

Przez kilkadziesiąt sekund `kubectl` milczy — **diagnozuj `crictl`-em**.

</div>

<div data-marpit-fragment>

> Klaster cofnął się do chwili migawki. Obiekty utworzone po niej zniknęły,
> usunięte — wróciły. To nie jest efekt uboczny, to definicja odtwarzania.

</div>

---

# W klastrze HA to nie jest to samo

<div data-marpit-fragment>

Przy **stacked etcd na trzech node'ach** nie wystarczy odtworzyć jednego:
pozostałe dwa mają stare dane i nowy member ich nie przekona.

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

**Dwie drogi**

</div>

<div data-marpit-fragment>

1. odtworzyć **wszystkie** instancje
   z tej samej migawki, każdą
   z własnym `--name` i wspólnym
   `--initial-cluster`
2. odtworzyć **jedną**, a pozostałe
   dołączyć od zera jak nowe node'y

</div>

</div>
<div>

<div data-marpit-fragment>

**Czego nie robić**

</div>

<div data-marpit-fragment>

Odtworzyć trzech instancji osobno,
bez uzgodnionego `--initial-cluster`.
Powstaną **trzy osobne klastry**,
które nie utworzą kworum — i to
jest najczęstszy błąd przy pierwszym
podejściu do odtwarzania HA.

</div>

</div>
</div>

<div data-marpit-fragment>

> Kopia, której nigdy nie odtworzyłeś, jest hipotezą. Próba odtworzenia to
> jedyny sposób, żeby sprawdzić, czy backup w ogóle działa — i czy umiesz
> go użyć pod presją.

</div>

---

# Po co PodDisruptionBudget

<div data-marpit-fragment>

Serwisujesz node'a, więc robisz `kubectl drain`. Bez żadnej ochrony klaster
zabierze z niego **wszystkie** Pody naraz. Stały tam dwie z trzech replik?
Zostaje jedna. Stały wszystkie trzy? Zostaje zero — i aplikacja znika.

</div>

<div data-marpit-fragment>

Nikt nie popełnił błędu: `drain` zrobił dokładnie to, o co go poproszono.
Brakowało informacji, **ile wolno zabrać**.

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

### PDB to umowa z klastrem

</div>

<div data-marpit-fragment>

*„Rób swoje planowe prace, ale
nie schodź poniżej tego poziomu
dostępności."*

</div>

<div data-marpit-fragment>

Deklarujesz ją **raz**, osobnym
obiektem, obok Deploymentu.

</div>

</div>
<div>

<div data-marpit-fragment>

### Kto o nią pyta

</div>

* `kubectl drain` przy serwisowaniu
* `kubeadm upgrade` node'ów (lab 16)
* autoscaler zdejmujący node'a

<div data-marpit-fragment>

Wszystko, co **planowo** rusza Pody.

</div>

</div>
</div>

---

# PDB w praktyce

<div data-marpit-fragment>

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: wazna-pdb, namespace: lfs458-m15}
spec:
  minAvailable: 2
  selector:
    matchLabels: {app: wazna-usluga}
```

</div>

<div data-marpit-fragment>

**`minAvailable: 2`** znaczy: w każdej chwili co najmniej dwa Pody pasujące
do selektora mają być gotowe. Przy trzech replikach **jedna może odejść**.

</div>

<div data-marpit-fragment>

```bash
kubectl get pdb -n lfs458-m15
# NAME       MIN AVAILABLE   MAX UNAVAILABLE   ALLOWED DISRUPTIONS
# wazna-pdb  2               N/A               1
```

</div>

<div data-marpit-fragment>

> Kolumna **ALLOWED DISRUPTIONS** mówi wprost, ile Podów wolno zabrać
> **w tej chwili**. Zero znaczy: `drain` się zatrzyma.

</div>

---

# Co naprawdę robi `drain`

<div data-marpit-fragment>

`kubectl drain` **nie kasuje** Podów — woła **Eviction API**, a ono sprawdza
budżet przed każdą zgodą.

</div>

<div data-marpit-fragment>

```bash
kubectl drain lfs458-worker --ignore-daemonsets
# evicting pod lfs458-m15/wazna-usluga-7d4b8-x9k2p
# error when evicting pod ... (will retry after 5s):
#   Cannot evict pod as it would violate the pod's disruption budget.
```

</div>

<div data-marpit-fragment>

Odpowiedź API to **429 Too Many Requests**. `drain` nie poddaje się —
ponawia próbę co pięć sekund i czeka, aż kontroler odtworzy replikę gdzie
indziej i budżet znów na to pozwoli.

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Pułapka

</div>

<div data-marpit-fragment>

`minAvailable` **równe** liczbie replik
daje `ALLOWED DISRUPTIONS 0`.
`drain` będzie ponawiał w nieskończoność,
a Ty zobaczysz „wiszący" węzeł.

</div>

</div>
<div>

<div data-marpit-fragment>

### Druga forma zapisu

</div>

<div data-marpit-fragment>

`maxUnavailable: 1` wyraża to samo
„od drugiej strony" i lepiej znosi
zmianę liczby replik. Obu pól
**nie wolno** podać naraz.

</div>

</div>
</div>

---

# Czego PDB nie zrobi

<div data-marpit-fragment>

| PDB chroni przed | PDB **nie** chroni przed |
|---|---|
| `kubectl drain` przy serwisowaniu | awarią node'a |
| aktualizacją node'ów przez operatora | awarią zasilania |
| automatycznym skalowaniem w dół | `kubectl delete pod` |

</div>

<div data-marpit-fragment>

> PDB dotyczy wyłącznie **dobrowolnych** zakłóceń. Awaria nie pyta o zgodę —
> przed nią chroni liczba replik i ich rozproszenie, nie budżet zakłóceń.

</div>

---

<!-- _class: lab -->

# Lab 15

<div data-marpit-fragment>

**13 punktów + 3 dodatkowe · klaster `kind-ha`**

</div>

<div data-marpit-fragment>

```bash
labctl lab 15
```

</div>

<div data-marpit-fragment>

Policzysz kworum i odporność swojej topologii, zapytasz etcd
o listę członków, zrobisz migawkę i **zweryfikujesz ją** `etcdutl`-em,
nazwiesz to, czego kopia nie obejmuje, a w zadaniu dodatkowym
zabezpieczysz aplikację PodDisruptionBudgetem.

</div>

<div data-marpit-fragment>

> Przy 8 GiB RAM usuń najpierw klaster podstawowy:
> `labctl env down kind-basic`

</div>

---

# Co warto zapamiętać

* awaria control plane **zamraża** klaster, nie zabija działających Podów
* kworum to `n/2 + 1`; **trzy** node'y przeżyją jedną awarię, dwa — żadnej
* parzysta liczba instancji etcd nie daje nic ponad nieparzystą o jeden mniejszą
* po utracie kworum etcd przechodzi w tryb tylko do odczytu
* stacked jest prostszy, external odporniejszy i droższy
* `etcdctl` rozmawia z bazą, `etcdutl` pracuje na pliku migawki
* `restore` tworzy **nowy katalog danych** — trzeba na niego przestawić etcd
* w klastrze HA odtwarzasz **wszystkie** instancje z jednej migawki
  albo jedną, a resztę dołączasz od nowa
* **migawka etcd nie zawiera danych z PersistentVolume** ani PKI
* PDB chroni przed `drain`, nie przed awarią

<script src="nawigacja.js"></script>
