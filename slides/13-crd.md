---
marp: true
theme: lfs458
paginate: true
footer: 'LFS458 · rozdział 13 · Custom Resource Definition'
---

<!-- _class: tytul -->
<!-- _paginate: false -->

# Custom Resource Definition

## Rozdział 13 · lab `13`

Jak dołożyć własny rodzaj obiektu do API —
bez zmieniania czegokolwiek w Kubernetesie

---

# Plan rozdziału

<div data-marpit-fragment>

1. **Przegląd** — po co rozszerzać API
2. **CRD** — rejestracja własnego zasobu
3. **Operatory** — CRD plus kontroler
4. **Aggregated API** — druga droga rozszerzania
5. **Lab 13** — własny zasób w API klastra

</div>

---

<!-- _class: sekcja -->

# 1. Po co rozszerzać API

---

# Dlaczego nie ConfigMapa

<div data-marpit-fragment>

Masz własny obiekt do opisania — powiedzmy bazę danych do uruchomienia.
Mógłbyś wrzucić to do ConfigMapy jako tekst. Co tracisz:

</div>

<div data-marpit-fragment>

| Z ConfigMapą | Z własnym zasobem |
|---|---|
| walidacja: **żadna** | schemat OpenAPI, odrzucenie przy zapisie |
| `kubectl get bazy` | działa, z własnymi kolumnami |
| RBAC: na wszystkie ConfigMapy | osobne uprawnienia na ten typ |
| `kubectl explain` | działa |
| obserwowanie zmian (`watch`) | działa jak dla każdego obiektu |

</div>

<div data-marpit-fragment>

> Kubernetes to w dużej mierze **baza danych z reconciliation loops**.
> CRD pozwala dołożyć do niej własną tabelę — a resztę mechanizmów
> dostajesz za darmo.

</div>

---

<!-- _class: sekcja -->

# 2. CustomResourceDefinition

---

# Rejestracja nowego rodzaju

<div data-marpit-fragment>

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: zadania.lfs458.io          # MUSI być <plural>.<grupa>
spec:
  group: lfs458.io
  scope: Namespaced                # albo Cluster
  names: {plural: zadania, singular: zadanie, kind: Zadanie, shortNames: [zad]}
  versions:
    - name: v1
      served: true                 # obsługiwana przez API
      storage: true                # w tej wersji zapisywana w etcd
```

</div>

<div data-marpit-fragment>

> Nazwa CRD musi brzmieć dokładnie `<liczba mnoga>.<grupa>` — to wymóg.

</div>

---

# Schemat robi całą robotę

<div data-marpit-fragment>

```yaml
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              required: [opis]
              properties:
                opis:      {type: string, minLength: 3}
                priorytet: {type: integer, minimum: 1, maximum: 5, default: 3}
```

</div>

<div data-marpit-fragment>

```bash
kubectl apply -f zle-zadanie.yaml
# Error: spec.priorytet in body should be less than or equal to 5
```

</div>

---

# Co daje schemat

* walidację wykonuje **apiserver**, nie `kubectl` — dlatego sprawdzisz ją
  przez `--dry-run=server`, a nie `--dry-run=client`
* `default` wypełnia pole, gdy nikt go nie podał
* pola **spoza schematu są odcinane** przy zapisie, bez ostrzeżenia

<div data-marpit-fragment>

> Schemat to nie ozdoba. Bez niego trzeba włączyć
> `x-kubernetes-preserve-unknown-fields`, a obiekt staje się workiem na
> dowolny YAML: API przyjmie wszystko, a błąd wyjdzie dopiero w kontrolerze,
> który ma to przeczytać.

</div>

---

# Wygody, których oczekujesz od zasobu wbudowanego

<div data-marpit-fragment>

```yaml
      subresources:
        status: {}                 # osobna ścieżka /status
      additionalPrinterColumns:
        - {name: Opis,      type: string,  jsonPath: .spec.opis}
        - {name: Priorytet, type: integer, jsonPath: .spec.priorytet}
```

</div>

<div data-marpit-fragment>

```bash
kubectl get zadania -n lfs458-m13
# NAME         OPIS                  PRIORYTET
# sprzatanie   Posprzatac po labie   2
```

</div>

<div data-marpit-fragment>

| Dodatek | Co daje |
|---|---|
| `shortNames` | `kubectl get zad` |
| `additionalPrinterColumns` | własne kolumny zamiast samej nazwy i wieku |
| `subresources.status` | rozdzielenie uprawnień: użytkownik pisze `spec`, kontroler `status` |
| `categories: [all]` | zasób pojawi się w `kubectl get all` |

</div>

---

<!-- _class: sekcja -->

# 3. Operatory

---

# CRD opisuje, kontroler działa

<div data-marpit-fragment>

```text
   CRD           ← nowy rodzaj obiektu w API   (deklaracja)
    +
   kontroler     ← reconciliation loop dla niego (działanie)
    =
   operator
```

</div>

<div data-marpit-fragment>

Sam CRD to **tylko miejsce na dane**. Bez kontrolera utworzysz obiekt
`Zadanie` i nic się nie wydarzy — dokładnie tak jest w labie 13.

</div>

<div data-marpit-fragment>

Operator zamyka w kodzie wiedzę administratora: jak postawić klaster bazy,
jak zrobić kopię i ją odtworzyć, jak zaktualizować wersję bez przestoju.

</div>

<div data-marpit-fragment>

> Przykłady: Prometheus Operator, Rook (rozdział 8), cert-manager.
> **Gateway API też działa na CRD.**

</div>

---

<!-- _class: sekcja -->

# 4. Aggregated API

---

# Druga droga: aggregated API server

<div data-marpit-fragment>

| | **CRD** | **Aggregated API** |
|---|---|---|
| co dostarczasz | plik YAML | **działający serwer HTTPS** |
| przechowywanie | etcd klastra | dowolne — własne |
| walidacja | schemat OpenAPI | dowolny kod |
| trudność | minuty | projekt programistyczny |
| typowe użycie | 95% przypadków | metryki, rzeczy nieskładowalne w etcd |

</div>

<div data-marpit-fragment>

```bash
kubectl get apiservices | grep -v Local
# v1beta1.metrics.k8s.io   kube-system/metrics-server   True
```

</div>

<div data-marpit-fragment>

> **metrics-server jest aggregated API** — dlatego `kubectl top` działa
> jak zwykłe zapytanie do API, choć żadne metryki nie leżą w etcd.
> Zaczynaj od CRD; po aggregated API sięgaj, gdy CRD naprawdę nie wystarcza.

</div>

---

<!-- _class: lab -->

# Lab 13

<div data-marpit-fragment>

**15 punktów + 3 dodatkowe**

</div>

<div data-marpit-fragment>

```bash
labctl lab 13
```

</div>

<div data-marpit-fragment>

Zarejestrujesz zasób `Zadanie` ze schematem wymuszającym opis i zakres
priorytetu, utworzysz obiekt i **sprawdzisz, że walidacja działa**
po stronie serwera, dołożysz kolumny i podzasób `status`,
a na koniec nadasz na ten typ osobne uprawnienia RBAC.

</div>

<div data-marpit-fragment>

```bash
kubectl get crd
kubectl api-resources --api-group=lfs458.io
kubectl get zad -n lfs458-m13
```

</div>

<div data-marpit-fragment>

> Usunięcie CRD kasuje **wszystkie** obiekty tego typu. Nieodwracalnie.

</div>

---

# Co warto zapamiętać

* CRD dokłada rodzaj obiektu do API bez zmian w samym Kubernetesie
* nazwa CRD to zawsze `<liczba mnoga>.<grupa>`
* walidację wykonuje **apiserver**; pola spoza schematu są odcinane
* `shortNames`, kolumny i podzasób `status` sprawiają, że zasób zachowuje się
  jak wbudowany
* **CRD + kontroler = operator**; sam CRD niczego nie uruchamia
* aggregated API to własny serwer — `metrics-server` jest tego przykładem
* usunięcie CRD kasuje wszystkie obiekty tego typu

<script src="nawigacja.js"></script>
