# loe_pause

Legends of Empire (LOE) için **Pause Menü + Ayarlar ekranı**. ESC / P ile açılan yerleşik GTA duraklatma menüsünün yerine geçen FiveM NUI menüsü (Qbox, `[loe]` kategorisi).

- Ana menü: **Harita · İstatistikler · Battlepass · Shop · Ayarlar · Oyundan Çık**
- Ayarlar: 3 bölümlü ekran (kategoriler · alt kategoriler · arama + ayar satırları), klavye + fare, Türkçe/İngilizce
- Bağımlılık yok: `qbx_core`, `pma-voice`, `loe_3dmap` yalnızca **varsa** (pcall) kullanılır; `ox_lib` gerekmez.

## Kurulum

```
resources/[loe]/loe_pause      →  server.cfg'de zaten `ensure [loe]` var; ayrıca satır eklemek gerekmez.
```

Resource ilk kez eklendiği için **sunucu restart** (ya da txAdmin'den `ensure loe_pause`) gerekir.
`loe_hud` aktifken menü açıkken radar gizlenir, loe_hud'ın minimap eşitlemesi sayesinde HUD de gizlenir.

### Güncelleme (git)

```bash
runuser -u fivem -- git -C "/opt/fivem/txData/LegendsofEmpire_AC516C.base/resources/[loe]/loe_pause" pull
```

## Dosyalar

| Dosya | Görev |
|---|---|
| `fxmanifest.lua` | Manifest (`ui_page`, paylaşımlı/client/server scriptler) |
| `config.lua` | Marka, arka plan, ESC yakalama, ana menü, harita/native menü bağlantıları, özellik anahtarları, varsayılanlar, FiveM tuş listesi |
| `shared/schema.lua` | **Ayarlar ekranının tek doğruluk kaynağı** (kategoriler, gruplar, satırlar, tr/en metinler) |
| `client/prefs.lua` | Şemaya göre doğrulama + oyuncu bazında KVP kalıcılığı |
| `client/apply.lua` | Ayarları oyuna uygulayan native çağrıları + eylemler (kayıt, sıfırlama) |
| `client/main.lua` | ESC/P yakalama, aç/kapat, NUI odağı, NUI callback'leri, harita/yerleşik menü geçişleri |
| `html/` | NUI (vanilla HTML/CSS/JS), `html/img/bg.jpg` arka plan |
| `_dev/` | Yalnızca geliştirme: `check.py` (Lua/şema/doğrulama testleri), `mock.html` (tarayıcıda önizleme) |

## ESC nasıl yönetiliyor

1. Yerleşik menü açıldığı kare tespit edilir (`IsPauseMenuActive`) ve hemen kapatılır; bu menü açılır. (Başka resource'lar — `loe_apt` gibi — kontrol seviyesinde ESC'nin engellenemediğini zaten belgelemişti.)
2. Menü açıkken oyun kontrolleri kapatılır, radar gizlenir; kapanınca radar önceki durumuna döner, NUI odağı bırakılır.
3. Başka bir NUI (envanter, `loe_apt`, `loe_dealership`, `loe_cursor`...) ESC ile **kapanırken** aynı basış bu menüyü **açmaz** (`Config.Hijack.nuiGraceMs`). Menü kapanırken sızan ESC de yutulur (`reopenCooldownMs`).
4. Giriş yapılmamışken (`LocalPlayer.state.isLoggedIn ~= true`), ara sahnede ve ekran kararmışken yerleşik menüye dokunulmaz → karakter seçimi/yaratma bozulmaz.
5. Script ile açılan yerleşik menü/harita (`ActivateFrontendMenu`) ESC'de kendiliğinden kapanmaz — yalnızca bir seviye geri gider ve açık kalır. Bu yüzden akış sırasında ESC / P / Geri yakalanır, menü kapatılır, sızan yeniden açılış söndürülür ve (tercih açıksa) LOE menüsüne dönülür. Sorun giderme: `Config.Debug = true` yapınca F8 konsolunda `[loe_pause] native ...` satırları görünür.
6. Güvenlik ağı: **Ayarlar → Normal Menü** ile oyuncu ESC'yi yerleşik menüye çevirebilir; `/loepause` her durumda bu menüyü açar. Sunucu tarafında `Config.Hijack.enabled = false` hepsini kapatır.

## Kapsam: ne GERÇEKTEN çalışır, ne yerleşik menüye yönlenir

GTA'nın grafik/ses/kontrol ayarlarının çoğu **FiveM'den okunamaz ya da yazılamaz** (CFX native dokümanında `SET_PROFILE_SETTING` yoktur; yalnızca `GET_PROFILE_SETTING` vardır). Bu yüzden ekrandaki her satır dürüstçe etiketlidir:

- **Uygulanan ayarlar** (anahtar/seçici/kaydırıcı; KVP'de saklanır, giriş yapınca yeniden uygulanır):

| Ayar | Karşılığı |
|---|---|
| Hedefleme modu (`aim.mode`) | `SetPlayerTargetingMode` |
| Yürürken / araç kamerası, sinematik kamera tuşu | `SetFollowPedCamViewMode`, `SetFollowVehicleCamViewMode`, `SetCinematicButtonActive` |
| Radar ve HUD, Nişangâh, GPS rotası | `DisplayRadar`, `HideHudComponentThisFrame(14)`, `SetBlipRoute` |
| Araç radyosu | `SetUserRadioControlEnabled`, `SetVehicleRadioEnabled` |
| Mesafe ayrıntısı ölçeği (Gelişmiş Grafikler) | `OverrideLodscaleThisFrame` |
| Telsiz / arama ses seviyesi, mikrofon tıkı | `pma-voice` export'ları (`setRadioVolume`, `setCallVolume`, `setMicClick*Volume`, `setVoiceProperty`) |
| Rockstar Editor kaydı (başlat / kaydet / iptal) | `StartRecording`, `StopRecordingAndSaveClip`, `StopRecordingAndDiscardClip` |
| Tercihler: vurgu rengi, koyu mod, portre modu, dil, harita dönüş animasyonu, görünümü sıfırla | Yalnızca bu menünün kendi arayüzü |
| Normal Menü: ESC'de yerleşik menü | Ana döngü bu tercihe bakar |

- **`GTA Ayarları` etiketli satırlar** (çözünürlük, MSAA, VSync, doku/gölge kalitesi, ses seviyeleri, çıkış cihazı, fare/gamepad hassasiyeti, titreşim, altyazı, parlaklık, güvenli alan...): burada **değiştirilemez**. Satıra tıklamak yerleşik GTA/FiveM menüsünü açar (`Config.Native`).
- **Tuş Atamaları** salt okunurdur: güncel tuş `GetControlInstructionalButton` ile okunur. Değiştirmek için "Tuşları değiştir" satırı FiveM tuş atamaları menüsünü açar (`FE_MENU_VERSION_LANDING_KEYMAPPING_MENU`). "FiveM" grubu `Config.KeyMappings` listesinden beslenir; atanmamış olanlar gizlenir.
- **Kayıt ve Başlangıç**: GTA'nın kayıt yükleme / başlangıç akışı FiveM'de uygulanmaz; bölüm bunu açıklar.

### Ana menü

| Satır | Davranış |
|---|---|
| Harita | `loe_3dmap` çalışıyorsa onu açar; yoksa **doğrudan yerleşik büyük harita** (`ActivateFrontendMenu` + `PauseMenuceptionGoDeeper(0)`, bkz. `Config.Native.map`). Varsayılan: ESC ile harita kapanınca doğrudan oyuna dönülür. Tercih (`pref.mapReturn`, varsayılan **kapalı**) açıksa harita / yerleşik menü ESC ile kapanınca LOE menüsü animasyonla geri gelir; ESC'nin yerleşik menüyü yeniden açan sızıntısı söndürülür |
| İstatistikler | `Config.Menu`'de harici `resource/export` verilirse onu açar; yoksa yerleşik özet: karakter (ad, citizenid, meslek), finans (nakit/banka) ve **Sağlık** kartı. Sağlık kartı `loe_jobcreator` hastalık sisteminin istemciye gönderdiği `healthState` olayından beslenir (ad, belirti, "ilaç etkisinde" / "sargılı" durumu); hastalık yoksa "Hastalığın yok" yazar. Sistem `Config.Health` ile ayarlanır, `loe_jobcreator`'a dokunulmaz |
| Battlepass / Shop | Sunucuda bu sistemler **yok**. `Config.Menu`'de `resource`/`export` (varsayılan `loe_battlepass`/`loe_shop` → `Open`) başlamışsa onları açar; değilse "Yakında" sayfası gösterir. |
| Ayarlar | Ayarlar ekranı |
| Oyundan Çık | Onay penceresi → "Sunucudan ayrıl" (`disconnect`) / "Oyunu kapat" (`quit`) |

## Güvenlik

- NUI'den gelen **her** değer Lua'da yeniden doğrulanır: id şemada olmalı; toggle yalnızca boolean, select yalnızca tanımlı seçenek, slider yalnızca sonlu sayı (aralığa kırpılır, adıma yuvarlanır). Bozuk/oynanmış KVP yüklenirken süzülür.
- Eylem ve native hedefleri beyaz listededir (`Schema.actions`, `Config.Native`); `quit` yalnızca `disconnect`/`quit` kabul eder.
- Menü kapalıyken gelen NUI callback'leri reddedilir. Sağlık verisi yalnızca sunucudan gelen olaydan okunur ve uzunluk/tür süzgecinden geçer.

## Test (oyunda)

1. Giriş yap → ESC: LOE menüsü açılmalı, yerleşik GTA menüsü **görünmemeli**; HUD/minimap gizlenmeli.
2. ESC tekrar: menü kapanmalı, oyun kontrolü ve minimap/HUD geri gelmeli, yerleşik menü açılmamalı.
3. Envanteri aç, ESC ile kapat: pause menü **açılmamalı**.
4. Harita: `loe_3dmap` açılmalı; kapanınca (tercih açıksa) menü geri gelmeli.
5. Ayarlar'da bir `GTA Ayarları` satırı: yerleşik GTA menüsü açılmalı, ESC ile çıkınca oyuna dönmeli. **Çalışmazsa** `config.lua > Config.Native` hash'lerini düzelt.
6. Ayarlar → Kamera/Görüntü/Ses vb.: değiştir, çık, tekrar gir: değerler korunmalı; yeniden bağlanınca da korunmalı (KVP).
7. Tercihler → Görünümü Sıfırla: onay çıkmalı; sonra tema/renk/dil varsayılana dönmeli.
8. Normal Menü → "ESC ile yerleşik menü": ESC yerleşik menüyü açmalı; `/loepause` bu menüyü açmalı.
9. Karakter seçimi/ilk giriş ekranında ESC: yerleşik davranış bozulmamalı.

> Doğrulanması gerekenler (oyun içi test yapılmadan kesinleştirilemez): `Config.Native` hash'lerinin ESC'deki gerçek menüye karşılığı, `GetControlInstructionalButton`'ın fare düğmeleri için döndürdüğü jeton adları (`html/js/app.js > MOUSE`), `SetBlipRoute`'un waypoint çizgisini kapatması.

## Geliştirme

```bash
pip install lupa
python _dev/check.py                      # Lua sözdizimi + şema + doğrulama testleri, _dev/schema.json üretir
python -m http.server 8123                # sonra http://localhost:8123/_dev/mock.html  (?lang=en &dark=0 &portrait=1 &accent=blue)
```

Arka plan: `html/img/bg.jpg` (tasarım referansından). Kendi görselini koymak için aynı adla değiştir.
