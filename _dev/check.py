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
                check(f"Apply.actions['{r['id']}']" in apply_src + main_src, f"{r['id']}: eylem işleyicisi yok")

(ROOT / '_dev' / 'schema.json').write_text(json.dumps(cats, ensure_ascii=False, indent=1), encoding='utf-8')
rows = sum(len(g['rows']) for c in cats for g in c['groups'])
print(f'  {len(cats)} kategori, {rows} satır, {len(seen)} kimlikli ayar → _dev/schema.json')

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

pl.execute("Prefs.values = {}; Prefs.set('pref.accent', 'red'); Prefs.set('pref.dark', false)")
pl.execute("Prefs.reset({'pref.accent', 'pref.dark'})")
check(pl.eval("Prefs.get('pref.accent')") == 'magenta' and pl.eval("Prefs.get('pref.dark')") is True, 'reset varsayılana dönmeli')
check(pl.eval("Prefs.get('pref.lang')") == 'tr', "varsayılan dil 'tr' olmalı")
check(pl.eval("Prefs.get('pref.dark')") is True, 'varsayılan koyu tema açık olmalı')

# sunucu varsayılan geçersiz kılma
pl.execute("Config.Defaults['pref.accent'] = 'blue'")
check(pl.eval("Prefs.default('pref.accent')") == 'blue', 'Config.Defaults uygulanmalı')
pl.execute("Config.Defaults['pref.accent'] = 'invalid'")
check(pl.eval("Prefs.default('pref.accent')") == 'magenta', 'geçersiz Config.Defaults yok sayılmalı')

# ------------------------------------------------------------------ 4) ana döngü simülasyonu
print('[4] ESC / harita / sızan ESC akışı (simülasyon)')

SIM_PRELUDE = r'''
sim = { now = 5000, pause = false, nuiFocus = false, msgs = {}, calls = {}, handlers = {}, exported = {}, threads = {}, events = {}, escFrame = false }
local S = sim
setmetatable(_G, { __index = function(_, k) return function() end end })   -- bilinmeyen native → no-op

LocalPlayer = { state = { isLoggedIn = true } }
json = { encode = function() return '{}' end, decode = function() return {} end }
function GetResourceKvpString() return nil end
function SetResourceKvp() end
function GetCurrentResourceName() return 'loe_pause' end
function GetResourceState(r) return 'missing' end
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
function IsControlJustPressed(g, c) return S.escFrame and g == 0 and c == 200 end
function ActivateFrontendMenu()
    S.calls.Activate = (S.calls.Activate or 0) + 1
    S.events[#S.events + 1] = { at = S.now + 120, fn = function() S.pause = true end }   -- oyun menüyü biraz sonra açar
end
function PauseMenuceptionGoDeeper(p) S.calls.GoDeeper = p end
function AddEventHandler() end
function RegisterNetEvent() end
function RegisterCommand() end
function RegisterKeyMapping() end
function TriggerServerEvent() end
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
end
function sim.frames(ms) for _ = 1, math.ceil(ms / 16) do sim.step(16) end end
function sim.lastOpen() local l; for _, m in ipairs(S.msgs) do if m.action == 'open' then l = m end end return l end
function sim.openCount() local n = 0; for _, m in ipairs(S.msgs) do if m.action == 'open' then n = n + 1 end end return n end
'''

SIM_SCENARIO = r'''
local R = {}
local function check(c, msg) if not c then R[#R + 1] = msg end end
local isOpen = function() return sim.exported.IsOpen() end

sim.frames(100)
sim.nui('ready')
check(isOpen() == false, 'başlangıçta menü kapalı olmalı')

-- S1: ESC → yerleşik menü söndürülür, LOE menüsü açılır
sim.pause = true; sim.frames(64)
check(isOpen() == true, 'S1: ESC LOE menüsünü açmalı')
check(sim.pause == false, 'S1: yerleşik pause menü kapatılmalı')

-- S2: Harita → büyük harita açılır ve açık KALIR; ESC ile kapanınca sızan yeniden açılış söndürülür, LOE menüsü döner
local r = sim.nui('menu', { id = 'map' })
check(r and r.ok, 'S2: menu callback ok dönmeli')
sim.frames(120)
check(isOpen() == false, 'S2: harita seçilince LOE menüsü kapanmalı')
sim.frames(700)
check(sim.calls.Activate == 1, 'S2: ActivateFrontendMenu bir kez çağrılmalı')
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
return R
'''

sim = LuaRuntime(unpack_returned_tuples=True)
sim.execute(SIM_PRELUDE)
import os  # noqa: E402

for rel in ('config.lua', 'shared/schema.lua', 'client/prefs.lua', 'client/apply.lua', 'client/main.lua'):
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

print()
if failures:
    print(f'{len(failures)} HATA')
    sys.exit(1)
print('Tüm denetimler geçti.')
