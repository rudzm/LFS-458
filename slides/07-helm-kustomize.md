---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · rozdział 7 · Helm and Kustomize'
---

<!-- _class: tytul -->
<!-- _paginate: false -->

# Helm and Kustomize

## Rozdział 7 · lab `07`

Jeden zestaw manifestów, wiele środowisk —
dwie szkoły rozwiązywania tego samego problemu

---

# Plan rozdziału

<div data-marpit-fragment>

1. **Helm** — czart, wartości, wydania i ich cykl życia
2. **Kustomize** — baza i nakładki, bez języka szablonów
3. **Kiedy co wybrać** — i dlaczego nie trzeba wybierać na zawsze
4. **Lab 07** — ten sam zestaw obiektów w dwóch wariantach

</div>

---

# Problem: jeden zestaw obiektów, trzy środowiska

<div data-marpit-fragment>

Masz Deployment, Service i ConfigMapę. Teraz potrzebujesz tego samego
w `dev`, `test` i `prod` — z inną liczbą replik, innym obrazem
i innym poziomem logowania.

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Złe odpowiedzi

</div>

* trzy kopie katalogu
* `sed` w skrypcie CI
* ręczna edycja przed każdym wdrożeniem

</div>
<div>

<div data-marpit-fragment>

### Dwie dobre

</div>

* **Helm** — szablony z wartościami
* **Kustomize** — baza plus nakładki,
  bez języka szablonów

</div>
</div>

<div data-marpit-fragment>

> Różnica jest w podejściu: Helm **generuje** YAML z szablonu, Kustomize
> **nakłada łatki** na gotowy YAML. Stąd biorą się wszystkie dalsze różnice.

</div>

---

<!-- _class: sekcja -->

# 1. Helm

---

# Trzy pojęcia i nic więcej

<div data-marpit-fragment>

| Pojęcie | Co to jest |
|---|---|
| **Chart** | paczka: szablony + wartości domyślne + metadane |
| **Values** | wartości wstawiane do szablonów (`values.yaml`, `--set`) |
| **Release** | **zainstalowana instancja** czartu w klastrze, z nazwą i historią |

</div>

<div data-marpit-fragment>

```bash
helm create sklep          # szkielet czartu
tree sklep
# sklep/
# ├── Chart.yaml        metadane i wersja
# ├── values.yaml       wartości domyślne
# ├── templates/        szablony Go
# │   ├── deployment.yaml
# │   └── service.yaml
# └── charts/           zależności
```

</div>

<div data-marpit-fragment>

> Z jednego czartu możesz mieć **wiele wydań** w jednym klastrze.

</div>

---

# Cykl życia wydania

<div data-marpit-fragment>

```bash
helm install sklep-prod ./sklep -n lfs458-m07 --create-namespace \
  --set replicaCount=3 --set image.tag=1.27-alpine

helm list -n lfs458-m07
helm upgrade sklep-prod ./sklep -n lfs458-m07 --reuse-values --set replicaCount=5
helm history sklep-prod -n lfs458-m07
helm rollback sklep-prod 1 -n lfs458-m07
helm uninstall sklep-prod -n lfs458-m07
```

</div>

<div data-marpit-fragment>

| Flaga | Co robi | Pułapka |
|---|---|---|
| `--set` | nadpisuje pojedynczą wartość | typy: `--set x=1` to liczba, `--set x="1"` tekst |
| `--reuse-values` | zachowuje wartości z poprzedniego wydania | **bez niej** wracają domyślne z czartu |
| `--atomic` | wycofuje przy niepowodzeniu | wydłuża czas wdrożenia |

</div>

<div data-marpit-fragment>

> Brak `--reuse-values` przy `upgrade` to najczęstsza niespodzianka Helma:
> zmieniasz jedną rzecz, a reszta po cichu wraca do wartości domyślnych.

</div>

---

# Sprawdź, zanim wdrożysz

<div data-marpit-fragment>

```bash
helm lint ./sklep                          # błędy w czarcie
helm template ./sklep --set replicaCount=7 # renderuje BEZ instalacji
helm install --dry-run --debug sklep-test ./sklep   # renderuje + waliduje serwerem
helm get manifest sklep-prod -n lfs458-m07 # co faktycznie poszło do klastra
```

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

**`helm template`**

</div>

* czysto lokalnie
* nie dotyka klastra
* nie zna stanu wydania

</div>
<div>

<div data-marpit-fragment>

**`helm get manifest`**

</div>

* czyta **stan wydania** z klastra
* pokazuje, co naprawdę jest wdrożone

</div>
</div>

<div data-marpit-fragment>

> Różnica między tymi dwoma poleceniami bywa pierwszym krokiem diagnozy:
> *„co miało być”* kontra *„co faktycznie jest”*.

</div>

---

<!-- _class: sekcja -->

# 2. Kustomize

---

# Bez szablonów — nakładki na YAML

<div data-marpit-fragment>

```text
   base/                     overlays/produkcja/
   ├── deployment.yaml       └── kustomization.yaml
   └── kustomization.yaml
```

</div>

<div data-marpit-fragment>

```yaml
# overlays/produkcja/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: lfs458-m07
nameSuffix: -produkcja
resources:
  - ../../base
replicas:
  - {name: web, count: 3}
```

</div>

<div data-marpit-fragment>

**Bazy nie ruszasz.** Nakładka opisuje wyłącznie różnicę.

</div>

---

# Kustomize jest wbudowany w kubectl

<div data-marpit-fragment>

```bash
kubectl kustomize overlays/produkcja     # wyrenderuj i obejrzyj
kubectl apply -k overlays/produkcja      # wyrenderuj i zastosuj
kubectl delete -k overlays/produkcja
```

</div>

<div data-marpit-fragment>

| Mechanizm | Do czego |
|---|---|
| `namePrefix` / `nameSuffix` | rozróżnienie środowisk w nazwach |
| `commonLabels` | wspólna etykieta dla wszystkiego |
| `replicas` | liczba replik bez dotykania bazy |
| `images` | podmiana obrazu i tagu |
| `patches` | dowolna łatka strategic-merge lub JSON 6902 |
| `configMapGenerator` | ConfigMapa **z sufiksem skrótu treści** |

</div>

---

# `configMapGenerator` — czemu akurat on

<div data-marpit-fragment>

Zwykła ConfigMapa ma **stałą nazwę**. Podmieniasz jej zawartość, a szablon
Poda się nie zmienia — więc Kubernetes nie ma powodu niczego restartować
i Pody dalej trzymają starą konfigurację.

</div>

<div data-marpit-fragment>

`configMapGenerator` dokleja do nazwy **skrót zawartości**:

</div>

<div data-marpit-fragment>

```text
ustawienia-produkcja-9f8c7b6d5t
                     └── zmienia się razem z treścią
```

</div>

<div data-marpit-fragment>

Nowa treść → nowa nazwa → zmiana w szablonie Poda → **automatyczny rollout**.

</div>

<div data-marpit-fragment>

> To jedna z tych rzeczy, dla których ludzie sięgają po Kustomize nawet wtedy,
> gdy resztę robią Helmem.

</div>

---

# Helm czy Kustomize

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Helm, gdy

</div>

* **dystrybuujesz** oprogramowanie
  innym zespołom
* potrzebujesz wersjonowania
  i `rollback` po stronie narzędzia
* instalujesz cudze komponenty
  (operatory, bazy, ingress)
* potrzebujesz logiki: pętle, warunki

</div>
<div>

<div data-marpit-fragment>

### Kustomize, gdy

</div>

* masz **własne** manifesty
  i kilka środowisk
* chcesz czytać czysty YAML,
  bez `{{ }}`
* nie potrzebujesz stanu wydania
* wystarczy `kubectl`, bez dodatków

</div>
</div>

<div data-marpit-fragment>

> Nie są wykluczające: częsty układ produkcyjny to `helm template` jako
> generator, a potem Kustomize jako warstwa dopasowania — albo Helm
> z nakładką `post-renderer`.

</div>

---

<!-- _class: lab -->

# Lab 07

<div data-marpit-fragment>

**15 punktów + 3 dodatkowe**

</div>

<div data-marpit-fragment>

```bash
labctl lab 07
```

</div>

<div data-marpit-fragment>

Zbudujesz czart i zainstalujesz z niego wydanie, zaktualizujesz je
i wycofasz, potem zrobisz to samo przez bazę i nakładkę Kustomize,
użyjesz `configMapGenerator`, a na koniec sprawdzisz czart
przez `helm lint` i `helm template` — **bez instalacji**.

</div>

<div data-marpit-fragment>

> Weryfikator patrzy wyłącznie na stan klastra. Pliki są środkiem,
> nie celem — organizuj je, jak chcesz.

</div>

---

# Co warto zapamiętać

* Helm: **chart** → **values** → **release**; wydanie ma historię i `rollback`
* `upgrade` bez `--reuse-values` przywraca wartości domyślne czartu
* `helm template` renderuje lokalnie, `helm get manifest` czyta stan z klastra
* Kustomize nie ma szablonów: baza plus nakładka opisująca **różnicę**
* `kubectl apply -k` wystarcza — Kustomize jest w `kubectl`
* `configMapGenerator` dokleja skrót treści i dzięki temu wymusza rollout
* Helm do dystrybucji, Kustomize do własnych manifestów; da się łączyć

<script src="nawigacja.js"></script>
