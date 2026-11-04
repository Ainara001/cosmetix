'use strict';

// Admin panel. All text from the server goes in through textContent, never innerHTML.
const $ = (sel, root = document) => root.querySelector(sel);

function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (k === 'class') node.className = v;
    else if (k.startsWith('on')) node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v);
  }
  for (const c of children.flat()) {
    if (c !== null && c !== undefined) node.append(c instanceof Node ? c : document.createTextNode(String(c)));
  }
  return node;
}

async function api(method, path, body) {
  const res = await fetch(`/admin/api${path}`, {
    method,
    headers: {
      'x-requested-with': 'cosmetix-admin',
      ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
    credentials: 'same-origin',
  });
  if (res.status === 204) return null;
  const data = await res.json().catch(() => ({}));
  if (res.status === 401 && path !== '/login') {
    showLogin();
    throw new Error('Войдите заново');
  }
  if (!res.ok) throw new Error(data.message || `Ошибка ${res.status}`);
  return data;
}

const fmtDate = (iso) =>
  iso ? new Date(iso).toLocaleString('ru-RU', { dateStyle: 'short', timeStyle: 'medium' }) : '—';
const short = (id) => id.slice(0, 8);
const json = (o) => (o && Object.keys(o).length ? JSON.stringify(o) : '');

// ---------- sign in ----------
function showLogin() {
  $('#app').hidden = true;
  $('#login').hidden = false;
  $('#login-form').elements.password.value = '';
}

$('#login-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = e.target.elements;
  $('#login-error').textContent = '';
  try {
    await api('POST', '/login', { username: f.username.value, password: f.password.value });
    await start();
  } catch (err) {
    $('#login-error').textContent = err.message;
  }
});

$('#logout').addEventListener('click', async () => {
  await api('POST', '/logout').catch(() => {});
  showLogin();
});

async function start() {
  const me = await api('GET', '/me');
  $('#who').textContent = me.username;
  $('#login').hidden = true;
  $('#app').hidden = false;
  await loadCategories();
  openTab(currentTab);
}

// ---------- tabs ----------
let currentTab = 'overview';
const loaders = {
  overview: loadOverview,
  products: () => loadProducts(),
  logins: () => loadEvents('l', 'app_open'),
  events: () => loadEvents('e'),
  users: loadUsers,
  audit: loadAudit,
};

function openTab(name) {
  currentTab = name;
  for (const b of document.querySelectorAll('#tabs button')) {
    b.classList.toggle('active', b.dataset.tab === name);
  }
  for (const s of document.querySelectorAll('.content > section')) s.hidden = s.id !== `tab-${name}`;
  loaders[name]().catch((err) => alert(err.message));
}
$('#tabs').addEventListener('click', (e) => {
  if (e.target.dataset.tab) openTab(e.target.dataset.tab);
});

function pager(id, state, total, reload) {
  const box = $(`#${id}-pager`);
  box.replaceChildren(
    el('button', { type: 'button', ...(state.offset === 0 ? { disabled: '' } : {}), onclick: () => { state.offset = Math.max(0, state.offset - state.limit); reload(); } }, '←'),
    el('span', {}, total === 0 ? '0' : `${state.offset + 1}–${Math.min(total, state.offset + state.limit)} из ${total}`),
    el('button', { type: 'button', ...(state.offset + state.limit >= total ? { disabled: '' } : {}), onclick: () => { state.offset += state.limit; reload(); } }, '→'),
  );
}

// ---------- overview ----------
async function loadOverview() {
  const s = await api('GET', '/stats');
  const tile = (n, label) => el('div', { class: 'tile' }, el('b', {}, n), el('span', {}, label));
  const row = (cells) => el('tr', {}, cells.map((c) => el('td', {}, c)));
  $('#tab-overview').replaceChildren(
    el('div', { class: 'tiles' },
      tile(s.users, 'устройств всего'),
      tile(s.activeUsers24h, 'активны за 24 часа'),
      tile(s.opens24h, 'входов за 24 часа'),
      tile(s.opens7d, 'входов за 7 дней'),
      tile(s.events, 'событий всего')),
    el('div', { class: 'cols' },
      el('div', {}, el('h3', {}, 'События за 7 дней по типам'),
        el('table', {}, el('thead', {}, el('tr', {}, el('th', {}, 'Тип'), el('th', {}, 'Число'))),
          el('tbody', {}, s.eventsByType7d.length ? s.eventsByType7d.map((t) => row([t.type, t.n])) : [row(['Пока нет событий', ''])]))),
      el('div', {}, el('h3', {}, 'Входы по дням (14 дней, UTC)'),
        el('table', {}, el('thead', {}, el('tr', {}, el('th', {}, 'День'), el('th', {}, 'Входов'), el('th', {}, 'Устройств'))),
          el('tbody', {}, s.opensByDay.length ? s.opensByDay.map((d) => row([d.day, d.opens, d.users])) : [row(['Пока нет входов', '', ''])])))),
  );
}

// ---------- products ----------
const pState = { offset: 0, limit: 50 };
let categories = [];

async function loadCategories() {
  categories = (await api('GET', '/categories')).items.map((c) => c.name);
  const sel = $('#p-cat');
  const keep = sel.value;
  sel.replaceChildren(el('option', { value: '' }, 'Все категории'), ...categories.map((c) => el('option', { value: c }, c)));
  sel.value = categories.includes(keep) ? keep : '';
  $('#cat-list').replaceChildren(...categories.map((c) => el('option', { value: c })));
}

async function loadProducts() {
  const q = new URLSearchParams({ limit: pState.limit, offset: pState.offset });
  if ($('#p-q').value.trim()) q.set('q', $('#p-q').value.trim());
  if ($('#p-cat').value) q.set('category', $('#p-cat').value);
  const data = await api('GET', `/products?${q}`);
  $('#p-table tbody').replaceChildren(
    ...data.items.map((p) =>
      el('tr', { onclick: () => editProduct(p.id) },
        el('td', {}, p.id), el('td', {}, p.brand), el('td', {}, p.name), el('td', {}, p.category),
        el('td', {}, p.country || '—'),
        el('td', {}, p.price, ' ', p.priceSource === 'demo' ? el('span', { class: 'tag', title: 'Пример из сида приложения, не цена магазина' }, 'демо') : null),
        el('td', {}, p.inci ? 'есть' : '—')),
    ),
  );
  pager('p', pState, data.total, loadProducts);
}

let searchTimer;
$('#p-q').addEventListener('input', () => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => { pState.offset = 0; loadProducts().catch((e) => alert(e.message)); }, 250);
});
$('#p-cat').addEventListener('change', () => { pState.offset = 0; loadProducts().catch((e) => alert(e.message)); });

let editingId = null;
let original = null;

async function editProduct(id) {
  const p = await api('GET', `/products/${id}`);
  editingId = id;
  original = p;
  const f = $('#edit-form').elements;
  $('#ed-title').textContent = p.name;
  $('#ed-sub').textContent = `№ ${p.id} · ${p.brand}`;
  f.name.value = p.name;
  f.category.value = p.category;
  f.country.value = p.country || '';
  f.price.value = p.price;
  f.inci.value = p.inci;
  $('#ed-price-note').textContent =
    p.priceSource === 'demo'
      ? 'Сейчас это демо-цена из сида приложения, не цена магазина. После сохранения будет помечена как введённая вручную.'
      : 'Цена введена вручную в админке.';
  $('#ed-src').textContent = p.sourceUrl ? `Источник состава: ${p.sourceUrl}` : 'Источник состава не указан.';
  $('#ed-error').textContent = '';
  $('#editor').showModal();
}

$('#ed-cancel').addEventListener('click', () => $('#editor').close());

$('#edit-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const f = e.target.elements;
  // send only what changed
  const next = {
    name: f.name.value,
    category: f.category.value,
    country: f.country.value,
    price: Number(f.price.value),
    inci: f.inci.value,
  };
  const patch = {};
  for (const [k, v] of Object.entries(next)) {
    const was = k === 'country' ? original.country || '' : original[k];
    if (v !== was) patch[k] = v;
  }
  if (Object.keys(patch).length === 0) return $('#editor').close();
  $('#ed-save').disabled = true;
  try {
    await api('PATCH', `/products/${editingId}`, patch);
    $('#editor').close();
    await loadCategories();
    await loadProducts();
  } catch (err) {
    $('#ed-error').textContent = err.message;
  } finally {
    $('#ed-save').disabled = false;
  }
});

// ---------- events / logins ----------
const eState = { e: { offset: 0, limit: 50 }, l: { offset: 0, limit: 50 } };

async function loadEvents(prefix, fixedType) {
  const state = eState[prefix];
  const q = new URLSearchParams({ limit: state.limit, offset: state.offset });
  const type = fixedType || $('#e-type').value.trim();
  if (type) q.set('type', type);
  const data = await api('GET', `/events?${q}`);
  $(`#${prefix}-table tbody`).replaceChildren(
    ...data.items.map((ev) =>
      el('tr', {},
        el('td', {}, fmtDate(ev.createdAt)),
        el('td', { class: 'mono', title: ev.userId }, short(ev.userId)),
        ...(fixedType ? [] : [el('td', {}, ev.type)]),
        el('td', { class: 'mono' }, json(ev.props))),
    ),
  );
  pager(prefix, state, data.total, () => loadEvents(prefix, fixedType));
}

let typeTimer;
$('#e-type').addEventListener('input', () => {
  clearTimeout(typeTimer);
  typeTimer = setTimeout(() => { eState.e.offset = 0; loadEvents('e').catch((e) => alert(e.message)); }, 300);
});

// ---------- devices, audit ----------
const uState = { offset: 0, limit: 50 };
async function loadUsers() {
  const data = await api('GET', `/users?limit=${uState.limit}&offset=${uState.offset}`);
  $('#u-table tbody').replaceChildren(
    ...data.items.map((u) =>
      el('tr', {}, el('td', { class: 'mono', title: u.id }, short(u.id)), el('td', {}, fmtDate(u.createdAt)),
        el('td', {}, fmtDate(u.lastSeenAt)), el('td', {}, u.opens), el('td', {}, u.events))),
  );
  pager('u', uState, data.total, loadUsers);
}

const FIELD = { name: 'название', category: 'категория', inci: 'состав', country: 'страна', price: 'цена', description: 'описание' };
async function loadAudit() {
  const data = await api('GET', '/audit?limit=100');
  const clip = (v) => (v === null || v === '' ? '—' : String(v).length > 60 ? `${String(v).slice(0, 60)}…` : String(v));
  $('#a-table tbody').replaceChildren(
    ...data.items.map((a) =>
      el('tr', {}, el('td', {}, fmtDate(a.createdAt)), el('td', {}, a.username),
        el('td', {}, a.productName ? `№ ${a.productId} ${a.productName}` : `№ ${a.productId ?? '—'}`),
        el('td', {}, Object.entries(a.changes).map(([k, c]) => el('div', {}, `${FIELD[k] || k}: ${clip(c.from)} → ${clip(c.to)}`))))),
  );
}

// ---------- start ----------
start().catch(showLogin);
