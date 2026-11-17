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
3. **Nessun segreto nel repository, né in chiaro né cifrato.** La fonte unica è il password manager.
   - **Sul PC** i valori stanno in `private/` (ignorata da git) e arrivano all'app con `--dart-define-from-file`; il modello delle chiavi è `app/env.example.json`, con soli segnaposto.
   - **In CI** stanno nei secrets degli environment `dev` e `prod` di GitHub Actions; i file si salvano come base64, si ricostruiscono nel job e non si caricano mai come artifact.
   - **Lato server** stanno nei secrets delle Edge Functions e in Supabase Vault.
   - **Nell'app** solo valori pubblici per natura (URL e chiave publishable di Supabase, client ID OAuth), comunque fuori dal repository: nel codice si scrivono solo i nomi delle variabili.
   - **Mai**, in nessun file del repository né nell'app: chiave `service_role`, password del database, chiavi private, keystore.
   - **In caso di fuga:** rotazione immediata del segreto; cancellarlo dal repository non basta.
4. **Importi in centesimi interi**, mai numeri decimali in virgola mobile.
5. **Niente logica condivisa nell'app.** Le regole che valgono per più membri (quote, conguaglio, visibilità) stanno in Postgres (schema, RLS, funzioni SQL) e nelle Edge Functions.
6. **Ogni tabella nuova** arriva con le sue policy RLS e i suoi test pgTAP.
7. **Codice in inglese, testi dell'interfaccia in italiano.** Unica eccezione: i campi di `AppColors` e i token di `lib/theme/tokens.dart` tengono i nomi italiani di `docs/spec/stile.md` (`testoTerziario`, `banda`, `suPrimarioTenue`, `avviso`, `credito`, `debito`, `nastroGiallo`, `nastroNero`).
8. **Stile solo da `docs/spec/stile.md`:** nelle schermate si usano i ruoli colore, mai codici esadecimali. Dopo ogni modifica ai token: `python tools/contrasti/contrasti.py docs/spec/stile.md`.
9. **Branch e pull request** (GitHub Flow, sezione sotto). `main` è sempre rilasciabile; il merge solo con la CI verde: i controlli obbligatori sono `gitleaks`, `app`, `golden`, `tokens` e `database` (sezione CI).
10. **CI:** nei log solo esiti (riuscito, fallito), mai dati; nessun dump o dato come artifact dei workflow.
11. **Non leggere né copiare il contenuto di `private/`.** I file che contiene li legge solo la build; se serve sapere cosa c'è dentro, chiedi. Claude Code si avvia dalla radice del repository, dove vale `.claude/settings.json`, che nega lettura e modifica di `private/`.
12. **Analisi con `very_good_analysis`:** `fvm flutter analyze` deve dare zero problemi prima di ogni commit, e il codice deve essere formattato (`fvm dart format .`). Nessuna regola si disattiva senza chiedere.
13. **Il codice generato non si committa:** `*.g.dart` e `*.freezed.dart` sono in `.gitignore`. Dopo ogni checkout o pull si rigenerano con `build_runner`; la CI li genera da sola.

## Branch e pull request

- **Un branch per funzionalità**, creato da `main` aggiornato e di vita breve. Nomi in inglese, minuscoli, con il tipo del commit come prefisso (sezione Commit): `feat/`, `fix/`, `docs/`, `chore/`, `test/`, `refactor/`, `ci/` (es. `feat/cash-reconciliation`). Mai dati personali nei nomi.
- **Su `main` non si fa push diretto:** ogni modifica arriva da una pull request (lo impone il ruleset del repository).
- **Una pull request per funzionalità**, piccola. Titolo e descrizione **in inglese**, e il titolo nel formato Conventional Commits (es. `feat(sync): add bank transaction deduplication`): diventano titolo e testo del merge commit su `main`. Nella descrizione: specifica di riferimento, cosa è stato fatto, come si prova.
- **Nel branch** si può riscrivere la cronologia (rebase, force push) finché la pull request è aperta; su `main` mai.
- **Prima del merge:** branch aggiornato con `main` (tasto "Update branch" o `git merge main`), CI verde, conversazioni risolte.
- **Merge solo con merge commit**, niente squash né rebase: su `main` restano i singoli commit e un merge commit per funzionalità. `git log --first-parent main` mostra una riga per funzionalità; per annullarne una intera basta `git revert -m 1 <merge commit>`.
- Dopo il merge il branch si cancella (impostazione del repository).
- Le pull request di Dependabot (branch `dependabot/…`, titoli `build(deps): …` e `ci(deps): …`) seguono le stesse regole: CI verde e merge commit.
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

## Struttura

| Cartella | Contenuto |
|---|---|
| `app/lib/core/config/` | Configurazione letta da `--dart-define-from-file` (`AppConfig`) |
| `app/lib/core/money/` | `Money`: importo in centesimi interi e valuta ISO 4217, formato italiano |
| `app/lib/core/router/` | Router (go_router) e catalogo delle schermate e dei fogli |
| `app/lib/theme/` | Sistema grafico da `docs/spec/stile.md`: token delle sei combinazioni (`tokens.dart`), `AppColors`, `CasaColors` (colori della casa, calcolati in OKLab), scala tipografica in Google Sans Flex, spaziature, raggi e dimensioni (`dimens.dart`), durate e transizioni, temi dei componenti Material, varianti dei bottoni (`AppButtonStyles`), palette e tema scelti (`appearance.dart`) |
| `app/lib/design/` | Componenti fatti a mano, condivisi tra le schermate: biscotto, banda diagonale, card in evidenza, avviso, card di sezione dell'hub, tessere, riga movimento, barra dei Saldi, tastierino, "fade through" tra le schede; più il segnaposto. Ricevono valori già pronti: niente logica di business |
| `app/assets/fonts/` | Google Sans Flex (file variabile ufficiale) con la sua licenza `OFL.txt` |
| `app/lib/features/auth/` | Sblocco, accesso, primo accesso (A1–A3) |
| `app/lib/features/household/` | Crea o entra in una casa, inviti (A7–A10) |
| `app/lib/features/hub/` | Hub (B1) |
| `app/lib/features/finance/` | Sezione Finanze: `summary`, `transactions`, `manual_entry`, `analytics`, `accounts` |
| `app/lib/features/settings/` | Impostazioni (I1–I10) |
| `app/lib/features/dev/` | Indice delle schermate e catalogo dei componenti (`/dev/components`), temporanei |
| `app/test/` | Test dell'app; in `test/golden/` i golden test dei componenti (tag `golden`), con le immagini in `test/golden/goldens/` |
| `supabase/` | Configurazione locale di Supabase; migrazioni, test pgTAP ed Edge Functions in arrivo |
| `.github/` | Workflow (`ci.yml` per le pull request, `goldens.yml` per le immagini dei golden test), azione comune `actions/flutter-setup`, template della pull request, Dependabot |

Rotte, livelli e tasto indietro: `docs/spec/navigazione.md`. Ogni schermata nuova si aggiunge prima al catalogo (`app/lib/core/router/screen_catalog.dart`).

Ogni componente nuovo si aggiunge anche al catalogo dei componenti (`app/lib/features/dev/component_catalog.dart`): da lì lo leggono la schermata `/dev/components`, i widget test e i golden test. Le icone sono Material Symbols Rounded (`Symbols.*_rounded` di `material_symbols_icons`), mai `Icons.*`.

L'interfaccia Material si importa da `package:material_ui/material_ui.dart`, non da `package:flutter/material.dart` (deprecato). Flutter e Dart si usano sempre tramite fvm: la versione è fissata in `.fvmrc`.

## Comandi

In PowerShell. Da `app/`:

```powershell
fvm flutter pub get                       # dipendenze
fvm dart run build_runner build -d        # generazione del codice (*.g.dart, *.freezed.dart): dopo ogni checkout o pull
fvm flutter analyze                       # analisi: zero problemi
fvm dart format .                         # formattazione
fvm flutter test --exclude-tags golden    # test (i golden girano solo in CI, su Linux)
fvm flutter run --dart-define-from-file=../private/env.dev.json                   # avvio sul telefono
fvm flutter build apk --release --dart-define-from-file=../private/env.dev.json   # build della release firmata
fvm flutter install --release             # installazione della release sul telefono
```

La build release richiede `private/key.properties` e il keystore; le build debug no.

## CI

`.github/workflows/ci.yml` gira su ogni pull request verso `main` e su ogni push su `main`. Un job per controllo, con il nome usato nel ruleset di `main`:

| Job | Cosa controlla |
|---|---|
| `gitleaks` | Segreti nei commit |
| `app` | Formattazione dei file committati, generazione del codice, `flutter analyze` (anche le info), test senza i golden |
| `golden` | Golden test (`--tags golden`) |
| `tokens` | Contrasti dei token di `docs/spec/stile.md` |
| `database` | Migrazioni e test pgTAP su Supabase avviato nel runner (salta se non ce ne sono) |

**Golden test:** le immagini di riferimento si generano **solo su Linux**, nella CI, perché Windows disegna i caratteri in modo diverso. Per aggiornarle: etichetta `update-goldens` sulla pull request, oppure workflow "Update goldens" avviato a mano sul branch (mai su `main`). Il workflow rigenera le immagini, le committa sul branch a nome di `github-actions[bot]` e fa ripartire la CI; poi `git pull` sul branch. Sul PC i golden non si lanciano.

Nei workflow: niente `pull_request_target`, niente segreti nei job delle pull request, nessun artifact, nei log solo esiti.

Dalla radice del repository:

```powershell
supabase start                            # avvia Supabase in locale (serve Docker)
supabase db reset                         # ricrea il database locale dalle migrazioni
supabase test db                          # test pgTAP
supabase stop                             # ferma Supabase
python tools/contrasti/contrasti.py docs/spec/stile.md   # controllo dei contrasti
```
