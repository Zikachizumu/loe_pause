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
import importlib.util
import struct
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
lua.execute((ROOT / 'shared/gtaset_data.lua').read_text(encoding='utf-8'))
lua.execute((ROOT / 'shared/schema.lua').read_text(encoding='utf-8'))
cats = lua_to_py(lua.eval('Schema.categories'))

expected = ['controller', 'mouse', 'keys', 'audio', 'camera', 'advgfx', 'display', 'voice', 'editor', 'prefs', 'menu']
check([c['id'] for c in cats] == expected, f'kategori sırası beklenenden farklı: {[c["id"] for c in cats]}')

tr_names = ['Kontroller', 'Klavye / Fare', 'Tuş Atamaları', 'Ses', 'Kamera', 'Grafik', 'Görüntü',
            'Sesli Sohbet', 'Rockstar Editor', 'Tercihler', 'Normal Menü']
check([c['label']['tr'] for c in cats] == tr_names, 'Türkçe kategori adları/sırası beklenenle uyuşmuyor')
check([c['id'] for c in cats if c.get('hidden')] == ['menu'], 'Normal Menü yalnızca allowNativeMenu=false iken gizli olmalı (başka gizli kategori olmamalı)')

seen = {}
for c in cats:
    check(len(c['groups']) > 0, f'{c["id"]}: grup yok')
    for g in c['groups']:
        check(len(g['rows']) > 0, f'{c["id"]}.{g["id"]}: boş grup')
        for r in g['rows']:
            t = r['type']
            check(t in ('toggle', 'select', 'slider', 'key', 'action', 'info', 'gtaslider', 'glist', 'gta'), f'bilinmeyen/izin verilmeyen tür {t}')
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
            if t in ('toggle', 'select', 'slider', 'key', 'action'):
                check(bool(r['label'].get('tr')) and bool(r['label'].get('en')), f'{r.get("id") or r["label"]}: etiket eksik')
            if t == 'key':
                check(('control' in r) != ('command' in r), f'key satırı control XOR command olmalı: {r["label"]}')
            if t == 'gtaslider':
                check(isinstance(r.get('pid'), int) and r.get('max', 0) >= 1 and r.get('text'), f'{r.get("id")}: GTA kaydırıcı satırı eksik (pid/max/text)')
            if t == 'glist':
                check(isinstance(r.get('pid'), int) and len(r.get('labels', {})) >= 2 and r.get('text'), f'{r.get("id")}: GTA liste satırı eksik (pid/labels/text)')
            if t == 'gta':
                check(r.get('target') in ('settings', 'graphics', None), f'gta satırı hedefi geçersiz: {r.get("target")}')

native_targets = set(lua_to_py(lua.eval('(function() local t = {} for k in pairs(Config.Native) do t[k] = true end return t end)()')).keys())
check('settings' in native_targets, 'Config.Native.settings tanımlı olmalı (OPTIONS → GTA Settings bunu açar)')
for c in cats:
    for g in c['groups']:
        check(any(r['type'] != 'info' for r in g['rows']), f'{c["id"]}.{g["id"]}: yalnızca bilgi notu olan grup kalmamalı')

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

# GTA'nın kendi ayarları: tablo (shared/gtaset_data.lua) → şema satırları
gta_rows = [r for c in cats for g in c['groups'] for r in g['rows'] if r['type'] in ('gtaslider', 'glist')]
data_rows = lua_to_py(lua.eval('(function() local t = {} for _, c in ipairs(GtaSetData.cats) do for _, r in ipairs(c.rows) do if r.pid and (r.kind == "slider" or r.kind == "list") then t[#t + 1] = { pid = r.pid, kind = r.kind } end end end return t end)()'))
data_rows = list(data_rows.values()) if isinstance(data_rows, dict) else list(data_rows)
skipped = {0, 204, 205, 207, 412}                      # bizim satırlarımızla aynı işi yapanlar (schema.lua GTA_SKIP)
check({r['pid'] for r in gta_rows} == {d['pid'] for d in data_rows} - skipped, 'GTA satırları tablodaki tüm ayarlanabilir satırlar (GTA_SKIP hariç) olmalı')
check(len(gta_rows) == len({r['pid'] for r in gta_rows}), 'GTA satırlarında yinelenen pid var')
check(sum(1 for r in gta_rows if r['type'] == 'gtaslider') >= 20 and sum(1 for r in gta_rows if r['type'] == 'glist') >= 30, 'GTA satır sayıları beklenenden az')
check(next(r for r in gta_rows if r['pid'] == 212).get('inv') is True, 'Güvenli bölge (212) ters kaydırıcı olarak işaretli olmalı')
check(next(r for r in gta_rows if r['pid'] == 754)['max'] == 200, 'Fare hassasiyeti üst sınırı 200 olmalı (ölçüm)')
check(lua.eval("(function() for id in pairs(Schema.rows) do if tostring(id):sub(1, 4) == 'gta.' then return true end end return false end)()") is False,
      'GTA satırları Schema.rows (Prefs / KVP) içine girmemeli')
for pid in skipped:
    check(pid not in {r['pid'] for r in gta_rows}, f'{pid}: bizim satırımızla çakışan GTA ayarı listede olmamalı')
gta_cats = {c['id'] for c in cats for g in c['groups'] for r in g['rows'] if r['type'] in ('gtaslider', 'glist')}
check(gta_cats == {'controller', 'mouse', 'audio', 'camera', 'display'}, f'GTA satırlarının kategorileri: {gta_cats}')
check(any(r['type'] == 'gta' and r.get('target') == 'graphics' for c in cats for g in c['groups'] for r in g['rows']), 'Grafik sayfasında GTA Grafik ekranı satırı olmalı')
check('graphics' in native_targets and lua.eval("Config.Native.graphics.category") == 6, 'Config.Native.graphics doğrudan Grafik kategorisini açmalı (category = 6)')

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
check(all(x in menu_ids for x in ('resume', 'map', 'stats', 'inventory', 'battlepass', 'shop', 'settings', 'support', 'quit')) and 'position' not in menu_ids,
      'Config.Menu: ana maddeler eksik ya da KONUM MODU hâlâ listede')
check(lua.eval("(function() for _, m in ipairs(Config.Menu) do if m.id == 'map' then return m.enabled ~= false end end end)()") is True, 'Config.Menu: MAP menüde görünmeli (konsept)')
check(lua.eval('Config.MapCommand') != 'loe_bigmap' and lua.eval('Config.MapKey') == '', 'Config: loe_hud ile aynı komut adı / M tuşu çakışmamalı (M tuşu loe_hud/bigmap.lua içinde)')
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
check(pl.eval("Prefs.get('pref.lang')") == 'en' and pl.eval("Prefs.get('pref.accent')") == 'pink'
      and pl.eval("Prefs.get('pref.dark')") is True and pl.eval("Prefs.get('pref.mapReturn')") is False, 'sıfırlama: arayüz tercihleri varsayılana dönmeli')
check(pl.eval("Prefs.get('aim.mode')") == 'free', 'sıfırlama: oyun ayarları (aim.mode) korunmalı')
check(kvp.get('loe_pause:migrated:ui-reset-v1') == '1', 'sıfırlama: işaret yazılmalı')
check(not any(k.startswith('pref.') for k in json.loads(kvp['loe_pause:prefs:v1'])), 'sıfırlama: kayıttan pref.* silinmeli')
pl.execute("Prefs.set('pref.lang', 'tr'); Prefs.flush(); Prefs.values = {}; Prefs.load()")
check(pl.eval("Prefs.get('pref.lang')") == 'tr', 'sıfırlama: sonradan seçilen tercih kalıcı olmalı (sıfırlama yeniden çalışmamalı)')
pl.execute("Prefs.values = {}; Prefs.flush()")

pl.execute("Prefs.values = {}; Prefs.set('pref.accent', 'red'); Prefs.set('pref.dark', false)")
pl.execute("Prefs.reset({'pref.accent', 'pref.dark'})")
check(pl.eval("Prefs.get('pref.accent')") == 'pink' and pl.eval("Prefs.get('pref.dark')") is True, 'reset varsayılana dönmeli')
check(pl.eval("Prefs.get('pref.lang')") == 'en', "varsayılan dil 'en' olmalı")
check(pl.eval("Prefs.get('pref.dark')") is True, 'varsayılan koyu tema açık olmalı')

# sunucu varsayılan geçersiz kılma
pl.execute("Config.Defaults['pref.accent'] = 'blue'")
check(pl.eval("Prefs.default('pref.accent')") == 'blue', 'Config.Defaults uygulanmalı')
pl.execute("Config.Defaults['pref.accent'] = 'invalid'")
check(pl.eval("Prefs.default('pref.accent')") == 'pink', 'geçersiz Config.Defaults yok sayılmalı')

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
function GetLabelText(id) return 'T_' .. id end

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

sim.frames(700)

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

setMapItem(true)    -- varsayılan: MAP menüde görünür (M tuşu ayrıca loe_hud'da)

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
-- S11: menünün kendi harita komutu (loe_pause_map; M tuşu loe_hud'da) → menüsüz doğrudan büyük harita; aynı komut / ESC kapatır; LOE menüsü geri gelmez
check(type(sim.commands.loe_pause_map) == 'function' and sim.commands.loe_bigmap == nil, 'S11: loe_pause_map komutu kayıtlı olmalı, loe_bigmap (loe_hud içinde) kaydedilmemeli')
Prefs.set('pref.mapReturn', true)                            -- dönüş tercihi AÇIK olsa bile tuştan açılan harita menüye dönmemeli
local act11, open11 = sim.calls.Activate or 0, sim.openCount()
sim.commands.loe_pause_map(); sim.frames(1300)
check((sim.calls.Activate or 0) == act11 + 1 and sim.calls.GoDeeper == 0, 'S11: M büyük haritayı doğrudan açmalı (GoDeeper(0))')
check(sim.pause == true and isOpen() == false and sim.openCount() == open11, 'S11: harita açık, LOE menüsü açılmamalı')
sim.escFrame = true; sim.step(16); sim.frames(1500)
check(sim.pause == false and isOpen() == false and sim.openCount() == open11, 'S11: ESC haritayı kapatmalı, LOE menüsü dönmemeli (mapReturn açık olsa da)')

sim.frames(700)
sim.commands.loe_pause_map(); sim.frames(1300)
check(sim.pause == true, 'S11: M ikinci kez haritayı açmalı')
sim.commands.loe_pause_map(); sim.frames(1500)                  -- harita açıkken aynı tuş kapatır
check(sim.pause == false and isOpen() == false and sim.openCount() == open11, 'S11: harita açıkken M haritayı kapatmalı')
sim.frames(700)

local act11b = sim.calls.Activate or 0
sim.pause = true; sim.frames(64)                             -- LOE menüsü açıkken M işlemez
check(isOpen() == true, 'S11: menü açılmalı')
sim.commands.loe_pause_map(); sim.frames(600)
check((sim.calls.Activate or 0) == act11b and isOpen() == true, 'S11: LOE menüsü açıkken M harita açmamalı')
sim.exported.Close(); sim.frames(700)
LocalPlayer.state.isLoggedIn = false
sim.commands.loe_pause_map(); sim.frames(600)
check((sim.calls.Activate or 0) == act11b, 'S11: giriş yapılmamışken M harita açmamalı')
LocalPlayer.state.isLoggedIn = true; sim.frames(300)
sim.nuiFocus = true
sim.commands.loe_pause_map(); sim.frames(600)
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
sim.started.ox_inventory = true
sim.pause = true; sim.frames(64)
local op = sim.lastOpen()
check(isOpen() == true and op.stats.id == 7 and op.stats.name == 'Mark Smith' and op.stats.job == 'LSPD'
    and op.stats.grade == 'Lieutenant' and op.stats.cash == 0 and op.stats.bank == 27640295, 'S12: oyuncu kartı verisi (kimlik/ad/meslek/para) iletilmeli')
local ids, soons = {}, {}
for _, m in ipairs(op.menu) do ids[#ids + 1] = m.id; if m.soon then soons[#soons + 1] = m.id end end
check(table.concat(ids, ',') == 'resume,map,stats,inventory,battlepass,shop,settings,support,quit', 'S12: ana menü sırası (konsept; DISCONNECT son): ' .. table.concat(ids, ','))
check(sim.nui('menu', { id = 'position' }).ok == false, 'S12: KONUM MODU kaldırıldı, menu callback reddetmeli')
check(table.concat(soons, ',') == 'battlepass,shop', 'S12: resource çalışmayan Battlepass/Shop "yakında" olarak işaretlenmeli: ' .. table.concat(soons, ','))
check(sim.nui('menu', { id = 'battlepass' }).page == 'soon', 'S12: resource yokken Battlepass "yakında" sayfası döndürmeli')
check(sim.nui('menu', { id = 'stats' }).page == 'stats', 'S12: CHARACTER STATS yerleşik istatistik sayfasını döndürmeli')
check(sim.nui('menu', { id = 'hack' }).ok == false, 'S12: tanımsız menü maddesi reddedilmeli')
-- S12c: envanter maddesi: menü kapanır, ox_inventory export'u çağrılır
local invCalls = 0
rawset(exports, 'ox_inventory', { openInventory = function() invCalls = invCalls + 1 end })
check(sim.nui('menu', { id = 'inventory' }).ok == true, 'S12c: envanter maddesi kabul edilmeli')
sim.frames(600)
check(invCalls == 1 and isOpen() == false, 'S12c: menü kapanmalı ve ox_inventory açılmalı (çağrı=' .. invCalls .. ')')
rawset(exports, 'ox_inventory', nil)
-- S12e: loe_hud büyük haritası (M) açıkken LOE menüsü yerleşik menüyü ele geçirmez; harita kapanınca ESC yine LOE menüsünü açar
sim.started.loe_hud = true
rawset(exports, 'loe_hud', { IsBigMapOpen = function() return true end })
sim.pause = true; sim.frames(400)
check(isOpen() == false and sim.pause == true, 'S12e: loe_hud haritası açıkken yerleşik menü söndürülmemeli / LOE menüsü açılmamalı')
rawset(exports, 'loe_hud', { IsBigMapOpen = function() return false end })
sim.frames(700)
check(isOpen() == true, 'S12e: büyük harita kapanınca yerleşik menü yeniden LOE menüsüne çevrilmeli')
rawset(exports, 'loe_hud', nil); sim.started.loe_hud = nil
-- S12b: meslek / rütbe loe_jobcore'dan okunur (qbx_core job'u "unemployed / Freelancer" kalır)
local jc = { ready = true, state = { primaryJob = 'lspd', onDuty = false, jobs = { lspd = { name = 'lspd', label = 'LSPD', gradeLabel = 'Lieutenant' } } } }
rawset(exports, 'qbx_core', { GetPlayerData = function() return {
    citizenid = 'ABC123', charinfo = { firstname = 'Mark', lastname = 'Smith' },
    job = { label = 'Civilian', grade = { name = 'Freelancer' } }, money = { cash = 0, bank = 1 } } end })
rawset(exports, 'loe_jobcore', {
    IsReady = function() return jc.ready end, GetPlayerState = function() return jc.state end, GetJobLabel = function() return 'Unemployed' end })
local function reopen() sim.exported.Close(); sim.frames(700); sim.pause = true; sim.frames(64); return sim.lastOpen().stats end
sim.exported.Close(); sim.frames(700)
sim.started.loe_jobcore = true
local sj = reopen()
check(sj.job == 'LSPD' and sj.grade == 'Lieutenant', 'S12b: jobcore mesleği/rütbesi kartta görünmeli, Freelancer değil (' .. tostring(sj.job) .. '/' .. tostring(sj.grade) .. ')')
jc.state = { primaryJob = 'lspd', activeJob = 'mechanic', onDuty = true, jobs = { lspd = { label = 'LSPD', gradeLabel = 'Lieutenant' }, mechanic = { label = 'Mechanic', gradeLabel = 'Trainee' } } }
sj = reopen()
check(sj.job == 'Mechanic' and sj.grade == 'Trainee', 'S12b: mesaideki meslek birincil meslekten önce gelmeli (' .. tostring(sj.job) .. ')')
jc.state = { onDuty = false, jobs = {} }
sj = reopen()
check(sj.job == 'Unemployed' and sj.grade == nil, 'S12b: mesleği olmayan oyuncuda jobcore işsiz etiketi gösterilmeli, Freelancer değil (' .. tostring(sj.job) .. ')')
jc.ready = false
sj = reopen()
check(sj.job == nil and sj.name == 'Mark Smith', 'S12b: jobcore hazır değilken yanlış meslek gösterilmemeli')
jc.ready = true
sim.started.loe_jobcore = nil
sj = reopen()
check(sj.job == 'Civilian' and sj.grade == 'Freelancer', 'S12b: jobcore yokken qbx_core mesleğine düşmeli')
rawset(exports, 'loe_jobcore', nil)
rawset(exports, 'qbx_core', nil)
sim.exported.Close(); sim.frames(700)

-- S15: GTA'nın kendi ayarları — okuma (açılış verisi), doğrulama, gizli GTA menüsüyle yazma, yeniden deneme, hata, kilit
-- Sahte oyun: kategori/satır yapısı GERÇEK tablodan (shared/gtaset_data.lua). Kaydırıcılar uçta durur, listeler döner; ters
-- kaydırıcıda (212) sağ = değer azalır. Kök SET_INPUT_EVENT 9 gezinir (40 ms içinde gelen ikincisi yutulur), 10/11 değeri
-- değiştirir (aralıktan hız: 40 ms'den sık gelen yutulur); oyun gibi değer menü KAPANINCA kaydedilir. MENU_SHIFT_DEPTH(+1/-1)
-- satırlara girer/çıkar, sonra 300 ms gezinme yutulur; çıkınca kimlik bir gezinmeye kadar -1 olur; giriş/çıkış ve değer adımı
-- önceki işlemden 150 ms geçmeden gelirse yutulur.
local CATS = {}
for _, c in ipairs(GtaSetData.cats) do
    local rows = {}
    for _, r in ipairs(c.rows) do
        local row = { u = tostring(r.uid), p = r.pid, kind = r.kind, inv = r.inv }
        if r.kind == 'slider' then row.max = r.max
        elseif r.kind == 'list' then row.max = #r.labels - 1; row.wrap = true end
        rows[#rows + 1] = row
    end
    CATS[#CATS + 1] = { uid = tostring(c.uid), rows = rows }
end
CATS[#CATS + 1] = { uid = '6', rows = { { u = '103', p = 900, max = 2, wrap = true, kind = 'list' } } }   -- Graphics: dokunulmaz
table.insert(CATS, 3, { uid = '148', rows = {} })                                                     -- Key Bindings: girilmez
local START = {}
for _, c in ipairs(CATS) do
    for _, r in ipairs(c.rows) do if r.p then START[r.p] = (r.kind == 'slider') and math.min(r.max, 1 + (r.p % 5)) or 0 end end
end
START[754] = 50; START[213] = 18; START[212] = 3
for k, v in pairs(START) do sim.profile[k] = v end
local DEAD = { [761] = true }                                  -- hiç değişmeyen satır
local fk = { cat = 1, row = 0, focus = false, hn = 0, hv = {}, pending = {}, suppressAt = -1000, visibleRead = false, sessions = 0, valCount = 0 }
local realActivate, realSFA = ActivateFrontendMenu, SetFrontendActive
ActivateFrontendMenu = function(...)
    fk.sessions = fk.sessions + 1
    fk.cat, fk.row, fk.focus, fk.pending, fk.left = 1, 0, false, {}, false
    if fk.noOpen then return end
    return realActivate(...)
end
SetFrontendActive = function(v)
    if not v and sim.pause then for k, x in pairs(fk.pending) do sim.profile[k] = x end fk.pending = {} end
    return realSFA(v)
end
SuppressFrontendRenderingThisFrame = function() fk.suppressAt = sim.now end
local function isHidden() return sim.now - fk.suppressAt <= 32 end
local function value(pid) local v = fk.pending[pid]; if v == nil then v = sim.profile[pid] or 0 end return v end
BeginScaleformMovieMethodOnFrontend = function(path) fk.cur = { p = path, a = {} }; return 1 end
ScaleformMovieMethodAddParamInt = function(v) fk.cur.a[#fk.cur.a + 1] = v end
ScaleformMovieMethodAddParamBool = function(v) fk.cur.a[#fk.cur.a + 1] = v end
EndScaleformMovieMethod = function()
    if not sim.pause then return end
    local c, a = CATS[fk.cat], fk.cur.a
    local gap = sim.now - (fk.lastAny or -1000)
    if fk.cur.p == 'MENU_SHIFT_DEPTH' then
        if gap < 150 then return end
    elseif a[1] == 10 or a[1] == 11 then
        local vgap = sim.now - (fk.lastVal or -1000)
        if vgap < 40 or gap < 40 then return end
        fk.lastVal = sim.now
        fk.valCount = fk.valCount + 1
        if fk.flaky and vgap < 100 and fk.valCount % 4 == 0 then return end        -- hızlı basışların bir kısmı yutulur
    end
    fk.lastAny = sim.now
    if fk.cur.p == 'SET_INPUT_EVENT' then
        if a[1] == 9 then
            if sim.now - (fk.lastNav or -1000) < 40 or sim.now < (fk.lockUntil or 0) then return end
            fk.lastNav = sim.now
            if fk.focus then fk.row = (fk.row + 1) % #c.rows
            elseif fk.left then fk.left = false; fk.cat = fk.cat % #CATS + 1
            else fk.cat = fk.cat % #CATS + 1 end
        elseif (a[1] == 10 or a[1] == 11) and fk.focus then
            local r = c.rows[fk.row + 1]
            if r and r.p and not DEAD[r.p] then
                local v = value(r.p) + ((a[1] == 11) == not r.inv and 1 or -1)
                if r.wrap then v = v > r.max and 0 or (v < 0 and r.max or v) else v = math.max(0, math.min(r.max, v)) end
                fk.pending[r.p] = v
            end
        end
    elseif fk.cur.p == 'MENU_SHIFT_DEPTH' then
        fk.lockUntil = sim.now + 300
        if a[1] == 1 and #c.rows > 0 then fk.focus, fk.row, fk.left = true, 0, false
        elseif a[1] == -1 and fk.focus then fk.focus, fk.left = false, true end
    end
end
EndScaleformMovieMethodReturnValue = function()
    fk.hn = fk.hn + 1
    local p, c, r = fk.cur.p, CATS[fk.cat], nil
    if sim.pause then
        if not isHidden() and not fk.visibleOk then fk.visibleRead = true end
        if p == 'menuUniqueID.toString' then r = fk.focus and c.rows[fk.row + 1].u or (fk.left and '-1' or c.uid)
        elseif p == 'menuLevel.toString' then r = fk.focus and '2' or '1' end
    end
    fk.hv[fk.hn] = r
    return fk.hn
end
IsScaleformMovieMethodReturnValueReady = function(h) return fk.hv[h] ~= nil end
GetScaleformMovieMethodReturnValueString = function(h) return fk.hv[h] end
GetScaleformMovieMethodReturnValueInt = function(h) return tonumber(fk.hv[h]) or 0 end

local function doneMsg() local d; for _, m in ipairs(sim.msgs) do if m.action == 'gtaDone' then d = m end end return d end
local function listHas(list, v) for _, x in ipairs(list or {}) do if x == v then return true end end return false end

-- A) açılış verisi: GTA değerleri ve GTA etiketleri
sim.latent = nil
sim.pause = true; sim.frames(64)
check(isOpen() == true, 'S15: LOE menüsü açılmalı')
local op = sim.lastOpen()
check(type(op.gta) == 'table' and op.gta[300] == START[300] and op.gta[212] == 3 and op.gta[754] == 50 and op.gta[900] == nil,
    'S15: açılış verisinde GTA ayar değerleri olmalı (yalnızca tablodaki pid\'ler)')
check(type(op.gtaLabels) == 'table' and op.gtaLabels['MO_SFX'] == 'T_MO_SFX' and op.gtaLabels['MO_ON'] == 'T_MO_ON', 'S15: açılış verisinde GTA etiketleri olmalı')

-- B) doğrulama: bilinmeyen pid, aralık dışı, tam sayı olmayan, aynı değer, boş → reddedilir
check(GtaSet.clean({ ['300'] = START[300] }) == nil, 'S15: aynı değer değişiklik sayılmamalı')
check(GtaSet.clean({ ['999'] = 1, ['300'] = -1, ['301'] = 11, ['14'] = 2.5, ['13'] = 99 }) == nil, 'S15: geçersiz değerler elenmeli')
check(GtaSet.clean('x') == nil and GtaSet.clean({}) == nil and GtaSet.clean(nil) == nil, 'S15: geçersiz istek reddedilmeli')
local cl = GtaSet.clean({ ['300'] = 7, ['999'] = 1, ['301'] = 11, ['754'] = 120 })
check(cl and cl[300] == 7 and cl[754] == 120 and cl[301] == nil and cl[999] == nil, 'S15: yalnızca geçerli değişiklikler kalmalı')
check(sim.nui('gtaApply', { changes = { ['999'] = 1 } }).ok == false, 'S15: geçerli değişiklik yoksa uygulama başlamamalı')
check(GtaSet.busy == false and fk.sessions == 0, 'S15: boş istek GTA menüsünü açmamalı')

-- C) uygulama: kaydırıcı, ters kaydırıcı, liste (kısa yoldan dönme), fare hassasiyeti; LOE menüsü açık kalır
sim.msgs = {}
local r1 = sim.nui('gtaApply', { changes = { ['300'] = 7, ['301'] = 3, ['754'] = 120, ['212'] = 0, ['12'] = 11, ['999'] = 5, ['13'] = 99, ['14'] = 2.5 } })
check(r1 and r1.ok == true and GtaSet.busy == true, 'S15: uygulama başlamalı')
check(sim.nui('gtaApply', { changes = { ['300'] = 2 } }).ok == false, 'S15: uygulanırken ikinci istek reddedilmeli')
check(sim.nui('close').ok == false and isOpen() == true, 'S15: uygulanırken menü kapanmamalı')
sim.frames(1500)
check(sim.pause == true and isHidden() and isOpen() == true, 'S15: GTA menüsü gizli açılmalı, LOE menüsü açık kalmalı')
sim.escFrame = true; sim.step(16); sim.frames(300)
check(isOpen() == true and sim.pause == true, 'S15: uygulanırken ESC menüyü kapatmamalı')
sim.frames(120000)
local d1 = doneMsg()
check(d1 and d1.ok == true and #d1.failed == 0, 'S15: uygulama başarılı bildirilmeli')
check(sim.profile[300] == 7 and sim.profile[301] == 3 and sim.profile[754] == 120 and sim.profile[212] == 0 and sim.profile[12] == 11,
    'S15: değerler hedefe gelmeli (300=' .. tostring(sim.profile[300]) .. ' 301=' .. tostring(sim.profile[301]) .. ' 754=' .. tostring(sim.profile[754]) .. ' 212=' .. tostring(sim.profile[212]) .. ' 12=' .. tostring(sim.profile[12]) .. ')')
check(sim.profile[13] == START[13] and sim.profile[14] == START[14], 'S15: geçersiz istenen değerler uygulanmamalı')
check(d1 and d1.values and d1.values[300] == 7 and d1.values[212] == 0, 'S15: güncel değerler arayüze gitmeli')
check(isOpen() == true and sim.pause == false and sim.nuiFocus == true and GtaSet.busy == false and fk.visibleRead == false,
    'S15: uygulama sonunda GTA menüsü kapanmalı, LOE menüsü ve NUI odağı sürmeli, menü hiç görünmemeli')
sim.frames(1500)
check(isOpen() == true, 'S15: uygulamadan sonra LOE menüsü kapanmamalı (NUI odağı geri gelirken)')

-- D) hızlı basışların bir kısmı yutulursa yavaş aralıkla yeniden denenir
fk.flaky, fk.sessions, fk.valCount = true, 0, 0
sim.msgs = {}
sim.nui('gtaApply', { changes = { ['308'] = START[308] + 6, ['233'] = START[233] + 5 } })
sim.frames(200000)
local d2 = doneMsg()
check(d2 and d2.ok == true and sim.profile[308] == START[308] + 6 and sim.profile[233] == START[233] + 5, 'S15: yutulan basışlar yeniden denemeyle tamamlanmalı')
check(fk.sessions >= 2, 'S15: yeniden deneme yeni bir gizli oturum açmalı (oturum=' .. fk.sessions .. ')')
fk.flaky = false

-- E) hiç değişmeyen satır: 3 denemeden sonra başarısız bildirilir, diğerleri uygulanır
fk.sessions = 0
sim.msgs = {}
sim.nui('gtaApply', { changes = { ['761'] = 3, ['231'] = 9 } })
sim.frames(300000)
local d3 = doneMsg()
check(d3 and d3.ok == false and listHas(d3.failed, 761) and not listHas(d3.failed, 231) and sim.profile[231] == 9 and sim.profile[761] == START[761],
    'S15: uygulanamayan satır başarısız bildirilmeli, diğeri uygulanmalı')
check(fk.sessions == 3 and isOpen() == true and sim.pause == false and GtaSet.busy == false, 'S15: en çok 3 deneme; sonra her şey kapanmalı')

-- F) GTA menüsü hiç açılmazsa: değişiklik yok, hata bildirilir, kilit kalkar
fk.noOpen = true
sim.msgs = {}
sim.nui('gtaApply', { changes = { ['300'] = 2 } })
sim.frames(100000)
local d4 = doneMsg()
check(d4 and d4.ok == false and listHas(d4.failed, 300) and sim.profile[300] == 7 and GtaSet.busy == false and isOpen() == true, 'S15: menü açılamazsa hata bildirilmeli, menü sürmeli')
fk.noOpen = false

-- G) menü kapalıyken uygulama isteği reddedilir
sim.exported.Close(); sim.frames(700)
check(sim.nui('gtaApply', { changes = { ['300'] = 2 } }).ok == false and GtaSet.busy == false, 'S15: menü kapalıyken uygulama reddedilmeli')

-- H) Grafik sayfası: GTA ekranı doğrudan Grafik kategorisinde açılır (görünür), oyuncu kapatana kadar açık kalır
sim.pause = true; sim.frames(64)
check(isOpen() == true, 'S15: LOE menüsü yeniden açılmalı')
local actH = sim.calls.Activate or 0
fk.visibleOk = true
sim.nui('native', { target = 'graphics' })
sim.frames(6000)
check((sim.calls.Activate or 0) == actH + 1 and sim.pause == true and CATS[fk.cat].uid == '6', 'S15: Grafik ekranı doğrudan Grafik kategorisinde açılmalı (kategori ' .. CATS[fk.cat].uid .. ')')
sim.pause = false; sim.frames(3000)
fk.visibleOk = false
check(sim.nui('native', { target = 'zzz' }) == nil or true, 'S15: geçersiz hedef sorun çıkarmamalı')
-- I) Grafik ekranı kapanır; ana döngü menüyü yeniden kurar
sim.exported.Close(); sim.frames(700)

ActivateFrontendMenu, SetFrontendActive = realActivate, realSFA
SuppressFrontendRenderingThisFrame = nil
BeginScaleformMovieMethodOnFrontend, ScaleformMovieMethodAddParamInt, ScaleformMovieMethodAddParamBool, EndScaleformMovieMethod = nil, nil, nil, nil
EndScaleformMovieMethodReturnValue, IsScaleformMovieMethodReturnValueReady = nil, nil
GetScaleformMovieMethodReturnValueString, GetScaleformMovieMethodReturnValueInt = nil, nil
return R
'''

sim = LuaRuntime(unpack_returned_tuples=True)
sim.execute(SIM_PRELUDE)
import os  # noqa: E402

for rel in ('config.lua', 'shared/gtaset_data.lua', 'shared/schema.lua', 'client/prefs.lua', 'client/apply.lua', 'client/gtaset.lua', 'client/main.lua'):
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

# ------------------------------------------------------------------ 6) GEÇİCİ: scaleform araçları
print('[6] Scaleform araçları (_dev/gfx)')
import subprocess  # noqa: E402
check(not (ROOT / 'stream').exists() and not (ROOT / 'stream_enhanced').exists(),
      'Yamalı scaleform dosyası dağıtımda olmamalı (FiveM Enhanced base-asset geçersiz kılmayı yok sayıyor)')
vr = subprocess.run([sys.executable, str(ROOT / '_dev/gfx/verify_hook.py')], capture_output=True, text=True, encoding='utf-8')
check(vr.returncode == 0, 'AS2 kanca doğrulayıcısı: ' + (vr.stdout + vr.stderr).strip()[-300:])

print()
if failures:
    print(f'{len(failures)} HATA')
    sys.exit(1)
print('Tüm denetimler geçti.')
