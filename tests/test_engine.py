"""Testy semantyki asercji — na wzorcach wyjętych z prawdziwych checks.yaml."""
import importlib.util, sys
spec = importlib.util.spec_from_loader("lfs458", None)
m = importlib.util.module_from_spec(spec)
src = open("bin/labctl", encoding="utf-8").read()
src = src.replace('if __name__ == "__main__":', 'if False:')
m.__dict__["__file__"] = "bin/labctl"
m.__dict__["__name__"] = "lfs458_pod_testem"
exec(compile(src, "lfs458", "exec"), m.__dict__)

ok = bad = 0
def t(opis, got, want):
    global ok, bad
    if got == want:
        ok += 1
    else:
        bad += 1
        print(f"  ✗ {opis}: dostałem {got!r}, chciałem {want!r}")

C = m.compare

# ── eq, także dla liczb i booli zapisanych w YAML-u różnie ────────────────────
t("eq string",            C(["Active"], "eq", "Active", "all"), True)
t("eq liczba jako int",   C(["80"], "eq", 80, "all"), True)
t("eq zero",              C(["0"], "eq", 0, "all"), True)
t("eq bool z YAML",       C(["true"], "eq", True, "all"), True)
t("eq bool jako string",  C(["true"], "eq", "true", "all"), True)
t("eq nie pasuje",        C(["Pending"], "eq", "Running", "all"), False)

# ── matches: wzorce RE2 z klasami POSIX (moduł 04) ───────────────────────────
mail = r"^[^@[:space:]]+@[^@[:space:]]+\.[a-zA-Z]{2,}$"
t("e-mail poprawny",      C(["zespol-platformy@example.com"], "matches", mail, "all"), True)
t("e-mail ze spacją",     C(["zespol platformy@example.com"], "matches", mail, "all"), False)
t("e-mail bez domeny",    C(["admin@localhost"], "matches", mail, "all"), False)
t("opis >63 znaki",       C(["x"*70], "matches", "^.{64,}$", "all"), True)
t("opis <63 znaki",       C(["x"*40], "matches", "^.{64,}$", "all"), False)
t("wersja vX.Y.Z",        C(["v1.37.0"], "matches", r"^v1\.[0-9]+\.[0-9]+", "all"), True)
t("(?i) bez rozmiaru",    C(["Insufficient memory"], "matches", "(?i)insufficient +memory", "all"), True)
t("CA data RRRR-MM-DD",   C(["2036-08-21"], "matches", "^20[0-9]{2}-[0-1][0-9]-[0-3][0-9]$", "all"), True)
t("grupa rdzeniowa \"\"", C(['""'], "matches", '^""$', "all"), True)

# ── oneOf: value jako lista rozdzielona przecinkami (moduły 03, 05, 09, 12) ──
t("oneOf trafia",         C(["iptables"], "oneOf", "iptables, ipvs, nftables", "all"), True)
t("oneOf nie trafia",     C(["kernelspace"], "oneOf", "iptables, ipvs, nftables", "all"), False)
t("oneOf wszystkie verby",C(["get","list","watch"], "oneOf", "get, list, watch", "all"), True)
t("oneOf z nadmiarem",    C(["get","delete"], "oneOf", "get, list, watch", "all"), False)

# ── kwantyfikatory, w tym pusty wynik ────────────────────────────────────────
t("all po wielu",         C(["Running","Running"], "eq", "Running", "all"), True)
t("all z jednym złym",    C(["Running","Pending"], "eq", "Running", "all"), False)
t("any trafia",           C(["a","b","nginx:1.27-alpine"], "eq", "nginx:1.27-alpine", "any"), True)
t("none na pustym",       C([], "eq", "CrashLoopBackOff", "none"), True)
t("none gdy jest",        C(["CrashLoopBackOff"], "eq", "CrashLoopBackOff", "none"), False)
t("none gdy czegoś innego",C(["Running"], "eq", "CrashLoopBackOff", "none"), True)
t("all na pustym = fałsz",C([], "eq", "Running", "all"), False)

# ── porównania liczbowe (rewizje, repliki) ───────────────────────────────────
t("gte rewizja 3>=2",     C(["3"], "gte", 2, "all"), True)
t("gte rewizja 1>=2",     C(["1"], "gte", 2, "all"), False)
t("gt priorytet 9>5",     C(["9"], "gt", 5, "all"), True)
t("none dla gt (walidacja CRD)", C(["2","3"], "gt", 5, "none"), True)

# ── values_of: sklejanie wyników jsonpath ────────────────────────────────────
V = m.values_of
t("[*] rozdziela spacją",  V("a b c", "{.items[*].metadata.name}"), ["a","b","c"])
t("pojedyncza wartość",    V("Active", "{.status.phase}"), ["Active"])
t("wartość ze spacją",     V("wydanie api-v2", "{.metadata.annotations['x']}"), ["wydanie api-v2"])
t("pusty wynik",           V("", "{.spec.taints[*].key}"), [])

# ── budowa argumentów kubectl: liczba mnoga w Kubernetesie bywa nieregularna ──
# Regresja: naiwne kind+"s" dawało `ingresss`, `networkpolicys` i `zadanies`,
# czyli wywracało moduły 09, 12, 14 i capstone.
R = lambda **kw: " ".join(m.resource_args(kw))
t("Pod → pod",                R(kind="Pod", apiVersion="v1", name="x"), "get pod x")
t("Deployment → .apps",       R(kind="Deployment", apiVersion="apps/v1", name="x"),
                              "get deployment.apps x")
t("Ingress bez 'ingresss'",   R(kind="Ingress", apiVersion="networking.k8s.io/v1", name="x"),
                              "get ingress.networking.k8s.io x")
t("NetworkPolicy poprawnie",  R(kind="NetworkPolicy", apiVersion="networking.k8s.io/v1", name="x"),
                              "get networkpolicy.networking.k8s.io x")
t("zasób własny (CRD)",       R(kind="Zadanie", apiVersion="lfs458.io/v1", name="x"),
                              "get zadanie.lfs458.io x")
t("labelSelector",            R(kind="Pod", apiVersion="v1", labelSelector="app=x", namespace="n"),
                              "get pod -l app=x -n n")
t("allNamespaces",            R(kind="DaemonSet", apiVersion="apps/v1", allNamespaces=True),
                              "get daemonset.apps -A")

# ── asercje bez `op`, z samym `count` (18 takich w materiałach) ──────────────
# Regresja: silnik woła compare() tylko wtedy, gdy `op` jest podane. Bez tego
# checki w rodzaju „Deployment utworzył ReplicaSet" wywalały cały moduł.
import types
A = m.check_assert
def fake_kubectl(ctx, args, timeout=30):
    # udajemy trzy obiekty zwrócone przez jsonpath {.items[*].metadata.name}
    return 0, "petla-abc petla-def petla-ghi", ""
_oryg = m.kubectl
m.kubectl = fake_kubectl
res = {"apiVersion": "apps/v1", "kind": "ReplicaSet", "namespace": "x"}
t("count-only: gte 1 przy 3",   A("c", res, {"path": "{.items[*].metadata.name}",
                                             "count": {"op": "gte", "value": 1}})[0], True)
t("count-only: eq 3 przy 3",    A("c", res, {"path": "{.items[*].metadata.name}",
                                             "count": {"op": "eq", "value": 3}})[0], True)
t("count-only: eq 2 przy 3",    A("c", res, {"path": "{.items[*].metadata.name}",
                                             "count": {"op": "eq", "value": 2}})[0], False)
t("bez op i bez count = błąd",  A("c", res, {"path": "{.items[*].metadata.name}"})[0], False)
m.kubectl = _oryg

# ── checker HTTP: 308 bez podążania za przekierowaniem ──────────────────────
# Regresja: domyślny urllib szedł za 308 na https://<host>/, czego DNS nie
# rozwiązuje, i check modułu 09 wywracał się zamiast zobaczyć kod 308.
import http.server, threading, socket

class _Serwer(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/przekieruj":
            self.send_response(308)
            self.send_header("Location", "https://nie-ma-takiej-nazwy.invalid/")
            self.end_headers()
        else:
            tresc = b"to-jest-sklep\n"
            self.send_response(200)
            self.send_header("Content-Length", str(len(tresc)))
            self.end_headers()
            self.wfile.write(tresc)
    def log_message(self, *a):
        pass

_gniazdo = socket.socket(); _gniazdo.bind(("127.0.0.1", 0))
_port = _gniazdo.getsockname()[1]; _gniazdo.close()
_srv = http.server.HTTPServer(("127.0.0.1", _port), _Serwer)
threading.Thread(target=_srv.serve_forever, daemon=True).start()

H = m.check_http
t("http 200 + bodyMatches",
  H({"http": {"url": f"http://127.0.0.1:{_port}/", "expectStatus": 200,
              "bodyMatches": "to-jest-sklep", "timeout": "5s"}})[0], True)
t("http 308 widoczny, bez przekierowania",
  H({"http": {"url": f"http://127.0.0.1:{_port}/przekieruj", "expectStatus": 308,
              "timeout": "5s"}})[0], True)
t("http zły status wyłapany",
  H({"http": {"url": f"http://127.0.0.1:{_port}/", "expectStatus": 404,
              "timeout": "5s"}})[0], False)
t("http nagłówek Host przechodzi",
  H({"http": {"url": f"http://127.0.0.1:{_port}/", "host": "sklep.lfs458.local",
              "expectStatus": 200, "timeout": "5s"}})[0], True)
t("insecure buduje kontekst bez weryfikacji",
  H({"http": {"url": f"http://127.0.0.1:{_port}/", "expectStatus": 200,
              "insecure": True, "timeout": "5s"}})[0], True)
_srv.shutdown()

# ── timeouty z checks.yaml ───────────────────────────────────────────────────
P = m.parse_timeout
t("40s", P("40s"), 40); t("3m", P("3m"), 180); t("15m", P("15m"), 900); t("2m", P("2m"), 120)

print(f"\n  {ok} przeszło, {bad} nie przeszło")
sys.exit(1 if bad else 0)
