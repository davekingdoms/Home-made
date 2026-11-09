# CLAUDE.md

Istruzioni per chi lavora su questo repository, agenti compresi.

## Il progetto

App Flutter per le finanze di una casa con uno o più membri: movimenti importati dalle banche (PSD2), classificazione, quote per membro su ogni riga, conguaglio tra i membri, bilancio. Backend su Supabase. Le specifiche sono in `docs/spec/`.

## Regole

1. **Leggi la specifica in `docs/spec/` prima di scrivere codice.** Se manca o è ambigua, chiedi: non inventare regole di business.
2. **Il repository è pubblico: nessuna informazione personale.** Mai nomi reali, email, telefoni, indirizzi o città, IBAN, numeri di carta (anche mascherati o le ultime 4 cifre), saldi, importi, date, descrizioni o esercenti di movimenti veri, datori di lavoro, dati di salute. Vale per codice, commenti, test, fixture, seed, specifiche, messaggi di commit, nomi dei branch e log della CI.
   - Dati di prova solo **inventati**: membri d'esempio Anna, Bruno, Carla; "Casa di prova"; esercenti, importi e date di fantasia; IBAN e numeri di carta palesemente finti.
   - Le risposte delle banche nei test si **ricostruiscono** sul formato (stessi campi, valori inventati), non si copiano da risposte vere.
   - Se un compito richiede dati reali, fermati e chiedi. I file locali con dati reali stanno in `private/`, che è ignorata da git.
   - Se un dato personale finisce in un commit, non basta un commit che lo cancella: va riscritta la cronologia prima del push.
3. **Mai segreti nel codice.** Chiavi PEM, chiave `service_role`, password del database, keystore e `google-services.json` stanno nel password manager e nei secret della CI o delle Edge Functions. Nell'app solo l'URL e la chiave `anon` di Supabase.
4. **Importi in centesimi interi**, mai numeri decimali in virgola mobile.
5. **Niente logica condivisa nell'app.** Le regole che valgono per più membri (quote, conguaglio, visibilità) stanno in Postgres (schema, RLS, funzioni SQL) e nelle Edge Functions.
6. **Ogni tabella nuova** arriva con le sue policy RLS e i suoi test pgTAP.
7. **Codice in inglese, testi dell'interfaccia in italiano.**
8. **Stile solo da `docs/spec/stile.md`:** nelle schermate si usano i ruoli colore, mai codici esadecimali. Dopo ogni modifica ai token: `python3 tools/contrasti/contrasti.py docs/spec/stile.md`.
9. **Branch e pull request** (GitHub Flow, sezione sotto). `main` è sempre rilasciabile; il merge solo con la CI verde.
10. **CI:** nei log solo esiti (riuscito, fallito), mai dati; nessun dump o dato come artifact dei workflow.

## Branch e pull request

- **Un branch per funzionalità**, creato da `main` aggiornato e di vita breve. Nomi in inglese, minuscoli, con il tipo del commit come prefisso (sezione Commit): `feat/`, `fix/`, `docs/`, `chore/`, `test/`, `refactor/`, `ci/` (es. `feat/cash-reconciliation`). Mai dati personali nei nomi.
- **Su `main` non si fa push diretto:** ogni modifica arriva da una pull request (lo impone il ruleset del repository).
- **Una pull request per funzionalità**, piccola. Titolo e descrizione **in inglese**, e il titolo nel formato Conventional Commits (es. `feat(sync): add bank transaction deduplication`): diventano titolo e testo del merge commit su `main`. Nella descrizione: specifica di riferimento, cosa è stato fatto, come si prova.
- **Nel branch** si può riscrivere la cronologia (rebase, force push) finché la pull request è aperta; su `main` mai.
- **Prima del merge:** branch aggiornato con `main` (tasto "Update branch" o `git merge main`), CI verde, conversazioni risolte.
- **Merge solo con merge commit**, niente squash né rebase: su `main` restano i singoli commit e un merge commit per funzionalità. `git log --first-parent main` mostra una riga per funzionalità; per annullarne una intera basta `git revert -m 1 <merge commit>`.
- Dopo il merge il branch si cancella (impostazione del repository).
- **Rilasci:** tag `vX.Y.Z` su un commit di `main`; i tag `v*` non si spostano né si cancellano.

## Commit

Ogni commit segue [Conventional Commits](https://www.conventionalcommits.org/) ed è scritto **in inglese**.

- **Formato:** `<type>(<scope>): <description>`, con lo scope facoltativo. Descrizione all'imperativo, in minuscolo, senza punto finale, entro 72 caratteri (es. `fix(settlement): round shares with largest remainder`).
- **Tipi:** `feat` (funzionalità nuova), `fix` (correzione), `docs`, `test`, `refactor`, `perf`, `style`, `build`, `ci`, `chore`, `revert`.
- **Scope:** l'area toccata, in inglese (es. `db`, `sync`, `auth`, `settlement`, `theme`, `hub`). Le migrazioni del database usano lo scope `db` (es. `feat(db): add member shares table`).
- **Corpo** (facoltativo, dopo una riga vuota): cosa cambia e perché.
- **Modifiche incompatibili:** `!` dopo il tipo o lo scope (es. `feat(db)!: ...`) e un piè di pagina `BREAKING CHANGE: ...`.
- Commit piccoli e coerenti: uno per passo logico, non uno per file.
- Nessun dato personale nei messaggi (regola 2).

## Comandi

Da aggiungere con lo scheletro dell'app: avvio, test, reset del database locale.
