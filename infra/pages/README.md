# Pages

Pagine statiche pubblicate con Cloudflare Pages: la pagina di ritorno dal collegamento bancario, l'informativa privacy provvisoria, la pagina degli inviti e `assetlinks.json` per gli App Link di Android. Specifiche: [`docs/spec/sincronizzazione.md`](../../docs/spec/sincronizzazione.md), sezioni 1 e 3; [`docs/spec/accesso.md`](../../docs/spec/accesso.md), A3 e A10; [`docs/spec/navigazione.md`](../../docs/spec/navigazione.md), sezione 2.

Pages pubblica **questa cartella così com'è**: nessuna build, nessuna dipendenza, nessuna risorsa esterna (niente CDN, font remoti o analytics).

## Contenuto

| File | Cosa fa |
|---|---|
| `bank-link/index.html` | Pagina di ritorno (percorso `/bank-link/`): mostra l'esito del collegamento. Senza JavaScript, `<noscript>` mostra il testo generico |
| `bank-link/app.js` | Legge `esito` e `codice` dall'indirizzo, sceglie titolo e testo dalla tabella `TEXTS` in cima al file e toglie la query dall'indirizzo (`history.replaceState`) |
| `bank-link/style.css` | Stile: ruoli colore della palette Teal di [`docs/spec/stile.md`](../../docs/spec/stile.md), tema chiaro e scuro, carattere di sistema |
| `privacy/index.html` | Informativa privacy provvisoria (percorso `/privacy/`, versione `p1`), per le prove tra i membri della casa; l'app la apre da A3 (`PAGES_BASE_URL` + `/privacy/`). Pagina statica, senza script |
| `privacy/style.css` | Stile dell'informativa: gli stessi ruoli colore e lo stesso carattere della pagina di ritorno |
| `invite/index.html` | Pagina degli inviti (percorso `/invite/`), per chi apre il link d'invito senza l'app: istruzioni e codice. Senza JavaScript, `<noscript>` dice di aprire il link dal telefono. Stile e script con percorsi assoluti, perché la stessa pagina risponde anche a `/dev/invite/` |
| `invite/app.js` | Legge `t` e `c` dal frammento dell'indirizzo (`#t=…&c=…`) con la stessa lettura rigida dell'app e mostra il codice in due gruppi da 4; con il frammento mancante o non valido, il testo del link non completo |
| `invite/style.css` | Stile della pagina degli inviti: gli stessi ruoli colore e lo stesso carattere dell'informativa |
| `_redirects` | `/dev/invite/` (link dell'app `dev`) riscritto su `/invite/` con stato 200: l'indirizzo e il frammento restano |
| `index.html` | Radice minima con il solo nome dell'app |
| `robots.txt` | Nessuna pagina da indicizzare |
| `_headers` | Intestazioni di sicurezza (CSP, niente referrer, niente frame), `no-store` per `/bank-link/`, tipo JSON per `assetlinks.json` |
| `.well-known/assetlinks.json` | Associazione con le due app Android, i flavor `prod` (`io.github.davekingdoms.homemade`) e `dev` (`io.github.davekingdoms.homemade.dev`): stessa impronta SHA-256 della firma di rilascio |

### Pagina degli inviti

Il link d'invito (`https://<progetto>.pages.dev/invite/#t=<token>&c=<codice>`, `/dev/invite/` per l'app `dev`) apre l'app quando è installata (App Link) e questa pagina negli altri casi.

- Token e codice stanno nel **frammento**, che il browser non manda al server: non finiscono nei log di Pages né in un `Referer`.
- Il frammento si legge solo come dati: esattamente `t` (43 caratteri base64url) e `c` (8 caratteri dell'alfabeto dei codici, anche minuscoli), una volta ciascuno. Il token non compare mai nella pagina.
- Nessuna chiamata di rete, niente `localStorage` né cookie, nessun log. Il frammento resta nell'indirizzo: ricaricando la pagina il codice si rivede.
- La CSP di `_headers` vale anche qui: niente script né stili inline.

### Pagina di ritorno

`eb-callback` rimanda a `APP_RETURN_URL` (`https://<progetto>.pages.dev/bank-link/`) con `?esito=ok` oppure `?esito=annullato|errore&codice=<codice>`.

- I valori dell'indirizzo servono **solo come chiavi** della tabella `TEXTS`: non finiscono mai nella pagina. Esito o codice sconosciuto, mancante, ripetuto o malformato → testo generico, senza il valore.
- Il codice ("Codice: …") compare solo per i quattro codici noti, preso dalla tabella.
- Nessuna chiamata di rete, niente `localStorage` né cookie, nessun log.
- I testi sono provvisori: si cambiano in `TEXTS`; il testo generico è anche nel blocco `<noscript>` di `bank-link/index.html`.
- Le intestazioni di `_headers` vietano script e stili inline (`'unsafe-inline'` non c'è): stili solo in `style.css`, script solo in `app.js`.

## Prova in locale

Dalla radice del repository, con Node:

```powershell
npx wrangler@latest pages dev infra/pages
```

Wrangler serve la cartella come Pages, intestazioni di `_headers` comprese (di solito su `http://localhost:8788`). Da provare:

- `/bank-link/?esito=ok`
- `/bank-link/?esito=annullato&codice=link_cancelled`
- `/bank-link/?esito=errore&codice=link_expired` (e `link_rejected`, `link_failed`)
- `/bank-link/?esito=errore&codice=<script>`, `/bank-link/?esito=boh`, `/bank-link/` senza parametri
- tema chiaro e scuro, larghezza 320 px; nella console nessun errore CSP; dopo il caricamento l'indirizzo è solo `/bank-link/`
- `/privacy/`: tema chiaro e scuro, larghezza 320 px, nessun errore CSP
- `/invite/#t=AbCdEfGhIjKlMnOpQrStUvWxYz0123456789-_AbCdE&c=K7QMX2PA` (valori inventati): il codice "K7QM X2PA", nessuna traccia del token; lo stesso con `c=k7qmx2pa`
- `/dev/invite/#t=…&c=…` con gli stessi valori: la stessa pagina (riscrittura di `_redirects`), con l'indirizzo invariato
- `/invite/` senza frammento, `/invite/#t=x&c=K7QMX2PA`, `/invite/#c=K7QMX2PA`: il testo del link non completo
- tema chiaro e scuro, larghezza 320 px; nella console nessun errore CSP
- intestazioni: `curl.exe -sI http://localhost:8788/bank-link/` e `curl.exe -sI http://localhost:8788/.well-known/assetlinks.json`

Senza Node, solo per l'aspetto (le intestazioni di `_headers` non si applicano):

```powershell
python -m http.server 8788 --directory infra/pages
```

## Pubblicazione

Progetto Cloudflare Pages collegato al repository, ramo di produzione `main`, cartella di output `infra/pages`, **nessun comando di build**. L'indirizzo è `https://<progetto>.pages.dev`.

`assetlinks.json` contiene solo l'impronta della firma di rilascio, per i due pacchetti; le impronte di debug e della firma delle app di Google Play si aggiungono quando servono. Gli intent filter dell'App Link nell'app (dalla 4.7, per gli inviti) prendono l'host da `PAGES_BASE_URL` e il percorso dal flavor: le build di debug non sono verificate e aprono la pagina nel browser.
