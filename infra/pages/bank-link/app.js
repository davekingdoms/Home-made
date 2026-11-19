'use strict';

// Texts of the bank link outcome, by `esito` and `codice` (provisional: the
// final wording comes with screen H). The URL values are only used as keys
// of this table: nothing from the URL is ever written into the page.
const TEXTS = {
  outcomes: {
    ok: {
      icon: 'ok',
      title: 'Banca collegata',
      text: 'Il collegamento è riuscito e la prima sincronizzazione è partita. Puoi chiudere questa pagina e tornare a Home-made.',
    },
    annullato: {
      icon: 'cancelled',
      title: 'Collegamento annullato',
      text: "Hai annullato l'autorizzazione: nessun conto è stato collegato. Puoi riprovare da Home-made.",
      codes: {
        link_cancelled: {},
      },
    },
    errore: {
      icon: 'error',
      title: 'Collegamento non completato',
      text: 'Riprova da Home-made.',
      codes: {
        link_expired: {
          title: 'Collegamento scaduto',
          text: "La richiesta è scaduta o è già stata usata. Riprova da Home-made e completa l'autorizzazione entro 30 minuti, nello stesso browser.",
        },
        link_rejected: {
          title: 'La banca non ha autorizzato il collegamento',
          text: 'Nessun conto è stato collegato. Riprova più tardi da Home-made.',
        },
        link_failed: {
          title: 'Collegamento non completato',
          text: 'Qualcosa non ha funzionato durante il ritorno dalla banca. Riprova tra qualche minuto da Home-made.',
        },
      },
    },
  },
  // Unknown, missing or malformed `esito`. Same text as the <noscript> block.
  fallback: {
    icon: 'unknown',
    title: 'Esito non disponibile',
    text: 'Torna a Home-made per vedere lo stato dei conti.',
  },
};

// The table key equal to `value`, or null. Only own keys of the table match,
// so values such as `constructor` or `__proto__` never hit the prototype.
function tableKey(table, value) {
  if (!table || value === null) return null;
  const key = Object.keys(table).find((candidate) => candidate === value);
  return key === undefined ? null : key;
}

// The parameter when it appears exactly once, otherwise null (malformed).
function single(params, name) {
  const values = params.getAll(name);
  return values.length === 1 ? values[0] : null;
}

function resolve(search) {
  const params = new URLSearchParams(search);
  const outcomeKey = tableKey(TEXTS.outcomes, single(params, 'esito'));
  if (outcomeKey === null) return { ...TEXTS.fallback, code: null };

  const outcome = TEXTS.outcomes[outcomeKey];
  const code = tableKey(outcome.codes, single(params, 'codice'));
  const byCode = code === null ? {} : outcome.codes[code];
  return {
    icon: outcome.icon,
    title: byCode.title || outcome.title,
    text: byCode.text || outcome.text,
    code,
  };
}

// Leaves only the path in the address bar and in the history entry.
function clearQuery() {
  if (!location.search && !location.hash) return;
  try {
    history.replaceState(null, '', location.pathname);
  } catch (_) {
    // Not allowed here (e.g. a local file): the page still shows the outcome.
  }
}

function render(entry) {
  const result = document.getElementById('result');
  result.dataset.icon = entry.icon;
  document.getElementById('title').textContent = entry.title;
  document.getElementById('text').textContent = entry.text;
  if (entry.code !== null) {
    document.getElementById('code').textContent = entry.code;
    document.getElementById('code-line').hidden = false;
  }
  document.title = `${entry.title} · Home-made`;
  result.hidden = false;
}

let entry;
try {
  entry = resolve(location.search);
} catch (_) {
  entry = { ...TEXTS.fallback, code: null };
}
clearQuery();
render(entry);
