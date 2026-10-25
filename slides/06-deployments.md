---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · rozdział 6 · Managing State With Deployments'
---

<!-- _class: tytul -->
<!-- _paginate: false -->

# Managing State With Deployments

## Rozdział 6 · lab `06`

Wydanie, aktualizacja, wycofanie —
i co naprawdę dzieje się pod spodem

---

# Plan rozdziału

<div data-marpit-fragment>

1. **Przegląd** — po co warstwa nad Podem
2. **Deployment i ReplicaSet** — podział pracy
3. **Strategie wydania** — i jak nie zrobić przerwy
4. **DaemonSet** — kontroler bez pola `replicas`
5. **Labels** — spoiwo całego mechanizmu
6. **Lab 06** — pełny cykl życia wydania

</div>

---

<!-- _class: sekcja -->

# 1. Po co warstwa nad Podem

---

# Sam Pod nie wystarczy

<div data-marpit-fragment>

| Pod utworzony ręcznie | Pod z Deploymentu |
|---|---|
| padnie node → **znika na zawsze** | kontroler tworzy go gdzie indziej |
| skalowanie → ręcznie, po jednym | `kubectl scale --replicas=10` |
| nowa wersja → usuń i utwórz | `rollout` wymienia stopniowo |
| błąd w nowej wersji → odtwórz ze starego YAML-a | `rollout undo` |

</div>

<div data-marpit-fragment>

```text
   Deployment   ──►   ReplicaSet   ──►   Pod
   czym ma być        ile kopii          proces
   i jak wydawać      ma działać
```

</div>

<div data-marpit-fragment>

> Deployment **nie zarządza Podami bezpośrednio**. Zarządza ReplicaSetami,
> a one dopiero Podami. Ten podział jest kluczem do wycofywania wersji.

</div>

---

<!-- _class: sekcja -->

# 2. Deployment i ReplicaSet

---

# Co się dzieje przy aktualizacji

<div data-marpit-fragment>

```bash
kubectl set image deployment/sklep nginx=nginx:1.27-alpine -n lfs458-m06
kubectl get rs -n lfs458-m06
```

</div>

<div data-marpit-fragment>

```text
   przed:   ReplicaSet-abc (nginx:1.26)   3 Pody
   w trakcie: ReplicaSet-abc  2 Pody   +   ReplicaSet-xyz  2 Pody
   po:      ReplicaSet-abc (nginx:1.26)   0 Podów   ← zostaje w historii
            ReplicaSet-xyz (nginx:1.27)   3 Pody
```

</div>

* **każda zmiana szablonu** tworzy nowy ReplicaSet
* stare ReplicaSety zostają z zerem replik — to jest cała historia wydań
* ile ich trzymać: `spec.revisionHistoryLimit` (domyślnie 10)

<div data-marpit-fragment>

> Zmiana wyłącznie `replicas` **nie** tworzy nowej rewizji — to nie jest
> zmiana szablonu Poda.

</div>

---

# Historia i wycofywanie

<div data-marpit-fragment>

```bash
kubectl rollout history deployment/sklep -n lfs458-m06
kubectl rollout undo deployment/sklep -n lfs458-m06
kubectl rollout undo deployment/sklep --to-revision=1 -n lfs458-m06
kubectl rollout status deployment/sklep -n lfs458-m06
```

</div>

<div data-marpit-fragment>

Dwie rzeczy, które zaskakują:

</div>

<div data-marpit-fragment>

1. **`undo` nie cofa numeru rewizji.** Tworzy *nową* rewizję z zawartością
   starej: po cofnięciu z 2 do 1 masz rewizję **3**.
2. **`undo` przywraca też adnotacje** szablonu. Jeśli stara rewizja nie miała
   `kubernetes.io/change-cause`, po cofnięciu adnotacja **zniknie** —
   trzeba zapisać powód wycofania na nowo.

</div>

<div data-marpit-fragment>

```bash
kubectl annotate deployment/sklep -n lfs458-m06 --overwrite \
  kubernetes.io/change-cause='wycofanie do 1.26 — błąd w 1.27'
```

</div>

---

<!-- _class: sekcja -->

# 3. Strategie wydania

---

# Strategia: jak wymieniać Pody

<div class="kolumny">
<div>

<div data-marpit-fragment>

### RollingUpdate *(domyślna)*

</div>

<div data-marpit-fragment>

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```

</div>

* stopniowo, bez przestoju
* `maxUnavailable: 0` = nigdy mniej
  replik niż zadeklarowano
* `maxSurge: 1` = najwyżej jedna
  nadmiarowa

</div>
<div>

<div data-marpit-fragment>

### Recreate

</div>

<div data-marpit-fragment>

```yaml
strategy:
  type: Recreate
```

</div>

* ubija **wszystkie**, potem tworzy nowe
* jest przerwa w działaniu
* potrzebne, gdy dwie wersje nie mogą
  działać naraz (migracja schematu,
  wolumen RWO)

</div>
</div>

<div data-marpit-fragment>

> `maxUnavailable: 0` **nic nie gwarantuje bez `readinessProbe`** — bez niej
> Kubernetes uzna Pod za gotowy, zanim aplikacja zacznie odpowiadać.
> To najczęstsza przyczyna „wdrożenia bez przestoju”, które jednak zrobiło przestój.

</div>

---

# Probes — skąd klaster wie, że Pod działa

<div data-marpit-fragment>

| Probe | Pyta | Co się dzieje przy porażce |
|---|---|---|
| `startupProbe` | czy już wstał? | wstrzymuje pozostałe probes |
| `readinessProbe` | czy może przyjmować ruch? | **wypisanie z Service'u**, Pod żyje |
| `livenessProbe` | czy jeszcze żyje? | **restart kontenera** |

</div>

<div data-marpit-fragment>

```yaml
readinessProbe:
  httpGet: {path: /, port: 80}
  initialDelaySeconds: 2
  periodSeconds: 5
```

</div>

<div data-marpit-fragment>

> Najczęstszy błąd: `livenessProbe` ustawiona zbyt agresywnie na wolno
> startującej aplikacji — kontener jest restartowany w kółko, zanim zdąży wstać.
> Od tego jest `startupProbe`.

</div>

---

<!-- _class: sekcja -->

# 4. DaemonSet

---

# Jeden Pod na każdy node

<div data-marpit-fragment>

```yaml
kind: DaemonSet          # BEZ pola replicas
spec:
  template:
    spec:
      tolerations:       # żeby trafić także na control plane
        - {key: node-role.kubernetes.io/control-plane,
           operator: Exists, effect: NoSchedule}
```

</div>

* liczbę Podów wyznacza **liczba node'ów**, nie `replicas`
* nowy node w klastrze → Pod pojawia się tam automatycznie

<div data-marpit-fragment>

Zastosowania: zbieranie logów, agent monitoringu, CNI plugin, `kube-proxy`
— wszystko, co musi być **wszędzie**.

</div>

---

<!-- _class: sekcja -->

# 5. Labels

---

# Etykiety spinają wszystko

<div data-marpit-fragment>

```yaml
spec:
  selector:
    matchLabels: {app: sklep}    # kontroler szuka TEGO
  template:
    metadata:
      labels: {app: sklep}       # i to MUSI pasować
```

</div>

* `spec.selector` Deploymentu jest **niezmienny** po utworzeniu
* rozjazd selektora i etykiet szablonu = obiekt zostanie odrzucony
* Service wybiera Pody **tym samym mechanizmem** — stąd pusty `Endpoints`,
  gdy selektor się nie zgadza *(zobaczysz to w labie 12)*

---

# Etykiety w praktyce

<div data-marpit-fragment>

```bash
kubectl get pods --show-labels
kubectl get pods -l 'app in (sklep,blog),wersja!=v1'
kubectl label pod <nazwa> app=sklep-debug --overwrite
```

</div>

<div data-marpit-fragment>

> Ostatnie polecenie to najpraktyczniejsza technika diagnostyczna z tego
> rozdziału: **odcinasz podejrzany Pod** od kontrolera. ReplicaSet tworzy
> nowy w jego miejsce, a Ty spokojnie badasz odciętego — bez pośpiechu
> i bez wpływu na ruch produkcyjny.

</div>

---

<!-- _class: lab -->

# Lab 06

<div data-marpit-fragment>

**20 punktów + 3 dodatkowe**

</div>

<div data-marpit-fragment>

```bash
labctl lab 06
```

</div>

<div data-marpit-fragment>

Przejdziesz pełny cykl: wydanie, aktualizacja obrazu z zapisem powodu,
wycofanie, strategia `maxUnavailable: 0` z `readinessProbe`, DaemonSet
na wszystkich trzech node'ach, a na koniec odcięcie Poda od kontrolera.

</div>

<div data-marpit-fragment>

> Trzymaj w drugim oknie `kubectl get pods -n lfs458-m06 -w` — połowa nauki
> w tym labie polega na patrzeniu, co dzieje się **w trakcie**.

</div>

---

# Co warto zapamiętać

* Deployment zarządza ReplicaSetami, ReplicaSet — Podami
* każda zmiana **szablonu** tworzy nowy ReplicaSet; zmiana `replicas` nie
* `rollout undo` tworzy nową rewizję i **kasuje** `change-cause` ze starej
* `maxUnavailable: 0` bez `readinessProbe` niczego nie gwarantuje
* `readinessProbe` wypisuje z Service'u, `livenessProbe` restartuje kontener
* DaemonSet nie ma `replicas`; na control plane wejdzie tylko z `toleration`
* zmiana etykiety odcina Pod od kontrolera — technika diagnostyczna

<script src="nawigacja.js"></script>
