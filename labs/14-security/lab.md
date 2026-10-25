# Lab 14 — utwardzanie

**22 punkty obowiązkowe + 3 dodatkowe**

## Cel

Kubernetes domyślnie nie jest utwardzony: kontenery działają jako root,
każdy Pod rozmawia z każdym, Secrety leżą w etcd otwartym tekstem.
Dokładasz to, czego brakuje.

**Najważniejsze jest zadanie 4.** Nie wystarczy utworzyć obiekt
`NetworkPolicy` — trzeba sprawdzić, że naprawdę blokuje.

## Ściągawka

| Chcę | Polecenie |
|---|---|
| pola securityContext | `kubectl explain pod.spec.securityContext` |
| UID procesu w kontenerze | `kubectl exec -n lfs458-m14 utwardzony -- id -u` |
| włączyć PSA | `kubectl label ns X pod-security.kubernetes.io/enforce=restricted` |
| sprawdzić odrzucenie | `kubectl run zly --image=nginx --privileged -n X --dry-run=server` |
| polityki sieciowe | `kubectl get netpol -n lfs458-m14` |
| adres IP Poda | `kubectl get pod serwer -n lfs458-m14 -o jsonpath='{.status.podIP}'` |
| test łączności | `kubectl exec -n lfs458-m14 zabroniony -- wget -qO- --timeout=4 http://<IP>:5678` |
| flagi apiservera | `kubectl -n kube-system get pod -l component=kube-apiserver -o yaml \| grep authorization` |

## Zadania

| # | Zadanie | Pkt |
|---|---|---|
| 1 | Utwardzony Pod: nie-root, RO rootfs, `drop: ALL`, seccomp | 4 |
| 2 | Pod Security Admission na poziomie `restricted` | 4 |
| 3 | Scena do testu izolacji: serwer i dwaj klienci | 4 |
| 4 | `NetworkPolicy` + **doświadczalny dowód**, że działa | 4 |
| 5 | *(dodatkowe)* **pytania ABCD** o pluginy admission, kody 401/403 i bramki żądania | 3 |
| 6 | **Pytania ABCD** — uprawnienia, PSA, tryby autoryzacji | 2 |
| 7 | Pluginy admission: włączenie `AlwaysPullImages`, wyłączenie `LimitRanger`, dowód na Podzie | 4 |

## Na co zwrócić uwagę

- **Zadanie 1** — utwardzony kontener często nie wstaje za pierwszym razem.
  To realna cena utwardzania: `readOnlyRootFilesystem` wymaga podmontowania
  `emptyDir` wszędzie tam, gdzie aplikacja pisze. `kubectl describe` powie,
  czego brakuje.
- **Zadanie 2** — wdrażaj PSA stopniowo: najpierw `warn` i `audit`, przeczytaj,
  co się posypie, dopiero potem `enforce`. Na produkcji odwrotna kolejność
  kończy się zablokowanym wdrożeniem.
- **Zadanie 4** — polityka bez CNI plugina, który ją obsługuje, **nie robi nic
  i nie zgłasza błędu**. Obiekt się utworzy, `kubectl get netpol` go pokaże,
  a ruch będzie płynął dalej. Dlatego sprawdzenie wymaga `wget` z obu
  klientów, a nie tylko istnienia obiektu.
- **Zadanie 7** — zmienia flagi apiservera, więc `kubectl` znika na kilkadziesiąt
  sekund i to jest planowe. Uwaga na pułapkę: tuż po zapisaniu manifestu
  odpowiada jeszcze **stary** apiserver. Czy nowy już działa, sprawdzisz we
  flagach mirror Poda (`kubectl -n kube-system get pod -l component=kube-apiserver -o yaml | grep admission`).
  `labctl cleanup 14` przywraca oryginalne flagi z kopii, którą `labctl` zrobił
  przed zadaniem.
- Zrób ten sam eksperyment na każdym nowym klastrze, zanim zaufasz politykom.
  Kilka poleceń odpowiada na pytanie, na które dokumentacja nie odpowie.

## Sprzątanie

```bash
labctl cleanup 14
```
