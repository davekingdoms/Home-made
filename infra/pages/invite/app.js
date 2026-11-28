'use strict';

// The page of an invite link opened without the app (docs/spec/accesso.md,
// A10). The fragment of the address carries t (the token) and c (the code):
// it is read only as data, as strictly as the app reads it, and nothing
// leaves the page. The token is never shown; no network, no localStorage,
// no cookies, no log. The fragment stays in the address, so a reload shows
// the code again.

// 32 random bytes in base64url, without the padding (create_invite).
const TOKEN = /^[A-Za-z0-9_-]{43}$/;

// 8 characters without 0, O, 1, I, L, in capitals.
const CODE = /^[2-9ABCDEFGHJKMNPQRSTUVWXYZ]{8}$/;

// The code of the fragment `hash`, in capitals, or null when the fragment
// is missing or malformed: exactly t and c, once each.
function readCode(hash) {
  const fragment = hash.startsWith('#') ? hash.slice(1) : hash;
  if (fragment === '') return null;
  const values = new Map();
  for (const pair of fragment.split('&')) {
    const separator = pair.indexOf('=');
    if (separator <= 0) return null;
    const key = pair.slice(0, separator);
    if (key !== 't' && key !== 'c') return null;
    if (values.has(key)) return null;
    values.set(key, pair.slice(separator + 1));
  }
  const token = values.get('t');
  const code = values.get('c');
  if (token === undefined || code === undefined) return null;
  if (!TOKEN.test(token)) return null;
  const upper = code.toUpperCase();
  return CODE.test(upper) ? upper : null;
}

// Shows the code in two groups of 4, or the text of a broken link.
function render() {
  let code;
  try {
    code = readCode(location.hash);
  } catch (_) {
    code = null;
  }
  const invite = document.getElementById('invite');
  const broken = document.getElementById('broken');
  if (code === null) {
    invite.hidden = true;
    broken.hidden = false;
    return;
  }
  document.getElementById('code').textContent = `${code.slice(0, 4)} ${code.slice(4)}`;
  broken.hidden = true;
  invite.hidden = false;
}

render();
window.addEventListener('hashchange', render);
