local isOpen, uiReady, pendingOpen = false, false, nil
local openedAt, closedAt, lastNuiFocusAt = 0, 0, 0
local radarWasHidden, radarOffAtOpen, blurred = false, false, false
-- Bizim başlattığımız yerleşik GTA menüsü akışı: target = hangi menü, seen = gerçekten açıldı mı, returnAt = LOE menüsüne dönüş zamanı
local native = { target = nil, since = 0, seen = false, returnAt = nil }

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
    local out = { id = GetPlayerServerId(PlayerId()) }       -- ping/oyuncu sayısı sunucudan gelir (loe_pause:client:info)
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
    })
    TriggerServerEvent('loe_pause:server:getInfo')
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
    native.target, native.since, native.seen, native.returnAt = target, GetGameTimer(), false, nil
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
                -- Bizim başlattığımız yerleşik menü (harita / oyun / ayarlar): açıkken dokunma.
                if paused then
                    native.seen = true
                elseif native.seen or now - native.since > 4000 then
                    -- Menü kapandı (ya da hiç açılmadı). ESC yerleşik menüyü kapatırken aynı basış onu YENİDEN açar;
                    -- akış bittiği için aşağıdaki dal onu söndürür, ardından (tercih açıksa) LOE menüsüne dönülür.
                    local wasOpen = native.seen
                    native.target, native.seen = nil, false
                    closedAt = now
                    if wasOpen and Prefs.get('pref.mapReturn') then
                        native.returnAt = now + Config.Hijack.reopenCooldownMs + 60
                    end
                end
            elseif paused then
                if Prefs.get('menu.native') or not canHijack() then
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
    elseif id == 'game' then
        cb({ ok = true })
        openNative('game')
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
    openNative('game')
    return { ok = true }
end

-- ================================================================ SUNUCU BİLGİSİ
RegisterNetEvent('loe_pause:client:info', function(data)
    if type(data) ~= 'table' or not isOpen then return end
    SendNUIMessage({
        action  = 'info',
        players = tonumber(data.players),
        max     = tonumber(data.max),
        ping    = tonumber(data.ping),
    })
end)

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
