/* Tuning screen (NUI side of contract section 6 + v3 B4/B6/C). Builds all DOM inside #tuning-root.
 *
 * Lua -> NUI:  openTuning { mode, manualSwap, vehicle = { label, plate, owned, plateIndex, plateStyle },
 *                           groups, lastCart?, workOrder? }
 *              closeTuning {}, tuning:suspend { on }
 * NUI -> Lua:  tuning:preview, tuning:camera, tuning:orbit, tuning:zoom, tuning:close { changes, swaps },
 *              tuning:install { changes, swaps }, tuning:swap, tuning:order, tuning:loadLast,
 *              tuning:presets, tuning:presetApply, tuning:presetSave, tuning:presetDelete,
 *              tuning:workorderLoad, tuning:workorderSend
 *
 * Modes: 'mechanic' (install, swap, order) and 'design' (customer terminal: preview only, prices are
 * estimates, performance levels are wishes, main action "Send til mekaniker").
 *
 * All dynamic text goes through textContent (App.el). Lua is never trusted for shapes: the payload is
 * normalised first. Chrome 103: no :has(), color-mix(), nesting.
 */
(function () {
    'use strict';

    const root = document.getElementById('tuning-root');
    if (!root || !window.App) return;

    const el = App.el;

    // ---------------------------------------------------------------------------------------------
    // Strings: App.t() returns the key when the locale lacks it, so every key has a Danish fallback.
    // ---------------------------------------------------------------------------------------------

    const FALLBACK = {
        ui_stock: 'Standard',
        ui_installed: 'Monteret',
        ui_install: 'Monter',
        ui_cart: 'Kurv',
        ui_total: 'I alt',
        ui_close: 'Luk',
        ui_back: 'Tilbage',
        ui_cancel: 'Annuller',
        ui_empty_cart: 'Kurven er tom. Vælg en ændring for at se den på bilen.',
        ui_not_owned: 'Bilen har ingen ejer: ændringer gemmes ikke, og dele kan ikke skiftes.',
        ui_order: 'Bestil',
        ui_ordered: 'Bestilt',
        ui_ordering: 'Bestiller...',
        ui_eta: 'ca. %s min',
        ui_stock_count: '%s på lager',
        ui_out_of_stock: 'Ikke på lager',
        ui_order_failed: 'Kunne ikke bestille. Prøv igen.',
        ui_swap_confirm: 'Skift %s til %s?',
        ui_swap_discard: 'Det, der ligger i kurven, bliver ikke monteret.',
        ui_swap_manual: 'Du skifter delen selv, trin for trin.',
        ui_swap_now: 'Skift nu',
        ui_add_to_cart: 'Læg i kurv',
        ui_in_cart: 'I kurven',
        ui_on: 'Til',
        ui_off: 'Fra',
        ui_search: 'Søg',
        ui_no_match: 'Ingen resultater.',
        ui_empty_list: 'Ingen muligheder.',
        ui_pick_colour: 'Vælg farve',
        ui_undo: 'Fortryd',
        ui_groups: 'Kategorier',
        ui_changed: '%s ændret',
        ui_drag_hint: 'Træk for at dreje',
        ui_zoom_hint: 'Rul for at zoome',
        ui_cam_default: 'Overblik',
        ui_cam_front: 'Front',
        ui_cam_rear: 'Bagende',
        ui_cam_wheel: 'Hjul',
        ui_cam_engine: 'Motor',
        ui_cam_side: 'Side',
        ui_cam_interior: 'Kabine',
        ui_plate: 'Nummerplade %s',
        ui_price: 'Pris %s',
        ui_estimate: 'ca. %s',
        ui_estimate_total: 'Anslået pris',
        ui_from_stock: 'Fra lageret',
        ui_needs_stock: 'Mangler på lager',
        ui_wish: 'Ønske',
        ui_send_mechanic: 'Send til mekaniker',
        ui_design_note: 'Prøv ændringer på din bil. Priserne er anslåede.',
        ui_presets: 'Presets',
        ui_presets_builtin: 'Faste',
        ui_presets_mine: 'Mine',
        ui_presets_empty: 'Ingen presets til denne model endnu. Gem kurven som preset for at bruge den igen.',
        ui_presets_loading: 'Henter presets...',
        ui_presets_error: 'Presets kunne ikke hentes.',
        ui_retry: 'Prøv igen',
        ui_preset_apply: 'Brug',
        ui_preset_delete: 'Slet',
        ui_preset_delete_confirm: 'Slet "%s"? Det kan ikke fortrydes.',
        ui_preset_keep: 'Behold',
        ui_preset_save: 'Gem som preset',
        ui_preset_model: 'Kun til denne model',
        ui_workorder_title: 'Kundens ønske',
        ui_workorder_text: '%s · %s ændringer',
        ui_load: 'Indlæs',
        ui_last_title: 'Indlæs sidste',
        ui_last_text: '%s ændringer fra sidste gang',
        ui_neon_all: 'Alle',
    };

    function T(key, ...args) {
        let s = App.t(key, ...args);
        if (s === key && FALLBACK[key]) {
            let i = 0;
            s = FALLBACK[key].replace(/%[sd]/g, () => (i < args.length ? String(args[i++]) : ''));
        }
        return s;
    }

    // ---------------------------------------------------------------------------------------------
    // Small helpers
    // ---------------------------------------------------------------------------------------------

    const num = (v, d = 0) => { const n = Number(v); return Number.isFinite(n) ? n : d; };
    const int = (v, d = 0) => Math.trunc(num(v, d));
    const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v));
    const clone = (o) => (o === undefined ? undefined : JSON.parse(JSON.stringify(o)));
    const money = (n) => '$' + String(Math.round(num(n))).replace(/\B(?=(\d{3})+(?!\d))/g, '.');
    const qa = (parent, sel) => Array.from(parent.querySelectorAll(sel));
    const str = (v, max) => String(v ?? '').slice(0, max || 120);

    const TYPES = { sub: 1, mod: 1, colour: 1, toggle: 1, rgb: 1, list: 1, performance: 1 };
    const MAX_DEPTH = 6;
    const NEON_IDS = ['neonFront', 'neonLeft', 'neonRight', 'neonBack'];

    // Font Awesome class from a Lua icon name ('gauge-high' or 'fa-solid fa-gauge-high'), sanitised
    function iconClass(name, fallback) {
        const s = String(name || '').trim();
        if (/^[a-z0-9-]{1,40}$/i.test(s)) return 'fa-solid fa-' + s.replace(/^fa-/, '');
        if (/^[a-z0-9 -]{1,60}$/i.test(s) && s.indexOf('fa-') !== -1) return s;
        return 'fa-solid fa-' + (fallback || 'circle');
    }

    function icon(cls) {
        return el('i', { class: cls, attrs: { 'aria-hidden': 'true' } });
    }

    const safeHex = (h) => (/^#[0-9a-f]{6}$/i.test(String(h)) ? String(h) : null);

    function hexToRgb(hex) {
        const m = /^#?([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(String(hex).trim());
        return m ? { r: parseInt(m[1], 16), g: parseInt(m[2], 16), b: parseInt(m[3], 16) } : null;
    }

    const rgbToHex = (c) => '#' + [c.r, c.g, c.b].map((v) => clamp(int(v), 0, 255).toString(16).padStart(2, '0')).join('');

    // Hue shifted hex, used to fake the colour travel of chameleon paints in the swatch
    function hueShift(hex, deg) {
        const c = hexToRgb(hex) || { r: 128, g: 128, b: 128 };
        const r = c.r / 255, g = c.g / 255, b = c.b / 255;
        const max = Math.max(r, g, b), min = Math.min(r, g, b);
        let h = 0, s = 0;
        const l = (max + min) / 2;
        if (max !== min) {
            const d = max - min;
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
            if (max === r) h = (g - b) / d + (g < b ? 6 : 0);
            else if (max === g) h = (b - r) / d + 2;
            else h = (r - g) / d + 4;
            h /= 6;
        }
        h = (h + deg / 360 + 1) % 1;
        s = clamp(s < 0.35 ? 0.55 : s, 0, 1);
        const lq = clamp(l < 0.2 ? 0.34 : l, 0.2, 0.75);
        const q = lq < 0.5 ? lq * (1 + s) : lq + s - lq * s;
        const p = 2 * lq - q;
        const f = (tt) => {
            if (tt < 0) tt += 1;
            if (tt > 1) tt -= 1;
            if (tt < 1 / 6) return p + (q - p) * 6 * tt;
            if (tt < 1 / 2) return q;
            if (tt < 2 / 3) return p + (q - p) * (2 / 3 - tt) * 6;
            return p;
        };
        return rgbToHex({ r: f(h + 1 / 3) * 255, g: f(h) * 255, b: f(h - 1 / 3) * 255 });
    }

    const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
    const baseOf = (id) => String(id).split(':')[0];

    // ---------------------------------------------------------------------------------------------
    // Network: in demo mode (no FiveM) the calls are simulated (see the end of the file)
    // ---------------------------------------------------------------------------------------------

    let demoPost = null;

    async function post(name, body) {
        if (App.isGame) return App.post(name, body);
        if (Array.isArray(window.__trace)) window.__trace.push({ name, body: clone(body), t: performance.now() });
        return demoPost ? demoPost(name, body || {}) : { ok: true };
    }

    // ---------------------------------------------------------------------------------------------
    // Payload normalisation
    // ---------------------------------------------------------------------------------------------

    function normOptions(list) {
        return (Array.isArray(list) ? list : []).map((o) => ({
            value: int(o && o.value, -1),
            label: str(o && o.label),
            hex: safeHex(o && o.hex),
        }));
    }

    function normColourGroups(list) {
        return (Array.isArray(list) ? list : []).map((g) => ({
            id: str(g && g.id, 40),
            label: str(g && g.label, 40),
            colours: (Array.isArray(g && g.colours) ? g.colours : []).map((c) => ({
                index: int(c && c.index),
                label: str(c && c.label),
                hex: safeHex(c && c.hex) || '#808080',
            })),
        })).filter((g) => g.colours.length > 0);
    }

    function normNode(n, depth) {
        if (!n || typeof n !== 'object' || !TYPES[n.type] || depth > MAX_DEPTH) return null;
        const node = { type: n.type, id: str(n.id, 80), label: str(n.label ?? n.id), price: Math.max(0, num(n.price)) };
        if (!node.id) return null;
        if (n.icon) node.icon = n.icon;
        // Nodes that share a price (tyre smoke on/off + colour, neon tubes + colour) are charged once
        node.priceId = str(n.priceId ?? n.id, 80);

        switch (n.type) {
            case 'sub':
                node.items = (Array.isArray(n.items) ? n.items : []).map((c) => normNode(c, depth + 1)).filter(Boolean);
                if (!node.items.length) return null;
                break;
            case 'mod':
            case 'list':
                node.options = normOptions(n.options);
                node.current = int(n.current, -1);
                if (!node.options.length) return null;
                break;
            case 'colour':
                node.groups = normColourGroups(n.groups);
                node.current = int(n.current, -1);
                if (!node.groups.length) return null;
                break;
            case 'toggle':
                node.current = n.current === true;
                break;
            case 'rgb': {
                const c = n.current || {};
                node.current = { r: clamp(int(c.r, 255), 0, 255), g: clamp(int(c.g, 255), 0, 255), b: clamp(int(c.b, 255), 0, 255) };
                break;
            }
            case 'performance':
                node.current = int(n.current);
                node.options = (Array.isArray(n.options) ? n.options : []).map((o) => ({
                    level: int(o && o.level),
                    label: str(o && o.label),
                    item: o && o.item ? str(o.item, 64) : null,
                    stock: Math.max(0, int(o && o.stock)),
                    price: Math.max(0, num(o && o.price)),
                }));
                if (!node.options.length) return null;
                break;
            default:
                return null;
        }
        return node;
    }

    // Pending performance swap (from a preset, a work order, "Indlæs sidste" or the level list)
    function normSwap(s) {
        if (!s || typeof s !== 'object' || typeof s.category !== 'string') return null;
        return {
            category: str(s.category, 40),
            level: Math.max(0, int(s.level)),
            current: Math.max(0, int(s.current)),
            label: str(s.label ?? s.category),
            levelLabel: str(s.levelLabel ?? s.level),
            price: Math.max(0, num(s.price)),
            item: s.item ? str(s.item, 64) : null,
            stock: s.stock === undefined || s.stock === null ? null : Math.max(0, int(s.stock)),
        };
    }

    // ---------------------------------------------------------------------------------------------
    // State
    // ---------------------------------------------------------------------------------------------

    const S = {
        open: false,
        session: 0,              // increases per open: late answers of an old screen are ignored
        mode: 'mechanic',        // 'mechanic' | 'design'
        manualSwap: false,
        data: null,
        groups: [],
        gi: 0,                   // active group index; -1 = presets view
        nav: [],                 // sub / leaf nodes below the active group
        cur: {},                 // id -> current (previewed) value
        orig: {},                // id -> value on the car when the screen opened
        touched: {},             // id -> sequence number of the last change
        seq: 0,
        nodes: new Map(),        // id -> value node
        bases: new Map(),        // base id -> value nodes sharing it (wheel types)
        perf: new Map(),         // category -> performance node
        swaps: {},               // category -> pending swap (normSwap shape)
        colourNames: new Map(),
        colourTab: {},
        search: {},
        memory: {},
        swapPick: null,          // { category, level } chosen in the level list (mechanic, confirm sheet)
        sheet: null,             // null | 'cart' | 'swap' | 'delete'
        deleteId: null,
        order: { busy: false, item: null, until: 0, ordered: {}, error: {} },
        presets: { state: 'idle', builtin: [], mine: [], error: '' },
        presetBusy: false,
        lastCart: null,          // { count } or null
        workOrder: null,         // { owner, count } or null
        busy: false,             // install / swap / send in progress
        suspended: false,
        cam: 'default',
    };

    let ui = null;
    let leaveTimer = 0;
    let orderTimer = 0;

    const isDesign = () => S.mode === 'design';

    function indexNodes(list, gi, parent) {
        list.forEach((n) => {
            if (n.type === 'sub') { indexNodes(n.items, gi, n); return; }
            n.gi = gi;
            if (n.type === 'performance') { S.perf.set(n.id, n); return; }
            // Rims live in one sub per wheel type: the cart line must say which type
            // Rims (one node per wheel type) and nodes that share a price with siblings (neon tubes, smoke
            // colour) are named after their sub-category in the cart: "Neon" / "Venstre: Til"
            n.cartGroup = (parent && (n.id.indexOf(':') !== -1 || n.priceId !== n.id) && parent.label !== n.label) ? parent.label : null;
            S.nodes.set(n.id, n);
            const b = baseOf(n.id);
            if (!S.bases.has(b)) S.bases.set(b, []);
            S.bases.get(b).push(n);
            S.orig[n.id] = clone(n.current);
            S.cur[n.id] = clone(n.current);
            if (n.type === 'colour') {
                n.groups.forEach((g) => g.colours.forEach((c) => { if (!S.colourNames.has(c.index)) S.colourNames.set(c.index, c.label); }));
            }
        });
    }

    function isChanged(node) { return !eq(S.cur[node.id], S.orig[node.id]); }

    function countChanged(list) {
        let n = 0;
        list.forEach((x) => {
            if (x.type === 'sub') n += countChanged(x.items);
            else if (x.type === 'performance') { if (S.swaps[x.id]) n += 1; }
            else if (isChanged(x)) n += 1;
        });
        return n;
    }

    function optionOf(node, value) {
        return node.options.find((x) => x.value === value) || null;
    }

    function colourName(index) {
        if (S.colourNames.has(index)) return S.colourNames.get(index);
        return index < 0 || index === 255 ? T('ui_stock') : '#' + index;
    }

    function colourHex(node, index) {
        for (const g of node.groups) {
            const c = g.colours.find((x) => x.index === index);
            if (c) return c.hex;
        }
        return null;
    }

    function valueText(node, value) {
        switch (node.type) {
            case 'mod':
            case 'list': { const o = optionOf(node, value); return o ? o.label : ''; }
            case 'colour': return colourName(value);
            case 'toggle': return value ? T('ui_on') : T('ui_off');
            case 'rgb': return rgbToHex(value).toUpperCase();
            default: return '';
        }
    }

    function priceText(n) {
        return isDesign() ? T('ui_estimate', money(n)) : money(n);
    }

    // ---------------------------------------------------------------------------------------------
    // Live preview (coalesced per base id, hover is debounced, restore goes back to the cart state)
    // ---------------------------------------------------------------------------------------------

    const pv = { timer: {}, pending: {}, last: {}, hover: 0 };

    function previewKey(node, value) {
        return JSON.stringify({ id: node.id, value });
    }

    function sendPreview(node, value) {
        const base = baseOf(node.id);
        const payload = { id: node.id, value: clone(value) };
        const key = JSON.stringify(payload);
        if (pv.last[base] === undefined && eq(value, S.orig[node.id]) && eq(value, S.cur[node.id])) return;
        if (pv.last[base] === key) return;
        pv.last[base] = key;

        if (pv.timer[base]) { pv.pending[base] = payload; return; }
        post('tuning:preview', payload);
        const tick = () => {
            pv.timer[base] = 0;
            if (pv.pending[base]) {
                const p = pv.pending[base];
                pv.pending[base] = null;
                post('tuning:preview', p);
                pv.timer[base] = setTimeout(tick, 80);
            }
        };
        pv.timer[base] = setTimeout(tick, 80);
    }

    function hoverPreview(node, value) {
        clearTimeout(pv.hover);
        pv.hover = setTimeout(() => sendPreview(node, value), 60);
    }

    // Back to what is in the cart for this node's base (the changed sibling, else the installed one)
    function restorePreview(node) {
        clearTimeout(pv.hover);
        const sibs = S.bases.get(baseOf(node.id)) || [node];
        let eff = null;
        sibs.forEach((s) => { if (isChanged(s) && (!eff || S.touched[s.id] > S.touched[eff.id])) eff = s; });
        if (!eff) eff = sibs.find((s) => !eq(S.orig[s.id], -1) && s.type !== 'toggle' && s.type !== 'rgb') || node;
        sendPreview(eff, S.cur[eff.id]);
    }

    function resetPreviewState() {
        clearTimeout(pv.hover);
        Object.keys(pv.timer).forEach((k) => clearTimeout(pv.timer[k]));
        pv.timer = {}; pv.pending = {}; pv.last = {};
    }

    // ---------------------------------------------------------------------------------------------
    // Changing values
    // ---------------------------------------------------------------------------------------------

    // Store a value without previewing it (Lua already applied it, e.g. a loaded preset)
    function storeValue(node, value) {
        const id = node.id;
        (S.bases.get(baseOf(id)) || []).forEach((s) => {
            if (s.id !== id) { S.cur[s.id] = clone(S.orig[s.id]); delete S.touched[s.id]; }
        });
        S.cur[id] = clone(value);
        if (isChanged(node)) S.touched[id] = ++S.seq; else delete S.touched[id];
    }

    function setValue(node, value) {
        storeValue(node, value);
        sendPreview(node, value);
        afterChange();
    }

    function revert(node) {
        (S.bases.get(baseOf(node.id)) || [node]).forEach((s) => { S.cur[s.id] = clone(S.orig[s.id]); delete S.touched[s.id]; });
        restorePreview(node);
        afterChange();
    }

    function afterChange() {
        paintRail();
        paintListRows();
        paintLeaf();
        renderFoot();
        if (S.sheet === 'cart') renderSheet();
    }

    // Cosmetic cart lines: one per base id (rims of different wheel types replace each other)
    function cartEntries() {
        const byBase = {};
        S.nodes.forEach((n) => {
            if (!isChanged(n)) return;
            const b = baseOf(n.id);
            if (!byBase[b] || S.touched[n.id] > S.touched[byBase[b].id]) byBase[b] = n;
        });
        const list = Object.keys(byBase).map((b) => {
            const n = byBase[b];
            const value = valueText(n, S.cur[n.id]);
            return {
                node: n, id: n.id, value: clone(S.cur[n.id]), price: n.price, seq: S.touched[n.id] || 0,
                name: n.cartGroup || n.label, detail: n.cartGroup ? n.label + ': ' + value : value,
            };
        }).sort((a, c) => a.seq - c.seq);
        // One price per priceId (as Lua bills it): later lines with the same priceId are included in the first
        const charged = new Set();
        list.forEach((e) => {
            const pid = e.node.priceId || e.id;
            e.shared = charged.has(pid);
            if (e.shared) e.price = 0;
            charged.add(pid);
        });
        return list;
    }

    function swapList() {
        const order = Array.from(S.perf.keys());
        return Object.keys(S.swaps).map((k) => S.swaps[k]).sort((a, b) => order.indexOf(a.category) - order.indexOf(b.category));
    }

    function cartPayload() {
        return {
            changes: cartEntries().map((e) => ({ id: e.id, value: e.value })),
            swaps: swapList().map((s) => ({ category: s.category, level: s.level })),
        };
    }

    function cartCount() {
        return cartEntries().length + swapList().length;
    }

    function cartTotal() {
        let total = cartEntries().reduce((s, e) => s + e.price, 0);
        // Parts are bought by the workshop; only the customer's estimate includes them
        if (isDesign()) total += swapList().reduce((s, w) => s + w.price, 0);
        return total;
    }

    // A pending swap for a level from the level list
    function swapFromLevel(node, o) {
        return normSwap({
            category: node.id, level: o.level, current: node.current, label: node.label, levelLabel: o.label,
            price: o.price, item: o.item, stock: isDesign() ? null : o.stock,
        });
    }

    function setSwap(node, o) {
        if (!o || o.level === node.current) delete S.swaps[node.id];
        else S.swaps[node.id] = swapFromLevel(node, o);
        afterChange();
    }

    // Merge a loaded look (preset, work order, last cart) into the cart. Lua already previewed it.
    function mergeLoaded(res) {
        const changes = Array.isArray(res && res.changes) ? res.changes : [];
        changes.forEach((c) => {
            const node = c && S.nodes.get(String(c.id));
            if (!node || c.value === undefined || c.value === null) return;
            let value = c.value;
            if (node.type === 'toggle') value = value === true || value === 1;
            else if (node.type === 'rgb') {
                const v = value || {};
                value = { r: clamp(int(v.r ?? v[0]), 0, 255), g: clamp(int(v.g ?? v[1]), 0, 255), b: clamp(int(v.b ?? v[2]), 0, 255) };
            } else value = int(value, -1);
            storeValue(node, value);
            pv.last[baseOf(node.id)] = previewKey(node, value);
        });
        const swaps = Array.isArray(res && res.swaps) ? res.swaps : [];
        swaps.map(normSwap).filter(Boolean).forEach((s) => {
            const node = S.perf.get(s.category);
            if (!node) return;
            if (s.level === node.current) delete S.swaps[s.category];
            else S.swaps[s.category] = s;
        });
        afterChange();
        if (currentLeaf() && currentLeaf().type === 'performance') renderView(0);
    }

    // ---------------------------------------------------------------------------------------------
    // Navigation
    // ---------------------------------------------------------------------------------------------

    const inPresets = () => S.gi === -1;
    const activeGroup = () => S.groups[S.gi] || null;
    const lastNav = () => S.nav[S.nav.length - 1] || null;
    const pathKey = () => S.gi + '/' + S.nav.map((n) => n.id).join('/');

    function currentLeaf() {
        const last = lastNav();
        return last && last.type !== 'sub' ? last : null;
    }

    function currentItems() {
        if (inPresets()) return null;
        const last = lastNav();
        if (!last) return activeGroup().items;
        return last.type === 'sub' ? last.items : null; // null = a leaf is open
    }

    function rememberFocus() {
        if (!ui) return;
        const act = document.activeElement;
        if (!act || !ui.view.contains(act)) return;
        const rows = qa(ui.view, '[data-nav="row"]');
        const i = rows.indexOf(act);
        if (i >= 0) S.memory[pathKey()] = i;
    }

    function leaveLeaf() {
        const leaf = currentLeaf();
        if (leaf && leaf.type !== 'performance') restorePreview(leaf);
        S.swapPick = null;
        if (S.sheet === 'swap') S.sheet = null;
    }

    function go(node) {
        rememberFocus();
        S.nav.push(node);
        S.swapPick = null;
        if (S.sheet === 'swap') S.sheet = null;
        renderAll(1);
    }

    // Jump back to a crumb: depth 0 = the group itself
    function goTo(depth) {
        if (depth >= S.nav.length) return;
        leaveLeaf();
        S.nav = S.nav.slice(0, depth);
        renderAll(-1);
    }

    function goBack() {
        if (S.sheet) { closeSheet(); return true; }
        if (!S.nav.length) return false;
        goTo(S.nav.length - 1);
        return true;
    }

    // Camera preset per group, like the mod shop
    const GROUP_CAMERA = { wheels: 'wheel', engine: 'engine', interior: 'interior', plates: 'plate', performance: 'default' };

    function selectGroup(i, keepFocus) {
        if (i < -1 || i >= S.groups.length) return;
        leaveLeaf();
        S.sheet = null;
        S.gi = i;
        S.nav = [];
        const g = activeGroup();
        if (g && GROUP_CAMERA[g.id] && GROUP_CAMERA[g.id] !== S.cam) setCamera(GROUP_CAMERA[g.id]);
        if (i === -1 && S.presets.state !== 'ready') loadPresets();
        renderAll(1, keepFocus);
    }

    function stepGroup(d) {
        const n = S.groups.length + 1; // + presets
        const cur = S.gi === -1 ? S.groups.length : S.gi;
        const next = (cur + d + n) % n;
        selectGroup(next === S.groups.length ? -1 : next, false);
    }

    // ---------------------------------------------------------------------------------------------
    // Plate (B4): the game's own plate texture (nui-img) when the client could load it, else CSS
    // ---------------------------------------------------------------------------------------------

    // CSS recreation per plate index (GTA plate styles, modelled on the Californian base plates):
    // bg/fg colours, top line text and whether that line is the cursive script.
    const PLATES = {
        0: { cls: 'p-white', top: 'San Andreas', script: true, fg: '#0F2352' },
        1: { cls: 'p-black', top: 'SAN ANDREAS', fg: '#CF9E00' },
        2: { cls: 'p-blue', top: 'SAN ANDREAS', fg: '#E0B54A' },
        3: { cls: 'p-stripes', top: 'SAN ANDREAS', fg: '#0F2352' },
        4: { cls: 'p-white', top: 'San Andreas', script: true, bottom: 'EXEMPT', fg: '#0F2352' },
        5: { cls: 'p-yankton', top: 'NORTH YANKTON', fg: '#111111' },
        6: { cls: 'p-ecola', top: 'eCola', script: true, fg: '#FEFEFE' },
        7: { cls: 'p-venturas', top: 'Las Venturas', script: true, fg: '#011866' },
        8: { cls: 'p-liberty', top: 'LIBERTY CITY', fg: '#0D147E' },
        9: { cls: 'p-carmeet', top: 'LS CAR MEET', fg: '#111111' },
        10: { cls: 'p-panic', top: 'LS PANIC', fg: '#FED40E' },
        11: { cls: 'p-pounders', top: 'POUNDERS', fg: '#F4BB2E' },
        12: { cls: 'p-sprunk', top: 'Sprunk', script: true, fg: '#FEFEFE' },
    };

    function buildPlate(v) {
        const meta = PLATES[v.plateIndex] || PLATES[0];
        const style = v.plateStyle || {};
        const plate = el('div', {
            class: 'tn-plate ' + meta.cls,
            attrs: { role: 'img', 'aria-label': T('ui_plate', v.plate), title: v.plate, 'data-plate': String(v.plateIndex) },
        });
        plate.style.setProperty('--plate-fg', safeHex(style.text) || meta.fg);
        if (safeHex(style.outline)) plate.style.setProperty('--plate-outline', style.outline);

        const deco = el('span', { class: 'tn-plate-deco', attrs: { 'aria-hidden': 'true' } }, [
            el('span', { class: 'tn-plate-top' + (meta.script ? ' is-script' : ''), text: meta.top }),
            meta.bottom ? el('span', { class: 'tn-plate-bottom', text: meta.bottom }) : null,
        ]);
        const text = el('span', { class: 'tn-plate-text', text: v.plate });
        plate.append(deco, text);
        // Up to 8 characters must fit like on the real plate: squeeze the line horizontally if needed
        requestAnimationFrame(() => {
            const room = plate.clientWidth * 0.9;
            const need = text.scrollWidth;
            if (room > 0 && need > room) text.style.transform = 'scaleX(' + (room / need).toFixed(3) + ')';
            // Long state lines ("NORTH YANKTON") get a smaller font instead of running into the screws
            qa(deco, '.tn-plate-top, .tn-plate-bottom').forEach((line) => {
                if (line.clientWidth > 0 && line.scrollWidth > line.clientWidth) {
                    const size = parseFloat(getComputedStyle(line).fontSize) || 0;
                    if (size > 0) line.style.fontSize = (size * line.clientWidth / line.scrollWidth * 0.97).toFixed(2) + 'px';
                }
            });
        });

        // nui-img only exists in game; on any load error the CSS plate stays
        const url = typeof style.image === 'string' && /^https:\/\/nui-img\/[A-Za-z0-9_]+\/[A-Za-z0-9_]+$/.test(style.image) ? style.image : null;
        if (url) {
            const img = el('img', { class: 'tn-plate-img', attrs: { alt: '', src: url, draggable: 'false' } });
            img.addEventListener('load', () => { if (img.naturalWidth > 0) plate.classList.add('has-img'); });
            img.addEventListener('error', () => img.remove());
            plate.prepend(img);
        }
        return plate;
    }

    // ---------------------------------------------------------------------------------------------
    // Rendering: skeleton
    // ---------------------------------------------------------------------------------------------

    const CAMERAS = [
        ['default', 'eye'], ['front', 'car'], ['side', 'car-side'], ['rear', 'car-rear'],
        ['wheel', 'compact-disc'], ['engine', 'oil-can'], ['interior', 'couch'],
    ];

    function buildSkeleton() {
        const v = S.data.vehicle;
        const title = el('h1', { class: 'tn-title', text: v.label });
        const closeBtn = el('button', { class: 'tn-iconbtn', attrs: { type: 'button', 'aria-label': T('ui_close'), title: T('ui_close') }, on: { click: closeScreen } }, [icon('fa-solid fa-xmark')]);
        const head = el('header', { class: 'tn-head' }, [title, v.plate ? buildPlate(v) : null, closeBtn]);

        const banners = el('div', { class: 'tn-banners' });

        const rail = el('nav', { class: 'tn-rail', attrs: { 'aria-label': T('ui_groups') } });
        S.groups.forEach((g, i) => {
            rail.append(el('button', {
                class: 'tn-rail-btn',
                attrs: { type: 'button', 'aria-label': g.label, title: g.label, 'data-group': String(i) },
                on: { click: () => { if (i !== S.gi || S.nav.length) selectGroup(i, true); } },
            }, [icon(iconClass(g.icon, 'circle'))]));
        });
        rail.append(el('span', { class: 'tn-rail-sep', attrs: { 'aria-hidden': 'true' } }));
        rail.append(el('button', {
            class: 'tn-rail-btn',
            attrs: { type: 'button', 'aria-label': T('ui_presets'), title: T('ui_presets'), 'data-group': '-1' },
            on: { click: () => { if (!inPresets()) selectGroup(-1, true); } },
        }, [icon('fa-solid fa-bookmark')]));

        const crumbs = el('div', { class: 'tn-crumbs' });
        const view = el('div', { class: 'tn-view', attrs: { tabindex: '-1' } });
        const main = el('div', { class: 'tn-main' }, [crumbs, view]);
        const body = el('div', { class: 'tn-body' }, [rail, main]);
        const sheet = el('div', { class: 'tn-sheet', attrs: { role: 'dialog' } });
        sheet.hidden = true;
        const foot = el('footer', { class: 'tn-foot' });
        const panel = el('aside', { class: 'tn-panel' + (isDesign() ? ' is-design' : ''), attrs: { role: 'dialog', 'aria-label': v.label } }, [head, banners, body, sheet, foot]);

        const dockInner = el('div', { class: 'tn-dock-inner', attrs: { role: 'toolbar' } });
        CAMERAS.forEach(([focus, ic]) => {
            const label = T('ui_cam_' + focus);
            dockInner.append(el('button', {
                class: 'tn-cam',
                attrs: { type: 'button', 'aria-label': label, title: label, 'aria-pressed': focus === S.cam ? 'true' : 'false', 'data-focus': focus },
                on: { click: () => setCamera(focus) },
            }, [icon('fa-solid fa-' + ic)]));
        });
        const dock = el('div', { class: 'tn-dock' }, [dockInner]);

        const hint = el('div', { class: 'tn-hint', attrs: { 'aria-hidden': 'true' } }, [
            el('span', {}, [icon('fa-solid fa-computer-mouse'), el('span', { text: T('ui_drag_hint') }), el('i', { class: 'tn-hint-sep' }), el('span', { text: T('ui_zoom_hint') })]),
        ]);

        root.replaceChildren(panel, dock, hint);
        ui = { panel, banners, rail, crumbs, view, sheet, foot, dockInner };
    }

    function setCamera(focus) {
        S.cam = focus;
        paintCameras();
        post('tuning:camera', { focus });
    }

    function paintCameras() {
        if (!ui) return;
        qa(ui.dockInner, '.tn-cam').forEach((b) => b.setAttribute('aria-pressed', b.dataset.focus === S.cam ? 'true' : 'false'));
    }

    function paintRail() {
        if (!ui) return;
        qa(ui.rail, '.tn-rail-btn').forEach((b) => {
            const i = int(b.dataset.group);
            const active = i === S.gi;
            b.classList.toggle('is-active', active);
            b.classList.toggle('is-dirty', i >= 0 && countChanged(S.groups[i].items) > 0);
            b.setAttribute('aria-current', active ? 'true' : 'false');
        });
    }

    // ---------------------------------------------------------------------------------------------
    // Banners: design note, not owned, customer's work order, "Indlæs sidste"
    // ---------------------------------------------------------------------------------------------

    function banner(ic, title, desc, action, cls) {
        return el('div', { class: 'tn-banner' + (cls ? ' ' + cls : ''), attrs: { role: 'status' } }, [
            el('span', { class: 'tn-banner-icon' }, [icon('fa-solid fa-' + ic)]),
            el('span', { class: 'tn-banner-text' }, [
                title ? el('span', { class: 'tn-banner-title', text: title }) : null,
                desc ? el('span', { class: 'tn-banner-desc', text: desc }) : null,
            ]),
            action || null,
        ]);
    }

    function renderBanners() {
        if (!ui) return;
        const kids = [];
        if (isDesign()) {
            kids.push(banner('circle-info', null, T('ui_design_note')));
        } else if (!S.data.vehicle.owned) {
            kids.push(banner('triangle-exclamation', null, T('ui_not_owned'), null, 'is-warning'));
        }
        if (!isDesign() && S.workOrder) {
            const desc = T('ui_workorder_text', S.workOrder.owner || '-', S.workOrder.count);
            const btn = el('button', { class: 'tn-btn is-secondary is-small', text: T('ui_load'), attrs: { type: 'button', 'data-nav': 'banner' }, on: { click: loadWorkOrder } });
            btn.disabled = S.presetBusy || S.busy;
            kids.push(banner('clipboard-list', T('ui_workorder_title'), desc, btn));
        }
        if (S.lastCart) {
            const btn = el('button', { class: 'tn-btn is-secondary is-small', text: T('ui_load'), attrs: { type: 'button', 'data-nav': 'banner' }, on: { click: loadLast } });
            btn.disabled = S.presetBusy || S.busy;
            kids.push(banner('clock-rotate-left', T('ui_last_title'), T('ui_last_text', S.lastCart.count), btn));
        }
        ui.banners.replaceChildren(...kids);
        ui.banners.hidden = kids.length === 0;
    }

    // ---------------------------------------------------------------------------------------------
    // Breadcrumbs: every crumb but the last is a button that jumps back to that level
    // ---------------------------------------------------------------------------------------------

    function renderCrumbs() {
        const back = el('button', { class: 'tn-iconbtn tn-back', attrs: { type: 'button', 'aria-label': T('ui_back'), title: T('ui_back') }, on: { click: goBack } }, [icon('fa-solid fa-chevron-left')]);
        // Always in the layout (hidden at the top level), so the title never jumps sideways
        back.style.visibility = S.nav.length ? 'visible' : 'hidden';
        back.tabIndex = S.nav.length ? 0 : -1;

        const trail = el('div', { class: 'tn-crumb-trail' });
        const labels = inPresets() ? [T('ui_presets')] : [activeGroup().label].concat(S.nav.map((n) => n.label));
        labels.forEach((text, i) => {
            const last = i === labels.length - 1;
            if (i > 0) trail.append(icon('fa-solid fa-chevron-right tn-crumb-sep'));
            if (last) trail.append(el('span', { class: 'tn-crumb is-last', text, attrs: { 'aria-current': 'page' } }));
            else trail.append(el('button', { class: 'tn-crumb', text, attrs: { type: 'button', title: text }, on: { click: () => goTo(i) } }));
        });

        const kids = [back, trail];
        const leaf = currentLeaf();
        if (leaf && leaf.type !== 'performance' && leaf.price > 0) {
            kids.push(el('span', { class: 'tn-crumb-price', text: isDesign() ? T('ui_estimate', money(leaf.price)) : T('ui_price', money(leaf.price)) }));
        }
        ui.crumbs.replaceChildren(...kids);
    }

    // dir: 1 forward, -1 back. Rebuilds crumbs, view and footer; keeps the rail.
    function renderAll(dir, keepFocus) {
        paintRail();
        renderCrumbs();
        renderView(dir);
        renderFoot();
        renderSheet();
        if (!keepFocus) focusInitial();
    }

    function renderView(dir) {
        let content;
        if (inPresets()) content = buildPresets();
        else {
            const items = currentItems();
            content = items ? buildList(items, lastNav()) : buildLeaf(currentLeaf());
        }
        const keepScroll = dir === 0 ? ui.view.scrollTop : 0;
        ui.view.replaceChildren(...content);
        ui.view.scrollTop = keepScroll;
        if (dir) {
            ui.view.classList.toggle('is-back', dir < 0);
            ui.view.classList.remove('is-enter');
            void ui.view.offsetWidth;
            ui.view.classList.add('is-enter');
        }
        paintListRows();
        paintLeaf();
    }

    function focusInitial() {
        const rows = qa(ui.view, '[data-nav]').filter((n) => !n.disabled && n.tagName !== 'INPUT');
        if (!rows.length) return;
        const leaf = currentLeaf();
        let target = null;
        if (leaf) {
            target = ui.view.querySelector('[aria-checked="true"][data-nav]:not(:disabled)') || rows[0];
        } else {
            const mem = S.memory[pathKey()];
            const list = qa(ui.view, '[data-nav="row"]').filter((n) => !n.disabled);
            target = (mem !== undefined && list[mem]) ? list[mem] : list[0] || rows[0];
        }
        if (target) target.focus({ preventScroll: true });
    }

    // ---------------------------------------------------------------------------------------------
    // Rendering: list rows (the same row as ap1le_core menu.css: icon | title + description | trail)
    // ---------------------------------------------------------------------------------------------

    const TYPE_ICON = { colour: 'palette', rgb: 'droplet', toggle: 'power-off', list: 'list-ul', mod: 'screwdriver-wrench', sub: 'layer-group' };
    const ID_ICON = {
        engine: 'gauge-high', brakes: 'circle-stop', transmission: 'gears', suspension: 'arrows-up-down', armor: 'shield-halved', turbo: 'wind',
        modHorns: 'bullhorn', modLivery: 'paintbrush', oldLivery: 'paintbrush', windowTint: 'circle-half-stroke', plateIndex: 'hashtag',
        modPlateHolder: 'square', modVanityPlate: 'id-badge', xenon: 'lightbulb', customTires: 'circle', modHydrolic: 'arrows-up-down',
        modEngineBlock: 'cube', modAirFilter: 'wind', modStruts: 'grip-lines-vertical', modArchCover: 'circle-half-stroke', modTrimB: 'star',
        color1: 'spray-can', color2: 'spray-can', pearlescent: 'spray-can', wheelColor: 'palette', interiorColor: 'palette', dashboardColor: 'palette',
    };

    function rowIcon(node) {
        return iconClass(node.icon || ID_ICON[baseOf(node.id)] || TYPE_ICON[node.type], 'circle');
    }

    function bindFocus(btn) {
        btn.addEventListener('mousemove', () => {
            if (!btn.disabled && document.activeElement !== btn) btn.focus({ preventScroll: true });
        });
    }

    function isNeonSub(items) {
        return items.filter((n) => n.type === 'toggle' && NEON_IDS.indexOf(n.id) !== -1).length >= 2;
    }

    function buildList(items, parent) {
        const out = [];
        let list = items;
        if (isNeonSub(items)) {
            out.push(buildNeon(items));
            list = items.filter((n) => NEON_IDS.indexOf(n.id) === -1);
        }
        if (!list.length && !out.length) return [el('p', { class: 'tn-empty', text: T('ui_empty_list') })];
        // Icons on the top level (like a menu); plain rows inside a sub-category
        const withIcons = !parent;
        const box = el('div', { class: 'tn-list', attrs: { role: 'list' } });
        list.forEach((n) => box.append(buildRow(n, withIcons)));
        if (list.length) out.push(box);
        return out;
    }

    function buildRow(node, withIcon) {
        const row = el('button', { class: 'tn-row', attrs: { type: 'button', 'data-nav': 'row', 'data-id': node.id } });
        if (withIcon) row.append(el('span', { class: 'tn-row-icon' }, [icon(rowIcon(node))]));
        const desc = el('span', { class: 'tn-row-desc' });
        row.append(el('span', { class: 'tn-row-text' }, [el('span', { class: 'tn-row-title', text: node.label }), desc]));
        const trail = el('span', { class: 'tn-row-trail' });
        row.append(trail);

        if (node.type === 'toggle') {
            row.setAttribute('role', 'switch');
            trail.append(el('span', { class: 'tn-switch' }));
            row.addEventListener('click', () => setValue(node, !S.cur[node.id]));
        } else {
            row.dataset.open = '1';
            row.__chip = el('span', { class: 'tn-chip' });
            trail.append(row.__chip, icon('fa-solid fa-chevron-right tn-row-arrow'));
            row.addEventListener('click', () => go(node));
        }
        bindFocus(row);
        row.__node = node;
        row.__desc = desc;
        return row;
    }

    // Update description, dirty state and colour chips of the rows in the visible list
    function paintListRows() {
        if (!ui) return;
        qa(ui.view, '.tn-row').forEach((row) => {
            const n = row.__node;
            if (!n) return;
            let text = '';
            let dirty = false;
            let chip = null;
            if (n.type === 'sub') {
                const c = countChanged(n.items);
                dirty = c > 0;
                text = dirty ? T('ui_changed', c) : n.items.map((x) => x.label).join(', ');
            } else if (n.type === 'performance') {
                const cur = n.options.find((o) => o.level === n.current);
                const sw = S.swaps[n.id];
                dirty = !!sw;
                text = (cur ? cur.label : T('ui_stock')) + (sw ? '  →  ' + sw.levelLabel : '');
            } else {
                dirty = isChanged(n);
                text = valueText(n, S.cur[n.id]);
                if (n.type === 'colour') chip = colourHex(n, S.cur[n.id]);
                else if (n.type === 'rgb') chip = rgbToHex(S.cur[n.id]);
                else if (n.type === 'list') { const o = optionOf(n, S.cur[n.id]); chip = o && o.hex; }
                if (n.type === 'toggle') row.setAttribute('aria-checked', S.cur[n.id] ? 'true' : 'false');
            }
            row.classList.toggle('is-dirty', dirty);
            row.__desc.textContent = text || ' ';
            if (row.__chip) {
                row.__chip.hidden = !chip;
                if (chip) row.__chip.style.background = chip;
            }
        });
        paintNeon();
    }

    // ---------------------------------------------------------------------------------------------
    // Neon (B4): four tubes around a top-down car, switched one by one like v1, lit in the colour
    // ---------------------------------------------------------------------------------------------

    function buildNeon(items) {
        const tubes = {};
        items.forEach((n) => { if (NEON_IDS.indexOf(n.id) !== -1) tubes[n.id] = n; });
        const colourNode = items.find((n) => n.type === 'rgb') || null;
        const pos = { neonFront: 'is-front', neonBack: 'is-back', neonLeft: 'is-left', neonRight: 'is-right' };

        const car = el('div', { class: 'tn-neon-car', attrs: { 'aria-hidden': 'true' } }, [el('span', { class: 'tn-neon-glass' })]);
        const stage = el('div', { class: 'tn-neon-stage' }, [car]);
        NEON_IDS.forEach((id) => {
            const n = tubes[id];
            if (!n) return;
            const b = el('button', {
                class: 'tn-neon-tube ' + pos[id],
                attrs: { type: 'button', role: 'switch', 'data-nav': 'row', 'aria-label': n.label, title: n.label, 'data-tube': id },
                on: { click: () => setValue(n, !S.cur[n.id]) },
            }, [el('span', { class: 'tn-neon-light' })]);
            bindFocus(b);
            stage.append(b);
        });

        const all = el('button', {
            class: 'tn-btn is-secondary is-small tn-neon-all',
            attrs: { type: 'button', 'data-nav': 'row', role: 'switch' },
            on: {
                click: () => {
                    const on = !Object.keys(tubes).every((id) => S.cur[id]);
                    Object.keys(tubes).forEach((id) => { storeValue(tubes[id], on); sendPreview(tubes[id], on); });
                    afterChange();
                },
            },
        }, [icon('fa-solid fa-power-off'), el('span', { text: T('ui_neon_all') })]);
        bindFocus(all);

        const legend = el('div', { class: 'tn-neon-legend' });
        const box = el('div', { class: 'tn-neon' }, [stage, el('div', { class: 'tn-neon-side' }, [legend, all])]);
        box.__tubes = tubes;
        box.__colour = colourNode;
        box.__legend = legend;
        box.__all = all;
        return box;
    }

    function paintNeon() {
        const box = ui && ui.view.querySelector('.tn-neon');
        if (!box) return;
        const c = box.__colour ? S.cur[box.__colour.id] : { r: 255, g: 0, b: 80 };
        box.style.setProperty('--neon', rgbToHex(c));
        const names = [];
        qa(box, '.tn-neon-tube').forEach((b) => {
            const n = box.__tubes[b.dataset.tube];
            const on = !!S.cur[n.id];
            b.setAttribute('aria-checked', on ? 'true' : 'false');
            b.classList.toggle('is-dirty', isChanged(n));
            if (on) names.push(n.label);
        });
        box.__legend.textContent = names.length ? names.join(', ') : T('ui_off');
        box.__all.setAttribute('aria-checked', names.length === Object.keys(box.__tubes).length ? 'true' : 'false');
    }

    // ---------------------------------------------------------------------------------------------
    // Rendering: performance levels (a leaf like any other category; two-line rows of fixed height)
    // ---------------------------------------------------------------------------------------------

    function orderLocked() {
        return S.order.busy || performance.now() < S.order.until;
    }

    function levelState(node, o) {
        // -> { text, cls } for the description line (always one line, never wraps: A4)
        const isCurrent = o.level === node.current;
        if (isDesign()) {
            if (isCurrent) return { text: T('ui_installed') };
            return { text: o.price > 0 ? T('ui_estimate', money(o.price)) : ' ' };
        }
        if (isCurrent) return { text: T('ui_installed') };
        if (o.level === 0 || !o.item) return { text: ' ' };
        if (S.order.busy && S.order.item === o.item) return { text: T('ui_ordering') };
        const err = S.order.error[o.item];
        if (err) return { text: err, cls: 'is-error' };
        if (S.order.ordered[o.item] !== undefined) {
            const min = Math.max(1, Math.ceil(S.order.ordered[o.item] / 60));
            return { text: T('ui_ordered') + ' · ' + T('ui_eta', min) };
        }
        if (o.stock > 0) return { text: T('ui_stock_count', o.stock) };
        return { text: T('ui_out_of_stock') + (o.price > 0 ? ' · ' + money(o.price) : '') };
    }

    function buildPerfLeaf(node) {
        const box = el('div', { class: 'tn-levels', attrs: { role: 'radiogroup', 'aria-label': node.label } });
        node.options.forEach((o) => box.append(buildLevel(node, o)));
        const out = [box];
        return out;
    }

    function buildLevel(node, o) {
        const isCurrent = o.level === node.current;
        const owned = S.data.vehicle.owned;
        const wish = S.swaps[node.id];
        const inCart = !!wish && wish.level === o.level;
        let canPick;
        if (isDesign()) canPick = true;
        else canPick = owned && !isCurrent && (o.level === 0 || o.stock > 0);
        const picked = !isDesign() && S.swapPick && S.swapPick.category === node.id && S.swapPick.level === o.level;
        const checked = isDesign() ? (inCart || (!wish && isCurrent)) : (picked || inCart);

        const st = levelState(node, o);
        const desc = el('span', { class: 'tn-row-desc' + (st.cls ? ' ' + st.cls : ''), text: st.text, attrs: { title: st.text.trim() ? st.text : null } });
        const pick = el('button', {
            class: 'tn-level-pick',
            attrs: { type: 'button', 'data-nav': 'opt', role: 'radio', 'aria-checked': checked ? 'true' : 'false' },
        }, [
            el('span', { class: 'tn-radio' }, [icon('fa-solid fa-check')]),
            el('span', { class: 'tn-row-text' }, [el('span', { class: 'tn-row-title', text: o.label }), desc]),
            inCart ? el('span', { class: 'tn-tag', text: isDesign() ? T('ui_wish') : T('ui_in_cart') }) : null,
        ]);
        pick.disabled = !canPick;
        if (canPick) {
            pick.addEventListener('click', () => pickLevel(node, o));
            bindFocus(pick);
        }

        const row = el('div', {
            class: 'tn-level' + (isCurrent ? ' is-current' : '') + (checked ? ' is-selected' : '') + (canPick ? '' : ' is-unavailable'),
            attrs: { 'data-level': String(o.level) },
        }, [pick]);

        // Order button: only for missing parts, never in design mode
        if (!isDesign() && !isCurrent && o.level > 0 && o.item && o.stock <= 0 && S.order.ordered[o.item] === undefined) {
            const mine = S.order.busy && S.order.item === o.item;
            const btn = el('button', {
                class: 'tn-btn is-secondary is-small tn-order' + (mine ? ' is-busy' : ''),
                attrs: { type: 'button', 'data-nav': 'row', 'data-order': o.item, 'aria-label': T('ui_order') + ' ' + node.label + ' ' + o.label },
            }, [icon(mine ? 'fa-solid fa-circle-notch' : 'fa-solid fa-truck-fast'), el('span', { text: T('ui_order') })]);
            btn.disabled = orderLocked() || S.busy;
            // One handler, and the lock is taken synchronously in orderItem (A3: no double post)
            btn.addEventListener('click', (e) => { e.preventDefault(); orderItem(o.item); });
            bindFocus(btn);
            row.append(btn);
        }
        return row;
    }

    function pickLevel(node, o) {
        if (S.busy) return;
        if (isDesign()) {
            const wish = S.swaps[node.id];
            setSwap(node, wish && wish.level === o.level ? null : o);
            refreshLevels();
            return;
        }
        S.swapPick = { category: node.id, level: o.level };
        S.sheet = 'swap';
        refreshLevels();
        renderSheet();
    }

    // Re-render the level rows of the open performance leaf (keeps scroll and the focused control)
    function refreshLevels() {
        const leaf = currentLeaf();
        if (!ui || !leaf || leaf.type !== 'performance') return;
        const act = document.activeElement;
        let key = null;
        if (act && ui.view.contains(act)) {
            const lvl = act.closest('.tn-level');
            if (lvl) key = { level: lvl.dataset.level, order: !!act.dataset.order };
        }
        const top = ui.view.scrollTop;
        ui.view.replaceChildren(...buildPerfLeaf(leaf));
        ui.view.scrollTop = top;
        if (key && !S.sheet) {
            const lvl = ui.view.querySelector('.tn-level[data-level="' + key.level + '"]');
            const target = lvl && (key.order ? lvl.querySelector('.tn-order') : lvl.querySelector('.tn-level-pick'));
            if (target && !target.disabled) target.focus({ preventScroll: true });
            else if (lvl && key.order) {
                // The order button is locked while the order runs: keep keyboard focus in the list
                const p = lvl.querySelector('.tn-level-pick');
                if (p && !p.disabled) p.focus({ preventScroll: true });
                else ui.view.focus({ preventScroll: true });
            }
        }
    }

    // A3: exactly one tuning:order in flight; the buttons stay disabled until the answer is in and the
    // server's spacing has passed; the first answer (success or the real error) is what is shown.
    async function orderItem(item) {
        if (!item || S.order.busy || orderLocked() || S.busy || isDesign()) return;
        const session = S.session;
        S.order.busy = true;
        S.order.item = item;
        delete S.order.error[item];
        refreshLevels();
        let res = null;
        try {
            res = await post('tuning:order', { item });
        } finally {
            if (session === S.session) {
                S.order.busy = false;
                S.order.item = null;
            }
        }
        if (session !== S.session || !S.open) return;
        const ok = !!(res && res.ok);
        // Matches the client/server spacing (1 s between attempts, 3 s after a placed order)
        S.order.until = performance.now() + (ok ? 3200 : 1000);
        if (ok) {
            S.order.ordered[item] = Math.max(0, num(res.eta));
        } else {
            S.order.error[item] = (res && typeof res.error === 'string' && res.error) ? res.error.slice(0, 160) : T('ui_order_failed');
        }
        refreshLevels();
        clearTimeout(orderTimer);
        orderTimer = setTimeout(() => { if (S.open && session === S.session) refreshLevels(); }, (ok ? 3200 : 1000) + 30);
        if (!ok && ui) shake(ui.view.querySelector('.tn-level .tn-row-desc.is-error'));
    }

    // ---------------------------------------------------------------------------------------------
    // Rendering: leaves (options, colours, rgb)
    // ---------------------------------------------------------------------------------------------

    function buildLeaf(node) {
        if (!node) return [];
        if (node.type === 'performance') return buildPerfLeaf(node);
        if (node.type === 'colour') return buildColourLeaf(node);
        if (node.type === 'rgb') return buildRgbLeaf(node);
        return buildOptionsLeaf(node);
    }

    function buildOptionsLeaf(node) {
        const out = [];
        const box = el('div', { class: 'tn-opts', attrs: { role: 'radiogroup', 'aria-label': node.label } });
        const rows = node.options.map((o) => {
            const tag = el('span', { class: 'tn-tag', text: T('ui_installed') });
            tag.hidden = true;
            const chip = o.hex ? el('span', { class: 'tn-chip' }) : null;
            if (chip) chip.style.background = o.hex;
            const r = el('button', {
                class: 'tn-opt',
                attrs: { type: 'button', role: 'radio', 'data-nav': 'opt', 'data-value': String(o.value), 'aria-checked': 'false' },
            }, [el('span', { class: 'tn-radio' }, [icon('fa-solid fa-check')]), el('span', { class: 'tn-opt-name', text: o.label }), tag, chip]);
            r.__value = o.value;
            r.__label = o.label.toLowerCase();
            r.__tag = tag;
            r.addEventListener('click', () => setValue(node, o.value));
            r.addEventListener('focus', () => hoverPreview(node, o.value));
            bindFocus(r);
            box.append(r);
            return r;
        });
        const empty = el('p', { class: 'tn-empty', text: T('ui_no_match') });
        empty.hidden = true;

        if (node.options.length > 14) {
            const input = el('input', { attrs: { type: 'search', placeholder: T('ui_search'), 'aria-label': T('ui_search'), autocomplete: 'off', 'data-nav': 'search', maxlength: '40' } });
            input.value = S.search[node.id] || '';
            const apply = () => {
                const q = input.value.trim().toLowerCase();
                S.search[node.id] = input.value;
                let shown = 0;
                rows.forEach((r) => { const ok = !q || r.__label.indexOf(q) !== -1; r.hidden = !ok; if (ok) shown++; });
                empty.hidden = shown > 0;
            };
            input.addEventListener('input', apply);
            out.push(el('div', { class: 'tn-search' }, [icon('fa-solid fa-magnifying-glass'), input]));
            apply();
        }

        box.addEventListener('mouseleave', () => {
            const act = document.activeElement;
            if (act && box.contains(act)) act.blur();
            restorePreview(node);
        });
        box.addEventListener('focusout', (e) => { if (!e.relatedTarget || !box.contains(e.relatedTarget)) restorePreview(node); });
        out.push(box, empty);
        return out;
    }

    function finishOf(groupId) {
        return { metallic: 'f-metallic', matte: 'f-matte', metals: 'f-metals', chrome: 'f-chrome', worn: 'f-worn', chameleon: 'f-chameleon' }[groupId] || 'f-metallic';
    }

    function makeSwatch(c, finish, selected, isOrig) {
        const b = el('button', {
            class: 'tn-swatch ' + finish + (isOrig ? ' is-orig' : ''),
            attrs: { type: 'button', role: 'radio', 'data-nav': 'swatch', 'data-value': String(c.index), 'aria-checked': selected ? 'true' : 'false', 'aria-label': c.label, title: c.label },
        });
        b.style.setProperty('--c', c.hex);
        if (finish === 'f-chameleon') {
            b.style.backgroundImage = 'linear-gradient(135deg,' + c.hex + ' 0%,' + hueShift(c.hex, 75) + ' 55%,' + hueShift(c.hex, -70) + ' 100%)';
        }
        return b;
    }

    function buildColourLeaf(node) {
        const startGroup = () => {
            if (S.colourTab[node.id] && node.groups.some((g) => g.id === S.colourTab[node.id])) return S.colourTab[node.id];
            const withCur = node.groups.find((g) => g.colours.some((c) => c.index === S.cur[node.id]));
            return (withCur || node.groups[0]).id;
        };
        S.colourTab[node.id] = startGroup();

        const tabs = el('div', { class: 'tn-tabs', attrs: { role: 'tablist' } });
        const nameText = el('span');
        const nameTag = el('span', { class: 'tn-tag', text: T('ui_installed') });
        nameTag.hidden = true;
        const nameLine = el('div', { class: 'tn-colour-name', attrs: { 'aria-live': 'polite' } }, [nameText, nameTag]);
        const grid = el('div', { class: 'tn-grid', attrs: { role: 'radiogroup', 'aria-label': node.label } });

        const showName = (index) => {
            nameText.textContent = colourName(index);
            nameTag.hidden = !(index === S.orig[node.id] && index !== S.cur[node.id]);
        };
        node.__showName = showName;

        const fillGrid = () => {
            const g = node.groups.find((x) => x.id === S.colourTab[node.id]) || node.groups[0];
            const finish = finishOf(g.id);
            grid.replaceChildren(...g.colours.map((c) => {
                const b = makeSwatch(c, finish, c.index === S.cur[node.id], c.index === S.orig[node.id]);
                b.addEventListener('click', () => setValue(node, c.index));
                b.addEventListener('focus', () => { showName(c.index); hoverPreview(node, c.index); });
                b.addEventListener('mouseenter', () => showName(c.index));
                bindFocus(b);
                return b;
            }));
            qa(tabs, '.tn-tab').forEach((t) => {
                const on = t.dataset.group === g.id;
                t.setAttribute('aria-selected', on ? 'true' : 'false');
                if (on && tabs.scrollWidth > tabs.clientWidth) tabs.scrollLeft = Math.max(0, t.offsetLeft - 24);
            });
            showName(S.cur[node.id]);
        };

        tabs.addEventListener('wheel', (e) => {
            if (tabs.scrollWidth <= tabs.clientWidth) return;
            e.preventDefault();
            e.stopPropagation();
            tabs.scrollLeft += e.deltaY;
        }, { passive: false });

        node.groups.forEach((g) => {
            tabs.append(el('button', {
                class: 'tn-tab',
                attrs: { type: 'button', role: 'tab', 'data-nav': 'tab', 'data-group': g.id, 'aria-selected': 'false' },
                text: g.label,
                on: { click: () => { S.colourTab[node.id] = g.id; fillGrid(); paintLeaf(); } },
            }));
        });
        fillGrid();

        grid.addEventListener('mouseleave', () => {
            const act = document.activeElement;
            if (act && grid.contains(act)) act.blur();
            showName(S.cur[node.id]);
            restorePreview(node);
        });
        grid.addEventListener('focusout', (e) => {
            if (!e.relatedTarget || !grid.contains(e.relatedTarget)) { showName(S.cur[node.id]); restorePreview(node); }
        });
        return [tabs, nameLine, grid];
    }

    const RGB_PRESETS = ['#ffffff', '#ff1f1f', '#ff7a00', '#ffe600', '#7be22a', '#2ee6a6', '#14a8ff', '#1f3bff', '#8a2be2', '#ff1fa1'];

    function buildRgbLeaf(node) {
        const wrap = el('div', { class: 'tn-rgb' });
        const picker = el('input', { class: 'tn-rgb-preview', attrs: { type: 'color', 'aria-label': T('ui_pick_colour'), title: T('ui_pick_colour'), 'data-nav': 'misc' } });
        const hexIn = el('input', { attrs: { type: 'text', maxlength: '7', spellcheck: 'false', autocomplete: 'off', 'aria-label': 'HEX', 'data-nav': 'misc' } });
        const sliders = {};
        const apply = (rgb) => {
            if (!rgb) return;
            setValue(node, { r: rgb.r, g: rgb.g, b: rgb.b });
        };
        const sliderRow = (ch) => {
            const input = el('input', { attrs: { type: 'range', min: '0', max: '255', step: '1', 'aria-label': ch.toUpperCase(), 'data-nav': 'misc' } });
            const out = el('output', { text: '0' });
            input.addEventListener('input', () => {
                const c = Object.assign({}, S.cur[node.id]);
                c[ch] = int(input.value);
                apply(c);
            });
            sliders[ch] = { input, out };
            return el('label', { class: 'tn-slider' }, [el('span', { text: ch.toUpperCase() }), input, out]);
        };

        const presets = el('div', { class: 'tn-presets', attrs: { role: 'group' } });
        RGB_PRESETS.forEach((hex) => {
            const b = el('button', { class: 'tn-swatch f-matte', attrs: { type: 'button', 'aria-label': hex, title: hex.toUpperCase(), 'data-nav': 'misc' } });
            b.style.setProperty('--c', hex);
            b.dataset.hex = hex;
            b.addEventListener('click', () => apply(hexToRgb(hex)));
            presets.append(b);
        });

        node.__paint = () => {
            const c = S.cur[node.id];
            const hex = rgbToHex(c);
            if (picker.value !== hex) picker.value = hex;
            if (document.activeElement !== hexIn) hexIn.value = hex.toUpperCase();
            ['r', 'g', 'b'].forEach((ch) => {
                sliders[ch].input.value = String(c[ch]);
                sliders[ch].out.textContent = String(c[ch]);
            });
            qa(presets, '.tn-swatch').forEach((b) => b.setAttribute('aria-checked', b.dataset.hex === hex ? 'true' : 'false'));
            // Slider tracks show what the other two channels currently are
            sliders.r.input.style.setProperty('--track', 'linear-gradient(90deg,' + rgbToHex({ r: 0, g: c.g, b: c.b }) + ',' + rgbToHex({ r: 255, g: c.g, b: c.b }) + ')');
            sliders.g.input.style.setProperty('--track', 'linear-gradient(90deg,' + rgbToHex({ r: c.r, g: 0, b: c.b }) + ',' + rgbToHex({ r: c.r, g: 255, b: c.b }) + ')');
            sliders.b.input.style.setProperty('--track', 'linear-gradient(90deg,' + rgbToHex({ r: c.r, g: c.g, b: 0 }) + ',' + rgbToHex({ r: c.r, g: c.g, b: 255 }) + ')');
        };

        picker.addEventListener('input', () => apply(hexToRgb(picker.value)));
        hexIn.addEventListener('input', () => {
            const v = hexIn.value.trim();
            const rgb = hexToRgb(v.charAt(0) === '#' ? v : '#' + v);
            if (rgb && /^#?[0-9a-f]{6}$/i.test(v)) apply(rgb);
        });
        hexIn.addEventListener('blur', () => { hexIn.value = rgbToHex(S.cur[node.id]).toUpperCase(); });

        wrap.append(picker, el('div', { class: 'tn-rgb-hex' }, [hexIn]), sliderRow('r'), sliderRow('g'), sliderRow('b'), presets);
        return [wrap];
    }

    // Selected / installed markers in the open leaf
    function paintLeaf() {
        const node = currentLeaf();
        if (!ui || !node || node.type === 'performance') return;
        const cur = S.cur[node.id];
        if (node.type === 'colour') {
            qa(ui.view, '.tn-swatch').forEach((b) => b.setAttribute('aria-checked', int(b.dataset.value) === cur ? 'true' : 'false'));
            if (node.__showName) node.__showName(cur);
            return;
        }
        if (node.type === 'rgb') {
            if (node.__paint) node.__paint();
            return;
        }
        qa(ui.view, '.tn-opt').forEach((r) => {
            const sel = r.__value === cur;
            r.setAttribute('aria-checked', sel ? 'true' : 'false');
            r.__tag.hidden = !(r.__value === S.orig[node.id] && !sel);
        });
    }

    // ---------------------------------------------------------------------------------------------
    // Presets view (C): built-in + own presets for this model, apply, delete, save the cart
    // ---------------------------------------------------------------------------------------------

    async function loadPresets() {
        const session = S.session;
        S.presets.state = 'loading';
        if (inPresets() && ui) renderView(0);
        const res = await post('tuning:presets', {});
        if (session !== S.session || !S.open) return;
        if (res && res.ok) {
            S.presets.builtin = (Array.isArray(res.builtin) ? res.builtin : []).map((p) => ({ id: str(p && p.id, 64), label: str(p && (p.label || p.name || p.id), 60) })).filter((p) => p.id);
            S.presets.mine = (Array.isArray(res.mine) ? res.mine : []).map((p) => ({ id: int(p && p.id), name: str(p && p.name, 60) })).filter((p) => p.id > 0);
            S.presets.state = 'ready';
        } else {
            S.presets.state = 'error';
            S.presets.error = (res && typeof res.error === 'string' && res.error) ? res.error.slice(0, 160) : T('ui_presets_error');
        }
        if (inPresets() && ui) renderView(0);
    }

    function presetRow(title, desc, onApply, trailKids) {
        const row = el('div', { class: 'tn-preset' });
        const btn = el('button', { class: 'tn-row', attrs: { type: 'button', 'data-nav': 'row' }, on: { click: onApply } }, [
            el('span', { class: 'tn-row-icon' }, [icon('fa-solid fa-bookmark')]),
            el('span', { class: 'tn-row-text' }, [el('span', { class: 'tn-row-title', text: title }), el('span', { class: 'tn-row-desc', text: desc || ' ' })]),
            el('span', { class: 'tn-row-trail' }, [el('span', { class: 'tn-row-action', text: T('ui_preset_apply') })]),
        ]);
        btn.disabled = S.presetBusy || S.busy;
        bindFocus(btn);
        row.append(btn);
        (trailKids || []).forEach((k) => row.append(k));
        return row;
    }

    function buildPresets() {
        const out = [];
        const st = S.presets.state;
        if (st === 'loading' || st === 'idle') {
            out.push(el('p', { class: 'tn-empty', text: T('ui_presets_loading') }));
        } else if (st === 'error') {
            out.push(el('p', { class: 'tn-empty is-error', text: S.presets.error }));
            const retry = el('button', { class: 'tn-btn is-secondary is-small', text: T('ui_retry'), attrs: { type: 'button', 'data-nav': 'row' }, on: { click: loadPresets } });
            out.push(el('div', { class: 'tn-section-actions' }, [retry]));
        } else {
            if (S.presets.builtin.length) {
                out.push(el('h2', { class: 'tn-section', text: T('ui_presets_builtin') }));
                const box = el('div', { class: 'tn-list' });
                S.presets.builtin.forEach((p) => box.append(presetRow(p.label, null, () => applyPreset(p.id))));
                out.push(box);
            }
            out.push(el('h2', { class: 'tn-section', text: T('ui_presets_mine') }));
            if (!S.presets.mine.length) {
                out.push(el('p', { class: 'tn-empty', text: T('ui_presets_empty') }));
            } else {
                const box = el('div', { class: 'tn-list' });
                S.presets.mine.forEach((p) => {
                    const del = el('button', {
                        class: 'tn-iconbtn tn-preset-del',
                        attrs: { type: 'button', 'data-nav': 'row', 'aria-label': T('ui_preset_delete') + ' ' + p.name, title: T('ui_preset_delete') },
                        on: { click: () => { S.deleteId = p.id; S.sheet = 'delete'; renderSheet(); } },
                    }, [icon('fa-solid fa-trash-can')]);
                    del.disabled = S.presetBusy || S.busy;
                    bindFocus(del);
                    box.append(presetRow(p.name, T('ui_preset_model'), () => applyPreset(p.id), [del]));
                });
                out.push(box);
            }
        }
        const save = el('button', {
            class: 'tn-btn is-secondary tn-wide' + (S.presetBusy ? ' is-busy' : ''),
            attrs: { type: 'button', 'data-nav': 'row', 'data-key': 'preset-save' },
            on: { click: savePreset },
        }, [icon(S.presetBusy ? 'fa-solid fa-circle-notch' : 'fa-solid fa-floppy-disk'), el('span', { text: T('ui_preset_save') })]);
        save.disabled = S.presetBusy || S.busy;
        bindFocus(save);
        out.push(el('div', { class: 'tn-section-actions' }, [save]));
        return out;
    }

    // Run one preset-type call at a time; the UI is locked meanwhile
    async function presetCall(name, body, onOk) {
        if (S.presetBusy || S.busy) return null;
        const session = S.session;
        S.presetBusy = true;
        refreshPresetUi();
        let res = null;
        try {
            res = await post(name, body);
        } finally {
            if (session === S.session) S.presetBusy = false;
        }
        if (session !== S.session || !S.open) return null;
        if (res && res.ok && onOk) onOk(res);
        refreshPresetUi();
        return res;
    }

    function refreshPresetUi() {
        if (!ui) return;
        renderBanners();
        if (inPresets()) renderView(0);
        renderFoot();
    }

    function applyPreset(id) {
        presetCall('tuning:presetApply', { id }, mergeLoaded);
    }

    function savePreset() {
        presetCall('tuning:presetSave', cartPayload(), () => { S.presets.state = 'idle'; loadPresets(); });
    }

    function deletePreset(id) {
        S.sheet = null;
        renderSheet();
        presetCall('tuning:presetDelete', { id }, () => {
            S.presets.mine = S.presets.mine.filter((p) => p.id !== id);
        });
    }

    function loadLast() {
        presetCall('tuning:loadLast', {}, (res) => { S.lastCart = null; mergeLoaded(res); });
    }

    function loadWorkOrder() {
        presetCall('tuning:workorderLoad', {}, (res) => { S.workOrder = null; mergeLoaded(res); });
    }

    // ---------------------------------------------------------------------------------------------
    // Footer bar (fixed height) + sheet above it (cart / swap confirm / delete confirm). The sheet
    // overlays the list instead of pushing it up, so nothing in the panel moves (A2).
    // ---------------------------------------------------------------------------------------------

    function renderFoot() {
        if (!ui) return;
        const act = document.activeElement;
        const refocus = act && ui.foot.contains(act) ? act.dataset.key : null;
        const count = cartCount();
        const total = cartTotal();

        const toggle = el('button', {
            class: 'tn-cart-toggle',
            attrs: { type: 'button', 'aria-expanded': S.sheet === 'cart' ? 'true' : 'false', 'data-key': 'cart-toggle' },
            on: { click: () => { S.sheet = S.sheet === 'cart' ? null : 'cart'; renderSheet(); renderFoot(); } },
        }, [
            icon('fa-solid fa-cart-shopping'),
            el('span', { class: 'tn-cart-title', text: T('ui_cart') }),
            count ? el('span', { class: 'tn-count', text: String(count) }) : null,
            icon('fa-solid fa-chevron-up tn-cart-chev'),
        ]);

        const totalBox = el('span', { class: 'tn-cart-total', attrs: { title: isDesign() ? T('ui_estimate_total') : T('ui_total') } }, [
            el('span', { class: 'tn-cart-total-label', text: isDesign() ? T('ui_estimate_total') : T('ui_total') }),
            el('span', { class: 'tn-cart-total-value', text: money(total) }),
        ]);

        let primary;
        if (isDesign()) {
            primary = el('button', {
                class: 'tn-btn is-primary' + (S.busy ? ' is-busy' : ''),
                attrs: { type: 'button', 'data-key': 'send' },
                on: { click: sendToMechanic },
            }, [icon(S.busy ? 'fa-solid fa-circle-notch' : 'fa-solid fa-paper-plane'), el('span', { text: T('ui_send_mechanic') })]);
        } else {
            primary = el('button', {
                class: 'tn-btn is-primary' + (S.busy ? ' is-busy' : ''),
                attrs: { type: 'button', 'data-key': 'install' },
                on: { click: installAll },
            }, [icon(S.busy ? 'fa-solid fa-circle-notch' : 'fa-solid fa-wrench'), el('span', { text: T('ui_install') })]);
        }
        primary.disabled = !count || S.busy || S.presetBusy;

        ui.foot.classList.toggle('is-open', S.sheet === 'cart');
        ui.foot.replaceChildren(el('div', { class: 'tn-cart-bar' }, [toggle, totalBox, primary]));
        if (refocus) {
            const again = ui.foot.querySelector('[data-key="' + refocus + '"]');
            if (again && !again.disabled) again.focus({ preventScroll: true });
        }
    }

    function closeSheet() {
        if (!S.sheet) return;
        const was = S.sheet;
        S.sheet = null;
        if (was === 'swap') { S.swapPick = null; refreshLevels(); }
        renderSheet();
        renderFoot();
        if (was === 'cart') { const t = ui.foot.querySelector('[data-key="cart-toggle"]'); if (t) t.focus({ preventScroll: true }); }
        else focusInitial();
    }

    function sheetHead(title) {
        return el('div', { class: 'tn-sheet-head' }, [
            el('span', { class: 'tn-sheet-title', text: title }),
            el('button', { class: 'tn-iconbtn', attrs: { type: 'button', 'aria-label': T('ui_close'), title: T('ui_close') }, on: { click: closeSheet } }, [icon('fa-solid fa-xmark')]),
        ]);
    }

    function renderSheet() {
        if (!ui) return;
        const sheet = ui.sheet;
        if (!S.sheet) { sheet.hidden = true; sheet.replaceChildren(); return; }
        sheet.hidden = false;
        sheet.className = 'tn-sheet is-' + S.sheet;

        if (S.sheet === 'cart') {
            const list = el('div', { class: 'tn-cart-list', attrs: { role: 'list' } });
            const cart = cartEntries();
            const swaps = swapList();
            if (!cart.length && !swaps.length) list.append(el('p', { class: 'tn-empty', text: T('ui_empty_cart') }));
            cart.forEach((e) => list.append(cartLine(e.name, e.detail, e.shared ? '' : priceText(e.price), () => revert(e.node))));
            swaps.forEach((s) => {
                let detail = s.levelLabel;
                let cls = '';
                let price = '';
                if (isDesign()) price = s.price > 0 ? priceText(s.price) : '';
                else if (s.level > 0 && s.item) {
                    const missing = s.stock !== null && s.stock < 1;
                    detail += ' · ' + (missing ? T('ui_needs_stock') : T('ui_from_stock'));
                    if (missing) cls = 'is-error';
                }
                list.append(cartLine(s.label, detail, price, () => { delete S.swaps[s.category]; afterChange(); refreshLevels(); }, cls));
            });
            sheet.replaceChildren(sheetHead(T('ui_cart')), list);
            return;
        }

        if (S.sheet === 'swap') {
            const pick = S.swapPick;
            const node = pick && S.perf.get(pick.category);
            const o = node && node.options.find((x) => x.level === pick.level);
            if (!node || !o) { S.sheet = null; sheet.hidden = true; return; }
            const kids = [el('p', { class: 'tn-sheet-text', text: T('ui_swap_confirm', node.label, o.label) })];
            const notes = [];
            if (S.manualSwap) notes.push(T('ui_swap_manual'));
            if (cartEntries().length || swapList().length) notes.push(T('ui_swap_discard'));
            if (notes.length) kids.push(el('p', { class: 'tn-sheet-note', text: notes.join(' ') }));
            const addBtn = el('button', { class: 'tn-btn is-secondary', text: T('ui_add_to_cart'), attrs: { type: 'button', 'data-key': 'swap-add' }, on: { click: () => { setSwap(node, o); closeSheet(); } } });
            const nowBtn = el('button', { class: 'tn-btn is-primary' + (S.busy ? ' is-busy' : ''), attrs: { type: 'button', 'data-key': 'swap-do' }, on: { click: confirmSwap } }, [
                S.busy ? icon('fa-solid fa-circle-notch') : null, el('span', { text: T('ui_swap_now') }),
            ]);
            nowBtn.disabled = S.busy;
            addBtn.disabled = S.busy;
            kids.push(el('div', { class: 'tn-sheet-actions' }, [
                el('button', { class: 'tn-btn is-ghost', text: T('ui_cancel'), attrs: { type: 'button', 'data-key': 'swap-cancel' }, on: { click: closeSheet } }),
                addBtn, nowBtn,
            ]));
            sheet.replaceChildren(...kids);
            if (!S.busy) nowBtn.focus({ preventScroll: true });
            return;
        }

        if (S.sheet === 'delete') {
            const p = S.presets.mine.find((x) => x.id === S.deleteId);
            if (!p) { S.sheet = null; sheet.hidden = true; return; }
            const delBtn = el('button', { class: 'tn-btn is-danger', text: T('ui_preset_delete'), attrs: { type: 'button', 'data-key': 'del-do' }, on: { click: () => deletePreset(p.id) } });
            sheet.replaceChildren(
                el('p', { class: 'tn-sheet-text', text: T('ui_preset_delete_confirm', p.name) }),
                el('div', { class: 'tn-sheet-actions' }, [
                    el('button', { class: 'tn-btn is-secondary', text: T('ui_preset_keep'), attrs: { type: 'button', 'data-key': 'del-keep' }, on: { click: closeSheet } }),
                    delBtn,
                ]),
            );
            delBtn.focus({ preventScroll: true });
        }
    }

    function cartLine(name, detail, price, onUndo, cls) {
        return el('div', { class: 'tn-cart-line', attrs: { role: 'listitem' } }, [
            el('span', { class: 'tn-row-text' }, [
                el('span', { class: 'tn-row-title', text: name, attrs: { title: name } }),
                el('span', { class: 'tn-row-desc' + (cls ? ' ' + cls : ''), text: detail || ' ', attrs: { title: detail || null } }),
            ]),
            el('span', { class: 'tn-cart-price', text: price }),
            el('button', { class: 'tn-iconbtn', attrs: { type: 'button', 'aria-label': T('ui_undo') + ' ' + name, title: T('ui_undo') }, on: { click: onUndo } }, [icon('fa-solid fa-xmark')]),
        ]);
    }

    function shake(node) {
        if (!node) return;
        node.classList.remove('is-shake');
        void node.offsetWidth;
        node.classList.add('is-shake');
    }

    async function installAll() {
        if (S.busy || S.presetBusy || isDesign() || !cartCount()) return;
        const session = S.session;
        S.busy = true;
        renderFoot();
        resetPreviewState();
        const res = await post('tuning:install', cartPayload());
        if (session !== S.session) return;
        S.busy = false;
        if (res && res.ok) hide();
        else { renderFoot(); shake(ui && ui.foot); }
    }

    async function sendToMechanic() {
        if (S.busy || S.presetBusy || !isDesign() || !cartCount()) return;
        const session = S.session;
        S.busy = true;
        renderFoot();
        const res = await post('tuning:workorderSend', cartPayload());
        if (session !== S.session) return;
        S.busy = false;
        // On success Lua closes the screen (closeTuning); until then the button stays as it is
        if (!(res && res.ok)) { renderFoot(); shake(ui && ui.foot); }
        else renderFoot();
    }

    async function confirmSwap() {
        const pick = S.swapPick;
        if (!pick || S.busy || isDesign() || !S.data.vehicle.owned) return;
        const session = S.session;
        S.busy = true;
        renderSheet();
        renderFoot();
        const res = await post('tuning:swap', { category: pick.category, level: pick.level });
        if (session !== S.session) return;
        S.busy = false;
        if (res && res.ok) hide();
        else { renderSheet(); renderFoot(); shake(ui && ui.sheet); }
    }

    // ---------------------------------------------------------------------------------------------
    // Open / close / suspend
    // ---------------------------------------------------------------------------------------------

    function open(raw) {
        raw = raw && typeof raw === 'object' ? raw : {};
        clearTimeout(leaveTimer);
        clearTimeout(orderTimer);
        resetPreviewState();

        const v = raw.vehicle || {};
        const groups = (Array.isArray(raw.groups) ? raw.groups : []).map((g) => ({
            id: str(g && g.id, 40),
            label: str(g && g.label, 60),
            icon: g && g.icon,
            items: (Array.isArray(g && g.items) ? g.items : []).map((n) => normNode(n, 0)).filter(Boolean),
        })).filter((g) => g.items.length > 0);
        if (!groups.length) { post('tuning:close', {}); return; }

        S.session += 1;
        S.mode = raw.mode === 'design' ? 'design' : 'mechanic';
        S.manualSwap = raw.manualSwap === true;
        S.data = {
            vehicle: {
                label: str(v.label, 60),
                plate: str(v.plate, 12).trim(),
                owned: v.owned === true,
                plateIndex: clamp(int(v.plateIndex), 0, 99),
                plateStyle: v.plateStyle && typeof v.plateStyle === 'object' ? v.plateStyle : {},
            },
        };
        S.groups = groups;
        S.gi = 0;
        S.nav = [];
        S.cur = {}; S.orig = {}; S.touched = {}; S.seq = 0;
        S.nodes = new Map(); S.bases = new Map(); S.perf = new Map(); S.colourNames = new Map();
        S.swaps = {};
        S.colourTab = {}; S.search = {}; S.memory = {};
        S.swapPick = null; S.sheet = null; S.deleteId = null;
        S.order = { busy: false, item: null, until: 0, ordered: {}, error: {} };
        S.presets = { state: 'idle', builtin: [], mine: [], error: '' };
        S.presetBusy = false;
        S.busy = false;
        S.suspended = false;
        S.cam = 'default';
        const lc = raw.lastCart;
        S.lastCart = lc && typeof lc === 'object' && int(lc.count) > 0 ? { count: int(lc.count) } : null;
        const wo = raw.workOrder;
        S.workOrder = S.mode === 'mechanic' && wo && typeof wo === 'object' ? { owner: str(wo.owner, 60), count: Math.max(0, int(wo.count)) } : null;
        groups.forEach((g, i) => indexNodes(g.items, i));

        S.open = true;
        buildSkeleton();
        renderBanners();
        root.classList.remove('is-leaving', 'is-suspended');
        root.classList.add('is-open');
        root.hidden = false;
        renderAll(1);
    }

    function hide() {
        if (!S.open) return;
        S.open = false;
        S.session += 1;
        endDrag();
        resetPreviewState();
        clearTimeout(orderTimer);
        root.classList.add('is-leaving');
        root.classList.remove('is-open', 'is-suspended');
        clearTimeout(leaveTimer);
        leaveTimer = setTimeout(() => {
            if (S.open) return;
            root.hidden = true;
            root.classList.remove('is-leaving', 'is-dragging');
            root.replaceChildren();
            ui = null;
        }, 200);
    }

    function closeScreen() {
        if (!S.open || S.busy) return;
        // The cart goes with the close: Lua keeps it for "Indlæs sidste"
        const payload = cartPayload();
        hide();
        post('tuning:close', payload);
    }

    function suspend(on) {
        S.suspended = !!on;
        if (S.suspended) endDrag();
        root.classList.toggle('is-suspended', S.suspended && S.open);
    }

    // ---------------------------------------------------------------------------------------------
    // Camera: drag on the free area = orbit, wheel = zoom (both throttled to 30/s)
    // ---------------------------------------------------------------------------------------------

    const FLUSH_MS = 34;
    let drag = null;
    let zoomAcc = 0;
    let zoomTimer = 0;
    let zoomLast = 0;

    function flushOrbit() {
        if (!drag) return;
        const dx = Math.round(drag.ax), dy = Math.round(drag.ay);
        if (dx === 0 && dy === 0) return;
        drag.ax -= dx; drag.ay -= dy;
        post('tuning:orbit', { dx, dy });
    }

    function endDrag() {
        if (!drag) return;
        flushOrbit();
        clearInterval(drag.timer);
        try { root.releasePointerCapture(drag.id); } catch (e) { /* already released */ }
        drag = null;
        root.classList.remove('is-dragging');
    }

    root.addEventListener('pointerdown', (e) => {
        if (!S.open || S.suspended || drag || (e.button !== 0 && e.button !== 2)) return;
        if (e.target.closest('.tn-panel, .tn-dock')) return;
        e.preventDefault();
        try { root.setPointerCapture(e.pointerId); } catch (err) { /* synthetic pointer */ }
        drag = { id: e.pointerId, x: e.clientX, y: e.clientY, ax: 0, ay: 0, timer: setInterval(flushOrbit, FLUSH_MS), moved: false };
        root.classList.add('is-dragging');
    });

    root.addEventListener('pointermove', (e) => {
        if (!drag || e.pointerId !== drag.id) return;
        drag.ax += e.clientX - drag.x;
        drag.ay += e.clientY - drag.y;
        drag.x = e.clientX;
        drag.y = e.clientY;
        if (!drag.moved && (Math.abs(drag.ax) + Math.abs(drag.ay) > 2)) {
            drag.moved = true;
            if (S.cam) { S.cam = ''; paintCameras(); } // a dragged view is no preset any more
        }
    });

    root.addEventListener('pointerup', (e) => { if (drag && e.pointerId === drag.id) endDrag(); });
    root.addEventListener('pointercancel', (e) => { if (drag && e.pointerId === drag.id) endDrag(); });
    root.addEventListener('lostpointercapture', () => endDrag());
    root.addEventListener('contextmenu', (e) => { if (S.open) e.preventDefault(); });

    function flushZoom() {
        zoomTimer = 0;
        if (!zoomAcc) return;
        const delta = zoomAcc;
        zoomAcc = 0;
        zoomLast = performance.now();
        post('tuning:zoom', { delta });
    }

    // delta > 0 = wheel down (move away), < 0 = wheel up (move closer); one notch = 1, at most +-3 per send
    root.addEventListener('wheel', (e) => {
        if (!S.open || S.suspended) return;
        if (e.target.closest('.tn-panel')) return;
        e.preventDefault();
        const notches = clamp(Math.round(Math.abs(e.deltaY) / 100) || 1, 1, 3);
        zoomAcc = clamp(zoomAcc + (e.deltaY > 0 ? notches : -notches), -3, 3);
        const wait = FLUSH_MS - (performance.now() - zoomLast);
        if (wait <= 0) flushZoom();
        else if (!zoomTimer) zoomTimer = setTimeout(flushZoom, wait);
    }, { passive: false });

    // ---------------------------------------------------------------------------------------------
    // Keyboard: arrows, Enter/Space (native button click), Backspace = back, Escape = back/close,
    // PageUp/Down = group
    // ---------------------------------------------------------------------------------------------

    function visible(nodes) {
        return nodes.filter((n) => !n.hidden && !n.disabled && n.getClientRects().length > 0);
    }

    function focusNode(n) {
        if (!n) return;
        n.focus({ preventScroll: true });
        n.scrollIntoView({ block: 'nearest' });
    }

    function scope() {
        // Keyboard focus moves inside the open sheet, else inside the view
        return S.sheet && !ui.sheet.hidden ? ui.sheet : ui.view;
    }

    function moveVertical(dir) {
        const act = document.activeElement;
        if (act && ui.rail.contains(act)) {
            const btns = qa(ui.rail, '.tn-rail-btn');
            const i = btns.indexOf(act);
            focusNode(btns[clamp(i + dir, 0, btns.length - 1)]);
            return;
        }
        if (act && act.classList.contains('tn-swatch') && act.closest('.tn-grid')) {
            const grid = act.parentElement;
            const sw = qa(grid, '.tn-swatch');
            const cols = Math.max(1, getComputedStyle(grid).gridTemplateColumns.split(' ').length);
            const j = sw.indexOf(act) + dir * cols;
            if (j < 0) {
                const tab = ui.view.querySelector('.tn-tab[aria-selected="true"]');
                if (tab) focusNode(tab);
            } else if (j < sw.length) focusNode(sw[j]);
            return;
        }
        if (act && act.classList.contains('tn-tab')) {
            if (dir > 0) focusNode(ui.view.querySelector('.tn-swatch[aria-checked="true"]') || ui.view.querySelector('.tn-swatch'));
            return;
        }
        const box = scope();
        const items = visible(qa(box, '[data-nav], .tn-btn, .tn-iconbtn').filter((n) => !n.classList.contains('tn-swatch') || n.closest('.tn-presets')));
        if (!items.length) return;
        const i = items.indexOf(act);
        if (i === -1) { focusNode(items[dir > 0 ? 0 : items.length - 1]); return; }
        focusNode(items[clamp(i + dir, 0, items.length - 1)]);
    }

    function moveHorizontal(dir) {
        const act = document.activeElement;
        if (!act) return;
        if (ui.rail.contains(act)) {
            if (dir > 0) focusInitial();
            return;
        }
        if (act.classList.contains('tn-tab')) {
            const tabs = qa(ui.view, '.tn-tab');
            const t = tabs[clamp(tabs.indexOf(act) + dir, 0, tabs.length - 1)];
            if (t && t !== act) { t.click(); focusNode(ui.view.querySelector('.tn-tab[aria-selected="true"]')); }
            return;
        }
        if (act.classList.contains('tn-swatch')) {
            const sw = qa(act.parentElement, '.tn-swatch');
            focusNode(sw[clamp(sw.indexOf(act) + dir, 0, sw.length - 1)]);
            return;
        }
        if (S.sheet) return;
        if (dir < 0) {
            if (S.nav.length) goBack();
            else focusNode(ui.rail.querySelector('.tn-rail-btn.is-active'));
            return;
        }
        if (act.dataset.open === '1') act.click();
    }

    document.addEventListener('keydown', (e) => {
        if (!S.open || root.hidden || !ui || S.suspended) return;
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        const tgt = e.target;
        const tag = tgt && tgt.tagName;
        const typing = tag === 'INPUT' && tgt.type !== 'range' && tgt.type !== 'color' && tgt.type !== 'checkbox';
        const range = tag === 'INPUT' && (tgt.type === 'range' || tgt.type === 'color');

        // Held keys repeat: never let a repeated Enter/Space click a button again (A3)
        if (e.repeat && (e.key === 'Enter' || e.key === ' ') && tag === 'BUTTON') { e.preventDefault(); return; }

        switch (e.key) {
            case 'Escape':
                e.preventDefault();
                if (S.busy) return;
                if (!goBack()) closeScreen();
                break;
            case 'Backspace':
                if (typing) return;
                e.preventDefault();
                if (!S.busy) goBack();
                break;
            case 'PageDown':
            case 'PageUp':
                e.preventDefault();
                if (!S.busy && !S.sheet) stepGroup(e.key === 'PageDown' ? 1 : -1);
                break;
            case 'ArrowDown':
            case 'ArrowUp':
                if (range) return;
                if (typing && tgt.type !== 'search') return;
                e.preventDefault();
                moveVertical(e.key === 'ArrowDown' ? 1 : -1);
                break;
            case 'ArrowLeft':
            case 'ArrowRight':
                if (typing || range) return;
                e.preventDefault();
                moveHorizontal(e.key === 'ArrowRight' ? 1 : -1);
                break;
            default:
        }
    });

    // ---------------------------------------------------------------------------------------------
    // NUI messages
    // ---------------------------------------------------------------------------------------------

    App.on('openTuning', open);
    App.on('closeTuning', () => { hide(); });
    App.on('tuning:suspend', (d) => suspend(d && d.on));

    // ---------------------------------------------------------------------------------------------
    // Demo mode (page opened in a normal browser): window.__demo(opts) renders a realistic payload.
    // opts: { mode: 'mechanic'|'design', plateIndex, owned, workOrder, lastCart, plateImage }
    // window.__demoFail = true makes orders fail; window.__demoSuspend(on) simulates a core dialog.
    // ---------------------------------------------------------------------------------------------

    if (!App.isGame) {
        const DEMO_LOCALE = Object.assign({}, FALLBACK);
        const wait = (ms) => new Promise((r) => setTimeout(r, ms));
        let demoMine = [{ id: 11, name: 'Gadebil sort' }, { id: 12, name: 'Kundens favorit' }];
        let demoNext = 20;
        let demoMode = 'mechanic';

        const PERF_DEMO = {
            engine: ['Motor', [3, 1, 0, 0], [6000, 11000, 18000, 27000]],
            brakes: ['Bremser', [2, 0, 0], [3000, 6000, 10000]],
            transmission: ['Gearkasse', [4, 2, 0], [5000, 9000, 14000]],
            suspension: ['Undervogn', [1, 1, 0, 0], [2500, 4500, 7000, 10000]],
            armor: ['Panser', [0, 0, 0, 0, 0], [5000, 9000, 14000, 20000, 28000]],
            turbo: ['Turbo', [0], [15000]],
        };
        const PERF_CURRENT = { engine: 2, brakes: 0, transmission: 1, suspension: 0, armor: 0, turbo: 0 };

        const demoSwap = (cat, level) => {
            const [label, stock, prices] = PERF_DEMO[cat];
            const s = { category: cat, level, current: PERF_CURRENT[cat], label, levelLabel: cat === 'turbo' ? 'Turbo' : 'Niveau ' + level, price: prices[level - 1] || 0 };
            if (demoMode === 'mechanic' && level > 0) { s.item = cat + '_lvl' + level; s.stock = stock[level - 1] || 0; }
            return s;
        };

        demoPost = async (name, body) => {
            switch (name) {
                case 'tuning:order':
                    await wait(450);
                    if (window.__demoFail) return { ok: false, error: 'Firmakontoen har ikke penge nok til bestillingen.' };
                    return { ok: true, eta: 300 };
                case 'tuning:presets':
                    await wait(250);
                    return { ok: true, builtin: [{ id: 'max_performance', label: 'Maks performance' }], mine: demoMine.slice() };
                case 'tuning:presetApply':
                    await wait(250);
                    if (body.id === 'max_performance') {
                        return { ok: true, name: 'Maks performance', changes: [], swaps: Object.keys(PERF_DEMO).map((c) => demoSwap(c, PERF_DEMO[c][1].length)).filter((s) => s.level !== s.current) };
                    }
                    return { ok: true, changes: [{ id: 'modSpoilers', value: 5 }, { id: 'color1', value: 0 }, { id: 'neonLeft', value: true }, { id: 'neonRight', value: true }], swaps: [demoSwap('brakes', 1)] };
                case 'tuning:presetSave':
                    await wait(300);
                    demoMine.push({ id: ++demoNext, name: 'Preset ' + demoNext });
                    return { ok: true, id: demoNext, name: 'Preset ' + demoNext };
                case 'tuning:presetDelete':
                    await wait(200);
                    demoMine = demoMine.filter((p) => p.id !== body.id);
                    return { ok: true };
                case 'tuning:loadLast':
                    await wait(200);
                    return { ok: true, changes: [{ id: 'modFrontBumper', value: 2 }, { id: 'windowTint', value: 2 }], swaps: [] };
                case 'tuning:workorderLoad':
                    await wait(250);
                    return { ok: true, owner: 'Mads Hansen', changes: [{ id: 'color1', value: 27 }, { id: 'modSpoilers', value: 3 }, { id: 'neonFront', value: true }, { id: 'neonBack', value: true }], swaps: [demoSwap('engine', 3), demoSwap('turbo', 1)] };
                case 'tuning:workorderSend':
                    await wait(350);
                    setTimeout(() => window.postMessage({ action: 'closeTuning', data: {} }, '*'), 250);
                    return { ok: true };
                case 'tuning:install':
                case 'tuning:swap':
                    await wait(150);
                    return { ok: true };
                default:
                    return { ok: true };
            }
        };

        const SPOILERS = ['Carbon', 'Gade', 'Sport', 'Race', 'GT-vinge', 'Andehale', 'Lav profil', 'Aggressiv', 'Slank', 'Bred', 'Tuner'];
        const modNames = (prefix, n, names) => Array.from({ length: n }, (_, i) => (names ? names[i % names.length] + ' ' : '') + prefix + ' ' + (i + 1));
        const mod = (id, label, price, current, count, prefix, names) => ({
            type: 'mod', id, label, price, current,
            options: [{ value: -1, label: 'Standard' }].concat(modNames(prefix || label, count, names).map((l, i) => ({ value: i, label: l }))),
        });
        const list = (id, label, price, current, labels) => ({
            type: 'list', id, label, price, current,
            options: labels.map((l, i) => ({ value: i, label: l })),
        });
        const sub = (id, label, items, icon) => ({ type: 'sub', id, label, items, icon });
        const perf = (id) => {
            const [label, counts, prices] = PERF_DEMO[id];
            return {
                type: 'performance', id, label, current: PERF_CURRENT[id],
                options: [{ level: 0, label: 'Standard' }].concat(counts.map((stock, i) => {
                    const o = { level: i + 1, label: id === 'turbo' ? 'Turbo' : 'Niveau ' + (i + 1), price: prices[i] };
                    if (demoMode === 'mechanic') { o.item = id + (id === 'turbo' ? '' : '_lvl' + (i + 1)); o.stock = stock; }
                    return o;
                })),
            };
        };

        function demoColourGroups() {
            if (Array.isArray(window.__demoColours) && window.__demoColours.length) return window.__demoColours;
            const mk = (lst) => lst.map(([label, hex], i) => ({ index: i, label, hex }));
            return [
                { id: 'metallic', label: 'Metallisk', colours: mk([['Sort', '#202322'], ['Grafit', '#232524'], ['Sølv', '#626C75'], ['Hvid', '#E8E8E4'], ['Rød', '#B01E23'], ['Orange', '#E0701B'], ['Gul', '#E7C429'], ['Grøn', '#1D6B3A'], ['Blå', '#2F4C8F'], ['Lilla', '#5B2A78']]) },
                { id: 'matte', label: 'Mat', colours: mk([['Mat sort', '#161819'], ['Mat grå', '#3C4044'], ['Mat hvid', '#D9D7CF']]) },
            ];
        }

        function demoPayload(opts) {
            const groupsC = demoColourGroups();
            const colour = (id, label, price, current) => ({ type: 'colour', id, label, price, current, groups: groupsC });
            const firstIdx = (gid, n) => { const g = groupsC.find((x) => x.id === gid); return g ? g.colours[Math.min(n, g.colours.length - 1)].index : 0; };
            const rims = [['0', 'Sport', 50], ['1', 'Muscle', 36], ['2', 'Lowrider', 30], ['3', 'SUV', 38], ['4', 'Terræn', 32], ['5', 'Tuner', 48], ['7', 'Luksus', 40], ['8', "Benny's Original", 36], ['9', "Benny's Bespoke", 36], ['11', 'Gade', 30], ['12', 'Bane', 30]]
                .map(([t, label, n]) => mod('modFrontWheels:' + t, label, 2000, t === '0' ? 4 : -1, n, 'Fælg'));
            const plateIndex = clamp(int(opts.plateIndex), 0, 12);
            const plateLabels = ['Blå på hvid 1', 'Gul på sort', 'Gul på blå', 'Blå på hvid 2', 'Blå på hvid 3', 'North Yankton', 'eCola', 'Las Venturas', 'Liberty City', 'LS Car Meet', 'LS Panic', 'LS Pounders', 'Sprunk'];
            const groups = [
                { id: 'performance', label: 'Ydelse', icon: 'gauge-high', items: Object.keys(PERF_DEMO).map(perf) },
                { id: 'bodywork', label: 'Karosseri', icon: 'car-side', items: [
                    sub('sub:bodywork:Front', 'Front', [mod('modFrontBumper', 'Frontkofanger', 1500, -1, 6, 'Kofanger'), mod('modGrille', 'Grill', 800, 0, 7, 'Grill'), mod('modHood', 'Motorhjelm', 1500, -1, 8, 'Motorhjelm')], 'car'),
                    sub('sub:bodywork:Bagende', 'Bagende', [mod('modSpoilers', 'Spoiler', 1500, 2, 9, 'Spoiler', SPOILERS), mod('modRearBumper', 'Bagkofanger', 1500, 1, 5, 'Kofanger'), mod('modExhaust', 'Udstødning', 1000, -1, 5, 'Udstødning')], 'car-rear'),
                    sub('sub:bodywork:Sider', 'Sider', [mod('modSideSkirt', 'Sideskørter', 1200, -1, 4, 'Skørter'), mod('modFrame', 'Rullebur', 2000, -1, 3, 'Rullebur'), mod('modFender', 'Venstre skærm', 1000, -1, 3, 'Skærm'), mod('modRightFender', 'Højre skærm', 1000, -1, 3, 'Skærm')], 'car-side'),
                    sub('sub:bodywork:Tag', 'Tag', [mod('modRoof', 'Tag', 1200, -1, 3, 'Tag'), mod('modAerials', 'Antenner', 500, -1, 3, 'Antenne')], 'car-on'),
                ] },
                { id: 'wheels', label: 'Hjul', icon: 'compact-disc', items: [
                    sub('sub:wheels:Fælge', 'Fælge', rims, 'compact-disc'),
                    { type: 'toggle', id: 'customTires', label: 'Specialdæk', price: 800, current: false },
                    sub('sub:wheels:Dækrøg', 'Dækrøg', [
                        { type: 'toggle', id: 'tyreSmoke', label: 'Dækrøg', price: 1500, current: false },
                        { type: 'rgb', id: 'tyreSmokeColor', label: 'Røgfarve', price: 1500, priceId: 'tyreSmoke', current: { r: 255, g: 255, b: 255 } },
                    ], 'smog'),
                    colour('wheelColor', 'Fælgfarve', 1000, firstIdx('metallic', 2)),
                ] },
                { id: 'respray', label: 'Lakering', icon: 'spray-can', items: [
                    colour('color1', 'Primærfarve', 2500, firstIdx('metallic', 4)),
                    colour('color2', 'Sekundærfarve', 2000, firstIdx('metallic', 0)),
                    colour('pearlescent', 'Perlemor', 1500, firstIdx('metallic', 3)),
                ] },
                { id: 'interior', label: 'Kabine', icon: 'couch', items: [
                    sub('sub:interior:Instrumentbræt', 'Instrumentbræt', [mod('modDashboard', 'Instrumentbræt', 1200, -1, 5, 'Instrumentbræt'), mod('modDial', 'Måleur', 800, -1, 6, 'Måleur'), mod('modSteeringWheel', 'Rat', 1000, -1, 8, 'Rat')], 'gauge'),
                    sub('sub:interior:Sæder', 'Sæder', [mod('modSeats', 'Sæder', 1500, -1, 6, 'Sæde')], 'couch'),
                    colour('interiorColor', 'Kabinefarve', 1000, firstIdx('matte', 1)),
                ] },
                { id: 'engine', label: 'Motorrum', icon: 'oil-can', items: [
                    mod('modEngineBlock', 'Motorblok', 1500, -1, 4, 'Motorblok'), mod('modAirFilter', 'Luftfilter', 800, -1, 4, 'Luftfilter'),
                    mod('modStruts', 'Fjederbensstivere', 1000, -1, 4, 'Stivere'),
                ] },
                { id: 'lights', label: 'Lys', icon: 'lightbulb', items: [
                    {
                        type: 'list', id: 'xenon', label: 'Xenon', price: 1500, current: -1,
                        options: [{ value: -1, label: 'Fra' }, { value: 255, label: 'Standard', hex: '#F2F4FF' }, { value: 1, label: 'Blå', hex: '#0215FF' }, { value: 3, label: 'Mintgrøn', hex: '#00FF8C' }, { value: 5, label: 'Gul', hex: '#FFFF00' }, { value: 8, label: 'Rød', hex: '#FF0101' }],
                    },
                    sub('sub:lights:Neon', 'Neon', [
                        { type: 'toggle', id: 'neonLeft', label: 'Venstre', price: 3000, priceId: 'neon', current: false },
                        { type: 'toggle', id: 'neonRight', label: 'Højre', price: 3000, priceId: 'neon', current: false },
                        { type: 'toggle', id: 'neonFront', label: 'Foran', price: 3000, priceId: 'neon', current: false },
                        { type: 'toggle', id: 'neonBack', label: 'Bagved', price: 3000, priceId: 'neon', current: false },
                        { type: 'rgb', id: 'neonColor', label: 'Neonfarve', price: 3000, priceId: 'neon', current: { r: 255, g: 0, b: 80 } },
                    ], 'bolt'),
                ] },
                { id: 'plates', label: 'Nummerplade', icon: 'hashtag', items: [
                    list('plateIndex', 'Pladetype', 300, plateIndex, plateLabels),
                    mod('modPlateHolder', 'Pladeholder', 300, -1, 4, 'Holder'), mod('modVanityPlate', 'Forfængelighedsplade', 300, -1, 4, 'Plade'),
                ] },
                { id: 'other', label: 'Andet', icon: 'sliders', items: [
                    list('windowTint', 'Rudetoning', 800, 0, ['Ingen', 'Standard', 'Lys røg', 'Mørk røg', 'Limousine', 'Helt sort', 'Grøn']),
                    mod('modLivery', 'Livery', 2500, -1, 6, 'Livery'),
                    mod('modHorns', 'Horn', 500, -1, 40, 'Horn'),
                ] },
            ];
            const PLATE_TEXT = ['#0F2352', '#CF9E00', '#BD7121', '#0F2352', '#0F2352', '#000000', '#FEFEFE', '#011866', '#0D147E', '#000000', '#FED40E', '#F4BB2E', '#FEFEFE'];
            const payload = {
                mode: demoMode,
                manualSwap: false,
                vehicle: {
                    label: 'Karin Sultan RS', plate: opts.plate || '46EEK572', owned: opts.owned !== false, plateIndex,
                    plateStyle: { text: PLATE_TEXT[plateIndex], outline: '#FFFFFF', image: opts.plateImage ? 'https://nui-img/vehshare/plate01' : undefined },
                },
                groups,
            };
            if (opts.lastCart) payload.lastCart = { count: 2, at: Date.now() };
            if (opts.workOrder && demoMode === 'mechanic') payload.workOrder = { owner: 'Mads Hansen', created_at: '', expires_at: '', count: 6 };
            return payload;
        }

        window.__demo = (opts) => {
            opts = opts || {};
            demoMode = opts.mode === 'design' ? 'design' : 'mechanic';
            App.setLocale(DEMO_LOCALE);
            window.postMessage({ action: 'openTuning', data: demoPayload(opts) }, '*');
            return opts;
        };
        window.__demoClose = () => window.postMessage({ action: 'closeTuning', data: {} }, '*');
        window.__demoSuspend = (on) => window.postMessage({ action: 'tuning:suspend', data: { on: !!on } }, '*');
    }
})();
