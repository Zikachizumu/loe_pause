-- Oyuncu tercihleri: şema tabanlı doğrulama + client KVP'de kalıcı saklama.
-- NUI'den gelen HİÇBİR değere güvenilmez: id şemada olmalı, değer türü/aralığı şemaya göre yeniden doğrulanır.

Prefs = { values = {}, loaded = false }

local KVP_KEY = 'loe_pause:prefs:v1'
local saving, dirty = false, false

local function finite(n)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge
end

--- Şemadaki satıra göre ham değeri doğrular. Dönüş: ok, normalleştirilmiş değer
function Prefs.validate(def, raw)
    if not def then return false end
    local t = def.type
    if t == 'toggle' then
        if raw == true or raw == false then return true, raw end
        return false
    elseif t == 'select' then
        if type(raw) ~= 'string' then return false end
        for _, o in ipairs(def.options) do
            if o.value == raw then return true, raw end
        end
        return false
    elseif t == 'slider' then
        if not finite(raw) then return false end
        local step = def.step or 1
        local n = math.max(def.min, math.min(def.max, raw))
        n = def.min + math.floor((n - def.min) / step + 0.5) * step
        n = math.floor(n * 1000 + 0.5) / 1000          -- kayan nokta gürültüsünü at
        n = math.max(def.min, math.min(def.max, n))
        return true, n
    end
    return false
end

--- Sunucu sahibinin Config.Defaults değeri geçerliyse onu, değilse şemadaki varsayılanı döndürür.
function Prefs.default(id)
    local def = Schema.rows[id]
    if not def then return nil end
    local override = Config.Defaults and Config.Defaults[id]
    if override ~= nil then
        local ok, v = Prefs.validate(def, override)
        if ok then return v end
    end
    return def.default
end

--- Etkin değer: saklı değer → (varsa) canlı okuma → varsayılan
function Prefs.get(id)
    local v = Prefs.values[id]
    if v ~= nil then return v end
    return Prefs.default(id)
end

--- Arayüze gösterilecek değer. Saklı değer yoksa ve ilgili sistem canlı değer verebiliyorsa (ör. pma-voice) onu gösterir.
function Prefs.display(id)
    local v = Prefs.values[id]
    if v ~= nil then return v end
    local reader = Apply and Apply.read and Apply.read[id]
    if reader then
        local ok, live = pcall(reader)
        if ok and live ~= nil then
            local good, norm = Prefs.validate(Schema.rows[id], live)
            if good then return norm end
        end
    end
    return Prefs.default(id)
end

function Prefs.snapshot()
    local out = {}
    for id in pairs(Schema.rows) do out[id] = Prefs.display(id) end
    return out
end

function Prefs.flush()
    dirty = false
    SetResourceKvp(KVP_KEY, json.encode(Prefs.values))
end

local function persist()
    dirty = true
    if saving then return end
    saving = true
    CreateThread(function()
        repeat
            dirty = false
            Wait(400)                        -- art arda gelen değişiklikleri (kaydırıcı) tek yazmada topla
        until not dirty
        saving = false
        Prefs.flush()
    end)
end

--- Dönüş: ok, değer
function Prefs.set(id, raw)
    if type(id) ~= 'string' then return false end
    local def = Schema.rows[id]
    if not def then return false end
    local ok, v = Prefs.validate(def, raw)
    if not ok then return false end
    Prefs.values[id] = v
    persist()
    return true, v
end

--- Verilen id'leri siler → varsayılana döner
function Prefs.reset(ids)
    for _, id in ipairs(ids) do Prefs.values[id] = nil end
    persist()
end

function Prefs.load()
    local raw = GetResourceKvpString(KVP_KEY)
    if raw and raw ~= '' then
        local ok, data = pcall(json.decode, raw)
        if ok and type(data) == 'table' then
            for id, value in pairs(data) do
                local def = Schema.rows[id]
                if def then
                    local good, v = Prefs.validate(def, value)
                    if good then Prefs.values[id] = v end
                end
            end
        end
    end
    Prefs.loaded = true
end

Prefs.load()
