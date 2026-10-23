# Lab 03 — komponenty pod maską

**14 punktów obowiązkowych + 2 dodatkowe**

## Cel

Po tym labie umiesz odpowiedzieć na pytania, które padają przy każdej awarii:
czym jest sieć w tym klastrze, skąd Pod ma adres, kto uruchomił dany kontener
i dlaczego niektórych Podów nie da się usunąć przez `kubectl delete`.

## Node to kontener

Klaster Kind trzyma node'y jako kontenery, więc wchodzisz do nich tak samo jak
do każdego innego:

```bash
docker ps                                  # albo: nerdctl ps
docker exec -it lfs458-worker bash
```

W środku znajdziesz dokładnie to samo, co na maszynie z modułu 02:

```bash
ls /etc/kubernetes/manifests
cat /var/lib/kubelet/config.yaml
crictl ps
ip route
```

> Jeśli używasz Rancher Desktopa w trybie containerd, wszędzie zamiast
> `docker` wpisuj `nerdctl`. `labctl doctor` powie Ci, którego masz.

## Ściągawka

| Chcę | Polecenie |
|---|---|
| pule adresów node'ów | `kubectl get nodes -o custom-columns=WEZEL:.metadata.name,CIDR:.spec.podCIDR` |
| pulę całego klastra | `kubectl -n kube-system get cm kubeadm-config -o yaml \| grep -A4 networking` |
| adres DNS | `kubectl get svc -n kube-system kube-dns` |
| tryb kube-proxy | `kubectl -n kube-system get cm kube-proxy -o yaml \| grep 'mode:'` |
| argumenty apiservera | `kubectl -n kube-system get pod -l component=kube-apiserver -o yaml \| grep secure-port` |
| port kubeleta | `kubectl get node lfs458-worker -o jsonpath='{.status.daemonEndpoints.kubeletEndpoint.Port}'` |
| właściciela Poda | `kubectl get pod <nazwa> -o jsonpath='{.metadata.ownerReferences[0].kind}'` |
| wejść do kontenera w Podzie | `kubectl exec -n <ns> <pod> -c <kontener> -- <polecenie>` |

## Zadania

| # | Zadanie | Pkt |
|---|---|---|
| 1 | Sieć klastra: CNI plugin, pule adresów, DNS, tryb kube-proxy | 3 |
| 2 | Pod `wspolna-siec` — dwa kontenery, dowód wspólnego `localhost` | 3 |
| 3 | Static Pod na `lfs458-worker` — z pominięciem serwera API | 4 |
| 4 | Porty komponentów: apiserver, etcd, kubelet | 2 |
| 5 | *(dodatkowe)* obserwacja: dlaczego static Pod wraca po usunięciu | 2 |
| 6 | **Pytania ABCD** — DNS, pule adresów, komponenty | 2 |

## Na co zwrócić uwagę

- **Zadanie 1** — `podcidr-klastra` to `/16`, a `podcidr-worker` to `/24`.
  Ta różnica nie jest przypadkiem: controller-manager kroi pulę klastra na
  wycinki i przydziela po jednym każdemu node'owi.
- **Zadanie 2** — spróbuj tego samego między dwoma **osobnymi** Podami.
  `localhost` nie zadziała nigdy, nawet gdy oba są na tym samym node'ie.
  To najkrótsza definicja tego, czym Pod się różni od kontenera.
- **Zadanie 3** — nazwa Poda w API to `statyczny-lfs458-worker`, a nie
  `statyczny`. Kubelet dokleja nazwę node'a, żeby mirror pody z różnych node'ów
  się nie zderzały.
- **Zadanie 3** — jeśli Pod się nie pojawia, sprawdź składnię pliku na node'ie:
  `docker exec lfs458-worker cat /etc/kubernetes/manifests/statyczny.yaml`.
  Kubelet nie zgłosi błędu przez API — zobaczysz go tylko w
  `docker exec lfs458-worker journalctl -u kubelet -n 30`.

## Sprzątanie

`labctl cleanup 03` usuwa namespace `lfs458-m03` **oraz** manifesty static Podów
z node'ów. To drugie jest ważne: gdyby plik został, Pod `statyczny` przeżyłby
całe szkolenie i mieszał w kolejnych labach.

```bash
labctl cleanup 03
```
