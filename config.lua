Config = {}

-- ================================================================ GENEL
Config.Command = 'loepause'   -- /loepause : menüyü elle açar/kapatır (yerleşik menü tercih edilse bile çalışır)
Config.OpenKey = ''           -- RegisterKeyMapping varsayılanı. Boş = atanmamış; oyuncu FiveM tuş ayarlarından verebilir.
Config.Debug   = false

Config.Brand = {
    name   = 'LEGENDS OF',
    accent = 'EMPIRE',                        -- vurgu renginde yazılan kısım
    footer = 'LEGENDS OF EMPIRE ROLEPLAY',
}

-- Arka plan. mode = 'image' → html/img/bg.jpg (tasarım referansı), 'game' → canlı oyun + bulanıklık.
-- Kendi görselini kullanmak için html/img/bg.jpg dosyasını değiştirmen yeterli (16:9, tercihen 1920x1080+).
Config.Background = {
    mode = 'image',
    image = 'img/bg.jpg',
}

-- ================================================================ ESC / P YAKALAMA
-- Yerleşik duraklatma menüsü açıldığı anda kapatılır ve bu menü açılır.
-- Diğer NUI'ler (envanter, loe_apt, loe_dealership...) ESC ile kapanırken aynı basış bu menüyü AÇMAZ.
Config.Hijack = {
    enabled          = true,
    requireLogin     = true,   -- LocalPlayer.state.isLoggedIn == true olmadan devralma (karakter seçimi/yaratma bozulmasın)
    nuiGraceMs       = 450,    -- başka bir NUI'nin odağı bu kadar yeni bıraktıysa ESC'yi yut
    reopenCooldownMs = 450,    -- kapanıştan hemen sonra gelen (sızan) ESC'yi yut
    blurGame         = false,  -- true: menü açıkken oyun ekranına bulanıklık (Background.mode = 'game' için anlamlı)
}

-- ================================================================ ANA MENÜ
-- Sıra sabittir (Harita, Oyun, İstatistikler, Battlepass, Shop, Ayarlar, Oyundan Çık).
-- enabled = false → satır gizlenir.
-- resource/export: bu resource 'started' ise export çağrılır; değilse satır "Yakında" sayfası gösterir.
Config.Menu = {
    { id = 'map',        enabled = true },
    { id = 'game',       enabled = true },
    { id = 'stats',      enabled = true },   -- resource verirsen harici istatistik sistemi açılır; yoksa yerleşik karakter özeti
    { id = 'battlepass', enabled = true, resource = 'loe_battlepass', export = 'Open' },
    { id = 'shop',       enabled = true, resource = 'loe_shop',       export = 'Open' },
    { id = 'settings',   enabled = true },
    { id = 'quit',       enabled = true },
}

-- Harita: loe_3dmap varsa onu açar, yoksa yerleşik GTA haritasına düşer.
Config.MapResource = { resource = 'loe_3dmap', open = 'Open', isOpen = 'IsOpen' }

-- Yerleşik GTA menüsüne geçişler. DOĞRULAMA GEREKİR: menü hash'leri sürümden sürüme farklı davranabilir;
-- çalışmayan olursa buradan değiştir (kod değişikliği gerekmez). Hash listesi: ActivateFrontendMenu dokümanı.
Config.Native = {
    map      = { menu = 'FE_MENU_VERSION_MP_PAUSE',               pause = false, component = -1 },
    game     = { menu = 'FE_MENU_VERSION_LANDING_MENU',           pause = true,  component = -1 },
    settings = { menu = 'FE_MENU_VERSION_LANDING_MENU',           pause = true,  component = -1 },
    keybinds = { menu = 'FE_MENU_VERSION_LANDING_KEYMAPPING_MENU', pause = true,  component = -1 },
}

-- ================================================================ ÖZELLİKLER
-- false yapılan özellik arayüzden tamamen kalkar ve uygulanmaz.
Config.Features = {
    recording = true,    -- Rockstar Editor: kayıt başlat / kaydet / iptal
    lodScale  = true,    -- Gelişmiş Grafikler: mesafe ayrıntısı ölçeği (OverrideLodscaleThisFrame, performansı etkiler)
    voice     = true,    -- Sesli Sohbet: pma-voice seviyeleri (pma-voice yoksa satırlar çalışmaz)
    cameraOverrides = true, -- Kamera: varsayılan görüş modu / sinematik kamera
}

-- ================================================================ VARSAYILANLAR
-- Oyuncu bir şeyi değiştirmediyse geçerli olan değerler. Verilmeyen id'ler schema.lua'daki varsayılanı kullanır.
-- Görünüm tercihleri oyuncu bazında KVP'de saklanır; buradaki değerler yalnızca başlangıç değeridir.
Config.Defaults = {
    ['pref.lang']      = 'tr',        -- 'tr' | 'en'
    ['pref.accent']    = 'magenta',   -- magenta | purple | blue | green | orange | red
    ['pref.dark']      = true,
    ['pref.portrait']  = false,
    ['pref.mapReturn'] = true,        -- haritadan çıkınca menüye animasyonla dön
    ['menu.native']    = false,       -- true: ESC yerleşik GTA menüsünü açar
}

-- ================================================================ TUŞ ATAMALARI → "FiveM" grubu
-- RegisterKeyMapping ile kayıtlı komutların GÜNCEL tuşu okunur (salt okunur). Okunamayan/atanmamış olanlar listelenmez.
-- command: RegisterKeyMapping'e verilen tam ad ('+inv' gibi ox_lib keybind'leri '+' ile başlar).
Config.KeyMappings = {
    { tr = '3D Harita',             en = '3D map',               command = '3dmap' },
    { tr = 'Fare imleci',           en = 'Mouse cursor',         command = 'imlec' },
    { tr = 'Minimap uzaklaştır',    en = 'Minimap zoom out',     command = 'loe_hud_minimapzoom' },
    { tr = 'Fotoğraf modu',         en = 'Photo mode',           command = 'loe_hud_photomode' },
    { tr = 'Envanter',              en = 'Inventory',            command = '+inv' },
    { tr = 'İkincil envanter',      en = 'Secondary inventory',  command = '+inv2' },
    { tr = 'Hızlı erişim çubuğu',   en = 'Hotbar',               command = '+hotbar' },
    { tr = 'Silahı doldur',         en = 'Reload weapon',        command = '+reloadweapon' },
    { tr = 'Araç kilidi',           en = 'Toggle vehicle lock',  command = '+togglelocks' },
    { tr = 'Motoru aç/kapat',       en = 'Toggle engine',        command = '+toggleengine' },
    { tr = 'Araç tuş ayarları',     en = 'Vehicle key settings', command = 'aractuslari' },
    { tr = 'Telsiz konuşma',        en = 'Radio talk',           command = '+radiotalk' },
    { tr = 'Konuşma mesafesi',      en = 'Cycle proximity',      command = 'cycleproximity' },
    { tr = 'Acil çıkış (mülk)',     en = 'Emergency exit',       command = 'loecik' },
}
