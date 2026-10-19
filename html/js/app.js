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
        menu_stats: ['KARAKTER', 'İSTATİSTİKLERİ'], menu_battlepass: ['BATTLE', 'PASS'],
        menu_shop: ['SHOP', ''], menu_quit: ['AYRIL', ''],
        game_title: 'Oyun Ayarları', ui_title: 'Arayüz Ayarları',
        opts_title: 'SEÇENEKLER', search_title: 'Arama', restore: ['SAYFAYI', 'SIFIRLA'], restore_title: 'Varsayılana dön?',
        restore_text: 'Bu sayfadaki ayarlar varsayılan değerlerine döner. Diğer sayfalar etkilenmez.', restore_yes: 'Evet, sıfırla',
        msg_restored: 'Varsayılanlar geri yüklendi',
        gta_settings: 'GTA Ayarları', gta_row: 'GTA ayar ekranı', gta_btn: 'Aç',
        gta_text: 'Grafik ayarları (doku, gölge, çözünürlük...), tuş atamaları ve diğer ayarlar GTA\'nın kendi ayar ekranında değiştirilir. Enter ile aç; ESC ile kapatınca buraya dönersin (Arayüz Ayarları → Menü Davranışı).',
        gta_apply: ['DEĞİŞİKLİKLERİ', 'UYGULA'], gta_applying: 'Uygulanıyor…', gta_wait: 'GTA ayarları uygulanıyor, lütfen bekle…',
        msg_gta_ok: 'GTA ayarları uygulandı', msg_gta_fail: 'Bazı ayarlar uygulanamadı',
        gta_leave_title: 'Uygulanmamış değişiklikler', gta_leave_text: 'GTA ayarlarında henüz uygulanmamış değişikliklerin var.',
        gta_leave_apply: 'Şimdi uygula', gta_leave_discard: 'Vazgeç ve çık', gta_leave_keep: 'Düzenlemeye devam',
        settings: 'Ayarlar', search: 'Ayarlarda ara…', no_results: 'Sonuç bulunamadı',
        hint_move: 'Gezin', hint_change: 'Değiştir', hint_select: 'Seç', hint_resume: 'Devam', hint_back: 'Geri', hint_close: 'Kapat', hint_search: 'Ara',
        on: 'Açık', off: 'Kapalı', metric: 'Metrik (km)', imperial: 'İngiliz (mil)', readonly: 'Salt okunur — değiştirmek için GTA Ayarları → Tuş Atamaları', unbound: 'Atanmamış',
        soon_pill: 'Yakında', soon_title: 'Yakında', soon_text: 'Bu özellik henüz sunucuda aktif değil. Çok yakında burada olacak.',
        quit_title: 'Oyundan çık?', quit_text: 'Sunucudan ayrılıp FiveM ana menüsüne dönersin.',
        quit_disconnect: 'Sunucudan ayrıl', cancel: 'Vazgeç',
        stats_title: 'Karakter İstatistikleri', st_character: 'Karakter', st_name: 'Ad Soyad', st_cid: 'Vatandaş No', st_job: 'Meslek',
        st_finance: 'Finans', st_cash: 'Nakit', st_bank: 'Banka',
        st_health: 'Sağlık', health_none: 'Hastalığın yok. Sağlıklısın.', health_unknown: 'Sağlık bilgisi alınıyor…',
        health_active: 'Aktif', health_quiet: 'İlaç etkisinde — belirtiler sessiz', health_bandaged: 'Sargılı',
        msg_rec_started: 'Kayıt başladı', msg_rec_saved: 'Klip kaydedildi', msg_rec_discarded: 'Kayıt iptal edildi', msg_reset_done: 'Görünüm varsayılana döndü',
        back: 'Geri', close: 'Kapat',
    },
    en: {
        pm_title: ['PAUSE', 'MENU'],
        menu_resume: ['RESUME', ''], menu_map: ['MAP', ''], menu_game: ['GAME', 'SETTINGS'], menu_ui: ['UI', 'SETTINGS'],
        menu_stats: ['CHARACTER', 'STATS'], menu_battlepass: ['BATTLE', 'PASS'],
        menu_shop: ['SHOP', ''], menu_quit: ['DISCONNECT', ''],
        game_title: 'Game Settings', ui_title: 'UI Settings',
        opts_title: 'OPTIONS', search_title: 'Search', restore: ['RESTORE', 'DEFAULTS'], restore_title: 'Restore defaults?',
        restore_text: 'The settings on this page return to their defaults. Other pages are not affected.', restore_yes: 'Yes, restore',
        msg_restored: 'Defaults restored',
        gta_settings: 'GTA Settings', gta_row: 'GTA settings screen', gta_btn: 'Open',
        gta_text: 'Graphics settings (texture, shadows, resolution...), key bindings and other options are changed in GTA\'s own settings screen. Press Enter to open it; closing it with ESC can bring you back here (UI Settings → Menu Behaviour).',
        gta_apply: ['APPLY', 'CHANGES'], gta_applying: 'Applying…', gta_wait: 'Applying GTA settings, please wait…',
        msg_gta_ok: 'GTA settings applied', msg_gta_fail: 'Some settings could not be applied',
        gta_leave_title: 'Unapplied changes', gta_leave_text: 'You have GTA setting changes that were not applied yet.',
        gta_leave_apply: 'Apply now', gta_leave_discard: 'Discard and leave', gta_leave_keep: 'Keep editing',
        settings: 'Settings', search: 'Search settings…', no_results: 'No results',
        hint_move: 'Navigate', hint_change: 'Change', hint_select: 'Select', hint_resume: 'Resume', hint_back: 'Back', hint_close: 'Close', hint_search: 'Search',
        on: 'On', off: 'Off', metric: 'Metric (km)', imperial: 'Imperial (mi)', readonly: 'Read-only — to rebind, open GTA Settings → Key Bindings', unbound: 'Unbound',
        soon_pill: 'Soon', soon_title: 'Coming soon', soon_text: 'This feature is not active on the server yet. It will be here soon.',
        quit_title: 'Disconnect?', quit_text: 'You will leave the server and return to the FiveM main menu.',
        quit_disconnect: 'Leave server', cancel: 'Cancel',
        stats_title: 'Character Stats', st_character: 'Character', st_name: 'Name', st_cid: 'Citizen ID', st_job: 'Job',
        st_finance: 'Finances', st_cash: 'Cash', st_bank: 'Bank',
        st_health: 'Health', health_none: 'No illness. You are healthy.', health_unknown: 'Loading health info…',
        health_active: 'Active', health_quiet: 'Medicated — symptoms quiet', health_bandaged: 'Bandaged',
        msg_rec_started: 'Recording started', msg_rec_saved: 'Clip saved', msg_rec_discarded: 'Recording discarded', msg_reset_done: 'Appearance reset to defaults',
        back: 'Back', close: 'Close',
    },
};

const DEFAULT_MENU = ['resume', 'map', 'game', 'ui', 'stats', 'battlepass', 'shop', 'quit'].map(id => ({ id, available: true, soon: id === 'battlepass' || id === 'shop' }));
const LINK_ICONS = { youtube: 'youtube', store: 'globe', discord: 'discord' };
// Yalnızca bu ana makineden gelen (Lua yapılandırmasından) https adresleri açılır; arayüzden adres alınmaz.
const SAFE_URL = /^https:\/\/[^\s"'<>]+$/i;

/* ============================================================ DURUM */
const S = {
    open: false, lang: 'en',
    allSchema: [], schema: [], scope: 'game', links: [], gta: true, bg: { mode: 'game' }, subSent: false,
    values: {}, keys: {}, caps: {}, menu: DEFAULT_MENU, stats: null, health: { known: false, conditions: [] },
    screen: 'main', page: null,
    mainIdx: 0, cat: 0, grp: 0, row: 0, zone: 'cats', query: '', entries: [],
    modal: null,
    // GTA'nın kendi ayarları: gset = güncel profil değerleri, gpend = henüz uygulanmamış değişiklikler, glabels = GTA metinleri
    gset: {}, gpend: {}, glabels: {}, gbusy: false,
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
    return m ? [parseInt(m[1], 16), parseInt(m[2], 16), parseInt(m[3], 16)] : [227, 32, 74];
};

const applyPrefs = () => {
    S.lang = S.values['pref.lang'] === 'tr' ? 'tr' : 'en';
    document.documentElement.lang = S.lang;

    const def = rowIndex['pref.accent'];
    const cur = def && (def.options.find(o => o.value === S.values['pref.accent']) || def.options[0]);
    const color = (cur && cur.color) || '#e3204a';
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
// main: ana menü; settings: ana menü SOLDA kalır, yanında OPTIONS + ayar paneli açılır; page: tam sayfa (istatistik / yakında)
const screens = { main: $('#screenMain'), settings: $('#screenSettings'), page: $('#screenPage') };
const showScreen = (name) => {
    S.screen = name;
    screens.main.classList.toggle('hidden', name === 'page');
    screens.settings.classList.toggle('hidden', name !== 'settings');
    screens.page.classList.toggle('hidden', name !== 'page');
    $('#hintsMain').classList.toggle('hidden', name === 'page');
    renderHints();
    syncSub();
};

// Lua'ya "alt ekrandayım" bilgisi: bu sırada ESC menüyü kapatmaz, bir adım geri döner (yalnızca arayüz işler)
const syncSub = () => {
    const sub = S.screen !== 'main' || !!S.modal;
    if (sub !== S.subSent) { S.subSent = sub; post('sub', { on: sub }); }
};

// replaceChildren(null) metin olarak "null" ekler: boş öğeleri süz
const setKids = (el, ...kids) => el.replaceChildren(...kids.flat(Infinity).filter(k => k !== null && k !== undefined && k !== false));

const hintSpan = (keys, label) => h('span', {}, keys.map(k => h('kbd', {}, k)), label);
const renderHints = () => {
    const main = $('#hintsMain'), pg = $('#hintsPage');
    if (S.screen === 'main') {
        main.replaceChildren(hintSpan(['↑', '↓'], t('hint_move')), hintSpan(['ENTER'], t('hint_select')), hintSpan(['ESC'], t('hint_resume')));
    } else {
        main.replaceChildren(hintSpan(['ESC'], t('hint_back')), hintSpan(['↑', '↓'], t('hint_move')), hintSpan(['ENTER'], t('hint_select')), hintSpan(['←', '→'], t('hint_change')));
    }
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
    setKids(el,
        h('div', { class: 'nm' }, st.name, st.id != null ? h('em', {}, `[${st.id}]`) : null),
        st.job ? h('div', { class: 'jb' }, h('b', {}, st.job), st.grade || '') : null,
        h('div', { class: 'mn' }, h('span', {}, ico('cash'), moneyStr(st.cash)), h('span', {}, ico('card'), moneyStr(st.bank))));
};

const renderStatic = () => {
    const [ta, tb] = t('pm_title');
    $('#pmTitleA').textContent = ta; $('#pmTitleB').textContent = tb;
    $('#pBack').title = t('back');
    $('#pClose').title = t('close');
    { const [ra, rb] = t('restore'); setKids($('#gsRestore'), h('b', {}, ra), rb ? h('i', {}, ' ' + rb) : null); }
    q.placeholder = t('search');
    const bg = $('#bg');
    bg.style.backgroundImage = (S.bg && S.bg.mode !== 'game' && S.bg.image) ? `url("${S.bg.image}")` : 'none';
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
            onmouseenter: () => { if (S.screen === 'main') setMainIdx(i); },
            onclick: () => { if (S.screen === 'main') setMainIdx(i); activateMenu(item.id); },
        }, h('span', { class: 'ind' }), h('span', { class: 'lbl' }, h('b', {}, a), b ? h('i', {}, b) : null),
        item.soon ? h('span', { class: 'pill' }, t('soon_pill')) : null);
    };
    $('#menuList').replaceChildren(...S.menu.map((it, n) => make(it, n)));
};

const setMainIdx = (i) => {
    if (!S.menu[i]) return;
    const changed = i !== S.mainIdx;
    S.mainIdx = i;
    document.querySelectorAll('.pm-item').forEach((el) => el.classList.toggle('sel', Number(el.dataset.idx) === i));
    if (changed) setSuffix(S.menu[i].id);
};

const activateMenu = async (id) => {
    if (id === 'resume') return guardPending(() => post('close'));
    if (id === 'game') return openSettings('game');
    if (id === 'ui') return openSettings('ui');
    if (id === 'quit') return confirmQuit();
    const item = S.menu.find(it => it.id === id);
    if (item && item.soon) return showPage('soon', id);
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
// Game Settings'te OPTIONS'ın son maddesi: GTA'nın kendi ayar ekranı (kategori değil; S.cat === S.schema.length)
const hasGtaOpt = () => S.scope === 'game' && S.gta;
const optCount = () => S.schema.length + (hasGtaOpt() ? 1 : 0);
const gtaSelected = () => hasGtaOpt() && S.cat === S.schema.length;
const gtaEntries = () => [
    { key: 'gta.info', row: { type: 'info', text: { tr: STR.tr.gta_text, en: STR.en.gta_text } } },
    { key: 'gta.open', row: { type: 'gta', label: { tr: STR.tr.gta_row, en: STR.en.gta_row } } },
];

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
    if (!S.query && gtaSelected()) return gtaEntries();
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
    } else if (curCat()) {
        // Bir kategorinin tüm grupları tek listede; birden çok grup varsa her grubun başına küçük başlık
        const multi = curCat().groups.length > 1;
        curCat().groups.forEach((g, gi) => {
            const rows = g.rows.map((r, ri) => ({ r, ri })).filter(x => entryVisible(x.r));
            if (!rows.length) return;
            if (multi) out.push({ key: `h${S.cat}.${gi}`, head: L(g.label), row: { type: 'head' } });
            rows.forEach(({ r, ri }) => out.push({ key: `${S.cat}.${gi}.${ri}`, row: r, cat: curCat(), grp: g }));
        });
    }
    return out;
};

const selectable = (e) => e && e.row.type !== 'info' && e.row.type !== 'head';
const firstSelectable = () => { const i = S.entries.findIndex(selectable); return i < 0 ? 0 : i; };

/* ============================================================ GTA AYARLARI (profil değerleri; "Uygula" ile yazılır) */
const gCur = (r) => S.gset[r.pid] ?? 0;
const gVal = (r) => (S.gpend[r.pid] !== undefined ? S.gpend[r.pid] : gCur(r));
const gMax = (r) => (r.type === 'glist' ? (r.labels || []).length - 1 : (r.max || 0));
const gPendingCount = () => Object.keys(S.gpend).length;
const gHuman = (id) => String(id).replace(/^MO_/, '').replace(/_/g, ' ').toLowerCase().replace(/^./, (c) => c.toUpperCase());
const gText = (id) => S.glabels[id] || gHuman(id);
const gDisplay = (r, v) => (r.inv ? gMax(r) - v : v);          // ters kaydırıcıda (güvenli bölge) sağ = küçük profil değeri
const gShow = (r, v) => `${(r.base || 0) + gDisplay(r, v)}${r.unit || ''}`;   // ör. güvenli bölge: %90..%100

// Şemadaki GTA satırlarına GTA'nın kendi metinlerini (oyuncunun GTA diliyle) etiket olarak yazar
const applyGtaLabels = () => {
    for (const c of S.allSchema) for (const g of c.groups) for (const r of g.rows) {
        if (r.type === 'gtaslider' || r.type === 'glist') { const s = gText(r.text); r.label = { tr: s, en: s }; }
    }
};

const setG = (r, v) => {
    if (S.gbusy) return;
    v = clamp(Math.round(v), 0, gMax(r));
    if (v === gCur(r)) delete S.gpend[r.pid]; else S.gpend[r.pid] = v;
};

// dir > 0: sağ ok. Liste: döner; kaydırıcı: uçta durur (ters kaydırıcıda sağ ok profil değerini azaltır)
const stepG = (r, dir, shift) => {
    const v = gVal(r), max = gMax(r);
    if (r.type === 'glist') { setG(r, (v + dir + max + 1) % (max + 1)); return; }
    const unit = (max > 30 ? Math.round(max / 40) : 1) * (shift ? 5 : 1);
    setG(r, v + (r.inv ? -dir : dir) * unit);
};

const renderApply = () => {
    const b = $('#gsApply'), n = gPendingCount();
    b.classList.toggle('hidden', n === 0 && !S.gbusy);
    b.disabled = S.gbusy;
    if (S.gbusy) setKids(b, h('span', { class: 'spin' }), t('gta_applying'));
    else { const [a, c] = t('gta_apply'); setKids(b, h('b', {}, a), c ? h('i', {}, ' ' + c) : null, h('em', {}, ` (${n})`)); }
    app.classList.toggle('gbusy', S.gbusy);
};

const applyGta = async () => {
    if (S.gbusy || !gPendingCount()) return;
    S.gbusy = true;
    renderApply();
    toast(t('gta_wait'));
    const res = await post('gtaApply', { changes: S.gpend });
    if (!res || !res.ok) { S.gbusy = false; S.gpend = {}; renderApply(); renderRows(); toast(t('msg_gta_fail')); }
};

const onGtaDone = (d) => {
    S.gbusy = false;
    if (d.values && typeof d.values === 'object') S.gset = d.values;
    S.gpend = {};
    renderApply();
    if (S.screen === 'settings') renderRows();
    toast(t(d.ok ? 'msg_gta_ok' : 'msg_gta_fail'));
};

// Uygulanmamış GTA değişikliği varken ayarlardan çıkış: uygula / vazgeç / düzenlemeye devam
const guardPending = (leave) => {
    if (!gPendingCount() || S.gbusy) { leave(); return; }
    openModal({
        title: t('gta_leave_title'), text: t('gta_leave_text'),
        buttons: [
            { label: t('gta_leave_keep'), kind: 'ghost', cancel: true },
            { label: t('gta_leave_discard'), kind: 'ghost', onClick: () => { S.gpend = {}; renderRows(); leave(); } },
            { label: t('gta_leave_apply'), onClick: applyGta },
        ],
    });
};

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

const activateRow = (e) => {
    const r = e.row;
    if (r.type === 'toggle') setValue(r, !S.values[r.id]);
    else if (r.type === 'select') stepSelect(r, 1);
    else if (r.type === 'action') runAction(r);
    else if (r.type === 'gta') openNative(r.target || 'settings');
    else if (r.type === 'glist') { stepG(r, 1); renderRows(); }
};

const adjustRow = (e, dir, shift) => {
    const r = e.row;
    if (r.type === 'toggle') { const want = dir > 0; if (!!S.values[r.id] !== want) setValue(r, want); }
    else if (r.type === 'select') stepSelect(r, dir);
    else if (r.type === 'slider') stepSlider(r, dir, shift ? 5 : 1);
    else if (r.type === 'gtaslider' || r.type === 'glist') { stepG(r, dir, shift); renderRows(); }
    else if (dir < 0) goBack();
};

/* ============================================================ AYARLAR: çizim (PSettings.mp4 tasarımı) */
const splitTwo = (text) => { const s = String(text || ''); const i = s.indexOf(' '); return i < 0 ? [s, ''] : [s.slice(0, i), s.slice(i)]; };
const twoTone = (text) => { const [a, b] = splitTwo(text); return [h('b', {}, a), b ? h('i', {}, b) : null]; };

// Seçili satırın açıklaması panelin altındaki not satırında görünür (videodaki "After changing graphics settings…" satırı gibi)
const setNote = (r) => {
    let txt = '';
    if (r) {
        txt = L(r.desc);
        if (!txt && r.type === 'gta') txt = t('gta_text');
        if (!txt && r.type === 'key') txt = t('readonly');
    }
    $('#gsNote').textContent = txt;
};
const paintNote = () => {
    const e = S.entries[S.row];
    setNote(S.zone === 'rows' && e ? e.row : null);
};

const buildRow = (e, i) => {
    const r = e.row;
    if (r.type === 'head') return h('div', { class: 'gs-subhead' }, e.head);
    if (r.type === 'info') return h('div', { class: 'gs-info' }, L(r.text));

    const sel = S.zone === 'rows' && i === S.row;
    const base = `gs-row t-${r.type}` + (sel ? ' sel' : '');
    const mark = () => { S.zone = 'rows'; S.row = i; };
    const hover = () => setNote(r);
    const label = h('div', { class: 'gl' }, e.crumb ? h('span', { class: 'gs-crumb' }, e.crumb) : null, ...twoTone(L(r.label)));
    const arrow = (txt, fn) => h('button', { class: 'ar', type: 'button', onclick: (ev) => { ev.stopPropagation(); mark(); fn(); } }, txt);

    if (r.type === 'toggle') {
        const on = !!S.values[r.id];
        const seg = (val, text) => h('button', { class: val === on ? 'on' : '', type: 'button', onclick: (ev) => { ev.stopPropagation(); mark(); setValue(r, val); } }, text);
        return h('div', { class: base, onmouseenter: hover, onclick: () => { mark(); setValue(r, !on); } }, label,
            h('div', { class: 'gc seg' }, seg(false, t('off')), seg(true, t('on'))));
    }

    if (r.type === 'select') {
        const cur = r.options.find(o => o.value === S.values[r.id]) || r.options[0];
        const [va, vb] = splitTwo(L(cur.label));
        return h('div', { class: base, onmouseenter: hover, onclick: () => { mark(); stepSelect(r, 1); } }, label,
            h('div', { class: 'gc pick' }, arrow('‹', () => stepSelect(r, -1)),
                h('span', { class: 'val' }, cur.color ? h('span', { class: 'dot', style: `background:${cur.color}` }) : null, h('b', {}, va), vb ? h('i', {}, vb) : null),
                arrow('›', () => stepSelect(r, 1))));
    }

    if (r.type === 'slider') return buildSlider(e, base, label, mark, hover, arrow);
    if (r.type === 'gtaslider') return buildGSlider(r, base + (S.gpend[r.pid] !== undefined ? ' chg' : ''), label, mark, hover, arrow);

    if (r.type === 'glist') {
        const n = (r.labels || []).length, v = gVal(r), cls = base + (S.gpend[r.pid] !== undefined ? ' chg' : '');
        if (n === 2) {
            const seg = (i) => h('button', { class: i === v ? 'on' : '', type: 'button', onclick: (ev) => { ev.stopPropagation(); mark(); setG(r, i); renderRows(); } }, gText(r.labels[i]));
            return h('div', { class: cls, onmouseenter: hover, onclick: () => { mark(); stepG(r, 1); renderRows(); } }, label, h('div', { class: 'gc seg' }, seg(0), seg(1)));
        }
        const [va, vb] = splitTwo(gText(r.labels[Math.min(v, n - 1)] || ''));
        return h('div', { class: cls, onmouseenter: hover, onclick: () => { mark(); stepG(r, 1); renderRows(); } }, label,
            h('div', { class: 'gc pick' }, arrow('‹', () => { stepG(r, -1); renderRows(); }),
                h('span', { class: 'val' }, h('b', {}, va), vb ? h('i', {}, vb) : null),
                arrow('›', () => { stepG(r, 1); renderRows(); })));
    }

    if (r.type === 'key') {
        const token = r.control != null ? S.keys['c:' + r.control] : S.keys['m:' + r.command];
        const pretty = prettyKey(token);
        return h('div', { class: base, onmouseenter: hover, onclick: () => { mark(); renderRows(); } }, label,
            h('div', { class: 'gc end' }, pretty ? h('span', { class: 'keycap' }, pretty) : h('span', { class: 'keycap none' }, t('unbound'))));
    }

    if (r.type === 'action') {
        // Kısayol eylemi (r.command): atanmış tuşu da göster
        const pretty = r.command ? prettyKey(S.keys['m:' + r.command]) : null;
        return h('div', { class: base, onmouseenter: hover, onclick: () => { mark(); runAction(r); } }, label,
            h('div', { class: 'gc end' },
                r.command ? (pretty ? h('span', { class: 'keycap' }, pretty) : h('span', { class: 'keycap none' }, t('unbound'))) : null,
                h('button', { class: 'gs-btn sm', type: 'button' }, L(r.button))));
    }

    if (r.type === 'gta') {
        return h('div', { class: base, onmouseenter: hover, onclick: () => { mark(); openNative(r.target || 'settings'); } }, label,
            h('div', { class: 'gc end' }, h('button', { class: 'gs-btn sm', type: 'button' }, t('gta_btn')), ico('chevronR')));
    }
    return h('div', { class: base }, label);
};

const buildSlider = (e, base, label, mark, hover, arrow) => {
    const r = e.row;
    let v = S.values[r.id] ?? r.default;
    const pct = (x) => ((x - r.min) / (r.max - r.min)) * 100;
    const fill = h('div', { class: 'sl-fill', style: `width:${pct(v)}%` });
    const out = h('span', { class: 'sl-val' }, fmtSlider(r, v));
    const track = h('div', { class: 'sl-track' }, fill);

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
        fill.style.width = pct(v) + '%'; out.textContent = fmtSlider(r, v);
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
    return h('div', { class: base, onmouseenter: hover }, label,
        h('div', { class: 'gc sl' }, arrow('‹', () => stepSlider(r, -1)), track, out, arrow('›', () => stepSlider(r, 1))));
};

// GTA kaydırıcısı: 0..max tam sayı adımları; sürükleme yalnızca bekleyen değeri değiştirir ("Uygula"ya kadar GTA'ya yazılmaz)
const buildGSlider = (r, base, label, mark, hover, arrow) => {
    const max = Math.max(1, r.max || 1);
    const pos = () => gDisplay(r, gVal(r));
    const fill = h('div', { class: 'sl-fill', style: `width:${(pos() / max) * 100}%` });
    const out = h('span', { class: 'sl-val' }, gShow(r, gVal(r)));
    const track = h('div', { class: 'sl-track' }, fill);
    const fromEvent = (ev) => {
        if (S.gbusy) return;
        const rect = track.getBoundingClientRect();
        const f = clamp((ev.clientX - rect.left) / rect.width, 0, 1);
        const p = Math.round(f * max);
        setG(r, r.inv ? max - p : p);
        fill.style.width = `${(pos() / max) * 100}%`; out.textContent = gShow(r, gVal(r));
        const row = track.closest('.gs-row');
        if (row) row.classList.toggle('chg', S.gpend[r.pid] !== undefined);
        renderApply();
    };
    track.addEventListener('pointerdown', (ev) => {
        ev.stopPropagation();
        mark();
        track.setPointerCapture(ev.pointerId);
        fromEvent(ev);
        const move = (m) => fromEvent(m);
        const up = () => { track.removeEventListener('pointermove', move); track.removeEventListener('pointerup', up); };
        track.addEventListener('pointermove', move);
        track.addEventListener('pointerup', up);
    });
    return h('div', { class: base, onmouseenter: hover }, label,
        h('div', { class: 'gc sl' }, arrow('‹', () => { stepG(r, -1); renderRows(); }), track, out, arrow('›', () => { stepG(r, 1); renderRows(); })));
};

// OPTIONS sütunu: kategoriler (Game Settings) ya da arayüz ayar sayfaları (UI Settings); Game Settings'te en sonda "GTA Settings"
const renderOpts = () => {
    $('#optTitle').textContent = t('opts_title');
    const pick = (i) => () => { S.cat = i; S.zone = 'cats'; S.query = ''; q.value = ''; refreshSettings(true); };
    const items = S.schema.map((c, i) => h('button', {
        class: 'gs-opt' + (!S.query && i === S.cat ? ' cur' : ''), type: 'button', onclick: pick(i),
    }, h('i', { class: 'd' }), h('span', {}, L(c.label))));
    if (hasGtaOpt()) {
        items.push(h('button', { class: 'gs-opt ext' + (!S.query && gtaSelected() ? ' cur' : ''), type: 'button', onclick: pick(S.schema.length) },
            h('i', { class: 'd' }), h('span', {}, t('gta_settings')), ico('chevronR')));
    }
    $('#optList').replaceChildren(...items);
};

// Başlık: GAMESETTINGS // GRAPHICS (ilk sözcük kalın, kalanı ince)
const renderTitle = () => {
    const [a, b] = pair(S.scope === 'ui' ? 'ui' : 'game');
    const page = S.query ? t('search_title') : (gtaSelected() ? t('gta_settings') : (curCat() ? L(curCat().label) : ''));
    const [p1, p2] = splitTwo(page);
    setKids($('#sTitle'), h('b', {}, a), b ? h('i', {}, b) : null, h('span', { class: 'sl' }, '//'), h('b', {}, p1), p2 ? h('i', {}, p2) : null);
};

const pageIds = () => {
    const ids = [];
    if (S.query || !curCat()) return ids;
    for (const g of curCat().groups) for (const r of g.rows) {
        if (r.id && (r.type === 'toggle' || r.type === 'select' || r.type === 'slider') && entryVisible(r)) ids.push(r.id);
    }
    return ids;
};

const renderRows = (resetScroll) => {
    const list = $('#rowsList');
    const prev = list.scrollTop;
    S.entries = buildEntries();
    if (S.row >= S.entries.length) S.row = Math.max(0, S.entries.length - 1);
    renderTitle();
    list.replaceChildren(...(S.entries.length ? S.entries.map((e, i) => buildRow(e, i)) : [h('div', { class: 'gs-empty' }, t('no_results'))]));
    list.scrollTop = resetScroll ? 0 : prev;
    $('#gsRestore').classList.toggle('hidden', pageIds().length === 0);
    renderApply();
    paintNote();
};

const paintZones = () => {
    $('#colCats').classList.toggle('active', S.zone === 'cats');
    paintNote();
};

const refreshSettings = (resetScroll) => {
    if (resetScroll) { S.entries = buildEntries(); S.row = firstSelectable(); }
    renderOpts(); renderRows(resetScroll); paintZones();
};

const scrollSelected = () => {
    const el = $('#rowsList .gs-row.sel');
    if (el) el.scrollIntoView({ block: 'nearest' });
};

// scope: 'game' → tüm ayar kategorileri (Tercihler hariç), 'ui' → Tercihler'in grupları ayrı sayfalar olarak
const scopeSchema = (scope) => {
    if (scope === 'ui') {
        const prefs = S.allSchema.find(c => c.id === 'prefs');
        return prefs ? prefs.groups.map(g => ({ id: 'prefs.' + g.id, label: g.label, groups: [g] })) : [];
    }
    return S.allSchema.filter(c => c.id !== 'prefs');
};

// Seçili ana menü maddesinden OPTIONS sütununa uzanan ince çizgi (videodaki gibi)
const placeLine = () => {
    const line = $('#gsLine');
    const lbl = document.querySelector('.pm-item.sel .lbl');
    if (!lbl || S.screen !== 'settings') { line.classList.add('hidden'); return; }
    const r = lbl.getBoundingClientRect();
    const rem = parseFloat(getComputedStyle(document.documentElement).fontSize) || 16;
    const left = r.right + 0.7 * rem;
    const right = $('#colCats').getBoundingClientRect().left - 1.4 * rem;
    line.classList.toggle('hidden', right - left < 8);
    line.style.left = `${left}px`; line.style.width = `${Math.max(0, right - left)}px`; line.style.top = `${r.top + r.height / 2}px`;
};
window.addEventListener('resize', () => { if (S.screen === 'settings') placeLine(); });

const openSettings = (scope = 'game') => {
    S.scope = scope; S.schema = scopeSchema(scope);
    S.cat = 0; S.row = 0; S.query = ''; q.value = '';
    S.zone = 'cats';
    const idx = S.menu.findIndex(m => m.id === scope);
    if (idx >= 0) setMainIdx(idx);
    showScreen('settings');
    refreshSettings(true);
    placeLine();
};

// Bu sayfadaki ayarları varsayılana döndürür (yalnızca şemadaki id'ler; Lua yeniden doğrular)
const restoreDefaults = () => openModal({
    title: t('restore_title'), text: t('restore_text'),
    buttons: [
        { label: t('cancel'), kind: 'ghost', cancel: true },
        { label: t('restore_yes'), onClick: async () => {
            const res = await post('restore', { ids: pageIds() });
            if (res && res.values) { Object.assign(S.values, res.values); applyPrefs(); renderAll(); toast(t('msg_restored')); }
        } },
    ],
});

/* ============================================================ GERİ / NAVİGASYON */
const goBack = () => {
    if (S.modal) { closeModal(); return; }
    if (S.screen === 'page') { showScreen('main'); return; }
    if (S.screen !== 'settings') return;
    q.blur();
    if (S.query) { S.query = ''; q.value = ''; S.zone = 'rows'; refreshSettings(true); return; }
    if (S.zone === 'rows' || S.zone === 'search') { S.zone = 'cats'; renderRows(); paintZones(); return; }
    guardPending(() => showScreen('main'));
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
    syncSub();
};
const closeModal = () => { S.modal = null; modalEl.classList.add('hidden'); syncSub(); };
const runModalButton = (b) => { closeModal(); if (b.onClick) b.onClick(); };

let toastTimer = null;
const toast = (msg) => {
    const el = $('#toast');
    el.textContent = msg;
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => el.classList.remove('show'), 2200);
};

/* ============================================================ KLAVYE */
const onKey = (ev) => {
    if (!S.open) return;
    const k = ev.key;

    if (S.gbusy) { ev.preventDefault(); return; }        // GTA ayarları uygulanırken menü girdi almaz

    if (k === 'Escape') {
        ev.preventDefault();
        if (S.modal) closeModal(); else if (S.screen !== 'main') goBack(); else post('close');   // ESC = bir adım geri; ana listede menüyü kapatır
        return;
    }

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
    if ((k === 'a' || k === 'A') && gPendingCount()) { ev.preventDefault(); applyGta(); return; }

    if (S.zone === 'cats') {
        if (k === 'ArrowUp' || k === 'ArrowDown') {
            const n = optCount();
            S.cat = (S.cat + (k === 'ArrowDown' ? 1 : -1) + n) % n;
            refreshSettings(true);
        } else if (k === 'Enter' && gtaSelected()) openNative('settings');
        else if (k === 'ArrowRight' || k === 'Enter') enterRows();
        else if (k === 'ArrowLeft') goBack();
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

$('#gsRestore').addEventListener('click', restoreDefaults);
$('#gsApply').addEventListener('click', applyGta);
$('#pBack').addEventListener('click', goBack);
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
    S.caps = d.caps || {};
    S.menu = (Array.isArray(d.menu) && d.menu.length) ? d.menu : DEFAULT_MENU;
    S.stats = d.stats || null;
    S.health = d.health || { known: false, conditions: [] };
    S.gset = d.gta || {}; S.glabels = d.gtaLabels || {}; S.gpend = {}; S.gbusy = false;
    applyGtaLabels();
    S.mainIdx = 0; S.cat = 0; S.grp = 0; S.row = 0; S.zone = 'cats'; S.query = ''; q.value = '';
    S.scope = 'game'; S.schema = scopeSchema('game');
    S.subSent = false;
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
    else if (d.action === 'caps') {
        S.caps = d.caps || {};
        if (S.screen === 'settings') refreshSettings(false);
    }
    else if (d.action === 'gtaDone') onGtaDone(d);
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
