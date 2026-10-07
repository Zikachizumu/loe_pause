-- Menü açılırken oyuncu sayısını döndürür. Başka sunucu mantığı yok; ayarlar tamamen client'ta (KVP).

local lastRequest = {}

RegisterNetEvent('loe_pause:server:getInfo', function()
    local src = source
    local now = GetGameTimer()
    if lastRequest[src] and now - lastRequest[src] < 2000 then return end   -- istek yağmurunu kes
    lastRequest[src] = now

    TriggerClientEvent('loe_pause:client:info', src, {
        players = GetNumPlayerIndices(),
        max     = GetConvarInt('sv_maxclients', 48),
        ping    = GetPlayerPing(src),             -- GetPlayerPing yalnızca sunucu tarafında vardır
    })
end)

AddEventHandler('playerDropped', function()
    lastRequest[source] = nil
end)
