import json, re, sys
from pathlib import Path

XML = Path(r'C:/Users/yasin/AppData/Local/Temp/claude/C--Users-yasin-Desktop-FiveM-VPS/e489275e-1190-4654-af8b-be45eb9c4afd/scratchpad/gfx9/pausemenu.xml')
MAP = Path(r'C:/Users/yasin/Desktop/FiveM-VPS/_work/loe_pause/_dev/gtaset/map_v8.json')
DOCS = Path(r'C:/Users/yasin/AppData/Local/Temp/claude/C--Users-yasin-Desktop-FiveM-VPS/f144c686-e39f-4cab-93b4-eeaa680bb79b/scratchpad/dl/profile-settings.md')
OUT = Path(sys.argv[1])

x = XML.read_text(encoding='utf-8', errors='replace')
d = json.loads(MAP.read_text(encoding='utf-8'))

# --- DisplayValues: seçenek adları
opts = {}
dv = x[x.index('<DisplayValues>'):x.index('</DisplayValues>')]
for m in re.finditer(r'<Item[^>]*>\s*<MenuOption>(.*?)</MenuOption>(.*?)</Item>\s*(?=<Item|</DisplayValues>|\s*$)', dv, re.S):
    pass
for blk in re.split(r'(?=<MenuOption>MENU_OPTION)', dv)[1:]:
    name = re.match(r'<MenuOption>(.*?)</MenuOption>', blk).group(1)
    labels = re.findall(r'<cTextId>(.*?)</cTextId>', blk.split('</MenuDisplayOptions>')[0])
    opts.setdefault(name, labels)

# --- profil kimlikleri (belge)
docs = {}
for line in DOCS.read_text(encoding='utf-8').splitlines():
    m = re.match(r'\|\s*`(\d+)`\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|', line)
    if m and m.group(3):
        docs[int(m.group(1))] = (m.group(2), m.group(3))

CATS = {
    '0': ('controls', 'MENU_UNIQUE_ID_SETTINGS_CONTROLS',
          ['MO_CTRL_CONTEXT', 'MO_TAR', 'MO_SPRINT', 'MO_VIB', 'MO_INV', 'MO_CTY', 'MO_CTY_FPS', 'MO_SENS', 'MO_FPS_LSENS', 'MO_FPS_ASENS',
           'MO_LK_SENS', 'MO_TPS_DZONE', 'MO_FPS_DZONE', 'MO_TPS_ACCEL', 'MO_FPS_ACCEL', 'MO_SNIPE', 'MO_DHB', 'MO_ADB', 'MO_RDF']),
    '1': ('mouse', 'MENU_UNIQUE_ID_SETTINGS_MISC_CONTROLS',
          ['MO_MONFSENS', 'MO_MOUSEWEIGHT', 'MO_MOUSEACC', 'MO_INVMOUSE', 'MO_KBM_TOGGLAIM', 'MO_FPS_DEFAULT_AIM_TYPE', 'MO_MOUSEDRIVE',
           'MO_MOUSEFLY', 'MO_MOUSESUB', 'MO_MDRVSENS', 'MO_MPPILSENS', 'MO_MHPILSEN', 'MO_MSUBSENS', 'MO_MOUSEFLYINV', 'MO_MOUSESUBINV',
           'MO_MOUSEFLYSWAP', 'MO_ACMBIKE', 'MO_ACMCAR', 'MO_ACMPLANE', 'MO_KB_LTE', 'MO_RDF']),
    '3': ('audio', 'MENU_UNIQUE_ID_SETTINGS_AUDIO',
          ['MO_SFX', 'MO_MUS', 'MO_DBOOST', 'MO_RST', 'MO_UR_PLAYMODE', 'MO_UR_AUTOSCAN', 'MO_UR_QUICKSCAN', 'MO_UR_COMPLETESCAN', 'MO_AUDIO_FOCUS', 'MO_RDF']),
    '4': ('camera', 'MENU_UNIQUE_ID_SETTINGS_CAMERA',
          ['MO_FPS_TOGGLE', 'MO_CAMERAHEIGHT', 'MO_FPS_ALVL', 'MO_FPS_FOV', 'MO_FPS_RAG', 'MO_FPS_ROLL', 'MO_FPS_HDB', 'MO_FPS_TPC', 'MO_FPS_VAC',
           'MO_HOOD_CAMERA', 'MO_FPS_REL_CAM_DRIVEBY', 'MO_RDF']),
    '5': ('display', 'MENU_UNIQUE_ID_SETTINGS_DISPLAY',
          ['MO_RAD', 'MO_HUD', 'MO_HUD_TARG', 'MO_RET_SIZE', 'MO_DISPGPS', 'MO_BRI', 'MO_SAFEZONE', 'MO_SKFX', 'MO_SUB', 'MO_MEASUREMENT', 'MO_RDF']),
}


def xml_items(screen):
    i = x.index('<MenuScreen>%s</MenuScreen>' % screen)
    j = x.index('</MenuItems>', i)
    out = []
    for attrs, body in re.findall(r'<Item([^>]*)>(.*?)</Item>', x[i:j], re.S):
        t = re.search(r'<cTextId>(.*?)</cTextId>', body)
        out.append({
            'text': t.group(1) if t else None,
            'pref': (re.search(r'<MenuPref>(.*?)</MenuPref>', body) or [None, None])[1],
            'opt': (re.search(r'<MenuOption>(.*?)</MenuOption>', body) or [None, None])[1],
            'plat': (re.search(r'platform="([^"]*)"', attrs) or [None, ''])[1],
        })
    return out


# --- profil kimlikleri: sonuçlardan (satır uid → [pid, eski, yeni])
pid_of = {}
for r in d['results']:
    if r['ids']:
        # aynı uid iki kez gelebilir (Audio'da Music ve Restore defaults = 9); ilk eşleşmeyi koru
        pid_of.setdefault((r['cat'], r['row']), r['ids'][0])

rows_out, problems = [], []
for cat, (cname, screen, want) in CATS.items():
    uids = next(c['rows'] for c in d['cats'] if c['cat'] == cat)
    if len(uids) != len(want):
        problems.append(f'{cname}: uid sayısı {len(uids)} != beklenen {len(want)}')
        continue
    xi = xml_items(screen)
    for n, (u, text) in enumerate(zip(uids, want)):
        cands = [it for it in xi if it['text'] == text]
        it = next((c for c in cands if c['plat'] in ('', 'pc_only', 'pc_only|xbsx|ps5', 'pc_only|xbox1|xbsx') and c['pref']), None) or (cands[0] if cands else {})
        pid = pid_of.get((cat, u)) if not (cname == 'audio' and n == 9) else None
        row = {'cat': cname, 'catUid': cat, 'uid': int(u), 'text': text, 'pref': it.get('pref'), 'opt': it.get('opt')}
        if pid:
            row['pid'], row['was'], row['now'] = pid[0], pid[1], pid[2]
            if pid[0] in docs:
                row['doc'] = docs[pid[0]][1]
        if it.get('opt') and it['opt'] != 'MENU_OPTION_SLIDER' and opts.get(it['opt']):
            row['labels'] = opts[it['opt']]
        if text == 'MO_RDF':
            row['kind'] = 'defaults'
        elif row.get('pid') is None:
            row['kind'] = 'other'
        elif it.get('opt') == 'MENU_OPTION_SLIDER':
            row['kind'] = 'slider'
        else:
            row['kind'] = 'list'
        rows_out.append(row)

print('problems:', problems)
print('opts known:', len(opts))
for r in rows_out:
    print(r['cat'].ljust(9), str(r['uid']).rjust(4), r['text'].ljust(24), str(r.get('pid', '-')).rjust(4), r['kind'].ljust(8), (r.get('opt') or '-').ljust(36),
          ('labels=%d' % len(r['labels'])) if r.get('labels') else '', '| doc:', r.get('doc', ''))
OUT.write_text(json.dumps(rows_out, ensure_ascii=False, indent=1), encoding='utf-8')
