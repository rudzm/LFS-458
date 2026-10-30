---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · dodatek · GitOps i Argo Rollouts'
---

<!-- _class: tytul -->
<!-- _paginate: false -->

# GitOps i Argo Rollouts

## Dodatek · pokaz na żywo

Ten sam `reconciliation loop`, który zna już kontroler —
tylko stan docelowy mieszka w gicie, a nie w głowie administratora

---

# Plan dodatku

<div data-marpit-fragment>

1. **Problem** — kto i kiedy ostatnio zmienił ten klaster?
2. **Cztery zasady** — co sprawia, że to jest GitOps, a nie „YAML w repo”
3. **Push kontra pull** — kto ma poświadczenia do klastra
4. **Argo CD** — `Application`, synchronizacja, `prune` i `selfHeal`
5. **Pokaz** — commit zmienia klaster, `kubectl edit` już nie
6. **Argo Rollouts** — canary i blue-green z podziałem ruchu i analizą

</div>

<div data-marpit-fragment>

> GitOps jest **poza programem LFS458 i CKA** — na egzaminie pracujesz
> `kubectl`. Ale w pracy klaster rzadko zmienia się inaczej niż przez repo.

</div>

---

# Problem: klaster zmieniany z laptopa

<div class="kolumny">
<div>

<div data-marpit-fragment>

**Jak było przez cztery dni**

</div>

```bash
kubectl apply -f deployment.yaml
kubectl scale deploy sklep --replicas=5
kubectl edit deploy sklep   # „na chwilę”
```

</div>
<div>

<div data-marpit-fragment>

**Co z tego wynika**

</div>

* nikt nie wie, **kto** i **dlaczego** zmienił
* plik w repo mówi 3 repliki, klaster ma 5
  — to jest `drift` *(rozjazd)*
* odtworzenie klastra = archeologia
* każdy z `kubectl` jest drogą do produkcji

</div>
</div>

<div data-marpit-fragment>

> Rozdział 7 dał nam **jeden zestaw manifestów na wiele środowisk**.
> Brakuje odpowiedzi na pytanie, **kto je wdraża i pilnuje**.

</div>

---

# Cztery zasady GitOps

<div data-marpit-fragment>

| Zasada | Znaczenie | Znamy to z… |
|---|---|---|
| **Declarative** *(deklaratywnie)* | opisujesz stan, nie kroki | manifesty YAML, rozdział 3 |
| **Versioned and immutable** | stan docelowy żyje w gicie, z historią | `git log` zamiast `kubectl rollout history` |
| **Pulled automatically** | agent **sam pobiera** zmiany z repo | — |
| **Continuously reconciled** | agent **stale** porównuje i naprawia | `reconciliation loop` kontrolera |

</div>

<div data-marpit-fragment>

> Zasady pochodzą z projektu **OpenGitOps** (CNCF). Dwie ostatnie odróżniają
> GitOps od zwykłego „pipeline robi `kubectl apply`”.

</div>

---

# Push kontra pull — gdzie są klucze do klastra

<div data-marpit-fragment>

```text
 push      git ──► CI ──kubectl apply──►  klaster
                   │
                   └─ CI trzyma kubeconfig z prawami do produkcji

 pull      git ◄──pobiera co kilka minut──  agent w klastrze ──► klaster
                                          (Argo CD / Flux)
```

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

**Push**

</div>

* wdraża raz, w chwili pipeline'u
* ręczna zmiana zostaje na zawsze
* poświadczenia **poza** klastrem

</div>
<div>

<div data-marpit-fragment>

**Pull**

</div>

* porównuje i poprawia **cały czas**
* ręczna zmiana zostaje cofnięta
* klaster **niczego nie wystawia** — tylko czyta repo

</div>
</div>

---

# To ten sam wzorzec co kontroler

<div data-marpit-fragment>

```text
 Deployment controller          Argo CD
 ─────────────────────          ─────────────────────────────
 stan docelowy:  spec w etcd    stan docelowy:  commit w gicie
 stan faktyczny: Pody           stan faktyczny: obiekty w klastrze
 różnica?        twórz / usuń   różnica?        apply / prune
```

</div>

<div data-marpit-fragment>

* Argo CD to **zwykły operator**: CRD `Application` plus kontroler (rozdział 13)
* działa w klastrze jako Pody, z własnym `ServiceAccount` i RBAC (rozdział 5)
* wdraża surowy YAML, **czart Helma albo Kustomize** (rozdział 7)

</div>

<div data-marpit-fragment>

> Nic nowego pod spodem — jeden `reconciliation loop` więcej, tylko piętro wyżej.

</div>

---

# Argo CD czy Flux

<div data-marpit-fragment>

| | **Argo CD** | **Flux** |
|---|---|---|
| model | `Application` wskazuje repo i ścieżkę | `GitRepository` + `Kustomization` / `HelmRelease` |
| interfejs | rozbudowane **UI** z grafem obiektów | CLI i CRD, UI z zewnątrz |
| wiele klastrów | jedna instancja zarządza wieloma | zwykle Flux w każdym klastrze |
| status w CNCF | graduated | graduated |

</div>

<div data-marpit-fragment>

> Oba robią to samo. Na pokaz bierzemy **Argo CD**, bo jego graf
> Deployment → ReplicaSet → Pod widać z drugiego końca sali.

</div>

---

# `Application` — jeden obiekt, który tworzysz ręcznie

<div data-marpit-fragment>

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: witryna
  namespace: argocd
spec:
  source:
    repoURL: git://git.gitops-git.svc.cluster.local/aplikacja.git
    targetRevision: main          # gałąź, tag albo commit
    path: .                       # katalog z manifestami w repo
  destination:
    server: https://kubernetes.default.svc
    namespace: witryna
  syncPolicy:
    automated:
      prune: true                 # plik zniknął z gita → obiekt znika
      selfHeal: true              # zmiana w klastrze → cofnięta
```

</div>

---

# Trzy przełączniki synchronizacji

<div data-marpit-fragment>

| Ustawienie | Bez niego | Z nim |
|---|---|---|
| `automated` | Argo CD pokazuje `OutOfSync`, czeka na kliknięcie **Sync** | wdraża każdy nowy commit sam |
| `prune` | usunięty z repo obiekt **zostaje** w klastrze | znika razem z plikiem |
| `selfHeal` | ręczna zmiana zostaje do następnego commita | cofnięta w kilkanaście sekund |

</div>

<div data-marpit-fragment>

> `selfHeal` zmienia odruch zespołu: **`kubectl edit` przestaje działać**.
> Zmiana bez commita nie przetrwa nawet minuty, więc jedyna droga to repo.

</div>

---

<!-- _class: lab -->

# Pokaz

<div data-marpit-fragment>

```bash
demo/gitops/demo.sh postaw          # Argo CD + serwer git w klastrze, ~1 min
demo/gitops/demo.sh ui              # https://localhost:9443, admin + hasło
```

</div>

<div data-marpit-fragment>

```bash
cd ~/gitops-demo
sed -i 's/replicas: 2/replicas: 4/' deployment.yaml
git commit -am "Cztery repliki" && git wypchnij       # push + hard refresh
```

</div>

<div data-marpit-fragment>

```bash
kubectl -n witryna scale deploy witryna --replicas=10   # i patrzymy, jak wraca
git rm service.yaml && git commit -m "Bez Service" && git wypchnij   # prune
git revert --no-edit HEAD && git wypchnij                  # rollback = commit
```

</div>

<div data-marpit-fragment>

```bash
demo/gitops/demo.sh usun            # klaster wraca do stanu sprzed pokazu
```

</div>

---

# Na co uważać, zanim wprowadzisz GitOps

<div data-marpit-fragment>

| Pułapka | Rozwiązanie |
|---|---|
| **Secret w gicie** to hasło w historii na zawsze | Sealed Secrets, SOPS, External Secrets Operator |
| HPA zmienia `replicas`, `selfHeal` je cofa | usuń `replicas` z manifestu albo `ignoreDifferences` |
| Argo CD sprawdza repo **co ~3 minuty** | webhook z GitHuba/GitLaba — wtedy od razu |
| awaria wymaga szybkiej ręcznej poprawki | wyłącz `selfHeal` na chwilę, potem commit |

</div>

<div data-marpit-fragment>

> W pokazie ~3 minuty skraca `wypchnij`: po pushu każe Argo CD odświeżyć
> repo od razu (*hard refresh*). Na produkcji tę samą robotę robi webhook.

</div>

---

<!-- _class: sekcja -->

# Argo Rollouts — wdrożenia progresywne

---

# Czego brakuje Deploymentowi

<div data-marpit-fragment>

`RollingUpdate` z rozdziału 6 reguluje tylko **tempo** podmiany Podów.
Nie wie nic o tym, **czy nowa wersja działa** — poza `readinessProbe`.

</div>

<div data-marpit-fragment>

| Potrzeba | Deployment | Rollout |
|---|---|---|
| 20% ruchu na nową wersję | tylko przez proporcję Podów (1 z 5) | **dokładnie 20%**, przez Ingress lub mesh |
| zatrzymanie na decyzję człowieka | `rollout pause` ręcznie, w losowym momencie | `pause` jako **krok planu** |
| wycofanie, gdy rośnie liczba błędów | nie ma — `progressDeadlineSeconds` tylko oznacza porażkę | `AnalysisTemplate` → **automatyczny abort** |
| blue-green | dwa Deploymenty i ręczna zmiana selektora | strategia `blueGreen` |

</div>

<div data-marpit-fragment>

> `progressive delivery` *(wdrażanie progresywne)*: nowa wersja dostaje ruch
> porcjami, a każdą porcję poprzedza decyzja — człowieka albo metryki.

</div>

---

# Instalacja — kontroler i wtyczka `kubectl`

<div data-marpit-fragment>

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts --server-side \
  -f https://github.com/argoproj/argo-rollouts/releases/download/v1.10.1/install.yaml
```

</div>

<div data-marpit-fragment>

```bash
curl -LO https://github.com/argoproj/argo-rollouts/releases/download/v1.10.1/kubectl-argo-rollouts-linux-amd64
sudo install -m 0755 kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
kubectl argo rollouts version
```

</div>

<div data-marpit-fragment>

> **Bez `--server-side`** instalacja kończy się błędem
> `metadata.annotations: Too long` — CRD `Rollout` nie mieści się
> w adnotacji `last-applied-configuration`. Ten sam kłopot ma Argo CD.

</div>

<div data-marpit-fragment>

Wtyczka to zwykły plik `kubectl-*` w `PATH` — tak `kubectl` znajduje
wszystkie wtyczki, także instalowane przez `krew`.

</div>

---

# `Rollout` = Deployment + plan wdrożenia

<div class="kolumny">
<div>

<div data-marpit-fragment>

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: sklep
spec:
  replicas: 4
  selector:
    matchLabels: {app: sklep}
  template:            # jak w Deploymencie
    metadata:
      labels: {app: sklep}
    spec:
      containers:
        - name: web
          image: hashicorp/http-echo:1.0
          args: ["-text=wersja 1"]
```

</div>

</div>
<div>

<div data-marpit-fragment>

```yaml
  strategy:
    canary:
      stableService: sklep-stabilny
      canaryService: sklep-canary
      trafficRouting:
        nginx:
          stableIngress: sklep
      steps:
        - setWeight: 20
        - pause: {}          # czeka na człowieka
        - setWeight: 50
        - pause: {duration: 30s}
```

</div>

<div data-marpit-fragment>

* `spec.template` — bez zmian względem Deploymentu
* istniejący Deployment podepniesz przez `workloadRef`

</div>

</div>
</div>

---

# Jak naprawdę dzieli się ruch

<div data-marpit-fragment>

```text
             Host: sklep.lfs458.local
                       │
        ┌──────────────┴──────────────┐
  Ingress sklep               Ingress sklep-sklep-canary   ← tworzy Rollouts
        │                       canary-weight: "20"
  Service sklep-stabilny        Service sklep-canary
        │                              │
  ReplicaSet rev 1 (4 Pody)     ReplicaSet rev 2 (1 Pod)
```

</div>

<div data-marpit-fragment>

```bash
for i in $(seq 200); do curl -s -H 'Host: sklep.lfs458.local' localhost:8080/; done | sort | uniq -c
#   159 wersja 1
#    41 wersja 2
```

</div>

<div data-marpit-fragment>

> Rollouts **nie przełącza ruchu sam** — ustawia adnotacje `canary-*`
> ingress-nginx i selektory obu Service'ów. Bez `trafficRouting` zostaje
> tylko proporcja Podów, jak w Deploymencie.

</div>

---

# Prowadzenie wdrożenia z wtyczki

<div data-marpit-fragment>

```bash
kubectl argo rollouts set image sklep web=hashicorp/http-echo:1.1 -n sklep
kubectl argo rollouts get rollout sklep -n sklep --watch
```

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

```text
Status:        ॥ Paused
Message:       CanaryPauseStep
  Step:        1/4
  ActualWeight: 20
⟳ sklep               Rollout     ॥ Paused
├──# revision:2
│  └──⧉ sklep-69d6…   ReplicaSet  canary
└──# revision:1
   └──⧉ sklep-6894…   ReplicaSet  stable
```

</div>

</div>
<div>

<div data-marpit-fragment>

| Polecenie | Działanie |
|---|---|
| `promote` | następny krok; `--full` — do końca |
| `abort` | cały ruch wraca na stabilną |
| `retry` | ponowienie po `abort` |
| `undo` | powrót do poprzedniej rewizji |
| `dashboard` | UI na `localhost:3100` |

</div>

</div>
</div>

---

# Analiza — wycofanie bez człowieka

<div class="kolumny">
<div>

<div data-marpit-fragment>

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: odpowiada
spec:
  metrics:
    - name: test-dymny
      count: 3
      interval: 10s
      failureLimit: 0
      provider:
        job:
          spec:
            backoffLimit: 0
            template:
              spec:
                restartPolicy: Never
                containers:
                  - name: test
                    image: busybox:1.36
                    command: [sh, -c, "wget -qO- \
                      http://sklep-canary | grep -q ^wersja"]
```

</div>

</div>
<div>

<div data-marpit-fragment>

```yaml
steps:
  - setWeight: 20
  - analysis:
      templates:
        - templateName: odpowiada
  - setWeight: 50
```

</div>

<div data-marpit-fragment>

```text
Status:  ✖ Degraded
Message: RolloutAborted: … Metric
  "test-dymny" assessed Failed due to
  failed (1) > failureLimit (0)
```

</div>

<div data-marpit-fragment>

* `job` — dowolny test jako Job (rozdział 5)
* w praktyce: `prometheus` — np. odsetek odpowiedzi 5xx
* także `web`, `datadog`, `newrelic`, …

</div>

</div>
</div>

---

# Blue-green — dwie pełne wersje, jedno przełączenie

<div class="kolumny">
<div>

<div data-marpit-fragment>

```yaml
strategy:
  blueGreen:
    activeService: sklep
    previewService: sklep-podglad
    autoPromotionEnabled: false
    scaleDownDelaySeconds: 30
```

</div>

<div data-marpit-fragment>

* nowa wersja startuje w **pełnej** liczbie replik
* testy idą przez `sklep-podglad`
* `promote` przełącza selektor `sklep` **naraz**

</div>

</div>
<div>

<div data-marpit-fragment>

| Chwila | `sklep` | `sklep-podglad` |
|---|---|---|
| przed zmianą | niebieska | niebieska |
| po `set image` | niebieska | **zielona** |
| po `promote` | **zielona** | zielona |

</div>

<div data-marpit-fragment>

> Canary oszczędza zasoby i ogranicza zasięg błędu. Blue-green kosztuje
> **podwójną liczbę Podów**, ale daje natychmiastowy powrót.

</div>

</div>
</div>

---

# Rollouts i Argo CD razem

<div data-marpit-fragment>

```text
 git commit (nowy obraz) ──► Argo CD: sync Rollout ──► Rollouts: 20% → analiza → 50% → 100%
                                                              │
                                                  metryki złe → abort, ruch wraca
```

</div>

<div data-marpit-fragment>

| Kto | Za co odpowiada |
|---|---|
| **Argo CD** | **co** ma być wdrożone — stan z gita |
| **Argo Rollouts** | **jak** nowa wersja dostaje ruch |

</div>

<div data-marpit-fragment>

* Argo CD rozumie stan `Rollout` (`Paused`, `Degraded`) i ma w UI akcje
  **Resume**, **Abort**, **Retry**
* nowy obraz wpisuj **w repo**, nie przez `set image` —
  inaczej `selfHeal` cofnie zmianę w połowie canary
* abort nie zmienia repo: w gicie dalej stoi zła wersja, więc popraw ją commitem

</div>

---

<!-- _class: lab -->

# Na koniec: egzamin próbny

<div data-marpit-fragment>

**100 punktów · 120 minut · próg 66% · klaster `kind-basic`**

</div>

<div data-marpit-fragment>

```bash
labctl lab 90
```

</div>

<div data-marpit-fragment>

Zadania w stylu CKA ze wszystkich pięciu obszarów egzaminu.
**Bez podpowiedzi i bez sprawdzania w trakcie** — wynik dopiero po
zakończeniu, z punktami za częściowo wykonane zadania.

</div>

---

# Co warto zapamiętać

* GitOps = **stan docelowy w gicie** + **agent w klastrze**, który pilnuje go w `reconciliation loop`
* pull zamiast push: klaster **sam pobiera** zmiany, CI nie trzyma kubeconfigu
* Argo CD i Flux to **zwykłe operatory** — CRD plus `reconciliation loop`
* `prune` usuwa to, czego nie ma w repo; `selfHeal` cofa ręczne zmiany
* rollback to **`git revert`**, a audyt to **`git log`**
* Secretów nie trzyma się w gicie jawnym tekstem
* Argo Rollouts: canary **z dokładnym podziałem ruchu**, pauzy i **automatyczny abort** po metrykach
* Argo CD decyduje, **co** wdrożyć; Rollouts — **jak** nowa wersja dostaje ruch

---

# Dziękuję — ankieta i kontakt

Proszę o wypełnienie krótkiej ankiety — pomoże poprawić kolejne edycje
szkolenia. **Zeskanuj kod telefonem** albo otwórz link.

<div class="kolumny">
<div style="text-align:center">

**Ankieta po szkoleniu**

<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 37 37" width="240" height="240" shape-rendering="crispEdges"><rect width="37" height="37" fill="#fff"/><path fill="#17202a" d="M2 2h1v1h-1zM3 2h1v1h-1zM4 2h1v1h-1zM5 2h1v1h-1zM6 2h1v1h-1zM7 2h1v1h-1zM8 2h1v1h-1zM12 2h1v1h-1zM15 2h1v1h-1zM19 2h1v1h-1zM20 2h1v1h-1zM21 2h1v1h-1zM22 2h1v1h-1zM25 2h1v1h-1zM28 2h1v1h-1zM29 2h1v1h-1zM30 2h1v1h-1zM31 2h1v1h-1zM32 2h1v1h-1zM33 2h1v1h-1zM34 2h1v1h-1zM2 3h1v1h-1zM8 3h1v1h-1zM11 3h1v1h-1zM15 3h1v1h-1zM16 3h1v1h-1zM17 3h1v1h-1zM19 3h1v1h-1zM22 3h1v1h-1zM24 3h1v1h-1zM26 3h1v1h-1zM28 3h1v1h-1zM34 3h1v1h-1zM2 4h1v1h-1zM4 4h1v1h-1zM5 4h1v1h-1zM6 4h1v1h-1zM8 4h1v1h-1zM10 4h1v1h-1zM12 4h1v1h-1zM13 4h1v1h-1zM15 4h1v1h-1zM17 4h1v1h-1zM18 4h1v1h-1zM19 4h1v1h-1zM20 4h1v1h-1zM21 4h1v1h-1zM22 4h1v1h-1zM25 4h1v1h-1zM28 4h1v1h-1zM30 4h1v1h-1zM31 4h1v1h-1zM32 4h1v1h-1zM34 4h1v1h-1zM2 5h1v1h-1zM4 5h1v1h-1zM5 5h1v1h-1zM6 5h1v1h-1zM8 5h1v1h-1zM10 5h1v1h-1zM13 5h1v1h-1zM16 5h1v1h-1zM18 5h1v1h-1zM21 5h1v1h-1zM22 5h1v1h-1zM23 5h1v1h-1zM24 5h1v1h-1zM25 5h1v1h-1zM26 5h1v1h-1zM28 5h1v1h-1zM30 5h1v1h-1zM31 5h1v1h-1zM32 5h1v1h-1zM34 5h1v1h-1zM2 6h1v1h-1zM4 6h1v1h-1zM5 6h1v1h-1zM6 6h1v1h-1zM8 6h1v1h-1zM10 6h1v1h-1zM11 6h1v1h-1zM13 6h1v1h-1zM15 6h1v1h-1zM17 6h1v1h-1zM20 6h1v1h-1zM26 6h1v1h-1zM28 6h1v1h-1zM30 6h1v1h-1zM31 6h1v1h-1zM32 6h1v1h-1zM34 6h1v1h-1zM2 7h1v1h-1zM8 7h1v1h-1zM10 7h1v1h-1zM12 7h1v1h-1zM14 7h1v1h-1zM15 7h1v1h-1zM16 7h1v1h-1zM17 7h1v1h-1zM18 7h1v1h-1zM19 7h1v1h-1zM22 7h1v1h-1zM24 7h1v1h-1zM28 7h1v1h-1zM34 7h1v1h-1zM2 8h1v1h-1zM3 8h1v1h-1zM4 8h1v1h-1zM5 8h1v1h-1zM6 8h1v1h-1zM7 8h1v1h-1zM8 8h1v1h-1zM10 8h1v1h-1zM12 8h1v1h-1zM14 8h1v1h-1zM16 8h1v1h-1zM18 8h1v1h-1zM20 8h1v1h-1zM22 8h1v1h-1zM24 8h1v1h-1zM26 8h1v1h-1zM28 8h1v1h-1zM29 8h1v1h-1zM30 8h1v1h-1zM31 8h1v1h-1zM32 8h1v1h-1zM33 8h1v1h-1zM34 8h1v1h-1zM10 9h1v1h-1zM12 9h1v1h-1zM16 9h1v1h-1zM17 9h1v1h-1zM23 9h1v1h-1zM25 9h1v1h-1zM2 10h1v1h-1zM4 10h1v1h-1zM5 10h1v1h-1zM6 10h1v1h-1zM7 10h1v1h-1zM8 10h1v1h-1zM11 10h1v1h-1zM13 10h1v1h-1zM15 10h1v1h-1zM16 10h1v1h-1zM17 10h1v1h-1zM19 10h1v1h-1zM20 10h1v1h-1zM24 10h1v1h-1zM26 10h1v1h-1zM28 10h1v1h-1zM29 10h1v1h-1zM30 10h1v1h-1zM31 10h1v1h-1zM32 10h1v1h-1zM3 11h1v1h-1zM9 11h1v1h-1zM11 11h1v1h-1zM12 11h1v1h-1zM18 11h1v1h-1zM20 11h1v1h-1zM21 11h1v1h-1zM22 11h1v1h-1zM23 11h1v1h-1zM25 11h1v1h-1zM26 11h1v1h-1zM28 11h1v1h-1zM29 11h1v1h-1zM31 11h1v1h-1zM32 11h1v1h-1zM34 11h1v1h-1zM6 12h1v1h-1zM7 12h1v1h-1zM8 12h1v1h-1zM11 12h1v1h-1zM13 12h1v1h-1zM17 12h1v1h-1zM20 12h1v1h-1zM23 12h1v1h-1zM27 12h1v1h-1zM28 12h1v1h-1zM30 12h1v1h-1zM32 12h1v1h-1zM33 12h1v1h-1zM2 13h1v1h-1zM3 13h1v1h-1zM4 13h1v1h-1zM5 13h1v1h-1zM6 13h1v1h-1zM7 13h1v1h-1zM10 13h1v1h-1zM12 13h1v1h-1zM13 13h1v1h-1zM16 13h1v1h-1zM17 13h1v1h-1zM21 13h1v1h-1zM23 13h1v1h-1zM24 13h1v1h-1zM27 13h1v1h-1zM28 13h1v1h-1zM30 13h1v1h-1zM31 13h1v1h-1zM32 13h1v1h-1zM33 13h1v1h-1zM2 14h1v1h-1zM4 14h1v1h-1zM6 14h1v1h-1zM7 14h1v1h-1zM8 14h1v1h-1zM12 14h1v1h-1zM17 14h1v1h-1zM20 14h1v1h-1zM23 14h1v1h-1zM29 14h1v1h-1zM30 14h1v1h-1zM31 14h1v1h-1zM33 14h1v1h-1zM3 15h1v1h-1zM4 15h1v1h-1zM6 15h1v1h-1zM11 15h1v1h-1zM12 15h1v1h-1zM13 15h1v1h-1zM15 15h1v1h-1zM16 15h1v1h-1zM17 15h1v1h-1zM18 15h1v1h-1zM19 15h1v1h-1zM22 15h1v1h-1zM24 15h1v1h-1zM25 15h1v1h-1zM26 15h1v1h-1zM27 15h1v1h-1zM28 15h1v1h-1zM29 15h1v1h-1zM31 15h1v1h-1zM33 15h1v1h-1zM34 15h1v1h-1zM2 16h1v1h-1zM3 16h1v1h-1zM5 16h1v1h-1zM7 16h1v1h-1zM8 16h1v1h-1zM10 16h1v1h-1zM11 16h1v1h-1zM12 16h1v1h-1zM14 16h1v1h-1zM19 16h1v1h-1zM21 16h1v1h-1zM24 16h1v1h-1zM26 16h1v1h-1zM27 16h1v1h-1zM28 16h1v1h-1zM29 16h1v1h-1zM30 16h1v1h-1zM33 16h1v1h-1zM4 17h1v1h-1zM14 17h1v1h-1zM15 17h1v1h-1zM18 17h1v1h-1zM20 17h1v1h-1zM21 17h1v1h-1zM22 17h1v1h-1zM23 17h1v1h-1zM24 17h1v1h-1zM25 17h1v1h-1zM26 17h1v1h-1zM27 17h1v1h-1zM28 17h1v1h-1zM32 17h1v1h-1zM3 18h1v1h-1zM6 18h1v1h-1zM8 18h1v1h-1zM11 18h1v1h-1zM12 18h1v1h-1zM18 18h1v1h-1zM19 18h1v1h-1zM21 18h1v1h-1zM22 18h1v1h-1zM24 18h1v1h-1zM26 18h1v1h-1zM27 18h1v1h-1zM29 18h1v1h-1zM30 18h1v1h-1zM34 18h1v1h-1zM2 19h1v1h-1zM4 19h1v1h-1zM5 19h1v1h-1zM7 19h1v1h-1zM9 19h1v1h-1zM12 19h1v1h-1zM14 19h1v1h-1zM16 19h1v1h-1zM18 19h1v1h-1zM19 19h1v1h-1zM20 19h1v1h-1zM21 19h1v1h-1zM22 19h1v1h-1zM25 19h1v1h-1zM27 19h1v1h-1zM28 19h1v1h-1zM29 19h1v1h-1zM31 19h1v1h-1zM32 19h1v1h-1zM34 19h1v1h-1zM5 20h1v1h-1zM6 20h1v1h-1zM7 20h1v1h-1zM8 20h1v1h-1zM11 20h1v1h-1zM13 20h1v1h-1zM14 20h1v1h-1zM15 20h1v1h-1zM17 20h1v1h-1zM18 20h1v1h-1zM19 20h1v1h-1zM24 20h1v1h-1zM26 20h1v1h-1zM27 20h1v1h-1zM29 20h1v1h-1zM30 20h1v1h-1zM32 20h1v1h-1zM33 20h1v1h-1zM2 21h1v1h-1zM4 21h1v1h-1zM5 21h1v1h-1zM6 21h1v1h-1zM9 21h1v1h-1zM10 21h1v1h-1zM11 21h1v1h-1zM16 21h1v1h-1zM18 21h1v1h-1zM19 21h1v1h-1zM20 21h1v1h-1zM25 21h1v1h-1zM26 21h1v1h-1zM29 21h1v1h-1zM30 21h1v1h-1zM31 21h1v1h-1zM32 21h1v1h-1zM3 22h1v1h-1zM5 22h1v1h-1zM8 22h1v1h-1zM9 22h1v1h-1zM15 22h1v1h-1zM18 22h1v1h-1zM22 22h1v1h-1zM23 22h1v1h-1zM24 22h1v1h-1zM29 22h1v1h-1zM30 22h1v1h-1zM31 22h1v1h-1zM2 23h1v1h-1zM5 23h1v1h-1zM6 23h1v1h-1zM9 23h1v1h-1zM10 23h1v1h-1zM11 23h1v1h-1zM12 23h1v1h-1zM14 23h1v1h-1zM16 23h1v1h-1zM17 23h1v1h-1zM20 23h1v1h-1zM23 23h1v1h-1zM25 23h1v1h-1zM26 23h1v1h-1zM27 23h1v1h-1zM28 23h1v1h-1zM31 23h1v1h-1zM34 23h1v1h-1zM2 24h1v1h-1zM6 24h1v1h-1zM8 24h1v1h-1zM9 24h1v1h-1zM10 24h1v1h-1zM11 24h1v1h-1zM12 24h1v1h-1zM15 24h1v1h-1zM16 24h1v1h-1zM17 24h1v1h-1zM18 24h1v1h-1zM19 24h1v1h-1zM20 24h1v1h-1zM22 24h1v1h-1zM26 24h1v1h-1zM31 24h1v1h-1zM32 24h1v1h-1zM33 24h1v1h-1zM2 25h1v1h-1zM4 25h1v1h-1zM5 25h1v1h-1zM7 25h1v1h-1zM9 25h1v1h-1zM10 25h1v1h-1zM11 25h1v1h-1zM15 25h1v1h-1zM16 25h1v1h-1zM17 25h1v1h-1zM23 25h1v1h-1zM26 25h1v1h-1zM27 25h1v1h-1zM28 25h1v1h-1zM31 25h1v1h-1zM32 25h1v1h-1zM2 26h1v1h-1zM4 26h1v1h-1zM5 26h1v1h-1zM6 26h1v1h-1zM8 26h1v1h-1zM10 26h1v1h-1zM11 26h1v1h-1zM12 26h1v1h-1zM13 26h1v1h-1zM16 26h1v1h-1zM17 26h1v1h-1zM19 26h1v1h-1zM22 26h1v1h-1zM24 26h1v1h-1zM26 26h1v1h-1zM27 26h1v1h-1zM28 26h1v1h-1zM29 26h1v1h-1zM30 26h1v1h-1zM31 26h1v1h-1zM33 26h1v1h-1zM34 26h1v1h-1zM10 27h1v1h-1zM11 27h1v1h-1zM13 27h1v1h-1zM16 27h1v1h-1zM20 27h1v1h-1zM21 27h1v1h-1zM22 27h1v1h-1zM23 27h1v1h-1zM26 27h1v1h-1zM30 27h1v1h-1zM32 27h1v1h-1zM33 27h1v1h-1zM34 27h1v1h-1zM2 28h1v1h-1zM3 28h1v1h-1zM4 28h1v1h-1zM5 28h1v1h-1zM6 28h1v1h-1zM7 28h1v1h-1zM8 28h1v1h-1zM11 28h1v1h-1zM13 28h1v1h-1zM15 28h1v1h-1zM17 28h1v1h-1zM18 28h1v1h-1zM20 28h1v1h-1zM22 28h1v1h-1zM23 28h1v1h-1zM25 28h1v1h-1zM26 28h1v1h-1zM28 28h1v1h-1zM30 28h1v1h-1zM32 28h1v1h-1zM33 28h1v1h-1zM2 29h1v1h-1zM8 29h1v1h-1zM10 29h1v1h-1zM13 29h1v1h-1zM15 29h1v1h-1zM16 29h1v1h-1zM17 29h1v1h-1zM18 29h1v1h-1zM22 29h1v1h-1zM23 29h1v1h-1zM24 29h1v1h-1zM25 29h1v1h-1zM26 29h1v1h-1zM30 29h1v1h-1zM31 29h1v1h-1zM32 29h1v1h-1zM33 29h1v1h-1zM34 29h1v1h-1zM2 30h1v1h-1zM4 30h1v1h-1zM5 30h1v1h-1zM6 30h1v1h-1zM8 30h1v1h-1zM10 30h1v1h-1zM11 30h1v1h-1zM14 30h1v1h-1zM16 30h1v1h-1zM20 30h1v1h-1zM23 30h1v1h-1zM26 30h1v1h-1zM27 30h1v1h-1zM28 30h1v1h-1zM29 30h1v1h-1zM30 30h1v1h-1zM31 30h1v1h-1zM33 30h1v1h-1zM34 30h1v1h-1zM2 31h1v1h-1zM4 31h1v1h-1zM5 31h1v1h-1zM6 31h1v1h-1zM8 31h1v1h-1zM10 31h1v1h-1zM12 31h1v1h-1zM13 31h1v1h-1zM16 31h1v1h-1zM17 31h1v1h-1zM18 31h1v1h-1zM19 31h1v1h-1zM22 31h1v1h-1zM24 31h1v1h-1zM25 31h1v1h-1zM26 31h1v1h-1zM27 31h1v1h-1zM30 31h1v1h-1zM31 31h1v1h-1zM32 31h1v1h-1zM34 31h1v1h-1zM2 32h1v1h-1zM4 32h1v1h-1zM5 32h1v1h-1zM6 32h1v1h-1zM8 32h1v1h-1zM10 32h1v1h-1zM11 32h1v1h-1zM12 32h1v1h-1zM14 32h1v1h-1zM15 32h1v1h-1zM19 32h1v1h-1zM21 32h1v1h-1zM23 32h1v1h-1zM24 32h1v1h-1zM25 32h1v1h-1zM26 32h1v1h-1zM27 32h1v1h-1zM28 32h1v1h-1zM29 32h1v1h-1zM32 32h1v1h-1zM2 33h1v1h-1zM8 33h1v1h-1zM12 33h1v1h-1zM13 33h1v1h-1zM14 33h1v1h-1zM15 33h1v1h-1zM16 33h1v1h-1zM18 33h1v1h-1zM21 33h1v1h-1zM22 33h1v1h-1zM23 33h1v1h-1zM25 33h1v1h-1zM27 33h1v1h-1zM30 33h1v1h-1zM31 33h1v1h-1zM32 33h1v1h-1zM2 34h1v1h-1zM3 34h1v1h-1zM4 34h1v1h-1zM5 34h1v1h-1zM6 34h1v1h-1zM7 34h1v1h-1zM8 34h1v1h-1zM10 34h1v1h-1zM11 34h1v1h-1zM12 34h1v1h-1zM13 34h1v1h-1zM14 34h1v1h-1zM15 34h1v1h-1zM16 34h1v1h-1zM19 34h1v1h-1zM21 34h1v1h-1zM24 34h1v1h-1zM26 34h1v1h-1zM27 34h1v1h-1zM28 34h1v1h-1zM29 34h1v1h-1zM33 34h1v1h-1z"/></svg>

<span style="font-size:0.75em; white-space:nowrap">[https://sube.nobleprog.com/pl/open-tef/47027](https://sube.nobleprog.com/pl/open-tef/47027)</span>

</div>
<div style="text-align:center">

**Kontakt ze mną — LinkedIn**

<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 33 33" width="240" height="240" shape-rendering="crispEdges"><rect width="33" height="33" fill="#fff"/><path fill="#17202a" d="M2 2h1v1h-1zM3 2h1v1h-1zM4 2h1v1h-1zM5 2h1v1h-1zM6 2h1v1h-1zM7 2h1v1h-1zM8 2h1v1h-1zM11 2h1v1h-1zM13 2h1v1h-1zM16 2h1v1h-1zM18 2h1v1h-1zM19 2h1v1h-1zM20 2h1v1h-1zM21 2h1v1h-1zM22 2h1v1h-1zM24 2h1v1h-1zM25 2h1v1h-1zM26 2h1v1h-1zM27 2h1v1h-1zM28 2h1v1h-1zM29 2h1v1h-1zM30 2h1v1h-1zM2 3h1v1h-1zM8 3h1v1h-1zM11 3h1v1h-1zM13 3h1v1h-1zM14 3h1v1h-1zM16 3h1v1h-1zM17 3h1v1h-1zM19 3h1v1h-1zM22 3h1v1h-1zM24 3h1v1h-1zM30 3h1v1h-1zM2 4h1v1h-1zM4 4h1v1h-1zM5 4h1v1h-1zM6 4h1v1h-1zM8 4h1v1h-1zM10 4h1v1h-1zM12 4h1v1h-1zM14 4h1v1h-1zM16 4h1v1h-1zM21 4h1v1h-1zM24 4h1v1h-1zM26 4h1v1h-1zM27 4h1v1h-1zM28 4h1v1h-1zM30 4h1v1h-1zM2 5h1v1h-1zM4 5h1v1h-1zM5 5h1v1h-1zM6 5h1v1h-1zM8 5h1v1h-1zM10 5h1v1h-1zM11 5h1v1h-1zM12 5h1v1h-1zM14 5h1v1h-1zM15 5h1v1h-1zM16 5h1v1h-1zM17 5h1v1h-1zM18 5h1v1h-1zM19 5h1v1h-1zM24 5h1v1h-1zM26 5h1v1h-1zM27 5h1v1h-1zM28 5h1v1h-1zM30 5h1v1h-1zM2 6h1v1h-1zM4 6h1v1h-1zM5 6h1v1h-1zM6 6h1v1h-1zM8 6h1v1h-1zM10 6h1v1h-1zM11 6h1v1h-1zM13 6h1v1h-1zM18 6h1v1h-1zM19 6h1v1h-1zM20 6h1v1h-1zM21 6h1v1h-1zM22 6h1v1h-1zM24 6h1v1h-1zM26 6h1v1h-1zM27 6h1v1h-1zM28 6h1v1h-1zM30 6h1v1h-1zM2 7h1v1h-1zM8 7h1v1h-1zM10 7h1v1h-1zM12 7h1v1h-1zM13 7h1v1h-1zM16 7h1v1h-1zM17 7h1v1h-1zM18 7h1v1h-1zM24 7h1v1h-1zM30 7h1v1h-1zM2 8h1v1h-1zM3 8h1v1h-1zM4 8h1v1h-1zM5 8h1v1h-1zM6 8h1v1h-1zM7 8h1v1h-1zM8 8h1v1h-1zM10 8h1v1h-1zM12 8h1v1h-1zM14 8h1v1h-1zM16 8h1v1h-1zM18 8h1v1h-1zM20 8h1v1h-1zM22 8h1v1h-1zM24 8h1v1h-1zM25 8h1v1h-1zM26 8h1v1h-1zM27 8h1v1h-1zM28 8h1v1h-1zM29 8h1v1h-1zM30 8h1v1h-1zM10 9h1v1h-1zM11 9h1v1h-1zM13 9h1v1h-1zM17 9h1v1h-1zM18 9h1v1h-1zM21 9h1v1h-1zM22 9h1v1h-1zM2 10h1v1h-1zM4 10h1v1h-1zM5 10h1v1h-1zM6 10h1v1h-1zM7 10h1v1h-1zM8 10h1v1h-1zM13 10h1v1h-1zM14 10h1v1h-1zM15 10h1v1h-1zM16 10h1v1h-1zM19 10h1v1h-1zM20 10h1v1h-1zM21 10h1v1h-1zM24 10h1v1h-1zM25 10h1v1h-1zM26 10h1v1h-1zM27 10h1v1h-1zM28 10h1v1h-1zM2 11h1v1h-1zM4 11h1v1h-1zM6 11h1v1h-1zM11 11h1v1h-1zM12 11h1v1h-1zM14 11h1v1h-1zM15 11h1v1h-1zM16 11h1v1h-1zM19 11h1v1h-1zM20 11h1v1h-1zM21 11h1v1h-1zM23 11h1v1h-1zM24 11h1v1h-1zM25 11h1v1h-1zM26 11h1v1h-1zM30 11h1v1h-1zM5 12h1v1h-1zM6 12h1v1h-1zM8 12h1v1h-1zM9 12h1v1h-1zM15 12h1v1h-1zM17 12h1v1h-1zM19 12h1v1h-1zM24 12h1v1h-1zM5 13h1v1h-1zM6 13h1v1h-1zM7 13h1v1h-1zM10 13h1v1h-1zM11 13h1v1h-1zM12 13h1v1h-1zM14 13h1v1h-1zM17 13h1v1h-1zM18 13h1v1h-1zM21 13h1v1h-1zM22 13h1v1h-1zM23 13h1v1h-1zM25 13h1v1h-1zM27 13h1v1h-1zM29 13h1v1h-1zM2 14h1v1h-1zM3 14h1v1h-1zM4 14h1v1h-1zM7 14h1v1h-1zM8 14h1v1h-1zM10 14h1v1h-1zM12 14h1v1h-1zM13 14h1v1h-1zM14 14h1v1h-1zM15 14h1v1h-1zM19 14h1v1h-1zM21 14h1v1h-1zM27 14h1v1h-1zM28 14h1v1h-1zM2 15h1v1h-1zM5 15h1v1h-1zM6 15h1v1h-1zM9 15h1v1h-1zM10 15h1v1h-1zM11 15h1v1h-1zM13 15h1v1h-1zM14 15h1v1h-1zM15 15h1v1h-1zM18 15h1v1h-1zM19 15h1v1h-1zM20 15h1v1h-1zM21 15h1v1h-1zM22 15h1v1h-1zM23 15h1v1h-1zM24 15h1v1h-1zM26 15h1v1h-1zM30 15h1v1h-1zM2 16h1v1h-1zM3 16h1v1h-1zM6 16h1v1h-1zM8 16h1v1h-1zM11 16h1v1h-1zM12 16h1v1h-1zM15 16h1v1h-1zM16 16h1v1h-1zM17 16h1v1h-1zM18 16h1v1h-1zM20 16h1v1h-1zM22 16h1v1h-1zM23 16h1v1h-1zM24 16h1v1h-1zM25 16h1v1h-1zM27 16h1v1h-1zM28 16h1v1h-1zM3 17h1v1h-1zM4 17h1v1h-1zM5 17h1v1h-1zM6 17h1v1h-1zM10 17h1v1h-1zM13 17h1v1h-1zM14 17h1v1h-1zM16 17h1v1h-1zM17 17h1v1h-1zM25 17h1v1h-1zM26 17h1v1h-1zM29 17h1v1h-1zM6 18h1v1h-1zM7 18h1v1h-1zM8 18h1v1h-1zM10 18h1v1h-1zM11 18h1v1h-1zM12 18h1v1h-1zM13 18h1v1h-1zM17 18h1v1h-1zM19 18h1v1h-1zM21 18h1v1h-1zM25 18h1v1h-1zM27 18h1v1h-1zM28 18h1v1h-1zM2 19h1v1h-1zM3 19h1v1h-1zM4 19h1v1h-1zM5 19h1v1h-1zM7 19h1v1h-1zM12 19h1v1h-1zM14 19h1v1h-1zM15 19h1v1h-1zM18 19h1v1h-1zM19 19h1v1h-1zM20 19h1v1h-1zM21 19h1v1h-1zM22 19h1v1h-1zM23 19h1v1h-1zM24 19h1v1h-1zM25 19h1v1h-1zM26 19h1v1h-1zM28 19h1v1h-1zM30 19h1v1h-1zM2 20h1v1h-1zM4 20h1v1h-1zM5 20h1v1h-1zM8 20h1v1h-1zM13 20h1v1h-1zM14 20h1v1h-1zM15 20h1v1h-1zM16 20h1v1h-1zM17 20h1v1h-1zM19 20h1v1h-1zM24 20h1v1h-1zM25 20h1v1h-1zM28 20h1v1h-1zM2 21h1v1h-1zM5 21h1v1h-1zM7 21h1v1h-1zM10 21h1v1h-1zM11 21h1v1h-1zM13 21h1v1h-1zM15 21h1v1h-1zM17 21h1v1h-1zM20 21h1v1h-1zM22 21h1v1h-1zM23 21h1v1h-1zM24 21h1v1h-1zM25 21h1v1h-1zM26 21h1v1h-1zM29 21h1v1h-1zM2 22h1v1h-1zM4 22h1v1h-1zM6 22h1v1h-1zM7 22h1v1h-1zM8 22h1v1h-1zM10 22h1v1h-1zM11 22h1v1h-1zM14 22h1v1h-1zM16 22h1v1h-1zM19 22h1v1h-1zM20 22h1v1h-1zM22 22h1v1h-1zM23 22h1v1h-1zM24 22h1v1h-1zM25 22h1v1h-1zM26 22h1v1h-1zM28 22h1v1h-1zM29 22h1v1h-1zM30 22h1v1h-1zM10 23h1v1h-1zM11 23h1v1h-1zM12 23h1v1h-1zM13 23h1v1h-1zM14 23h1v1h-1zM18 23h1v1h-1zM19 23h1v1h-1zM20 23h1v1h-1zM22 23h1v1h-1zM26 23h1v1h-1zM27 23h1v1h-1zM28 23h1v1h-1zM29 23h1v1h-1zM30 23h1v1h-1zM2 24h1v1h-1zM3 24h1v1h-1zM4 24h1v1h-1zM5 24h1v1h-1zM6 24h1v1h-1zM7 24h1v1h-1zM8 24h1v1h-1zM11 24h1v1h-1zM13 24h1v1h-1zM17 24h1v1h-1zM18 24h1v1h-1zM19 24h1v1h-1zM21 24h1v1h-1zM22 24h1v1h-1zM24 24h1v1h-1zM26 24h1v1h-1zM27 24h1v1h-1zM28 24h1v1h-1zM2 25h1v1h-1zM8 25h1v1h-1zM10 25h1v1h-1zM13 25h1v1h-1zM16 25h1v1h-1zM21 25h1v1h-1zM22 25h1v1h-1zM26 25h1v1h-1zM29 25h1v1h-1zM2 26h1v1h-1zM4 26h1v1h-1zM5 26h1v1h-1zM6 26h1v1h-1zM8 26h1v1h-1zM10 26h1v1h-1zM14 26h1v1h-1zM17 26h1v1h-1zM19 26h1v1h-1zM22 26h1v1h-1zM23 26h1v1h-1zM24 26h1v1h-1zM25 26h1v1h-1zM26 26h1v1h-1zM28 26h1v1h-1zM29 26h1v1h-1zM30 26h1v1h-1zM2 27h1v1h-1zM4 27h1v1h-1zM5 27h1v1h-1zM6 27h1v1h-1zM8 27h1v1h-1zM10 27h1v1h-1zM12 27h1v1h-1zM13 27h1v1h-1zM14 27h1v1h-1zM15 27h1v1h-1zM16 27h1v1h-1zM18 27h1v1h-1zM19 27h1v1h-1zM20 27h1v1h-1zM21 27h1v1h-1zM25 27h1v1h-1zM27 27h1v1h-1zM28 27h1v1h-1zM29 27h1v1h-1zM30 27h1v1h-1zM2 28h1v1h-1zM4 28h1v1h-1zM5 28h1v1h-1zM6 28h1v1h-1zM8 28h1v1h-1zM10 28h1v1h-1zM11 28h1v1h-1zM14 28h1v1h-1zM16 28h1v1h-1zM17 28h1v1h-1zM18 28h1v1h-1zM21 28h1v1h-1zM23 28h1v1h-1zM24 28h1v1h-1zM25 28h1v1h-1zM26 28h1v1h-1zM27 28h1v1h-1zM28 28h1v1h-1zM29 28h1v1h-1zM2 29h1v1h-1zM8 29h1v1h-1zM12 29h1v1h-1zM13 29h1v1h-1zM15 29h1v1h-1zM16 29h1v1h-1zM17 29h1v1h-1zM22 29h1v1h-1zM23 29h1v1h-1zM24 29h1v1h-1zM25 29h1v1h-1zM27 29h1v1h-1zM29 29h1v1h-1zM2 30h1v1h-1zM3 30h1v1h-1zM4 30h1v1h-1zM5 30h1v1h-1zM6 30h1v1h-1zM7 30h1v1h-1zM8 30h1v1h-1zM10 30h1v1h-1zM13 30h1v1h-1zM16 30h1v1h-1zM19 30h1v1h-1zM21 30h1v1h-1zM24 30h1v1h-1zM25 30h1v1h-1zM26 30h1v1h-1zM27 30h1v1h-1zM28 30h1v1h-1z"/></svg>

<span style="font-size:0.75em; white-space:nowrap">[https://www.linkedin.com/in/michal-rudz/](https://www.linkedin.com/in/michal-rudz/)</span>

</div>
</div>

<script src="nawigacja.js"></script>
