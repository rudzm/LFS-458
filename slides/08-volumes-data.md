---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · rozdział 8 · Volumes and Data'
---

<!-- _class: tytul -->
<!-- _paginate: false -->

# Volumes and Data

## Rozdział 8 · lab `08`

Gdzie mieszkają dane, które mają przeżyć kontener —
i jak podać konfigurację spoza obrazu

---

# Plan rozdziału

<div data-marpit-fragment>

1. **Przegląd** — dlaczego kontener potrzebuje wolumenu
2. **Volumes** — typy związane z cyklem życia Poda
3. **Persistent Volumes** — PV, PVC, StorageClass
4. **Rook** — pamięć trwała z wnętrza klastra
5. **Przekazywanie danych** — zmienne, ConfigMap, Downward API
6. **Secrety** — typy, trzy sposoby podania, czego nie chronią
7. **Lab 08** — osiem zadań o danych

</div>

---

<!-- _class: sekcja -->

# 1. Dlaczego w ogóle

---

# Warstwa zapisu ginie razem z kontenerem

<div data-marpit-fragment>

```text
  ┌──────────────────────────┐
  │ warstwa zapisu kontenera │  ← znika przy restarcie
  ├──────────────────────────┤
  │ warstwy obrazu (RO)      │  ← niezmienne
  └──────────────────────────┘
```

</div>

* **restart kontenera** w tym samym Podzie → warstwa zapisu znika
* Pod przeniesiony na inny node → tym bardziej
* dwa kontenery w jednym Podzie **nie widzą** nawzajem swoich systemów plików

<div data-marpit-fragment>

| Potrzeba | Odpowiedź |
|---|---|
| wymiana plików między kontenerami Poda | `emptyDir` |
| dane przeżywające restart kontenera | `emptyDir` wystarczy |
| dane przeżywające **usunięcie Poda** | PersistentVolumeClaim |
| konfiguracja spoza obrazu | ConfigMap, Secret |

</div>

---

<!-- _class: sekcja -->

# 2. Volumes

---

# Wolumen deklarujesz raz, montujesz wielokrotnie

<div data-marpit-fragment>

```yaml
spec:
  volumes:                       # deklaracja — raz na Poda
    - name: robocze
      emptyDir: {}
  containers:
    - name: producent
      volumeMounts:              # montowanie — w każdym kontenerze osobno
        - {name: robocze, mountPath: /wyjscie}
    - name: konsument
      volumeMounts:
        - {name: robocze, mountPath: /wejscie}   # inna ścieżka, ten sam wolumen
```

</div>

---

# Cztery typy, które spotkasz najczęściej

<div data-marpit-fragment>

| Typ | Cykl życia | Zastosowanie |
|---|---|---|
| `emptyDir` | **z Podem** | katalog roboczy, wymiana między kontenerami |
| `hostPath` | z node'em | dostęp do plików node'a — **ryzykowne** |
| `configMap`, `secret` | z Podem | konfiguracja jako pliki |
| `persistentVolumeClaim` | **niezależny** | dane, które mają zostać |

</div>

<div data-marpit-fragment>

> `hostPath` to furtka do systemu plików node'a — w produkcji blokuje ją
> Pod Security Admission (rozdział 14).

</div>

---

<!-- _class: sekcja -->

# 3. Persistent Volumes

---

# Trzy obiekty i podział ról

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Deweloper pisze

</div>

<div data-marpit-fragment>

**PersistentVolumeClaim**
*(namespace'owany)*

</div>

<div data-marpit-fragment>

```yaml
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: standard
  resources:
    requests: {storage: 100Mi}
```

</div>

<div data-marpit-fragment>

*„potrzebuję 100 MiB”*

</div>

</div>
<div>

<div data-marpit-fragment>

### Administrator daje

</div>

<div data-marpit-fragment>

**StorageClass** → provisioner
tworzy **PersistentVolume**
*(klastrowy)*

</div>

* jaki backend
* jaka polityka odzyskiwania
* kiedy tworzyć wolumen

</div>
</div>

<div data-marpit-fragment>

```bash
kubectl get pvc,pv -n lfs458-m08
kubectl get storageclass
```

</div>

<div data-marpit-fragment>

> Deweloper **nie musi wiedzieć**, czy pod spodem jest NFS, dysk w chmurze
> czy katalog na node'ie. To jest cała wartość tej abstrakcji.

</div>

---

# Dwie rzeczy, które mylą najczęściej

<div class="kolumny">
<div>

<div data-marpit-fragment>

### `Pending` to nie awaria

</div>

<div data-marpit-fragment>

Domyślna klasa w naszym klastrze ma
`volumeBindingMode:`
**`WaitForFirstConsumer`**

</div>

* PVC czeka, aż **jakiś Pod** go użyje
* dopiero wtedy powstaje PV
* i powstaje **na właściwym node'ie**

</div>
<div>

<div data-marpit-fragment>

### Tryby dostępu

</div>

<div data-marpit-fragment>

| Tryb | Znaczenie |
|---|---|
| `RWO` | jeden **node** zapisuje |
| `ROX` | wiele node'ów czyta |
| `RWX` | wiele node'ów zapisuje |

</div>

<div data-marpit-fragment>

`RWO` ≠ „jeden Pod” — to jeden
**node**. Nie każdy backend
obsługuje `RWX`.

</div>

</div>
</div>

<div data-marpit-fragment>

| Reclaim policy | Co po usunięciu PVC |
|---|---|
| `Delete` *(typowa domyślna)* | PV i dane **znikają** |
| `Retain` | PV zostaje, dane zostają, trzeba posprzątać ręcznie |

</div>

<div data-marpit-fragment>

> Na produkcji dla danych, na których Ci zależy — `Retain`.

</div>

---

# Rook — pamięć trwała z klastra

<div data-marpit-fragment>

Gdy nie masz macierzy ani chmury, a potrzebujesz `RWX` i replikacji:

</div>

* **Rook** to operator, który uruchamia **Ceph** wewnątrz Kubernetesa
* dyski node'ów stają się wspólną pulą pamięci
* udostępnia blok (`RWO`), system plików (`RWX`) i obiekt (S3)
* integruje się przez **CSI**, więc dla Poda wygląda jak każda inna StorageClass

<div class="kolumny">
<div>

<div data-marpit-fragment>

**Zyskujesz**

</div>

* pamięć trwałą bez zewnętrznej macierzy
* replikację i samonaprawę

</div>
<div>

<div data-marpit-fragment>

**Płacisz**

</div>

* znacznym zużyciem CPU i RAM
* operacyjną złożonością Cepha

</div>
</div>

<div data-marpit-fragment>

> Dla trzech node'ów w laborce to przerost formy — dlatego w labie używamy
> provisionera `local-path`. Ale warto wiedzieć, że ta droga istnieje.

</div>

---

<!-- _class: sekcja -->

# 5. Przekazywanie danych do Podów

---

# ConfigMap — dwa kanały, ten sam obiekt

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Jako zmienna

</div>

<div data-marpit-fragment>

```yaml
env:
  - name: TRYB
    valueFrom:
      configMapKeyRef:
        name: ustawienia
        key: TRYB
```

</div>

* pojedyncze klucze
* **nie zmienia się** w działającym
  kontenerze

</div>
<div>

<div data-marpit-fragment>

### Jako pliki

</div>

<div data-marpit-fragment>

```yaml
volumes:
  - name: konf
    configMap: {name: ustawienia}
```

</div>

* każdy klucz = osobny plik
* **aktualizuje się** w locie
  (z opóźnieniem do ~minuty)

</div>
</div>

<div data-marpit-fragment>

```bash
kubectl exec -n lfs458-m08 konfiguracja -- ls -l /etc/ustawienia
# dowiązania symboliczne → tak działa podmiana w locie
```

</div>

<div data-marpit-fragment>

> Różnica praktyczna: jeśli aplikacja ma przeładowywać konfigurację bez
> restartu — montuj jako wolumen. Jeśli nie — zmienne są prostsze.

</div>

---

<!-- _class: sekcja -->

# 6. Secrety

---

# Secret — zakodowany, nie zaszyfrowany

<div data-marpit-fragment>

```bash
kubectl get secret poswiadczenia -o jsonpath='{.data.haslo}' | base64 -d
# tajne123        ← jedno polecenie, żadnego łamania zabezpieczeń
```

</div>

<div data-marpit-fragment>

| Mit | Rzeczywistość |
|---|---|
| „Secret jest bezpieczny” | to `base64`, czyli **kodowanie**, nie szyfrowanie |
| „nikt tego nie odczyta” | odczyta każdy z prawem `get` na Secretach |
| „w etcd jest zaszyfrowane” | **tylko** gdy włączysz `EncryptionConfiguration` |

</div>

<div data-marpit-fragment>

Co robić naprawdę:

</div>

* ograniczyć RBAC do Secretów **nazwa po nazwie**
* włączyć szyfrowanie etcd at rest
* rozważyć zewnętrzny magazyn (Vault, Secrets Store CSI Driver)

---

# Secret ma typ, i typ ma znaczenie

<div data-marpit-fragment>

| Typ | Do czego | Jak utworzyć |
|---|---|---|
| `Opaque` | cokolwiek — hasła, tokeny | `create secret generic` |
| `kubernetes.io/tls` | certyfikat + klucz dla Ingressu | `create secret tls` |
| `kubernetes.io/dockerconfigjson` | prywatny rejestr obrazów | `create secret docker-registry` |
| `kubernetes.io/service-account-token` | token konta — tworzony przez klaster | *(nie ręcznie)* |
| `kubernetes.io/basic-auth`, `ssh-auth` | gotowe schematy pól | `create secret generic --type=` |

</div>

<div data-marpit-fragment>

Typ nie jest etykietą: serwer API **waliduje wymagane klucze**.
`kubernetes.io/tls` bez `tls.crt` i `tls.key` zostanie odrzucony,
a Ingress i kubelet szukają dokładnie tych nazw.

</div>

---

# `stringData` — pisz jawnym tekstem

<div data-marpit-fragment>

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: certyfikat
type: Opaque
stringData:                    # ← jawny tekst, serwer API koduje sam
  haslo: tajne123
  klucz.pem: |
    -----BEGIN PRIVATE KEY-----
```

</div>

<div data-marpit-fragment>

**`stringData` jest tylko do zapisu.** Przy odczycie zobaczysz już `data`
z `base64` — pole zniknie z wyjścia `kubectl get -o yaml`.

</div>

<div data-marpit-fragment>

> Po co, jeśli `data` robi to samo? Bo `echo tajne123 | base64` **dokleja
> znak nowej linii** i aplikacja dostaje hasło z `\n` na końcu.
> To najczęstszy błąd ręcznie pisanych Secretów — i jeden z trudniejszych
> do zdiagnozowania, bo wszystko *wygląda* poprawnie.

</div>

---

# Trzy sposoby podania — i który wybrać

<div class="kolumny">
<div>

<div data-marpit-fragment>

### Zmienna środowiskowa

</div>

<div data-marpit-fragment>

```yaml
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: poswiadczenia
        key: haslo
```

</div>

* zamrożona przy starcie Poda
* **widoczna** w `describe pod`,
  w `/proc/<pid>/environ`
  i w zrzutach awaryjnych

</div>
<div>

<div data-marpit-fragment>

### Wolumen (plik)

</div>

<div data-marpit-fragment>

```yaml
volumes:
  - name: tls
    secret:
      secretName: certyfikat
      defaultMode: 0400
```

</div>

* **odświeżany bez restartu**
* prawa pliku pod kontrolą
* montuj `readOnly: true`

</div>
</div>

<div data-marpit-fragment>

**`imagePullSecrets`** to trzecia ścieżka: sekret do rejestru nie trafia do
kontenera — czyta go **kubelet**, żeby pobrać obraz.

</div>

---

# Wolumen z Secreta — co naprawdę widzi aplikacja

<div data-marpit-fragment>

```bash
$ kubectl exec czytelnik -- ls -la /etc/tls
drwxrwxrwt  3 root root  ..2026_10_18_16_39_01.123
lrwxrwxrwx  1 root root  ..data -> ..2026_10_18_16_39_01.123
lrwxrwxrwx  1 root root  cert.pem -> ..data/cert.pem

$ kubectl exec czytelnik -- ls -lL /etc/tls      # -L: za linkiem
-r--------  1 root root  87  cert.pem
```

</div>

<div data-marpit-fragment>

Katalog z sygnaturą czasu i dwa poziomy linków to mechanizm **atomowej
podmiany**: kubelet tworzy nowy katalog i przestawia link `..data`.
Aplikacja nigdy nie trafia na plik w połowie zapisany.

</div>

<div class="kolumny">
<div>

<div data-marpit-fragment>

**`defaultMode: 0400`**

</div>

<div data-marpit-fragment>

Zapisuj **ósemkowo, z zerem**.
Bez zera `400` to dziesiętnie —
inne prawa, niż chciałeś.
W API i tak zobaczysz `256`.

</div>

</div>
<div>

<div data-marpit-fragment>

**Czego to nie da**

</div>

<div data-marpit-fragment>

`subPath` **wyłącza odświeżanie**.
Montujesz przez `subPath` — wracasz
do semantyki zmiennej środowiskowej.

</div>

</div>
</div>

---

<!-- _class: lab -->

# Lab 08

<div data-marpit-fragment>

**22 punkty + 6 dodatkowych**

</div>

<div data-marpit-fragment>

```bash
labctl lab 08
```

</div>

<div data-marpit-fragment>

Połączysz dwa kontenery wspólnym `emptyDir`, poprosisz o trwały wolumen
i **udowodnisz jego trwałość** — usuwając Pod i tworząc nowy, podasz
konfigurację dwoma kanałami naraz, a Secret **wszystkimi trzema**: jako
zmienne, jako pliki z prawami `0400` i jako `imagePullSecrets`.

</div>

<div data-marpit-fragment>

> PVC w stanie `Pending` przed utworzeniem Poda to **poprawne zachowanie**
> klasy `WaitForFirstConsumer`, nie awaria.

</div>

---

# Co warto zapamiętać

* warstwa zapisu kontenera ginie przy restarcie — stąd wolumeny
* wolumen deklarujesz raz w `spec.volumes`, montujesz w każdym kontenerze osobno
* PVC jest namespace'owany, PV — klastrowy; łączy je StorageClass
* `WaitForFirstConsumer` = `Pending` do czasu użycia przez Pod. To normalne
* `ReadWriteOnce` dotyczy **node'a**, nie Poda
* `Retain` chroni dane przed usunięciem razem z PVC
* ConfigMap i Secret jako wolumen aktualizują się w locie, jako zmienna — nie
  (a `subPath` wyłącza to odświeżanie)
* **Secret to base64**, nie szyfrowanie; typ jest walidowany przez API
* **`stringData` zamiast ręcznego `base64`** — `echo | base64` dokleja `\n`
* plik bije zmienną: nie wycieka przez `describe pod`.
  Montuj `readOnly: true`, ustaw `defaultMode: 0400`

<script src="nawigacja.js"></script>
