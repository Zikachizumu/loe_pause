(() => {
'use strict';

/* ============================================================ YARDIMCILAR */
const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'loe_pause';
const post = (name, data) => fetch(`https://${RES}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(data || {}),
}).then(r => r.json()).catch(() => null);

const $ = (sel, root = document) => root.querySelector(sel);

const h = (tag, props = {}, ...kids) => {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(props || {})) {
        if (v == null || v === false) continue;
        if (k === 'class') el.className = v;
        else if (k === 'html') el.innerHTML = v;
        else if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
        else el.setAttribute(k, v === true ? '' : v);
    }
    for (const c of kids.flat(Infinity)) {
        if (c == null || c === false) continue;
        el.append(c.nodeType ? c : document.createTextNode(String(c)));
    }
    return el;
};
const ico = (name) => { const i = document.createElement('i'); i.className = 'ico'; i.innerHTML = window.icon(name); return i; };
const clamp = (n, a, b) => Math.max(a, Math.min(b, n));

/* ============================================================ METİNLER */
const STR = {
    tr: {
        // Ana menü etiketleri [kalın kısım, ince kısım]; başlıkta ve maddelerde boşluksuz birleşik yazılır (tasarım gereği)
        pm_title: ['DURAKLATMA', 'MENÜSÜ'],
        menu_resume: ['DEVAM', 'ET'], menu_map: ['HARİTA', ''], menu_game: ['OYUN', 'AYARLARI'], menu_ui: ['ARAYÜZ', 'AYARLARI'],
        menu_position: ['KONUM', 'MODU'], menu_stats: ['İSTATİSTİKLER', ''], menu_battlepass: ['BATTLE', 'PASS'],
        menu_shop: ['SHOP', ''], menu_quit: ['AYRIL', ''],
        all_gta: 'Tüm GTA ayarları', game_title: 'Oyun Ayarları', ui_title: 'Arayüz Ayarları',
        ms_placeholder: 'Yer ara…', ms_places: 'yer', ms_idle: 'Aramak için tıkla veya bas', ms_active: 'Enter: GPS kur · Esc: haritaya dön',
        ms_set: 'GPS kuruldu', ms_none: 'Eşleşen yer yok',
        settings: 'Ayarlar', search: 'Ayarlarda ara…', no_results: 'Sonuç bulunamadı',
        hint_move: 'Gezin', hint_change: 'Değiştir', hint_select: 'Seç', hint_resume: 'Devam', hint_back: 'Geri', hint_close: 'Kapat', hint_search: 'Ara',
        on: 'Açık', off: 'Kapalı', metric: 'Metrik (km)', imperial: 'İngiliz (mil)', native_tag: 'GTA Ayarları', readonly: 'Salt okunur — değiştirmek için FiveM tuş atamaları', unbound: 'Atanmamış',
        soon_pill: 'Yakında', soon_title: 'Yakında', soon_text: 'Bu özellik henüz sunucuda aktif değil. Çok yakında burada olacak.',
        quit_title: 'Oyundan çık?', quit_text: 'Sunucudan ayrılıp FiveM ana menüsüne dönersin.',
        quit_disconnect: 'Sunucudan ayrıl', cancel: 'Vazgeç',
        stats_title: 'İstatistikler', st_character: 'Karakter', st_name: 'Ad Soyad', st_cid: 'Vatandaş No', st_job: 'Meslek',
        st_finance: 'Finans', st_cash: 'Nakit', st_bank: 'Banka',
        st_health: 'Sağlık', health_none: 'Hastalığın yok. Sağlıklısın.', health_unknown: 'Sağlık bilgisi alınıyor…',
        health_active: 'Aktif', health_quiet: 'İlaç etkisinde — belirtiler sessiz', health_bandaged: 'Sargılı',
        msg_rec_started: 'Kayıt başladı', msg_rec_saved: 'Klip kaydedildi', msg_rec_discarded: 'Kayıt iptal edildi', msg_reset_done: 'Görünüm varsayılana döndü',
        back: 'Geri', close: 'Kapat',
    },
    en: {
        pm_title: ['PAUSE', 'MENU'],
        menu_resume: ['RESUME', ''], menu_map: ['MAP', ''], menu_game: ['GAME', 'SETTINGS'], menu_ui: ['UI', 'SETTINGS'],
        menu_position: ['POSITION', 'MODE'], menu_stats: ['STATISTICS', ''], menu_battlepass: ['BATTLE', 'PASS'],
        menu_shop: ['SHOP', ''], menu_quit: ['DISCONNECT', ''],
        all_gta: 'All GTA settings', game_title: 'Game Settings', ui_title: 'UI Settings',
        ms_placeholder: 'Search places…', ms_places: 'places', ms_idle: 'Click here or press', ms_active: 'Enter: set GPS · Esc: back to map',
        ms_set: 'GPS set', ms_none: 'No places match',
        settings: 'Settings', search: 'Search settings…', no_results: 'No results',
        hint_move: 'Navigate', hint_change: 'Change', hint_select: 'Select', hint_resume: 'Resume', hint_back: 'Back', hint_close: 'Close', hint_search: 'Search',
        on: 'On', off: 'Off', metric: 'Metric (km)', imperial: 'Imperial (mi)', native_tag: 'GTA Settings', readonly: 'Read-only — change it in the FiveM key bindings', unbound: 'Unbound',
        soon_pill: 'Soon', soon_title: 'Coming soon', soon_text: 'This feature is not active on the server yet. It will be here soon.',
        quit_title: 'Disconnect?', quit_text: 'You will leave the server and return to the FiveM main menu.',
        quit_disconnect: 'Leave server', cancel: 'Cancel',
        stats_title: 'Statistics', st_character: 'Character', st_name: 'Name', st_cid: 'Citizen ID', st_job: 'Job',
        st_finance: 'Finances', st_cash: 'Cash', st_bank: 'Bank',
        st_health: 'Health', health_none: 'No illness. You are healthy.', health_unknown: 'Loading health info…',
        health_active: 'Active', health_quiet: 'Medicated — symptoms quiet', health_bandaged: 'Bandaged',
        msg_rec_started: 'Recording started', msg_rec_saved: 'Clip saved', msg_rec_discarded: 'Recording discarded', msg_reset_done: 'Appearance reset to defaults',
        back: 'Back', close: 'Close',
    },
};

const DEFAULT_MENU = ['resume', 'map', 'game', 'ui', 'position', 'quit'].map(id => ({ id, available: true, soon: id === 'position' }));
const LINK_ICONS = { youtube: 'youtube', store: 'globe', discord: 'discord' };
// Yalnızca bu ana makineden gelen (Lua yapılandırmasından) https adresleri açılır; arayüzden adres alınmaz.
const SAFE_URL = /^https:\/\/[^\s"'<>]+$/i;

/* ============================================================ DURUM */
const S = {
    open: false, lang: 'en',
    allSchema: [], schema: [], scope: 'game', links: [], gta: true, bg: { mode: 'game' },
    values: {}, keys: {}, native: {}, caps: {}, menu: DEFAULT_MENU, stats: null, health: { known: false, conditions: [] },
    screen: 'main', page: null,
    mainIdx: 0, cat: 0, grp: 0, row: 0, zone: 'cats', query: '', entries: [],
    modal: null,
};

const app = $('#app');
const q = $('#q');
const t = (k) => (STR[S.lang] && STR[S.lang][k]) ?? STR.tr[k] ?? k;
const L = (o) => (o ? (o[S.lang] ?? o.tr ?? '') : '');

const norm = (s) => String(s || '').toLocaleLowerCase('tr').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/ı/g, 'i');

const rowIndex = {};
const indexSchema = () => {
    for (const k of Object.keys(rowIndex)) delete rowIndex[k];
    for (const c of S.allSchema) for (const g of c.groups) for (const r of g.rows) if (r.id && !rowIndex[r.id]) rowIndex[r.id] = r;
};

/* ============================================================ TERCİHLER (görünüm) */
const hexToRgb = (hex) => {
    const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex || '');
    return m ? [parseInt(m[1], 16), parseInt(m[2], 16), parseInt(m[3], 16)] : [255, 255, 255];
};

const applyPrefs = () => {
    S.lang = S.values['pref.lang'] === 'tr' ? 'tr' : 'en';
    document.documentElement.lang = S.lang;

    const def = rowIndex['pref.accent'];
    const cur = def && (def.options.find(o => o.value === S.values['pref.accent']) || def.options[0]);
    const color = (cur && cur.color) || '#ffffff';
    const rgb = hexToRgb(color);
    const lum = (0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]) / 255;
    document.documentElement.style.setProperty('--accent', color);
    document.documentElement.style.setProperty('--accent-rgb', rgb.join(', '));
    document.documentElement.style.setProperty('--on-accent', lum > 0.55 ? '#0b0b0d' : '#ffffff');   // vurgunun üstündeki yazı okunur kalsın

    app.dataset.theme = S.values['pref.dark'] === false ? 'light' : 'dark';
    app.classList.toggle('bg-game', S.bg && S.bg.mode === 'game');
    updatePortrait();
};

const updatePortrait = () => {
    const on = S.values['pref.portrait'] === true || (window.innerWidth / window.innerHeight) < 1.25;
    document.documentElement.classList.toggle('portrait', on);
};
window.addEventListener('resize', updatePortrait);

/* ============================================================ EKRANLAR */
const screens = { main: $('#screenMain'), settings: $('#screenSettings'), page: $('#screenPage') };
const showScreen = (name) => {
    S.screen = name;
    for (const [k, el] of Object.entries(screens)) el.classList.toggle('hidden', k !== name);
    $('#hintsMain').classList.toggle('hidden', name !== 'main');
    renderHints();
};

const hintSpan = (keys, label) => h('span', {}, keys.map(k => h('kbd', {}, k)), label);
const renderHints = () => {
    const main = $('#hintsMain'), st = $('#hintsSettings'), pg = $('#hintsPage');
    main.replaceChildren(hintSpan(['↑', '↓'], t('hint_move')), hintSpan(['ENTER'], t('hint_select')), hintSpan(['ESC'], t('hint_resume')));
    st.replaceChildren(
        hintSpan(['↑', '↓'], t('hint_move')), hintSpan(['←', '→'], t('hint_change')), hintSpan(['Enter'], t('hint_select')),
        hintSpan(['Backspace'], t('hint_back')), hintSpan(['/'], t('hint_search')), hintSpan(['ESC'], t('hint_close')));
    pg.replaceChildren(hintSpan(['Backspace'], t('hint_back')), hintSpan(['ESC'], t('hint_close')));
};

/* ============================================================ ANA MENÜ (PAUSE MENU) */
const REDUCED = !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
// Etiket çifti [kalın, ince]; tek sözcüklü etiketlerde ince kısım boştur.
const pair = (id) => { const v = t('menu_' + id); return Array.isArray(v) ? v : [String(v), '']; };
const lblText = (id) => pair(id).join('');

// Başlık sonekinin "karıştırma" efekti: seçili maddenin adı soldan sağa çözülür, kalan harfler rastgele görünür.
const SCRAMBLE = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
let scrambleTimer = null;
const setSuffix = (id) => {
    const el = $('#pmSuffix');
    clearInterval(scrambleTimer);
    if (!id || id === 'resume') { el.replaceChildren(); return; }
    const [a, b] = pair(id);
    const full = a + b, n = full.length, cut = a.length, TOTAL = 14;
    let step = REDUCED ? TOTAL : 0;
    const paint = () => {
        const reveal = Math.floor(n * step / TOTAL);
        let out = '';
        for (let i = 0; i < n; i++) out += i < reveal ? full[i] : SCRAMBLE[(Math.random() * SCRAMBLE.length) | 0];
        el.replaceChildren(h('span', { class: 'sl' }, '//'), h('b', {}, out.slice(0, cut)), h('i', {}, out.slice(cut)));
    };
    paint();
    if (step >= TOTAL) return;
    scrambleTimer = setInterval(() => { step++; paint(); if (step >= TOTAL) clearInterval(scrambleTimer); }, 32);
};

const openLink = (url) => {
    if (typeof url !== 'string' || !SAFE_URL.test(url)) return;
    if (typeof window.invokeNative === 'function') window.invokeNative('openUrl', url);
};

const renderLinks = () => {
    $('#pmLinks').replaceChildren(...S.links.map(l => h('button', { class: 'pm-link', type: 'button', onclick: () => openLink(l.url) },
        ico(LINK_ICONS[l.id] || 'globe'), String(l.label || l.id))));
};

const fmtNum = (v) => String(Math.trunc(v)).replace(/\B(?=(\d{3})+(?!\d))/g, '\u00a0');
const moneyStr = (v) => (typeof v === 'number' && isFinite(v) ? '$' + fmtNum(v) : '—');

const renderCard = () => {
    const el = $('#pmCard');
    const st = S.stats || {};
    if (!st.name) { el.classList.add('hidden'); return; }
    el.classList.remove('hidden');
    el.replaceChildren(
        h('div', { class: 'nm' }, st.name, st.id != null ? h('em', {}, `[${st.id}]`) : null),
        st.job ? h('div', { class: 'jb' }, h('b', {}, st.job), st.grade || '') : null,
        h('div', { class: 'mn' }, h('span', {}, ico('cash'), moneyStr(st.cash)), h('span', {}, ico('card'), moneyStr(st.bank))));
};

const renderStatic = () => {
    const [ta, tb] = t('pm_title');
    $('#pmTitleA').textContent = ta; $('#pmTitleB').textContent = tb;
    $('#sTitle').textContent = t(S.scope === 'ui' ? 'ui_title' : 'game_title');
    $('#sBack').title = t('back'); $('#pBack').title = t('back');
    $('#sClose').title = t('close'); $('#pClose').title = t('close');
    q.placeholder = t('search');
    const bg = $('#bg');
    bg.style.backgroundImage = (S.bg && S.bg.mode !== 'game' && S.bg.image) ? `url("${S.bg.image}")` : 'none';
    const gta = $('#pmGta');
    gta.textContent = t('all_gta');
    gta.classList.toggle('hidden', !S.gta);
    renderLinks();
    renderCard();
    renderHints();
};

const renderMenu = () => {
    const make = (item, n) => {
        const i = S.menu.indexOf(item);
        const [a, b] = pair(item.id);
        return h('button', {
            class: 'pm-item' + (i === S.mainIdx ? ' sel' : ''), role: 'menuitem', type: 'button', 'data-idx': i, style: `--n:${n}`,
            onmouseenter: () => setMainIdx(i),
            onclick: () => { setMainIdx(i); activateMenu(item.id); },
        }, h('span', { class: 'ind' }), h('span', { class: 'lbl' }, h('b', {}, a), b ? h('i', {}, b) : null),
        item.soon ? h('span', { class: 'pill' }, t('soon_pill')) : null);
    };
    const main = S.menu.filter(it => it.id !== 'quit');
    $('#menuList').replaceChildren(...main.map((it, n) => make(it, n)));
    $('#menuQuit').replaceChildren(...S.menu.filter(it => it.id === 'quit').map(it => make(it, main.length + 1)));
};

const setMainIdx = (i) => {
    if (!S.menu[i]) return;
    const changed = i !== S.mainIdx;
    S.mainIdx = i;
    document.querySelectorAll('.pm-item').forEach((el) => el.classList.toggle('sel', Number(el.dataset.idx) === i));
    if (changed) setSuffix(S.menu[i].id);
};

const activateMenu = async (id) => {
    if (id === 'resume') return post('close');
    if (id === 'game') return openSettings('game');
    if (id === 'ui') return openSettings('ui');
    if (id === 'quit') return confirmQuit();
    const item = S.menu.find(it => it.id === id);
    if (item && item.soon) return toast(t('soon_text'));
    const res = await post('menu', { id });
    if (!res || !res.ok) return;
    if (res.page === 'stats') showPage('stats', id);
    else if (res.page === 'soon') showPage('soon', id);
};

const confirmQuit = () => openModal({
    title: t('quit_title'), text: t('quit_text'),
    buttons: [
        { label: t('cancel'), kind: 'ghost', cancel: true },
        { label: t('quit_disconnect'), onClick: () => post('quit', { mode: 'disconnect' }) },
    ],
});

/* ============================================================ SAYFA (istatistik / yakında) */
const fmtMoney = (v) => (typeof v === 'number' ? '$' + v.toLocaleString(S.lang === 'tr' ? 'tr-TR' : 'en-US') : '—');
const dash = (v) => (v === undefined || v === null || v === '' ? '—' : String(v));

const showPage = (kind, id) => {
    S.page = { kind, id };
    showScreen('page');
    renderPage();
};

const kv = (label, value) => h('div', { class: 'kv' }, h('span', {}, label), h('b', {}, value));

// Sağlık kartı: hastalık yoksa tek satır; varsa her biri için ad + durum + belirti.
const healthRows = () => {
    const hl = S.health || {};
    if (!hl.known) return [h('p', { class: 'health-note' }, t('health_unknown'))];
    if (!hl.conditions || !hl.conditions.length) return [h('p', { class: 'health-note ok' }, t('health_none'))];
    return hl.conditions.map(c => {
        const status = c.suppressed ? t('health_quiet') : (c.bandaged ? t('health_bandaged') : t('health_active'));
        return h('div', { class: 'cond' + (c.suppressed ? ' quiet' : '') },
            h('div', { class: 'cond-head' }, h('b', {}, c.label), h('span', { class: 'chip' }, status)),
            c.symptom && !c.suppressed ? h('small', {}, c.symptom) : null);
    });
};

const renderPage = () => {
    if (!S.page) return;
    const body = $('#pageBody');
    if (S.page.kind === 'stats') {
        $('#pTitle').textContent = t('stats_title');
        const st = S.stats || {};
        const job = st.job ? (st.grade ? `${st.job} — ${st.grade}` : st.job) : null;
        body.replaceChildren(h('div', { class: 'cards' },
            h('div', { class: 'cardx wide' }, h('h4', {}, ico('user'), t('st_character')),
                kv(t('st_name'), dash(st.name)), kv(t('st_cid'), dash(st.cid)), kv(t('st_job'), dash(job))),
            h('div', { class: 'cardx' }, h('h4', {}, ico('wallet'), t('st_finance')),
                kv(t('st_cash'), fmtMoney(st.cash)), kv(t('st_bank'), fmtMoney(st.bank))),
            h('div', { class: 'cardx' }, h('h4', {}, ico('heart'), t('st_health')), ...healthRows())));
    } else {
        $('#pTitle').textContent = lblText(S.page.id);
        body.replaceChildren(h('div', { class: 'soon' }, h('span', { class: 'big' }, ico('clock')), h('h3', {}, t('soon_title')), h('p', {}, t('soon_text'))));
    }
};

/* ============================================================ AYARLAR: veri */
const curCat = () => S.schema[S.cat];
const curGrp = () => (curCat() ? curCat().groups[S.grp] : null);
const hasGroupCol = () => !S.query && !!curCat() && curCat().groups.length > 1;
const hasCatCol = () => S.schema.length > 1;                    // tek kategorili kapsamda (Arayüz Ayarları) kategori sütunu yok

const KEYNAMES = {
    LSHIFT: 'Shift', RSHIFT: 'Shift', SHIFT: 'Shift', LCONTROL: 'Ctrl', RCONTROL: 'Ctrl', CONTROL: 'Ctrl', LMENU: 'Alt', RMENU: 'Alt', MENU: 'Alt',
    SPACE: 'Space', RETURN: 'Enter', BACK: 'Backspace', ESCAPE: 'Esc', TAB: 'Tab', CAPITAL: 'Caps', DELETE: 'Del', INSERT: 'Ins',
    PRIOR: 'PgUp', NEXT: 'PgDn', HOME: 'Home', END: 'End', UP: '↑', DOWN: '↓', LEFT: '←', RIGHT: '→',
    OEM_PERIOD: '.', OEM_COMMA: ',', OEM_PLUS: '=', OEM_MINUS: '-',
};
const MOUSE = {
    b_100: { tr: 'Sol Tık', en: 'Left Click' }, b_101: { tr: 'Sağ Tık', en: 'Right Click' }, b_102: { tr: 'Orta Tık', en: 'Middle Click' },
    b_103: { tr: 'Fare 4', en: 'Mouse 4' }, b_104: { tr: 'Fare 5', en: 'Mouse 5' },
    b_115: { tr: 'Tekerlek ↑', en: 'Wheel ↑' }, b_116: { tr: 'Tekerlek ↓', en: 'Wheel ↓' },
};
const prettyKey = (token) => {
    if (typeof token !== 'string' || !token) return null;
    if (token.startsWith('t_')) {
        const raw = token.slice(2);
        const up = raw.toUpperCase();
        return KEYNAMES[up] || (raw.length === 1 ? up : raw);
    }
    if (MOUSE[token]) return L(MOUSE[token]);
    return S.lang === 'tr' ? 'Fare / Düğme' : 'Mouse / Button';
};

const entryVisible = (r) => !(r.type === 'key' && r.command && !S.keys['m:' + r.command]) && !(r.cap && !S.caps[r.cap]);

const buildEntries = () => {
    const out = [];
    if (S.query) {
        const needle = norm(S.query);
        const seenIds = new Set();
        S.schema.forEach((c, ci) => c.groups.forEach((g, gi) => g.rows.forEach((r, ri) => {
            if (r.type === 'info' || !entryVisible(r)) return;
            if (r.id) { if (seenIds.has(r.id)) return; seenIds.add(r.id); }   // aynı ayar iki grupta olabilir
            const hay = norm([L(r.label), r.label && r.label.tr, r.label && r.label.en, L(r.desc), L(c.label), L(g.label)].join(' '));
            if (hay.includes(needle)) out.push({ key: `${ci}.${gi}.${ri}`, row: r, cat: c, grp: g, crumb: `${L(c.label)} › ${L(g.label)}` });
        })));
    } else if (curGrp()) {
        curGrp().rows.forEach((r, ri) => { if (entryVisible(r)) out.push({ key: `${S.cat}.${S.grp}.${ri}`, row: r, cat: curCat(), grp: curGrp() }); });
    }
    return out;
};

const selectable = (e) => e && e.row.type !== 'info';
const firstSelectable = () => { const i = S.entries.findIndex(selectable); return i < 0 ? 0 : i; };

/* ============================================================ AYARLAR: değer değiştirme */
const fmtSlider = (r, v) => {
    const dec = r.decimals != null ? r.decimals : (r.step < 1 ? 1 : 0);
    return Number(v).toFixed(dec) + (r.unit === '%' ? '%' : r.unit === 'x' ? 'x' : '');
};

const afterChange = (id) => {
    if (id && id.startsWith('pref.')) {
        const langChanged = id === 'pref.lang';
        applyPrefs();
        if (langChanged) { renderAll(); return; }
    }
};

const setValue = async (r, v) => {
    S.values[r.id] = v;
    afterChange(r.id);
    renderRows();
    const res = await post('setting', { id: r.id, value: v });
    if (res && res.value !== undefined && res.value !== null && res.value !== v) {
        S.values[r.id] = res.value;
        afterChange(r.id);
        renderRows();
    }
};

const stepSelect = (r, dir) => {
    const opts = r.options, i = Math.max(0, opts.findIndex(o => o.value === S.values[r.id]));
    setValue(r, opts[(i + dir + opts.length) % opts.length].value);
};

const stepSlider = (r, dir, mult = 1) => {
    const v = S.values[r.id] ?? r.default;
    const n = clamp(Math.round((v + dir * r.step * mult) * 1000) / 1000, r.min, r.max);
    if (n !== v) setValue(r, n);
};

const runAction = (r) => {
    const go = async () => {
        const res = await post('action', { id: r.id });
        if (res && res.values) { Object.assign(S.values, res.values); applyPrefs(); renderAll(); }
        if (res && res.msg) toast(t('msg_' + res.msg));
    };
    if (!r.confirm) return go();
    openModal({
        title: L(r.confirm.title), text: L(r.confirm.text),
        buttons: [
            { label: L(r.confirm.no), kind: 'ghost', cancel: true },
            { label: L(r.confirm.yes), onClick: go },
        ],
    });
};

const openNative = (target) => post('native', { target: target || 'settings' });

// GTA'nın güncel değeri (salt okunur; yalnızca Lua okuyabildiyse gelir). Değiştirmek için satır yerleşik ekranı açar.
const LANG_NAMES = ['English', 'Français', 'Deutsch', 'Italiano', 'Español', 'Português (BR)', 'Polski', 'Русский', '한국어', '繁體中文', '日本語', 'Español (MX)', '简体中文'];
const nativeValue = (r) => {
    if (!r.read) return null;
    const v = S.native[r.read];
    if (v === undefined || v === null) return null;
    switch (r.read) {
        case 'subtitles': return v ? t('on') : t('off');
        case 'metric': return v ? t('metric') : t('imperial');
        case 'safezone': return typeof v === 'number' ? v + '%' : null;
        case 'resolution': return typeof v === 'string' ? v : null;
        case 'language': return LANG_NAMES[v] || null;
        default: return null;
    }
};

const activateRow = (e) => {
    const r = e.row;
    if (r.type === 'toggle') setValue(r, !S.values[r.id]);
    else if (r.type === 'select') stepSelect(r, 1);
    else if (r.type === 'action') runAction(r);
    else if (r.type === 'native') openNative(r.target);
    else if (r.type === 'key') openNative('keybinds');
};

const adjustRow = (e, dir, shift) => {
    const r = e.row;
    if (r.type === 'toggle') { const want = dir > 0; if (!!S.values[r.id] !== want) setValue(r, want); }
    else if (r.type === 'select') stepSelect(r, dir);
    else if (r.type === 'slider') stepSlider(r, dir, shift ? 5 : 1);
    else if (dir < 0) goBack();
};

/* ============================================================ AYARLAR: çizim */
const buildRow = (e, i) => {
    const r = e.row;
    const sel = S.zone === 'rows' && i === S.row;
    const base = `row t-${r.type}` + (sel ? ' sel' : '');
    const mark = () => { S.zone = 'rows'; S.row = i; };

    if (r.type === 'info') return h('div', { class: base }, ico('info'), h('span', {}, L(r.text)));

    const label = h('div', { class: 'r-label' },
        e.crumb ? h('span', { class: 'r-crumb' }, e.crumb) : null,
        h('b', {}, L(r.label)),
        r.desc ? h('small', {}, L(r.desc)) : null);

    if (r.type === 'toggle') {
        const on = !!S.values[r.id];
        return h('div', { class: base, onclick: () => { mark(); setValue(r, !on); } }, label,
            h('div', { class: 'r-ctl' }, h('span', { class: 'sw-text' }, on ? t('on') : t('off')),
                h('button', { class: 'switch', type: 'button', role: 'switch', 'aria-checked': String(on) })));
    }

    if (r.type === 'select') {
        const cur = r.options.find(o => o.value === S.values[r.id]) || r.options[0];
        const arrow = (name, dir) => h('button', { class: 'arr', type: 'button', onclick: (ev) => { ev.stopPropagation(); mark(); stepSelect(r, dir); } }, ico(name));
        return h('div', { class: base, onclick: () => { mark(); stepSelect(r, 1); } }, label,
            h('div', { class: 'r-ctl pick' }, arrow('arrowL', -1),
                h('span', { class: 'val' }, cur.color ? h('i', { class: 'dot', style: `color:${cur.color};background:${cur.color}` }) : null, L(cur.label)),
                arrow('arrowR', 1)));
    }

    if (r.type === 'slider') return buildSlider(e, base, label, mark);

    if (r.type === 'key') {
        const token = r.control != null ? S.keys['c:' + r.control] : S.keys['m:' + r.command];
        const pretty = prettyKey(token);
        return h('div', { class: base, title: t('readonly'), onclick: () => { mark(); renderRows(); } }, label,
            h('div', { class: 'r-ctl' }, pretty ? h('span', { class: 'keycap' }, pretty) : h('span', { class: 'keycap none' }, t('unbound'))));
    }

    if (r.type === 'action') {
        // Kısayol eylemi (r.command): atanmış tuşu da göster
        const pretty = r.command ? prettyKey(S.keys['m:' + r.command]) : null;
        return h('div', { class: base, onclick: () => { mark(); runAction(r); } }, label,
            h('div', { class: 'r-ctl' },
                r.command ? (pretty ? h('span', { class: 'keycap' }, pretty) : h('span', { class: 'keycap none' }, t('unbound'))) : null,
                h('button', { class: 'btn', type: 'button' }, L(r.button))));
    }

    if (r.type === 'native') {
        const cur = nativeValue(r);
        return h('div', { class: base, onclick: () => { mark(); openNative(r.target); } }, label,
            h('div', { class: 'r-ctl' }, cur ? h('span', { class: 'ro-val' }, cur) : null,
                h('span', { class: 'tag' }, t('native_tag')), ico('chevronR')));
    }
    return h('div', { class: base }, label);
};

const buildSlider = (e, base, label, mark) => {
    const r = e.row;
    let v = S.values[r.id] ?? r.default;
    const pct = (x) => ((x - r.min) / (r.max - r.min)) * 100;
    const fill = h('div', { class: 'sl-fill', style: `width:${pct(v)}%` });
    const thumb = h('div', { class: 'sl-thumb', style: `left:${pct(v)}%` });
    const out = h('span', { class: 'sl-val' }, fmtSlider(r, v));
    const track = h('div', { class: 'sl-track' }, fill, thumb);

    let lastSend = 0, timer = null;
    const send = (final) => {
        const now = performance.now();
        clearTimeout(timer);
        if (final || now - lastSend > 70) { lastSend = now; post('setting', { id: r.id, value: v }); }
        else timer = setTimeout(() => send(true), 80);
    };
    const fromEvent = (ev) => {
        const rect = track.getBoundingClientRect();
        const f = clamp((ev.clientX - rect.left) / rect.width, 0, 1);
        const raw = r.min + f * (r.max - r.min);
        v = clamp(Math.round(((Math.round((raw - r.min) / r.step) * r.step) + r.min) * 1000) / 1000, r.min, r.max);
        S.values[r.id] = v;
        fill.style.width = pct(v) + '%'; thumb.style.left = pct(v) + '%'; out.textContent = fmtSlider(r, v);
    };
    track.addEventListener('pointerdown', (ev) => {
        ev.stopPropagation();
        mark();
        track.setPointerCapture(ev.pointerId);
        fromEvent(ev); send(false);
        const move = (m) => { fromEvent(m); send(false); };
        const up = () => { track.removeEventListener('pointermove', move); track.removeEventListener('pointerup', up); send(true); };
        track.addEventListener('pointermove', move);
        track.addEventListener('pointerup', up);
    });
    return h('div', { class: base }, label, h('div', { class: 'r-ctl sl' }, track, out));
};

const renderCats = () => {
    const col = $('#colCats');
    $('#sBody').classList.toggle('no-cats', !hasCatCol());
    col.replaceChildren(...S.schema.map((c, i) => h('button', {
        class: 'nav-item' + (i === S.cat ? ' cur' : ''), type: 'button',
        onclick: () => { S.cat = i; S.grp = 0; S.zone = 'cats'; S.query = ''; q.value = ''; refreshSettings(true); },
    }, ico(c.icon), h('span', {}, L(c.label)))));
    const cur = col.querySelector('.cur');
    if (cur) cur.scrollIntoView({ block: 'nearest' });
};

const renderGroups = () => {
    const col = $('#colGrps');
    const on = hasGroupCol();
    $('#sBody').classList.toggle('no-grp', !on);
    if (!on) { col.replaceChildren(); return; }
    col.replaceChildren(...curCat().groups.map((g, i) => h('button', {
        class: 'nav-item' + (i === S.grp ? ' cur' : ''), type: 'button',
        onclick: () => { S.grp = i; S.zone = 'grps'; refreshSettings(true); },
    }, h('span', {}, L(g.label)))));
    const cur = col.querySelector('.cur');
    if (cur) cur.scrollIntoView({ block: 'nearest' });
};

const renderRows = (resetScroll) => {
    const list = $('#rowsList');
    const prev = list.scrollTop;
    S.entries = buildEntries();
    if (S.row >= S.entries.length) S.row = Math.max(0, S.entries.length - 1);

    const crumb = $('#crumb');
    if (S.query) crumb.replaceChildren(`${S.entries.length} ${t('hint_search').toLowerCase()}`);
    else if (curCat()) crumb.replaceChildren(h('b', {}, L(curCat().label)), curGrp() && curCat().groups.length > 1 ? ` › ${L(curGrp().label)}` : '');

    if (!S.entries.length) list.replaceChildren(h('div', { class: 'empty' }, t('no_results')));
    else list.replaceChildren(...S.entries.map((e, i) => buildRow(e, i)));
    list.scrollTop = resetScroll ? 0 : prev;
};

const paintZones = () => {
    $('#colCats').classList.toggle('active', S.zone === 'cats');
    $('#colGrps').classList.toggle('active', S.zone === 'grps');
};

const refreshSettings = (resetScroll) => {
    if (resetScroll) { S.entries = buildEntries(); S.row = firstSelectable(); }
    renderCats(); renderGroups(); renderRows(resetScroll); paintZones();
};

const scrollSelected = () => {
    const el = $('#rowsList .row.sel');
    if (el) el.scrollIntoView({ block: 'nearest' });
};

// scope: 'game' → tüm ayar kategorileri (Tercihler hariç), 'ui' → yalnızca Tercihler (arayüz görünümü)
const scopeSchema = (scope) => S.allSchema.filter(c => (scope === 'ui' ? c.id === 'prefs' : c.id !== 'prefs'));

const openSettings = (scope = 'game') => {
    S.scope = scope; S.schema = scopeSchema(scope);
    S.cat = 0; S.grp = 0; S.row = 0; S.query = ''; q.value = '';
    S.zone = hasCatCol() ? 'cats' : (hasGroupCol() ? 'grps' : 'rows');
    $('#sTitle').textContent = t(scope === 'ui' ? 'ui_title' : 'game_title');
    showScreen('settings');
    refreshSettings(true);
    if (S.zone === 'rows') paintZones();
};

/* ============================================================ GERİ / NAVİGASYON */
const goBack = () => {
    if (S.modal) { closeModal(); return; }
    if (S.screen === 'page') { showScreen('main'); return; }
    if (S.screen !== 'settings') return;
    if (S.query) { S.query = ''; q.value = ''; S.zone = 'rows'; refreshSettings(true); return; }
    if (S.zone === 'rows' && (hasGroupCol() || hasCatCol())) { S.zone = hasGroupCol() ? 'grps' : 'cats'; renderRows(); paintZones(); return; }
    if (S.zone === 'grps' && hasCatCol()) { S.zone = 'cats'; renderRows(); paintZones(); return; }
    showScreen('main');
};

const moveRow = (delta) => {
    if (!S.entries.length) return;
    let i = S.row;
    do { i += delta; } while (i >= 0 && i < S.entries.length && !selectable(S.entries[i]));
    if (i < 0 || i >= S.entries.length) return;
    S.row = i;
    renderRows();
    scrollSelected();
};

const enterRows = () => { S.zone = 'rows'; S.row = firstSelectable(); renderRows(); paintZones(); scrollSelected(); };

/* ============================================================ MODAL / TOAST */
const modalEl = $('#modal');
// Düğmeler yalnızca bir kez oluşturulur; seçim değişince sadece sınıf güncellenir. (Fare üstündeyken düğmeleri yeniden
// çizmek mousedown ile mouseup arasında öğeyi değiştirir ve "click" hiç oluşmaz.)
const paintModal = () => {
    const m = S.modal;
    if (!m) return;
    $('#modalBtns').querySelectorAll('.btn').forEach((el, i) => el.classList.toggle('sel', i === m.idx));
};
const renderModal = () => {
    const m = S.modal;
    $('#modalBtns').replaceChildren(...m.buttons.map((b, i) => h('button', {
        class: 'btn' + (b.kind === 'ghost' ? ' ghost' : '') + (i === m.idx ? ' sel' : ''), type: 'button',
        onmouseenter: () => { m.idx = i; paintModal(); },
        onclick: () => runModalButton(b),
    }, b.label)));
};
const openModal = ({ title, text, buttons }) => {
    S.modal = { buttons, idx: 0 };
    $('#modalTitle').textContent = title;
    $('#modalText').textContent = text;
    modalEl.classList.remove('hidden');
    renderModal();
};
const closeModal = () => { S.modal = null; modalEl.classList.add('hidden'); };
const runModalButton = (b) => { closeModal(); if (b.onClick) b.onClick(); };

let toastTimer = null;
const toast = (msg) => {
    const el = $('#toast');
    el.textContent = msg;
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('show'), 2200);
};

/* ============================================================ BÜYÜK HARİTA ARAMA PANELİ */
// Lua (client/main.lua) haritadaki işaretleri tarar ve listeyi gönderir; filtre burada, yazdıkça çalışır. Koordinat arayüze GELMEZ:
// seçimde yalnızca liste kimliği (id) Lua'ya gider, GPS'i Lua kurar.
const M = { shown: false, focused: false, items: [], query: '', sel: 0, shownList: [] };
const mapRoot = $('#mapSearch'), msq = $('#msq');

const fmtDist = (d) => (d < 1000 ? `${d} m` : `${(d / 1000).toFixed(1)} km`);

const msFilter = () => {
    const toks = norm(M.query).split(/\s+/).filter(Boolean);
    if (!toks.length) return M.items;
    const list = M.items.filter(e => toks.every(tk => e.nn.includes(tk)));
    list.sort((a, b) => (b.nn.startsWith(toks[0]) - a.nn.startsWith(toks[0])) || (a.d - b.d));   // başı eşleşen önce, sonra yakın olan
    return list;
};

const msPaintSel = () => {
    const rows = $('#msList').querySelectorAll('.ms-row');
    rows.forEach((el, i) => el.classList.toggle('sel', i === M.sel));
    const cur = rows[M.sel];
    if (cur) cur.scrollIntoView({ block: 'nearest' });
};

let flashTimer = null;
const msHint = () => {
    const el = $('#msHint');
    el.classList.remove('ok');
    const key = M.key ? prettyKey(M.key) : null;
    el.textContent = M.focused ? t('ms_active') : `${t('ms_idle')}${key ? ' ' + key : ''}`;
};
const msFlash = (text) => {
    const el = $('#msHint');
    clearTimeout(flashTimer);
    el.textContent = text; el.classList.add('ok');
    flashTimer = setTimeout(msHint, 2200);
};

const msPick = (e) => {
    if (!e) return;
    post('mapPick', { id: e.id }).then(res => { if (res && res.ok) msFlash(`${t('ms_set')}: ${String(res.name || e.n)}`); });
};

const msRender = () => {
    $('#msq').placeholder = t('ms_placeholder');
    $('#msKey').textContent = M.key ? (prettyKey(M.key) || '') : '';
    $('#msKey').classList.toggle('hidden', !M.key);
    const list = msFilter();
    M.shownList = list.slice(0, 200);
    $('#msCount').textContent = `${list.length} ${t('ms_places')}`;
    if (M.sel >= M.shownList.length) M.sel = Math.max(0, M.shownList.length - 1);
    $('#msList').replaceChildren(...(M.shownList.length ? M.shownList.map((e, i) => h('button', {
        class: 'ms-row' + (i === M.sel ? ' sel' : ''), type: 'button',
        onmouseenter: () => { M.sel = i; msPaintSel(); },      // yeniden çizme yok: tıklama kaybolmasın
        onclick: () => msPick(e),
    }, h('b', {}, e.n), h('span', {}, fmtDist(e.d)))) : [h('div', { class: 'ms-empty' }, t('ms_none'))]));
    msHint();
};

const msGeo = (g) => {
    const ok = (v, d) => (typeof v === 'number' && v >= 0 && v <= 1 ? v : d);
    const st = document.documentElement.style;
    g = g || {};
    st.setProperty('--ms-l', ok(g.left, .76)); st.setProperty('--ms-r', ok(g.right, .98));
    st.setProperty('--ms-t', ok(g.top, .06)); st.setProperty('--ms-b', ok(g.bottom, .94));
};

const onMapPanel = (d) => {
    if (!d.show) {
        M.shown = false; M.focused = false; M.items = [];
        mapRoot.classList.add('hidden'); mapRoot.classList.remove('active');
        msq.value = ''; M.query = ''; M.sel = 0; msq.blur();
        return;
    }
    M.items = (Array.isArray(d.items) ? d.items : []).slice(0, 700)
        .filter(e => e && typeof e.id === 'number' && typeof e.n === 'string')
        .map(e => ({ id: e.id, n: e.n.slice(0, 60), d: Number.isFinite(e.d) ? Math.max(0, Math.round(e.d)) : 0, nn: norm(e.n) }));
    M.key = typeof d.key === 'string' ? d.key : null;
    M.shown = true; M.focused = false; M.query = ''; M.sel = 0; msq.value = '';
    msGeo(d.geo);
    mapRoot.classList.remove('hidden', 'active');
    msRender();
};

const onMapFocus = (d) => {
    M.focused = !!d.on && M.shown;
    mapRoot.classList.toggle('active', M.focused);
    if (M.focused) { msq.focus(); msq.select(); } else msq.blur();
    msHint();
};

msq.addEventListener('input', () => { M.query = msq.value; M.sel = 0; msRender(); });
// Panelin dışına tıklamak arama modunu bitirir (fare yeniden haritayı sürükleyebilir)
document.addEventListener('mousedown', (ev) => { if (M.focused && !ev.target.closest('.ms-box')) post('mapSearchExit'); });

// Arama modunda klavye: yazı kutuya gider; yön tuşları listede gezer, Enter GPS kurar, ESC modu bitirir (haritayı kapatmaz)
const onMapKey = (ev) => {
    const k = ev.key;
    if (k === 'Escape') { ev.preventDefault(); post('mapSearchExit'); return true; }
    if (k === 'ArrowDown' || k === 'ArrowUp') {
        if (M.shownList.length) { M.sel = (M.sel + (k === 'ArrowDown' ? 1 : -1) + M.shownList.length) % M.shownList.length; msPaintSel(); }
        ev.preventDefault(); return true;
    }
    if (k === 'Enter') { ev.preventDefault(); msPick(M.shownList[M.sel]); return true; }
    return false;
};

/* ============================================================ KLAVYE */
const onKey = (ev) => {
    if (M.focused) { onMapKey(ev); return; }      // arama modunda menü tuşları devre dışı
    if (!S.open) return;
    const k = ev.key;

    if (k === 'Escape') { ev.preventDefault(); post('close'); return; }

    if (S.modal) {
        const m = S.modal;
        if (k === 'ArrowLeft') { m.idx = (m.idx - 1 + m.buttons.length) % m.buttons.length; paintModal(); }
        else if (k === 'ArrowRight') { m.idx = (m.idx + 1) % m.buttons.length; paintModal(); }
        else if (k === 'Enter' || k === ' ') runModalButton(m.buttons[m.idx]);
        else if (k === 'Backspace') closeModal();
        else return;
        ev.preventDefault();
        return;
    }

    if (ev.target === q) {
        if (k === 'ArrowDown' || k === 'Enter') { ev.preventDefault(); q.blur(); S.zone = 'rows'; S.row = firstSelectable(); renderRows(); paintZones(); scrollSelected(); }
        return;
    }

    if (S.screen === 'main') {
        if (k === 'ArrowUp') setMainIdx((S.mainIdx - 1 + S.menu.length) % S.menu.length);
        else if (k === 'ArrowDown') setMainIdx((S.mainIdx + 1) % S.menu.length);
        else if (k === 'Enter' || k === ' ') activateMenu(S.menu[S.mainIdx].id);
        else return;
        ev.preventDefault();
        return;
    }

    if (S.screen === 'page') {
        if (k === 'Backspace') { ev.preventDefault(); goBack(); }
        return;
    }

    // ayarlar
    if (k === 'Backspace') { ev.preventDefault(); goBack(); return; }
    if (k === '/') { ev.preventDefault(); S.zone = 'search'; q.focus(); return; }

    if (S.zone === 'cats') {
        if (k === 'ArrowUp' || k === 'ArrowDown') {
            S.cat = (S.cat + (k === 'ArrowDown' ? 1 : -1) + S.schema.length) % S.schema.length;
            S.grp = 0; refreshSettings(true);
        } else if (k === 'ArrowRight' || k === 'Enter') {
            if (hasGroupCol()) { S.zone = 'grps'; paintZones(); } else enterRows();
        } else return;
    } else if (S.zone === 'grps') {
        const n = curCat().groups.length;
        if (k === 'ArrowUp' || k === 'ArrowDown') { S.grp = (S.grp + (k === 'ArrowDown' ? 1 : -1) + n) % n; refreshSettings(true); S.zone = 'grps'; paintZones(); }
        else if (k === 'ArrowRight' || k === 'Enter') enterRows();
        else if (k === 'ArrowLeft' && hasCatCol()) { S.zone = 'cats'; paintZones(); }
        else return;
    } else {
        const e = S.entries[S.row];
        if (k === 'ArrowUp') moveRow(-1);
        else if (k === 'ArrowDown') moveRow(1);
        else if ((k === 'ArrowLeft' || k === 'ArrowRight') && e) adjustRow(e, k === 'ArrowRight' ? 1 : -1, ev.shiftKey);
        else if ((k === 'Enter' || k === ' ') && e) activateRow(e);
        else return;
    }
    ev.preventDefault();
};
window.addEventListener('keydown', onKey, true);

q.addEventListener('focus', () => { S.zone = 'search'; renderRows(); paintZones(); });
q.addEventListener('input', () => {
    S.query = q.value.trim();
    S.zone = 'search';
    refreshSettings(true);
});

/* ============================================================ GENEL ÇİZİM + NUI MESAJLARI */
const renderAll = () => {
    applyPrefs();
    renderStatic();
    renderMenu();
    if (S.screen === 'settings') refreshSettings(false);
    if (S.screen === 'page') renderPage();
};

$('#sBack').addEventListener('click', goBack);
$('#pBack').addEventListener('click', goBack);
$('#sClose').addEventListener('click', () => post('close'));
$('#pClose').addEventListener('click', () => post('close'));
modalEl.addEventListener('click', (ev) => { if (ev.target === modalEl) closeModal(); });
document.querySelectorAll('[data-i]').forEach(el => { el.innerHTML = window.icon(el.dataset.i); });

const onInit = (d) => {
    S.allSchema = Array.isArray(d.schema) ? d.schema.filter(c => c && !c.hidden) : [];
    S.schema = scopeSchema(S.scope);
    S.links = Array.isArray(d.links) ? d.links.filter(l => l && typeof l.url === 'string' && SAFE_URL.test(l.url)).slice(0, 4) : [];
    S.gta = d.gta !== false;
    if (d.bg) S.bg = d.bg;
    indexSchema();
    renderAll();
};

const onOpen = (d) => {
    S.values = d.values || {};
    S.keys = d.keys || {};
    S.native = d.native || {};
    S.caps = d.caps || {};
    S.menu = (Array.isArray(d.menu) && d.menu.length) ? d.menu : DEFAULT_MENU;
    S.stats = d.stats || null;
    S.health = d.health || { known: false, conditions: [] };
    S.mainIdx = 0; S.cat = 0; S.grp = 0; S.row = 0; S.zone = 'cats'; S.query = ''; q.value = '';
    S.scope = 'game'; S.schema = scopeSchema('game');
    closeModal();
    applyPrefs();
    showScreen('main');
    renderAll();
    setSuffix(S.menu[0] && S.menu[0].id);

    app.classList.remove('hidden', 'anim-open', 'anim-return', 'on');
    void app.offsetWidth;
    app.classList.add(d.anim === 'return' ? 'anim-return' : 'anim-open');
    requestAnimationFrame(() => app.classList.add('on'));
    S.open = true;
};

const onClose = () => {
    S.open = false;
    app.classList.remove('on');
    setTimeout(() => { if (!S.open) app.classList.add('hidden'); }, 240);
};

window.addEventListener('message', (ev) => {
    const d = ev.data;
    if (!d || !d.action) return;
    if (d.action === 'init') onInit(d);
    else if (d.action === 'open') onOpen(d);
    else if (d.action === 'close') onClose();
    else if (d.action === 'mapPanel') onMapPanel(d);
    else if (d.action === 'mapFocus') onMapFocus(d);
    else if (d.action === 'caps') {
        S.caps = d.caps || {};
        if (S.screen === 'settings') refreshSettings(false);
    }
    else if (d.action === 'health') {
        S.health = d.health || { known: false, conditions: [] };
        if (S.screen === 'page' && S.page && S.page.kind === 'stats') renderPage();
    }
});

// Lua tarafı (callback'ler) NUI'den biraz geç hazır olabilir → ilk yanıt gelene kadar dene.
(async function boot() {
    for (let i = 0; i < 40; i++) {
        const res = await post('ready');
        if (res && res.ok) return;
        await new Promise(r => setTimeout(r, 500));
    }
})();

})();
