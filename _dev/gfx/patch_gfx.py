"""pause_menu_sp_content.gfx'e LOE kayıt kancası ekler.

Kök zaman çizelgesinin 1. karesine, TIMELINE oluşturulduktan HEMEN SONRA çalışan yeni bir DoAction etiketi eklenir:
  - Oyunun içerik filmine gönderdiği seçili metod çağrıları (SET_DATA_SLOT, UPDATE_SLOT, SET_VIDEO_MEMORY_BAR...)
    sarmalanır; her çağrı "AD<US>arg1<US>arg2...<RS>" olarak _global.LOE_LOG'a eklenir, sonra asıl metod çağrılır.
  - TIMELINE.LOE_PING()          -> "LOE_OK"
  - TIMELINE.LOE_DUMP(n)         -> kaydın ilk n karakteri (ve kayıttan silinir)
  - TIMELINE.LOE_CLEAR()         -> kaydı boşaltır
Kullanım: python patch_gfx.py girdi.gfx çıktı.gfx
"""
import struct
import sys

US, RS = '\x1f', '\x1e'
MAX_LOG = 200000

WRAP = [
    'SET_DATA_SLOT', 'UPDATE_SLOT', 'UPDATE_DATA_SLOT', 'SET_DATA_SLOT_EMPTY', 'DISPLAY_DATA_SLOT',
    'SET_VIDEO_MEMORY_BAR', 'SET_VIDEO_MEMORY_BAR_2', 'SET_DESCRIPTION', 'SET_COLUMN_TITLE', 'SET_COLUMN_FOCUS',
    'SET_COLUMN_HIGHLIGHT', 'SET_COLUMN_SCROLL', 'SHOW_COLUMN', 'SHOW_WARNING_MESSAGE', 'SET_TITLE', 'SET_TIP_TEXT',
    'MENU_STATE', 'MENU_SHIFT_DEPTH', 'MENU_SECTION_JUMP', 'SET_MENU_LEVEL', 'LAYOUT_CHANGED',
    'LAYOUT_CHANGED_FOR_SCRIPT_ONLY', 'SET_INPUT_EVENT', 'SET_COLUMN_INPUT_EVENT', 'MENU_INTERACTION_RESPONSE',
    'SET_FOCUS', 'SET_HIGHLIGHT', 'SET_STATE', 'SET_CHANGED', 'SET_INDEX_CHANGED', 'SET_HIGHLIGHTED_CHANGED',
    'SET_CONTROL_LABELS', 'SET_HEADER_TITLE', 'SHOW_AND_CLEAR_COLUMNS', 'INIT_COLUMN_SCROLL', 'SET_CONTENT_SCALED',
]


# ------------------------------------------------------------------ küçük AS2 assembler
class Asm:
    def __init__(self):
        self.items = []      # ('raw', bytes) | ('label', name) | ('jump', op, label)

    def raw(self, b): self.items.append(('raw', b)); return self

    def op(self, code): return self.raw(bytes([code]))

    def rec(self, code, data): return self.raw(bytes([code]) + struct.pack('<H', len(data)) + data)

    def label(self, name): self.items.append(('label', name)); return self

    def jump(self, label): self.items.append(('jump', 0x99, label)); return self

    def if_(self, label): self.items.append(('jump', 0x9D, label)); return self

    def push(self, *vals):
        data = b''
        for v in vals:
            if v is None:
                data += b'\x03'                     # undefined
            elif isinstance(v, bool):
                data += b'\x05' + (b'\x01' if v else b'\x00')
            elif isinstance(v, int):
                data += b'\x07' + struct.pack('<i', v)
            elif isinstance(v, str):
                data += b'\x00' + v.encode('latin-1') + b'\x00'
            else:
                raise TypeError(v)
        return self.rec(0x96, data)

    # sık kullanılan işlemler
    def getvar(self, name): return self.push(name).op(0x1C)
    def getmember(self): return self.op(0x4E)
    def setmember(self): return self.op(0x4F)
    def setvar(self): return self.op(0x1D)
    def deflocal(self): return self.op(0x3C)
    def callmethod(self): return self.op(0x52)
    def add2(self): return self.op(0x47)
    def less2(self): return self.op(0x48)
    def equals2(self): return self.op(0x49)
    def not_(self): return self.op(0x12)
    def incr(self): return self.op(0x50)
    def ret(self): return self.op(0x3E)
    def pop(self): return self.op(0x17)

    def function(self, params, body):
        """Anonim DefineFunction (v1): parametreler yerel değişken olur, iç fonksiyonlar (closure) erişebilir."""
        code = body.assemble()
        data = b'\x00' + struct.pack('<H', len(params))
        for p in params:
            data += p.encode('latin-1') + b'\x00'
        data += struct.pack('<H', len(code))
        self.rec(0x9B, data)
        return self.raw(code)

    def assemble(self):
        # 1) boyutlar ve etiket konumları
        pos, labels = 0, {}
        for it in self.items:
            if it[0] == 'raw':
                pos += len(it[1])
            elif it[0] == 'label':
                labels[it[1]] = pos
            else:
                pos += 5
        # 2) üretim
        out, pos = b'', 0
        for it in self.items:
            if it[0] == 'raw':
                out += it[1]; pos += len(it[1])
            elif it[0] == 'jump':
                nxt = pos + 5
                off = labels[it[2]] - nxt
                out += bytes([it[1]]) + struct.pack('<Hh', 2, off); pos += 5
        return out


def build_hook():
    # LOE_WRAP(n, orig) -> function () { s = n; a = arguments; j = 0; while (j < a.length) s += US + a[j++];
    #                                      if (_global.LOE_LOG.length < MAX) _global.LOE_LOG += s + RS; return orig.apply(this, a); }
    inner = Asm()
    inner.push('s').getvar('n').deflocal()
    inner.push('a').getvar('arguments').deflocal()
    inner.push('j', 0).deflocal()
    inner.label('top')
    inner.getvar('j').getvar('a').push('length').getmember().less2().not_().if_('end')
    inner.push('s').getvar('s').push(US).add2().getvar('a').getvar('j').getmember().add2().setvar()
    inner.push('j').getvar('j').incr().setvar()
    inner.jump('top')
    inner.label('end')
    inner.getvar('_global').push('LOE_LOG').getmember().push('length').getmember().push(MAX_LOG).less2().not_().if_('skip')
    inner.getvar('_global').push('LOE_LOG')
    inner.getvar('_global').push('LOE_LOG').getmember().getvar('s').add2().push(RS).add2()
    inner.setmember()
    inner.label('skip')
    inner.getvar('a').getvar('this').push(2).getvar('orig').push('apply').callmethod().ret()

    wrap = Asm()
    wrap.function([], inner).ret()          # return function () {...}

    dump_body = Asm()   # LOE_DUMP(maxLen)
    dump_body.push('s').getvar('maxLen').push(0, 2).getvar('_global').push('LOE_LOG').getmember().push('substr').callmethod().deflocal()
    dump_body.getvar('_global').push('LOE_LOG')
    dump_body.getvar('maxLen').push(1).getvar('_global').push('LOE_LOG').getmember().push('substr').callmethod()
    dump_body.setmember()
    dump_body.getvar('s').ret()

    ping_body = Asm().push('LOE_OK').ret()
    clear_body = Asm()
    clear_body.getvar('_global').push('LOE_LOG', '').setmember().push(1).ret()

    a = Asm()
    # _global.LOE_LOG = ""
    a.getvar('_global').push('LOE_LOG', '').setmember()
    # _global.LOE_WRAP = function (n, orig) {...}
    a.getvar('_global').push('LOE_WRAP').function(['n', 'orig'], wrap).setmember()
    for i, name in enumerate(WRAP):
        skip = 'skip%d' % i
        # if (TIMELINE[name] != undefined) TIMELINE[name] = _global.LOE_WRAP(name, TIMELINE[name])
        a.getvar('TIMELINE').push(name).getmember().push(None).equals2().if_(skip)
        a.getvar('TIMELINE').push(name)
        a.getvar('TIMELINE').push(name).getmember().push(name, 2).getvar('_global').push('LOE_WRAP').callmethod()
        a.setmember()
        a.label(skip)
    a.getvar('TIMELINE').push('LOE_DUMP').function(['maxLen'], dump_body).setmember()
    a.getvar('TIMELINE').push('LOE_PING').function([], ping_body).setmember()
    a.getvar('TIMELINE').push('LOE_CLEAR').function([], clear_body).setmember()
    return a.assemble() + b'\x00'          # ActionEndFlag


def tag_bytes(code, data):
    if len(data) < 0x3F:
        return struct.pack('<H', (code << 6) | len(data)) + data
    return struct.pack('<HI', (code << 6) | 0x3F, len(data)) + data


def patch(src, dst):
    b = bytearray(open(src, 'rb').read())
    assert b[:3] == b'GFX', 'yalnızca sıkıştırılmamış GFX desteklenir: %r' % bytes(b[:3])
    body = bytes(b[8:])
    nbits = body[0] >> 3
    pos = (5 + nbits * 4 + 7) // 8 + 4
    # ilk DoAction (kök, 1. kare) etiketini bul; kancayı hemen arkasına ekle
    p = pos
    insert_at = None
    while p < len(body):
        cl = struct.unpack_from('<H', body, p)[0]
        code, ln = cl >> 6, cl & 0x3F
        hdr = 2
        if ln == 0x3F:
            ln = struct.unpack_from('<I', body, p + 2)[0]; hdr = 6
        if code == 1:                      # ShowFrame: 1. kare bitti, DoAction bulunamadı
            break
        if code == 12:
            data = body[p + hdr:p + hdr + ln]
            assert b'TIMELINE' in data and b'PAUSE_MENU_SP_CONTENT' in data, 'beklenmeyen kök DoAction'
            insert_at = p + hdr + ln
            break
        p += hdr + ln
    assert insert_at is not None, 'kök DoAction bulunamadı'
    hook = tag_bytes(12, build_hook())
    new_body = body[:insert_at] + hook + body[insert_at:]
    out = bytearray(b[:8]) + new_body
    struct.pack_into('<I', out, 4, len(out))
    open(dst, 'wb').write(out)
    print('patched: +%d bytes, hook at body offset %d, total %d' % (len(hook), insert_at, len(out)))


if __name__ == '__main__':
    patch(sys.argv[1], sys.argv[2])
