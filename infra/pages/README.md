# Pages

Pagine statiche pubblicate con Cloudflare Pages: la pagina di ritorno dal collegamento bancario e `assetlinks.json` per gli App Link di Android. Specifica: [`docs/spec/sincronizzazione.md`](../../docs/spec/sincronizzazione.md), sezioni 1 e 3.

Pages pubblica **questa cartella così com'è**: nessuna build, nessuna dipendenza, nessuna risorsa esterna (niente CDN, font remoti o analytics).

## Contenuto

| File | Cosa fa |
|---|---|
| `bank-link/index.html` | Pagina di ritorno (percorso `/bank-link/`): mostra l'esito del collegamento. Senza JavaScript, `<noscript>` mostra il testo generico |
| `bank-link/app.js` | Legge `esito` e `codice` dall'indirizzo, sceglie titolo e testo dalla tabella `TEXTS` in cima al file e toglie la query dall'indirizzo (`history.replaceState`) |
| `bank-link/style.css` | Stile: ruoli colore della palette Teal di [`docs/spec/stile.md`](../../docs/spec/stile.md), tema chiaro e scuro, carattere di sistema |
| `index.html` | Radice minima con il solo nome dell'app |
| `robots.txt` | Nessuna pagina da indicizzare |
| `_headers` | Intestazioni di sicurezza (CSP, niente referrer, niente frame), `no-store` per `/bank-link/`, tipo JSON per `assetlinks.json` |
| `.well-known/assetlinks.json` | Associazione con l'app Android (impronta SHA-256 della firma di rilascio) |

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
- intestazioni: `curl.exe -sI http://localhost:8788/bank-link/` e `curl.exe -sI http://localhost:8788/.well-known/assetlinks.json`

Senza Node, solo per l'aspetto (le intestazioni di `_headers` non si applicano):

```powershell
python -m http.server 8788 --directory infra/pages
```

## Pubblicazione

Progetto Cloudflare Pages collegato al repository, ramo di produzione `main`, cartella di output `infra/pages`, **nessun comando di build**. L'indirizzo è `https://<progetto>.pages.dev`.

`assetlinks.json` contiene solo l'impronta della firma di rilascio; le impronte di debug e della firma delle app di Google Play si aggiungono quando servono. Gli intent filter dell'App Link nell'app arrivano con l'iterazione 4.
