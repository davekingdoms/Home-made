# Home-made

App per le finanze di casa: importa i movimenti dalle banche, li classifica, divide le spese tra i membri della casa (da uno a N) e calcola il conguaglio. In seguito: scontrini e dispensa.

**Stato:** in progettazione. Il codice arriva con le prime iterazioni.

## Stack

Flutter (Android, telefono e tablet) · Supabase (Postgres, accesso con Google, Edge Functions) · Enable Banking (PSD2) · GitHub Actions · Cloudflare R2 e Pages · Firebase (distribuzione dell'app e notifiche).

## Struttura

| Cartella | Contenuto |
|---|---|
| `app/` | App Flutter (in arrivo) |
| `supabase/` | Migrazioni, test pgTAP, Edge Functions (in arrivo) |
| `infra/backup/` | Backup notturno del database |
| `infra/pages/` | Pagine per gli App Link e il ritorno dal collegamento bancario |
| `docs/spec/` | Specifiche tecniche, da leggere prima di scrivere codice |
| `tools/` | Strumenti di sviluppo (controllo dei contrasti dei colori) |

## Regole

Valgono per chiunque lavori sul repository, persone e agenti: vedi [`CLAUDE.md`](CLAUDE.md). In breve: specifica prima del codice, nessun segreto e **nessun dato personale o reale** nel repository, nella cronologia e nei log della CI.
