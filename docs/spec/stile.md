# Specifica dello stile

Unica fonte di stile e token dell'app. Da qui si scrive il tema Flutter; i componenti si controllano con i golden test nelle sei combinazioni (3 palette × scuro/chiaro), che fanno anche da catalogo.

Il mockup di riferimento sta fuori dal repository e usa ancora un carattere segnaposto e alcuni colori precedenti: dove differisce, vale questa specifica.

## 1. Principi
- Material 3 con forme **Material 3 Expressive**, look Pixel. **Palette fisse** (niente colori dinamici), scelte da ogni utente: Teal (base), Dollari, Soldi mauriziani; tema Automatico, Chiaro o Scuro.
- Ogni colore è un **ruolo**: le schermate non usano mai codici esadecimali, solo ruoli del `ColorScheme` o dell'estensione `AppColors`.
- **Accessibilità WCAG AA** in tutte e sei le combinazioni, verificata da un test automatico (sezione 11).

## 2. Colori

### 2.1 Ruoli Material 3 per le sei combinazioni
Valori con le correzioni di contrasto della sezione 2.3. `surfaceContainer` è la media in OKLab tra Superficie 1 e 2. `surfaceTint` trasparente: niente tinta di elevazione.

| Ruolo | Teal scuro | Teal chiaro | Dollari scuro | Dollari chiaro | Mauriziani scuro | Mauriziani chiaro |
|---|---|---|---|---|---|---|
| `primary` | #A6EEF6 | #006A73 | #B5E8A9 | #2F6B3E | #D6C2FF | #5B3F8C |
| `onPrimary` | #00363C | #FFFFFF | #0E3815 | #FFFFFF | #33175E | #FFFFFF |
| `primaryContainer` | #00666F | #00666F | #2F6B3E | #2F6B3E | #5B3F8C | #5B3F8C |
| `onPrimaryContainer` | #FFFFFF | #FFFFFF | #FFFFFF | #FFFFFF | #FFFFFF | #FFFFFF |
| `secondary` | #A6EEF6 | #006A73 | #B5E8A9 | #2F6B3E | #D6C2FF | #5B3F8C |
| `onSecondary` | #00363C | #FFFFFF | #0E3815 | #FFFFFF | #33175E | #FFFFFF |
| `secondaryContainer` | #1F4E53 | #BFE6EA | #2A4F31 | #C6E6C0 | #43345C | #E2D4FB |
| `onSecondaryContainer` | #E3F1F2 | #161D1D | #E5F1E5 | #171D17 | #EDE6F4 | #1D1A22 |
| `tertiary` | #A6EEF6 | #A6EEF6 | #B5E8A9 | #B5E8A9 | #D6C2FF | #D6C2FF |
| `onTertiary` | #00363C | #00363C | #0E3815 | #0E3815 | #33175E | #33175E |
| `tertiaryContainer` | #A6EEF6 | #A6EEF6 | #B5E8A9 | #B5E8A9 | #D6C2FF | #D6C2FF |
| `onTertiaryContainer` | #00363C | #00363C | #0E3815 | #0E3815 | #33175E | #33175E |
| `error` | #FFB4AB | #BA1A1A | #FFB4AB | #BA1A1A | #FFB4AB | #BA1A1A |
| `onError` | #690005 | #FFFFFF | #690005 | #FFFFFF | #690005 | #FFFFFF |
| `errorContainer` | #93000A | #FFDAD6 | #93000A | #FFDAD6 | #93000A | #FFDAD6 |
| `onErrorContainer` | #FFDAD6 | #93000A | #FFDAD6 | #93000A | #FFDAD6 | #93000A |
| `surface` | #161A1A | #F4FBFA | #161A17 | #F5FBF4 | #18161C | #FBF8FE |
| `onSurface` | #E3F1F2 | #161D1D | #E5F1E5 | #171D17 | #EDE6F4 | #1D1A22 |
| `onSurfaceVariant` | #A9C2C5 | #3F5052 | #AFC4B0 | #41524A | #BDB2CC | #4C4459 |
| `surfaceContainerLowest` | #161A1A | #F4FBFA | #161A17 | #F5FBF4 | #18161C | #FBF8FE |
| `surfaceContainerLow` | #1A2526 | #E7F1F0 | #1B251D | #E8F2E7 | #221E29 | #F0EBF7 |
| `surfaceContainer` | #1C2C2E | #E0EDEC | #1E2C21 | #E1EEE0 | #26212E | #EBE4F4 |
| `surfaceContainerHigh` | #1E3336 | #DAE9E8 | #213425 | #DBEADA | #2A2434 | #E6DEF1 |
| `surfaceContainerHighest` | #24393C | #CBE0DE | #283D2C | #CCE0CB | #332C3F | #DAD0E9 |
| `surfaceDim` | #161A1A | #CBE0DE | #161A17 | #CCE0CB | #18161C | #DAD0E9 |
| `surfaceBright` | #24393C | #F4FBFA | #283D2C | #F5FBF4 | #332C3F | #FBF8FE |
| `outline` | #5E7477 | #6F8385 | #63776A | #71857A | #6F667E | #7B7289 |
| `outlineVariant` | #24393C | #CBDCDB | #283D2C | #CCDDCB | #332C3F | #DDD5E8 |
| `inverseSurface` | #E3F1F2 | #161D1D | #E5F1E5 | #171D17 | #EDE6F4 | #1D1A22 |
| `onInverseSurface` | #161A1A | #F4FBFA | #161A17 | #F5FBF4 | #18161C | #FBF8FE |
| `inversePrimary` | #00666F | #A6EEF6 | #2F6B3E | #B5E8A9 | #5B3F8C | #D6C2FF |
| `shadow` | #000000 | #000000 | #000000 | #000000 | #000000 | #000000 |
| `scrim` | #000000 | #000000 | #000000 | #000000 | #000000 | #000000 |
| `surfaceTint` | trasparente | trasparente | trasparente | trasparente | trasparente | trasparente |
| `testoTerziario` | #8EA1A4 | #566A6C | #94A595 | #566B59 | #938AA2 | #655C73 |
| `banda` | #007781 | #007781 | #387647 | #387647 | #6B4CA0 | #6B4CA0 |
| `suPrimarioTenue` | #CDF5F9 | #CDF5F9 | #D3F2D6 | #D3F2D6 | #E6DAFB | #E6DAFB |
| `avviso` | #E8C872 | #765500 | #E8C872 | #765500 | #E8C872 | #765500 |
| `credito` | #A6EEF6 | #006A73 | #B5E8A9 | #2F6B3E | #D6C2FF | #5B3F8C |
| `debito` | #FFB4AB | #BA1A1A | #FFB4AB | #BA1A1A | #FFB4AB | #BA1A1A |

**Corrispondenza con i nomi del mockup:** Sfondo = `surface`; Superficie 1 (card) = `surfaceContainerLow`; Superficie 2 (avvisi, rilievo) = `surfaceContainerHigh`; Superficie 3 (elementi interni) = `surfaceContainerHighest`; Primario pieno = `primaryContainer`; Decorazione su primario = `AppColors.banda`; Testo tenue su primario = `AppColors.suPrimarioTenue`; Accento (riempimenti tenui) = `tertiary`/`tertiaryContainer`; Accento per icone, bottoni pieni, interruttori = `primary`; Indicatore selezione = `secondaryContainer`; Testo, secondario, terziario = `onSurface`, `onSurfaceVariant`, `AppColors.testoTerziario`; Bordi = `outline`; Divisori = `outlineVariant`.

**Colori fissi, uguali per tutte le palette:** testo su primario pieno #FFFFFF; badge del contatore #FFB4AB con testo #690005 nel tema scuro, `error`/`onError` nel chiaro; nastro del cantiere #FFC83D / #1F1F1F.

### 2.2 Regole d'uso
- **Accento tenue** (`tertiary`): solo come riempimento (biscotto, segnaposti, icona di Finanze) con sopra `onTertiary`. Nel tema chiaro non è mai testo, icona o unico segnale di stato.
- **Testo terziario**: solo su `surface`, `surfaceContainerLow` e `surfaceContainerHigh`; mai su `surfaceContainerHighest` (usare `onSurfaceVariant`).
- **Card in evidenza** (`primaryContainer` con banda diagonale `AppColors.banda`): testo bianco o `suPrimarioTenue`, leggibili anche sopra la banda.
- **Credito e debito:** credito = `AppColors.credito` (= `primary`: accento tenue nel tema scuro, accento pieno nel chiaro); debito = `AppColors.debito` (= `error`). Vale per barre e importi dei Saldi e per il conguaglio; il colore delle entrate in Movimenti è da definire nella specifica dei Movimenti. **Il colore non è mai l'unico segnale:** sempre segno +/− e testo ("Devi tu", "Deve alla casa").
- **Avviso** (`AppColors.avviso`): icone e testi di avvertimento; #E8C872 nel tema scuro, #765500 nel chiaro.

### 2.3 Correzioni rispetto al mockup
- Testo terziario scuro: Teal #7F9598 → #8EA1A4; Dollari #839784 → #94A595.
- Banda decorativa: Teal #007A84 → #007781; Dollari #3B7D4B → #387647.
- Avviso nel tema chiaro: #E8C872 → #765500.
- Token in più usati nel prototipo dell'hub (`text3` #C2D6D8, `mutedVal`, `casaBg`) non diventano ruoli: titoli attenuati = `onSurfaceVariant`; sezioni "in arrivo" = `testoTerziario`; sfondo della casa = colori della casa (sezione 9).

## 3. Carattere e scala tipografica
- **Google Sans Flex** (SIL Open Font License 1.1, uso commerciale consentito), **incluso negli asset**, non scaricato. Licenza OFL in Info › Licenze (`LicenseRegistry`).
- **Pesi:** 400, 500, 600. In Flutter si imposta sia `fontWeight` sia `fontVariations: [FontVariation('wght', …)]`.
- **Scala** (dimensione/interlinea in dp, peso):

| Ruolo `TextTheme` | Valori | Uso |
|---|---|---|
| displaySmall | 40/48, 500 | Importo nel Nuovo movimento |
| headlineLarge | 32/40, 500 | Titolo delle schede |
| headlineMedium | 28/36, 500 | Data nell'hub, importi grandi nelle card |
| headlineSmall | 24/32, 500 | Importi nelle card dell'hub con 2 sezioni |
| titleLarge | 22/28, 500 | Titolo dei dettagli e delle sottopagine |
| titleMedium | 17/24, 500 | Nome delle card, controparte |
| titleSmall | 15/20, 500 | Intestazioni di sezione (in `onSurfaceVariant`) |
| bodyLarge | 16/24, 400 | Voci di elenco |
| bodyMedium | 15/22, 400 | Corpo |
| bodySmall | 13/18, 400 | Sottotitoli, descrizioni |
| labelLarge | 14/20, 600 | Bottoni |
| labelMedium | 12/16, 500 | Didascalie, etichette della barra |
| labelSmall | 11/16, 600 | Badge, etichette della casa |

- **Importi:** sempre cifre tabellari (`FontFeature.tabularFigures()`), peso 600 negli elenchi; segno meno tipografico (−).
- **Adattamento senza scorrimento (hub):** prima si stringe la larghezza (`wdth` fino all'85%), poi si riduce la dimensione entro un minimo, poi si tronca con i puntini. Soglie da definire nella specifica dell'hub.
- **Da verificare nei golden test:** peso sull'asse `wght`, cifre tabellari, presenza dell'asse grade, peso del file (eventuale sottoinsieme latino).

## 4. Spaziature, raggi, dimensioni
- **Griglia da 4 dp:** 4, 8, 12, 16, 20, 24, 32. Margine laterale delle schermate 16; spazio tra card 12; padding delle card 16 (14 nelle card della griglia dell'hub); spazio tra sezioni 22–24.
- **Raggi (scala M3 Expressive):** 8 barre, chip, piccoli elementi; 12 campi di testo; **16 FAB**; 20 elementi interni; 24 righe di scelta (palette); **28 card, avvisi, gruppi di voci**; **32 card dell'hub e casa**; pillola (metà altezza) per bottoni, chip, segmenti, tessere.
- **Dimensioni:** area toccabile minima 48; bottoni a pillola alti 44 (compatti) o 52–56 (principali); FAB 56; righe di elenco minimo 60–64; barra in alto 64; avatar 48 (hub), 40 (elenchi).
- **Forme fatte a mano:** biscotto (cerchio con 12 lobi) per avatar e contatori; bande diagonali arrotondate.

## 5. Icone
- **Material Symbols Rounded**, peso 400, grado 0, dimensione ottica 24, **contorno**; **piene** solo sulla scheda attiva della barra. Un solo set di icone.
- Dimensioni 24 (barra, voci), 20 (dentro bottoni e tessere), 18 (segnaposti della casa).
- **Da verificare:** pacchetto Flutter e riduzione automatica del font alle sole icone usate nella build di rilascio.

## 6. Animazioni
- Solo Flutter e Material 3, nessuna libreria esterna di animazione.
- **Durate:** 150 ms (stati, piccoli cambi), 300 ms (fogli, espansioni), 500 ms (transizioni di schermata e della casa). Curva "emphasized" di Material 3 (`Easing.emphasizedDecelerate` in entrata, `emphasizedAccelerate` in uscita).
- **Transizioni:** "fade through" tra le schede della barra; "shared axis" orizzontale verso i dettagli; i fogli salgono dal basso. **Indietro predittivo** di Android attivo.
- **Riduci animazioni:** se il telefono lo chiede (`MediaQuery.disableAnimations`), le transizioni diventano dissolvenze brevi e la casa resta ferma.

## 7. Accessibilità
- Contrasto AA: testo ≥ 4,5, testo grande e componenti ≥ 3. Verificato su tutti i ruoli (sezione 11).
- **Testo di sistema:** fino al 200% nelle schermate con scorrimento; nell'hub limitato al 130% (`TextScaler.clamp`).
- Area toccabile minima 48 × 48; etichette `Semantics` su icone e numeri (es. "8 transazioni da classificare"); il colore non è mai l'unico segnale.
- Lettore di schermo: la casa ha un'etichetta descrittiva e ogni stanza toccabile la sua.

## 8. Componenti
Stati per tutti: normale, premuto (livello di stato 10%), focus (10% più anello), disattivato (contenuto `onSurface` al 38%, contenitore al 12%), errore dove ha senso. I livelli di stato sono quelli standard di Material 3.

| Componente | In Flutter | Varianti | Note |
|---|---|---|---|
| Barra di navigazione | `NavigationBar` | 4 schede, badge | Indicatore a pillola `secondaryContainer`, etichette sempre visibili, badge su Movimenti |
| Barra in alto | `AppBar` | "‹ Finanze" (livello 1), freccia indietro (livello 2) | Avatar solo nell'hub |
| Bottone principale | `FilledButton` | normale, compatto 44 | `primary`/`onPrimary` |
| Bottone tonale | `FilledButton.tonal` | — | `surfaceContainerHighest` con testo `primary` (es. Promemoria) |
| Bottone con contorno | `OutlinedButton` | normale, distruttivo | Bordo `outline`; distruttivo con testo `error` (es. Esci) |
| Bottone di testo | `TextButton` | — | Link "Saldi", "Report" |
| FAB "+" | `FloatingActionButton` | — | 56, raggio 16 |
| Segmented button | `SegmentedButton` | 2–3 segmenti | Pillola, selezione `secondaryContainer` |
| Chip filtro | `FilterChip` / `ActionChip` | con freccia | Periodo, conti, filtri |
| Interruttore | `Switch` | — | Acceso `primary` |
| Radio | `Radio` | riga palette con tre pallini | — |
| Campo di testo | `TextField` | normale, errore | Raggio 12 |
| Foglio dal basso | `showModalBottomSheet` | — | Raggio 28 in alto |
| Avviso | personalizzato (`Card` + `ListTile`) | errore, avviso, info | Icona colorata, titolo, sottotitolo, azione a pillola; sfondo `surfaceContainerHigh` |
| Card | `Card` | normale (`surfaceContainerLow`), in evidenza (`primaryContainer` + banda) | Raggio 28 (32 nell'hub) |
| Card sezione dell'hub | personalizzata | attiva, "in arrivo" | Icona tonda, nome, stato, 2 dati rapidi |
| Tessere rapide | personalizzate | biscotto con numero, pillola con valore | Biscotto `tertiary` |
| Tessera numerica | personalizzata | — | Etichetta piccola + importo |
| Riga movimento | `ListTile` personalizzato | normale, suggerimento (icona tratteggiata, testo in `primary`, tasto ✓) | — |
| Barra dei Saldi | personalizzata | credito, debito | Divisa al centro; `credito`/`debito` su traccia `surfaceContainerHighest` |
| Tastierino numerico | personalizzato | — | Tasti a pillola |
| Trascina per aggiornare | `RefreshIndicator` | — | — |
| Biscotto (forma) | `ShapeBorder` personalizzato | avatar, contatore | 12 lobi |
| Banda diagonale | decorazione personalizzata | card in evidenza, card dell'hub | — |
| Casa dell'hub | `CustomPainter` | vedi sezione 9 | Stanze toccabili |

## 9. Casa dell'hub e cielo

### 9.1 Casa
- **Disegno vettoriale** partendo dalla casa del mockup. Studio di riferimento nel mockup: palette, ora, meteo, studio acceso o al buio (15 combinazioni).
- **Animazioni con Flutter**, nessuna libreria esterna.
- Un unico sorgente: ogni forma ha un **ruolo colore**, ogni stanza un identificativo e una zona toccabile. **La casa è appoggiata su un prato** con collina dietro, ciuffi d'erba e ombre a terra, tutto in palette.
- Stanze: studio = Finanze; cucina in cantiere = Dispensa; ingresso con cassettiera = Documenti; cuccia in giardino = Animali; camera libera. **Stanza accesa** (qualcosa da fare): ruoli "acc", vetro acceso, alone (16% di notte, 12% all'alba, 8% di giorno), monitor e lampada in accento. **Al buio:** ruoli "buio", vetro spento, niente alone.

### 9.2 Colori della casa (regola decisa, valori da rifinire)
- **Base: ruoli Teal notturni.** Le altre combinazioni si **calcolano nel codice**:
  - **Palette:** rotazione della tinta in OKLCH di (tinta del primario della palette − tinta del primario Teal), luminosità e croma invariate (croma ridotta se esce dal gamut sRGB); i ruoli quasi grigi (croma < 0,008) non si ruotano.
  - **Giorno:** L' = 0,20 + 0,80·L, croma invariata.
  - **Alba e tramonto:** media in OKLab tra notte e giorno, poi 12% verso #E07A3C.
- **Ruoli (Teal, notte):** ombra #0A1011 · terra #173B3E · terraFronte #0D2729 · terraLato #0A1F21 · muro #1E3A3D · muroOmbra #162D30 · muroLuce #2B4A4E · cornice #3E6A6F · ringhiera #6E979B · tetto #00666F · tettoOmbra #003D44 · timpano #00525A · buioFondo #1A2A2C · buioLato #152325 · buioPav #203335 · accFondo #2F7177 · accLato #28656B · accPav #3A8A90 · vetroAcceso #D2F7FB · alone #A6EEF6 · arredo #2A4245 · arredoOmbra #203538 · arredoChiaro #3A5558 · arredoLuce #4E6B6E · mobile #0F3337 · mobileScuro #0B2427 · vetroSpento #24393C · vetroScuro #0F2326 · porta #00525A · accento #A6EEF6 · accento2 #7FD4DE · verde #1F5A5F · verdeLuce #2A6E73 · pianta #1F4A4E · cucciaTetto #245A5F · banda1 #00444B · banda2 #005A63 · stelle #C2D6D8.
- **Cielo notturno:** Teal #111718, Dollari #121712, Soldi mauriziani #141218.
- Le tabelle delle 9 combinazioni (3 palette × notte, alba, giorno) si generano dalla regola e diventano golden test.

### 9.3 Fase 1
La casa è **solo notturna**, anche nel tema chiaro, con le stanze accese o al buio secondo lo stato delle sezioni. Il cielo variabile arriva nella fase 1b. Il permesso di posizione si chiede comunque già dalla fase 1 (sezione 9.4).

### 9.4 Cielo variabile (fase 1b)
- Il cielo segue l'**ora reale**, non il tema dell'app; cambia all'alba e al tramonto.
- **Sempre in palette:** notte = cielo scuro con bande, luna e stelle; giorno = stessa tinta più chiara (luminosità 0,60 in alto, 0,80 in basso), sole e bande accennati; alba e tramonto = a metà, con un po' di arancio (#E8804A, 10–22%) e sole basso.
- **Meteo:** sereno, nuvoloso, pioggia, nebbia, neve. Con il maltempo il cielo perde il 60% della croma; nuvole un tono più chiare del cielo.
- **Pioggia, neve e nebbia stanno dietro la casa**, mai davanti; la neve si posa su tetto, prato, cuccia e albero. Pioggia e neve cadono, nuvole e nebbia si spostano piano; ferme con "riduci animazioni".
- **Alba e tramonto** calcolati sul telefono (formula astronomica, offline).
- **Posizione del telefono**, per utente. Approssimativa (`ACCESS_COARSE_LOCATION`), mai in background; permesso chiesto al primo avvio (creazione o ingresso nella casa) già dalla fase 1, modificabile nelle impostazioni; se negato, città scelta a mano.
- **Privacy:** coordinate arrotondate (circa 10 km), solo sul telefono e verso il servizio meteo; **mai salvate su Supabase**. Da dichiarare nella sezione sulla sicurezza dei dati di Google Play dal primo rilascio.
- **Meteo: MET Norway** (Locationforecast 2.0): gratuito anche per uso commerciale (CC BY 4.0), nessuna chiave, User-Agent con nome dell'app e contatto obbligatorio (mai un'email personale nel codice), attribuzione in Info › Licenze. Aggiornamento circa ogni ora con l'ultimo dato salvato; senza rete o senza dato, cielo sereno. **Da verificare:** i termini chiedono che le app mobili passino da un proxy con cache invece di chiamare l'API direttamente (eventuale Edge Function di Supabase che non salva le coordinate).

## 10. Corrispondenza con Flutter
- `ThemeData(useMaterial3: true, colorScheme: …, textTheme: …, extensions: [AppColors(…), CasaColors(…)])`, uno per ciascuna delle sei combinazioni, costruiti da una tabella in `lib/theme/tokens.dart` copiata dalla sezione 2.1.
- `ColorScheme(brightness: …)` con tutti i ruoli della tabella (nessun `fromSeed`: palette fisse).
- `AppColors extends ThemeExtension`: `testoTerziario`, `banda`, `suPrimarioTenue`, `avviso`, `credito`, `debito`, `nastroGiallo`, `nastroNero`.
- `CasaColors extends ThemeExtension`: i ruoli della casa per palette e ora, calcolati con la regola della sezione 9.2.
- `textTheme` dalla sezione 3 con `fontFamily: 'GoogleSansFlex'`; temi dei componenti (`navigationBarTheme`, `cardTheme`, `filledButtonTheme`, `segmentedButtonTheme`, `chipTheme`, `floatingActionButtonTheme`, `bottomSheetTheme`, `inputDecorationTheme`) con raggi e colori delle sezioni 4 e 8.
- `pageTransitionsTheme`: indietro predittivo su Android; transizioni della sezione 6.
- Palette e tema scelti dall'utente stanno in cima all'app (salvati nel profilo) e si applicano subito a tutte le schermate.

## 11. Verifica dei contrasti
Lo script `tools/contrasti/contrasti.py` legge la tabella della sezione 2.1 e calcola il contrasto WCAG su 26 coppie per combinazione: 156 controlli, tutti superati con i valori attuali. Va eseguito in CI a ogni modifica dei token, insieme ai golden test:

```
python3 tools/contrasti/contrasti.py docs/spec/stile.md
```

## 12. Ancora aperto
- Valori fini della casa e del cielo (luminosità del giorno, quantità di arancio, croma del maltempo): nella fase 1b.
- Verifiche tecniche: font variabile in Flutter, pacchetto delle icone, termini di MET Norway (proxy per le app mobili e uso con molti utenti).
