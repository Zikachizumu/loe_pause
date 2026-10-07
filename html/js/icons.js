// 24x24 çizgi simgeler (stroke = currentColor). Dolgulu olanlar kendi fill'ini taşır.
window.ICONS = {
    map: '<path d="M9 4 3 6.5v13L9 17l6 3 6-2.5v-13L15 7 9 4Z"/><path d="M9 4v13M15 7v13"/>',
    gamepad: '<path d="M7 8h10a5 5 0 0 1 5 5v1.2a2.8 2.8 0 0 1-4.9 1.8L15.6 14H8.4l-1.5 2A2.8 2.8 0 0 1 2 14.2V13a5 5 0 0 1 5-5Z"/><path d="M8 10.6v2.8M6.6 12h2.8"/><circle cx="15.8" cy="11.2" r=".7" fill="currentColor"/><circle cx="17.8" cy="12.8" r=".7" fill="currentColor"/>',
    bars: '<rect x="4" y="12" width="3.6" height="8" rx=".8" fill="currentColor" stroke="none"/><rect x="10.2" y="5" width="3.6" height="15" rx=".8" fill="currentColor" stroke="none"/><rect x="16.4" y="9" width="3.6" height="11" rx=".8" fill="currentColor" stroke="none"/>',
    pass: '<path d="M12 3 4 6v6c0 4.5 3.2 7.6 8 9 4.8-1.4 8-4.5 8-9V6l-8-3Z"/><path d="m12 8 1.3 2.7 2.9.4-2.1 2 .5 2.9L12 14.6 9.4 16l.5-2.9-2.1-2 2.9-.4L12 8Z"/>',
    shop: '<path d="M5.2 8h13.6l-1 12H6.2l-1-12Z"/><path d="M9 8V6.6a3 3 0 0 1 6 0V8"/>',
    gear: '<circle cx="12" cy="12" r="3"/><path d="M12 2.8v2.6M12 18.6v2.6M2.8 12h2.6M18.6 12h2.6M5.5 5.5l1.8 1.8M16.7 16.7l1.8 1.8M18.5 5.5l-1.8 1.8M7.3 16.7l-1.8 1.8"/><circle cx="12" cy="12" r="6.4"/>',
    exit: '<path d="M10 4H5v16h5"/><path d="m15 8 4 4-4 4M19 12H9"/>',
    chevron: '<path d="m6 9 6 6 6-6"/>',
    chevronR: '<path d="m9.5 6 6 6-6 6"/>',
    arrowL: '<path d="m14.5 6-6 6 6 6"/>',
    arrowR: '<path d="m9.5 6 6 6-6 6"/>',
    back: '<path d="M15 5 8 12l7 7"/>',
    close: '<path d="M6 6l12 12M18 6 6 18"/>',
    search: '<circle cx="11" cy="11" r="6"/><path d="m20 20-4.2-4.2"/>',
    mouse: '<rect x="6.5" y="3" width="11" height="18" rx="5.5"/><path d="M12 7v4"/>',
    keyboard: '<rect x="2.5" y="6" width="19" height="12" rx="2"/><path d="M6 10h.01M9 10h.01M12 10h.01M15 10h.01M18 10h.01M7.5 14h9"/>',
    speaker: '<path d="M4 9.5v5h3.5l4.5 4v-13l-4.5 4H4Z"/><path d="M15.5 9a4 4 0 0 1 0 6M18 6.5a8 8 0 0 1 0 11"/>',
    camera: '<path d="M4 8h3l1.5-2.5h7L17 8h3v11H4V8Z"/><circle cx="12" cy="13" r="3.4"/>',
    monitor: '<rect x="3" y="4.5" width="18" height="12" rx="1.6"/><path d="M9 20h6M12 16.5V20"/>',
    chip: '<rect x="6" y="6" width="12" height="12" rx="1.6"/><rect x="9.6" y="9.6" width="4.8" height="4.8"/><path d="M9 3v3M15 3v3M9 18v3M15 18v3M3 9h3M3 15h3M18 9h3M18 15h3"/>',
    sliders: '<path d="M4 7h9M17 7h3M4 17h3M11 17h9"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="17" r="2"/>',
    mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3"/>',
    film: '<rect x="3.5" y="4" width="17" height="16" rx="2"/><path d="M3.5 9h17M3.5 15h17M8 4v16M16 4v16"/>',
    save: '<path d="M5 4h11l3 3v13H5V4Z"/><path d="M8 4v5h7V4M8 20v-6h8v6"/>',
    palette: '<path d="M12 3.5a8.5 8.5 0 1 0 0 17c1.4 0 2-.9 2-1.8 0-1.2-.9-1.5-.9-2.6 0-1 .8-1.6 1.8-1.6H17a3.5 3.5 0 0 0 3.5-3.5c0-3.8-3.7-7.5-8.5-7.5Z"/><circle cx="7.8" cy="11" r=".9" fill="currentColor"/><circle cx="11" cy="7.6" r=".9" fill="currentColor"/><circle cx="15.4" cy="8.4" r=".9" fill="currentColor"/>',
    menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
    clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
    info: '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5M12 8h.01"/>',
    user: '<circle cx="12" cy="8.5" r="3.5"/><path d="M5 20a7 7 0 0 1 14 0"/>',
    wallet: '<path d="M4 7.5h14a2 2 0 0 1 2 2V18a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V7.5Z"/><path d="M4 7.5V6a2 2 0 0 1 2-2h10"/><circle cx="16" cy="13.8" r="1" fill="currentColor"/>',
    signal: '<path d="M5 19v-3M10 19v-6M15 19V9M20 19V5"/>',
};

window.icon = function (name) {
    return '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (window.ICONS[name] || '') + '</svg>';
};
