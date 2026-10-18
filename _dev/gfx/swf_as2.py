"""Scaleform GFX (SWF) dosyasındaki AS2 kodunu listeler: sınıf adları (DoInitAction), sabit havuzu dizeleri ve
fonksiyonların basit bir disassembly'si. Kullanım: python swf_as2.py file.gfx [--dis NAME_REGEX] [--strings]"""
import re
import struct
import sys
import zlib


def load(path):
    b = open(path, 'rb').read()
    sig = b[:3]
    if sig in (b'CFX', b'CWS'):
        body = zlib.decompress(b[8:])
    elif sig in (b'GFX', b'FWS'):
        body = b[8:]
    else:
        raise SystemExit('bilinmeyen imza %r' % sig)
    # RECT atla
    nbits = body[0] >> 3
    rect_bytes = (5 + nbits * 4 + 7) // 8
    pos = rect_bytes + 4  # frame rate + count
    return body, pos


def tags(body, pos):
    while pos < len(body):
        code_len = struct.unpack_from('<H', body, pos)[0]
        pos += 2
        code, ln = code_len >> 6, code_len & 0x3F
        if ln == 0x3F:
            ln = struct.unpack_from('<I', body, pos)[0]
            pos += 4
        yield code, body[pos:pos + ln]
        pos += ln
        if code == 0:
            break


def cstr(b, p):
    e = b.index(b'\0', p)
    return b[p:e].decode('latin-1'), e + 1


ACTION_NAMES = {
    0x04: 'NextFrame', 0x06: 'Play', 0x07: 'Stop', 0x0A: 'Add', 0x0B: 'Subtract', 0x0C: 'Multiply', 0x0D: 'Divide',
    0x0E: 'Equals', 0x0F: 'Less', 0x10: 'And', 0x11: 'Or', 0x12: 'Not', 0x13: 'StringEquals', 0x14: 'StringLength',
    0x17: 'Pop', 0x18: 'ToInteger', 0x1C: 'GetVariable', 0x1D: 'SetVariable', 0x20: 'SetTarget2', 0x21: 'StringAdd',
    0x22: 'GetProperty', 0x23: 'SetProperty', 0x24: 'CloneSprite', 0x26: 'Trace', 0x34: 'GetTime', 0x3A: 'Delete',
    0x3B: 'Delete2', 0x3C: 'DefineLocal', 0x3D: 'CallFunction', 0x3E: 'Return', 0x3F: 'Modulo', 0x40: 'NewObject',
    0x41: 'DefineLocal2', 0x42: 'InitArray', 0x43: 'InitObject', 0x44: 'TypeOf', 0x45: 'TargetPath', 0x46: 'Enumerate',
    0x47: 'Add2', 0x48: 'Less2', 0x49: 'Equals2', 0x4A: 'ToNumber', 0x4B: 'ToString', 0x4C: 'PushDuplicate',
    0x4D: 'StackSwap', 0x4E: 'GetMember', 0x4F: 'SetMember', 0x50: 'Increment', 0x51: 'Decrement', 0x52: 'CallMethod',
    0x53: 'NewMethod', 0x54: 'InstanceOf', 0x55: 'Enumerate2', 0x60: 'BitAnd', 0x61: 'BitOr', 0x62: 'BitXor',
    0x63: 'BitLShift', 0x64: 'BitRShift', 0x65: 'BitURShift', 0x66: 'StrictEquals', 0x67: 'Greater', 0x68: 'StringGreater',
    0x69: 'Extends', 0x2B: 'CastOp', 0x2C: 'ImplementsOp', 0x8F: 'Try', 0x2A: 'Throw',
    0x81: 'GotoFrame', 0x83: 'GetURL', 0x87: 'StoreRegister', 0x88: 'ConstantPool', 0x8A: 'WaitForFrame',
    0x8B: 'SetTarget', 0x8C: 'GoToLabel', 0x94: 'With', 0x96: 'Push', 0x99: 'Jump', 0x9A: 'GetURL2',
    0x9B: 'DefineFunction', 0x9D: 'If', 0x9E: 'Call', 0x9F: 'GotoFrame2', 0x8E: 'DefineFunction2',
}


def actions(code, pool_out):
    """Action kayıtlarını (offset, ad, argüman) olarak döndürür; ConstantPool dizelerini pool_out'a ekler."""
    p, out, pool = 0, [], []
    while p < len(code):
        op = code[p]
        start = p
        p += 1
        data = b''
        if op >= 0x80:
            ln = struct.unpack_from('<H', code, p)[0]
            p += 2
            data = code[p:p + ln]
            p += ln
        name = ACTION_NAMES.get(op, 'op%02X' % op)
        arg = ''
        if op == 0x88:
            n = struct.unpack_from('<H', data, 0)[0]
            q = 2
            pool = []
            for _ in range(n):
                s, q = cstr(data, q)
                pool.append(s)
            pool_out.extend(pool)
            arg = '%d strings' % n
        elif op == 0x96:
            q, vals = 0, []
            while q < len(data):
                t = data[q]; q += 1
                if t == 0:
                    s, q = cstr(data, q); vals.append(repr(s))
                elif t == 1:
                    vals.append('%g' % struct.unpack_from('<f', data, q)[0]); q += 4
                elif t == 2:
                    vals.append('null')
                elif t == 3:
                    vals.append('undefined')
                elif t == 4:
                    vals.append('r%d' % data[q]); q += 1
                elif t == 5:
                    vals.append('true' if data[q] else 'false'); q += 1
                elif t == 6:
                    lo, hi = struct.unpack_from('<II', data, q)
                    vals.append('%g' % struct.unpack('<d', struct.pack('<II', hi, lo))[0]); q += 8
                elif t == 7:
                    vals.append('%d' % struct.unpack_from('<i', data, q)[0]); q += 4
                elif t == 8:
                    i = data[q]; q += 1
                    vals.append(repr(pool[i]) if i < len(pool) else 'c%d' % i)
                elif t == 9:
                    i = struct.unpack_from('<H', data, q)[0]; q += 2
                    vals.append(repr(pool[i]) if i < len(pool) else 'c%d' % i)
                else:
                    vals.append('?%d' % t); break
            arg = ', '.join(vals)
        elif op in (0x99, 0x9D):
            arg = '-> %d' % (p + struct.unpack_from('<h', data, 0)[0])
        elif op == 0x87:
            arg = 'r%d' % data[0]
        elif op == 0x8E:
            fname, q = cstr(data, 0)
            nparams, nregs, flags = struct.unpack_from('<HBH', data, q); q += 5
            params = []
            for _ in range(nparams):
                reg = data[q]; q += 1
                s, q = cstr(data, q)
                params.append('%s(r%d)' % (s, reg))
            body_len = struct.unpack_from('<H', data, q)[0]
            arg = '%s(%s) body=%d regs=%d flags=%04X' % (fname, ', '.join(params), body_len, nregs, flags)
            out.append((start, name, arg, body_len))
            continue
        elif op == 0x9B:
            fname, q = cstr(data, 0)
            nparams = struct.unpack_from('<H', data, q)[0]; q += 2
            params = []
            for _ in range(nparams):
                s, q = cstr(data, q); params.append(s)
            body_len = struct.unpack_from('<H', data, q)[0]
            arg = '%s(%s) body=%d' % (fname, ', '.join(params), body_len)
            out.append((start, name, arg, body_len))
            continue
        out.append((start, name, arg, 0))
    return out


def main():
    path = sys.argv[1]
    body, pos = load(path)
    want_dis = None
    if '--dis' in sys.argv:
        want_dis = re.compile(sys.argv[sys.argv.index('--dis') + 1])
    show_strings = '--strings' in sys.argv
    for code, data in tags(body, pos):
        if code not in (12, 59):
            continue
        if code == 59:
            sprite = struct.unpack_from('<H', data, 0)[0]
            data = data[2:]
        pool = []
        acts = actions(data, pool)
        cls = [s for s in pool if s.startswith('com.rockstargames') or s.startswith('__Packages')]
        print('== %s sprite=%s len=%d class=%s' % ('DoInitAction' if code == 59 else 'DoAction',
                                                   sprite if code == 59 else '-', len(data), cls[:3]))
        if show_strings:
            ups = sorted({s for s in pool if re.fullmatch(r'[A-Z][A-Z0-9_]{2,}', s)})
            print('   UPPER:', ' '.join(ups))
        if want_dis:
            # Bir SetMember('NAME') ile biten fonksiyon tanımını bul: Push 'NAME' ... DefineFunction2 ... SetMember
            for i, (off, nm, arg, blen) in enumerate(acts):
                if nm in ('DefineFunction2', 'DefineFunction'):
                    # tanımdan önceki son Push'ta isim var
                    label = ''
                    for j in range(i - 1, max(-1, i - 4), -1):
                        if acts[j][1] == 'Push':
                            label = acts[j][2]
                            break
                    if want_dis.search(label):
                        end_off = off + 3 + len(arg) + blen  # yaklaşık
                        print('--- fn', label, '::', arg)
                        k = i + 1
                        body_end = off + blen + 200000
                        # gövde: tanım kaydının sonundan blen bayt
                        # kayıt uzunluğu: sonraki action'ın offset'i
                        rec_end = acts[i + 1][0] if i + 1 < len(acts) else off
                        stop = rec_end + blen
                        while k < len(acts) and acts[k][0] < stop:
                            print('   %6d %-16s %s' % acts[k][:3])
                            k += 1


if __name__ == '__main__':
    main()
