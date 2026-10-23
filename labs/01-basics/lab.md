# Lab 01 — pierwsze spojrzenie na klaster

**12 punktów obowiązkowych + 2 dodatkowe**

## Cel

Po tym labie potrafisz odpowiedzieć na cztery pytania, które będą wracać przez
całe szkolenie:

1. Z ilu maszyn składa się mój klaster i która pełni jaką rolę?
2. Gdzie fizycznie działają komponenty control plane?
3. Co jeszcze działa w klastrze poza samym Kubernetesem i jak to znaleźć?
4. Co się dzieje, gdy stan faktyczny rozjedzie się ze stanem docelowym?

## Przygotowanie

Środowisko tego modułu to **kind-basic**. Jeśli `labctl env list` pokazuje, że
nie stoi — `labctl env up kind-basic` i około trzech minut przerwy. Potem:

```bash
kubectl config use-context kind-lfs458
kubectl get nodes
```

Powinny być widoczne trzy node'y w stanie `Ready`.

## Ściągawka na ten lab

| Chcę | Polecenie |
|---|---|
| listę node'ów z detalami | `kubectl get nodes -o wide` |
| Pody w konkretnym namespace | `kubectl get pods -n kube-system` |
| Pody ze wszystkich namespace'ów | `kubectl get pods -A -o wide` |
| namespace'y | `kubectl get namespaces` |
| etykiety obiektu | `kubectl get ns lfs458-m01 --show-labels` |
| jedno pole obiektu | `kubectl get node <nazwa> -o jsonpath='{.status.nodeInfo.kubeletVersion}'` |
| opis pola API | `kubectl explain deployment.spec.replicas` |
| obserwację zmian na żywo | `kubectl get pods -n lfs458-m01 -w` |

## Zadania

Przez zadania prowadzi `labctl` — pokazuje jedno naraz, sprawdza na Enter
i wydaje podpowiedzi, gdy utkniesz:

```bash
labctl lab 01
```

Jeśli wolisz sprawdzać samodzielnie, bez prowadzenia:

```bash
labctl check 01                    # sprawdź wszystkie zadania
labctl check 01 --task task-4      # sprawdź jedno zadanie
labctl check 01 --watch 10s        # sprawdzaj co 10 s, aż wszystko będzie zielone
```

W skrócie:

| # | Zadanie | Pkt |
|---|---|---|
| 1 | Namespace `lfs458-m01` z etykietą `lfs458.io/modul=01` | 1 |
| 2 | Inwentaryzacja node'ów i komponentów control plane | 3 |
| 3 | Pod aplikacji `kasa` w namespace `sklep-demo` — nazwa, node, obraz | 2 |
| 4 | Deployment `petla` (2× `nginx:1.27-alpine`) i obserwacja samonaprawy | 4 |
| 5 | *(dodatkowe)* skalowanie do 4 replik + adnotacja z obserwacją | 2 |
| 6 | **Pytania o klaster** — cztery pytania ABCD, odpowiedzi szukasz `kubectl`-em | 2 |

## Na co zwrócić uwagę

- **Zadanie 2** — komponenty control plane działają jako *static Pody*. Kubelet
  czyta ich definicje z katalogu `/etc/kubernetes/manifests` na node'ie i uruchamia
  je bez udziału schedulera. Dlatego nie ma dla nich Deploymentu ani ReplicaSetu.
- **Zadanie 4** — po usunięciu Poda przyjrzyj się nazwie tego, który go zastąpił.
  Środkowy człon (hash ReplicaSetu) zostaje bez zmian. To dowód, że odtworzeniem
  zajął się *ten sam* ReplicaSet, a nie Deployment.
- Jeśli check jest czerwony mimo poprawnej konfiguracji, sprawdź, czy Pody zdążyły
  wstać: `kubectl get pods -n lfs458-m01`. Weryfikator patrzy na stan **teraz**.
- **Zadanie 6** jest inne niż pozostałe: nic nie budujesz. Lab sam tworzy obiekty
  w osobnym namespace, a Ty masz je **odczytać** i wybrać odpowiedź. Warianty są
  generowane z Twojego klastra, więc nie da się ich zgadnąć z pamięci — trzeba
  uruchomić polecenie.

## Sprzątanie

Na koniec uruchom **`labctl cleanup 01`** — usunie to namespace
`lfs458-m01` z całą zawartością. Klaster zostaje: korzysta z niego jeszcze
jedenaście kolejnych modułów.

To samo z terminala:

```bash
labctl cleanup 01
```
