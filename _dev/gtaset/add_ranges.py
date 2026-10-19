"""shared/gtaset_data.lua kaydırıcı satırlarına ölçülen üst sınırı (max) ve ters yönü (inv) ekler.
Kaynak: _dev/gtaset/ranges_v10.json (/loe_gtaset v10 sonucu: lo = 0 her kaydırıcıda, hi = üst sınır, inv = sağa basış değeri azaltır).
Kullanım: python _dev/gtaset/add_ranges.py   (tekrar çalıştırılabilir)"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
data = json.loads((ROOT / '_dev/gtaset/ranges_v10.json').read_text(encoding='utf-8'))
ranges = data['ranges']
# Güvenli bölge (212): GetSafeZoneSize = 1 - 0.01 * profil değeri → ekranda %100..%90 (sağ = geniş) olarak gösterilir
DISPLAY = {'212': ", base = 90, unit = '%'"}
path = ROOT / 'shared/gtaset_data.lua'
out, n = [], 0
for line in path.read_text(encoding='utf-8').splitlines():
    m = re.search(r"kind = 'slider'.*pid = (\d+)", line)
    if m:
        r = ranges[m.group(1)]
        assert r['lo'] == 0, r
        line = re.sub(r", max = \d+|, inv = true|, base = \d+, unit = '%'", '', line)
        extra = f", max = {r['hi']}" + (', inv = true' if r['inv'] else '') + DISPLAY.get(m.group(1), '')
        line = re.sub(r"(pid = \d+)", lambda mm: mm.group(1) + extra, line, count=1)
        n += 1
    out.append(line)
path.write_text('\n'.join(out) + '\n', encoding='utf-8')
print(n, 'kaydırıcı güncellendi')
