"""
Yalnızca geliştirme: oyuna girmeden resource'u doğrular (dağıtıma girmez, fxmanifest'e dahil değildir).

  python _dev/check.py

1) Tüm Lua dosyalarının sözdizimini denetler (Lua 5.4, FiveM ile aynı).
2) config.lua + shared/schema.lua'yı yükler, şemayı denetler ve _dev/schema.json'a yazar (mock.html bunu kullanır).
3) client/prefs.lua'nın doğrulama / kalıcılık mantığını sahte KVP ile test eder.
Gereksinim: pip install lupa
"""
import json
import pathlib
import sys

from lupa.lua54 import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parent.parent
failures = []


def check(cond, msg):
    if not cond:
        failures.append(msg)
        print('  FAIL', msg)


def lua_to_py(o):
    if isinstance(o, (str, int, float, bool)) or o is None:
        return o
    keys = list(o.keys())
    if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        return [lua_to_py(o[i]) for i in range(1, len(keys) + 1)]
    return {str(k): lua_to_py(o[k]) for k in keys}


def py_to_lua(lua, o):
    if isinstance(o, dict):
        return lua.table_from({k: py_to_lua(lua, v) for k, v in o.items()})
    if isinstance(o, list):
        return lua.table_from([py_to_lua(lua, v) for v in o])
    return o


# ------------------------------------------------------------------ 1) sözdizimi
print('[1] Lua sözdizimi')
lua_files = [p for p in ROOT.rglob('*.lua') if '_dev' not in p.parts]
syntax = LuaRuntime(unpack_returned_tuples=True)
for p in sorted(lua_files):
    ok, err = syntax.eval('function(src, name) local f, e = load(src, name) return f ~= nil, e end')(p.read_text(encoding='utf-8'), p.name)
    check(ok, f'{p.relative_to(ROOT)}: {err}')
    print('  OK  ' if ok else '  FAIL', p.relative_to(ROOT))

# ------------------------------------------------------------------ 2) şema
print('[2] Şema')
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute((ROOT / 'config.lua').read_text(encoding='utf-8'))
lua.execute((ROOT / 'shared/schema.lua').read_text(encoding='utf-8'))
cats = lua_to_py(lua.eval('Schema.categories'))

expected = ['controller', 'mouse', 'keys', 'audio', 'camera', 'display', 'graphics', 'advgfx', 'voice', 'editor', 'startup', 'prefs', 'menu']
check([c['id'] for c in cats] == expected, f'kategori sırası beklenenden farklı: {[c["id"] for c in cats]}')

tr_names = ['Oyun Kolu', 'Klavye / Fare', 'Tuş Atamaları', 'Ses', 'Kamera', 'Görüntü', 'Grafikler', 'Gelişmiş Grafikler',
            'Sesli Sohbet', 'Rockstar Editor', 'Kayıt ve Başlangıç', 'Tercihler', 'Normal Menü']
check([c['label']['tr'] for c in cats] == tr_names, 'Türkçe kategori adları/sırası beklenenle uyuşmuyor')
check([c['id'] for c in cats if c.get('hidden')] == ['menu'], 'Normal Menü yalnızca allowNativeMenu=false iken gizli olmalı (başka gizli kategori olmamalı)')

seen = {}
for c in cats:
    check(len(c['groups']) > 0, f'{c["id"]}: grup yok')
    for g in c['groups']:
        check(len(g['rows']) > 0, f'{c["id"]}.{g["id"]}: boş grup')
        for r in g['rows']:
            t = r['type']
            check(t in ('toggle', 'select', 'slider', 'key', 'action', 'native', 'info'), f'bilinmeyen tür {t}')
            if t in ('toggle', 'select', 'slider', 'action'):
                check('id' in r, f'{c["id"]}.{g["id"]}: id yok ({t})')
            if 'id' in r and t != 'action':
                if r['id'] in seen:
                    check(seen[r['id']] == r, f'{r["id"]}: iki yerde farklı tanım')
                seen[r['id']] = r
            if t == 'select':
                vals = [o['value'] for o in r['options']]
                check(r['default'] in vals, f'{r["id"]}: varsayılan seçenekte yok')
                check(len(vals) == len(set(vals)), f'{r["id"]}: yinelenen seçenek')
            if t == 'slider':
                check(r['min'] <= r['default'] <= r['max'], f'{r["id"]}: varsayılan aralık dışı')
            if t == 'native':
                check(r['target'] in ('settings', 'keybinds', 'game', 'map'), f'native hedefi geçersiz: {r["target"]}')
                if r.get('read'):
                    check(r['read'] in ('subtitles', 'metric', 'safezone', 'resolution', 'language'), f'{r["label"]["tr"]}: bilinmeyen read anahtarı {r["read"]}')
                    check(f"read('{r['read']}'" in (ROOT / 'client/main.lua').read_text(encoding='utf-8'), f'{r["read"]}: main.lua okuyucusu yok')
            if t in ('toggle', 'select', 'slider', 'key', 'native', 'action'):
                check(bool(r['label'].get('tr')) and bool(r['label'].get('en')), f'{r.get("id") or r["label"]}: etiket eksik')
            if t == 'key':
                check(('control' in r) != ('command' in r), f'key satırı control XOR command olmalı: {r["label"]}')

native_targets = set(lua_to_py(lua.eval('(function() local t = {} for k in pairs(Config.Native) do t[k] = true end return t end)()')).keys())
for c in cats:
    for g in c['groups']:
        for r in g['rows']:
            if r['type'] == 'native':
                check(r['target'] in native_targets, f'{r["target"]} Config.Native içinde yok')

# Her ayarlanabilir id'nin client/apply.lua'da karşılığı olmalı (yalnızca pref.*/menu.* UI tarafında olabilir)
apply_src = (ROOT / 'client/apply.lua').read_text(encoding='utf-8')
main_src = (ROOT / 'client/main.lua').read_text(encoding='utf-8')
ui_only = ('pref.', 'menu.native')
for rid, r in seen.items():
    if r['type'] in ('toggle', 'select', 'slider') and not rid.startswith(ui_only):
        check(f"Apply.fn['{rid}']" in apply_src or f"Prefs.get('{rid}')" in apply_src, f'{rid}: uygulama kodu yok (sahte ayar!)')
for c in cats:
    for g in c['groups']:
        for r in g['rows']:
            if r['type'] == 'action':
                dynamic = r['id'].startswith('cmd.') and 'Apply.actions[actionId]' in main_src       # Config.Shortcuts döngüsü
                check(dynamic or f"Apply.actions['{r['id']}']" in apply_src + main_src, f"{r['id']}: eylem işleyicisi yok")

# Hızlı Eylemler: yapılandırma tutarlılığı
shortcuts = lua_to_py(lua.eval('(function() local t = {} for i, s in ipairs(Config.Shortcuts) do t[i] = s end return t end)()'))
sc_ids = [s['id'] for s in shortcuts.values()] if isinstance(shortcuts, dict) else [s['id'] for s in shortcuts]
check(len(sc_ids) == len(set(sc_ids)), 'Config.Shortcuts: yinelenen id')
for s in (shortcuts.values() if isinstance(shortcuts, dict) else shortcuts):
    check(not s['command'].startswith('+'), f"Config.Shortcuts: '+' ile başlayan (bas-bırak) komut eklenemez: {s['command']}")
    check(f"cmd.{s['id']}" in {r['id'] for c in cats for g in c['groups'] for r in g['rows'] if r['type'] == 'action'}, f"Config.Shortcuts: {s['id']} şemada eylem satırı olmamış")
    if s.get('aces'):
        check(any(r.get('cap') == s['id'] for c in cats for g in c['groups'] for r in g['rows']), f"{s['id']}: aces var ama satırda cap yok (herkese görünür!)")

(ROOT / '_dev' / 'schema.json').write_text(json.dumps(cats, ensure_ascii=False, indent=1), encoding='utf-8')
rows = sum(len(g['rows']) for c in cats for g in c['groups'])
print(f'  {len(cats)} kategori, {rows} satır, {len(seen)} kimlikli ayar → _dev/schema.json')

# NUI: hover/klavye ile seçim değişince onay penceresi düğmeleri YENİDEN OLUŞTURULMAMALI (mousedown ile mouseup arasında öğe
# değişirse "click" hiç oluşmaz → "Vazgeç / Sunucudan ayrıl" çalışmaz hatası). Yalnızca sınıf güncellenir (paintModal).
import re  # noqa: E402
app_js = (ROOT / 'html/js/app.js').read_text(encoding='utf-8')
check(not re.search(r'onmouseenter:[^\n]*renderModal\(', app_js), 'app.js: onmouseenter içinde renderModal() çağrılmamalı (düğmeler yeniden çizilir, click kaybolur)')
check(len(re.findall(r'renderModal\(\)', app_js)) == 1, 'app.js: renderModal() yalnızca openModal içinde çağrılmalı')

# Ana menü: Config.Menu'deki her madde için arayüzde TR + EN etiket çifti olmalı ('menu_<id>: [kalın, ince]')
menu_ids = lua_to_py(lua.eval('(function() local t = {} for i, m in ipairs(Config.Menu) do t[i] = m.id end return t end)()'))
menu_ids = list(menu_ids.values()) if isinstance(menu_ids, dict) else list(menu_ids)
for mid in menu_ids:
    check(len(re.findall(rf"menu_{mid}: \[", app_js)) == 2, f"app.js: menu_{mid} için TR ve EN etiket çifti olmalı")
check(menu_ids[0] == 'resume' and menu_ids[-1] == 'quit', 'Config.Menu: RESUME ilk, DISCONNECT (quit) son olmalı')
check(all(x in menu_ids for x in ('resume', 'game', 'ui', 'position', 'quit')), 'Config.Menu: ana maddeler eksik')
check(lua.eval("(function() for _, m in ipairs(Config.Menu) do if m.id == 'map' then return m.enabled end end end)()") is False, 'Config.Menu: MAP varsayılan kapalı olmalı (harita yalnızca M)')
# İngilizce varsayılan: arayüz metinlerinde TR/EN anahtar seti aynı olmalı, İngilizce metinlerde Türkçe harf olmamalı
def str_keys(block):
    body = re.search(rf"\n    {block}: \{{(.*?)\n    \}},", app_js, re.S).group(1)
    return set(re.findall(r"\b([a-z_0-9]+): ", body))
tr_keys, en_keys = str_keys('tr'), str_keys('en')
check(tr_keys == en_keys, f"app.js STR: TR/EN anahtarları farklı: yalnızca TR={sorted(tr_keys - en_keys)} yalnızca EN={sorted(en_keys - tr_keys)}")
TR_CHARS = set('çğıöşüÇĞİÖŞÜ')
def walk_en(o, path=''):
    if isinstance(o, dict):
        if 'tr' in o and 'en' in o and isinstance(o['en'], str):
            if (TR_CHARS & set(o['en'])) and o['en'] != 'Türkçe':
                check(False, f"İngilizce metinde Türkçe harf: {path} → {o['en'][:60]}")
        for k, v in o.items(): walk_en(v, f'{path}.{k}')
    elif isinstance(o, list):
        for i, v in enumerate(o): walk_en(v, f'{path}[{i}]')
walk_en(cats, 'schema')
for name in ('Shortcuts', 'KeyMappings'):
    items = lua_to_py(lua.eval(f'(function() local t = {{}} for i, s in ipairs(Config.{name}) do t[i] = s end return t end)()'))
    for it in (items.values() if isinstance(items, dict) else items):
        check(not (TR_CHARS & set(it.get('en', ''))), f"Config.{name}: İngilizce metinde Türkçe harf: {it.get('en')}")
        if it.get('desc'): check(not (TR_CHARS & set(it['desc'].get('en', ''))), f"Config.{name}: desc.en Türkçe harf içeriyor")
check(lua.eval("Config.Defaults['pref.lang']") == 'en', "Config.Defaults['pref.lang'] 'en' olmalı (menü İngilizce varsayılan)")
check('lang="en"' in (ROOT / 'html/index.html').read_text(encoding='utf-8'), 'index.html lang="en" olmalı')
check('invokeNative' in app_js and 'SAFE_URL' in app_js, 'app.js: bağlantılar yalnızca SAFE_URL ile invokeNative(openUrl) üzerinden açılmalı')
check('onmouseenter' in app_js and "setSuffix" in app_js, 'app.js: başlık karıştırma efekti bağlı olmalı')

# ------------------------------------------------------------------ 3) Prefs mantığı
print('[3] Prefs doğrulama / kalıcılık')
pl = LuaRuntime(unpack_returned_tuples=True)
kvp = {}


def set_kvp(k, v): kvp[k] = v
def get_kvp(k): return kvp.get(k)
def enc(t): return json.dumps(lua_to_py(t))
def dec(s):
    return py_to_lua(pl, json.loads(s))


g = pl.globals()
g.SetResourceKvp = set_kvp
g.GetResourceKvpString = get_kvp
g.CreateThread = lambda fn: None          # kaydetmeyi elle çağıracağız
g.Wait = lambda ms: None
g.json = pl.table_from({'encode': enc, 'decode': dec})
pl.execute((ROOT / 'config.lua').read_text(encoding='utf-8'))
pl.execute((ROOT / 'shared/schema.lua').read_text(encoding='utf-8'))
pl.execute((ROOT / 'client/prefs.lua').read_text(encoding='utf-8'))
T = pl.eval('function(id, v) local ok, val = Prefs.set(id, v) return ok, val end')


def t(id_, v):
    r = T(id_, v)
    return tuple(r) if isinstance(r, tuple) else (r,)


check(t('disp.radar', True) == (True, True), 'toggle true kabul edilmeli')
check(t('disp.radar', 'yes')[0] is False, 'toggle string reddedilmeli')
check(t('disp.radar', 1)[0] is False, 'toggle sayı reddedilmeli')
check(t('aim.mode', 'free') == (True, 'free'), 'geçerli seçenek kabul edilmeli')
check(t('aim.mode', 'hack')[0] is False, 'geçersiz seçenek reddedilmeli')
check(t('aim.mode', 3)[0] is False, 'select sayı reddedilmeli')
check(t('nope.id', True)[0] is False, 'şemada olmayan id reddedilmeli')
check(t(None, True)[0] is False, 'id nil reddedilmeli')
check(t('voice.radio', 250) == (True, 100), 'slider üst sınıra kırpılmalı')
check(t('voice.radio', -5) == (True, 0), 'slider alt sınıra kırpılmalı')
check(t('voice.radio', 47) == (True, 45), 'slider adıma yuvarlanmalı (47 → 45)')
check(t('voice.radio', '50')[0] is False, 'slider string reddedilmeli')
check(t('voice.radio', float('nan'))[0] is False, 'slider NaN reddedilmeli')
check(t('voice.radio', float('inf'))[0] is False, 'slider Inf reddedilmeli')
check(t('gfx.lod', 1.34) == (True, 1.3), 'ondalık adım doğru yuvarlanmalı')
check(t('pref.accent', 'purple') == (True, 'purple'), 'accent kabul edilmeli')

# kalıcılık: flush → yeni runtime → yükle
pl.execute('Prefs.flush()')
saved = json.loads(kvp['loe_pause:prefs:v1'])
check(saved.get('pref.accent') == 'purple' and saved.get('aim.mode') == 'free', f'KVP içeriği beklenenden farklı: {saved}')

kvp['loe_pause:prefs:v1'] = json.dumps({'pref.accent': 'hack', 'aim.mode': 'free', 'zzz': 1, 'voice.radio': 9999, 'disp.radar': 'x'})
pl.execute('Prefs.values = {}; Prefs.load()')
vals = lua_to_py(pl.eval('Prefs.values'))
check(vals == {'aim.mode': 'free', 'voice.radio': 100}, f'bozuk KVP süzülmeli: {vals}')

kvp['loe_pause:prefs:v1'] = 'not json {{'
pl.execute('Prefs.values = {}; Prefs.load()')
check(lua_to_py(pl.eval('Prefs.values')) == {}, 'çözülemeyen KVP boş sonuç vermeli')

# tek seferlik arayüz sıfırlaması: kayıtlı pref.* silinir (varsayılanlar gelir), oyun ayarları korunur; sonraki seçimler kalıcıdır
kvp['loe_pause:prefs:v1'] = json.dumps({'pref.lang': 'tr', 'pref.accent': 'blue', 'pref.dark': False, 'pref.mapReturn': True, 'aim.mode': 'free'})
kvp.pop('loe_pause:migrated:ui-reset-v1', None)
pl.execute('Prefs.values = {}; Prefs.load()')
check(pl.eval("Prefs.get('pref.lang')") == 'en' and pl.eval("Prefs.get('pref.accent')") == 'crimson'
      and pl.eval("Prefs.get('pref.dark')") is True and pl.eval("Prefs.get('pref.mapReturn')") is False, 'sıfırlama: arayüz tercihleri varsayılana dönmeli')
check(pl.eval("Prefs.get('aim.mode')") == 'free', 'sıfırlama: oyun ayarları (aim.mode) korunmalı')
check(kvp.get('loe_pause:migrated:ui-reset-v1') == '1', 'sıfırlama: işaret yazılmalı')
check(not any(k.startswith('pref.') for k in json.loads(kvp['loe_pause:prefs:v1'])), 'sıfırlama: kayıttan pref.* silinmeli')
pl.execute("Prefs.set('pref.lang', 'tr'); Prefs.flush(); Prefs.values = {}; Prefs.load()")
check(pl.eval("Prefs.get('pref.lang')") == 'tr', 'sıfırlama: sonradan seçilen tercih kalıcı olmalı (sıfırlama yeniden çalışmamalı)')
pl.execute("Prefs.values = {}; Prefs.flush()")

pl.execute("Prefs.values = {}; Prefs.set('pref.accent', 'red'); Prefs.set('pref.dark', false)")
pl.execute("Prefs.reset({'pref.accent', 'pref.dark'})")
check(pl.eval("Prefs.get('pref.accent')") == 'crimson' and pl.eval("Prefs.get('pref.dark')") is True, 'reset varsayılana dönmeli')
check(pl.eval("Prefs.get('pref.lang')") == 'en', "varsayılan dil 'en' olmalı")
check(pl.eval("Prefs.get('pref.dark')") is True, 'varsayılan koyu tema açık olmalı')

# sunucu varsayılan geçersiz kılma
pl.execute("Config.Defaults['pref.accent'] = 'blue'")
check(pl.eval("Prefs.default('pref.accent')") == 'blue', 'Config.Defaults uygulanmalı')
pl.execute("Config.Defaults['pref.accent'] = 'invalid'")
check(pl.eval("Prefs.default('pref.accent')") == 'crimson', 'geçersiz Config.Defaults yok sayılmalı')

# ------------------------------------------------------------------ 4) ana döngü simülasyonu
print('[4] ESC / harita / sızan ESC akışı (simülasyon)')

SIM_PRELUDE = r'''
sim = { now = 5000, pause = false, nuiFocus = false, msgs = {}, calls = {}, handlers = {}, exported = {}, threads = {}, events = {}, escFrame = false,
        netHandlers = {}, started = {}, serverEvents = {}, commands = {}, profile = {}, delFrame = false }
local S = sim
setmetatable(_G, { __index = function(_, k) return function() end end })   -- bilinmeyen native → no-op
Citizen = { InvokeNative = function() end, ResultAsInteger = function() end, PointerValueInt = function() end }
function SetTimeout(ms, fn) sim.at(ms, fn) end
function GetProfileSetting(id) return S.profile[id] or 0 end
function TriggerLatentServerEvent(name, bps, data) S.latent = { name = name, data = data } end

LocalPlayer = { state = { isLoggedIn = true } }
json = { encode = function() return '{}' end, decode = function() return {} end }
function GetResourceKvpString() return nil end
function SetResourceKvp() end
function GetCurrentResourceName() return 'loe_pause' end
function GetResourceState(r) return S.started[r] and 'started' or 'missing' end
function GetHashKey(s) return 1 end
function GetControlInstructionalButton() return 't_E' end
function GetVehiclePedIsIn() return 0 end
function GetPlayerServerId() return 7 end
function PlayerId() return 1 end
function IsRadarHidden() return false end
function GetGameTimer() return S.now end
function CreateThread(fn) S.threads[#S.threads + 1] = { co = coroutine.create(fn), wake = 0 } end
function Wait(ms) coroutine.yield(ms or 0) end
function RegisterNUICallback(name, fn) S.handlers[name] = fn end
function SendNUIMessage(m) S.msgs[#S.msgs + 1] = m end
function SetNuiFocus(a) S.nuiFocus = a == true end
function IsNuiFocused() return S.nuiFocus end
function IsPauseMenuActive() return S.pause end
function SetFrontendActive(v) if not v then S.pause = false end end
function SetPauseMenuActive(v) if not v then S.pause = false end end
function IsDisabledControlJustPressed(_, c) return S.escFrame and (c == 200) end
function IsControlJustPressed(g, c) return (S.escFrame and g == 0 and c == 200) or (S.delFrame and c == 214) end
function ActivateFrontendMenu()
    S.calls.Activate = (S.calls.Activate or 0) + 1
    S.events[#S.events + 1] = { at = S.now + 120, fn = function() S.pause = true end }   -- oyun menüyü biraz sonra açar
end
function PauseMenuceptionGoDeeper(p) S.calls.GoDeeper = p end
local function addHandler(name, fn) S.netHandlers[name] = S.netHandlers[name] or {}; table.insert(S.netHandlers[name], fn) end
function AddEventHandler(name, fn) addHandler(name, fn) end
function RegisterNetEvent(name, fn) if fn then addHandler(name, fn) end end
function RegisterCommand(name, fn) S.commands[name] = fn end
function RegisterKeyMapping() end
function TriggerServerEvent(name) S.serverEvents[#S.serverEvents + 1] = name end
exports = setmetatable({}, {
    __call = function(_, name, fn) S.exported[name] = fn end,
    __index = function() return setmetatable({}, { __index = function() return function() return nil end end }) end,
})

function sim.at(ms, fn) S.events[#S.events + 1] = { at = S.now + ms, fn = fn } end
function sim.nui(name, data)
    local out
    S.handlers[name](data or {}, function(r) out = r end)
    return out
end
function sim.step(ms)
    S.now = S.now + ms
    for i = #S.events, 1, -1 do
        local e = S.events[i]
        if S.now >= e.at then table.remove(S.events, i); e.fn() end
    end
    local list = {}
    for i, t in ipairs(S.threads) do list[i] = t end
    for _, t in ipairs(list) do
        if coroutine.status(t.co) ~= 'dead' and S.now >= t.wake then
            local ok, w = coroutine.resume(t.co)
            if not ok then error(w) end
            t.wake = S.now + (w or 0)
        end
    end
    S.escFrame = false
    S.delFrame = false
end
function sim.frames(ms) for _ = 1, math.ceil(ms / 16) do sim.step(16) end end
function sim.lastOpen() local l; for _, m in ipairs(S.msgs) do if m.action == 'open' then l = m end end return l end
function sim.openCount() local n = 0; for _, m in ipairs(S.msgs) do if m.action == 'open' then n = n + 1 end end return n end
function sim.last() return S.msgs[#S.msgs] end
function sim.fire(name, ...) for _, fn in ipairs(S.netHandlers[name] or {}) do fn(...) end end
function sim.count(list, v) local n = 0; for _, x in ipairs(list) do if x == v then n = n + 1 end end return n end
'''

SIM_SCENARIO = r'''
local R = {}
local function check(c, msg) if not c then R[#R + 1] = msg end end
local isOpen = function() return sim.exported.IsOpen() end

sim.frames(100)
sim.nui('ready')
check(isOpen() == false, 'başlangıçta menü kapalı olmalı')
local function setMapItem(on) for _, it in ipairs(Config.Menu) do if it.id == 'map' then it.enabled = on end end end
setMapItem(true)   -- S1b..S3b: menüden harita akışı (varsayılan kapalı; açılırsa hâlâ çalışmalı)

-- S1: ESC → yerleşik menü söndürülür, LOE menüsü açılır
sim.pause = true; sim.frames(64)
check(isOpen() == true, 'S1: ESC LOE menüsünü açmalı')
check(sim.pause == false, 'S1: yerleşik pause menü kapatılmalı')

-- S1b: varsayılan tercih (haritadan dönüş KAPALI): ESC haritayı kapatır, oyuna dönülür, LOE menüsü tekrar AÇILMAZ
check(Prefs.get('pref.mapReturn') == false, 'S1b: haritadan dönüş varsayılanı kapalı olmalı')
sim.nui('menu', { id = 'map' })
sim.frames(1300)
check(sim.pause == true, 'S1b: harita açılmalı')
local before0 = sim.openCount()
sim.escFrame = true; sim.step(16)
sim.frames(2500)
check(sim.pause == false, 'S1b: ESC haritayı kapatmalı')
check(isOpen() == false and sim.openCount() == before0, 'S1b: menü tekrar açılmamalı')
sim.frames(700)
sim.pause = true; sim.frames(64)
check(isOpen() == true, 'S1b: sonraki ESC LOE menüsünü açmalı')
Prefs.set('pref.mapReturn', true)

-- S2: Harita → büyük harita açılır ve açık KALIR; ESC ile kapanınca sızan yeniden açılış söndürülür, LOE menüsü döner (tercih açık)
local act0 = sim.calls.Activate or 0
local r = sim.nui('menu', { id = 'map' })
check(r and r.ok, 'S2: menu callback ok dönmeli')
sim.frames(120)
check(isOpen() == false, 'S2: harita seçilince LOE menüsü kapanmalı')
sim.frames(700)
check(sim.calls.Activate == act0 + 1, 'S2: ActivateFrontendMenu bir kez çağrılmalı')
check(sim.calls.GoDeeper == 0, 'S2: büyük haritaya inmek için GoDeeper(0) çağrılmalı')
check(sim.pause == true, 'S2: yerleşik harita açık kalmalı (söndürülmemeli)')
sim.frames(600)                                              -- videodaki gibi: harita açıldıktan ~1 sn sonra ESC
check(sim.pause == true, 'S2: harita açık kalmalı')
local before = sim.openCount()
sim.pause = false                                            -- ESC: oyun haritayı kapatır
sim.at(250, function() sim.pause = true end)                 -- ...aynı basış yerleşik menüyü YENİDEN açar (videodaki hata)
sim.frames(1200)
check(sim.pause == false, 'S2: sızan yeniden açılış söndürülmeli, harita açık kalmamalı')
check(isOpen() == true and sim.openCount() == before + 1 and sim.lastOpen().anim == 'return', 'S2: LOE menüsü "return" animasyonuyla dönmeli')

-- S2b: harita uzun süre açık kaldıktan sonra ESC
sim.nui('menu', { id = 'map' })
sim.frames(900)
check(sim.pause == true, 'S2b: harita açılmalı')
sim.frames(3500)
check(sim.pause == true, 'S2b: harita uzun süre açık kalmalı')
before = sim.openCount()
sim.pause = false
sim.at(250, function() sim.pause = true end)
sim.frames(1200)
check(sim.pause == false, 'S2b: sızan yeniden açılış söndürülmeli')
check(isOpen() == true and sim.openCount() == before + 1 and sim.lastOpen().anim == 'return', 'S2b: LOE menüsü geri dönmeli')

-- S2c: script ile açılan harita ESC'de KAPANMAZ (yalnızca "sıçrama", açık kalır) → ESC'yi biz yakalayıp kapatmalıyız
sim.nui('menu', { id = 'map' })
sim.frames(900)
check(sim.pause == true, 'S2c: harita açılmalı')
sim.frames(800)
before = sim.openCount()
sim.escFrame = true; sim.step(16)                            -- ESC: oyun menüyü kapatmaz
sim.frames(1500)
check(sim.pause == false, 'S2c: ESC haritayı kapatmalı (açık kalmamalı)')
check(isOpen() == true and sim.openCount() == before + 1 and sim.lastOpen().anim == 'return', 'S2c: LOE menüsü geri dönmeli')

-- S3: dönüş tercihi kapalıyken oyuna dönülür
Prefs.set('pref.mapReturn', false)
sim.nui('menu', { id = 'map' })
sim.frames(900)
check(sim.pause == true, 'S3: harita açılmalı')
before = sim.openCount()
sim.pause = false
sim.at(250, function() sim.pause = true end)
sim.frames(1500)
check(sim.pause == false, 'S3: sızan yeniden açılış söndürülmeli')
check(isOpen() == false and sim.openCount() == before, 'S3: tercih kapalıyken menü geri gelmemeli')

-- S3b: aynı tercih, ESC haritayı kapatmıyor
sim.pause = false; sim.frames(700)
sim.exported.Close()
sim.pause = true; sim.frames(64)                             -- ESC → LOE menüsü
sim.nui('menu', { id = 'map' })
sim.frames(1300)
check(sim.pause == true, 'S3b: harita açılmalı')
before = sim.openCount()
sim.escFrame = true; sim.step(16)
sim.frames(1500)
check(sim.pause == false, 'S3b: ESC haritayı kapatmalı')
check(isOpen() == false and sim.openCount() == before, 'S3b: tercih kapalıyken menü geri gelmemeli')
Prefs.set('pref.mapReturn', true)

-- S4: başka bir NUI ESC ile kapanırken pause menü açılmamalı
sim.nuiFocus = true; sim.frames(48)
sim.nuiFocus = false; sim.pause = true; sim.frames(64)
check(isOpen() == false, 'S4: NUI kapanışındaki ESC LOE menüsünü açmamalı')
check(sim.pause == false, 'S4: o ESC yerleşik menüyü de açık bırakmamalı')

-- S5: giriş yapılmamışken yerleşik menüye dokunulmaz
sim.frames(700)
LocalPlayer.state.isLoggedIn = false
sim.pause = true; sim.frames(160)
check(isOpen() == false and sim.pause == true, 'S5: giriş yapılmamışken yerleşik menü serbest kalmalı')
sim.pause = false; LocalPlayer.state.isLoggedIn = true; sim.frames(700)

-- S6: menü açıkken ESC ile kapanır
sim.pause = true; sim.frames(64)
check(isOpen() == true, 'S6: menü yeniden açılmalı')
sim.frames(500)
sim.escFrame = true; sim.step(16); sim.frames(64)
check(isOpen() == false, 'S6: açıkken ESC menüyü kapatmalı')

-- S7: sağlık kartı — sunucunun healthState olayı önbelleğe alınır, menü açılınca ve açıkken iletilir
local EV = 'loe_jobcreator:client:healthState'
sim.frames(700)
sim.fire(EV, { enabled = true, conditions = { { id = 'flu', label = 'Flu', symptom = 'cough', bandaged = false, suppressed = true } } })
sim.pause = true; sim.frames(64)
local o = sim.lastOpen()
check(isOpen() == true, 'S7: menü açılmalı')
check(o.health and o.health.known == true and #o.health.conditions == 1 and o.health.conditions[1].label == 'Flu'
    and o.health.conditions[1].suppressed == true and o.health.conditions[1].bandaged == false, 'S7: hastalık menü açılırken iletilmeli')
sim.fire(EV, { enabled = true, conditions = {} })
check(sim.last().action == 'health' and #sim.last().health.conditions == 0, 'S7: menü açıkken güncelleme "health" mesajı olarak gitmeli')
sim.fire(EV, 'çöp')
sim.fire(EV, { enabled = true, conditions = { 'x', { label = 5 }, { label = '' }, { label = 'Ok' } } })
check(#sim.last().health.conditions == 1 and sim.last().health.conditions[1].label == 'Ok', 'S7: bozuk veri süzülmeli')
sim.fire(EV, { enabled = false })
check(#sim.last().health.conditions == 0, 'S7: sağlık sistemi kapalıyken liste boş olmalı')

-- S7b: oyuncu çıkışı önbelleği siler; loe_jobcreator çalışıyorsa menü güncel durumu bir kez ister (10 sn sınırı)
sim.exported.Close(); sim.frames(700)
sim.fire('QBCore:Client:OnPlayerUnload')
sim.started.loe_jobcreator = true
local hello = 'loe_jobcreator:server:healthHello'
local n0 = sim.count(sim.serverEvents, hello)
sim.pause = true; sim.frames(64)
check(sim.lastOpen().health.known == false, 'S7b: çıkıştan sonra önbellek temiz olmalı')
check(sim.count(sim.serverEvents, hello) == n0 + 1, 'S7b: bilinmeyen durumda healthHello istenmeli')
sim.exported.Close(); sim.frames(700)
sim.pause = true; sim.frames(64)
check(sim.count(sim.serverEvents, hello) == n0 + 1, 'S7b: 10 sn içinde tekrar istenmemeli')
sim.exported.Close()

-- S8: GTA'nın güncel ayar değerleri (salt okunur) menü açılırken iletilir; okunamayan/geçersiz değer hiç gönderilmez
sim.frames(700)
IsSubtitlePreferenceSwitchedOn = function() return true end
ShouldUseMetricMeasurements = function() return true end
GetSafeZoneSize = function() return 0.95 end
GetActualScreenResolution = function() return 2560, 1440 end
GetCurrentLanguage = function() return 0 end
sim.pause = true; sim.frames(64)
local nv = sim.lastOpen().native
check(type(nv) == 'table' and nv.subtitles == true and nv.metric == true and nv.safezone == 95
    and nv.resolution == '2560x1440' and nv.language == 0, 'S8: GTA ayar değerleri menü açılırken iletilmeli')
sim.exported.Close(); sim.frames(700)
GetSafeZoneSize = function() return 5.0 end                 -- geçersiz aralık
GetActualScreenResolution = function() return 0, 0 end
GetCurrentLanguage = function() error('native yok') end     -- native patlarsa menü yine açılmalı
sim.pause = true; sim.frames(64)
nv = sim.lastOpen().native
check(isOpen() == true, 'S8: okuma hatası menüyü bozmamalı')
check(nv.safezone == nil and nv.resolution == nil and nv.language == nil, 'S8: geçersiz/okunamayan değer gönderilmemeli')
sim.exported.Close(); sim.frames(700)

-- S8b: yerleşik GTA menüsü KAPALI (allowNativeMenu = false): eski tercih true olsa bile ESC her zaman LOE menüsünü açar
check(Config.Hijack.allowNativeMenu == false, 'S8b: allowNativeMenu varsayılanı false olmalı')
Prefs.set('menu.native', true)
sim.pause = true; sim.frames(64)
check(isOpen() == true and sim.pause == false, 'S8b: tercih true olsa da ESC LOE menüsünü açmalı, yerleşik menü söndürülmeli')
local rs = sim.nui('setting', { id = 'menu.native', value = true })
check(rs and rs.ok == false, 'S8b: menu.native değişikliği reddedilmeli')
local ra = sim.nui('action', { id = 'menu.opennative' })
check(ra and ra.ok == false, 'S8b: menu.opennative reddedilmeli')
local actBefore = sim.calls.Activate or 0
sim.frames(800)
check((sim.calls.Activate or 0) == actBefore and sim.pause == false, 'S8b: yerleşik menü açılmamalı')
sim.exported.Close(); sim.frames(700)

-- S8c: allowNativeMenu = true iken eski davranış (kaçış kapısı): tercih açıksa ESC yerleşik menüyü serbest bırakır
Config.Hijack.allowNativeMenu = true
sim.pause = true; sim.frames(160)
check(isOpen() == false and sim.pause == true, 'S8c: izin verilmişse tercih açıkken yerleşik menü serbest kalmalı')
sim.pause = false; sim.frames(700)
Config.Hijack.allowNativeMenu = false
Prefs.set('menu.native', false)

-- S9: Oyundan Çık → yalnızca "sunucudan ayrıl" (disconnect) çalışır; oyunu kapatan 'quit' hiçbir yoldan çalışmaz
local cmds, restarts = {}, 0
ExecuteCommand = function(c) cmds[#cmds + 1] = c end
RestartGame = function() restarts = restarts + 1 end
sim.pause = true; sim.frames(64)
check(isOpen() == true, 'S9: menü açılmalı')
sim.nui('quit', { mode = 'quit' }); sim.frames(400)
check(#cmds == 0 and isOpen() == true, 'S9: mode=quit reddedilmeli (menü açık kalır, komut yok)')
sim.nui('quit', {}); sim.nui('quit', 'x'); sim.frames(400)
check(#cmds == 0 and isOpen() == true, 'S9: modsuz/bozuk istek reddedilmeli')
local leave0 = sim.count(sim.serverEvents, 'loe_pause:server:leave')
check(leave0 == 0, 'S9: reddedilen isteklerde sunucuya ayrılma olayı gitmemeli')
check(restarts == 0, 'S9: reddedilen isteklerde oyun yeniden başlatılmamalı')
sim.nui('quit', { mode = 'disconnect' }); sim.frames(800)
check(sim.count(sim.serverEvents, 'loe_pause:server:leave') == 1, 'S9: sunucudan ayrıl, sunucuya ayrılma olayını göndermeli')
check(isOpen() == false, 'S9: ayrılırken menü kapanmalı')
check(restarts == 0, 'S9: sunucuya süre tanınmalı (yedek hemen çalışmamalı)')
sim.frames(3000)
check(restarts == 1, 'S9: sunucu düşürmezse yedek olarak RestartGame çalışmalı')
check(#cmds == 0, 'S9: script\'ten çalışmayan disconnect komutu kullanılmamalı')

-- S10: Hızlı Eylemler — kısayol komutu menü kapandıktan sonra çalışır; yetki gerektirenler yalnızca sunucu onayıyla
sim.frames(700)
sim.fire('QBCore:Client:OnPlayerUnload')
sim.pause = true; sim.frames(64)
check(isOpen() == true, 'S10: menü açılmalı')
check(type(sim.lastOpen().caps) == 'table' and next(sim.lastOpen().caps) == nil, 'S10: yetki gelmeden caps boş olmalı')
check(sim.count(sim.serverEvents, 'loe_pause:server:caps') >= 1, 'S10: açılışta sunucudan yetki istenmeli')
local r1 = sim.nui('action', { id = 'cmd.cursor' })
check(r1 and r1.ok == true, 'S10: imlec eylemi ok dönmeli')
check(isOpen() == false, 'S10: eylem menüyü kapatmalı')
sim.frames(500)
check(#cmds == 1 and cmds[1] == 'imlec', 'S10: kısayol komutu menü kapandıktan sonra çalışmalı')

sim.frames(700)
sim.pause = true; sim.frames(64)
local r2 = sim.nui('action', { id = 'cmd.admin' })
check(r2 and r2.ok == false and isOpen() == true, 'S10: yetkisizken admin eylemi reddedilmeli')
sim.frames(500)
check(#cmds == 1, 'S10: reddedilen admin komutu çalıştırılmamalı')
local r3 = sim.nui('action', { id = 'cmd.hack' })
check(r3 and r3.ok == false, 'S10: tanımsız kısayol reddedilmeli')
local r3b = sim.nui('action', { id = 'cmd.cursor; quit' })
check(r3b and r3b.ok == false, 'S10: kimliğe komut eklenemez')

sim.fire('loe_pause:client:caps', { 'admin' })
check(sim.last().action == 'caps' and sim.last().caps.admin == true, 'S10: yetki menü açıkken arayüze iletilmeli')
sim.fire('loe_pause:client:caps', { 'cursor', 'hack', 5 })
check(sim.last().caps.cursor == nil and sim.last().caps.hack == nil and sim.last().caps.admin == nil, 'S10: bozuk/yetkisiz caps listesi süzülmeli')
sim.fire('loe_pause:client:caps', 'çöp')
sim.fire('loe_pause:client:caps', { 'admin' })
local r4 = sim.nui('action', { id = 'cmd.admin' })
check(r4 and r4.ok == true, 'S10: yetkiliyken admin eylemi çalışmalı')
sim.frames(500)
check(#cmds == 2 and cmds[2] == 'admin', 'S10: admin komutu çalışmalı')
sim.fire('QBCore:Client:OnPlayerUnload')
sim.frames(700)
sim.pause = true; sim.frames(64)
check(next(sim.lastOpen().caps) == nil, 'S10: oyuncu çıkınca yetki silinmeli')
sim.exported.Close(); sim.frames(700)

setMapItem(false)   -- varsayılan: MAP menüde yok, harita yalnızca M ile

-- S14: Game/UI Settings alt ekranı — ESC menüyü KAPATMAZ (arayüz bir adım geri döner); "Restore defaults" yalnızca şemadaki id'leri sıfırlar
sim.frames(700)
sim.pause = true; sim.frames(64)
check(isOpen() == true, 'S14: menü açılmalı')
sim.frames(400)
check(sim.nui('sub', { on = 'evet' }) ~= nil, 'S14: sub callback çökmemeli')
sim.nui('sub', { on = true })
sim.escFrame = true; sim.step(16); sim.frames(300)
check(isOpen() == true, 'S14: alt ekrandayken ESC menüyü kapatmamalı')
sim.pause = true; sim.frames(64)                              -- ESC'nin sızdırdığı yerleşik duraklatma menüsü de kapatmamalı, yalnızca söndürülmeli
check(isOpen() == true and sim.pause == false, 'S14: alt ekranda sızan duraklatma menüsü söndürülmeli, LOE menüsü açık kalmalı')
sim.nui('sub', { on = false })
sim.frames(100); sim.escFrame = true; sim.step(16); sim.frames(300)
check(isOpen() == false, 'S14: ana listedeyken ESC menüyü kapatmalı')
sim.pause = true; sim.frames(64)
sim.nui('sub', { on = true }); sim.exported.Close(); sim.frames(100)
sim.pause = true; sim.frames(64)
check(isOpen() == true, 'S14: yeniden açılışta alt ekran bilgisi sıfırlanmış olmalı')
sim.frames(400)
sim.escFrame = true; sim.step(16); sim.frames(300)
check(isOpen() == false, 'S14: yeni açılışta ESC yine menüyü kapatmalı')

-- Restore defaults
sim.frames(700)
sim.pause = true; sim.frames(64)
check(isOpen() == true, 'S14: menü açılmalı (restore)')
Prefs.set('voice.radio', 85); Prefs.set('aim.mode', 'free')
local rr = sim.nui('restore', { ids = { 'voice.radio', 'zzz.yok', 5, 'menu.opennative', 'aim.mode' } })
check(rr and rr.ok == true and rr.values['voice.radio'] == 60 and rr.values['aim.mode'] == 'game', 'S14: restore yalnızca geçerli id\'leri varsayılana döndürmeli')
check(Prefs.get('voice.radio') == 60 and Prefs.get('aim.mode') == 'game', 'S14: restore kalıcı değeri de sıfırlamalı')
Prefs.set('disp.radar', false)
local ro = sim.nui('restore', { ids = { 'disp.reticle' } })
check(ro.ok == true and Prefs.get('disp.radar') == false, 'S14: restore listede olmayan ayarlara dokunmamalı')
Prefs.reset({ 'disp.radar' })
check(sim.nui('restore', { ids = { 'zzz.yok', 7 } }).ok == false and sim.nui('restore', { ids = 'x' }).ok == false and sim.nui('restore', {}).ok == false, 'S14: geçersiz restore istekleri reddedilmeli')
sim.exported.Close(); sim.frames(700)
-- S11: M tuşu (loe_bigmap) → menüsüz doğrudan büyük harita; aynı tuş / ESC kapatır; LOE menüsü geri gelmez
check(type(sim.commands.loe_bigmap) == 'function', 'S11: loe_bigmap komutu kayıtlı olmalı')
Prefs.set('pref.mapReturn', true)                            -- dönüş tercihi AÇIK olsa bile tuştan açılan harita menüye dönmemeli
local act11, open11 = sim.calls.Activate or 0, sim.openCount()
sim.commands.loe_bigmap(); sim.frames(1300)
check((sim.calls.Activate or 0) == act11 + 1 and sim.calls.GoDeeper == 0, 'S11: M büyük haritayı doğrudan açmalı (GoDeeper(0))')
check(sim.pause == true and isOpen() == false and sim.openCount() == open11, 'S11: harita açık, LOE menüsü açılmamalı')
sim.escFrame = true; sim.step(16); sim.frames(1500)
check(sim.pause == false and isOpen() == false and sim.openCount() == open11, 'S11: ESC haritayı kapatmalı, LOE menüsü dönmemeli (mapReturn açık olsa da)')

sim.frames(700)
sim.commands.loe_bigmap(); sim.frames(1300)
check(sim.pause == true, 'S11: M ikinci kez haritayı açmalı')
sim.commands.loe_bigmap(); sim.frames(1500)                  -- harita açıkken aynı tuş kapatır
check(sim.pause == false and isOpen() == false and sim.openCount() == open11, 'S11: harita açıkken M haritayı kapatmalı')
sim.frames(700)

local act11b = sim.calls.Activate or 0
sim.pause = true; sim.frames(64)                             -- LOE menüsü açıkken M işlemez
check(isOpen() == true, 'S11: menü açılmalı')
sim.commands.loe_bigmap(); sim.frames(600)
check((sim.calls.Activate or 0) == act11b and isOpen() == true, 'S11: LOE menüsü açıkken M harita açmamalı')
sim.exported.Close(); sim.frames(700)
LocalPlayer.state.isLoggedIn = false
sim.commands.loe_bigmap(); sim.frames(600)
check((sim.calls.Activate or 0) == act11b, 'S11: giriş yapılmamışken M harita açmamalı')
LocalPlayer.state.isLoggedIn = true; sim.frames(300)
sim.nuiFocus = true
sim.commands.loe_bigmap(); sim.frames(600)
check((sim.calls.Activate or 0) == act11b, 'S11: başka bir arayüz odaktayken M harita açmamalı')
sim.nuiFocus = false; sim.frames(600)
Prefs.set('pref.mapReturn', false)

-- S12: ana menü verisi — bağlantılar süzülür, GTA düğmesi anahtarı, menü sırası, oyuncu kartı
local function lastInit() local l; for _, m in ipairs(sim.msgs) do if m.action == 'init' then l = m end end return l end
sim.nui('ready')
check(lastInit() and type(lastInit().links) == 'table' and #lastInit().links == 0, 'S12: adresi boş bağlantı NUI\'ye gitmemeli')
check(lastInit().gta == true, 'S12: GTA ayarları düğmesi varsayılan açık olmalı')
local oldLinks = Config.Links
Config.Links = {
    { id = 'youtube', label = 'YouTube', url = 'https://example.com/yt' },
    { id = 'discord', label = 'Discord', url = 'http://example.com/insecure' },
    { id = 'store',   label = 'Store',   url = 'javascript:alert(1)' },
    { id = 'x1',      label = 'X',       url = 'https://exa mple.com' },
    { id = 'x2',      label = 'X',       url = 'https://a.com/"onload="x' },
    'çöp', { id = 5, url = 'https://ok.example' },
}
sim.nui('ready')
local lk = lastInit().links
check(#lk == 1 and lk[1].id == 'youtube' and lk[1].url == 'https://example.com/yt', 'S12: yalnızca geçerli https adresleri gönderilmeli (' .. tostring(#lk) .. ')')
Config.Links = oldLinks
Config.Features.allGtaSettings = false
sim.nui('ready')
check(lastInit().gta == false, 'S12: allGtaSettings=false iken düğme gizlenmeli')
Config.Features.allGtaSettings = nil
sim.nui('ready')

rawset(exports, 'qbx_core', { GetPlayerData = function() return {
    citizenid = 'ABC123', charinfo = { firstname = 'Mark', lastname = 'Smith' },
    job = { label = 'LSPD', grade = { name = 'Lieutenant' } }, money = { cash = 0, bank = 27640295 } } end })
sim.pause = true; sim.frames(64)
local op = sim.lastOpen()
check(isOpen() == true and op.stats.id == 7 and op.stats.name == 'Mark Smith' and op.stats.job == 'LSPD'
    and op.stats.grade == 'Lieutenant' and op.stats.cash == 0 and op.stats.bank == 27640295, 'S12: oyuncu kartı verisi (kimlik/ad/meslek/para) iletilmeli')
local ids, soonId = {}, nil
for _, m in ipairs(op.menu) do ids[#ids + 1] = m.id; if m.soon then soonId = m.id end end
check(table.concat(ids, ',') == 'resume,game,ui,position,quit', 'S12: ana menü sırası (MAP yok, harita yalnızca M): ' .. table.concat(ids, ','))
check(sim.nui('menu', { id = 'map' }).ok == false, 'S12: MAP menüden kaldırıldı, menu callback reddetmeli')
check(soonId == 'position', 'S12: KONUM MODU "yakında" olarak işaretlenmeli')
check(sim.nui('menu', { id = 'stats' }) and sim.nui('menu', { id = 'stats' }).ok == false, 'S12: kapalı menü maddesi (stats) reddedilmeli')
check(sim.nui('menu', { id = 'hack' }).ok == false, 'S12: tanımsız menü maddesi reddedilmeli')
rawset(exports, 'qbx_core', nil)
sim.exported.Close(); sim.frames(700)

-- S15: GEÇİCİ gfxprobe — yetki sunucudan gelir; test sırasında ana döngü yerleşik menüye dokunmaz; bitince her şey eski haline döner
local realPrint, realEncode = print, json.encode
print = function() end
json.encode = function(t) sim.encoded = t; return 'X' end
sim.frames(800)
check(type(LoeProbe) == 'table' and LoeProbe.active == false, 'S15: LoeProbe tanımlı ve pasif olmalı')
local actP = sim.calls.Activate or 0
sim.commands['loe_gfxtest']()
check(sim.serverEvents[#sim.serverEvents] == 'loe_pause:server:gfxprobeAsk', 'S15: komut önce sunucudan yetki istemeli')
check(sim.pause == false, 'S15: yetki gelmeden menü açılmamalı')
sim.fire('loe_pause:client:gfxprobeGo', 'auto', false)
sim.frames(2000)
check(sim.pause == false and LoeProbe.active == false and (sim.calls.Activate or 0) == actP, 'S15: yetkisiz oyuncuda test başlamamalı')

sim.latent, sim.encoded = nil, nil
sim.commands['loe_gfxtest']()
sim.fire('loe_pause:client:gfxprobeGo', 'auto', true)
sim.frames(1600)
check(LoeProbe.active == true and sim.pause == true and isOpen() == false, 'S15: test GTA ayar menüsünü açmalı')
sim.escFrame = true; sim.step(16); sim.frames(500)
check(sim.pause == true and isOpen() == false, 'S15: test sırasında ESC yakalama yerleşik menüye dokunmamalı')
sim.frames(30000)
check(LoeProbe.active == false and sim.pause == false and isOpen() == false, 'S15: test bitince menü kapanmalı, LOE menüsü açılmamalı')
check(sim.latent and sim.latent.name == 'loe_pause:server:gfxprobe' and sim.encoded and sim.encoded.kind == 'auto', 'S15: sonuç sunucuya gönderilmeli')
local phases = {}
for _, e in ipairs((sim.encoded or {}).log or {}) do if e.k == 'phase' then phases[#phases + 1] = e.name end end
check(table.concat(phases, ',') == 'open,deeper0,nav-g2,nav-g0,hidden,scaleform,end', 'S15: faz sırası: ' .. table.concat(phases, ','))
check(sim.calls.GoDeeper == 0, 'S15: ayar sayfasına GoDeeper(0) ile girilmeli')

-- kayıt: profil değişikliği yakalanmalı, ESC kaydı bitirmemeli, Delete bitirmeli
sim.latent, sim.encoded = nil, nil
sim.frames(800)
sim.commands['loe_gfxrec']()
sim.fire('loe_pause:client:gfxprobeGo', 'record', true)
sim.frames(2000)
check(LoeProbe.active == true and sim.pause == true, 'S15: kayıt GTA ayar menüsünü açmalı')
sim.profile[203] = 1; sim.frames(600); sim.profile[203] = nil; sim.frames(600)
sim.escFrame = true; sim.step(16); sim.frames(300)
check(sim.pause == true and LoeProbe.active == true, 'S15: kayıtta ESC kaydı bitirmemeli')
sim.delFrame = true; sim.step(16); sim.frames(3000)
check(LoeProbe.active == false and sim.pause == false and isOpen() == false, 'S15: Delete kaydı bitirmeli, menü kapanmalı')
local prof, reason = 0, nil
for _, e in ipairs((sim.encoded or {}).log or {}) do
    if e.k == 'profile' then prof = prof + 1 end
    if e.k == 'recordEnd' then reason = e.reason end
end
check(sim.encoded and sim.encoded.kind == 'record' and reason == 'delete' and prof == 2, 'S15: kayıt sonucu (tür/neden/profil değişikliği): ' .. tostring(reason) .. ' ' .. prof)

-- hata yolu: test ortasında native hata verirse test kapanmalı, hata raporlanmalı, ESC yakalama geri gelmeli
local realAct = ActivateFrontendMenu
ActivateFrontendMenu = function() error('boom') end
sim.latent, sim.encoded = nil, nil
sim.frames(800)
sim.commands['loe_gfxtest']()
sim.fire('loe_pause:client:gfxprobeGo', 'auto', true)
sim.frames(4000)
ActivateFrontendMenu = realAct
check(LoeProbe.active == false and sim.encoded and sim.encoded.error ~= nil, 'S15: hata olursa test kapanmalı ve hata raporlanmalı')

-- test bittikten sonra ESC yine LOE menüsünü açmalı
sim.frames(700)
sim.pause = true; sim.frames(64)
check(isOpen() == true, 'S15: test sonrası ESC yakalama geri gelmeli')
sim.exported.Close(); sim.frames(700)
print, json.encode = realPrint, realEncode
return R
'''

sim = LuaRuntime(unpack_returned_tuples=True)
sim.execute(SIM_PRELUDE)
import os  # noqa: E402

for rel in ('config.lua', 'shared/schema.lua', 'client/prefs.lua', 'client/apply.lua', 'client/main.lua', 'client/gfxprobe.lua'):
    path = ROOT / rel
    if rel == 'client/main.lua' and os.environ.get('LOE_MAIN_LUA'):      # eski sürümle testin hatayı yakaladığını doğrulamak için
        path = pathlib.Path(os.environ['LOE_MAIN_LUA'])
    sim.execute(path.read_text(encoding='utf-8'))
try:
    res = lua_to_py(sim.execute(SIM_SCENARIO))
    for msg in (res or []):
        check(False, msg)
    print('  senaryolar tamam')
except Exception as exc:  # noqa: BLE001
    check(False, f'simülasyon hatası: {exc}')

# ------------------------------------------------------------------ 5) sunucu: ayrılma olayı
print('[5] Sunucu: sunucudan ayrıl')
sv = LuaRuntime(unpack_returned_tuples=True)
sv.execute(r'''
handlers, dropped, now, source = {}, {}, 1000, 0
function RegisterNetEvent(n, fn) handlers[n] = fn end
function AddEventHandler(n, fn) handlers[n] = fn end
function GetGameTimer() return now end
function DropPlayer(s, r) dropped[#dropped + 1] = { s = s, r = r } end
''')
sv.execute(r'''
aceTable, sent = {}, {}
function IsPlayerAceAllowed(s, a) return aceTable[s .. ':' .. a] == true end
function TriggerClientEvent(n, t, list) sent[#sent + 1] = { n = n, t = t, list = list } end
''')
sv.execute((ROOT / 'config.lua').read_text(encoding='utf-8'))
sv.execute((ROOT / 'server/main.lua').read_text(encoding='utf-8'))
CAPS = sv.eval('''function(src, adv, admin)
    source = src; now = now + (adv or 0)
    aceTable[tostring(src) .. ':admin'] = admin == true
    handlers['loe_pause:server:caps']()
    return #sent
end''')
SV = sv.eval('''function(src, adv)
    source = src; now = now + (adv or 0)
    handlers['loe_pause:server:leave']()
    return #dropped
end''')
sv_drop = sv.eval('function() source = 5 handlers["playerDropped"]() end')
check(SV(5) == 1, 'sunucu: ayrılma isteği oyuncuyu düşürmeli')
d0 = lua_to_py(sv.eval('dropped[1]'))
check(d0['s'] == 5 and isinstance(d0['r'], str) and d0['r'], 'sunucu: yalnızca isteği gönderen düşürülmeli, neden metni dolu olmalı')
check(SV(5, 500) == 1, 'sunucu: 3 sn içinde art arda istek yok sayılmalı')
check(SV(5, 3000) == 2, 'sunucu: süre dolunca yeniden düşürülebilmeli')
check(SV(0) == 2, 'sunucu: source=0 yok sayılmalı')
check(SV('7') == 2, 'sunucu: sayı olmayan source yok sayılmalı')
check(SV(-3) == 2, 'sunucu: negatif source yok sayılmalı')
sv_drop()
check(SV(5, 10) == 3, 'sunucu: oyuncu çıkınca sınır kaydı temizlenmeli')

# yetki görünürlüğü (Hızlı Eylemler)
n0 = int(sv.eval('#sent'))
check(CAPS(9, 5000, False) == n0 + 1, 'sunucu: caps isteği yanıtlanmalı')
last = lua_to_py(sv.eval('sent[#sent]'))
check(last['n'] == 'loe_pause:client:caps' and last['t'] == 9 and len(lua_to_py(sv.eval('sent[#sent].list')) or []) == 0, 'sunucu: yetkisiz oyuncuya boş liste gitmeli')
check(CAPS(9, 100, True) == n0 + 1, 'sunucu: caps istekleri 2 sn sınırlanmalı')
check(CAPS(9, 3000, True) == n0 + 2, 'sunucu: süre dolunca yeniden yanıtlanmalı')
check(list(lua_to_py(sv.eval('sent[#sent].list'))) == ['admin'], 'sunucu: admin ACE sahibine "admin" gitmeli')
check(CAPS(0, 5000, True) == n0 + 2, 'sunucu: source=0 yok sayılmalı')
sv.execute('source = 9 handlers["playerDropped"]()')
check(CAPS(9, 0, False) == n0 + 3, 'sunucu: oyuncu çıkınca caps sınırı temizlenmeli')


# GEÇİCİ gfxprobe: yalnızca admin ACE, oran sınırı, boyut sınırı, dosya adı
sv.execute(r'''
saved = {}
function SaveResourceFile(res, name, data, len) saved[#saved + 1] = { res = res, name = name, n = #data } return true end
function GetCurrentResourceName() return 'loe_pause' end
function TriggerClientEvent(n, t, ...) local a = { ... }; sent[#sent + 1] = { n = n, t = t, list = a[1], allowed = a[2] } end
''')
ASK = sv.eval('''function(src, adv, admin, mode)
    source = src; now = now + (adv or 0)
    aceTable[tostring(src) .. ':admin'] = admin == true
    handlers['loe_pause:server:gfxprobeAsk'](mode)
    return #sent
end''')
PUT = sv.eval('''function(src, adv, admin, payload)
    source = src; now = now + (adv or 0)
    aceTable[tostring(src) .. ':admin'] = admin == true
    handlers['loe_pause:server:gfxprobe'](payload)
    return #saved
end''')
n1 = int(sv.eval('#sent'))
check(ASK(11, 5000, False, 'auto') == n1 + 1, 'sunucu: gfxprobe yetki isteği yanıtlanmalı')
lastp = lua_to_py(sv.eval('sent[#sent]'))
check(lastp['n'] == 'loe_pause:client:gfxprobeGo' and lastp['list'] == 'auto' and lastp.get('allowed') is False, 'sunucu: yetkisiz oyuncuya izin verilmemeli')
check(ASK(11, 100, True, 'record') == n1 + 1, 'sunucu: gfxprobe yetki isteği 3 sn sınırlanmalı')
check(ASK(11, 3500, True, 'record') == n1 + 2 and lua_to_py(sv.eval('sent[#sent]')).get('allowed') is True
      and lua_to_py(sv.eval('sent[#sent].list')) == 'record', 'sunucu: admin oyuncuya izin verilmeli')
check(ASK(11, 3500, True, 'evil') == n1 + 3 and lua_to_py(sv.eval('sent[#sent].list')) == 'auto', 'sunucu: bilinmeyen mod auto olmalı')
check(PUT(12, 0, False, '{"a":1}') == 0, 'sunucu: yetkisiz oyuncunun sonucu kaydedilmemeli')
check(PUT(12, 0, True, '{"a":1}') == 1, 'sunucu: admin sonucu kaydedilmeli')
sv1 = lua_to_py(sv.eval('saved[1]'))
import re  # noqa: E402
check(sv1['res'] == 'loe_pause' and re.fullmatch(r'gfxprobe_\d{8}_\d{6}_12\.json', sv1['name']) is not None, f'sunucu: dosya adı biçimi: {sv1["name"]}')
check(PUT(12, 500, True, '{"b":1}') == 1, 'sunucu: 10 sn içinde ikinci sonuç yok sayılmalı')
check(PUT(12, 11000, True, 'z' * 1500001) == 1, 'sunucu: çok büyük sonuç reddedilmeli')
check(PUT(12, 0, True, 123) == 1 and PUT(12, 0, True, '') == 1, 'sunucu: metin olmayan / boş sonuç reddedilmeli')
check(PUT(12, 0, True, '{"c":1}') == 2, 'sunucu: geçersiz istekler oran sınırını tüketmemeli')
sv.execute('Config.GfxProbe.enabled = false')
check(PUT(12, 20000, True, '{"d":1}') == 2 and ASK(13, 0, True, 'auto') and lua_to_py(sv.eval('sent[#sent]')).get('allowed') is False,
      'sunucu: GfxProbe kapalıyken hiçbir şey kabul edilmemeli')
sv.execute('Config.GfxProbe.enabled = true')

print()
if failures:
    print(f'{len(failures)} HATA')
    sys.exit(1)
print('Tüm denetimler geçti.')
