# Capstone — wdrożenie produkcyjne od zera

**28 punktów obowiązkowych + 4 dodatkowe**

## Cel

Zbudować od zera środowisko produkcyjne dla jednej usługi, spełniające
standardy z całego szkolenia: limity i domyślne żądania, konfiguracja poza
obrazem, utwardzone kontenery, własny ServiceAccount z minimalnym RBAC, rozproszenie
replik, wejście z zewnątrz, izolacja sieciowa i bezpieczne wydanie nowej wersji.

## Jak to działa

Dostajesz **wymagania, nie instrukcje**. Hinty są skąpsze niż w zwykłych
labach: pierwszy naprowadza, drugi podaje polecenie. Pełnych rozwiązań szukaj
dopiero wtedy, gdy naprawdę utkniesz — to ćwiczenie ma przypominać egzamin.

Wszystko powstaje w namespace **`sklep-prod`**, na klastrze `kind-basic`.

## Co budujesz

```text
              świat zewnętrzny
                    │  Host: sklep.lfs458.local
              ┌─────▼─────┐
              │  Ingress  │  ← klasa nginx
              └─────┬─────┘
              ┌─────▼─────┐
              │  Service  │  80 → 5678
              └─────┬─────┘
      ┌─────────────┴─────────────┐   NetworkPolicy: tylko z ingress-nginx
      ▼                           ▼
┌───────────┐               ┌───────────┐   ServiceAccount + RBAC
│  api (1)  │               │  api (2)  │   ConfigMap + Secret
└───────────┘               └───────────┘   utwardzony securityContext
   node A                     node B      rozproszenie po node'ach
                                            PDB + strategia bez przestoju
```

## Zadania

| # | Zadanie | Moduły | Pkt |
|---|---|---|---|
| 1 | Namespace z `ResourceQuota` i `LimitRange` | 05 | 4 |
| 2 | ConfigMap, Secret, ServiceAccount, RBAC | 05, 07 | 4 |
| 3 | Deployment wg standardu produkcyjnego | 06, 10, 14 | 6 |
| 4 | Service i Ingress | 08, 09 | 5 |
| 5 | Izolacja sieciowa + dowód | 14 | 5 |
| 6 | PDB, strategia i wydanie nowej wersji | 06, 15 | 4 |
| 7 | *(dodatkowe)* warstwa danych na PVC | 07 | 4 |

## Rady

- **Buduj przyrostowo.** Zadanie 3 ma osiem wymagań naraz — dodawaj je po
  jednym i po każdym uruchamiaj `kubectl rollout status`. Gdy coś przestanie
  działać, będzie wiadomo, co doszło ostatnio.
- **Czytaj `describe`, nie zgaduj.** Cała metoda z modułu 12 obowiązuje.
- **Pułapka wbudowana w zadanie 3 i 6.** Rozproszenie replik ma być regułą
  **`preferred`**. Wariant `required` przy dwóch node'ach zakleszcza wdrożenie z `maxSurge: 1`,
  bo nadmiarowa replika nie ma gdzie stanąć. Rollout stanie z komunikatem
  `1 out of 2 new replicas have been updated` i nie ruszy nigdy.
- **Zadanie 5 sprawdza dwie rzeczy naraz**: że obcy Pod **nie** dosięga
  usługi i że ruch przez Ingress **nadal** działa. Zbyt szeroka polityka
  odetnie też kontroler Ingress.
- Pilnuj `ResourceQuota` z zadania 1 — masz limit 10 Podów na cały namespace.

## Sprzątanie

```bash
labctl cleanup 99
```
