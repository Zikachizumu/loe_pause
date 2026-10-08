fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'loe_pause'
author 'loe'
description 'LOE Pause Menu — ESC menüsünün yerine geçen NUI menü + Ayarlar ekranı (Qbox)'
version '1.0.0'

ui_page 'html/index.html'

shared_scripts {
    'config.lua',
    'shared/schema.lua'
}

client_scripts {
    'client/prefs.lua',
    'client/apply.lua',
    'client/main.lua'
}

files {
    'html/index.html',
    'html/css/*.css',
    'html/js/*.js',
    'html/img/*'
}

-- Bagimlilik YOK (bilerek): qbx_core, pma-voice ve loe_3dmap yalnizca varsa pcall ile kullanilir.
-- Bu resource ox_lib'e ihtiyac duymaz; KVP + yerlesik natives yeterlidir.
