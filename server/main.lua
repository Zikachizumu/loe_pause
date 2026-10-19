-- "Oyundan Çık → Sunucudan ayrıl": oyuncuyu sunucudan ayırır (FiveM ana menüsüne düşer).
-- İstemcideki ExecuteCommand('disconnect') her sürümde güvenilir çalışmadığı için kesin yol sunucudan DropPlayer'dır.
-- Yalnızca olayı gönderen oyuncunun KENDİSİ düşürülür; başka oyuncu hedeflenemez.

local REASON = 'You left the server. See you again!'
local lastLeave = {}

RegisterNetEvent('loe_pause:server:leave', function()
    local src = source
    if type(src) ~= 'number' or src <= 0 then return end

    local now = GetGameTimer()
    if lastLeave[src] and now - lastLeave[src] < 3000 then return end   -- art arda istek
    lastLeave[src] = now

    DropPlayer(src, REASON)
end)

-- Hızlı Eylemler görünürlüğü: yalnızca Config.Shortcuts'ta `aces` tanımlı satırlar için, oyuncunun o ACE'lerden birine
-- sahip olup olmadığını söyler. Bu yalnızca arayüzde satırı gösterir; asıl yetki kontrolü komutun kendi resource'undadır.
local lastCaps = {}

RegisterNetEvent('loe_pause:server:caps', function()
    local src = source
    if type(src) ~= 'number' or src <= 0 then return end

    local now = GetGameTimer()
    if lastCaps[src] and now - lastCaps[src] < 2000 then return end
    lastCaps[src] = now

    local allowed = {}
    for _, s in ipairs(Config.Shortcuts or {}) do
        if type(s.id) == 'string' and type(s.aces) == 'table' then
            for _, ace in ipairs(s.aces) do
                if IsPlayerAceAllowed(src, ace) then allowed[#allowed + 1] = s.id break end
            end
        end
    end
    TriggerClientEvent('loe_pause:client:caps', src, allowed)
end)

-- ASSETS sayfası: oyuncunun KENDİ evleri ve araçları. Yalnızca olayı gönderen oyuncu için hesaplanır; yanıtta başkasına ait veri yoktur.
-- Kaynak yoksa / sorgu başarısızsa o alan gönderilmez (arayüz "alınamıyor" gösterir; "hiç yok" demez).
local MAX_ASSETS = 50
local lastAssets = {}

local function citizenId(src)
    local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    return ok and type(player) == 'table' and player.PlayerData and player.PlayerData.citizenid or nil
end

local function rows(query, params)
    local ok, res = pcall(function() return MySQL.query.await(query, params) end)
    return ok and type(res) == 'table' and res or nil
end

local function propertyLabel(ptype, identifier)
    local ok, info = pcall(function() return exports.loe_apt:getPropertyInfo(ptype, identifier) end)
    if ok and type(info) == 'table' and type(info.label) == 'string' and info.label ~= '' then return info.label end
    return tostring(identifier)
end

RegisterNetEvent('loe_pause:server:assets', function()
    local src = source
    if type(src) ~= 'number' or src <= 0 then return end

    local now = GetGameTimer()
    if lastAssets[src] and now - lastAssets[src] < 2000 then return end
    lastAssets[src] = now

    local cid = citizenId(src)
    if not cid then return end

    local out = {}

    -- araçlar (qbx_vehicles)
    local okV, list = pcall(function() return exports.qbx_vehicles:GetPlayerVehicles({ citizenid = cid }) end)
    if okV and type(list) == 'table' then
        out.vehicles = {}
        for _, v in ipairs(list) do
            if #out.vehicles >= MAX_ASSETS then break end
            out.vehicles[#out.vehicles + 1] = {
                model  = tostring(v.modelName or ''),
                plate  = type(v.props) == 'table' and tostring(v.props.plate or '') or '',
                state  = tonumber(v.state),
                garage = type(v.garage) == 'string' and v.garage or nil,
            }
        end
    end

    -- evler / daireler (loe_apt) ve otel odaları: sahip olunanlar ya da süresi dolmamış kiralananlar
    local props = rows('SELECT ptype, identifier, owner FROM loe_properties WHERE owner = ? OR (renter = ? AND (rent_expire IS NULL OR rent_expire > UNIX_TIMESTAMP()))', { cid, cid })
    local rooms = rows('SELECT hotel, room FROM loe_hotel_rooms WHERE citizenid = ? AND expire > UNIX_TIMESTAMP()', { cid })
    if props or rooms then
        out.homes = {}
        for _, p in ipairs(props or {}) do
            if #out.homes >= MAX_ASSETS then break end
            out.homes[#out.homes + 1] = { label = propertyLabel(p.ptype, p.identifier), kind = tostring(p.ptype), rented = p.owner ~= cid }
        end
        for _, r in ipairs(rooms or {}) do
            if #out.homes >= MAX_ASSETS then break end
            out.homes[#out.homes + 1] = { label = ('%s #%s'):format(tostring(r.hotel), tostring(r.room)), kind = 'hotel', rented = true }
        end
    end

    TriggerClientEvent('loe_pause:client:assets', src, out)
end)

AddEventHandler('playerDropped', function()
    lastLeave[source] = nil
    lastCaps[source] = nil
    lastAssets[source] = nil
end)
