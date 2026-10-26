---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · rozdział 11 · Scheduling'
---

<!-- _class: tytul -->
<!-- _paginate: false -->

# Scheduling

## Rozdział 11 · lab `11`

Kto decyduje, na którym node'ie wyląduje Pod —
i jak na tę decyzję wpłynąć

---

# Plan rozdziału

<div data-marpit-fragment>

1. **Przegląd** — dwie fazy decyzji
2. **Ustawienia schedulera** — czym można pokręcić
3. **Specyfikacja Poda** — `nodeName`, `nodeSelector`, zasoby i klasy QoS
4. **Autoskalowanie** — HPA dokłada repliki, VPA powiększa Pody
5. **Affinity** — warianty `required` i `preferred`
6. **Taints i tolerations** — odpychanie zamiast przyciągania
7. **Priorytety i preemption** — kto komu ustępuje miejsca
8. **Lab 11** — mechanizmy rozmieszczania i autoskalowanie

</div>

---

<!-- _class: sekcja -->

# 1. Jak scheduler podejmuje decyzję

---

# Dwie fazy: filtrowanie i punktowanie

<div data-marpit-fragment>

```text
   wszystkie node'y
        │
        ▼  FILTERING — kto w ogóle może
   [ dość CPU i RAM? pasuje nodeSelector? toleruje taint?
     jest port? jest wolumen? ]
        │
        ▼  SCORING — kto najlepiej
   [ najwięcej wolnych zasobów? affinity? rozproszenie? ]
        │
        ▼
   zapis nodeName w obiekcie Poda
```

</div>

* żaden node nie przeszedł filtrowania → Pod zostaje `Pending`
* decyzja jest **jednorazowa**: raz przypisany Pod nie jest przenoszony

<div data-marpit-fragment>

> Dołożenie node'a nie przeniesie na niego istniejących Podów — od tego
> jest osobne narzędzie (`descheduler`).

</div>

---

# Pod, którego nie da się zaplanować

<div data-marpit-fragment>

```bash
kubectl describe pod za-duzy -n lfs458-m11 | sed -n '/Events/,$p'
```

</div>

<div data-marpit-fragment>

```text
Warning  FailedScheduling  0/3 nodes are available:
  1 node(s) had untolerated taint {node-role.kubernetes.io/control-plane: },
  2 Insufficient memory.
```

</div>

<div data-marpit-fragment>

> Ten komunikat jest **najbardziej pomocnym w całym Kubernetesie**: mówi
> dokładnie, ile node'ów odpadło i z jakiego powodu każdy.

</div>

<div data-marpit-fragment>

| Fraza | Znaczenie |
|---|---|
| `Insufficient cpu/memory` | suma `requests` nie mieści się na node'ie |
| `untolerated taint` | brakuje `toleration` |
| `didn't match Pod's node affinity/selector` | etykiety node'a nie pasują |
| `had volume node affinity conflict` | wolumen jest przypięty do innego node'a |

</div>

---

# To requests decyduje, nie zużycie

<div class="kolumny">
<div>

<div data-marpit-fragment>

### `requests`

</div>

* **gwarancja** — tyle Pod dostanie
* **to jest podstawa decyzji** schedulera
* suma requests ≤ pojemność node'a

</div>
<div>

<div data-marpit-fragment>

### `limits`

</div>

* **sufit** — więcej nie weźmie
* CPU: dławienie (throttling)
* pamięć: **OOMKill**
* schedulera nie obchodzą

</div>
</div>

<div data-marpit-fragment>

```yaml
resources:
  requests: {cpu: 50m, memory: 64Mi}
  limits:   {memory: 128Mi}
```

</div>

<div data-marpit-fragment>

> Node może być obciążony w 10%, a mimo to **odrzucić** Poda — bo liczy się
> suma zadeklarowanych `requests`, nie faktyczne zużycie. I odwrotnie:
> node bez `requests` przyjmie wszystko, a potem padnie na OOM.

</div>

---

<!-- _class: sekcja -->

# 2. Ustawienia schedulera

---

# Scheduler ma własną konfigurację

<div data-marpit-fragment>

Na klastrze kubeadm scheduler startuje **bez `--config`**:

</div>

<div data-marpit-fragment>

```bash
kubectl -n kube-system get pod -l component=kube-scheduler -o yaml | grep -A7 command:
#   - kube-scheduler
#   - --authentication-kubeconfig=/etc/kubernetes/scheduler.conf
#   - …
#   - --leader-elect=true            ← żadnego --config
```

</div>

* działa wtedy z ustawieniami **domyślnymi**: jeden profil `default-scheduler`, punktacja `LeastAllocated`
* własne ustawienia podaje plik **`KubeSchedulerConfiguration`**
* na kubeadm plik trafia do static Poda schedulera: flaga `--config` plus wolumen `hostPath` z tym plikiem

---

# Dwa profile w jednym schedulerze

<div data-marpit-fragment>

```yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: /etc/kubernetes/scheduler.conf
profiles:
  - schedulerName: default-scheduler
  - schedulerName: upakuj            # drugi profil w tym samym procesie
    pluginConfig:
      - name: NodeResourcesFit
        args:
          scoringStrategy:
            type: MostAllocated      # domyślnie: LeastAllocated
```

</div>

<div data-marpit-fragment>

> `LeastAllocated` rozkłada Pody na najluźniejsze node'y, `MostAllocated`
> upycha je na najbardziej zajętych — tak, żeby puste maszyny dało się wyłączyć.

</div>

---

# Fazy i pluginy

<div data-marpit-fragment>

Każda decyzja przechodzi przez stałe fazy, a w każdej działają **pluginy**:

</div>

<div data-marpit-fragment>

```text
  kolejka      PrioritySort                ← kto pierwszy: priorytet Poda
  Filter       NodeResourcesFit, NodeAffinity, TaintToleration, NodePorts,
               VolumeBinding, PodTopologySpread, InterPodAffinity
  PostFilter   DefaultPreemption           ← nikt nie przeszedł? preemption
  Score        NodeResourcesFit, NodeResourcesBalancedAllocation,
               ImageLocality, InterPodAffinity, TaintToleration
  Bind         DefaultBinder               ← zapis nodeName w obiekcie Poda
```

</div>

<div data-marpit-fragment>

> Każdy mechanizm z tego rozdziału to plugin: `nodeSelector` i affinity to
> `NodeAffinity`, taints — `TaintToleration`, `requests` — `NodeResourcesFit`,
> priorytety — `PrioritySort` i `DefaultPreemption`. Profil może je włączać,
> wyłączać i stroić.

</div>

---

# Profil wybiera Pod — `schedulerName`

<div data-marpit-fragment>

```yaml
spec:
  schedulerName: upakuj      # domyślnie: default-scheduler
```

</div>

* jeden proces schedulera może obsługiwać **kilka profili** — Pod wskazuje profil nazwą
* tak samo wskazuje się **osobny scheduler**, uruchomiony obok domyślnego
* nazwa, której nikt nie obsługuje → Pod czeka **w ciszy**:

<div data-marpit-fragment>

```text
sierota   0/1   Pending   0   10s      ← zero zdarzeń, zero warunków
```

</div>

<div data-marpit-fragment>

> Gdy Pod jest `Pending`, a `describe` milczy, sprawdź `spec.schedulerName`.
> Zwykle scheduler mówi, dlaczego odmówił — tego Poda po prostu nie widzi.

</div>

---

<!-- _class: sekcja -->

# 3. Specyfikacja Poda

---

# Trzy klasy QoS

<div data-marpit-fragment>

Klasę **wylicza apiserver przy tworzeniu Poda** — z `requests` i `limits`
wszystkich kontenerów — i zapisuje w `status.qosClass`:

</div>

<div data-marpit-fragment>

| Klasa | Kiedy |
|---|---|
| `Guaranteed` | **każdy** kontener: `requests` = `limits`, dla CPU **i** pamięci |
| `Burstable` | coś ustawione, ale warunek Guaranteed niespełniony |
| `BestEffort` | **żadnych** `requests` ani `limits` |

</div>

<div data-marpit-fragment>

```bash
kubectl get pod api -o jsonpath='{.status.qosClass}'
```

</div>

<div data-marpit-fragment>

> Pułapka: same `limits` bez `requests` dają **Guaranteed** — apiserver
> przepisuje `limits` do `requests`, a scheduler rezerwuje pełny limit.

</div>

---

# Co z klasą robi node

<div data-marpit-fragment>

| | Guaranteed | Burstable | BestEffort |
|---|---|---|---|
| `oom_score_adj` procesu | `-997` | `2`…`999` | `1000` |
| cgroup na node'ie | `kubepods` | `kubepods-burstable` | `kubepods-besteffort` |
| gdy node'owi brakuje pamięci | ginie **ostatni** | w środku | ginie **pierwszy** |

</div>

* przekroczenie `limits` pamięci → `OOMKilled`, kod wyjścia **137** — w każdej klasie
* przekroczenie `limits` CPU → dławienie, proces żyje dalej
* klasa jest **na całe życie Poda** — zmiana zasobów w locie, która by ją zmieniła, zostaje odrzucona:

<div data-marpit-fragment>

```text
Pod QOS Class may not change as a result of resizing
```

</div>

<div data-marpit-fragment>

> Praktyka: Guaranteed dla tego, czego nie wolno ubić (bazy, płatności),
> Burstable dla typowych aplikacji, BestEffort tylko dla zadań, którym
> nie szkodzi przerwanie.

</div>

---

# Od najprostszego do najbardziej elastycznego

<div data-marpit-fragment>

| Mechanizm | Jak działa | Kiedy |
|---|---|---|
| `nodeName` | **omija schedulera**, wpisujesz node wprost | prawie nigdy |
| `nodeSelector` | prosta równość etykiet | gdy warunek jest jeden |
| `nodeAffinity` | wyrażenia, `required` i `preferred` | gdy potrzebujesz `In`, `NotIn`, preferencji |
| `podAffinity` / `podAntiAffinity` | względem **innych Podów** | kolokacja albo rozproszenie |

</div>

<div data-marpit-fragment>

```bash
kubectl label node lfs458-worker2 dysk=ssd   # potem: nodeSelector: {dysk: ssd}
```

</div>

<div data-marpit-fragment>

> `nodeName` wygląda najprościej i dlatego kusi — ale omija całą logikę
> schedulera: nie sprawdzi zasobów, taintów ani wolumenów.

</div>

---

<!-- _class: sekcja -->

# 4. Autoskalowanie — HPA i VPA

---

# HPA — więcej replik, gdy rośnie obciążenie

<div class="kolumny">
<div>

<div data-marpit-fragment>

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: {name: skalowany}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: skalowany
  minReplicas: 1
  maxReplicas: 5
  metrics:
    - type: Resource
      resource:
        name: cpu
        target: {type: Utilization,
                 averageUtilization: 50}
```

</div>

</div>
<div>

<div data-marpit-fragment>

```bash
kubectl autoscale deployment skalowany \
  --cpu=50% --min=1 --max=5
```

</div>

* procent liczony jest od **`requests`** — przy `cpu: 20m` cel 50% to 10m na Pod
* bez `requests` HPA nie ma od czego liczyć: `missing request for cpu`
* dane bierze z **metrics-server**
* repliki = `ceil(bieżące × zużycie / cel)`, w granicach `min`–`max`

</div>
</div>

---

# HPA w praktyce

<div data-marpit-fragment>

```text
$ kubectl get hpa skalowany -w
NAME        REFERENCE              TARGETS              MINPODS   MAXPODS   REPLICAS
skalowany   Deployment/skalowany   cpu: <unknown>/50%   1         5         1     ← metryki jeszcze nie spłynęły
skalowany   Deployment/skalowany   cpu: 97%/50%         1         5         5

$ kubectl describe hpa skalowany | sed -n '/Events/,$p'
  Normal  SuccessfulRescale  New size: 5; reason: cpu resource utilization
                             (percentage of request) above target
```

</div>

* **w górę szybko** — tu około 20 s od startu ruchu
* **w dół ostrożnie** — domyślnie 5 minut stabilizacji, żeby nie skakać przy chwilowych spadkach (`behavior.scaleDown.stabilizationWindowSeconds`)
* ręczne `kubectl scale` przy działającym HPA nic nie da — HPA ustawi swoje

---

# VPA — większe Pody zamiast większej ich liczby

<div class="kolumny">
<div>

<div data-marpit-fragment>

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata: {name: baza}
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: baza
  updatePolicy: {updateMode: "Off"}
```

</div>

</div>
<div>

<div data-marpit-fragment>

| `updateMode` | Co robi |
|---|---|
| `Off` | tylko rekomendacje |
| `Initial` | tylko nowym Podom |
| `Recreate` | przez nowy Pod |
| `InPlaceOrRecreate` | w locie, gdy się da |

</div>

</div>
</div>

* VPA **nie jest częścią Kubernetesa** — osobny projekt `kubernetes/autoscaler`
* nie łącz z HPA na tym samym CPU czy pamięci; zmiana w locie nie zmieni **klasy QoS** (sekcja 3)

---

<!-- _class: sekcja -->

# 5. Affinity

---

# `required` kontra `preferred`

<div class="kolumny">
<div>

<div data-marpit-fragment>

### `required…`

</div>

<div data-marpit-fragment>

```yaml
requiredDuringScheduling
IgnoredDuringExecution:
  - labelSelector:
      matchLabels: {app: api}
    topologyKey: kubernetes.io/hostname
```

</div>

<div data-marpit-fragment>

**warunek** — bez niego Pending

</div>

</div>
<div>

<div data-marpit-fragment>

### `preferred…`

</div>

<div data-marpit-fragment>

```yaml
preferredDuringScheduling
IgnoredDuringExecution:
  - weight: 100
    podAffinityTerm:
      labelSelector:
        matchLabels: {app: api}
      topologyKey: kubernetes.io/hostname
```

</div>

<div data-marpit-fragment>

**punkty** — brak nie blokuje

</div>

</div>
</div>

<div data-marpit-fragment>

> `IgnoredDuringExecution` w obu nazwach znaczy: reguła obowiązuje **przy
> planowaniu**, a nie później. Gdy etykieta node'a zmieni się po starcie,
> działający Pod nie zostanie przeniesiony.

</div>

---

# Pułapka `required` anti-affinity

<div data-marpit-fragment>

```text
   2 worker nodes + 3 repliki + podAntiAffinity typu required
   → trzecia replika zostaje Pending NA ZAWSZE
```

</div>

<div data-marpit-fragment>

Gorzej przy wydaniu nowej wersji:

</div>

<div data-marpit-fragment>

```text
   maxSurge: 1 + anti-affinity required + tyle replik, co node'ów
   → nadmiarowa replika nie ma gdzie stanąć
   → rollout stoi: "1 out of 2 new replicas have been updated"
```

</div>

<div data-marpit-fragment>

> Dlatego w capstone rozproszenie jest zadeklarowane przez **`preferred`**.
> Ta reguła rozproszy repliki tak samo dobrze, gdy jest miejsce,
> a nie zakleszczy wydania, gdy go brakuje.

</div>

<div data-marpit-fragment>

Alternatywa warta poznania: `topologySpreadConstraints` z `maxSkew` —
pozwala powiedzieć „rozproszenie, ale dopuszczam odchylenie o jeden”.

</div>

---

<!-- _class: sekcja -->

# 6. Taints i tolerations

---

# Odwrócenie perspektywy

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Taint — na **node'ie**

</div>

<div data-marpit-fragment>

```bash
kubectl taint node lfs458-worker2 \
  gpu=true:NoSchedule
```

</div>

<div data-marpit-fragment>

*„nie wpuszczam nikogo,
kto się na to nie zgodzi”*

</div>

<div data-marpit-fragment>

| Efekt | Działanie |
|---|---|
| `NoSchedule` | nie wpuszcza nowych |
| `PreferNoSchedule` | unika, ale wpuści |
| `NoExecute` | **wyrzuca** działające |

</div>

</div>
<div>

<div data-marpit-fragment>

### Toleration — w **Podzie**

</div>

<div data-marpit-fragment>

```yaml
tolerations:
  - key: gpu
    operator: Equal
    value: "true"
    effect: NoSchedule
```

</div>

<div data-marpit-fragment>

*„zgadzam się tam stanąć”*

</div>

</div>
</div>

<div data-marpit-fragment>

> **`toleration` to tylko zgoda, nie przyciąganie.** Pod z wpisem `toleration` może
> wylądować gdziekolwiek indziej. Żeby trafił właśnie tam, potrzebuje
> dodatkowo `nodeSelector` albo `nodeAffinity`.

</div>

---

# Gdzie to spotkasz w praktyce

<div data-marpit-fragment>

```bash
kubectl describe node lfs458-control-plane | grep -i taint
# node-role.kubernetes.io/control-plane:NoSchedule
```

</div>

<div data-marpit-fragment>

| Taint | Kto go nakłada | Po co |
|---|---|---|
| `node-role.kubernetes.io/control-plane` | kubeadm | trzyma workloady z dala od control plane |
| `node.kubernetes.io/not-ready` | kubelet | node nie jest gotowy |
| `node.kubernetes.io/unreachable` | node controller | **`NoExecute`** — eksmisja po 300 s |
| `node.kubernetes.io/disk-pressure` | kubelet | kończy się miejsce |

</div>

<div data-marpit-fragment>

Zdjęcie taintu — to samo polecenie z **minusem** na końcu:

</div>

<div data-marpit-fragment>

```bash
kubectl taint node lfs458-control-plane node-role.kubernetes.io/control-plane:NoSchedule-
```

</div>

---

<!-- _class: sekcja -->

# 7. Priorytety i preemption

---

# PriorityClass — kto jest ważniejszy

<div class="kolumny">
<div>

<div data-marpit-fragment>

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: krytyczne
value: 1000000         # więcej = ważniej
globalDefault: false   # true: dla Podów bez klasy
preemptionPolicy: PreemptLowerPriority
description: "płatności i logowanie"
```

</div>

<div data-marpit-fragment>

```yaml
# w Podzie
spec:
  priorityClassName: krytyczne
```

</div>

</div>
<div>

* klasa to obiekt **klastrowy**, Pod wskazuje ją po nazwie
* przy tworzeniu Poda kontroler admission `Priority` zamienia nazwę na liczbę w **`spec.priority`**
* Pod bez klasy dostaje `0` — albo wartość klasy z `globalDefault: true`
* wbudowane `system-cluster-critical` i `system-node-critical` są dla komponentów klastra

</div>
</div>

---

# Preemption — wywłaszczanie Podów

<div data-marpit-fragment>

Gdy Pod się nie mieści, scheduler szuka node'a, na którym **usunięcie Podów
o niższym priorytecie** zrobi mu miejsce:

</div>

<div data-marpit-fragment>

```text
wazny       FailedScheduling: 0/3 nodes are available: 1 Insufficient cpu, …
            preemption: found a potential placement for pod on node
            lfs458-control-plane, preempting 1 victims
wypelniacz  Preempted: Preempted by pod 8fc10cc8-… on node lfs458-control-plane
```

</div>

* ofiary kończą pracę normalnie, a ich kontroler tworzy je od nowa — zwykle gdzie indziej
* ofiar szuka się **od najniższego priorytetu**; Pody ważniejsze od nowego są nietykalne
* `preemptionPolicy: Never` — Pod idzie na początek kolejki, ale nikogo nie wyrzuca:
  `preemption: not eligible due to preemptionPolicy=Never`

---

# Priorytet a QoS — dwie różne rzeczy

<div data-marpit-fragment>

| | QoS | Priorytet |
|---|---|---|
| skąd się bierze | wyliczany z `requests` i `limits` | nadawany przez `PriorityClass` |
| kto z niego korzysta | kubelet i jądro na node'ie | scheduler: kolejka i preemption; kubelet przy eksmisji |
| czy się zmienia | nigdy | nigdy po utworzeniu Poda |

</div>

<div data-marpit-fragment>

> Wysoki priorytet **nie chroni przed OOM**. Gdy na node'ie kończy się
> pamięć, jądro zabija według `oom_score_adj` — a ten zależy od klasy QoS.
> Ważny Pod bez `requests` i tak zginie pierwszy.

</div>

---

<!-- _class: lab -->

# Lab 11

<div data-marpit-fragment>

**25 punktów + 3 dodatkowe**

</div>

<div data-marpit-fragment>

```bash
labctl lab 11
```

</div>

<div data-marpit-fragment>

Przypniesz Pod etykietą node'a, **celowo utworzysz Pod nie do zaplanowania**
i odczytasz powód ze zdarzeń, rozproszysz repliki anti-affinity `required`,
zarezerwujesz node taintem i trafisz na niego Podem z `toleration`,
w zadaniu dodatkowym zobaczysz, że preferencja nie blokuje, potem
**HPA wyskaluje Deployment pod ruchem**, który sam wygenerujesz, a na koniec
odczytasz klasy QoS i nadasz Podowi priorytet.

</div>

<div data-marpit-fragment>

> Zadanie 2 zostawia Pod w `Pending` **celowo** — to materiał do diagnozy,
> nie awaria.

</div>

---

# Co warto zapamiętać

* scheduler **filtruje**, potem **punktuje**; decyzja jest jednorazowa
* `requests`, nie faktyczne zużycie, decyduje o tym, czy Pod się zmieści
* `kubectl describe pod` podaje dokładny powód niezaplanowania — czytaj go
* `nodeName` omija schedulera i jego zabezpieczenia
* `required` = warunek (ryzyko `Pending`), `preferred` = punkty w rankingu
* anti-affinity `required` przy `maxSurge: 1` potrafi zakleszczyć rollout
* **taint odpycha, toleration tylko się zgadza** — przyciąga `nodeSelector`
* klasa QoS wynika z `requests` i `limits`: Guaranteed ginie ostatni, BestEffort pierwszy
* HPA liczy procent od `requests` i dokłada repliki; VPA zmienia same `requests`
* `PriorityClass` ustala kolejkę i to, kogo scheduler wywłaszczy — przed OOM nie chroni
* `schedulerName` wskazuje profil; nazwa bez schedulera = `Pending` bez zdarzeń

<script src="nawigacja.js"></script>
