// Karşılama kartının arka planı: gün batımında Los Santos silüeti. Sabit tohumlu üretilir; her açılışta aynı çizim çıkar.
window.homeArt = function () {
    let s = 7;
    const rnd = () => (s = (s * 16807) % 2147483647) / 2147483647;
    const W = 580, H = 194, base = H;
    let out = `<svg class="art" viewBox="0 0 ${W} ${H}" preserveAspectRatio="xMaxYMax slice" aria-hidden="true"><defs>
        <linearGradient id="hSky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1c1230"/><stop offset=".42" stop-color="#58285f"/><stop offset=".74" stop-color="#c04a82"/><stop offset="1" stop-color="#ff9a72"/></linearGradient>
        <radialGradient id="hSun" cx="0.76" cy="0.84" r="0.5"><stop offset="0" stop-color="#ffd2a1" stop-opacity=".95"/><stop offset=".25" stop-color="#ff8f78" stop-opacity=".5"/><stop offset="1" stop-color="#ff3e9a" stop-opacity="0"/></radialGradient>
    </defs>
    <rect width="${W}" height="${H}" fill="url(#hSky)"/><rect width="${W}" height="${H}" fill="url(#hSun)"/>`;

    const building = (x, w, h, color) => {
        let r = `<rect x="${x}" y="${base - h}" width="${w}" height="${h}" fill="${color}"/>`;
        for (let wy = base - h + 6; wy < base - 4; wy += 9) {
            for (let wx = x + 3; wx < x + w - 3; wx += 6) {
                if (rnd() > 0.78) r += `<rect x="${wx}" y="${wy}" width="2" height="3" fill="#ffc9a8" opacity="${(0.35 + rnd() * 0.5).toFixed(2)}"/>`;
            }
        }
        return r;
    };

    for (let x = 250; x < W; x += 14 + rnd() * 10) out += building(x, 12 + rnd() * 12, 38 + rnd() * 52, '#2a1838');
    // iki işaret bina: taçlı kule ve iğneli gökdelen
    out += `<rect x="372" y="${base - 128}" width="26" height="128" fill="#170f23"/><rect x="376" y="${base - 138}" width="18" height="10" fill="#170f23"/><rect x="381" y="${base - 150}" width="8" height="12" fill="#170f23"/>`;
    out += `<rect x="438" y="${base - 112}" width="22" height="112" fill="#1b1128"/><polygon points="441,${base - 112} 457,${base - 112} 449,${base - 156}" fill="#1b1128"/>`;
    for (let x = 240; x < W; x += 11 + rnd() * 12) out += building(x, 10 + rnd() * 14, 18 + rnd() * 40, '#120b1c');

    const palm = (x, h, lean) => {
        const tx = x + lean, ty = base - h;
        let r = `<path d="M${x} ${base} Q${x + lean * 0.2} ${base - h * 0.55} ${tx} ${ty}" stroke="#0d0815" stroke-width="3.4" fill="none" stroke-linecap="round"/>`;
        [[-30, -6], [-24, -20], [-8, -28], [10, -26], [26, -14], [30, 2], [-20, 6], [18, 8]].forEach(([dx, dy]) => {
            r += `<path d="M${tx} ${ty} Q${tx + dx * 0.55} ${ty + dy - 10} ${tx + dx} ${ty + dy}" stroke="#0d0815" stroke-width="2.6" fill="none" stroke-linecap="round"/>`;
        });
        return r;
    };
    out += palm(528, 112, 8) + palm(560, 84, -6) + palm(300, 70, 5);
    out += `<rect y="${base - 8}" width="${W}" height="8" fill="#0b0712"/></svg>`;
    return out;
};
