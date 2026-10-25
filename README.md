# LFS458 — materiały szkoleniowe

Czterodniowe szkolenie z Kubernetesa: **slajdy** (Markdown → PDF/HTML) i **laby**
sprawdzane automatycznie na żywym klastrze.

```
bin/labctl          narzędzie: środowiska, treść labów, sprawdzanie zadań
labs/NN-nazwa/      jeden moduł: lab.md (treść) + checks.yaml (zadania i checki)
     └─ solutions/  rozwiązania referencyjne — dla trenera i dla testów
slides/             prezentacje w Markdownie: 00-kontenery, 01–15
     └─ theme/      motyw CSS
scripts/            przygotowanie stanowiska
env/kind/           definicje klastrów Kind + dodatki
env/vm/kubeadm/     maszyny Vagranta pod moduł 02
tests/              testy silnika sprawdzającego
```

---

## 1. Jednorazowa instalacja stanowiska

Platforma docelowa to **Linux**. Wymagane:

| Narzędzie | Po co | Jak zdobyć |
|---|---|---|
| silnik kontenerów | Kind uruchamia node'y jako kontenery | `sudo apt install docker.io` + `sudo usermod -aG docker "$USER"` |
| **kind** ≥ 0.26 | klaster szkoleniowy | binarka z [kind.sigs.k8s.io](https://kind.sigs.k8s.io) |
| **kubectl** | rozmowa z API | wersja z linii klastra (dziś v1.37) |
| **helm** | moduł 07 | [helm.sh](https://helm.sh/docs/intro/install/) |
| `jq`, `openssl` | kilka labów | `sudo apt install jq openssl` |
| **vagrant** + **VirtualBox** | tylko moduł 02 | binarka z releases.hashicorp.com + `sudo apt install virtualbox` |
| **marp** | tylko do slajdów | binarka z [marp-cli/releases](https://github.com/marp-team/marp-cli/releases) |

Binarki instaluje jedno polecenie — bez roota, do `~/.local/bin`:

```bash
make doctor     # czego brakuje
make setup      # doinstaluj brakujące (kubectl, kind, helm, marp)
```

Skrypt sprawdza sumy kontrolne tam, gdzie wydawcy je publikują, pomija to,
co już jest w dobrej wersji, a zależności wymagające roota (silnik kontenerów,
VirtualBox) tylko wykrywa i wypisuje gotowe polecenia — sam uprawnień nie podnosi. Po `usermod -aG docker` trzeba się **przelogować**, inaczej
demon jest niewidoczny (`labctl doctor` to wykryje i powie).

VirtualBox dodatkowo wymaga dostępu do sterownika:

```bash
sudo usermod -aG vboxusers "$USER"
```

> **Stanowisko w maszynie wirtualnej?** Moduł 02 uruchamia VirtualBoksa *wewnątrz*
> stanowiska, więc hipernadzorca musi mieć włączoną **wirtualizację zagnieżdżoną**
> (VT-x/AMD-V przekazane do gościa). Reszta modułów używa kontenerów i działa
> bez tego.

Sprawdzenie kompletu:

```bash
./bin/labctl doctor
```

---

## 2. Praca z labem — ścieżka kursanta

Jedno polecenie prowadzi przez cały moduł:

```bash
labctl lab 01
```

Sesja wygląda tak:

1. **przygotowuje środowisko** — stawia klaster, jeśli go nie ma, i mówi,
   ile to potrwa; uruchamia też `setup` modułu, jeśli ten go wymaga
2. **pokazuje jedno zadanie** — tylko to, przy którym jesteś
3. czekasz przy znaku zachęty:

   | Klawisz | Działanie |
   |---|---|
   | **Enter** | sprawdź zadanie |
   | **h** | kolejna podpowiedź (stopniowane) |
   | **r** | rozwiązanie referencyjne |
   | **s** | pomiń zadanie |
   | **q** | wyjdź — postęp zostaje zapisany |

4. po sprawdzeniu od razu widzisz, **co konkretnie jest nie tak**
5. zaliczone zadanie przesuwa Cię dalej samo; niezaliczone zostawia na miejscu
   i możesz sprawdzać ponownie
6. na końcu podsumowanie i przypomnienie o sprzątaniu

Ponowne `labctl lab 01` **wznawia od pierwszego niezaliczonego zadania** —
postęp siedzi w `~/.labctl/progress.json`.

### Gdy nie chcesz sesji

```bash
labctl lab 01 --tekst       # cały materiał naraz (ściągawka, tabela zadań)
labctl check 01             # samo sprawdzenie, bez prowadzenia
labctl check 01 -v          # szczegóły wszystkich zadań, nie tylko bieżącego
labctl next 01              # opis następnego niezaliczonego zadania
labctl cleanup 01           # sprzątanie po module
```

W potoku i w CI (`labctl lab 01 | less`) sesja się nie uruchamia — wtedy
polecenie zachowuje się jak `--tekst`.

**Środowiska nie trzeba stawiać ręcznie.** `lab`, `next`, `check`, `hint` i `setup`
sprawdzają, czego dany moduł wymaga, i stawiają to same — z zapowiedzią, ile
to potrwa. Kursant nie musi pamiętać, że moduł 15 chodzi na innym klastrze niż
reszta, a moduł 02 na maszynach wirtualnych.

| Sytuacja | Zachowanie |
|---|---|
| klaster `kind` nie stoi | stawia od razu (~3 min) i czeka, aż node'y będą `Ready` |
| maszyny modułu 02 nie stoją | **pyta o zgodę** — to kilkanaście minut |
| sesja nieinteraktywna (CI) | drogie środowiska pomija i mówi, co uruchomić |
| nie chcesz automatu | `--no-env` |
| `labctl lab NN --tekst` | tylko wypisuje treść, niczego nie stawia |
| `labctl cleanup NN` | jeśli środowiska nie ma, nie ma czego sprzątać |

Przed stawianiem klastra labctl sprawdza, czy **porty hosta są wolne**
(8080, 8443) i mówi wprost, co je blokuje — zamiast pozwolić kindowi
przerwać tworzenie w połowie.

Przydatne warianty:

| Chcę | Polecenie |
|---|---|
| sprawdzić jedno zadanie | `labctl check 06 --task task-3` |
| sprawdzać w pętli, aż zzielenieje | `labctl check 06 --watch 10s` |
| bez komunikatów o błędach | `labctl check 06 -q` |
| zobaczyć rozwiązanie *(trener)* | `labctl solution 06 --task task-3` |
| przygotować moduł, który tego wymaga | `labctl setup 10` · `labctl setup 12` |

Hinty są **stopniowane**: każde `--hint` wydaje kolejny, pierwszy naprowadza,
ostatni jest prawie gotowym poleceniem. Postęp i zużyte hinty trzymane są
w `~/.labctl/progress.json`.

### Środowiska

| Nazwa | Alias | Moduły | Co to jest |
|---|---|---|---|
| `kind-basic` | `basic` | 14 z 18 | 3 node'y, ingress-nginx, metrics-server, cloud-provider-kind |
| `kind-ha` | `ha` | 15 | 3 × control plane ze stacked etcd + HAProxy |
| `vagrant-kubeadm` | `vm` | 02, 16 | dwie maszyny **bez** klastra, Kubernetes **1.36** |

Maszyny Vagranta celowo startują o jeden minor niżej niż klastry kind
(`K8S_MINOR` w `env/vm/kubeadm/Vagrantfile`): lab 02 stawia na nich klaster
1.36, a lab 16 podnosi go do 1.37 przez `kubeadm upgrade`. Oba laby dzielą
te same maszyny i robi się je jeden po drugim.

Kubeconfig klastra z maszyn **zostaje na `cp`** — kursant pracuje tam przez
`vagrant ssh`, a host nie dostaje nowego kontekstu. Weryfikator łączy się
z maszyną sam: w modułach 02 i 16 `labctl` stawia na początku `PATH` katalog
`scripts/vm-bin`, w którym są dwa skrypty:

- `kubectl` — wykonuje polecenie na `cp` z `/etc/kubernetes/admin.conf`
  (flagę `--context` pomija), więc checki piszą zwykłe `kubectl …`
- `na-maszynie cp|worker '<polecenie>'` — dowolne polecenie na maszynie,
  przez `vagrant ssh --no-tty`

Z tych samych skryptów korzystają rozwiązania wzorcowe 02 i 16.

Na `cp` prowizjonowanie zostawia też `~/kubeadm-config.yaml` — tę samą
instalację co flagi `kubeadm init` z zadania 1, zapisaną w pliku, do pokazania
`kubeadm init --config`.

```bash
labctl env list             # co jest i czy stoi
labctl env up ha            # postaw
labctl env down ha          # usuń
labctl env reset basic      # usuń i postaw od zera
```

`cleanup` przywraca klaster do stanu wyjściowego — sprawdzone: po przejściu
wszystkich modułów i uruchomieniu sprzątania nie zostają ani namespace'y,
ani CRD, ani PV, a etykiety i taints node'ów wracają do pierwotnych. Dlatego
**nie ma potrzeby stawiać klastra od nowa między modułami**. `env reset` jest
wyjściem awaryjnym na sytuację, gdy ktoś namieszał poza labem.

`cleanup` **nie kasuje klastra** — usuwa tylko obiekty danego modułu.
Klaster usuwa dopiero `env down`.

---

## 3. Slajdy

Źródłem jest **zwykły Markdown** w `slides/`, jeden plik na rozdział. Renderuje
go `marp` — pojedyncza binarka, Node **nie jest potrzebny**.

Siedemnaście prezentacji: rozdziały 1–15 plus dwa dodatki spoza sylabusa —
`00-kontenery` *(dla osób bez doświadczenia z kontenerami)* i
`16-cluster-maintenance` *(upgrade klastra, na końcu)*. **Numer rozdziału,
nazwa pliku z prezentacją i numer laba to jedna i ta sama liczba** —
`07-helm-kustomize.md` zapowiada lab `07`, który żyje w
`labs/07-helm-kustomize/` i używa namespace'u `lfs458-m07`.

### Jak zmienić coś w slajdzie

Otwierasz plik w dowolnym edytorze i piszesz Markdown. Slajdy rozdziela `---`
w osobnej linii:

````markdown
---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · rozdział 1 · Basics of Kubernetes'
---

<!-- _class: tytul -->

# Tytuł modułu
## Podtytuł

---

# Zwykły slajd

- punkt pierwszy
- punkt drugi

```bash
kubectl get nodes
```
````

Nagłówek na górze pliku (między pierwszą a drugą linią `---`) ustawia cały plik.
Komentarz `<!-- _class: … -->` dotyczy **tylko tego jednego slajdu**, a
`<!-- class: … -->` (bez podkreślnika) — tego slajdu i wszystkich następnych.

Klasy dostępne w motywie `lfs458`:

| Klasa | Do czego |
|---|---|
| `tytul` | slajd otwierający moduł — ciemne tło |
| `sekcja` | przerywnik między częściami rozdziału |
| `lab` | zapowiedź laba — zielony akcent |
| `ciemny` | odwrócone kolory, np. pod demo w terminalu |

Dwie kolumny:

```markdown
<div class="kolumny">
<div>

**Lewa strona**
- punkt

</div>
<div>

**Prawa strona**
- punkt

</div>
</div>
```

> Puste linie wokół treści w `<div>` są konieczne — bez nich Markdown w środku
> nie zostanie sformatowany.

### Podgląd na żywo

```bash
make watch
```

Otwiera serwer na `http://localhost:8099`; zapisanie pliku odświeża slajd
w przeglądarce. To najwygodniejszy sposób pracy nad treścią.

> **Port podaje się zmienną `PORT`, nie flagą.** `marp-cli` nie ma opcji
> `--port` (`-p` to `--preview`) i po cichu ją zignoruje, zostając na
> domyślnym **8080** — który jest zajęty przez Ingress klastra kind.
> Ręcznie: `PORT=8099 marp --config-file .marprc.yml --server slides`.
> Inny port: `make watch SLIDES_PORT=9000`.

Alternatywa bez terminala: rozszerzenie **Marp for VS Code** daje podgląd obok
edytora i eksport z palety poleceń.

### Ujawnianie treści po kolei

Punktor decyduje o tym, czy lista pojawia się naraz, czy punkt po punkcie:

```markdown
* pojawia się po kolei — jeden punkt na naciśnięcie strzałki
* drugi punkt
* trzeci punkt

- cała lista widoczna od razu
- drugi punkt
```

**Gwiazdka = ujawnianie po kolei, myślnik = wszystko naraz.** Domyślnie
wszystkie listy w slajdach są na gwiazdce. Jeśli gdzieś chcesz mieć całą
listę od razu (bo np. porównujesz pozycje między sobą), zamień `*` na `-`
w tej jednej liście.

Akapity, tabele, cytaty i bloki kodu są owinięte w `div`, bo Marp sam ich
nie fragmentuje:

```markdown
<div data-marpit-fragment>

Ten akapit pojawi się dopiero po naciśnięciu strzałki.

</div>
```

Te znaczniki wstawia i zdejmuje skrypt — nie trzeba ich pisać ręcznie:

```bash
scripts/fragmenty.py                    # oznacz wszystkie talie
scripts/fragmenty.py --cofnij           # zdejmij oznaczenia (bezstratnie)
scripts/fragmenty.py slides/09-services.md   # jedna talia
```

Skrypt pomija **slajdy tytułowe i sekcyjne** (mają pojawiać się w całości),
tytuł slajdu (`#`), podtytuł talii (`##`) oraz listy. Nagłówki `###` i głębsze
**są** fragmentami — zwykle stoją nad kolumną i bez tego wisiałyby nad pustką,
zanim pojawi się to, co opisują. Po dopisaniu nowej treści uruchom go jeszcze raz —
jest idempotentny, a `--cofnij` wraca do czystego Markdowna bit w bit.

### Przechodzenie między rozdziałami

Marp traktuje każdą talię osobno — na ostatnim slajdzie strzałka w prawo
normalnie nic nie robi. [`slides/nawigacja.js`](slides/nawigacja.js) to domyka:

| Klawisz / miejsce | Co się dzieje |
|---|---|
| **→** na ostatnim slajdzie | przechodzi do **następnego rozdziału** |
| **←** na pierwszym slajdzie | wraca na **koniec poprzedniego rozdziału** |
| **`i`** | spis rozdziałów (`http://localhost:8099/`) |
| znacznik w prawym dolnym rogu | pojawia się na końcu talii — można go kliknąć |

Strzałka najpierw odsłania wszystkie fragmenty bieżącego slajdu, a dopiero
potem przechodzi dalej — nie przeskoczysz rozdziału przypadkiem.

Skrypt jest dołączany jedną linią na końcu każdej talii
(`<script src="nawigacja.js"></script>`). Po dodaniu nowej prezentacji
**dopisz jej nazwę do tablicy `ROZDZIALY`** na górze pliku — ona ustala
kolejność. W PDF-ie skrypt nie robi nic.

> Działa w podglądzie na żywo i w HTML-u. **Eksport do PDF pokazuje slajd
> w stanie końcowym** — wszystko widoczne, jedna strona na slajd. To jest
> zamierzone: PDF ma być materiałem do czytania, nie zapisem kliknięć.

### Eksport

```bash
make slides         # wszystkie prezentacje → build/pdf/ (z zakładkami)
make slides-html    # → build/html/ (działa offline, do wysłania kursantom)
```

PDF i PPTX renderuje przeglądarka, więc w systemie musi być Chrome albo
Chromium. HTML powstaje bez przeglądarki.

Pojedynczy plik, z pominięciem Makefile'a:

```bash
marp --config-file .marprc.yml --allow-local-files slides/01-basics.md -o /tmp/01.pdf --pdf
```

### Zmiana wyglądu

Cały wygląd siedzi w [`slides/theme/lfs458.css`](slides/theme/lfs458.css).
Zmienne na górze pliku sterują kolorami i bazowym rozmiarem tekstu:

```css
--akcent:     #2d6cdf;   /* nagłówki, punktory, linki */
--akcent-lab: #1f9d55;   /* wszystko, co dotyczy labów */
font-size: 26px;         /* skala całej prezentacji */
```

Po zapisaniu CSS podgląd z `make watch` odświeży się sam.

### Animacje

| Czego chcesz | Czy marp to umie |
|---|---|
| **przejścia między slajdami** (fade, slide, …) | **tak** — dyrektywa `transition:`, działa w HTML w przeglądarkach z View Transitions API (Chrome/Edge) |
| **animacje CSS** (np. podświetlenie elementu) | tak — zwykły `@keyframes` w motywie; odpalają się przy wejściu na slajd, nie na klik |
| **pojawianie się punktów po kolei (klik po kliku)** | **nie ma natywnie** — patrz obejście niżej |
| animacje PowerPointa | tylko po eksporcie do PPTX i ręcznym dodaniu |

Przejścia ustawia się tak:

```markdown
---
marp: true
transition: fade        # dla całej prezentacji
---

# Slajd

---

<!-- transition: slide -->   <!-- tylko dla tego przejścia -->

# Następny
```

Eksport do HTML z przejściami:

```bash
marp --bespoke.transition slides/01-basics.md -o build/html/01-basics.html
```

**Pojawianie się punktów po kolei** marp obsługuje w jeden sposób: przez
powielenie slajdu, gdzie każda kopia pokazuje o punkt więcej. Brzmi topornie,
ale ma zaletę — działa wszędzie, także w PDF-ie:

```markdown
# Pętla sterowania

- obserwuj stan faktyczny

---

# Pętla sterowania

- obserwuj stan faktyczny
- porównaj ze stanem docelowym

---

# Pętla sterowania

- obserwuj stan faktyczny
- porównaj ze stanem docelowym
- podejmij działanie
```

Jeśli animacje mają być naprawdę bogate, sensowniej zrobić **jeden** taki slajd
w PowerPoincie niż przepisywać całość:

```bash
marp --pptx --pptx-editable slides/01-basics.md -o /tmp/01.pptx
```

Różnica jest zasadnicza i warto ją znać **przed** eksportem:

| | zwykły `--pptx` | `--pptx-editable` |
|---|---|---|
| zawartość slajdu | obrazek PNG | prawdziwe pola tekstowe |
| rozmiar (2 slajdy) | ~120 KB | ~9 KB |
| edycja w PowerPoincie | niemożliwa | normalna |
| animacje na elementach | niemożliwe | możliwe |
| wymaga | przeglądarki | przeglądarki **i LibreOffice** |

Flaga jest oznaczona jako eksperymentalna, a sam marp ostrzega, że wierność
odwzorowania zależy od LibreOffice. Pamiętaj też, że od momentu edycji w
PowerPoincie to **PPTX staje się źródłem prawdy**, a nie Markdown — więc rób to
dla pojedynczych slajdów, nie dla całych rozdziałów.

---

## 4. Konwencja językowa

Materiały są po polsku, ale terminologia Kubernetesa **nie jest tłumaczona na
siłę**. Kryterium jest praktyczne: kursant ma czytać to samo słowo, które za
chwilę wpisze do manifestu albo zobaczy na egzaminie.

| Kategoria | Reguła | Przykłady |
|---|---|---|
| Nazwy obiektów, pól i komponentów | **zawsze angielskie** | `Pod`, `Deployment`, `kubelet`, `tolerations`, `readinessProbe` |
| Terminy branżowe funkcjonujące po angielsku | **angielskie**, polski gloss kursywą w nawiasie przy pierwszym użyciu w rozdziale | `reconciliation loop` *(pętla uzgadniania)*, `desired state` *(stan docelowy)*, `worker node`, `node`, `API server`, `CNI plugin`, `canary deployment` |
| Słowa z naturalnym polskim odpowiednikiem | po polsku | klaster, etykieta, selektor, sieć, wolumen |
| Opisy, a nie terminy | po polsku | „magazyn stanu klastra" zamiast „baza stanu" |

Cztery zasady, które wynikły z przeglądu i warto o nich pamiętać:

1. **Nie rozbijaj par.** „control plane i węzły robocze" to najgorszy wariant —
   jedna połowa po angielsku, druga spolszczona. Ma być `control plane`
   i `worker node`.
2. **Nie tłumacz nazw obiektów API.** `Node` jest obiektem tak samo jak `Pod`
   — skoro nie mówimy „strąk", nie mówimy też „węzeł". Odmieniamy je po polsku:
   `node'a`, `node'ów`, `na node'ie`, tak jak `Poda` i `namespace'u`.
3. **Nie tłumacz tego, co jest polem w manifeście.** `toleration` i `probe`
   zostają po angielsku właśnie dlatego, że w YAML-u stoi `tolerations:`
   i `readinessProbe:`. „Tolerancja" i „sonda" tworzą rozjazd dokładnie tam,
   gdzie ma powstać odruch.
4. **Nie sklejaj hybryd.** „wtyczka CNI" i „anty-affinity" to pół-tłumaczenia —
   ma być `CNI plugin` i `anti-affinity`. Co innego **odmiana** angielskiego
   terminu po polsku: `static Pody`, `Podów`, `namespace'u`, `Service'u` są
   w porządku i tak się mówi w praktyce.

Ponieważ angielskie rzeczowniki się nie odmieniają, czasem trzeba przestawić
zdanie zamiast podmieniać wyraz:

| Zamiast | Lepiej |
|---|---|
| „sama tolerancja nie wystarczy" | „sam wpis `toleration` nie wystarczy" |
| „bez tolerancji taintu" | „bez `toleration` dla taintu" |
| „ustawiono obie sondy" | „ustawiono `readinessProbe` i `livenessProbe`" |

### Kalki z angielskiego

Osobna pułapka, niezależna od terminologii: **dosłownie przetłumaczony idiom**.
Nie chodzi o termin techniczny, tylko o zwrot, który po polsku nic nie znaczy
albo znaczy co innego.

| Kalka | Co z nią nie tak | Zamiast tego |
|---|---|---|
| „reguła kciuka" | *rule of thumb* — po polsku nie funkcjonuje | „w skrócie", „prosta zasada" |
| „z pudełka" | *out of the box* | „w standardzie", „gotowe" |
| „bez przerwy" o wdrożeniu | po polsku znaczy **nieprzerwanie**, nie *zero-downtime* | „bez przestoju" |
| „wspiera" o funkcji | *supports* — po polsku wspiera się kogoś, nie funkcję | „obsługuje" |
| „na koniec dnia" | *at the end of the day* | „ostatecznie", „w praktyce" |
| „obciążenie" o aplikacji | po polsku znaczy **zużycie zasobów**, nie *workload* | `workload` |
| „tożsamość dla obciążenia" | *identity for workload* | `ServiceAccount` albo `identity` |

Wyjątki — te same słowa bywają poprawne w innym znaczeniu:

| Zostaje | Dlaczego |
|---|---|
| „wspierana wersja" | chodzi o wsparcie producenta, nie o obsługę funkcji |
| „węzeł obciążony w 10%" | tu naprawdę chodzi o **zużycie zasobów** |
| „dostawca tożsamości" | ustalony polski odpowiednik *identity provider* |

---

## 5. Modyfikacja labów

Jeden moduł to katalog `labs/NN-nazwa/`:

- **`lab.md`** — treść dla kursanta: cel, ściągawka, tabela zadań, uwagi
- **`checks.yaml`** — metadane, zadania, hinty, rozwiązania i **checki**
- **`solutions/solution.sh`** — rozwiązanie referencyjne, przechodzące cały moduł

Check może mieć trzy postaci:

```yaml
# 1. stan obiektu w API
- name: "Deployment ma 3 gotowe repliki"
  resource: {apiVersion: apps/v1, kind: Deployment, namespace: lfs458-m06, name: sklep}
  assert:
    - path: "{.status.readyReplicas}"      # składnia jsonpath kubectl
      op: eq
      value: 3
      message: "poczekaj, aż wszystkie repliki będą Ready"

# 2. skrypt — gdy trzeba czegoś dowieść, a nie tylko odczytać
- name: "zabroniony klient jest naprawdę odcięty"
  exec:
    timeout: 90s
    script: |
      ...
    stdoutMatches: "WYNIK: połączenie zablokowane"

# 3. zapytanie HTTP
- name: "usługa odpowiada przez Ingress"
  http: {url: "http://localhost:8080/", host: "sklep.lfs458.local", expectStatus: 200}
```

Czwarta postać to **zadanie quizowe** — zamiast checków ma pytania
wielokrotnego wyboru:

```yaml
  - id: task-6
    points: 2
    description: |
      **Odczytaj klaster, zamiast go budować.**
    quiz:
      przygotuj:                  # opcjonalnie: lab tworzy obiekty, o które pyta
        script: |
          kubectl create deployment inwentaryzacja --image=nginx:1.26-alpine -n X
      pytania:
        - pytanie: "Jak nazywa się Pod w namespace `X`?"
          odpowiedz:
            script: |             # POPRAWNA ODPOWIEDŹ LICZONA Z KLASTRA
              kubectl get pods -n X -o jsonpath='{.items[0].metadata.name}'
          mylne: ["literalny wariant", "..."]
          mylne_z:
            script: |             # albo warianty też wyliczone z klastra
              kubectl get pods -n kube-system -o jsonpath='{.items[*].metadata.name}'
          wskazowka: "kubectl get pods -n X"
```

### Zadania, które najpierw psują albo budują

`przygotuj` nie jest zarezerwowane dla quizów — ma je **każde** zadanie.
Krok uruchamia się tuż przed pokazaniem treści i musi być **idempotentny**,
bo kursant wraca do zadania po każdym nieudanym sprawdzeniu:

```yaml
  - id: task-7
    points: 4
    przygotuj:
      opis: "psuję serwer API — za chwilę stracisz kubectl…"
      timeout: 3m
      script: |
        ...   # kopia zapasowa + celowa awaria
```

Z tego korzystają zadania naprawcze modułu 12 (apiserver, scheduler,
kubelet). Psucie siedzi w zadaniu, a nie w `setup` modułu — inaczej
`kubectl` padłby, zanim kursant zobaczy zadania 1–6.

Moduł, w którym API **ma** bywać nieosiągalne, deklaruje to na swoim
poziomie:

```yaml
apiBywaNiedostepne: true
```

Bez tej flagi `labctl` potraktowałby brak połączenia jako awarię stanowiska.
Z nią tłumaczy kursantowi, że taki jest plan, i podpowiada wejście na node'a.
`cleanup` takiego modułu musi przywracać stan wyjściowy **i czekać na powrót
API**, zanim ruszy dalsze kroki — inaczej usuwanie namespace'ów trafia
w martwy apiserver.

Poprawnej odpowiedzi **nie wpisuje się do pliku** — liczy ją `odpowiedz.script`
na żywym klastrze. Dzięki temu nie dezaktualizuje się przy losowym sufiksie
Poda ani przy zmianie wersji obrazu, a kursant musi uruchomić polecenie,
bo warianty pochodzą z jego własnego klastra.

Zadania quizowe odbywają się w sesji `labctl lab NN`; `labctl check NN`
pokazuje je jako `0/4 pytań` i odsyła do sesji, bo odpowiedzi padają przy
klawiaturze, a nie w klastrze.

Dwie zasady pisania pytań:

- **odpowiedź i każdy wariant to jedno słowo** — `labctl` dzieli wyjście
  skryptów na białych znakach, więc `w pamięci` dałoby dwa warianty.
  Stąd odpowiedzi w rodzaju `etcd`, `10.96.0.10`, `Node,RBAC`
- **po złej odpowiedzi `labctl` nie zdradza dobrej** — kursant ma dojść do niej
  sam, sprawdzając w klastrze albo prosząc o `wskazowka` pod `?`. Dlatego
  `wskazowka` mówi, *gdzie* szukać, a nie *co* jest odpowiedzią

Pytania o to, co kursant odczytuje z klastra, robimy jako quiz. Arkusz
`~/odpowiedzi/lab-NN.txt` (czytany przez `scripts/odpowiedz.sh`) zostaje tylko
tam, gdzie wpis jest częścią zadania praktycznego, np. fraza z logu
w zadaniu naprawczym.

> **Pułapka:** w skryptach checków nie używaj `grep -E '(?i)…'`. GNU grep nie
> zna tej składni i check nie przejdzie nigdy. Wielkość liter ignoruje
> `grep -qiE`. W `stdoutMatches` `(?i)` działa, bo to wyrażenie Pythona.

Operatory checków: `eq`, `matches`, `contains`, `oneOf`, `gt`, `gte`, `lt`, `lte`,
`exists`, `notExists`. Do tego `quantifier` (`all`/`any`/`none`) dla ścieżek
zwracających wiele wartości i `count` dla liczby trafień.

Po każdej zmianie:

```bash
make test        # testy silnika + walidacja materiałów (bez klastra)
```

Walidacja pilnuje m.in. zgodności punktów w `lab.md` z `checks.yaml`, kompletności
mapowania rozdziałów sylabusa i bitu wykonywalności skryptów.

Pełny test modułu na żywym klastrze:

```bash
labctl setup 12 && bash labs/12-troubleshooting/solutions/solution.sh && labctl check 12
```

Pojedyncze zadanie: `labctl check 12 --task 7` (albo `--task task-7`).
Literówka w numerze kończy się komunikatem, nie cichym „moduł zaliczony".

---

## 6. Gdy coś nie działa

| Objaw | Przyczyna i co zrobić |
|---|---|
| `labctl doctor`: „demon działa, ale ta sesja nie ma grupy `docker`" | przeloguj się albo `newgrp docker` |
| wszystkie checki czerwone z „context … does not exist" | środowisko nie stoi: `labctl env up kind-basic` |
| w modułach 02 i 16 „brak połączenia z klastrem na maszynie cp” | przed `kubeadm init` w zadaniu 1 modułu 02 tak ma być; potem sprawdź `vagrant status` w `env/vm/kubeadm` |
| `kind create cluster` wisi na „Starting control-plane" | za mało RAM/CPU dla silnika kontenerów |
| `ErrImagePull` na obrazach z Docker Hub | limit anonimowych pobrań — `docker login` albo obrazy z cache |
| Service typu LoadBalancer zostaje `<pending>` | padł `lfs458-cloud-provider`: `docker ps --filter name=lfs458-cloud-provider` |
| maszyna Vagranta wisi w bootcie (`rcu_preempt stalls`) | głodzenie CPU przy równoległym prowizjonowaniu — `vagrant halt -f <maszyna> && vagrant up <maszyna>` |
| `make slides` kończy się błędem przeglądarki | brak Chrome/Chromium — HTML (`make slides-html`) działa bez niego |

---

## 7. Przed szkoleniem

Dzień wcześniej, na każdym stanowisku:

```bash
./bin/labctl doctor
./bin/labctl env up kind-basic        # ~3 min
./bin/labctl env up vagrant-kubeadm   # kilkanaście minut — zrób z wyprzedzeniem
```

### Uwagi dla trenera

- **Dzień 1 jest najbardziej napięty** — po dodaniu rozdziału 0 wychodzi pięć
  wykładów zamiast czterech. Jeśli zabraknie czasu, najprościej przenieść
  **lab 04** (*APIs and Access*) na początek dnia 2: rozdział 5 bezpośrednio
  z niego korzysta, więc kolejność pozostaje logiczna. Alternatywa — przejść
  rozdział 0 w wersji powtórkowej, do czego jest przygotowany.
- **Dzień 4 jest najcięższy**: trzy rozdziały plus capstone. Gdy dni 1–3 się
  przesuną, najpierw skróć capstone (`99`) — pierwsze trzy zadania mają sens
  samodzielnie, resztę można zostawić jako pracę własną.
- **Moduł 02 puść przed przerwą.** Prowizjonowanie dwóch maszyn na stanowisko
  trwa długo, a osiem stanowisk ściągających naraz obraz systemu to dobry
  moment na kawę.
- **Capstone (`99`) idzie na sam koniec**, po `15` i `16`: korzysta
  z PodDisruptionBudgetu z rozdziału 15. Kolejność dnia 4 to
  `14` → `15` → `16` → `99`. Moduł 15 wymaga drugiego klastra (`kind-ha`),
  16 — maszyn Vagranta, a capstone znów `kind-basic`; przy 8 GiB RAM zdejmij
  `kind-ha` przed `labctl lab 99`.
- **Moduł 12 psuje klaster celowo** — i to dwa razy. `labctl setup 12` wdraża
  cztery zepsute obiekty, a zadania 7–9 psują **control plane**: serwer API,
  scheduler i kubeleta na `lfs458-worker2`. Awaria dzieje się dopiero w chwili
  wejścia w dane zadanie, więc zadania 1–6 da się zrobić normalnie.
  **Uprzedź grupę, że utrata `kubectl` w zadaniu 7 jest treścią zadania** —
  inaczej ktoś zacznie resetować klaster. `labctl cleanup 12` przywraca
  wszystko; `labctl env reset basic` jest wyjściem awaryjnym.
- **Lab 16 (Cluster Maintenance) to upgrade klastra** na maszynach Vagranta —
  tych samych, co lab 02. Maszyny startują na Kubernetes **1.36**, kursanci
  podnoszą je do **1.37**. Rozdział zamyka szkolenie, więc maszyny z laba 02
  zdążą do tego czasu zniknąć; `labctl` postawi nowe, ale to kilkanaście
  minut — warto puścić je przed przerwą.
- **Zadania dodatkowe** (`optional`) są dla osób, które skończyły wcześniej —
  nie wchodzą do sumy punktów i można je pominąć bez szkody dla kolejnych modułów.

### Obrazy ściągane po drodze

Przydaje się, gdy sieć w firmie filtruje ruch wychodzący: `kindest/node`,
`nginx`, `busybox`, `hashicorp/http-echo`, `registry.k8s.io/cloud-provider-kind/*`,
`registry.k8s.io/metrics-server/*`, `registry.k8s.io/ingress-nginx/*`
oraz `quay.io/cilium/*` (moduł 02, pobierane na maszyny przy `vagrant up`).
