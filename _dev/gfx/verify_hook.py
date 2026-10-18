"""patch_gfx.py'nin ürettiği AS2 kancasını (DoAction bytecode'u) küçük bir AS2 yorumlayıcısında çalıştırıp doğrular.
Yalnızca kancanın kullandığı işlemleri destekler; bilinmeyen işlem görürse hata verir (sessizce yanlış çalışmaz).
Kullanım: python verify_hook.py   (patch_gfx.build_hook() çıktısını sınar; hata varsa çıkış kodu 1)"""
import importlib.util
import pathlib
import struct
import sys

HERE = pathlib.Path(__file__).parent
spec = importlib.util.spec_from_file_location('patch_gfx', HERE / 'patch_gfx.py')
pg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pg)


class Undefined:
    def __repr__(self): return 'undefined'


UNDEF = Undefined()


class Obj(dict):
    pass


class Fn:
    def __init__(self, params, code, env):
        self.params, self.code, self.env = params, code, env

    def call(self, this, args):
        env = Env(self.env)
        for i, p in enumerate(self.params):
            env.vars[p] = args[i] if i < len(args) else UNDEF
        return run(self.code, env, this, list(args))


class Env:
    def __init__(self, parent=None):
        self.vars, self.parent = {}, parent

    def find(self, name):
        e = self
        while e:
            if name in e.vars:
                return e
            e = e.parent
        return None


def to_str(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, float) and v == int(v):
        return str(int(v))
    return str(v)


def truthy(v):
    return v is not UNDEF and v is not None and v is not False and v != 0 and v != ''


def get_member(obj, name):
    if isinstance(obj, str):
        if name == 'length':
            return len(obj)
        return UNDEF
    if isinstance(obj, list):
        if name == 'length':
            return len(obj)
        if isinstance(name, (int, float)) and int(name) < len(obj):
            return obj[int(name)]
        return UNDEF
    if isinstance(obj, (Obj, dict)):
        return obj.get(name, UNDEF)
    if isinstance(obj, Fn) and name == 'apply':
        return ('apply', obj)
    return UNDEF


def call_method(obj, name, args):
    if isinstance(obj, str) and name == 'substr':
        start = int(args[0])
        if len(args) > 1:
            return obj[start:start + int(args[1])]
        return obj[start:]
    if name == 'apply' and (isinstance(obj, Fn) or callable(obj)):
        this, arr = args[0], list(args[1])
        return obj.call(this, arr) if isinstance(obj, Fn) else obj(this, *arr)
    m = get_member(obj, name)
    if isinstance(m, Fn):
        return m.call(obj, args)
    if callable(m):
        return m(obj, *args)
    raise RuntimeError('aranan metod yok: %r.%s' % (type(obj).__name__, name))


def run(code, env, this, arguments):
    stack, pc = [], 0
    root = env
    while root.parent:
        root = root.parent
    steps = 0
    while pc < len(code):
        steps += 1
        if steps > 200000:
            raise RuntimeError('sonsuz döngü?')
        op = code[pc]; pc += 1
        data = b''
        if op >= 0x80:
            ln = struct.unpack_from('<H', code, pc)[0]; pc += 2
            data = code[pc:pc + ln]; pc += ln
        if op == 0x00:
            return UNDEF
        elif op == 0x96:
            q = 0
            while q < len(data):
                t = data[q]; q += 1
                if t == 0:
                    e = data.index(b'\0', q); stack.append(data[q:e].decode('latin-1')); q = e + 1
                elif t == 3:
                    stack.append(UNDEF)
                elif t == 5:
                    stack.append(bool(data[q])); q += 1
                elif t == 7:
                    stack.append(struct.unpack_from('<i', data, q)[0]); q += 4
                else:
                    raise RuntimeError('Push türü %d desteklenmiyor' % t)
        elif op == 0x1C:
            name = stack.pop()
            if name == 'this': stack.append(this)
            elif name == 'arguments': stack.append(arguments)
            else:
                e = env.find(name)
                stack.append(e.vars[name] if e else UNDEF)
        elif op == 0x1D:
            val, name = stack.pop(), stack.pop()
            e = env.find(name) or root
            e.vars[name] = val
        elif op == 0x3C:
            val, name = stack.pop(), stack.pop()
            env.vars[name] = val
        elif op == 0x4E:
            name, obj = stack.pop(), stack.pop()
            stack.append(get_member(obj, name))
        elif op == 0x4F:
            val, name, obj = stack.pop(), stack.pop(), stack.pop()
            obj[name] = val
        elif op == 0x52:
            name, obj, n = stack.pop(), stack.pop(), stack.pop()
            args = [stack.pop() for _ in range(int(n))]
            stack.append(call_method(obj, name, args))
        elif op == 0x47:
            b, a = stack.pop(), stack.pop()
            stack.append(to_str(a) + to_str(b) if isinstance(a, str) or isinstance(b, str) else a + b)
        elif op == 0x48:
            b, a = stack.pop(), stack.pop(); stack.append(a < b)
        elif op == 0x49:
            b, a = stack.pop(), stack.pop()
            stack.append(a is b if (a is UNDEF or b is UNDEF) else a == b)
        elif op == 0x12:
            stack.append(not truthy(stack.pop()))
        elif op == 0x50:
            stack.append(stack.pop() + 1)
        elif op == 0x17:
            stack.pop()
        elif op == 0x9D:
            off = struct.unpack_from('<h', data, 0)[0]
            if truthy(stack.pop()): pc += off
        elif op == 0x99:
            pc += struct.unpack_from('<h', data, 0)[0]
        elif op == 0x3E:
            return stack.pop()
        elif op == 0x9B:
            e = data.index(b'\0', 0); fname = data[:e].decode(); q = e + 1
            n = struct.unpack_from('<H', data, q)[0]; q += 2
            params = []
            for _ in range(n):
                e = data.index(b'\0', q); params.append(data[q:e].decode()); q = e + 1
            blen = struct.unpack_from('<H', data, q)[0]
            fn = Fn(params, code[pc:pc + blen], env)
            pc += blen
            if fname: env.vars[fname] = fn
            else: stack.append(fn)
        else:
            raise RuntimeError('desteklenmeyen işlem 0x%02X' % op)
    return UNDEF


def main():
    hook = pg.build_hook()
    root = Env()
    glob = Obj()
    root.vars['_global'] = glob
    calls = []

    def mk(name, ret):
        def f(this, *args):
            calls.append((name, this, args))
            return ret
        return f

    tl = Obj()
    for n in pg.WRAP:
        if n not in ('SET_TITLE', 'LAYOUT_CHANGED'):        # bu ikisi tanımsız: atlanmalı
            tl[n] = mk(n, 'ret_' + n)
    root.vars['TIMELINE'] = tl
    run(hook, root, UNDEF, [])

    errs = []

    def check(c, m):
        if not c:
            errs.append(m)

    check('SET_TITLE' not in tl and 'LAYOUT_CHANGED' not in tl, 'tanımsız metodlar tanımsız kalmalı')
    check(tl['LOE_PING'].call(tl, []) == 'LOE_OK', 'LOE_PING')
    r = call_method(tl, 'SET_DATA_SLOT', [1, 2, 'abc', 7, 3, True])
    check(r == 'ret_SET_DATA_SLOT', 'asıl metodun dönüş değeri korunmalı: %r' % r)
    check(calls[-1][0] == 'SET_DATA_SLOT' and calls[-1][1] is tl and list(calls[-1][2]) == [1, 2, 'abc', 7, 3, True],
          'asıl metod aynı this ve aynı argümanlarla çağrılmalı: %r' % (calls[-1],))
    call_method(tl, 'SET_VIDEO_MEMORY_BAR', [])
    check(calls[-1][0] == 'SET_VIDEO_MEMORY_BAR' and list(calls[-1][2]) == [], 'argümansız çağrı')
    US, RS = pg.US, pg.RS
    exp = 'SET_DATA_SLOT' + US + '1' + US + '2' + US + 'abc' + US + '7' + US + '3' + US + 'true' + RS + 'SET_VIDEO_MEMORY_BAR' + RS
    check(glob['LOE_LOG'] == exp, 'kayıt biçimi: %r' % glob['LOE_LOG'])
    first = call_method(tl, 'LOE_DUMP', [10])
    check(first == exp[:10] and glob['LOE_LOG'] == exp[10:], 'LOE_DUMP ilk n karakteri verip silmeli')
    rest = call_method(tl, 'LOE_DUMP', [5000])
    check(first + rest == exp and glob['LOE_LOG'] == '', 'LOE_DUMP kalanı vermeli')
    check(call_method(tl, 'LOE_DUMP', [5]) == '', 'boş kayıtta boş dize')
    call_method(tl, 'SET_FOCUS', ['x'])
    call_method(tl, 'LOE_CLEAR', [])
    check(glob['LOE_LOG'] == '', 'LOE_CLEAR')
    # sınır: kayıt MAX_LOG'u aşınca yeni giriş eklenmez ama asıl metod yine çağrılır
    glob['LOE_LOG'] = 'z' * pg.MAX_LOG
    n0 = len(calls)
    r = call_method(tl, 'SET_DATA_SLOT', [9])
    check(len(glob['LOE_LOG']) == pg.MAX_LOG and len(calls) == n0 + 1 and r == 'ret_SET_DATA_SLOT', 'kayıt sınırı: eklenmemeli, asıl metod çalışmalı')
    # asıl metod hata verirse hata aynen yayılmalı
    def boom(this, *a): raise ValueError('x')
    tl['SET_FOCUS'] = boom
    glob['LOE_LOG'] = ''
    try:
        call_method(tl, 'SET_FOCUS', [1]); check(False, 'hata yutulmamalı')
    except ValueError:
        pass
    if errs:
        for e in errs:
            print('FAIL', e)
        return 1
    print('verify_hook: tüm denetimler geçti (%d bayt kanca)' % len(hook))
    return 0


if __name__ == '__main__':
    sys.exit(main())
