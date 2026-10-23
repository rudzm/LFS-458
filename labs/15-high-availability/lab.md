# Lab 15 — wysoka dostępność

**13 punktów obowiązkowych + 3 dodatkowe**

## Cel

Po tym labie wiesz, ile instancji etcd musi odpowiadać, żeby klaster przyjmował
zapisy, ile awarii przeżyje Twoja topologia, jak zrobić i **zweryfikować** kopię
zapasową etcd — oraz czego ta kopia nie zawiera.

## Środowisko

Jedyny moduł na klastrze **`kind-ha`**: trzy control plane node'y ze stacked
etcd, za load balancerem HAProxy, którego Kind stawia sam.

```bash
labctl env down kind-basic     # jeśli masz 8 GiB RAM
labctl env up kind-ha
kubectl config use-context kind-lfs458-ha
```

> Dwa klastry Kind naraz potrafią wyczerpać limity systemowe (najczęściej
> `inotify`). Objaw: `too many open files` przy dołączaniu node'ów.
> Wtedy usuń klaster podstawowy i spróbuj ponownie.

## Ściągawka

| Chcę | Polecenie |
|---|---|
| control plane node'y | `kubectl get nodes -l node-role.kubernetes.io/control-plane` |
| Pody etcd | `kubectl -n kube-system get pod -l component=etcd` |
| load balancer Kind | `docker ps \| grep haproxy` |
| wejść do etcd | `kubectl -n kube-system exec <pod-etcd> -- etcdctl …` |
| listę członków | `etcdctl … member list -w table` |
| kopię zapasową | `etcdctl … snapshot save /tmp/etcd-backup.db` |
| sprawdzić kopię | `etcdutl snapshot status /tmp/etcd-backup.db -w table` |

Zestaw flag do każdego wywołania `etcdctl`:

```bash
--endpoints=https://127.0.0.1:2379 \
--cacert=/etc/kubernetes/pki/etcd/ca.crt \
--cert=/etc/kubernetes/pki/etcd/server.crt \
--key=/etc/kubernetes/pki/etcd/server.key
```

## Zadania

| # | Zadanie | Pkt |
|---|---|---|
| 1 | **Pytania ABCD** o topologię i kworum | 4 |
| 2 | Lista członków etcd | 4 |
| 3 | Kopia zapasowa i jej weryfikacja | 5 |
| 4 | *(dodatkowe)* `PodDisruptionBudget` | 3 |

## Na co zwrócić uwagę

- **Zadanie 2** — `etcdctl` **nie jest** zainstalowany na node'ie. Znajduje się
  w obrazie etcd, więc wchodzi się do niego przez `kubectl exec`.
- **Zadanie 3** — obraz etcd jest *distroless*: nie ma w nim powłoki, `ls`
  ani `wc`. Zostają same binarki `etcdctl` i `etcdutl`. To dobra ilustracja
  tego, o czym mówiliśmy w module 12 przy `kubectl debug`.
- **Zadanie 3, klucz `czego-nie-obejmuje`** — najważniejsza rzecz z modułu.
  Kopia etcd odtworzy **opis** aplikacji, ale nie jej **dane**: zawartość
  PersistentVolume nie wróci. Do tego służy Velero albo migawki macierzy.
- **Zadanie 4** — klaster nie ma worker node'ów, więc najpierw zdejmij
  `taint` z control plane, tak jak w module 02.

## Sprzątanie

```bash
labctl cleanup 15
labctl env down kind-ha
labctl env up kind-basic       # przywróć klaster do capstone'u
```
