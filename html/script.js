/* ap1le_mechanicjob NUI: tuning panel, invoice create dialog, customer invoice popup.
 * Plain JS, no dependencies. All dynamic text goes through textContent. */
(() => {
    'use strict';

    // -----------------------------------------------------------------------
    // Environment / helpers
    // -----------------------------------------------------------------------

    const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : null;
    const DEV = RES === null;

    const $ = (sel, root = document) => root.querySelector(sel);
    const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

    function el(tag, cls, text) {
        const node = document.createElement(tag);
        if (cls) node.className = cls;
        if (text !== undefined && text !== null) node.textContent = String(text);
        return node;
    }

    const num = (v, d = 0) => {
        const n = Number(v);
        return Number.isFinite(n) ? n : d;
    };
    const int = (v, d = 0) => Math.trunc(num(v, d));
    const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
    const money = (n) => '$' + Math.round(num(n)).toLocaleString('en-US');
    const clone = (o) => JSON.parse(JSON.stringify(o));

    async function post(name, body = {}) {
        if (DEV) return devPost(name, body);
        try {
            const res = await fetch(`https://${RES}/${name}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(body),
            });
            return await res.json();
        } catch (err) {
            return null;
        }
    }

    // Static SVG icons (constants only, never built from dynamic data)
    const ICONS = {
        close: '<path d="M6 6l12 12M18 6L6 18"/>',
        check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
        trash: '<path d="M5 7h14M9 7V5h6v2M7 7l1 12h8l1-12"/>',
        left: '<path d="M14 6l-6 6 6 6"/>',
        right: '<path d="M10 6l6 6-6 6"/>',
        down: '<path d="M6 10l6 6 6-6"/>',
        swap: '<path d="M7 4l-3 3 3 3M4 7h13M17 20l3-3-3-3M20 17H7"/>',
        // camera presets
        default: '<path d="M12 3l8 4.5v9L12 21l-8-4.5v-9z"/><path d="M4 7.5l8 4.5 8-4.5M12 12v9"/>',
        front: '<path d="M6 19v-7l1.7-4.3A1.6 1.6 0 0 1 9.2 6.7h5.6a1.6 1.6 0 0 1 1.5 1L18 12v7"/><path d="M6 12h12M4.5 19H8M16 19h3.5"/><circle cx="8.9" cy="15" r=".9"/><circle cx="15.1" cy="15" r=".9"/>',
        rear: '<path d="M6 19v-7l1.7-4.3A1.6 1.6 0 0 1 9.2 6.7h5.6a1.6 1.6 0 0 1 1.5 1L18 12v7"/><path d="M6 12h12M4.5 19H8M16 19h3.5M8 15h2.6M13.4 15H16"/>',
        wheel: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="2.6"/><path d="M12 4v5.4M12 14.6V20M4 12h5.4M14.6 12H20"/>',
        engine: '<path d="M4 10h2V8h3V6h6v2h2v2h3v6h-3v2H8v-2H4z"/><path d="M9 12h6M9 15h6"/>',
        side: '<path d="M3 16.5v-3l2-.8 1.9-3.4A2 2 0 0 1 8.6 8.2h6a2 2 0 0 1 1.6.8l2.4 3.4 2.4.5V16.5"/><path d="M3 16.5h2.2M9.8 16.5h4.4M18.8 16.5H21"/><circle cx="7.5" cy="16.8" r="2"/><circle cx="16.5" cy="16.8" r="2"/>',
    };

    function icon(name, extraClass) {
        const wrap = document.createElement('span');
        wrap.className = 'ico' + (extraClass ? ' ' + extraClass : '');
        wrap.setAttribute('aria-hidden', 'true');
        wrap.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">'
            + (ICONS[name] || '') + '</svg>';
        return wrap;
    }

    // -----------------------------------------------------------------------
    // Locale (fetched once at load; the key is the fallback)
    // -----------------------------------------------------------------------

    let LOC = {};

    function t(key, ...args) {
        let s = (Object.prototype.hasOwnProperty.call(LOC, key) && typeof LOC[key] === 'string') ? LOC[key] : key;
        let i = 0;
        s = s.replace(/%[sd]/g, (m) => (i < args.length ? String(args[i++]) : m));
        return s;
    }

    function applyLocale() {
        $$('[data-i18n]').forEach((n) => { n.textContent = t(n.dataset.i18n); });
        $$('[data-i18n-aria]').forEach((n) => { n.setAttribute('aria-label', t(n.dataset.i18nAria)); });
    }

    let localeReady = null; // assigned at the bottom of the file, once everything is defined

    const hasLocale = () => Object.keys(LOC).length > 0;

    // One locale request; true when a non-empty string table came back
    async function fetchLocale() {
        const res = await post('locale');
        if (res && typeof res === 'object' && !Array.isArray(res) && Object.keys(res).length > 0) {
            LOC = res;
            applyLocale();
            return true;
        }
        return false;
    }

    // The page can load before the Lua 'locale' callback is registered: retry for ~5 s
    async function loadLocale() {
        for (let attempt = 0; attempt < 10; attempt++) {
            if (await fetchLocale()) return;
            await new Promise((r) => setTimeout(r, 500));
        }
        applyLocale();
    }

    // Used by every open: waits for the initial load, then retries once if it never succeeded
    async function ensureLocale() {
        await localeReady;
        if (!hasLocale()) await fetchLocale();
    }

    // -----------------------------------------------------------------------
    // Layer show / hide (opacity + transform transition, no animation loops)
    // -----------------------------------------------------------------------

    const hideTimers = new WeakMap();

    function showLayer(layer) {
        clearTimeout(hideTimers.get(layer));
        layer.hidden = false;
        // One-off frame so the transition starts from the hidden state
        requestAnimationFrame(() => layer.classList.add('show'));
    }

    function hideLayer(layer) {
        layer.classList.remove('show');
        clearTimeout(hideTimers.get(layer));
        hideTimers.set(layer, setTimeout(() => { layer.hidden = true; }, 260));
    }

    const isShown = (layer) => !layer.hidden && layer.classList.contains('show');

    // -----------------------------------------------------------------------
    // Shared widgets
    // -----------------------------------------------------------------------

    function makeSwitch(checked, onToggle, labelKey) {
        const b = el('button', 'switch');
        b.type = 'button';
        b.setAttribute('role', 'switch');
        b.setAttribute('aria-checked', checked ? 'true' : 'false');
        b.append(el('span', 'switch-track'), el('span', 'switch-text', t(labelKey || 'ui_enabled')));
        b.addEventListener('click', () => onToggle(b.getAttribute('aria-checked') !== 'true'));
        b.setChecked = (v) => b.setAttribute('aria-checked', v ? 'true' : 'false');
        return b;
    }

    function safeHex(hex) {
        return /^#[0-9a-f]{3,8}$/i.test(String(hex)) ? String(hex) : '#808080';
    }

    const hexToRgb = (hex) => {
        const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(hex);
        return m ? { r: parseInt(m[1], 16), g: parseInt(m[2], 16), b: parseInt(m[3], 16) } : { r: 255, g: 255, b: 255 };
    };
    const rgbToHex = (c) => '#' + [c.r, c.g, c.b].map((v) => clamp(int(v), 0, 255).toString(16).padStart(2, '0')).join('');

    // =======================================================================
    // TUNING
    // =======================================================================

    const PAINT_KEYS = [
        ['color1', 'ui_primary'],
        ['color2', 'ui_secondary'],
        ['pearlescentColor', 'ui_pearl'],
        ['wheelColor', 'ui_wheel_colour'],
    ];
    const NEON_SIDES = ['l', 'r', 'f', 'b'];
    const CAMERAS = ['default', 'front', 'rear', 'wheel', 'engine', 'side'];
    // GTA xenon colour indices 0..12 (255 = stock/default)
    const XENON_COLOURS = [
        '#ffffff', '#1f3bff', '#14a8ff', '#2ee6a6', '#7be22a', '#ffe600', '#ffb300',
        '#ff7a00', '#ff1f1f', '#ff7ac7', '#ff1fa1', '#8a2be2', '#5a2dff',
    ];
    const TABS = ['performance', 'cosmetic', 'paint', 'extras'];

    const T = {
        data: null,
        orig: null,
        cur: null,
        tab: 'performance',
        cam: 'default',
        sel: null,      // pending performance selection { category, level }
        busy: false,
        cart: [],
    };

    const tuningLayer = $('#tuning');
    const tBody = $('#t-body');

    // ---- normalisation: never trust the shape of what Lua sends ----------

    function normTuning(raw) {
        raw = raw || {};
        const v = raw.vehicle || {};
        const ex = raw.extras || {};
        const wt = ex.windowTint || {};
        const xe = ex.xenon || {};
        const ne = ex.neon || {};
        const pl = ex.plate || {};
        const pa = raw.paint || {};
        const neEn = ne.enabled || {};
        const neCo = ne.colour || {};
        const opts = (list, vk) => (Array.isArray(list) ? list : []).map((o) => ({ value: int(o && o[vk]), label: String((o && o.label) ?? '') }));

        return {
            vehicle: { label: String(v.label ?? ''), plate: String(v.plate ?? ''), owned: v.owned === true },
            performance: (Array.isArray(raw.performance) ? raw.performance : []).map((p) => ({
                id: String(p.id),
                label: String(p.label ?? p.id),
                current: int(p.current),
                options: (Array.isArray(p.options) ? p.options : []).map((o) => ({
                    level: int(o.level),
                    label: String(o.label ?? ''),
                    item: o.item ? String(o.item) : null,
                    hasItem: o.hasItem === true,
                })),
            })),
            cosmetic: (Array.isArray(raw.cosmetic) ? raw.cosmetic : []).map((c) => ({
                id: String(c.id),
                label: String(c.label ?? c.id),
                price: num(c.price),
                current: int(c.current, -1),
                options: opts(c.options, 'value'),
            })),
            paint: {
                colours: (Array.isArray(pa.colours) ? pa.colours : []).map((c) => ({
                    index: int(c.index), label: String(c.label ?? ''), hex: safeHex(c.hex),
                })),
                current: {
                    color1: int((pa.current || {}).color1, -1),
                    color2: int((pa.current || {}).color2, -1),
                    pearlescentColor: int((pa.current || {}).pearlescentColor, -1),
                    wheelColor: int((pa.current || {}).wheelColor, -1),
                },
                price: num(pa.price),
            },
            extras: {
                windowTint: { current: int(wt.current), price: num(wt.price), options: opts(wt.options, 'value') },
                xenon: { enabled: xe.enabled === true, colour: int(xe.colour, 255), price: num(xe.price) },
                neon: {
                    enabled: { l: neEn.l === true, r: neEn.r === true, f: neEn.f === true, b: neEn.b === true },
                    colour: { r: clamp(int(neCo.r, 255), 0, 255), g: clamp(int(neCo.g, 255), 0, 255), b: clamp(int(neCo.b, 255), 0, 255) },
                    price: num(ne.price),
                },
                plate: { current: int(pl.current), price: num(pl.price), options: opts(pl.options, 'value') },
            },
        };
    }

    function buildState(d) {
        const mods = {};
        d.cosmetic.forEach((c) => { mods[c.id] = c.current; });
        return {
            mods,
            paint: Object.assign({}, d.paint.current),
            windowTint: d.extras.windowTint.current,
            plate: d.extras.plate.current,
            xenon: { enabled: d.extras.xenon.enabled, colour: d.extras.xenon.colour },
            neon: { enabled: Object.assign({}, d.extras.neon.enabled), colour: Object.assign({}, d.extras.neon.colour) },
        };
    }

    // ---- preview (coalesced: the last value always arrives) ----------------

    const previewState = new Map();

    function sendPreview(type, id, value) {
        const key = type + ':' + id;
        let s = previewState.get(key);
        if (!s) {
            s = { timer: 0, pending: null };
            previewState.set(key, s);
        }
        const payload = { type, id, value };
        if (s.timer) {
            s.pending = payload;
            return;
        }
        post('tuning:preview', payload);
        const tick = () => {
            s.timer = 0;
            if (s.pending) {
                const p = s.pending;
                s.pending = null;
                post('tuning:preview', p);
                s.timer = setTimeout(tick, 80);
            }
        };
        s.timer = setTimeout(tick, 80);
    }

    function clearPreviews() {
        previewState.forEach((s) => { clearTimeout(s.timer); s.timer = 0; s.pending = null; });
    }

    // ---- cart: derived from the difference between cur and orig -------------

    function colourName(index) {
        const c = T.data.paint.colours.find((x) => x.index === index);
        return c ? c.label : '#' + index;
    }

    function optionLabel(list, value) {
        const o = list.find((x) => x.value === value);
        return o ? o.label : '';
    }

    function neonChanged(a, b) {
        const anyOn = NEON_SIDES.some((s) => a.enabled[s]);
        if (NEON_SIDES.some((s) => a.enabled[s] !== b.enabled[s])) return true;
        if (!anyOn) return false;
        return a.colour.r !== b.colour.r || a.colour.g !== b.colour.g || a.colour.b !== b.colour.b;
    }

    function xenonChanged(a, b) {
        if (a.enabled !== b.enabled) return true;
        return a.enabled && a.colour !== b.colour;
    }

    function computeCart() {
        const d = T.data;
        const items = [];

        d.cosmetic.forEach((c) => {
            if (T.cur.mods[c.id] === T.orig.mods[c.id]) return;
            const opt = optionLabel(c.options, T.cur.mods[c.id]);
            items.push({
                key: 'mod:' + c.id, tab: 'cosmetic', label: c.label, detail: opt, price: c.price,
                changes: [{ type: 'mod', id: c.id, value: T.cur.mods[c.id], label: c.label + ': ' + opt, price: c.price }],
            });
        });

        const paintChanges = PAINT_KEYS.filter(([k]) => T.cur.paint[k] !== T.orig.paint[k]);
        if (paintChanges.length) {
            items.push({
                key: 'paint', tab: 'paint', label: t('ui_paint'), price: d.paint.price,
                detail: paintChanges.map(([k]) => colourName(T.cur.paint[k])).join(' / '),
                changes: paintChanges.map(([k], i) => ({
                    type: 'paint', id: k, value: T.cur.paint[k], label: t('ui_paint'), price: i === 0 ? d.paint.price : 0,
                })),
            });
        }

        const ex = d.extras;
        if (T.cur.windowTint !== T.orig.windowTint) {
            const o = optionLabel(ex.windowTint.options, T.cur.windowTint);
            items.push({
                key: 'extra:windowTint', tab: 'extras', label: t('ui_window_tint'), detail: o, price: ex.windowTint.price,
                changes: [{ type: 'extra', id: 'windowTint', value: T.cur.windowTint, label: t('ui_window_tint'), price: ex.windowTint.price }],
            });
        }
        if (xenonChanged(T.cur.xenon, T.orig.xenon)) {
            items.push({
                key: 'extra:xenon', tab: 'extras', label: t('ui_xenon'), price: ex.xenon.price,
                detail: T.cur.xenon.enabled ? t('ui_enabled') : t('ui_stock'),
                changes: [{ type: 'extra', id: 'xenon', value: clone(T.cur.xenon), label: t('ui_xenon'), price: ex.xenon.price }],
            });
        }
        if (neonChanged(T.cur.neon, T.orig.neon)) {
            const on = NEON_SIDES.filter((s) => T.cur.neon.enabled[s]).length;
            items.push({
                key: 'extra:neon', tab: 'extras', label: t('ui_neon'), price: ex.neon.price,
                detail: on ? rgbToHex(T.cur.neon.colour) + '  x' + on : t('ui_stock'),
                changes: [{ type: 'extra', id: 'neon', value: clone(T.cur.neon), label: t('ui_neon'), price: ex.neon.price }],
            });
        }
        if (T.cur.plate !== T.orig.plate) {
            items.push({
                key: 'extra:plate', tab: 'extras', label: t('ui_plate'), price: ex.plate.price,
                detail: optionLabel(ex.plate.options, T.cur.plate),
                changes: [{ type: 'extra', id: 'plate', value: T.cur.plate, label: t('ui_plate'), price: ex.plate.price }],
            });
        }
        return items;
    }

    function refreshCart() {
        T.cart = computeCart();
        const list = $('#c-list');
        list.replaceChildren();
        let total = 0;
        T.cart.forEach((item) => {
            total += item.price;
            const li = el('li', 'cart-item');
            const txt = el('div', 'ci-text');
            txt.append(el('span', 'ci-label', item.label));
            if (item.detail) txt.append(el('span', 'ci-detail', item.detail));
            const price = el('span', 'ci-price', money(item.price));
            const rm = el('button', 'icon-btn tiny');
            rm.type = 'button';
            rm.setAttribute('aria-label', t('ui_cancel'));
            rm.append(icon('close'));
            rm.addEventListener('click', () => revertEntry(item));
            li.append(txt, price, rm);
            list.append(li);
        });
        $('#c-empty').hidden = T.cart.length > 0;
        list.hidden = T.cart.length === 0;
        $('#c-count').textContent = T.cart.length ? String(T.cart.length) : '';
        $('#c-total').textContent = money(total);
        $('#t-install').disabled = T.cart.length === 0 || T.busy;
        updateTabBadges();
    }

    function updateTabBadges() {
        $$('.tab', $('#t-tabs')).forEach((tab) => {
            const n = T.cart.filter((i) => i.tab === tab.dataset.tab).length;
            const badge = $('.badge', tab);
            badge.hidden = n === 0;
            badge.textContent = n ? String(n) : '';
        });
    }

    function revertEntry(item) {
        const o = T.orig;
        if (item.key.startsWith('mod:')) {
            const id = item.key.slice(4);
            T.cur.mods[id] = o.mods[id];
            sendPreview('mod', id, o.mods[id]);
        } else if (item.key === 'paint') {
            item.changes.forEach((c) => {
                T.cur.paint[c.id] = o.paint[c.id];
                sendPreview('paint', c.id, o.paint[c.id]);
            });
        } else if (item.key === 'extra:windowTint') {
            T.cur.windowTint = o.windowTint;
            sendPreview('extra', 'windowTint', o.windowTint);
        } else if (item.key === 'extra:plate') {
            T.cur.plate = o.plate;
            sendPreview('extra', 'plate', o.plate);
        } else if (item.key === 'extra:xenon') {
            T.cur.xenon = clone(o.xenon);
            sendPreview('extra', 'xenon', clone(o.xenon));
        } else if (item.key === 'extra:neon') {
            T.cur.neon = clone(o.neon);
            sendPreview('extra', 'neon', clone(o.neon));
        }
        refreshCart();
        refreshTab();
    }

    // ---- tab body --------------------------------------------------------

    function refreshTab(focusSel) {
        const top = tBody.scrollTop;
        const builders = { performance: buildPerformance, cosmetic: buildCosmetic, paint: buildPaint, extras: buildExtras };
        tBody.replaceChildren(builders[T.tab]());
        tBody.scrollTop = top;
        if (focusSel) {
            const f = tBody.querySelector(focusSel);
            if (f) f.focus({ preventScroll: false });
        }
    }

    function setTab(tab, focus) {
        if (!TABS.includes(tab)) return;
        T.tab = tab;
        $$('.tab', $('#t-tabs')).forEach((b) => {
            const on = b.dataset.tab === tab;
            b.setAttribute('aria-selected', on ? 'true' : 'false');
            b.tabIndex = on ? 0 : -1;
        });
        tBody.scrollTop = 0;
        refreshTab();
        if (focus) {
            const first = $('.card', tBody);
            if (first) first.focus({ preventScroll: true });
        }
    }

    const fk = (s) => '[data-fk="' + String(s).replace(/"/g, '\\"') + '"]';

    // ---- Performance tab ----------------------------------------------------

    function levelLabel(cat, level) {
        const o = cat.options.find((x) => x.level === level);
        return o ? o.label : '';
    }

    function selectableLevels(cat) {
        if (!T.data.vehicle.owned) return [];
        return cat.options.filter((o) => o.level !== cat.current && (o.level === 0 || o.hasItem)).map((o) => o.level);
    }

    function buildPerformance() {
        const d = T.data;
        const root = el('div', 'stack');

        if (!d.vehicle.owned) {
            const warn = el('div', 'notice');
            warn.append(icon('close', 'bad'), el('span', null, t('ui_not_owned')));
            root.append(warn);
        }

        d.performance.forEach((cat) => {
            const card = el('div', 'card perf');
            card.tabIndex = 0;
            card.dataset.fk = 'card:' + cat.id;
            if (!d.vehicle.owned) card.classList.add('locked');

            const head = el('div', 'card-head');
            head.append(el('h3', 'card-title', cat.label));
            const cur = el('span', 'pill good');
            cur.append(el('span', 'pill-k', t('ui_installed')), el('span', 'pill-v', levelLabel(cat, cat.current)));
            head.append(cur);
            card.append(head);

            const list = el('div', 'levels');
            list.setAttribute('role', 'radiogroup');
            list.setAttribute('aria-label', cat.label);
            cat.options.forEach((o) => {
                const isCur = o.level === cat.current;
                const isSel = !!T.sel && T.sel.category === cat.id && T.sel.level === o.level;
                const missing = o.level !== 0 && !o.hasItem;
                const b = el('button', 'lvl');
                b.type = 'button';
                b.dataset.fk = 'lvl:' + cat.id + ':' + o.level;
                b.setAttribute('role', 'radio');
                b.setAttribute('aria-checked', isSel || (isCur && !T.sel) ? 'true' : 'false');
                if (isCur) b.classList.add('current');
                if (isSel) b.classList.add('selected');
                const blocked = !d.vehicle.owned || isCur || missing;
                b.disabled = blocked && !isCur;
                if (isCur) b.setAttribute('aria-disabled', 'true');

                const main = el('div', 'lvl-main');
                main.append(el('span', 'lvl-name', o.label));
                if (o.item) main.append(el('span', 'lvl-item', o.item));
                else if (o.level === 0 && cat.current !== 0) main.append(el('span', 'lvl-item', t('ui_remove')));
                b.append(main);

                const state = el('span', 'lvl-state');
                if (isCur) {
                    state.classList.add('good');
                    state.append(icon('check'), el('span', null, t('ui_installed')));
                } else if (missing) {
                    state.classList.add('muted');
                    state.append(el('span', null, t('ui_no_item')));
                } else if (isSel) {
                    state.classList.add('acc');
                    state.append(icon('swap'));
                }
                b.append(state);

                if (!isCur && !blocked) {
                    b.addEventListener('click', () => {
                        T.sel = isSel ? null : { category: cat.id, level: o.level };
                        refreshTab(fk('lvl:' + cat.id + ':' + o.level));
                    });
                }
                list.append(b);
            });
            card.append(list);

            if (T.sel && T.sel.category === cat.id) {
                const bar = el('div', 'confirm');
                const txt = el('div', 'confirm-text');
                txt.append(
                    el('span', 'from', levelLabel(cat, cat.current)),
                    icon('right', 'arrow'),
                    el('span', 'to', levelLabel(cat, T.sel.level))
                );
                const actions = el('div', 'confirm-actions');
                const no = el('button', 'btn ghost small', t('ui_cancel'));
                no.type = 'button';
                no.addEventListener('click', () => { T.sel = null; refreshTab(fk('card:' + cat.id)); });
                const yes = el('button', 'btn primary small', T.sel.level === 0 ? t('ui_remove') : t('ui_swap'));
                yes.type = 'button';
                yes.dataset.fk = 'confirm:' + cat.id;
                yes.addEventListener('click', confirmSwap);
                actions.append(no, yes);
                bar.append(txt, actions);
                card.append(bar);
            }

            card.__step = (dir) => {
                const levels = selectableLevels(cat);
                if (!levels.length) return;
                const at = T.sel && T.sel.category === cat.id ? levels.indexOf(T.sel.level) : -1;
                const next = at === -1 ? (dir > 0 ? 0 : levels.length - 1) : (at + dir + levels.length) % levels.length;
                T.sel = { category: cat.id, level: levels[next] };
                refreshTab(fk('card:' + cat.id));
            };
            card.__enter = () => { if (T.sel && T.sel.category === cat.id) confirmSwap(); };

            root.append(card);
        });
        return root;
    }

    async function confirmSwap() {
        if (!T.sel || T.busy || !T.data.vehicle.owned) return;
        T.busy = true;
        $('#t-install').disabled = true;
        const res = await post('tuning:swap', { category: T.sel.category, level: T.sel.level });
        T.busy = false;
        if (res && res.ok) {
            hideTuning();
        } else {
            shake($('.confirm', tBody) || tBody);
            refreshCart();
        }
    }

    function shake(node) {
        node.classList.remove('shake');
        void node.offsetWidth;
        node.classList.add('shake');
    }

    // ---- Cosmetic tab -------------------------------------------------------

    function buildCosmetic() {
        const root = el('div', 'stack');
        T.data.cosmetic.forEach((c) => root.append(cosmeticCard(c)));
        return root;
    }

    function cosmeticCard(c) {
        const card = el('div', 'card cos');
        card.tabIndex = 0;
        card.dataset.fk = 'card:' + c.id;

        const head = el('div', 'card-head');
        head.append(el('h3', 'card-title', c.label), el('span', 'price', money(c.price)));
        card.append(head);

        const stepper = el('div', 'stepper');
        const prev = el('button', 'icon-btn'); prev.type = 'button'; prev.tabIndex = -1;
        prev.setAttribute('aria-label', c.label); prev.append(icon('left'));
        const next = el('button', 'icon-btn'); next.type = 'button'; next.tabIndex = -1;
        next.setAttribute('aria-label', c.label); next.append(icon('right'));
        const mid = el('button', 'stepper-mid'); mid.type = 'button'; mid.tabIndex = -1;
        mid.setAttribute('aria-expanded', 'false');
        const midName = el('span', 'mid-name');
        const midCount = el('span', 'mid-count');
        mid.append(midName, midCount, icon('down', 'chev'));
        stepper.append(prev, mid, next);
        card.append(stepper);

        const listWrap = el('div', 'opt-list');
        listWrap.hidden = true;
        listWrap.setAttribute('role', 'listbox');
        card.append(listWrap);

        let built = false;
        const idxOf = () => Math.max(0, c.options.findIndex((o) => o.value === T.cur.mods[c.id]));

        function paint() {
            const idx = idxOf();
            midName.textContent = c.options[idx] ? c.options[idx].label : '';
            midCount.textContent = (idx + 1) + ' / ' + c.options.length;
            card.classList.toggle('changed', T.cur.mods[c.id] !== T.orig.mods[c.id]);
            if (built) {
                $$('.opt', listWrap).forEach((b, i) => {
                    const on = i === idx;
                    b.classList.toggle('selected', on);
                    b.setAttribute('aria-selected', on ? 'true' : 'false');
                });
            }
        }

        function choose(index) {
            const o = c.options[index];
            if (!o || o.value === T.cur.mods[c.id]) return;
            T.cur.mods[c.id] = o.value;
            sendPreview('mod', c.id, o.value);
            paint();
            refreshCart();
        }

        function step(dir) {
            const n = c.options.length;
            if (n < 2) return;
            choose((idxOf() + dir + n) % n);
        }

        function buildList() {
            c.options.forEach((o, i) => {
                const b = el('button', 'opt');
                b.type = 'button';
                b.setAttribute('role', 'option');
                b.append(el('span', 'opt-name', o.label), el('span', 'opt-idx', i === 0 && o.value === -1 ? '' : String(i)));
                b.addEventListener('click', () => choose(i));
                listWrap.append(b);
            });
            built = true;
        }

        function toggleList() {
            const open = listWrap.hidden;
            if (open && !built) buildList();
            listWrap.hidden = !open;
            mid.setAttribute('aria-expanded', open ? 'true' : 'false');
            card.classList.toggle('open', open);
            paint();
            if (open) {
                const sel = $('.opt.selected', listWrap);
                if (sel) sel.scrollIntoView({ block: 'nearest' });
            }
        }

        prev.addEventListener('click', () => step(-1));
        next.addEventListener('click', () => step(1));
        mid.addEventListener('click', toggleList);
        card.__step = step;
        card.__enter = toggleList;
        paint();
        return card;
    }

    // ---- Paint tab ----------------------------------------------------------

    function buildPaint() {
        const d = T.data;
        const root = el('div', 'stack');

        const sum = el('div', 'tab-sum');
        sum.append(el('span', null, t('ui_paint')), el('span', 'price', money(d.paint.price)));
        root.append(sum);

        PAINT_KEYS.forEach(([key, labelKey]) => {
            const card = el('div', 'card paint');
            const head = el('div', 'card-head');
            const name = el('span', 'pill');
            const nameV = el('span', 'pill-v');
            name.append(nameV);
            head.append(el('h3', 'card-title', t(labelKey)), name);
            card.append(head);

            const grid = el('div', 'swatches');
            grid.setAttribute('role', 'radiogroup');
            grid.setAttribute('aria-label', t(labelKey));

            const paintHead = () => {
                nameV.textContent = colourName(T.cur.paint[key]);
                card.classList.toggle('changed', T.cur.paint[key] !== T.orig.paint[key]);
            };

            d.paint.colours.forEach((col) => {
                const b = el('button', 'swatch');
                b.type = 'button';
                b.dataset.index = String(col.index);
                b.setAttribute('role', 'radio');
                b.setAttribute('aria-label', col.label);
                b.title = col.label;
                b.style.setProperty('--sw', col.hex);
                const on = T.cur.paint[key] === col.index;
                b.classList.toggle('selected', on);
                b.setAttribute('aria-checked', on ? 'true' : 'false');
                b.addEventListener('click', () => {
                    T.cur.paint[key] = col.index;
                    sendPreview('paint', key, col.index);
                    $$('.swatch', grid).forEach((s) => {
                        const sel = s === b;
                        s.classList.toggle('selected', sel);
                        s.setAttribute('aria-checked', sel ? 'true' : 'false');
                    });
                    paintHead();
                    refreshCart();
                });
                grid.append(b);
            });
            paintHead();
            card.append(grid);
            root.append(card);
        });
        return root;
    }

    // ---- Extras tab ---------------------------------------------------------

    function chipsCard(titleKey, price, options, getCur, setCur, previewId) {
        const card = el('div', 'card chipcard');
        card.tabIndex = 0;
        card.dataset.fk = 'card:' + previewId;
        const head = el('div', 'card-head');
        head.append(el('h3', 'card-title', t(titleKey)), el('span', 'price', money(price)));
        card.append(head);

        const row = el('div', 'chips');
        row.setAttribute('role', 'radiogroup');
        row.setAttribute('aria-label', t(titleKey));

        const paint = () => {
            $$('.chip', row).forEach((b) => {
                const on = int(b.dataset.value) === getCur();
                b.classList.toggle('selected', on);
                b.setAttribute('aria-checked', on ? 'true' : 'false');
            });
            card.classList.toggle('changed', getCur() !== setCur.orig());
        };
        const choose = (value) => {
            if (value === getCur()) return;
            setCur(value);
            sendPreview('extra', previewId, value);
            paint();
            refreshCart();
        };
        options.forEach((o) => {
            const b = el('button', 'chip', o.label);
            b.type = 'button';
            b.dataset.value = String(o.value);
            b.setAttribute('role', 'radio');
            b.addEventListener('click', () => choose(o.value));
            row.append(b);
        });
        card.append(row);
        card.__step = (dir) => {
            if (options.length < 2) return;
            const i = Math.max(0, options.findIndex((o) => o.value === getCur()));
            choose(options[(i + dir + options.length) % options.length].value);
        };
        paint();
        return card;
    }

    function buildExtras() {
        const ex = T.data.extras;
        const root = el('div', 'stack');

        root.append(chipsCard('ui_window_tint', ex.windowTint.price, ex.windowTint.options,
            () => T.cur.windowTint,
            Object.assign((v) => { T.cur.windowTint = v; }, { orig: () => T.orig.windowTint }),
            'windowTint'));

        root.append(xenonCard(ex.xenon));
        root.append(neonCard(ex.neon));

        root.append(chipsCard('ui_plate', ex.plate.price, ex.plate.options,
            () => T.cur.plate,
            Object.assign((v) => { T.cur.plate = v; }, { orig: () => T.orig.plate }),
            'plate'));
        return root;
    }

    function xenonCard(xe) {
        const card = el('div', 'card xenon');
        card.tabIndex = 0;
        card.dataset.fk = 'card:xenon';
        const head = el('div', 'card-head');
        const sw = makeSwitch(T.cur.xenon.enabled, (v) => { T.cur.xenon.enabled = v; commit(); }, 'ui_enabled');
        head.append(el('h3', 'card-title', t('ui_xenon')), el('span', 'price', money(xe.price)));
        card.append(head);
        const line = el('div', 'row-between');
        line.append(sw);
        card.append(line);

        const grid = el('div', 'swatches small');
        grid.setAttribute('role', 'radiogroup');
        grid.setAttribute('aria-label', t('ui_xenon'));
        XENON_COLOURS.forEach((hex, i) => {
            const b = el('button', 'swatch');
            b.type = 'button';
            b.dataset.index = String(i);
            b.setAttribute('role', 'radio');
            b.setAttribute('aria-label', hex);
            b.style.setProperty('--sw', hex);
            b.addEventListener('click', () => {
                T.cur.xenon.colour = i;
                // Picking a colour turns the lights on
                T.cur.xenon.enabled = true;
                commit();
            });
            grid.append(b);
        });
        card.append(grid);

        function paint() {
            sw.setChecked(T.cur.xenon.enabled);
            grid.classList.toggle('dim', !T.cur.xenon.enabled);
            $$('.swatch', grid).forEach((b) => {
                const on = int(b.dataset.index) === T.cur.xenon.colour;
                b.classList.toggle('selected', on);
                b.setAttribute('aria-checked', on ? 'true' : 'false');
            });
            card.classList.toggle('changed', xenonChanged(T.cur.xenon, T.orig.xenon));
        }
        function commit() {
            sendPreview('extra', 'xenon', clone(T.cur.xenon));
            paint();
            refreshCart();
        }
        card.__step = (dir) => {
            const cur = T.cur.xenon.colour;
            const at = cur >= 0 && cur < XENON_COLOURS.length ? cur : (dir > 0 ? -1 : 0);
            T.cur.xenon.colour = (at + dir + XENON_COLOURS.length) % XENON_COLOURS.length;
            T.cur.xenon.enabled = true;
            commit();
        };
        card.__enter = () => { T.cur.xenon.enabled = !T.cur.xenon.enabled; commit(); };
        paint();
        return card;
    }

    function neonCard(ne) {
        const card = el('div', 'card neon');
        card.tabIndex = 0;
        card.dataset.fk = 'card:neon';
        const head = el('div', 'card-head');
        head.append(el('h3', 'card-title', t('ui_neon')), el('span', 'price', money(ne.price)));
        card.append(head);

        const allOn = () => NEON_SIDES.every((s) => T.cur.neon.enabled[s]);
        const anyOn = () => NEON_SIDES.some((s) => T.cur.neon.enabled[s]);

        const sw = makeSwitch(anyOn(), (v) => {
            NEON_SIDES.forEach((s) => { T.cur.neon.enabled[s] = v; });
            commit();
        }, 'ui_enabled');

        const body = el('div', 'neon-body');
        const diagram = el('div', 'neon-diagram');
        const car = el('div', 'neon-car');
        car.innerHTML = '<svg viewBox="0 0 60 110" aria-hidden="true"><path d="M30 6c-9 0-15 5-16 15l-2 14-4 3v14l4 2-1 24 3 12c1 6 8 9 16 9s15-3 16-9l3-12-1-24 4-2V38l-4-3-2-14C45 11 39 6 30 6z" fill="rgba(255,255,255,.07)" stroke="rgba(255,255,255,.55)" stroke-width="1.5" stroke-linejoin="round"/><path d="M20 38c3-4 7-5 10-5s7 1 10 5l-2 13H22z M22 78h16l3 10H19z" fill="rgba(255,255,255,.12)" stroke="rgba(255,255,255,.4)" stroke-width="1"/></svg>';
        diagram.append(car);
        const sideBtns = {};
        NEON_SIDES.forEach((s) => {
            const b = el('button', 'neon-side ' + s);
            b.type = 'button';
            b.setAttribute('role', 'switch');
            b.setAttribute('aria-label', t('ui_neon') + ' ' + s.toUpperCase());
            b.addEventListener('click', () => {
                T.cur.neon.enabled[s] = !T.cur.neon.enabled[s];
                commit();
            });
            sideBtns[s] = b;
            diagram.append(b);
        });

        const side = el('div', 'neon-side-col');
        const colourRow = el('label', 'colour-row');
        const picker = document.createElement('input');
        picker.type = 'color';
        picker.className = 'colour-input';
        picker.value = rgbToHex(T.cur.neon.colour);
        picker.setAttribute('aria-label', t('ui_neon'));
        const hexOut = el('span', 'hex');
        colourRow.append(picker, hexOut);
        picker.addEventListener('input', () => {
            T.cur.neon.colour = hexToRgb(picker.value);
            commit();
        });
        side.append(sw, colourRow);
        body.append(diagram, side);
        card.append(body);

        function paint() {
            const hex = rgbToHex(T.cur.neon.colour);
            card.style.setProperty('--neon', hex);
            hexOut.textContent = hex.toUpperCase();
            if (picker.value !== hex) picker.value = hex;
            NEON_SIDES.forEach((s) => {
                const on = T.cur.neon.enabled[s];
                sideBtns[s].classList.toggle('on', on);
                sideBtns[s].setAttribute('aria-checked', on ? 'true' : 'false');
            });
            sw.setChecked(anyOn());
            card.classList.toggle('changed', neonChanged(T.cur.neon, T.orig.neon));
        }
        function commit() {
            sendPreview('extra', 'neon', clone(T.cur.neon));
            paint();
            refreshCart();
        }
        card.__enter = () => {
            const v = !allOn();
            NEON_SIDES.forEach((s) => { T.cur.neon.enabled[s] = v; });
            commit();
        };
        paint();
        return card;
    }

    // ---- Camera row ---------------------------------------------------------

    function buildCameras() {
        const row = $('#t-cams');
        row.replaceChildren();
        CAMERAS.forEach((focus) => {
            const b = el('button', 'cam-btn');
            b.type = 'button';
            b.dataset.focus = focus;
            b.setAttribute('aria-label', focus);
            b.setAttribute('aria-pressed', focus === T.cam ? 'true' : 'false');
            b.append(icon(focus));
            b.addEventListener('click', () => {
                T.cam = focus;
                $$('.cam-btn', row).forEach((x) => x.setAttribute('aria-pressed', x === b ? 'true' : 'false'));
                post('tuning:camera', { focus });
            });
            row.append(b);
        });
    }

    // ---- open / close -------------------------------------------------------

    async function openTuning(raw) {
        await ensureLocale();
        T.data = normTuning(raw);
        T.orig = buildState(T.data);
        T.cur = clone(T.orig);
        T.sel = null;
        T.busy = false;
        T.cam = 'default';
        clearPreviews();

        $('#t-vehicle').textContent = T.data.vehicle.label;
        const plate = $('#t-plate');
        plate.textContent = T.data.vehicle.plate;
        plate.hidden = !T.data.vehicle.plate;

        buildCameras();
        const startTab = T.data.performance.length ? 'performance' : 'cosmetic';
        setTab(startTab);
        refreshCart();
        showLayer(tuningLayer);
        $('.panel', tuningLayer).focus({ preventScroll: true });
    }

    function hideTuning() {
        clearPreviews();
        T.sel = null;
        hideLayer(tuningLayer);
    }

    function closeTuning() {
        if (tuningLayer.hidden) return;
        hideTuning();
        post('tuning:close');
    }

    async function installTuning() {
        if (T.busy || !T.cart.length) return;
        T.busy = true;
        $('#t-install').disabled = true;
        const changes = [];
        T.cart.forEach((item) => item.changes.forEach((c) => changes.push(c)));
        clearPreviews();
        const res = await post('tuning:install', { changes });
        T.busy = false;
        if (res && res.ok) {
            hideTuning();
        } else {
            shake($('.cart', tuningLayer));
            refreshCart();
        }
    }

    // =======================================================================
    // INVOICE CREATE (mechanic)
    // =======================================================================

    const invLayer = $('#invoice');
    const I = { players: [], target: null, lines: [], maxLines: 10, maxTotal: 100000, busy: false, uid: 0 };

    const invTotal = () => I.lines.reduce((s, l) => s + (l.amount || 0), 0);

    function renderPlayers() {
        const wrap = $('#i-players');
        wrap.replaceChildren();
        I.players.forEach((p) => {
            const b = el('button', 'player');
            b.type = 'button';
            b.setAttribute('role', 'radio');
            const on = I.target === p.id;
            b.classList.toggle('selected', on);
            b.setAttribute('aria-checked', on ? 'true' : 'false');
            const initial = (p.name.trim().charAt(0) || '?').toUpperCase();
            b.append(el('span', 'avatar', initial), el('span', 'p-name', p.name), el('span', 'p-id', '#' + p.id));
            b.addEventListener('click', () => {
                I.target = p.id;
                wrap.classList.remove('invalid');
                renderPlayers();
            });
            wrap.append(b);
        });
    }

    function renderLines() {
        const wrap = $('#i-lines');
        wrap.replaceChildren();
        I.lines.forEach((line) => {
            const row = el('div', 'line');
            const label = document.createElement('input');
            label.type = 'text';
            label.maxLength = 48;
            label.value = line.label;
            label.autocomplete = 'off';
            label.setAttribute('aria-label', t('ui_line_label'));
            label.placeholder = t('ui_line_label');
            const amount = document.createElement('input');
            amount.type = 'text';
            amount.inputMode = 'numeric';
            amount.autocomplete = 'off';
            amount.className = 'amount';
            amount.value = line.amount ? String(line.amount) : '';
            amount.setAttribute('aria-label', t('ui_amount'));
            amount.placeholder = '0';
            const rm = el('button', 'icon-btn tiny');
            rm.type = 'button';
            rm.setAttribute('aria-label', t('ui_cancel'));
            rm.append(icon('trash'));

            label.addEventListener('input', () => { line.label = label.value; label.classList.remove('invalid'); });
            label.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); amount.focus(); } });
            amount.addEventListener('input', () => {
                const digits = amount.value.replace(/\D/g, '').slice(0, 9);
                let v = digits === '' ? 0 : parseInt(digits, 10);
                const others = invTotal() - (line.amount || 0);
                const allowed = Math.max(0, I.maxTotal - others);
                if (v > allowed) v = allowed;
                line.amount = v;
                const text = v ? String(v) : '';
                if (amount.value !== text) amount.value = text;
                amount.classList.remove('invalid');
                updateInvoiceTotals();
            });
            rm.addEventListener('click', () => {
                I.lines = I.lines.filter((l) => l !== line);
                if (!I.lines.length) I.lines.push(newLine());
                renderLines();
            });
            line.nodes = { label, amount };
            row.append(label, amount, rm);
            wrap.append(row);
        });
        $('#i-add').disabled = I.lines.length >= I.maxLines;
        updateInvoiceTotals();
    }

    function newLine(label, amount) {
        return { id: ++I.uid, label: label || '', amount: amount || 0 };
    }

    function updateInvoiceTotals() {
        const total = invTotal();
        $('#i-total').textContent = money(total);
        $('#i-cap').textContent = '/ ' + money(I.maxTotal);
        $('#i-meter').style.transform = 'scaleX(' + clamp(total / I.maxTotal, 0, 1) + ')';
        $('#invoice .i-total').classList.toggle('capped', total >= I.maxTotal);
    }

    async function openInvoice(raw) {
        await ensureLocale();
        raw = raw || {};
        I.maxLines = Math.max(1, int(raw.maxLines, 10));
        I.maxTotal = Math.max(1, int(raw.maxTotal, 100000));
        I.players = (Array.isArray(raw.players) ? raw.players : []).map((p) => ({ id: int(p.id), name: String(p.name ?? p.id) }));
        I.target = I.players.length === 1 ? I.players[0].id : null;
        I.busy = false;
        I.lines = [];
        (Array.isArray(raw.prefill) ? raw.prefill : []).slice(0, I.maxLines).forEach((l) => {
            const amount = clamp(int(l && l.amount), 0, I.maxTotal - invTotal());
            I.lines.push(newLine(String((l && l.label) ?? '').slice(0, 48), amount));
        });
        if (!I.lines.length) I.lines.push(newLine());

        $('#i-error').hidden = true;
        $('#i-players').classList.remove('invalid');
        $('#i-send').disabled = false;
        renderPlayers();
        renderLines();
        showLayer(invLayer);
        const first = I.lines[0].nodes && I.lines[0].label === '' ? I.lines[0].nodes.label : $('#i-send');
        $('.dialog', invLayer).focus({ preventScroll: true });
        if (first && first !== $('#i-send')) first.focus({ preventScroll: true });
    }

    function hideInvoiceCreate() {
        hideLayer(invLayer);
    }

    function cancelInvoice() {
        if (invLayer.hidden) return;
        hideInvoiceCreate();
        post('invoice:cancel');
    }

    function showInvoiceError(text) {
        const box = $('#i-error');
        box.textContent = text;
        box.hidden = !text;
    }

    async function sendInvoice() {
        if (I.busy) return;
        let valid = true;
        const lines = [];
        $('#i-players').classList.toggle('invalid', I.target === null);
        if (I.target === null) valid = false;

        I.lines.forEach((l) => {
            const label = l.label.replace(/[\u0000-\u001f\u007f]/g, '').trim();
            const blank = label === '' && !l.amount;
            if (blank) return;
            const badLabel = label === '';
            const badAmount = !(l.amount >= 1);
            if (l.nodes) {
                l.nodes.label.classList.toggle('invalid', badLabel);
                l.nodes.amount.classList.toggle('invalid', badAmount);
            }
            if (badLabel || badAmount) { valid = false; return; }
            lines.push({ label: label.slice(0, 48), amount: l.amount });
        });
        if (!lines.length) {
            valid = false;
            const first = I.lines[0];
            if (first && first.nodes) {
                first.nodes.label.classList.add('invalid');
                first.nodes.amount.classList.add('invalid');
            }
        }
        if (!valid) { shake($('.dialog', invLayer)); return; }

        I.busy = true;
        $('#i-send').disabled = true;
        showInvoiceError('');
        const res = await post('invoice:send', { target: I.target, lines });
        I.busy = false;
        $('#i-send').disabled = false;
        if (res && res.ok) {
            hideInvoiceCreate();
        } else {
            showInvoiceError((res && res.error) ? String(res.error) : t('ui_send'));
            shake($('.dialog', invLayer));
        }
    }

    // =======================================================================
    // CUSTOMER INVOICE POPUP
    // =======================================================================

    const popLayer = $('#popup');
    const P = { id: null, endAt: 0, timer: 0, busy: false };

    async function showInvoice(raw) {
        await ensureLocale();
        raw = raw || {};
        P.id = raw.id;
        P.busy = false;
        clearInterval(P.timer);

        $('#p-from').textContent = String(raw.from ?? '');
        $('#p-total').textContent = money(raw.total);
        const ul = $('#p-lines');
        ul.replaceChildren();
        (Array.isArray(raw.lines) ? raw.lines : []).forEach((l) => {
            const li = el('li');
            li.append(el('span', 'pl-label', String((l && l.label) ?? '')), el('span', 'pl-amount', money(l && l.amount)));
            ul.append(li);
        });

        // Show first: the bar transition needs a laid-out element to start from
        $('#p-error').hidden = true;
        $('#p-accept').disabled = false;
        $('#p-decline').disabled = false;
        showLayer(popLayer);

        const secs = Math.max(1, int(raw.expireSeconds, 60));
        P.endAt = Date.now() + secs * 1000;
        const bar = $('#p-bar');
        bar.style.transition = 'none';
        bar.style.transform = 'scaleX(1)';
        void bar.offsetWidth;
        bar.style.transition = 'transform ' + secs + 's linear';
        bar.style.transform = 'scaleX(0)';

        const tick = () => {
            const left = Math.max(0, Math.ceil((P.endAt - Date.now()) / 1000));
            $('#p-exp').textContent = t('ui_expires', left);
            $('#popup .popup').classList.toggle('urgent', left <= 10);
            if (left <= 0) clearInterval(P.timer);
        };
        tick();
        P.timer = setInterval(tick, 1000);

        $('#p-accept').focus({ preventScroll: true });
    }

    function hideInvoicePopup(id) {
        if (id !== undefined && id !== null && P.id !== null && id !== P.id) return;
        clearInterval(P.timer);
        P.id = null;
        hideLayer(popLayer);
    }

    async function respondInvoice(accept) {
        if (P.busy || P.id === null) return;
        P.busy = true;
        $('#p-accept').disabled = true;
        $('#p-decline').disabled = true;
        const id = P.id;
        const res = await post('invoice:respond', { id, accept });
        P.busy = false;
        if (res && res.ok) {
            hideInvoicePopup(id);
        } else if (P.id === id) {
            const box = $('#p-error');
            box.textContent = (res && res.error) ? String(res.error) : '';
            box.hidden = !box.textContent;
            $('#p-accept').disabled = false;
            $('#p-decline').disabled = false;
            shake($('#popup .popup'));
        }
    }

    // =======================================================================
    // Wiring
    // =======================================================================

    $('#t-x').append(icon('close'));
    $('#t-x').addEventListener('click', closeTuning);
    $('#t-close').addEventListener('click', closeTuning);
    $('#t-install').addEventListener('click', installTuning);
    $$('.tab', $('#t-tabs')).forEach((b) => b.addEventListener('click', () => setTab(b.dataset.tab)));

    $('#i-add').addEventListener('click', () => {
        if (I.lines.length >= I.maxLines) return;
        const line = newLine();
        I.lines.push(line);
        renderLines();
        if (line.nodes) line.nodes.label.focus();
    });
    $('#i-cancel').addEventListener('click', cancelInvoice);
    $('#i-send').addEventListener('click', sendInvoice);

    $('#p-accept').addEventListener('click', () => respondInvoice(true));
    $('#p-decline').addEventListener('click', () => respondInvoice(false));

    window.addEventListener('message', (e) => {
        const msg = e.data;
        if (!msg || typeof msg.action !== 'string') return;
        switch (msg.action) {
            case 'openTuning': openTuning(msg.data); break;
            case 'closeTuning': hideTuning(); break;
            case 'openInvoice': openInvoice(msg.data); break;
            case 'showInvoice': showInvoice(msg.data); break;
            case 'hideInvoice': hideInvoicePopup(msg.data ? msg.data.id : null); break;
            default: break;
        }
    });

    // ---- keyboard ------------------------------------------------------------

    function focusables(list, current, dir) {
        const i = list.indexOf(current);
        return list[clamp((i === -1 ? (dir > 0 ? -1 : list.length) : i) + dir, 0, list.length - 1)];
    }

    tBody.addEventListener('keydown', (e) => {
        const target = e.target;
        if (target.matches && target.matches('input')) return;
        const card = target.closest ? target.closest('.card') : null;

        if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') {
            const dir = e.key === 'ArrowRight' ? 1 : -1;
            if (target.classList.contains('swatch')) {
                const grid = target.parentElement;
                const all = $$('.swatch', grid);
                const next = focusables(all, target, dir);
                if (next) { next.focus(); e.preventDefault(); }
            } else if (card && card.__step) {
                card.__step(dir);
                e.preventDefault();
            }
        } else if (e.key === 'ArrowUp' || e.key === 'ArrowDown') {
            const dir = e.key === 'ArrowDown' ? 1 : -1;
            if (target.classList.contains('swatch')) {
                const grid = target.parentElement;
                const all = $$('.swatch', grid);
                const firstTop = all[0].offsetTop;
                const cols = all.filter((s) => s.offsetTop === firstTop).length || 1;
                const at = all.indexOf(target) + dir * cols;
                if (at >= 0 && at < all.length) all[at].focus();
                else {
                    const cards = $$('.card', tBody);
                    const nxt = focusables(cards, card, dir);
                    if (nxt) nxt.focus();
                }
                e.preventDefault();
            } else if (target.classList.contains('opt')) {
                const opts = $$('.opt', card);
                const nxt = focusables(opts, target, dir);
                if (nxt) nxt.focus();
                e.preventDefault();
            } else {
                const cards = $$('.card', tBody);
                const nxt = focusables(cards, card, dir);
                if (nxt) { nxt.focus(); e.preventDefault(); }
            }
        } else if (e.key === 'Enter' && target === card && card.__enter) {
            card.__enter();
            e.preventDefault();
        }
    });

    window.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            // The customer popup never closes on Escape; invoice create has priority over tuning
            if (isShown(invLayer)) { e.preventDefault(); cancelInvoice(); }
            else if (isShown(tuningLayer)) { e.preventDefault(); closeTuning(); }
            else if (isShown(popLayer)) e.preventDefault();
            return;
        }
        if (isShown(tuningLayer) && !isShown(invLayer) && (e.key === 'PageDown' || e.key === 'PageUp')) {
            const at = TABS.indexOf(T.tab);
            const dir = e.key === 'PageDown' ? 1 : -1;
            setTab(TABS[(at + dir + TABS.length) % TABS.length]);
            e.preventDefault();
        }
        if (isShown(invLayer) && e.key === 'Enter' && e.ctrlKey) {
            e.preventDefault();
            sendInvoice();
        }
    });

    // =======================================================================
    // Dev mode (page opened outside FiveM)
    // =======================================================================

    function devPost(name, body) {
        console.debug('[dev] POST', name, body);
        if (name === 'locale') return Promise.resolve(DEMO_LOCALE);
        if (name === 'invoice:send' && window.__demoFail) return Promise.resolve({ ok: false, error: 'Customer is too far away.' });
        if (name === 'invoice:respond' && window.__demoFail) return Promise.resolve({ ok: false, error: 'Not enough money in your bank account.' });
        return Promise.resolve({ ok: true });
    }

    const DEMO_LOCALE = {
        ui_tuning_title: 'Vehicle tuning', ui_performance: 'Performance', ui_cosmetic: 'Cosmetic', ui_paint: 'Paint',
        ui_extras: 'Extras', ui_stock: 'Stock', ui_level: 'Level %s', ui_installed: 'Installed',
        ui_no_item: 'No item', ui_swap: 'Swap part', ui_remove: 'Remove to stock', ui_install: 'Install',
        ui_cart: 'Work order', ui_total: 'Total', ui_close: 'Close', ui_primary: 'Primary', ui_secondary: 'Secondary',
        ui_pearl: 'Pearlescent', ui_wheel_colour: 'Wheel colour', ui_window_tint: 'Window tint', ui_xenon: 'Xenon lights',
        ui_neon: 'Neon', ui_plate: 'Plate style', ui_enabled: 'Enabled', ui_not_owned: 'This vehicle is not owned by a player, performance parts cannot be swapped.',
        ui_invoice_title: 'New invoice', ui_customer: 'Customer', ui_line_label: 'Description', ui_amount: 'Amount',
        ui_add_line: 'Add line', ui_send: 'Send invoice', ui_cancel: 'Cancel', ui_invoice_from: 'Invoice from',
        ui_accept: 'Accept and pay', ui_decline: 'Decline', ui_expires: 'Expires in %s seconds', ui_camera: 'Camera',
        ui_empty_cart: 'No changes yet',
    };

    function demoTuning() {
        const lvl = (cat, n, haveUpTo, itemPrefix) => {
            const opts = [{ level: 0, label: 'Stock' }];
            for (let i = 1; i <= n; i++) opts.push({ level: i, label: 'Level ' + i, item: itemPrefix + '_lvl' + i, hasItem: i <= haveUpTo || i === 1 });
            return opts;
        };
        const names = ['Stock', 'Carbon', 'Street', 'Sport', 'Race', 'GT Wing', 'Ducktail', 'Low Profile', 'Aggressive', 'Slim', 'Wide', 'Tuner'];
        const mod = (id, label, price, count, current) => ({
            id, label, price, current,
            options: [{ value: -1, label: 'Stock' }].concat(Array.from({ length: count }, (_, i) => ({ value: i, label: (names[(i + 1) % names.length]) + ' ' + label.split(' ')[0] + ' ' + (i + 1) }))),
        });
        const colours = [
            ['Metallic Black', '#0d1116', 0], ['Metallic Graphite', '#1c1d21', 1], ['Metallic Silver', '#99a1a8', 4], ['Metallic White', '#fffff6', 111],
            ['Metallic Red', '#c00e1a', 27], ['Metallic Candy Red', '#b6111b', 35], ['Metallic Orange', '#f78616', 38], ['Metallic Yellow', '#ffcf20', 88],
            ['Metallic Green', '#155c2d', 53], ['Lime Green', '#66b81f', 55], ['Metallic Blue', '#47578f', 64], ['Ultra Blue', '#0b9cf1', 70],
            ['Metallic Purple', '#621276', 145], ['Metallic Pink', '#df5891', 137], ['Matte Black', '#13181f', 12], ['Matte White', '#fcf9f1', 131],
            ['Chrome', '#b1b1b1', 120], ['Pure Gold', '#7a5f2c', 158],
        ].map(([label, hex, index]) => ({ index, label, hex }));
        return {
            vehicle: { label: 'Karin Sultan RS', plate: 'LS 4821', owned: !window.__demoNotOwned },
            performance: [
                { id: 'engine', label: 'Engine', current: 2, options: lvl('engine', 4, 2, 'engine') },
                { id: 'brakes', label: 'Brakes', current: 0, options: lvl('brakes', 3, 3, 'brakes') },
                { id: 'transmission', label: 'Transmission', current: 1, options: lvl('transmission', 3, 1, 'transmission') },
                { id: 'suspension', label: 'Suspension', current: 0, options: lvl('suspension', 4, 4, 'suspension') },
                { id: 'armor', label: 'Armor', current: 0, options: lvl('armor', 5, 2, 'armor') },
                { id: 'turbo', label: 'Turbo', current: 0, options: [{ level: 0, label: 'Stock' }, { level: 1, label: 'Turbo', item: 'turbo', hasItem: true }] },
            ],
            cosmetic: [
                mod('modSpoilers', 'Spoiler', 1500, 9, 2),
                mod('modFrontBumper', 'Front bumper', 1500, 6, -1),
                mod('modRearBumper', 'Rear bumper', 1500, 5, 1),
                mod('modSideSkirt', 'Side skirts', 1200, 4, -1),
                mod('modExhaust', 'Exhaust', 1000, 5, -1),
                mod('modGrille', 'Grille', 800, 7, 0),
                mod('modHood', 'Hood', 1500, 8, -1),
                mod('modRoof', 'Roof', 1200, 3, -1),
                mod('modHorns', 'Horn', 500, 40, -1),
                mod('modFrontWheels', 'Wheels', 2000, 60, 4),
            ],
            paint: { colours, current: { color1: 27, color2: 0, pearlescentColor: 111, wheelColor: 4 }, price: 2500 },
            extras: {
                windowTint: { current: 0, price: 800, options: ['None', 'Pure Black', 'Dark Smoke', 'Light Smoke', 'Stock', 'Limo', 'Green'].map((label, value) => ({ value, label })) },
                xenon: { enabled: false, colour: 255, price: 1500 },
                neon: { enabled: { l: false, r: false, f: false, b: false }, colour: { r: 255, g: 255, b: 255 }, price: 3000 },
                plate: { current: 0, price: 300, options: ['Blue on White 1', 'Yellow on Black', 'Yellow on Blue', 'Blue on White 2', 'Blue on White 3', 'San Andreas'].map((label, value) => ({ value, label })) },
            },
        };
    }

    if (DEV) {
        window.__demo = (view, tab) => {
            const all = !view || view === 'all';
            if (all || view === 'tuning') {
                window.postMessage({ action: 'openTuning', data: demoTuning() }, '*');
                if (tab && TABS.includes(tab)) localeReady.then(() => setTimeout(() => setTab(tab), 30));
            }
            if (all || view === 'invoice') {
                window.postMessage({
                    action: 'openInvoice',
                    data: {
                        players: [{ id: 3, name: 'Marcus Holm' }, { id: 7, name: 'Sofie Lindberg' }, { id: 12, name: 'Jonas K.' }],
                        prefill: [{ label: 'Spoiler: Carbon Spoiler 2', amount: 1500 }, { label: 'Paint', amount: 2500 }],
                        maxLines: 10, maxTotal: 100000,
                    },
                }, '*');
            }
            if (all || view === 'popup') {
                window.postMessage({
                    action: 'showInvoice',
                    data: {
                        id: 41, from: 'Mikkel Jensen',
                        lines: [{ label: 'Engine swap, Level 3', amount: 12000 }, { label: 'Brake upgrade', amount: 4500 }, { label: 'Labour', amount: 800 }],
                        total: 17300, expireSeconds: 60,
                    },
                }, '*');
            }
        };
    }
    // Fetch the locale exactly once at load
    localeReady = loadLocale();
})();
