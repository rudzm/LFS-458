# Lab 11 — sterowanie rozmieszczeniem

**25 punktów obowiązkowych + 3 dodatkowe**

## Cel

Pięć mechanizmów decydujących o tym, gdzie wyląduje Pod. Każdy daje efekt
widoczny natychmiast — trzymaj otwarte:

```bash
kubectl get pods -n lfs458-m11 -o wide
```

## Ściągawka

| Chcę | Polecenie |
|---|---|
| etykiety node'ów | `kubectl get nodes --show-labels` |
| nadać etykietę node'owi | `kubectl label node lfs458-worker2 dysk=ssd` |
| taints node'ów | `kubectl get nodes -o custom-columns=WEZEL:.metadata.name,TAINTS:.spec.taints` |
| nałożyć taint | `kubectl taint node lfs458-worker2 gpu=true:NoSchedule` |
| zdjąć taint | `kubectl taint node lfs458-worker2 gpu:NoSchedule-` |
| czemu Pending | `kubectl describe pod za-duzy -n lfs458-m11 \| sed -n '/Events/,$p'` |
| zajętość node'a | `kubectl describe node lfs458-worker \| sed -n '/Allocated/,/Events/p'` |
| klasa QoS Poda | `kubectl get pod X -o jsonpath='{.status.qosClass}'` |

## Zadania

| # | Zadanie | Pkt |
|---|---|---|
| 1 | Etykieta node'a + `nodeSelector` | 3 |
| 2 | Pod nie do zaplanowania i odczytanie powodu | 3 |
| 3 | Rozproszenie replik regułą anti-affinity | 4 |
| 4 | `taint` + `toleration` | 4 |
| 5 | *(dodatkowe)* `preferred`, czyli preferencja bez blokowania | 3 |
| 6 | **Pytania ABCD** — taints, efekty, gdzie stanie Pod | 2 |
| 7 | HPA dla Deploymentu `skalowany` i skalowanie pod ruchem | 4 |
| 8 | **Pytania ABCD** — klasy QoS i Pod z nieobsługiwanym `schedulerName` | 2 |
| 9 | PriorityClass `lfs458-wazne` i Pod, który z niej korzysta | 3 |

## Na co zwrócić uwagę

- **Zadanie 1** — nie wpisuj `nodeName`. To omija schedulera razem z jego
  zabezpieczeniami; chodzi o to, żeby scheduler **sam** wybrał node.
- **Zadanie 2** — Pod w `Pending` jest **zamierzony**. Zdarzenia schedulera
  podają wprost, ile node'ów odpadło i dlaczego. To najbardziej konkretny
  komunikat w całym Kubernetesie.
- **Zadanie 3** — dwie repliki, nie trzy. Zwykłe Pody nie trafiają na control plane node, więc przy regule `required` trzecia wisiałaby w `Pending`
  na zawsze. To pułapka anti-affinity w wariancie `required`.
- **Zadanie 4** — `toleration` to **zgoda**, nie przyciąganie. Sam wpis
  pozwoli Podowi wylądować gdziekolwiek; żeby trafił na konkretny node,
  potrzebny jest jeszcze `nodeSelector`.
- **Zadanie 7** — przez pierwszą minutę HPA pokazuje `<unknown>`: metrics-server
  jeszcze nie zebrał danych. W górę skaluje po kilkudziesięciu sekundach ruchu,
  w dół dopiero po około 5 minutach — to celowe opóźnienie, nie awaria.
- **Zadanie 8** — Pod z samymi `limits` ma klasę Guaranteed, bo apiserver
  przepisał `limits` do `requests`. A Pod `sierota` nie ma żadnych zdarzeń:
  żaden scheduler nie obsługuje jego `schedulerName`, więc nikt go nie widzi.
- **Zadanie 9** — `spec.priority` wpisuje apiserver przy tworzeniu Poda.
  Pod utworzony przed PriorityClass nie dostanie priorytetu — trzeba go
  utworzyć od nowa.

## Sprzątanie

Sprzątanie zdejmuje też etykiety i taints z node'ów — inaczej zostałyby
na kolejne moduły.
