# Lab 13 — własny zasób w API

**15 punktów obowiązkowych + 3 dodatkowe**

## Cel

Dokładasz do API klastra własny rodzaj obiektu i przekonujesz się, że jest
traktowany dokładnie tak samo jak Pod: ma skróty, kolumny, walidację i RBAC.

## Ściągawka

| Chcę | Polecenie |
|---|---|
| listę CRD | `kubectl get crd` |
| zasoby własnej grupy | `kubectl api-resources --api-group=lfs458.io` |
| stan rejestracji CRD | `kubectl describe crd zadania.lfs458.io` |
| dokumentację własnego pola | `kubectl explain zadanie.spec` |
| sprawdzić walidację bez zapisu | `kubectl apply --dry-run=server -f zle.yaml` |
| API agregowane | `kubectl get apiservices \| grep -v Local` |
| uprawnienia do własnego zasobu | `kubectl auth can-i list zadania --as=…` |

## Zadania

| # | Zadanie | Pkt |
|---|---|---|
| 1 | CRD `zadania.lfs458.io` ze schematem i skrótem | 4 |
| 2 | Obiekt `Zadanie` + dowód działania walidacji | 3 |
| 3 | Kolumny wydruku i podzasób `status` | 3 |
| 4 | RBAC dla własnego zasobu | 3 |
| 5 | *(dodatkowe)* **pytania ABCD** o API agregowane — `metrics.k8s.io` | 3 |
| 6 | **Pytania ABCD** — skrót, apiVersion i zasięg własnego zasobu | 2 |

## Na co zwrócić uwagę

- **Zadanie 1** — nazwa CRD **musi** brzmieć `<liczba mnoga>.<grupa>`.
  Inna nazwa zostanie odrzucona przez API z bardzo konkretnym komunikatem.
- **Zadanie 2** — spróbuj świadomie utworzyć obiekt z priorytetem `9`.
  Odrzucenie przychodzi z **serwera**, nie z `kubectl` — przekonasz się o tym,
  używając `--dry-run=server`.
- **Zadanie 3** — jeśli włączasz `subresources.status`, dodaj do schematu
  także `properties.status`. Bez tego pole zostanie odcięte przy zapisie.
- **Zadanie 4** — utworzenie CRD **nie daje** nikomu do niego dostępu.
  Działasz jako `cluster-admin` tylko dlatego, że masz regułę z gwiazdkami.

## Sprzątanie

Usunięcie CRD kasuje **wszystkie** obiekty tego typu w całym klastrze.
Sprzątanie modułu robi to za Ciebie.
