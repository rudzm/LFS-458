# Lab 07 — pakowanie i warianty

**15 punktów obowiązkowych + 3 dodatkowe**

## Cel

Po tym labie potrafisz wziąć jeden zestaw manifestów i wydać go w kilku
wariantach dwiema metodami: **szablonami** (Helm — wartości, wydania,
wycofywanie) i **nakładkami** (Kustomize — baza plus łatki, bez żadnego
języka szablonów). Zobaczysz też, czym różni się `helm template`
od `helm install`.

## Katalog roboczy

Będziesz tworzyć pliki na dysku:

```bash
mkdir -p ~/lfs458-m07 && cd ~/lfs458-m07
```

Weryfikator patrzy **wyłącznie na stan klastra** — pliki są środkiem, nie celem.

## Ściągawka

| Chcę | Polecenie |
|---|---|
| szkielet chartu | `helm create sklep` |
| sprawdzić chart | `helm lint ./sklep` |
| wyrenderować bez instalacji | `helm template sklep-prod ./sklep` |
| zainstalować | `helm install sklep-prod ./sklep -n lfs458-m07 --create-namespace` |
| listę wydań | `helm list -n lfs458-m07` |
| użyte wartości | `helm get values sklep-prod -n lfs458-m07` |
| historię | `helm history sklep-prod -n lfs458-m07` |
| wycofać | `helm rollback sklep-prod 1 -n lfs458-m07` |
| gdzie Helm trzyma stan | `kubectl get secrets -n lfs458-m07 -l owner=helm` |
| wyrenderować nakładkę | `kubectl kustomize overlays/produkcja` |
| zastosować nakładkę | `kubectl apply -k overlays/produkcja` |

## Zadania

| # | Zadanie | Pkt |
|---|---|---|
| 1 | Własny chart i instalacja wydania | 4 |
| 2 | `helm upgrade` i `helm rollback` | 4 |
| 3 | Baza i nakładka Kustomize | 4 |
| 4 | `configMapGenerator` i hasz w nazwie | 3 |
| 5 | *(dodatkowe)* `helm lint` i `helm template` | 3 |

## Na co zwrócić uwagę

- **Zadanie 2** — bez `--reuse-values` Helm wraca do wartości domyślnych chartu
  dla wszystkiego, co nie zostało podane ponownie. To najczęstsza pułapka przy
  aktualizacji: podnosisz liczbę replik i przy okazji cofasz obraz.
- **Zadanie 2** — `helm rollback` tworzy **nową** rewizję o zawartości starej,
  tak samo jak `kubectl rollout undo` w module 06.
- **Zadanie 3** — zawsze najpierw `kubectl kustomize <katalog>`. Zobaczysz
  dokładnie te manifesty, które trafią do klastra.
- **Zadanie 4** — wygenerowana ConfigMapa dostaje **hasz treści** w nazwie,
  a nakładka dokłada jeszcze swój `nameSuffix`. Wyjdzie coś w rodzaju
  `ustawienia-produkcja-9f8c7b6d5t`. Hasz jest celowy: zmiana treści zmienia
  nazwę, a zmiana nazwy w szablonie Poda wywołuje rollout — czyli rozwiązuje
  problem z modułu 08.

## Sprzątanie

```bash
labctl cleanup 07     # odinstalowuje wydanie Helma i usuwa namespace
```
