# Lab 12 — napraw to, co zepsute

**28 punktów obowiązkowych + 3 dodatkowe**

## Cel

Po tym labie masz nawyk, a nie listę sztuczek: czytasz stan Poda, potem
zdarzenia, potem logi — i dopiero na końcu zaglądasz do manifestu. Rozpoznajesz
po objawach cztery najczęstsze klasy awarii workloadów: nieosiągalny obraz,
kontener padający przy starcie, Service bez backendów i Pod, którego nie da się
zaplanować.

Druga połowa labu to **awarie samego klastra** — te, których nie naprawisz
przez `kubectl`, bo właśnie `kubectl` przestał działać. Egzamin CKA pyta o nie
osobno i rozwiązuje się je zawsze tak samo: wejdź na node, przeczytaj logi
kontenerów albo kubeleta, popraw manifest statycznego Poda.

## Jak działa ten lab

Odwrotnie niż pozostałe. **`labctl setup 12`** wdraża cztery
obiekty, z których **każdy jest zepsuty inaczej**. Nie budujesz — naprawiasz.

```bash
labctl setup 12        # psuje klaster (można powtórzyć, żeby zacząć od nowa)
```

Zadania **7–9** psują klaster w momencie, w którym do nich dochodzisz —
nie na starcie labu, bo inaczej nie dałoby się zrobić zadań 1–6. Jeśli
`kubectl` przestaje odpowiadać, **to jest treść zadania**, a nie awaria
stanowiska. Wszystko wraca do normy po `labctl cleanup 12`.

## Metoda, nie zgadywanie

Trzymaj się kolejności z wykładu:

```bash
kubectl get pods -n lfs458-m12 -o wide                       # 1. co
kubectl describe pod <nazwa> -n lfs458-m12 | sed -n '/Events/,$p'   # 2. dlaczego
kubectl logs <nazwa> -n lfs458-m12 --previous                # 3. co mówi aplikacja
kubectl get endpointslices -n lfs458-m12                     # 4. czy to sieć
```

**Nie otwieraj manifestów, dopóki nie przeczytasz stanu i zdarzeń.**
Nazwa stanu zwykle sama nazywa problem.

## Ściągawka stanów

| Stan | Pierwszy ruch |
|---|---|
| `ImagePullBackOff` | `describe` → sprawdź pełną nazwę obrazu |
| `CrashLoopBackOff` | **`logs --previous`** |
| `Pending` | `describe` → zdarzenia schedulera |
| `Running` + `0/1` | readinessProbe — `describe` |
| Service bez odpowiedzi | `kubectl get endpointslices` |
| `Pending` **bez zdarzeń** | nie żyje scheduler |
| node `NotReady` | kubelet na tym node'ie — wejdź na node |
| `kubectl` nie łączy się | apiserver — wejdź na node, `crictl logs` |

## Zadania

| # | Co jest zepsute | Pkt |
|---|---|---|
| 1 | Deployment `obrazek` nie wstaje | 3 |
| 2 | Deployment `padajacy` restartuje się w kółko | 4 |
| 3 | Service `sklep` nie kieruje ruchu | 4 |
| 4 | Pod `czekajacy` nigdy nie wystartował | 3 |
| 5 | *(dodatkowe)* odczyt metryk klastra | 3 |
| 6 | **Pytania ABCD** — rozpoznanie awarii po objawach | 2 |
| 7 | **`kubectl` nie odpowiada** — apiserver nie wstaje | 4 |
| 8 | Pod wisi w `Pending`, zdarzenia milczą | 4 |
| 9 | Node `lfs458-worker2` w `NotReady` | 4 |

## Na co zwrócić uwagę

- **Zadanie 2** — zwykłe `kubectl logs` pokaże bieżącą próbę, która może nic
  jeszcze nie wypisać. Komunikat aplikacji jest w logach **poprzedniej**
  instancji, więc potrzebujesz `--previous`.
- **Zadanie 3** — puste `Endpoints` przy działających Podach oznacza jedno:
  selektor Service'u nie pasuje do etykiet. Porównaj obie strony.
- **Zadanie 4** — `spec.nodeSelector` jest polem **niezmiennym**. Żeby je
  usunąć, trzeba Poda odtworzyć. Sprawdzenie pilnuje, żebyś nie obszedł
  problemu, nadając node'om fikcyjną etykietę.
- **Zadanie 7** — tu `kubectl` jest bezużyteczny i o to chodzi. Node klastra
  Kind to kontener, więc wchodzisz do niego przez `docker exec`; na prawdziwym
  klastrze byłoby to `ssh`. Narzędzie do oglądania kontenerów bez API to
  `crictl` — na node'ie jest już skonfigurowane.
- **Zadania 7 i 8** — apiserver i scheduler to **statyczne Pody**: kubelet
  czyta ich manifesty z `/etc/kubernetes/manifests/` i wstaje z nimi bez
  udziału API. Dlatego da się je naprawić, mając tylko powłokę na node'ie —
  zapisany plik działa natychmiast, bez żadnego `kubectl apply`.
- **Zadanie 9** — zanim uruchomisz kubelet, przeczytaj `journalctl -u kubelet`.
  Na egzaminie to właśnie tam jest powód, dla którego usługa nie wstaje.

## Gdy pada control plane — co dalej działa

| Pada | Co przestaje | Co nadal działa |
|---|---|---|
| kube-apiserver | `kubectl`, wszystkie kontrolery | istniejące Pody, Service'y, DNS, ruch |
| kube-scheduler | planowanie **nowych** Podów | wszystko, co już działa |
| kube-controller-manager | Deploymenty, naprawianie replik | istniejące Pody |
| kubelet na node'ie | raportowanie stanu, nowe Pody na tym node'ie | reszta klastra |
| etcd | API staje się bezużyteczne | ruch do działających Podów |

Wniosek praktyczny: **awaria control plane nie zrzuca aplikacji.** Masz czas,
żeby spokojnie zdiagnozować — bez API, przy pomocy:

```bash
docker exec -it lfs458-control-plane bash   # na produkcji: ssh
crictl ps -a                                # kontenery na tym node'ie
crictl logs <id>                            # dlaczego nie wstaje
journalctl -u kubelet -n 50 --no-pager      # co o tym sądzi kubelet
ls /etc/kubernetes/manifests/               # statyczne Pody control plane
```

## Sprzątanie

```bash
labctl cleanup 12
```
