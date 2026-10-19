local isOpen, uiReady, pendingOpen = false, false, nil
local openedAt, closedAt, lastNuiFocusAt = 0, 0, 0
local subActive = false   -- arayüz alt ekranda (ayarlar / sayfa / pencere): ESC menüyü kapatmaz, arayüz bir adım geri döner
local radarWasHidden, radarOffAtOpen, blurred = false, false, false
-- Bizim başlattığımız yerleşik GTA menüsü akışı: target = hangi menü, seen = gerçekten açıldı mı, returnAt = LOE menüsüne dönüş zamanı
local native = { target = nil, since = 0, seen = false, closingAt = nil, returnAt = nil }

-- ================================================================ YARDIMCILAR
local function menuItem(id)
    for _, item in ipairs(Config.Menu) do
        if item.id == id and item.enabled ~= false then return item end
    end
end

local function resourceStarted(name)
    return type(name) == 'string' and GetResourceState(name) == 'started'
end

--- M tuşuyla açılan büyük harita (loe_hud/client/bigmap.lua) kendi yerleşik menüsünü yönetir; ESC yakalama ona dokunmamalı.
local function bigMapOpen()
    if GetResourceState('loe_hud') ~= 'started' then return false end
    local ok, open = pcall(function() return exports.loe_hud:IsBigMapOpen() end)
    return ok and open == true
end

local function callExport(res, fnName, ...)
    local args = { ... }
    local ok, result = pcall(function()
        local ex = exports[res]
        return ex[fnName](ex, table.unpack(args))
    end)
    return ok, result
end

local function dbg(...)
    if Config.Debug then print('[loe_pause]', ...) end
end

local function killPause()
    if not IsPauseMenuActive() then return end
    pcall(SetFrontendActive, false)
    pcall(SetPauseMenuActive, false)
end

local function loggedIn()
    return not Config.Hijack.requireLogin or LocalPlayer.state.isLoggedIn == true
end

local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

-- ================================================================ NUI VERİSİ
local function keyToken(row)
    local token
    if row.control then
        token = GetControlInstructionalButton(0, row.control, true)
    elseif row.command then
        token = GetControlInstructionalButton(0, GetHashKey(row.command) | 0x80000000, true)
    end
    return token
end

local function buildKeys()
    local out = {}
    for _, c in ipairs(Schema.categories) do
        if c.id == 'keys' then
            for _, g in ipairs(c.groups) do
                for _, r in ipairs(g.rows) do
                    if r.type == 'key' or (r.type == 'action' and r.command) then
                        local k = r.control and ('c:' .. r.control) or ('m:' .. tostring(r.command))
                        local token = keyToken(r)
                        if type(token) == 'string' and token ~= '' then out[k] = token end
                    end
                end
            end
        end
    end
    return out
end

local function buildMenu()
    local out = {}
    for _, item in ipairs(Config.Menu) do
        if item.enabled ~= false then
            out[#out + 1] = {
                id = item.id,
                available = (not item.resource) or resourceStarted(item.resource),
                external = item.resource ~= nil,
                soon = item.soon == true or (item.resource ~= nil and not resourceStarted(item.resource)),   -- harici sistem yoksa "Yakında"
                new = item.new == true,
            }
        end
    end
    return out
end

--- Ana ekranın sağ kartları (seviye / battlepass): Config.Cards'taki export'lar yalnızca resource çalışıyorsa çağrılır;
--- dönen değerlerden yalnızca bilinen sayısal alanlar alınır.
local CARD_FIELDS = {
    level      = { 'level', 'xp', 'xpMax' },
    battlepass = { 'season', 'level', 'maxLevel' },
}

local function buildCards()
    local out = {}
    for id, fields in pairs(CARD_FIELDS) do
        local c = (Config.Cards or {})[id]
        if type(c) == 'table' and resourceStarted(c.resource) then
            local ok, res = callExport(c.resource, c.export)
            if ok and type(res) == 'table' then
                local card = {}
                for _, f in ipairs(fields) do
                    local n = tonumber(res[f])
                    if n then card[f] = n end
                end
                if next(card) then out[id] = card end
            end
        end
    end
    return out
end

--- Sağ üst bağlantılar: yalnızca https:// ile başlayan, boşluk/tırnak içermeyen adresler NUI'ye gider (en çok 4).
local function buildLinks()
    local out = {}
    for _, l in ipairs(Config.Links or {}) do
        if type(l) == 'table' and type(l.id) == 'string' and type(l.url) == 'string'
            and l.url:match("^https://[^%s\"'<>]+$") then
            out[#out + 1] = { id = l.id, label = tostring(l.label or l.id), url = l.url }
            if #out >= 4 then break end
        end
    end
    return out
end

--- Meslek / rütbe loe_jobcore'dan okunur (qbx_core'daki job alanı güncel tutulmaz). Aktif (mesaideki) meslek, yoksa birincil meslek.
--- @return boolean usable  jobcore çalışıyor mu (false → qbx_core'a düş)
--- @return string? label, string? grade
local function jobcoreJob()
    local res = (Config.JobSystem or {}).resource
    if not resourceStarted(res) then return false end
    local okR, ready = pcall(function() return exports[res]:IsReady() end)
    if okR and ready == false then return true end                      -- henüz senkron olmadı: yanlış meslek göstermektense boş bırak
    local ok, state = pcall(function() return exports[res]:GetPlayerState() end)
    if not ok or type(state) ~= 'table' then return false end
    local name = (state.onDuty and state.activeJob) or state.primaryJob
    local job = name and type(state.jobs) == 'table' and state.jobs[name]
    if type(job) == 'table' then
        return true, job.label or job.name, job.gradeLabel or job.gradeName
    end
    local okL, label = pcall(function() return exports[res]:GetJobLabel() end)      -- meslek yok: jobcore'un kendi "işsiz" etiketi
    return true, (okL and type(label) == 'string') and label or nil, nil
end

local function buildStats()
    local out = {}
    local ok, pd = pcall(function() return exports.qbx_core:GetPlayerData() end)
    if ok and type(pd) == 'table' then
        local ci = pd.charinfo or {}
        out.id = GetPlayerServerId(PlayerId())
        out.name = trim((ci.firstname or '') .. ' ' .. (ci.lastname or ''))
        out.cid = pd.citizenid
        local usable, label, grade = jobcoreJob()
        if usable then
            out.job, out.grade = label, grade
        elseif type(pd.job) == 'table' then
            out.job = pd.job.label or pd.job.name
            if type(pd.job.grade) == 'table' then out.grade = pd.job.grade.name end
        end
        if type(pd.money) == 'table' then
            out.cash, out.bank = pd.money.cash, pd.money.bank
        end
    end
    return out
end

--- Yerleşik GTA menüsüne ESC ile geçiş yalnızca config izin veriyorsa VE oyuncu seçtiyse geçerlidir.
local function nativeMenuWanted()
    return Config.Hijack.allowNativeMenu == true and Prefs.get('menu.native') == true
end

-- ================================================================ HIZLI EYLEMLER (kısayol komutları)
-- Görünürlük izni (yalnızca aces tanımlı satırlar için) sunucudan gelir; oyuncu çıkınca silinir.
local SHORTCUTS = {}                         -- 'cmd.<id>' -> Config.Shortcuts girdisi (beyaz liste)
for _, s in ipairs(Config.Shortcuts or {}) do
    if type(s.id) == 'string' and type(s.command) == 'string' and s.command:sub(1, 1) ~= '+' then
        SHORTCUTS['cmd.' .. s.id] = s
    end
end
local caps, lastCapsAsk = {}, 0

local function capsPayload()
    local out = {}
    for id in pairs(caps) do out[id] = true end
    return out
end

RegisterNetEvent('loe_pause:client:caps', function(list)
    if type(list) ~= 'table' then return end
    local fresh = {}
    for _, id in ipairs(list) do
        local s = type(id) == 'string' and SHORTCUTS['cmd.' .. id]
        if s and s.aces then fresh[id] = true end        -- yalnızca yetki gerektiren tanımlı satırlar
    end
    caps = fresh
    if isOpen then SendNUIMessage({ action = 'caps', caps = capsPayload() }) end
end)

AddEventHandler('QBCore:Client:OnPlayerUnload', function() caps = {} end)

local function refreshCaps()
    local now = GetGameTimer()
    if now - lastCapsAsk < 5000 then return end
    for _, s in pairs(SHORTCUTS) do
        if s.aces then
            lastCapsAsk = now
            TriggerServerEvent('loe_pause:server:caps')
            return
        end
    end
end

-- ================================================================ SAĞLIK (hastalıklar)
-- Hastalık sistemi loe_jobcreator'dadır (Sağlık sekmesi). Ona DOKUNMADAN, sunucunun bu oyuncuya zaten gönderdiği
-- 'healthState' olayını dinleyip son durumu saklarız; menü açılınca istatistik sayfasında gösteririz.
local HEALTH = Config.Health or {}
local health = { known = false, conditions = {} }
local lastHealthHello = 0

local function clip(v, n)
    if type(v) ~= 'string' or v == '' then return nil end
    return v:sub(1, n)
end

local function healthPayload()
    return { known = health.known, conditions = health.conditions }
end

RegisterNetEvent(HEALTH.event or 'loe_jobcreator:client:healthState', function(state)
    if type(state) ~= 'table' then return end
    local list = {}
    if state.enabled == true and type(state.conditions) == 'table' then
        for _, c in ipairs(state.conditions) do
            if type(c) == 'table' and clip(c.label, 60) then
                list[#list + 1] = {
                    id         = clip(c.id, 40),
                    label      = clip(c.label, 60),
                    symptom    = clip(c.symptom, 140),
                    bandaged   = c.bandaged == true,
                    suppressed = c.suppressed == true,
                }
                if #list >= 12 then break end
            end
        end
    end
    health.known, health.conditions = true, list
    if isOpen then SendNUIMessage({ action = 'health', health = healthPayload() }) end
end)

AddEventHandler('QBCore:Client:OnPlayerUnload', function()
    health.known, health.conditions = false, {}
end)

--- loe_pause sonradan başladıysa (restart) önbellek boştur: sistemin kendi "merhaba" olayıyla güncel durumu iste.
--- Bu olay loe_jobcreator tarafında tekrar çağrılabilir (ilk karşılamadan sonra yalnızca durumu yeniden gönderir).
local function refreshHealth()
    local res = HEALTH.resource or 'loe_jobcreator'
    if health.known or not resourceStarted(res) then return end
    local now = GetGameTimer()
    if now - lastHealthHello < 10000 then return end
    lastHealthHello = now
    TriggerServerEvent(HEALTH.helloEvent or 'loe_jobcreator:server:healthHello')
end

-- Home / Vehicles kartları (sunucu sayar): yalnızca menü açıksa arayüze iletilir; yalnızca sayısal alanlar geçer.
RegisterNetEvent('loe_pause:client:summary', function(s)
    if not isOpen or type(s) ~= 'table' then return end
    SendNUIMessage({ action = 'summary', homes = tonumber(s.homes), vehicles = tonumber(s.vehicles) })
end)

-- ================================================================ AÇ / KAPAT
local function restoreRadar()
    -- Oyuncu radarı kapattıysa kapalı kalsın; başka bir script açılıştan ÖNCE gizlemişse onun durumuna dön.
    if Prefs.get('disp.radar') == false then
        DisplayRadar(false)
    elseif radarWasHidden and not radarOffAtOpen then
        DisplayRadar(false)
    else
        DisplayRadar(true)
    end
end

local function close()
    if not isOpen then return end
    isOpen = false
    subActive = false
    closedAt = GetGameTimer()
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
    if blurred then TriggerScreenblurFadeOut(200.0); blurred = false end
    restoreRadar()
    Prefs.flush()
    killPause()
end

local function open(anim)
    if isOpen or GtaSet.busy then return end
    if not uiReady then pendingOpen = anim or 'open'; return end
    isOpen = true
    subActive = false
    openedAt = GetGameTimer()

    radarWasHidden = IsRadarHidden()
    radarOffAtOpen = Prefs.get('disp.radar') == false
    DisplayRadar(false)

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    if Config.Hijack.blurGame then TriggerScreenblurFadeIn(250.0); blurred = true end

    SendNUIMessage({
        action = 'open',
        anim   = anim or 'open',
        values = Prefs.snapshot(),
        keys   = buildKeys(),
        menu   = buildMenu(),
        stats  = buildStats(),
        server = Config.ServerName or 'LOE RP',
        cards  = buildCards(),
        health = healthPayload(),
        caps   = capsPayload(),
        gta    = GtaSet.values(),
        gtaLabels = GtaSet.labels(),
    })
    refreshHealth()
    refreshCaps()
    TriggerServerEvent('loe_pause:server:summary')
end

Apply.menuOpen = function() return isOpen end

local function canOpenManually()
    return not isOpen and not GtaSet.busy and not native.target and loggedIn() and not IsNuiFocused() and not IsPauseMenuActive()
        and not IsPlayerSwitchInProgress() and not IsCutsceneActive()
end

-- ================================================================ YERLEŞİK GTA MENÜSÜ / HARİTA
local function activateNative(target, noReturn)
    local n = Config.Native[target]
    if not n then return false end
    -- Akış başladı: ana döngü menü AÇILANA kadar (en çok 4 sn) ve açık kaldığı sürece ona dokunmaz.
    -- noReturn: harita tuşuyla (menüden değil) açıldı → kapanınca LOE menüsüne dönülmez.
    native.target, native.since, native.seen, native.closingAt, native.returnAt = target, GetGameTimer(), false, nil, nil
    native.noReturn = noReturn == true
    dbg('native start', target)
    ActivateFrontendMenu(GetHashKey(n.menu), n.pause == true, n.component or -1)
    if n.deeper ~= nil then
        -- ActivateFrontendMenu tek başına tüm duraklatma menüsünü açar; doğrudan sayfaya (ör. büyük harita)
        -- girmek için menü açılana kadar bekleyip bir seviye derine iniyoruz. (Çağıran bir thread içinde olmalı.)
        local deadline = GetGameTimer() + 1500
        while not IsPauseMenuActive() and GetGameTimer() < deadline do Wait(0) end
        Wait(n.deeperDelayMs or 100)
        PauseMenuceptionGoDeeper(n.deeper)
    end
    if n.category ~= nil then
        -- Ayarlar sayfası açılır; kategori listesinde istenen kategoriye (ör. Graphics) inilir (menü görünürken de çalışır)
        local deadline = GetGameTimer() + 2500
        while not IsPauseMenuActive() and GetGameTimer() < deadline do Wait(0) end
        Wait(700)
        GtaSet.focusCategory(n.category)
    end
    return true
end

--- Yerleşik menü akışı bitti. wasOpen = menü gerçekten açılmıştı → (tercih açıksa) LOE menüsüne dön.
local function finishNative(wasOpen)
    dbg('native finished, wasOpen =', wasOpen)
    local noReturn = native.noReturn
    native.target, native.seen, native.closingAt, native.noReturn = nil, false, nil, false
    closedAt = GetGameTimer()
    if wasOpen and not noReturn and Prefs.get('pref.mapReturn') then
        native.returnAt = closedAt + Config.Hijack.reopenCooldownMs + 60
    end
end

local function openNative(target)
    if not Config.Native[target] then return false end
    close()
    CreateThread(function()
        Wait(200)
        activateNative(target)
    end)
    return true
end

local function mapIsOpen(m)
    local ok, res = callExport(m.resource, m.isOpen)
    return ok and res == true
end

-- Harita kapanınca (ve tercih açıksa) menüyü animasyonla geri getir.
local function watchMapReturn(m)
    if not (m.isOpen and Prefs.get('pref.mapReturn')) then return end
    CreateThread(function()
        local deadline, opened = GetGameTimer() + 3000, false
        while GetGameTimer() < deadline do
            if mapIsOpen(m) then opened = true break end
            Wait(100)
        end
        if not opened then return end                       -- harita açılamadı (örn. uçuşta) → oyuna dön
        while mapIsOpen(m) do Wait(150) end
        Wait(450)                                           -- harita kapanış solması
        if canOpenManually() then open('return') end
    end)
end

local function openMap(fromKey)
    local m = Config.MapResource
    local wasOpen = isOpen
    close()
    if wasOpen then Wait(200) end
    if m and resourceStarted(m.resource) then
        local ok = callExport(m.resource, m.open)
        if ok then
            if not fromKey then watchMapReturn(m) end
            return
        end
    end
    activateNative('map', fromKey)
end

-- ================================================================ ANA DÖNGÜ: ESC / P YAKALAMA
local function canHijack()
    return Config.Hijack.enabled and loggedIn() and not IsPlayerSwitchInProgress()
        and not IsCutsceneActive() and not IsScreenFadedOut()
end

CreateThread(function()
    while true do
        Wait(0)
        if GtaSet.busy then
            -- client/gtaset.lua GTA ayar menüsünü GİZLİ açıp kapatıyor: ESC yakalama ona dokunmamalı; oyun girdisi yine kapalı kalır
            if isOpen then
                DisableAllControlActions(0)
                DisableAllControlActions(2)          -- gizli GTA menüsü (frontend) gerçek ESC/Enter tuşlarını işlemesin
                HideHudAndRadarThisFrame()
            end
            goto continue
        end

        local now = GetGameTimer()
        local paused = IsPauseMenuActive()

        if isOpen then
            DisableAllControlActions(0)
            HideHudAndRadarThisFrame()
            local sinceOpen = now - openedAt

            if paused then
                -- Açılışı tetikleyen ESC'nin yerleşik menüsü hâlâ sönüyor olabilir; sonrasında gelen = ESC ile kapat
                if sinceOpen > 350 and not subActive then close() else killPause() end
            elseif sinceOpen > 300 and not subActive and (IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 199)) then
                close()
            elseif sinceOpen > 400 and not IsNuiFocused() and now > (GtaSet.settleUntil or 0) then
                close()     -- ESC odağı bıraktırdı ya da başka bir resource odağı aldı
            end
        else
            if IsNuiFocused() then lastNuiFocusAt = now end

            if native.target then
                -- Bizim başlattığımız yerleşik menü (harita / oyun / ayarlar).
                if paused then
                    if not native.seen then dbg('native menu active') end
                    native.seen = true
                    -- Script ile açılan (ActivateFrontendMenu) menü ESC'de kendiliğinden KAPANMAZ; yalnızca bir seviye geri gider
                    -- ve harita açık kalır. Bu yüzden ESC / P / Geri'yi biz yakalayıp menüyü kapatırız.
                    if not native.closingAt and now - native.since > 500
                        and (IsControlJustPressed(0, 200) or IsControlJustPressed(0, 199) or IsControlJustPressed(2, 202)) then
                        native.closingAt = now
                        dbg('ESC in native menu -> closing')
                    end
                    if native.closingAt then killPause() end
                end
                if native.closingAt then
                    -- Kapanışta sızan ESC yerleşik menüyü yeniden açabilir: pencere boyunca her karede söndür.
                    if now - native.closingAt > 600 and not paused then finishNative(true) end
                elseif not paused and (native.seen or now - native.since > 4000) then
                    finishNative(native.seen)         -- menü kendi kapandı (ya da hiç açılmadı)
                end
            elseif paused then
                if nativeMenuWanted() or not canHijack() or bigMapOpen() then
                    -- yerleşik menü serbest (oyuncu tercihi / giriş yapılmamış / ara sahne)
                else
                    killPause()
                    local h = Config.Hijack
                    if not native.returnAt and now - closedAt >= h.reopenCooldownMs and now - lastNuiFocusAt >= h.nuiGraceMs then
                        open('open')
                    end
                end
            end

            if native.returnAt and now >= native.returnAt then
                if canOpenManually() then
                    native.returnAt = nil
                    open('return')
                elseif now - native.returnAt > 1500 then
                    native.returnAt = nil               -- dönüş mümkün olmadı (başka bir arayüz açık): oyunda kal
                end
            end
        end
        ::continue::
    end
end)

-- ================================================================ NUI CALLBACK'LERİ
RegisterNUICallback('ready', function(_, cb)
    uiReady = true
    SendNUIMessage({
        action = 'init',
        schema = Schema.categories,
        bg     = Config.Background,
        links  = buildLinks(),
        gta    = (Config.Features or {}).allGtaSettings ~= false,
    })
    cb({ ok = true })
    if pendingOpen then
        local anim = pendingOpen
        pendingOpen = nil
        open(anim)
    end
end)

RegisterNUICallback('close', function(_, cb)
    if GtaSet.busy then return cb({ ok = false }) end      -- GTA ayarları uygulanırken menü kapanmaz
    cb({ ok = true })
    close()
end)

-- GTA ayarlarını uygula: { changes = { [pid] = hedef } }. Değerler client/gtaset.lua'da yeniden doğrulanır (pid tablosu, aralık).
-- Uygulama GTA ayar menüsü gizli açılarak yapılır (birkaç saniye); bitince arayüze 'gtaDone' gider.
RegisterNUICallback('gtaApply', function(d, cb)
    if not isOpen or GtaSet.busy or type(d) ~= 'table' then return cb({ ok = false }) end
    if (Config.Features or {}).gtaSettings == false then return cb({ ok = false }) end
    local changes = GtaSet.clean(d.changes)
    if not changes then return cb({ ok = false, empty = true }) end
    cb({ ok = true })
    GtaSet.apply(changes, function(res)
        if isOpen then
            SetNuiFocus(true, true)
            SetNuiFocusKeepInput(false)
        end
        GtaSet.settleUntil = GetGameTimer() + 1500
        SendNUIMessage({ action = 'gtaDone', ok = res.ok == true, failed = res.failed, values = res.values })
    end)
end)

RegisterNUICallback('setting', function(d, cb)
    if not isOpen or type(d) ~= 'table' then return cb({ ok = false }) end
    if d.id == 'menu.native' and Config.Hijack.allowNativeMenu ~= true then return cb({ ok = false, value = false }) end
    local ok, value = Prefs.set(d.id, d.value)
    if not ok then return cb({ ok = false, value = type(d.id) == 'string' and Prefs.display(d.id) or nil }) end
    Apply.run(d.id)
    cb({ ok = true, value = value })
end)

RegisterNUICallback('action', function(d, cb)
    local id = type(d) == 'table' and d.id
    if not isOpen or type(id) ~= 'string' or not Schema.actions[id] then return cb({ ok = false }) end
    local handler = Apply.actions[id]
    if not handler then return cb({ ok = false }) end
    local res = handler() or { ok = false }
    cb(res)
    if res.close then close() end
end)

RegisterNUICallback('native', function(d, cb)
    local target = type(d) == 'table' and d.target
    if not isOpen or type(target) ~= 'string' or not Config.Native[target] then return cb({ ok = false }) end
    cb({ ok = true })
    openNative(target)
end)

RegisterNUICallback('menu', function(d, cb)
    local id = type(d) == 'table' and d.id
    local item = type(id) == 'string' and menuItem(id)
    if not isOpen or not item then return cb({ ok = false }) end

    if id == 'map' then
        cb({ ok = true })
        CreateThread(openMap)
    elseif id == 'stats' or id == 'battlepass' or id == 'shop' or id == 'inventory' then
        if item.resource and resourceStarted(item.resource) and item.export then
            cb({ ok = true })
            close()
            CreateThread(function()
                Wait(150)
                callExport(item.resource, item.export)
            end)
        else
            -- harici sistem yok: istatistik için yerleşik karakter özeti, diğerleri için "Yakında" sayfası
            cb({ ok = true, page = (id == 'stats') and 'stats' or 'soon' })
        end
    else
        cb({ ok = false })
    end
end)

-- Arayüz alt ekrana girdi/çıktı (ayarlar, sayfa, onay penceresi). Yalnızca boolean kabul edilir.
RegisterNUICallback('sub', function(d, cb)
    cb({ ok = true })
    if not isOpen or type(d) ~= 'table' or type(d.on) ~= 'boolean' then return end
    subActive = d.on
end)

-- "Restore defaults": bir ayar sayfasındaki ayarları varsayılana döndürür. Yalnızca şemadaki (toggle/select/slider) id'ler kabul edilir.
RegisterNUICallback('restore', function(d, cb)
    if not isOpen or type(d) ~= 'table' or type(d.ids) ~= 'table' then return cb({ ok = false }) end
    local ids = {}
    for _, id in ipairs(d.ids) do
        if type(id) == 'string' and Schema.rows[id] and #ids < 60 then ids[#ids + 1] = id end
    end
    if #ids == 0 then return cb({ ok = false }) end
    Prefs.reset(ids)
    for _, id in ipairs(ids) do Apply.run(id) end
    cb({ ok = true, values = Prefs.snapshot() })
end)

RegisterNUICallback('quit', function(d, cb)
    cb({ ok = true })
    local mode = type(d) == 'table' and d.mode
    -- Yalnızca "sunucudan ayrıl": bağlantıyı keser ve FiveM ana menüsüne döner. Oyunu tamamen kapatan 'quit' bilerek yok.
    if not isOpen or mode ~= 'disconnect' then return end
    close()
    CreateThread(function()
        Wait(150)
        -- 1) Sunucu bu oyuncuyu düşürür (server/main.lua, DropPlayer) → FiveM ana menüsüne "Sunucudan ayrıldın" mesajıyla düşer.
        --    (ExecuteCommand('disconnect') script'ten çalışmıyor; bu yüzden kullanılmaz.)
        dbg('leave requested')
        TriggerServerEvent('loe_pause:server:leave')
        -- 2) Yedek: birkaç saniye sonra hâlâ sunucudaysak (sunucu betiği yüklenmemiş vb.) oyunu kapatıp FiveM'i yeniden açar.
        --    Düşürme başarılı olursa resource durur ve bu satıra hiç gelinmez.
        Wait(3000)
        dbg('leave fallback: RestartGame')
        RestartGame()
    end)
end)

-- Hızlı Eylemler: menüyü kapatır, kısa bir beklemeden sonra kısayolun komutunu çalıştırır. Yalnızca Config.Shortcuts'taki
-- komutlar çalışır (NUI'den komut metni ALINMAZ; yalnızca şemadaki eylem kimliği gelir).
for actionId, s in pairs(SHORTCUTS) do
    Apply.actions[actionId] = function()
        if s.aces and not caps[s.id] then return { ok = false } end
        CreateThread(function()
            Wait(300)      -- menü kapanışı + kısayolun kendi debounce süresi (örn. imlec 250 ms)
            dbg('shortcut', s.command)
            ExecuteCommand(s.command)
        end)
        return { ok = true, close = true }
    end
end

Apply.actions['menu.opennative'] = function()
    if Config.Hijack.allowNativeMenu ~= true then return { ok = false } end
    openNative('game')
    return { ok = true }
end

-- ================================================================ KOMUT / EXPORT
RegisterCommand(Config.Command, function()
    if isOpen then
        close()
    elseif canOpenManually() then
        open('open')
    end
end, false)
RegisterKeyMapping(Config.Command, 'LOE pause menu', 'keyboard', Config.OpenKey or '')

-- Büyük harita tuşu (varsayılan M): menü açılmadan doğrudan büyük harita. Harita açıkken aynı tuş (ESC gibi) kapatır.
-- Harita menüden değil tuştan açıldığı için kapanınca LOE menüsüne dönülmez.
RegisterCommand(Config.MapCommand or 'loe_bigmap', function()
    if native.target == 'map' then
        if not native.closingAt and GetGameTimer() - native.since > 500 then
            native.closingAt = GetGameTimer()
            dbg('map key -> closing')
        end
        return
    end
    if canOpenManually() and not IsScreenFadedOut() then
        CreateThread(function() openMap(true) end)
    end
end, false)
if (Config.MapKey or '') ~= '' then
    RegisterKeyMapping(Config.MapCommand or 'loe_bigmap', 'Big map', 'keyboard', Config.MapKey)
end

exports('Open',   function() if canOpenManually() then open('open') end end)
exports('Close',  function() close() end)
exports('IsOpen', function() return isOpen end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    if blurred then TriggerScreenblurFadeOut(0.0) end
    restoreRadar()
    Prefs.flush()
end)
