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

-- Ana ekrandaki "Home" ve "Vehicles" kartları: oyuncunun KENDİ kayıtlarının sayısı. Yalnızca olayı gönderen oyuncu için hesaplanır;
-- yanıtta başkasına ait veri yoktur. Tablo yoksa (ilgili resource kurulu değil) o alan gönderilmez → arayüz "—" gösterir.
local lastSummary = {}

local function citizenId(src)
    local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)
    return ok and type(player) == 'table' and player.PlayerData and player.PlayerData.citizenid or nil
end

local function count(query, params)
    local ok, n = pcall(function() return MySQL.scalar.await(query, params) end)
    return ok and tonumber(n) or nil
end

RegisterNetEvent('loe_pause:server:summary', function()
    local src = source
    if type(src) ~= 'number' or src <= 0 then return end

    local now = GetGameTimer()
    if lastSummary[src] and now - lastSummary[src] < 2000 then return end
    lastSummary[src] = now

    local cid = citizenId(src)
    if not cid then return end

    local out = {}
    out.vehicles = count('SELECT COUNT(*) FROM player_vehicles WHERE citizenid = ?', { cid })

    local props = count('SELECT COUNT(*) FROM loe_properties WHERE owner = ? OR (renter = ? AND (rent_expire IS NULL OR rent_expire > UNIX_TIMESTAMP()))', { cid, cid })
    local rooms = count('SELECT COUNT(*) FROM loe_hotel_rooms WHERE citizenid = ? AND expire > UNIX_TIMESTAMP()', { cid })
    if props or rooms then out.homes = (props or 0) + (rooms or 0) end

    TriggerClientEvent('loe_pause:client:summary', src, out)
end)

AddEventHandler('playerDropped', function()
    lastLeave[source] = nil
    lastCaps[source] = nil
    lastSummary[source] = nil
end)
