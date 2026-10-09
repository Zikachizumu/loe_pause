local isOpen, uiReady, pendingOpen = false, false, nil
local openedAt, closedAt, lastNuiFocusAt = 0, 0, 0
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
                    if r.type == 'key' then
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
            }
        end
    end
    return out
end

local function buildStats()
    local out = {}
    local ok, pd = pcall(function() return exports.qbx_core:GetPlayerData() end)
    if ok and type(pd) == 'table' then
        local ci = pd.charinfo or {}
        out.name = trim((ci.firstname or '') .. ' ' .. (ci.lastname or ''))
        out.cid = pd.citizenid
        if type(pd.job) == 'table' then
            out.job = pd.job.label or pd.job.name
            if type(pd.job.grade) == 'table' then out.grade = pd.job.grade.name end
        end
        if type(pd.money) == 'table' then
            out.cash, out.bank = pd.money.cash, pd.money.bank
        end
    end
    return out
end

--- GTA'nın GÜNCEL ayar değerleri (yalnızca OKUNUR; GTA bu ayarların yazılmasına script'ten izin vermez).
--- Anahtarlar schema.lua'daki native satırların `read` alanıyla eşleşir. Okunamayan anahtar hiç gönderilmez → satırda değer görünmez.
local function buildNativeValues()
    local out = {}
    local function read(key, fn)
        local ok, v = pcall(fn)
        if ok and v ~= nil then out[key] = v end
    end
    read('subtitles', function() return IsSubtitlePreferenceSwitchedOn() == true end)
    read('metric', function() return ShouldUseMetricMeasurements() == true end)
    read('safezone', function()
        local z = GetSafeZoneSize()
        if type(z) == 'number' and z > 0 and z <= 1.001 then return math.floor(z * 100 + 0.5) end
    end)
    read('resolution', function()
        local w, h = GetActualScreenResolution()
        if type(w) == 'number' and type(h) == 'number' and w > 0 and h > 0 then
            return ('%dx%d'):format(math.floor(w), math.floor(h))
        end
    end)
    read('language', function()
        local l = GetCurrentLanguage()
        if type(l) == 'number' and l >= 0 and l <= 12 then return math.floor(l) end
    end)
    return out
end

--- Yerleşik GTA menüsüne ESC ile geçiş yalnızca config izin veriyorsa VE oyuncu seçtiyse geçerlidir.
local function nativeMenuWanted()
    return Config.Hijack.allowNativeMenu == true and Prefs.get('menu.native') == true
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
    if isOpen then return end
    if not uiReady then pendingOpen = anim or 'open'; return end
    isOpen = true
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
        health = healthPayload(),
        native = buildNativeValues(),
    })
    refreshHealth()
end

Apply.menuOpen = function() return isOpen end

local function canOpenManually()
    return not isOpen and not native.target and loggedIn() and not IsNuiFocused() and not IsPauseMenuActive()
        and not IsPlayerSwitchInProgress() and not IsCutsceneActive()
end

-- ================================================================ YERLEŞİK GTA MENÜSÜ / HARİTA
local function activateNative(target)
    local n = Config.Native[target]
    if not n then return false end
    -- Akış başladı: ana döngü menü AÇILANA kadar (en çok 4 sn) ve açık kaldığı sürece ona dokunmaz.
    native.target, native.since, native.seen, native.closingAt, native.returnAt = target, GetGameTimer(), false, nil, nil
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
    return true
end

--- Yerleşik menü akışı bitti. wasOpen = menü gerçekten açılmıştı → (tercih açıksa) LOE menüsüne dön.
local function finishNative(wasOpen)
    dbg('native finished, wasOpen =', wasOpen)
    native.target, native.seen, native.closingAt = nil, false, nil
    closedAt = GetGameTimer()
    if wasOpen and Prefs.get('pref.mapReturn') then
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

local function openMap()
    local m = Config.MapResource
    close()
    Wait(200)
    if m and resourceStarted(m.resource) then
        local ok = callExport(m.resource, m.open)
        if ok then watchMapReturn(m) return end
    end
    activateNative('map')
end

-- ================================================================ ANA DÖNGÜ: ESC / P YAKALAMA
local function canHijack()
    return Config.Hijack.enabled and loggedIn() and not IsPlayerSwitchInProgress()
        and not IsCutsceneActive() and not IsScreenFadedOut()
end

CreateThread(function()
    while true do
        Wait(0)
        local now = GetGameTimer()
        local paused = IsPauseMenuActive()

        if isOpen then
            DisableAllControlActions(0)
            HideHudAndRadarThisFrame()
            local sinceOpen = now - openedAt

            if paused then
                -- Açılışı tetikleyen ESC'nin yerleşik menüsü hâlâ sönüyor olabilir; sonrasında gelen = ESC ile kapat
                if sinceOpen > 350 then close() else killPause() end
            elseif sinceOpen > 300 and (IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 199)) then
                close()
            elseif sinceOpen > 400 and not IsNuiFocused() then
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
                if nativeMenuWanted() or not canHijack() then
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
    end
end)

-- ================================================================ NUI CALLBACK'LERİ
RegisterNUICallback('ready', function(_, cb)
    uiReady = true
    SendNUIMessage({
        action = 'init',
        schema = Schema.categories,
        brand  = Config.Brand,
        bg     = Config.Background,
    })
    cb({ ok = true })
    if pendingOpen then
        local anim = pendingOpen
        pendingOpen = nil
        open(anim)
    end
end)

RegisterNUICallback('close', function(_, cb)
    cb({ ok = true })
    close()
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
    elseif id == 'settings' then
        cb({ ok = true, page = 'settings' })
    elseif id == 'stats' or id == 'battlepass' or id == 'shop' then
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

RegisterNUICallback('quit', function(d, cb)
    cb({ ok = true })
    local mode = type(d) == 'table' and d.mode
    if not isOpen or (mode ~= 'disconnect' and mode ~= 'quit') then return end
    close()
    CreateThread(function()
        Wait(150)
        ExecuteCommand(mode)
    end)
end)

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
RegisterKeyMapping(Config.Command, 'LOE duraklatma menüsü', 'keyboard', Config.OpenKey or '')

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
