# Lab 06 — wydawanie wersji

**20 punktów obowiązkowych + 3 dodatkowe**

## Cel

Pełny cykl życia wdrożenia: wydanie, aktualizacja, wycofanie, konfiguracja
strategii i kontroler, który nie ma pola `replicas`.

**Otwórz drugi terminal** i trzymaj w nim podgląd na żywo. Połowa nauki
w tym labie polega na patrzeniu, co się dzieje w trakcie:

```bash
kubectl get pods -n lfs458-m06 -w
```

## Ściągawka

| Chcę | Polecenie |
|---|---|
| utworzyć Deployment | `kubectl create deployment sklep --image=nginx:1.26-alpine --replicas=3 -n lfs458-m06` |
| zmienić obraz | `kubectl set image deployment/sklep nginx=nginx:1.27-alpine -n lfs458-m06` |
| zapisać powód zmiany | `kubectl annotate deployment/sklep kubernetes.io/change-cause='…' --overwrite -n lfs458-m06` |
| śledzić rollout | `kubectl rollout status deployment/sklep -n lfs458-m06` |
| historię | `kubectl rollout history deployment/sklep -n lfs458-m06` |
| wycofać | `kubectl rollout undo deployment/sklep -n lfs458-m06` |
| przeładować Pody | `kubectl rollout restart deployment/sklep -n lfs458-m06` |
| zobaczyć ReplicaSety | `kubectl get rs -n lfs458-m06` |
| zmienić pole punktowo | `kubectl patch deployment sklep -n lfs458-m06 --type=strategic -p '{…}'` |
| etykiety Podów | `kubectl get pods -n lfs458-m06 --show-labels` |

## Zadania

| # | Zadanie | Pkt |
|---|---|---|
| 1 | Deployment `sklep` — 3 repliki `nginx:1.26-alpine` | 3 |
| 2 | Aktualizacja do `1.27-alpine` z zapisanym powodem zmiany | 4 |
| 3 | Wycofanie do poprzedniej rewizji | 4 |
| 4 | `RollingUpdate` bez przestoju + `readinessProbe` | 4 |
| 5 | DaemonSet `agent` na wszystkich trzech node'ach | 3 |
| 6 | *(dodatkowe)* odcięcie Poda od kontrolera zmianą etykiety | 3 |
| 7 | **Pytania ABCD** — ReplicaSety, rewizje, historia wydań | 2 |

## Na co zwrócić uwagę

- **Zadanie 2** — sprawdzenie patrzy na **historię** (numer rewizji, ReplicaSety),
  a nie na bieżący obraz. Musi tak być, bo w zadaniu 3 tę zmianę cofniesz.
- **Zadanie 3, pułapka** — po `rollout undo` adnotacja `change-cause`
  **znika**. `undo` przywraca cały szablon starej rewizji razem z jej
  adnotacjami, a tamta żadnego powodu nie miała. Zapisz nowy, opisujący
  wycofanie. To realna pułapka produkcyjna: historia zmian potrafi się urwać
  dokładnie w momencie, w którym najbardziej jej potrzebujesz.
- **Zadanie 4** — `maxUnavailable: 0` bez `readinessProbe` niczego nie
  gwarantuje. Kubernetes uzna Pod za gotowy, gdy tylko wystartuje proces —
  i wymieni wszystkie repliki na zepsute.
- **Zadanie 5** — bez `toleration` dla taintu DaemonSet trafi tylko na dwa
  workery. Sprawdzenie wymaga trzech, więc ten wpis jest obowiązkowy.
- **Zadanie 6** — obserwuj w drugim oknie. ReplicaSet zauważa brak repliki
  w ułamku sekundy. Odcięty Pod działa dalej i **nikt go nie usunie** —
  to najlepsza technika „zamrożenia” wadliwego Poda do analizy.

## Sprzątanie

```bash
labctl cleanup 06
```
