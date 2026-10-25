# Lab 04 — rozmowa z serwerem API

**12 punktów obowiązkowych + 3 dodatkowe**

## Cel

Przestajesz traktować `kubectl` jak magię. Po tym labie wiesz, jaki adres URL
kryje się za każdym poleceniem, umiesz zadać to samo pytanie `curl`-em
i potrafisz znaleźć dokumentację dowolnego pola bez otwierania przeglądarki.

## Zanim zaczniesz — obejrzyj, co robi kubectl

```bash
kubectl get pods -v=8 2>&1 | grep -E 'GET|Response Status'
```

Zobaczysz pełny adres, nagłówki i kod odpowiedzi. Wróć do tego polecenia
za każdym razem, gdy `kubectl` zachowa się dziwnie.

## Ściągawka

| Chcę | Polecenie |
|---|---|
| zobaczyć surowe żądanie | `kubectl get pods -v=8` |
| odpytać API przez kubectl | `kubectl get --raw /api/v1/namespaces/lfs458-m04/pods` |
| wystawić API na localhost | `kubectl proxy --port=8001 &` (potem `kill %1`) |
| listę zasobów API | `kubectl api-resources` |
| dokumentację pola | `kubectl explain pod.spec.containers.ports` |
| wygenerować szkielet | `kubectl run web --image=nginx --dry-run=client -o yaml` |
| zwalidować bez zapisu | `kubectl apply -f plik.yaml --dry-run=server` |
| wybrane pole obiektu | `kubectl get pod prosty -n lfs458-m04 -o jsonpath='{.spec.nodeName}'` |
| adnotacje obiektu | `kubectl get pod prosty -n lfs458-m04 -o jsonpath='{.metadata.annotations}' \| jq` |

## Zadania

| # | Zadanie | Pkt |
|---|---|---|
| 1 | Pod `prosty` z manifestu — etykiety i nazwany port | 3 |
| 2 | Adnotacje kontra etykiety na tym samym Podzie | 3 |
| 3 | **Pytania ABCD** o odpowiedź API: ścieżka, `kind`, `items`, grupa Deploymentu | 3 |
| 4 | **Pytania ABCD** — wartość domyślna i typ pola, wersja grupy, ścieżka w API | 3 |
| 5 | *(dodatkowe)* Pod utworzony przez `kubectl create --raw` | 3 |

## Na co zwrócić uwagę

- **Zadanie z pytaniami ABCD** nie wymaga tworzenia niczego — warianty odpowiedzi
  są generowane z Twojego klastra, więc nie da się ich zgadnąć z pamięci.
  Każda odpowiedź jest jednym poleceniem `kubectl` od Ciebie.

- **Zadanie 1** — nie pisz z pamięci. `kubectl explain pod.spec.containers.ports`
  poda dokładne nazwy pól szybciej, niż zdążysz sprawdzić w dokumentacji.
- **Zadanie 2** — spróbuj świadomie popełnić błąd: wpisz długi opis jako
  **etykietę**. Komunikat serwera (`must be no more than 63 characters`)
  jest tu lepszym nauczycielem niż jakikolwiek slajd.
- **Zadanie 3** — `kubectl proxy` zajmuje terminal. Uruchom go w tle (`&`)
  albo w drugim oknie i **nie zapomnij zamknąć** (`kill %1`). To API bez
  żadnego uwierzytelniania — na współdzielonej maszynie byłoby to poważne
  otwarcie klastra.
- **Zadanie 5** — `kubectl create --raw` przyjmuje **wyłącznie JSON**. Konwersja:
  `kubectl create -f pod.yaml --dry-run=client -o json`.

## Ciekawostka do sprawdzenia po labie

Porównaj dwa Pody z tego laba:

```bash
kubectl get pod prosty    -n lfs458-m04 -o jsonpath='{.metadata.annotations}' | jq
kubectl get pod przez-api -n lfs458-m04 -o jsonpath='{.metadata.annotations}' | jq
```

`prosty` powstał przez `kubectl apply` i ma adnotację
`kubectl.kubernetes.io/last-applied-configuration` — kopię manifestu, której
`apply` używa do wyliczania różnic. `przez-api` jej nie ma, bo poszedł prosto
do API. To jedyna praktyczna różnica między tymi dwiema drogami.

## Sprzątanie

```bash
labctl cleanup 04
```
