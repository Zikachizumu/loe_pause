-- GTA'nın kendi ayarlarını (ses seviyeleri, fare/oyun kolu hassasiyeti, kamera, ekran...) bu menüden OKUR ve YAZAR.
--
-- OKUMA: her satırın değeri bir "profil ayarı"dır → GetProfileSetting(pid). Menü kapalıyken anlıktır.
-- YAZMA: FiveM bu ayarlar için native sunmaz. Bu yüzden GTA'nın kendi ayar menüsü GİZLİ açılır
-- (SuppressFrontendRenderingThisFrame) ve menünün iç çağrıları (SET_INPUT_EVENT, MENU_SHIFT_DEPTH) ile sanki oyuncu
-- sağ/sol tuşa basmış gibi satırlar adım adım değiştirilir; menü kapanınca GTA değeri kaydeder, sonra profil okunup doğrulanır.
-- Bulgular ve zamanlama: _dev/gtaset/ (ölçüm sonuçları), shared/gtaset_data.lua (satır tablosu).
--
-- GTA menüsü her işlemden sonra kısa süre meşgul kalır ve o sırada gelen çağrıyı YUTAR: gezinme çağrıları ≥ 60 ms arayla,
-- satıra giriş/çıkış ve değer adımı bir önceki işlemden ≥ 250 ms sonra, seviye değişiminden sonra 400 ms beklenir.

GtaSet = { busy = false }

local DATA = GtaSetData or { cats = {} }
local SETTINGS_MENU = (Config.Native and Config.Native.settings and Config.Native.settings.menu) or 'FE_MENU_VERSION_LANDING_MENU'

-- com.rockstargames.ui.game.GamePadConstants: aşağı gezinme / sol / sağ
local DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT = 9, 10, 11
local STEP_GAP, SLOW_GAP = 50, 250          -- değer adımları arası (ölçüldü: 50 ms güvenli); doğrulama başarısızsa yavaş
local NAV_GAP, ACT_GAP, DEPTH_SETTLE = 60, 250, 400
local MAX_CHANGES = 80

-- ---------------------------------------------------------------- satır dizini
local byPid, rowOrder = {}, {}
for _, c in ipairs(DATA.cats) do
    for i, r in ipairs(c.rows) do
        if r.pid and (r.kind == 'slider' or r.kind == 'list') then
            byPid[r.pid] = { cat = c, row = r, order = i }
            rowOrder[#rowOrder + 1] = r.pid
        end
    end
end

local function span(info)           -- profil değerinin üst sınırı (alt sınır 0): kaydırıcı max, liste = seçenek sayısı - 1
    if info.row.kind == 'slider' then return info.row.max or 0 end
    return #(info.row.labels or {}) - 1
end

function GtaSet.values()
    local out = {}
    for _, pid in ipairs(rowOrder) do
        local v = GetProfileSetting(pid)
        if type(v) == 'number' then out[pid] = v end
    end
    return out
end

--- NUI'den gelen değişiklikleri doğrular: yalnızca tablodaki pid'ler, tam sayı, aralık içinde, şimdiki değerden farklı olanlar.
--- Dönüş: { [pid] = hedef } ya da nil
function GtaSet.clean(raw)
    if type(raw) ~= 'table' then return nil end
    local out, n = {}, 0
    for k, v in pairs(raw) do
        local pid = tonumber(k)
        local info = pid and byPid[pid]
        if info and type(v) == 'number' and v == math.floor(v) and v >= 0 and v <= span(info) then
            if v ~= GetProfileSetting(pid) then
                out[pid] = v
                n = n + 1
                if n > MAX_CHANGES then return nil end
            end
        end
    end
    if n == 0 then return nil end
    return out
end

-- ---------------------------------------------------------------- etiketler (GTA'nın kendi metinleri, oyuncunun GTA diliyle)
local labelCache
local function labelText(id)
    local ok, s = pcall(GetLabelText, id)
    if not ok or type(s) ~= 'string' or s == '' or s == 'NULL' then return nil end
    s = s:gsub('~[^~]*~', ''):gsub('<[^>]*>', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return s ~= '' and s or nil
end

function GtaSet.labels()
    if labelCache then return labelCache end
    local out = {}
    for _, c in ipairs(DATA.cats) do
        for _, r in ipairs(c.rows) do
            local t = labelText(r.text)
            if t then out[r.text] = t end
            for _, l in ipairs(r.labels or {}) do
                local o = labelText(l)
                if o then out[l] = o end
            end
        end
    end
    labelCache = out
    return out
end

-- ---------------------------------------------------------------- scaleform yardımcıları (oyun "TIMELINE." önekini kendisi ekler)
local function sfRead(path)
    local okB, started = pcall(BeginScaleformMovieMethodOnFrontend, path)
    if not okB or not started then return nil, 'begin' end
    local okE, h = pcall(EndScaleformMovieMethodReturnValue)
    if not okE or type(h) ~= 'number' then return nil, 'end' end
    local t = GetGameTimer()
    while GetGameTimer() - t < 250 do
        local okR, r = pcall(IsScaleformMovieMethodReturnValueReady, h)
        if okR and r then
            local o1, str = pcall(GetScaleformMovieMethodReturnValueString, h)
            local o2, int = pcall(GetScaleformMovieMethodReturnValueInt, h)
            if o1 and str ~= nil and str ~= '' then return str, 'ok' end
            return o2 and int or nil, 'ok'
        end
        Wait(0)
    end
    return nil, 'timeout'
end

local function uid() return tostring(sfRead('menuUniqueID.toString')) end
local function level() return tostring(sfRead('menuLevel.toString')) end

local function call(path, ...)
    local okB, started = pcall(BeginScaleformMovieMethodOnFrontend, path)
    if not (okB and started) then return false end
    for _, a in ipairs({ ... }) do
        if type(a) == 'boolean' then pcall(ScaleformMovieMethodAddParamBool, a) else pcall(ScaleformMovieMethodAddParamInt, a) end
    end
    pcall(EndScaleformMovieMethod)
    return true
end

local function sleep(ms)
    local s = GetGameTimer()
    repeat Wait(0) until GetGameTimer() - s >= ms
end

local lastAct = 0
local function pace(ms)
    local w = lastAct + ms - GetGameTimer()
    if w > 0 then sleep(w) end
end

-- Gezinme (aşağı): menuUniqueID değişene kadar bekle; yutulursa en çok 3 deneme
local function nav()
    local before = uid()
    for try = 1, 3 do
        pace(try == 1 and NAV_GAP or ACT_GAP)
        local t = GetGameTimer()
        call('SET_INPUT_EVENT', DPAD_DOWN)
        lastAct = GetGameTimer()
        local u
        repeat
            Wait(0)
            u = uid()
        until u ~= before or GetGameTimer() - t > 400
        if u ~= before then return true end
    end
    return false
end

-- Satırlara gir (+1) / çık (-1); seviye değişmezse en çok 3 deneme
local function depth(dir)
    local want = dir > 0 and '2' or '1'
    for _ = 1, 3 do
        pace(ACT_GAP)
        call('MENU_SHIFT_DEPTH', dir, false, false)       -- (yön, DontFallOff, SkipChecks): ölçümlerde çalışan çağrı
        lastAct = GetGameTimer()
        local t = GetGameTimer()
        repeat Wait(0) until level() == want or GetGameTimer() - t > 600
        if level() == want then
            sleep(DEPTH_SETTLE)
            lastAct = GetGameTimer()
            return true
        end
    end
    return false
end

local function stepN(dir, n, gap)
    pace(ACT_GAP)
    for _ = 1, n do
        call('SET_INPUT_EVENT', dir)
        sleep(gap)
    end
    lastAct = GetGameTimer()
end

-- ---------------------------------------------------------------- gizli oturum
local hidden = false
local function hide(on)
    if on and not hidden then
        hidden = true
        CreateThread(function()
            while hidden do
                SuppressFrontendRenderingThisFrame()
                Wait(0)
            end
        end)
    elseif not on then
        hidden = false
    end
end

local function openHidden()
    hide(true)
    ActivateFrontendMenu(GetHashKey(SETTINGS_MENU), true, -1)
    local deadline = GetGameTimer() + 6000
    while GetGameTimer() < deadline do
        if IsPauseMenuActive() then
            local _, st = sfRead('menuUniqueID.toString')
            if st == 'ok' then
                sleep(300)
                lastAct = GetGameTimer()
                return true
            end
        end
        Wait(0)
    end
    return false
end

-- Önce kapat, SONRA gizlemeyi bırak (menü bir kare bile görünmesin)
local function shut()
    pace(ACT_GAP)
    for _ = 1, 40 do
        if not IsPauseMenuActive() then break end
        pcall(SetFrontendActive, false)
        Wait(50)
    end
    hide(false)
end

local function gotoCat(cat)
    if level() ~= '1' then return false end
    for _ = 0, 14 do
        if uid() == cat then return true end
        if not nav() then return false end
    end
    return uid() == cat
end

local function gotoRow(row)
    if level() ~= '2' then return false end
    for _ = 0, 45 do
        if uid() == row then return true end
        if not nav() then return false end
    end
    return uid() == row
end

-- Menü kapanınca profil güncellenir: en az 600 ms bekle, iki ölçüm aynı olunca (en çok 2 sn) kabul et
local function settle()
    local t, prev = GetGameTimer(), nil
    while true do
        sleep(300)
        local cur = GtaSet.values()
        local same = prev ~= nil
        if same then for pid, v in pairs(cur) do if prev[pid] ~= v then same = false break end end end
        if same and GetGameTimer() - t >= 600 then return cur end
        if GetGameTimer() - t > 2000 then return cur end
        prev = cur
    end
end

-- ---------------------------------------------------------------- plan: hangi satırda hangi yöne kaç adım
local function stepsFor(info, cur, target)
    local row = info.row
    if row.kind == 'slider' then
        local diff = target - cur
        if diff == 0 then return nil end
        local up = row.inv and DPAD_LEFT or DPAD_RIGHT      -- profil değerini ARTIRAN yön (ters kaydırıcıda sol)
        local down = row.inv and DPAD_RIGHT or DPAD_LEFT
        return diff > 0 and up or down, math.abs(diff)
    end
    -- liste: seçenekler iki yönde döner → kısa yol
    local count = #row.labels
    local fwd, back = (target - cur) % count, (cur - target) % count
    if fwd == 0 then return nil end
    if fwd <= back then return DPAD_RIGHT, fwd end
    return DPAD_LEFT, back
end

-- changes: { [pid] = hedef } → kategori sırasına göre planlar (oturumda her kategoriye bir kez girilir)
local function buildPlan(changes, cur)
    local perCat = {}
    for pid, target in pairs(changes) do
        local info = byPid[pid]
        local dir, n = stepsFor(info, cur[pid] or 0, target)
        if dir then
            local cid = info.cat.uid
            perCat[cid] = perCat[cid] or { cat = info.cat, steps = {} }
            table.insert(perCat[cid].steps, { row = info.row.uid, order = info.order, dir = dir, n = n, pid = pid })
        end
    end
    local plan = {}
    for _, c in ipairs(DATA.cats) do
        local p = perCat[c.uid]
        if p then
            table.sort(p.steps, function(a, b) return a.order < b.order end)
            plan[#plan + 1] = p
        end
    end
    return plan
end

local function session(plan, gap)
    local ok = openHidden()
    if ok then
        for _, p in ipairs(plan) do
            if not (gotoCat(tostring(p.cat.uid)) and depth(1)) then ok = false break end
            for _, s in ipairs(p.steps) do
                if gotoRow(tostring(s.row)) then stepN(s.dir, s.n, gap) else ok = false end
            end
            if not depth(-1) then ok = false break end       -- bir sonraki kategori için kategori listesine dön
        end
    end
    shut()
    return ok
end

--- GÖRÜNÜR (oyuncunun açtığı) GTA ayar menüsünde kategori listesinde `cat` kategorisine iner (ör. Graphics = 6).
--- Bir thread içinde çağrılmalı.
function GtaSet.focusCategory(cat)
    for _ = 1, 10 do
        local _, st = sfRead('menuUniqueID.toString')
        if st == 'ok' then break end
        Wait(200)
    end
    lastAct = GetGameTimer()
    return gotoCat(tostring(cat))
end

-- ---------------------------------------------------------------- uygula
-- Dönüş (callback): { ok = bool, failed = { pid... }, values = { [pid] = değer } }
local function run(changes)
    local cur = GtaSet.values()
    local pending = changes
    for attempt = 1, 3 do
        local plan = buildPlan(pending, cur)
        if #plan == 0 then break end
        session(plan, attempt == 1 and STEP_GAP or SLOW_GAP)
        cur = settle()
        local left = {}
        for pid, target in pairs(pending) do
            if cur[pid] ~= target then left[pid] = target end
        end
        pending = left
        if next(pending) == nil then break end
    end
    local failed = {}
    for pid in pairs(pending) do failed[#failed + 1] = pid end
    table.sort(failed)
    return { ok = #failed == 0, failed = failed, values = cur }
end

--- Asenkron: GTA ayarlarını uygular. Dönüş false → zaten meşgul. cb(sonuç) uygulama bitince çağrılır.
function GtaSet.apply(changes, cb)
    if GtaSet.busy or type(changes) ~= 'table' then return false end
    GtaSet.busy = true
    CreateThread(function()
        local ok, res = pcall(run, changes)
        hide(false)
        if IsPauseMenuActive() then pcall(SetFrontendActive, false) end
        GtaSet.busy = false
        GtaSet.settleUntil = GetGameTimer() + 1500        -- NUI odağı geri gelirken ana döngü menüyü kapatmasın
        if not ok then res = { ok = false, failed = {}, values = GtaSet.values(), error = tostring(res) } end
        if cb then cb(res) end
    end)
    return true
end
