# Lab 05 — obiekty i uprawnienia

**13 punktów obowiązkowych + 3 dodatkowe**

## Cel

Druga połowa tego laba jest ważniejsza od pierwszej: budujesz ServiceAccount dla
workloadu i nadajesz mu **minimalny** zestaw uprawnień. To czynność, którą
administrator wykonuje co tydzień, a robiona po omacku kończy się rolą
`cluster-admin` dla wszystkiego.

## Ściągawka

| Chcę | Polecenie |
|---|---|
| katalog zasobów | `kubectl api-resources` |
| tylko zasoby klastrowe | `kubectl api-resources --namespaced=false` |
| grupy i wersje API | `kubectl api-versions` |
| utworzyć ServiceAccount | `kubectl create serviceaccount czytelnik -n lfs458-m05` |
| utworzyć Role | `kubectl create role r --verb=get,list --resource=pods -n lfs458-m05` |
| powiązać z SA | `kubectl create rolebinding b --role=r --serviceaccount=lfs458-m05:czytelnik -n lfs458-m05` |
| użyć wbudowanej roli | `kubectl create rolebinding b --clusterrole=view --serviceaccount=…` |
| sprawdzić uprawnienia | `kubectl auth can-i get pods --as=system:serviceaccount:lfs458-m05:czytelnik -n lfs458-m05` |
| pełną listę uprawnień | `kubectl auth can-i --list --as=… -n lfs458-m05` |
| obejrzeć wbudowaną rolę | `kubectl describe clusterrole view` |

## Zadania

| # | Zadanie | Pkt |
|---|---|---|
| 1 | **Pytania ABCD** — apiVersion, zasięg, zapis grupy rdzeniowej | 3 |
| 2 | ServiceAccount + Role + RoleBinding, minimalny zestaw | 4 |
| 3 | Rozszerzenie o `pods/log` i sprawdzenie granic uprawnień | 3 |
| 4 | ClusterRole + ClusterRoleBinding na zasób klastrowy | 3 |
| 5 | *(dodatkowe)* RoleBinding do wbudowanej ClusterRole `view` | 3 |

## Na co zwrócić uwagę

- **Zadanie z pytaniami ABCD** nie wymaga tworzenia niczego — warianty odpowiedzi
  są generowane z Twojego klastra, więc nie da się ich zgadnąć z pamięci.
  Każda odpowiedź jest jednym poleceniem `kubectl` od Ciebie.

- **Zadanie 1, klucz `core-group`** — w regule RBAC grupa rdzeniowa to
  **pusty łańcuch** `""`, a nie `"v1"`. Wpisanie `v1` daje regułę, która
  wygląda poprawnie i nie robi absolutnie nic. To najczęstszy błąd RBAC.
- **Zadanie 3** — podzasoby (`pods/log`, `pods/exec`, `deployments/scale`)
  wymienia się w `resources` **osobno**. Rola na `pods` nie daje prawa do logów.
- **Zadanie 4** — `Role` nigdy nie obejmie node'a, bo `Node` jest zasobem
  klastrowym. Nawet jeśli wpiszesz `nodes` do zwykłej `Role`, API to przyjmie
  i reguła po prostu nic nie da.
- **Zadanie 5** — zwróć uwagę na trzecie sprawdzenie: ta sama `ClusterRole`,
  ale przez `RoleBinding` działa **tylko w jednym namespace**. To najczęstszy
  i najbezpieczniejszy wzorzec RBAC.

## Sprzątanie

Sprzątanie usuwa też obiekty klastrowe (`ClusterRole`, `ClusterRoleBinding`) —
one nie należą do żadnego namespace'u i nie zniknęłyby razem z nim.

```bash
labctl cleanup 05
```
