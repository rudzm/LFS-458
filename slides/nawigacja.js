// Przechodzenie między rozdziałami bez wracania do listy.
//
// Marp traktuje każdą talię osobno: na ostatnim slajdzie strzałka w prawo
// po prostu nic nie robi. Ten skrypt domyka tę lukę — na końcu rozdziału
// strzałka przenosi do następnego, na początku wraca do poprzedniego.
//
// Działa w podglądzie (`make watch`) i w HTML-u z `make slides-html`;
// w PDF-ie jest martwy i nieszkodliwy.
(function () {
  'use strict';

  // Kolejność prezentacji = numery plików, czyli numery rozdziałów sylabusa.
  // Trzymamy się ich, bo numer widoczny na slajdzie i w spisie musi zgadzać
  // się z pozycją — lista, w której `07` stoi czternaste, wygląda na zepsutą.
  // Po dołożeniu talii dopisz ją tutaj we właściwym miejscu.
  var ROZDZIALY = [
    '00-kontenery', '01-basics', '02-installation', '03-architecture',
    '04-apis-access', '05-api-objects', '06-deployments', '07-helm-kustomize',
    '08-volumes-data', '09-services', '10-traffic', '11-scheduling',
    '12-logging-troubleshooting', '13-crd', '14-security',
    '15-high-availability', '16-cluster-maintenance', '17-gitops'
  ];

  var plik = decodeURIComponent(location.pathname.split('/').pop() || '');
  var rozszerzenie = plik.slice(plik.lastIndexOf('.'));      // `.md` albo `.html`
  var nazwa = plik.slice(0, plik.lastIndexOf('.'));
  var tu = ROZDZIALY.indexOf(nazwa);
  if (tu === -1) return;                                      // talia spoza listy

  var adres = function (i) {
    return i >= 0 && i < ROZDZIALY.length ? ROZDZIALY[i] + rozszerzenie : null;
  };
  var poprzedni = adres(tu - 1);
  var nastepny = adres(tu + 1);

  var slajdy = function () { return document.querySelectorAll('section'); };
  var numer = function () { return parseInt(location.hash.slice(1), 10) || 1; };

  // Na slajdzie z fragmentami strzałka musi najpierw odsłonić wszystko.
  var wszystkoOdslonieteNaOstatnim = function () {
    var s = slajdy()[slajdy().length - 1];
    if (!s) return false;
    var f = s.querySelectorAll('[data-bespoke-marp-fragment]');
    for (var i = 0; i < f.length; i++) {
      if (f[i].getAttribute('data-bespoke-marp-fragment') !== 'active') return false;
    }
    return true;
  };

  var naKoncu = function () {
    return numer() >= slajdy().length && wszystkoOdslonieteNaOstatnim();
  };
  var naPoczatku = function () { return numer() <= 1; };

  // ── znacznik w rogu: dokąd prowadzi następna strzałka ────────────────────
  var znacznik = document.createElement('a');
  znacznik.style.cssText = [
    'position:fixed', 'right:16px', 'bottom:14px', 'z-index:9999',
    'font:600 13px/1.4 system-ui,sans-serif', 'text-decoration:none',
    'padding:6px 12px', 'border-radius:14px', 'color:#0b3d2c',
    'background:rgba(39,174,96,.16)', 'border:1px solid rgba(39,174,96,.45)',
    'transition:opacity .15s', 'opacity:0', 'pointer-events:none'
  ].join(';');
  document.body.appendChild(znacznik);

  var odswiez = function () {
    if (naKoncu() && nastepny) {
      znacznik.textContent = 'następny rozdział →';
      znacznik.href = nastepny;
      znacznik.style.opacity = '1';
      znacznik.style.pointerEvents = 'auto';
    } else if (naKoncu()) {
      znacznik.textContent = 'spis rozdziałów';
      znacznik.href = './';
      znacznik.style.opacity = '1';
      znacznik.style.pointerEvents = 'auto';
    } else {
      znacznik.style.opacity = '0';
      znacznik.style.pointerEvents = 'none';
    }
  };

  // ── klawiatura ──────────────────────────────────────────────────────────
  var DALEJ = ['ArrowRight', 'PageDown', ' ', 'Spacebar'];
  var WSTECZ = ['ArrowLeft', 'PageUp'];

  document.addEventListener('keydown', function (e) {
    if (e.ctrlKey || e.altKey || e.metaKey) return;

    if (e.key === 'i' || e.key === 'I') {       // `i` — spis rozdziałów
      e.preventDefault();
      location.href = './';
      return;
    }
    if (DALEJ.indexOf(e.key) !== -1 && naKoncu() && nastepny) {
      e.preventDefault();
      e.stopPropagation();
      location.href = nastepny;
      return;
    }
    if (WSTECZ.indexOf(e.key) !== -1 && naPoczatku() && poprzedni) {
      e.preventDefault();
      e.stopPropagation();
      // `#9999` ląduje na ostatnim slajdzie — bespoke przycina numer do zakresu.
      location.href = poprzedni + '#9999';
    }
  }, true);                                     // faza przechwytywania: przed bespoke

  // Znacznik musi reagować na każdą zmianę stanu, nie tylko na klawisz:
  // bespoke odsłania fragmenty, przestawiając atrybut, a do slajdu można
  // też trafić z paska adresu albo kliknięciem.
  window.addEventListener('hashchange', odswiez);
  var obserwator = new MutationObserver(odswiez);
  obserwator.observe(document.body, {
    subtree: true,
    attributes: true,
    attributeFilter: ['data-bespoke-marp-fragment', 'data-bespoke-state']
  });
  setTimeout(odswiez, 150);
})();
