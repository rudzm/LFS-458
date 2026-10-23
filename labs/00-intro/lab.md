# Jak pracujemy z labami

`labctl` to **jedno narzędzie uruchamiane na Twoim komputerze**, obok klastra,
a nie w środku niego. To celowe: musi umieć tworzyć i kasować klastry, a także
pracować wtedy, gdy klaster jest zepsuty — a takie moduły też będą (moduł 12
jest w całości o naprawianiu, a moduł 02 zaczyna bez klastra).

Praca z modułem wygląda zawsze tak samo:

```bash
labctl lab 01              # treść laba
labctl next 01             # opis następnego zadania
labctl check 01            # po każdym zadaniu: co jest zielone, co nie
labctl check 01 --hint     # nie idzie? kolejna podpowiedź
labctl cleanup 01          # na koniec modułu
```

**O środowisko nie musisz dbać.** Jeśli moduł potrzebuje klastra, którego nie
ma, labctl postawi go sam — powie przy tym, ile to potrwa. Przy module 02,
gdzie stawiane są maszyny wirtualne i trwa to kilkanaście minut, najpierw
zapyta o zgodę.

Zasady, które warto znać od początku:

1. **Każde zadanie sprawdzasz na żywym klastrze.** Weryfikator nie czyta
   Twoich plików — patrzy na to, co naprawdę jest w API. Jak do tego dojdziesz,
   zależy od Ciebie.
2. **Hinty są stopniowane.** Pierwszy naprowadza, ostatni jest prawie gotowym
   poleceniem. `labctl check NN --hint` wydaje po jednym, dla pierwszego
   niezaliczonego zadania.
3. **`labctl cleanup NN` nie kasuje klastra** — usuwa tylko obiekty z danego
   modułu, żeby następny zaczynał na czysto. Klaster `kind-basic` obsługuje
   czternaście z szesnastu modułów i szkoda go stawiać za każdym razem.
   Sam klaster usuwa `labctl env down kind-basic`.
4. **Dwa moduły mają własny krok przygotowania**: 09 (sprawdza Gateway API)
   i 11 (celowo psuje cztery rzeczy, które masz naprawić) — `labctl setup 10`.

Pełna lista poleceń: `labctl --help`. Stan środowisk: `labctl env list`.
Czy stanowisko jest gotowe: `labctl doctor`.

## Co musisz mieć zainstalowane

Platformą docelową szkolenia jest **Linux**. Na macOS-ie wszystko poza modułami
z maszynami wirtualnymi też działa.

| Narzędzie | Do czego | Linux |
|---|---|---|
| **silnik kontenerów** | Kind uruchamia node'y jako kontenery | `sudo apt install docker.io` + dodaj się do grupy `docker` |
| **kind** | klaster w kilkadziesiąt sekund | **wersja 0.26 lub nowsza** — pobierz binarkę z [kind.sigs.k8s.io](https://kind.sigs.k8s.io) |
| **kubectl** | rozmowa z API klastra | [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) |
| **helm** | moduł 07 | [helm.sh/docs/intro/install](https://helm.sh/docs/intro/install/) |
| **jq** | wygodne czytanie JSON-a w kilku labach | `sudo apt install jq` |
| **vagrant** + **VirtualBox** | tylko moduł 02 (kubeadm na maszynach) | `sudo apt install virtualbox` + pakiet Vagranta |

Docker i podobne: labctl wykrywa `docker`, `nerdctl` i `podman` sam. Jeśli masz
Rancher Desktopa w trybie containerd, kind dostanie automatycznie
`KIND_EXPERIMENTAL_PROVIDER=nerdctl` — nie musisz nic ustawiać.

## Zasoby maszyny

| | Minimum | Zalecane |
|---|---|---|
| CPU | 4 rdzenie | 6+ |
| RAM | 8 GiB | 16 GiB |
| Dysk | 20 GiB wolnego | 40 GiB |

Klaster HA (3 × control plane) i maszyny wirtualne pod kubeadm zjadają
zauważalnie więcej. Jeśli masz 8 GiB, usuwaj środowiska, których akurat
nie używasz.

## Co jeszcze doinstaluje się po drodze

Niektóre moduły potrzebują rzeczy, których nie ma w gołym Kubernetesie.
Instaluje je automatycznie `labctl env up` — wypisujemy je tutaj,
żeby nie było niespodzianek, gdy Twoja firma filtruje ruch wychodzący:

| Moduł | Co dochodzi | Skąd |
|---|---|---|
| wszystkie na `kind-basic` | `ingress-nginx`, `metrics-server` | `raw.githubusercontent.com`, `github.com` |
| wszystkie na `kind-basic` | obrazy `nginx`, `busybox`, `http-echo` | `docker.io` |
| wszystkie na `kind-basic` | `cloud-provider-kind` — LoadBalancer i Gateway API | `registry.k8s.io` |

> Kubernetes nie ma wbudowanej obsługi Gateway API — to zestaw CRD-ów plus
> osobny kontroler. Jedno i drugie dostarcza `cloud-provider-kind`, który
> stawiamy razem ze środowiskiem (sekcja niżej). Moduł 13 nie sięga po żadne
> zewnętrzne repozytorium czartów — pracuje na czarcie z `helm create`.

## LoadBalancer i Gateway API — skąd się biorą

Goły Kind nie ma load balancera: Service typu `LoadBalancer` zostałby w stanie
`<pending>`, a Gateway API nie ma w Kubernetesie ani CRD, ani kontrolera.
Jedno i drugie dokłada [`cloud-provider-kind`](https://github.com/kubernetes-sigs/cloud-provider-kind),
które `labctl env up kind-basic` uruchamia **za Ciebie**, jako kontener obok
klastra:

```bash
docker ps --filter name=lfs458-cloud-provider
```

Co z tego wynika:

- Service typu `LoadBalancer` dostaje prawdziwy `EXTERNAL-IP` (moduł 09) —
  na Linuksie osiągalny wprost z hosta, bo to adres z sieci kontenerów Kinda
- `Gateway` z modułu 10 też dostaje własny adres, zamiast wisieć na porcie
  node'a; `GatewayClass` jest już w klastrze, nic nie instalujesz ręcznie

Czego trzeba pilnować:

| Warunek | Szczegół |
|---|---|
| silnik kontenerów | narzędzie jest testowane głównie z **Dockerem na Linuksie** |
| dostępność adresów | na Linuksie `EXTERNAL-IP` jest osiągalny z hosta; na macOS i WSL2 node'y Kinda nie są bezpośrednio widoczne i trzeba uruchomić je z `sudo` |
| objaw awarii | gdy kontener padnie, nowe `LoadBalancer`-y i bramy zostają w `<pending>` bez żadnego błędu — `labctl doctor` to pokaże |
| control plane node'y | jeśli mają obsługiwać ruch: `kubectl label node lfs458-control-plane node.kubernetes.io/exclude-from-external-load-balancers-` |

## Jeśli coś nie działa

| Objaw | Co zrobić |
|---|---|
| `kind create cluster` wisi na „Starting control-plane” | za mało RAM/CPU dla silnika kontenerów — zwiększ i spróbuj ponownie |
| `ErrImagePull` na obrazach z Docker Hub | limit anonimowych pobrań — `docker login` albo poproś trenera o obrazy z cache |
| checki czerwone, choć klaster działa | zły kontekst — `kubectl config use-context kind-lfs458` |
| „trwa już zadanie” przy `labctl env up` | labctl wykonuje naraz tylko jedną operację na środowisku; poczekaj na koniec |
