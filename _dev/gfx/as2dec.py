"""AS2 (ActionScript 2) bytecode -> okunabilir sözde kod. Yalnızca tersine mühendislik için (dağıtıma girmez).

Kullanım:  python as2dec.py dosya.gfx [--sprite N] [--grep REGEX]
  --sprite N : yalnızca DoInitAction sprite N (sınıf tanımları)
  --grep RE  : çıktıdaki fonksiyonlardan yalnızca adı/gövdesi RE ile eşleşenleri yazar (ad = 'proto.x = function' satırı)
Akış denetimi goto/etiket olarak gösterilir. Hata veren işlemler '/* ?opNN */' olarak işaretlenir."""
import re
import struct
import sys

from swf_as2 import ACTION_NAMES, load, tags


def r_cstr(b, p):
    e = b.index(b'\0', p)
    return b[p:e].decode('latin-1'), e + 1


class Dec:
    def __init__(self):
        self.pool = []
        self.out = []

    # ---- ifade biçimleme
    @staticmethod
    def member(obj, name):
        if re.fullmatch(r'[A-Za-z_$][A-Za-z_$0-9]*', name or ''):
            return '%s.%s' % (obj, name)
        return '%s[%s]' % (obj, name)

    def block(self, code, indent, regnames):
        ind = '    ' * indent
        pos, n = 0, len(code)
        # 1) komutları ve atlama hedeflerini çıkar
        ops, targets = [], set()
        while pos < n:
            start = pos
            op = code[pos]; pos += 1
            data = b''
            if op >= 0x80:
                ln = struct.unpack_from('<H', code, pos)[0]; pos += 2
                data = code[pos:pos + ln]; pos += ln
            body = b''
            if op in (0x9B, 0x8E):
                # fonksiyon gövdesi komuttan hemen sonra gelir
                if op == 0x9B:
                    _, q = r_cstr(data, 0)
                    np_ = struct.unpack_from('<H', data, q)[0]; q += 2
                    for _ in range(np_):
                        _, q = r_cstr(data, q)
                else:
                    _, q = r_cstr(data, 0)
                    np_ = struct.unpack_from('<H', data, q)[0]; q += 5
                    for _ in range(np_):
                        q += 1
                        _, q = r_cstr(data, q)
                blen = struct.unpack_from('<H', data, q)[0]
                body = code[pos:pos + blen]; pos += blen
            if op in (0x99, 0x9D):
                targets.add(pos + struct.unpack_from('<h', data, 0)[0])
            ops.append((start, op, data, body, pos))
        st = []
        out = self.out

        def emit(s):
            out.append(ind + s)

        def pop():
            return st.pop() if st else '<?>'

        for start, op, data, body, nxt in ops:
            if start in targets:
                emit('L%d:' % start)
            nm = ACTION_NAMES.get(op, 'op%02X' % op)
            if op == 0x88:
                q = 2; self.pool = []
                for _ in range(struct.unpack_from('<H', data, 0)[0]):
                    s, q = r_cstr(data, q); self.pool.append(s)
            elif op == 0x96:
                q = 0
                while q < len(data):
                    t = data[q]; q += 1
                    if t == 0:
                        s, q = r_cstr(data, q); st.append(repr(s))
                    elif t == 1:
                        st.append('%g' % struct.unpack_from('<f', data, q)[0]); q += 4
                    elif t == 2: st.append('null')
                    elif t == 3: st.append('undefined')
                    elif t == 4:
                        st.append(regnames.get(data[q], 'r%d' % data[q])); q += 1
                    elif t == 5:
                        st.append('true' if data[q] else 'false'); q += 1
                    elif t == 6:
                        lo, hi = struct.unpack_from('<II', data, q)
                        st.append('%g' % struct.unpack('<d', struct.pack('<II', hi, lo))[0]); q += 8
                    elif t == 7:
                        st.append('%d' % struct.unpack_from('<i', data, q)[0]); q += 4
                    elif t == 8:
                        i = data[q]; q += 1; st.append(repr(self.pool[i]) if i < len(self.pool) else 'c%d' % i)
                    elif t == 9:
                        i = struct.unpack_from('<H', data, q)[0]; q += 2; st.append(repr(self.pool[i]) if i < len(self.pool) else 'c%d' % i)
            elif op == 0x1C:
                nme = pop()
                st.append(nme[1:-1] if re.fullmatch(r"'[A-Za-z_$][A-Za-z_$0-9]*'", nme) else 'eval(%s)' % nme)
            elif op == 0x1D:
                v, nme = pop(), pop()
                emit('%s = %s;' % (nme[1:-1] if nme.startswith("'") else nme, v))
            elif op == 0x3C:
                v, nme = pop(), pop()
                emit('var %s = %s;' % (nme[1:-1] if nme.startswith("'") else nme, v))
            elif op == 0x41:
                nme = pop(); emit('var %s;' % nme[1:-1])
            elif op == 0x4E:
                nme, obj = pop(), pop()
                st.append(self.member(obj, nme[1:-1]) if nme.startswith("'") else '%s[%s]' % (obj, nme))
            elif op == 0x4F:
                v, nme, obj = pop(), pop(), pop()
                emit('%s = %s;' % (self.member(obj, nme[1:-1]) if nme.startswith("'") else '%s[%s]' % (obj, nme), v))
            elif op in (0x52, 0x53):
                nme, obj, na = pop(), pop(), pop()
                try:
                    args = [pop() for _ in range(int(float(na)))]
                except ValueError:
                    args = ['<?args %s>' % na]
                if nme in ("''", 'undefined'):
                    f = obj
                else:
                    f = self.member(obj, nme[1:-1]) if nme.startswith("'") else '%s[%s]' % (obj, nme)
                st.append(('new ' if op == 0x53 else '') + '%s(%s)' % (f, ', '.join(args)))
            elif op in (0x3D, 0x40):
                nme, na = pop(), pop()
                try:
                    args = [pop() for _ in range(int(float(na)))]
                except ValueError:
                    args = ['<?args %s>' % na]
                st.append(('new ' if op == 0x40 else '') + '%s(%s)' % (nme[1:-1] if nme.startswith("'") else nme, ', '.join(args)))
            elif op == 0x17:
                v = pop()
                if re.search(r'[()]', v) and not re.fullmatch(r'r\d+|[\w.]+', v):
                    emit(v + ';')
            elif op == 0x87:
                v = st[-1] if st else '<?>'
                rn = regnames.get(data[0], 'r%d' % data[0])
                emit('%s = %s;' % (rn, v))
                st[-1] = rn
            elif op in (0x47, 0x0A):
                b, a = pop(), pop(); st.append('(%s + %s)' % (a, b))
            elif op in (0x0B,): b, a = pop(), pop(); st.append('(%s - %s)' % (a, b))
            elif op in (0x0C,): b, a = pop(), pop(); st.append('(%s * %s)' % (a, b))
            elif op in (0x0D,): b, a = pop(), pop(); st.append('(%s / %s)' % (a, b))
            elif op in (0x3F,): b, a = pop(), pop(); st.append('(%s %% %s)' % (a, b))
            elif op in (0x48, 0x0F): b, a = pop(), pop(); st.append('(%s < %s)' % (a, b))
            elif op == 0x67: b, a = pop(), pop(); st.append('(%s > %s)' % (a, b))
            elif op in (0x49, 0x0E): b, a = pop(), pop(); st.append('(%s == %s)' % (a, b))
            elif op == 0x66: b, a = pop(), pop(); st.append('(%s === %s)' % (a, b))
            elif op == 0x10: b, a = pop(), pop(); st.append('(%s && %s)' % (a, b))
            elif op == 0x11: b, a = pop(), pop(); st.append('(%s || %s)' % (a, b))
            elif op == 0x12: st.append('!%s' % pop())
            elif op == 0x4C: st.append(st[-1] if st else '<?>')
            elif op == 0x4D: b, a = pop(), pop(); st.extend([b, a])
            elif op == 0x50: st.append('(%s + 1)' % pop())
            elif op == 0x51: st.append('(%s - 1)' % pop())
            elif op == 0x4A: st.append('Number(%s)' % pop())
            elif op == 0x4B: st.append('String(%s)' % pop())
            elif op == 0x44: st.append('typeof %s' % pop())
            elif op == 0x54: b, a = pop(), pop(); st.append('(%s instanceof %s)' % (a, b))
            elif op == 0x14: st.append('%s.length' % pop())
            elif op == 0x43:
                na = int(float(pop())); items = []
                for _ in range(na):
                    v, k = pop(), pop(); items.append('%s: %s' % (k[1:-1] if k.startswith("'") else k, v))
                st.append('{' + ', '.join(items) + '}')
            elif op == 0x42:
                na = int(float(pop())); st.append('[' + ', '.join(pop() for _ in range(na)) + ']')
            elif op == 0x3E:
                emit('return %s;' % pop())
            elif op == 0x9D:
                c = pop(); emit('if (%s) goto L%d;' % (c, nxt + struct.unpack_from('<h', data, 0)[0]))
            elif op == 0x99:
                emit('goto L%d;' % (nxt + struct.unpack_from('<h', data, 0)[0]))
            elif op == 0x69:
                b, a = pop(), pop(); emit('%s extends %s;' % (a, b))
            elif op in (0x3A, 0x3B):
                emit('delete ...;')
            elif op in (0x9B, 0x8E):
                if op == 0x9B:
                    fname, q = r_cstr(data, 0)
                    np_ = struct.unpack_from('<H', data, q)[0]; q += 2
                    params = []
                    for _ in range(np_):
                        s, q = r_cstr(data, q); params.append(s)
                    rn = {}
                    flags = 0
                else:
                    fname, q = r_cstr(data, 0)
                    np_, nregs, flags = struct.unpack_from('<HBH', data, q); q += 5
                    params, rn = [], {}
                    nxt_reg = 1
                    # önceden yüklenen kayıtlar (this, arguments, super, _root, _parent, _global), düşük bit sırasıyla
                    for bit, nm_ in ((0x10, 'this'), (0x04, 'arguments'), (0x40, 'super'), (0x20, '_root'), (0x80, '_parent'), (0x100, '_global')):
                        pass
                    pre = []
                    if flags & 0x01: pre.append('this')
                    if flags & 0x04: pre.append('arguments')
                    if flags & 0x10: pre.append('super')
                    if flags & 0x40: pre.append('_root')
                    if flags & 0x80: pre.append('_parent')
                    if flags & 0x100: pre.append('_global')
                    for nm_ in pre:
                        rn[nxt_reg] = nm_; nxt_reg += 1
                    for _ in range(np_):
                        reg = data[q]; q += 1
                        s, q = r_cstr(data, q)
                        params.append(s)
                        if reg: rn[reg] = s
                    # kalan kayıtlar r%d
                head = 'function %s(%s)' % (fname, ', '.join(params))
                fid = '__fn%d' % start
                emit('/* %s regs=%s */' % (head, ','.join('r%d=%s' % kv for kv in sorted(rn.items()))))
                emit('%s {' % head)
                self.block(body, indent + 1, rn)
                emit('}')
                st.append('<function %s>' % fname) if not fname else None
            elif op == 0x8B or op == 0x20:
                emit('/* setTarget */')
            elif op == 0x2A:
                emit('throw %s;' % pop())
            else:
                emit('/* ?%s */' % nm)
        for s in st:
            if s not in ('<?>',):
                pass


def main():
    path = sys.argv[1]
    sprite = None
    gre = None
    if '--sprite' in sys.argv:
        sprite = int(sys.argv[sys.argv.index('--sprite') + 1])
    if '--grep' in sys.argv:
        gre = re.compile(sys.argv[sys.argv.index('--grep') + 1])
    body, pos = load(path)
    for code, data in tags(body, pos):
        if code not in (12, 59):
            continue
        sp = None
        if code == 59:
            sp = struct.unpack_from('<H', data, 0)[0]; data = data[2:]
        if sprite is not None and sp != sprite:
            continue
        d = Dec()
        d.block(data, 0, {})
        text = '\n'.join(d.out)
        if gre and not gre.search(text):
            continue
        print('//' + '=' * 70)
        print('// %s sprite=%s' % ('DoInitAction' if code == 59 else 'DoAction', sp))
        print(text)


if __name__ == '__main__':
    main()
