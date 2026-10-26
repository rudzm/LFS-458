# Lab 08 — dane w klastrze

**25 punktów obowiązkowych + 6 dodatkowych**

## Cel

Osiem zadań o tym, gdzie mieszkają dane: od katalogu współdzielonego przez dwa
kontenery, przez wolumen przeżywający Pod, po konfigurację i sekrety podane
z zewnątrz obrazu.

Sekretom poświęcone są trzy zadania, bo trzy są sposoby ich podania —
**zmienna środowiskowa**, **plik** i **`imagePullSecrets`** — i różnią się
nie wygodą, a bezpieczeństwem.

## Zanim zaczniesz

```bash
kubectl get storageclass
```

Klaster ma jedną klasę — `standard`, provisioner `local-path`, tryb
**`WaitForFirstConsumer`**. To znaczy, że PVC zostanie w stanie `Pending`,
dopóki nie użyje go jakiś Pod. **To nie jest awaria** i zobaczysz to
w zadaniu 2.

## Ściągawka

| Chcę | Polecenie |
|---|---|
| klasy pamięci | `kubectl get storageclass` |
| PV i PVC | `kubectl get pv,pvc -n lfs458-m08` |
| zdiagnozować PVC | `kubectl describe pvc dane -n lfs458-m08` |
| utworzyć ConfigMapę | `kubectl create configmap ustawienia --from-literal=TRYB=produkcja -n lfs458-m08` |
| utworzyć Secret | `kubectl create secret generic p --from-literal=haslo=tajne -n lfs458-m08` |
| Secret do rejestru | `kubectl create secret docker-registry r --docker-server=… --docker-username=… --docker-password=…` |
| odczytać Secret | `kubectl get secret p -n lfs458-m08 -o jsonpath='{.data.haslo}' \| base64 -d` |
| prawa plików z wolumenu | `kubectl exec -n lfs458-m08 <pod> -- ls -lL /etc/tls` |
| sprawdzić pola wolumenu | `kubectl explain pod.spec.volumes` |
| zajrzeć do kontenera | `kubectl exec -n lfs458-m08 <pod> -- ls -l /sciezka` |

## Zadania

| # | Zadanie | Pkt |
|---|---|---|
| 1 | `emptyDir` jako kanał między dwoma kontenerami | 3 |
| 2 | PVC `dane` + Pod, który zapisuje na nim plik | 4 |
| 3 | ConfigMapa wstrzyknięta **jako zmienna i jako plik naraz** | 4 |
| 4 | Secret podany jako zmienne środowiskowe | 4 |
| 5 | Secret zamontowany jako pliki — `stringData`, `defaultMode` | 4 |
| 6 | Dowód trwałości — nowy Pod, te same dane | 3 |
| 7 | *(dodatkowe)* statyczny PV związany z PVC bez klasy | 3 |
| 8 | *(dodatkowe)* `imagePullSecrets` i typ `dockerconfigjson` | 3 |
| 9 | Downward API — nazwa Poda i node w zmiennych, etykiety w pliku | 3 |

## Na co zwrócić uwagę

- **Zadanie 2** — sprawdzenie celowo **nie zakłada nazwy Poda**, tylko szuka
  dowolnego Poda montującego PVC `dane`. W zadaniu 5 podmienisz Poda,
  a dane mają zostać.
- **Zadanie 3** — to najważniejsze rozróżnienie w module. Zmienna środowiskowa
  jest **zamrożona przy starcie Poda**; plik z wolumenu jest **odświeżany**
  (z opóźnieniem do minuty). Jeśli konfiguracja ma się dać zmieniać bez
  restartu, musi być plikiem. Zajrzyj do `/etc/ustawienia` — zobaczysz
  dowiązania symboliczne, dzięki którym podmiana jest atomowa.
- **Zadanie 4** — po utworzeniu Secreta odkoduj hasło jednym poleceniem.
  `base64` **nie jest szyfrowaniem**. Secret dystrybuuje dane, chroni je
  dopiero RBAC i szyfrowanie etcd (moduł 14).
- **Zadanie 5** — trzy rzeczy, które warto z niego wynieść. `stringData`
  przyjmuje jawny tekst i serwer API koduje go sam, co eliminuje klasyczny
  błąd `echo haslo | base64` (doklejony `\n` w haśle). `defaultMode` zapisuj
  **ósemkowo z zerem** (`0400`) — bez zera dostaniesz liczbę dziesiętną
  i inne prawa, niż zakładasz; w API i tak zobaczysz `256`. A prawa plików
  sprawdzaj przez `ls -lL`, bo bez `-L` patrzysz na link symboliczny.
- **Zadanie 6** — PVC w trybie `ReadWriteOnce` nie pozwoli zamontować wolumenu
  dwóm Podom na różnych node'ach naraz. Usuń stary Pod **przed** utworzeniem
  nowego, inaczej nowy zawiśnie w `Pending`.
- **Zadanie 7** — puste `storageClassName: ""` musi być w **obu** obiektach.
  Pominięcie pola to co innego niż pusty łańcuch: wtedy zadziała klasa domyślna
  i PVC dostanie świeży wolumen zamiast związać się z Twoim.
- **Zadanie 8** — obraz bierzemy publiczny, więc `imagePullSecrets` nie jest
  tu do niczego potrzebne; ćwiczysz **poprawne podłączenie**. W praktyce
  wygodniej dopiąć Secret do ServiceAccounta, niż wpisywać go do każdego Poda.
- **Zadanie 9** — po zmianie etykiety plik z wolumenu `downwardAPI` pokazuje
  nową wartość po kilku sekundach, a zmienna środowiskowa nigdy: dostaje
  wartość raz, przy starcie kontenera. Ta sama różnica co przy ConfigMapie
  z zadania 3.

## Sprzątanie

Sprzątanie usuwa namespace **oraz** statyczny PV — ten drugi jest zasobem
klastrowym i nie zniknąłby razem z namespace'em.

```bash
labctl cleanup 08
```
