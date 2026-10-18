/* Tuning screen (NUI side of contract section 6). Builds all DOM inside #tuning-root.
 *
 * Lua -> NUI:  openTuning { vehicle, groups }, closeTuning {}
 * NUI -> Lua:  tuning:preview, tuning:camera, tuning:orbit, tuning:zoom, tuning:install,
 *              tuning:swap, tuning:order, tuning:close
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
        ui_level: 'Niveau %s',
        ui_installed: 'Monteret',
        ui_install: 'Monter',
        ui_cart: 'Kurv',
        ui_total: 'I alt',
        ui_close: 'Luk',
        ui_back: 'Tilbage',
        ui_cancel: 'Annuller',
        ui_empty_cart: 'Intet valgt endnu.',
        ui_not_owned: 'Køretøjet ejes ikke: ændringerne gemmes ikke, og dele kan ikke skiftes.',
        ui_order: 'Bestil',
        ui_ordered: 'Bestilt',
        ui_eta: 'Leveres om ca. %s min',
        ui_stock_count: '%s på lager',
        ui_out_of_stock: 'Ikke på lager',
        ui_order_failed: 'Bestillingen mislykkedes.',
        ui_swap_confirm: 'Skift %s til %s?',
        ui_swap_discard: 'Ændringer i kurven, der ikke er monteret, kasseres.',
        ui_swap_do: 'Skift del',
        ui_on: 'Til',
        ui_off: 'Fra',
        ui_search: 'Søg...',
        ui_no_match: 'Ingen resultater.',
        ui_empty_list: 'Ingen muligheder.',
        ui_pick_colour: 'Vælg farve',
        ui_undo: 'Fortryd',
        ui_groups: 'Kategorier',
        ui_drag_hint: 'Træk for at dreje',
        ui_zoom_hint: 'Rul for at zoome',
        ui_cam_default: 'Overblik',
        ui_cam_front: 'Front',
        ui_cam_rear: 'Bagende',
        ui_cam_wheel: 'Hjul',
        ui_cam_engine: 'Motor',
        ui_cam_side: 'Side',
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
    const clone = (o) => JSON.parse(JSON.stringify(o));
    const money = (n) => '$' + String(Math.round(num(n))).replace(/\B(?=(\d{3})+(?!\d))/g, '.');
    const qa = (parent, sel) => Array.from(parent.querySelectorAll(sel));

    const TYPES = { sub: 1, mod: 1, colour: 1, toggle: 1, rgb: 1, list: 1, performance: 1 };
    const MAX_DEPTH = 6;

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

    const safeHex = (h) => (/^#[0-9a-f]{6}$/i.test(String(h)) ? String(h) : '#808080');

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
        // Make sure the shift is visible even on dull colours
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

    // Network wrapper: in demo mode (no FiveM) a few calls are simulated so the UI is testable
    async function post(name, body) {
        if (App.isGame) return App.post(name, body);
        if (Array.isArray(window.__trace)) window.__trace.push({ name, body, t: performance.now() });
        if (name === 'tuning:order') {
            await new Promise((r) => setTimeout(r, 450));
            if (window.__demoFail) return { ok: false, error: 'Firmakontoen har ikke råd.' };
            return { ok: true, eta: 300 };
        }
        return { ok: true };
    }

    // ---------------------------------------------------------------------------------------------
    // Payload normalisation
    // ---------------------------------------------------------------------------------------------

    function normOptions(list) {
        return (Array.isArray(list) ? list : []).map((o) => ({
            value: int(o && o.value, -1),
            label: String((o && o.label) ?? ''),
        }));
    }

    function normColourGroups(list) {
        return (Array.isArray(list) ? list : []).map((g) => ({
            id: String((g && g.id) ?? ''),
            label: String((g && g.label) ?? ''),
            colours: (Array.isArray(g && g.colours) ? g.colours : []).map((c) => ({
                index: int(c && c.index),
                label: String((c && c.label) ?? ''),
                hex: safeHex(c && c.hex),
            })),
        })).filter((g) => g.colours.length > 0);
    }

    function normNode(n, depth) {
        if (!n || typeof n !== 'object' || !TYPES[n.type] || depth > MAX_DEPTH) return null;
        const node = { type: n.type, id: String(n.id ?? ''), label: String(n.label ?? n.id ?? ''), price: Math.max(0, num(n.price)) };
        if (!node.id) return null;
        // Nodes that share a price (tyre smoke on/off + colour, neon layout + colour) are charged once
        node.priceId = String(n.priceId ?? n.id);

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
                    label: String((o && o.label) ?? ''),
                    item: o && o.item ? String(o.item) : null,
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

    // ---------------------------------------------------------------------------------------------
    // State
    // ---------------------------------------------------------------------------------------------

    const S = {
        open: false,
        data: null,
        groups: [],
        gi: 0,
        nav: [],                 // sub / leaf nodes below the active group
        cur: {},                 // id -> current (previewed) value
        orig: {},                // id -> value on the car when the screen opened
        touched: {},             // id -> sequence number of the last change
        seq: 0,
        nodes: new Map(),        // id -> value node
        bases: new Map(),        // base id -> value nodes sharing it (wheel types)
        colourNames: new Map(),  // colour index -> label
        colourTab: {},           // node id -> colour group id
        search: {},              // node id -> filter text
        memory: {},              // path key -> focused row index
        perfOpen: '',
        swap: null,              // { category, label, level, levelLabel }
        ordered: {},             // item -> eta seconds
        orderBusy: {},
        orderErr: {},
        cartOpen: false,
        busy: false,
        cam: 'default',
    };

    let ui = null;               // element references of the current session
    let leaveTimer = 0;

    function indexNodes(list, gi, parent) {
        list.forEach((n) => {
            if (n.type === 'sub') { indexNodes(n.items, gi, n); return; }
            if (n.type === 'performance') return;
            n.gi = gi;
            // Rims live in one sub per wheel type: the cart line must say which type
            n.cartLabel = (parent && n.id.indexOf(':') !== -1) ? parent.label + ' ' + n.label : n.label;
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
            else if (x.type !== 'performance' && isChanged(x)) n += 1;
        });
        return n;
    }

    function optionLabel(node, value) {
        const o = node.options.find((x) => x.value === value);
        return o ? o.label : '';
    }

    function colourName(index) {
        if (S.colourNames.has(index)) return S.colourNames.get(index);
        return index < 0 || index === 255 ? T('ui_stock') : '#' + index;
    }

    function valueText(node, value) {
        switch (node.type) {
            case 'mod':
            case 'list': return optionLabel(node, value);
            case 'colour': return colourName(value);
            case 'toggle': return value ? T('ui_on') : T('ui_off');
            case 'rgb': return rgbToHex(value).toUpperCase();
            default: return '';
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Live preview (coalesced per base id, hover is debounced, restore goes back to the cart state)
    // ---------------------------------------------------------------------------------------------

    const pv = { timer: {}, pending: {}, last: {}, hover: 0 };

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

    function setValue(node, value) {
        const id = node.id;
        // One change per base: rims of different wheel types replace each other
        (S.bases.get(baseOf(id)) || []).forEach((s) => {
            if (s.id !== id) { S.cur[s.id] = clone(S.orig[s.id]); delete S.touched[s.id]; }
        });
        S.cur[id] = clone(value);
        if (isChanged(node)) S.touched[id] = ++S.seq; else delete S.touched[id];
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
        renderFoot();
        paintLeaf();
        paintListRows();
    }

    function cartEntries() {
        const byBase = {};
        S.nodes.forEach((n) => {
            if (!isChanged(n)) return;
            const b = baseOf(n.id);
            if (!byBase[b] || S.touched[n.id] > S.touched[byBase[b].id]) byBase[b] = n;
        });
        const list = Object.keys(byBase).map((b) => {
            const n = byBase[b];
            return { node: n, id: n.id, value: clone(S.cur[n.id]), price: n.price, label: n.cartLabel + ': ' + valueText(n, S.cur[n.id]), seq: S.touched[n.id] || 0 };
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

    // ---------------------------------------------------------------------------------------------
    // Navigation
    // ---------------------------------------------------------------------------------------------

    const activeGroup = () => S.groups[S.gi];
    const lastNav = () => S.nav[S.nav.length - 1] || null;
    const pathKey = () => S.gi + '/' + S.nav.map((n) => n.id).join('/');

    function currentItems() {
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

    function go(node) {
        rememberFocus();
        S.nav.push(node);
        S.swap = null;
        renderAll(1);
    }

    function goBack() {
        if (S.swap) { S.swap = null; refreshPerfRows(); renderFoot(); return true; }
        if (!S.nav.length) return false;
        const hadLeaf = lastNav();
        if (hadLeaf && !(hadLeaf.type === 'sub')) restorePreview(hadLeaf);
        S.nav.pop();
        renderAll(-1);
        return true;
    }

    function selectGroup(i, focusView) {
        if (i < 0 || i >= S.groups.length) return;
        const leaf = lastNav();
        if (leaf && leaf.type !== 'sub') restorePreview(leaf);
        S.gi = i;
        S.nav = [];
        S.swap = null;
        renderAll(1, !focusView);
    }

    function stepGroup(d) {
        selectGroup((S.gi + d + S.groups.length) % S.groups.length, true);
    }

    // ---------------------------------------------------------------------------------------------
    // Rendering: skeleton
    // ---------------------------------------------------------------------------------------------

    const CAMERAS = [
        ['default', 'cube'], ['front', 'car'], ['rear', 'car-rear'],
        ['wheel', 'circle-dot'], ['engine', 'gears'], ['side', 'car-side'],
    ];

    function buildSkeleton() {
        const v = S.data.vehicle;
        const title = el('h1', { class: 'tn-title', text: v.label });
        const plate = el('span', { class: 'tn-plate', text: v.plate });
        plate.hidden = !v.plate;
        const closeBtn = el('button', { class: 'tn-iconbtn', attrs: { type: 'button', 'aria-label': T('ui_close'), title: T('ui_close') }, on: { click: closeScreen } }, [icon('fa-solid fa-xmark')]);
        const head = el('header', { class: 'tn-head' }, [title, plate, closeBtn]);

        const notice = el('div', { class: 'tn-notice', attrs: { role: 'status' } }, [icon('fa-solid fa-triangle-exclamation'), el('span', { text: T('ui_not_owned') })]);
        notice.hidden = v.owned;

        const rail = el('nav', { class: 'tn-rail', attrs: { 'aria-label': T('ui_groups') } });
        S.groups.forEach((g, i) => {
            const b = el('button', {
                class: 'tn-rail-btn',
                attrs: { type: 'button', 'aria-label': g.label, title: g.label, 'data-group': String(i) },
                on: { click: () => { if (i !== S.gi || S.nav.length) selectGroup(i); } },
            }, [icon(iconClass(g.icon, 'circle'))]);
            rail.append(b);
        });

        const crumbs = el('div', { class: 'tn-crumbs' });
        const view = el('div', { class: 'tn-view', attrs: { tabindex: '-1' } });
        const main = el('div', { class: 'tn-main' }, [crumbs, view]);
        const body = el('div', { class: 'tn-body' }, [rail, main]);
        const foot = el('footer', { class: 'tn-foot' });
        const panel = el('aside', { class: 'tn-panel', attrs: { role: 'dialog', 'aria-label': v.label } }, [head, notice, body, foot]);

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
        ui = { panel, rail, crumbs, view, foot, dockInner };
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
        qa(ui.rail, '.tn-rail-btn').forEach((b, i) => {
            b.classList.toggle('is-active', i === S.gi);
            b.classList.toggle('is-dirty', countChanged(S.groups[i].items) > 0);
            b.setAttribute('aria-current', i === S.gi ? 'true' : 'false');
        });
    }

    function renderCrumbs() {
        const g = activeGroup();
        const trail = el('div', { class: 'tn-crumb-trail' });
        const labels = [g.label].concat(S.nav.map((n) => n.label));
        labels.forEach((text, i) => {
            const last = i === labels.length - 1;
            if (i > 0) trail.append(icon('fa-solid fa-chevron-right'));
            trail.append(el('span', { class: last ? 'is-last' + (labels.length === 1 ? ' is-first-only' : '') : '', text }));
        });
        const kids = [];
        if (S.nav.length) {
            kids.push(el('button', { class: 'tn-iconbtn', attrs: { type: 'button', 'aria-label': T('ui_back'), title: T('ui_back') }, on: { click: goBack } }, [icon('fa-solid fa-chevron-left')]));
        }
        kids.push(trail);
        const leaf = lastNav();
        if (leaf && leaf.type !== 'sub' && leaf.price > 0) kids.push(el('span', { class: 'tn-crumb-price', text: money(leaf.price) }));
        ui.crumbs.replaceChildren(...kids);
    }

    // dir: 1 forward, -1 back. Rebuilds crumbs, view and footer; keeps the rail.
    function renderAll(dir, fromRail) {
        paintRail();
        renderCrumbs();
        renderView(dir);
        renderFoot();
        focusInitial(fromRail);
    }

    function renderView(dir) {
        const items = currentItems();
        let content;
        if (items) content = buildList(items);
        else content = buildLeaf(lastNav());

        ui.view.replaceChildren(...content);
        ui.view.scrollTop = 0;
        ui.view.classList.toggle('is-back', dir < 0);
        ui.view.style.animation = 'none';
        void ui.view.offsetWidth;
        ui.view.style.animation = '';
        paintListRows();
        paintLeaf();
    }

    function focusInitial(fromRail) {
        if (fromRail) return;
        const rows = qa(ui.view, '[data-nav]').filter((n) => !n.disabled && n.tagName !== 'INPUT');
        if (!rows.length) return;
        const leaf = lastNav();
        let target = null;
        if (leaf && leaf.type !== 'sub') {
            target = ui.view.querySelector('[aria-checked="true"][data-nav]') || rows[0];
        } else {
            const mem = S.memory[pathKey()];
            const list = qa(ui.view, '[data-nav="row"]');
            target = (mem !== undefined && list[mem]) ? list[mem] : list[0] || rows[0];
        }
        if (target) target.focus({ preventScroll: true });
    }

    // ---------------------------------------------------------------------------------------------
    // Rendering: list of nodes
    // ---------------------------------------------------------------------------------------------

    function buildList(items) {
        if (!items.length) return [el('p', { class: 'tn-empty', text: T('ui_empty_list') })];
        const list = el('div', { class: 'tn-list', attrs: { role: 'list' } });
        items.forEach((n) => list.append(n.type === 'performance' ? buildPerfCard(n) : buildRow(n)));
        return [list];
    }

    function bindFocus(btn) {
        btn.addEventListener('mousemove', () => {
            if (!btn.disabled && document.activeElement !== btn) btn.focus({ preventScroll: true });
        });
    }

    function buildRow(node) {
        const row = el('button', { class: 'tn-row', attrs: { type: 'button', 'data-nav': 'row', 'data-id': node.id } });
        row.append(el('span', { class: 'tn-row-label', text: node.label }));
        const val = el('span', { class: 'tn-row-value' });

        if (node.type === 'toggle') {
            row.setAttribute('role', 'switch');
            row.append(el('span', { class: 'tn-switch' }));
            row.addEventListener('click', () => setValue(node, !S.cur[node.id]));
        } else {
            row.dataset.open = '1';
            row.append(val);
            row.append(icon('fa-solid fa-chevron-right tn-row-arrow'));
            row.addEventListener('click', () => go(node));
        }
        bindFocus(row);
        row.__node = node;
        row.__val = val;
        return row;
    }

    // Update value text, dirty markers and counters of the rows in the visible list
    function paintListRows() {
        if (!ui) return;
        qa(ui.view, '.tn-row').forEach((row) => {
            const n = row.__node;
            if (!n) return;
            if (n.type === 'toggle') {
                row.setAttribute('aria-checked', S.cur[n.id] ? 'true' : 'false');
                row.classList.toggle('is-dirty', isChanged(n));
                return;
            }
            const val = row.__val;
            const kids = [];
            if (n.type === 'sub') {
                const c = countChanged(n.items);
                if (c > 0) kids.push(el('span', { class: 'tn-count', text: c }));
                row.classList.toggle('is-dirty', c > 0);
            } else {
                const dirty = isChanged(n);
                row.classList.toggle('is-dirty', dirty);
                if (dirty) kids.push(el('span', { class: 'tn-dot' }));
                if (n.type === 'colour') {
                    const hexOf = colourHex(n, S.cur[n.id]);
                    if (hexOf) kids.push(el('span', { class: 'tn-chip', attrs: { style: 'background:' + hexOf } }));
                } else if (n.type === 'rgb') {
                    kids.push(el('span', { class: 'tn-chip', attrs: { style: 'background:' + rgbToHex(S.cur[n.id]) } }));
                }
                if (n.type !== 'rgb') kids.push(el('span', { text: valueText(n, S.cur[n.id]) }));
            }
            val.replaceChildren(...kids);
        });
    }

    function colourHex(node, index) {
        for (const g of node.groups) {
            const c = g.colours.find((x) => x.index === index);
            if (c) return c.hex;
        }
        return null;
    }

    // ---------------------------------------------------------------------------------------------
    // Rendering: performance cards
    // ---------------------------------------------------------------------------------------------

    function buildPerfCard(node) {
        const open = S.perfOpen === node.id;
        const cur = node.options.find((o) => o.level === node.current);
        const head = el('button', { class: 'tn-card-head', attrs: { type: 'button', 'data-nav': 'row', 'aria-expanded': open ? 'true' : 'false', 'data-open': '1' } }, [
            el('span', { class: 'tn-row-label', text: node.label }),
            el('span', { class: 'tn-badge is-current', text: cur ? cur.label : T('ui_stock') }),
            icon('fa-solid fa-chevron-right tn-row-arrow'),
        ]);
        bindFocus(head);
        const card = el('div', { class: 'tn-card' + (open ? ' is-open' : ''), attrs: { role: 'listitem' } }, [head]);
        const levels = el('div', { class: 'tn-levels' });

        head.addEventListener('click', () => {
            S.perfOpen = S.perfOpen === node.id ? '' : node.id;
            if (S.swap && S.swap.category !== S.perfOpen) S.swap = null;
            qa(ui.view, '.tn-card').forEach((c) => {
                const isThis = c === card;
                c.classList.toggle('is-open', isThis && S.perfOpen === node.id);
                c.querySelector('.tn-card-head').setAttribute('aria-expanded', (isThis && S.perfOpen === node.id) ? 'true' : 'false');
            });
            renderFoot();
        });

        node.options.forEach((o) => levels.append(buildLevel(node, o)));
        card.append(levels);
        return card;
    }

    function buildLevel(node, o) {
        const isCurrent = o.level === node.current;
        const owned = S.data.vehicle.owned;
        const canPick = owned && !isCurrent && (o.level === 0 || o.stock > 0);
        const selected = S.swap && S.swap.category === node.id && S.swap.level === o.level;

        const pick = el('button', {
            class: 'tn-level-pick',
            attrs: { type: 'button', 'data-nav': 'row', role: 'radio', 'aria-checked': selected ? 'true' : 'false' },
        }, [
            el('span', { class: 'tn-radio' }, [icon('fa-solid fa-check')]),
            el('span', { class: 'tn-level-name', text: o.label }),
        ]);
        pick.disabled = !canPick;
        if (canPick) {
            pick.addEventListener('click', () => {
                S.swap = { category: node.id, label: node.label, level: o.level, levelLabel: o.label };
                refreshPerfRows();
                renderFoot();
            });
            bindFocus(pick);
        }

        const row = el('div', { class: 'tn-level' + (isCurrent ? ' is-current' : '') + (selected ? ' is-selected' : '') + (canPick ? '' : ' is-unavailable'), attrs: { 'data-level': String(o.level) } }, [pick]);

        // Right side: state / stock / order
        if (isCurrent) {
            row.append(el('span', { class: 'tn-badge is-current', text: T('ui_installed') }));
        } else if (o.level > 0 && o.item) {
            const err = S.orderErr[o.item];
            if (S.ordered[o.item] !== undefined) {
                const min = Math.max(1, Math.ceil(S.ordered[o.item] / 60));
                row.append(el('span', { class: 'tn-badge is-info' }, [icon('fa-solid fa-truck-fast'), el('span', { text: T('ui_ordered') + ' · ' + T('ui_eta', min) })]));
            } else if (o.stock > 0) {
                row.append(el('span', { class: 'tn-badge is-ok', text: T('ui_stock_count', o.stock) }));
            } else {
                if (err) row.append(el('span', { class: 'tn-badge is-error', text: err }));
                else row.append(el('span', { class: 'tn-badge is-out', text: T('ui_out_of_stock') }));
                const busy = !!S.orderBusy[o.item];
                const btn = el('button', {
                    class: 'tn-btn is-secondary is-small' + (busy ? ' is-busy' : ''),
                    attrs: { type: 'button', 'data-nav': 'row', 'data-order': o.item },
                    on: { click: () => orderItem(node, o, row) },
                }, [icon(busy ? 'fa-solid fa-circle-notch' : 'fa-solid fa-truck-fast'), el('span', { text: T('ui_order') }), o.price > 0 ? el('span', { class: 'tn-price', text: money(o.price) }) : null]);
                btn.disabled = busy;
                bindFocus(btn);
                row.append(btn);
            }
        }
        return row;
    }

    // Re-render only the performance cards (keeps open state, scroll and focus position)
    function refreshPerfRows() {
        if (!ui) return;
        const items = currentItems();
        if (!items) return;
        const act = document.activeElement;
        const focusKey = act && ui.view.contains(act) ? (act.dataset.order ? 'order:' + act.dataset.order : null) : null;
        const cards = qa(ui.view, '.tn-card');
        let ci = 0;
        const perfNodes = [];
        (function collect(list) { list.forEach((n) => { if (n.type === 'performance') perfNodes.push(n); }); })(items);
        perfNodes.forEach((n) => {
            const old = cards[ci++];
            if (!old) return;
            const fresh = buildPerfCard(n);
            old.replaceWith(fresh);
        });
        if (focusKey) {
            const again = ui.view.querySelector('[data-order="' + focusKey.slice(6) + '"]');
            if (again && !again.disabled) again.focus({ preventScroll: true });
        }
    }

    async function orderItem(node, o, row) {
        if (!o.item || S.orderBusy[o.item]) return;
        S.orderBusy[o.item] = true;
        delete S.orderErr[o.item];
        refreshPerfRows();
        const res = await post('tuning:order', { item: o.item });
        S.orderBusy[o.item] = false;
        if (!S.open) return;
        if (res && res.ok) {
            S.ordered[o.item] = Math.max(0, num(res.eta));
        } else {
            S.orderErr[o.item] = (res && typeof res.error === 'string' && res.error) ? res.error : T('ui_order_failed');
            setTimeout(() => { delete S.orderErr[o.item]; if (S.open) refreshPerfRows(); }, 4500);
        }
        refreshPerfRows();
        const fresh = ui && ui.view.querySelector('.tn-card.is-open [data-level="' + o.level + '"]');
        if (fresh && !(res && res.ok)) shake(fresh);
    }

    // ---------------------------------------------------------------------------------------------
    // Rendering: leaves (options, colours, rgb)
    // ---------------------------------------------------------------------------------------------

    function buildLeaf(node) {
        if (!node) return [];
        if (node.type === 'colour') return buildColourLeaf(node);
        if (node.type === 'rgb') return buildRgbLeaf(node);
        return buildOptionsLeaf(node);
    }

    function buildOptionsLeaf(node) {
        const out = [];
        const box = el('div', { class: 'tn-opts', attrs: { role: 'radiogroup', 'aria-label': node.label } });
        const rows = node.options.map((o) => {
            const tag = el('span', { class: 'tn-opt-tag', text: T('ui_installed') });
            tag.hidden = true;
            const r = el('button', {
                class: 'tn-opt',
                attrs: { type: 'button', role: 'radio', 'data-nav': 'opt', 'data-value': String(o.value), 'aria-checked': 'false' },
            }, [el('span', { class: 'tn-radio' }, [icon('fa-solid fa-check')]), el('span', { class: 'tn-opt-name', text: o.label }), tag]);
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
        box.__rows = rows;

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

        const leave = () => {
            const act = document.activeElement;
            if (act && box.contains(act)) act.blur();
            restorePreview(node);
        };
        box.addEventListener('mouseleave', leave);
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
        const nameTag = el('span', { class: 'tn-opt-tag', text: T('ui_installed') });
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

        const leave = () => {
            const act = document.activeElement;
            if (act && grid.contains(act)) act.blur();
            showName(S.cur[node.id]);
            restorePreview(node);
        };
        grid.addEventListener('mouseleave', leave);
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
        const sliderRow = (ch, from, to) => {
            const input = el('input', { attrs: { type: 'range', min: '0', max: '255', step: '1', 'aria-label': ch.toUpperCase(), 'data-nav': 'misc' } });
            const out = el('output', { text: '0' });
            input.style.setProperty('--track', 'linear-gradient(90deg,' + from + ',' + to + ')');
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

        const apply = (rgb) => {
            if (!rgb) return;
            setValue(node, { r: rgb.r, g: rgb.g, b: rgb.b });
        };
        node.__paint = () => {
            const c = S.cur[node.id];
            const hex = rgbToHex(c);
            if (picker.value !== hex) picker.value = hex;
            if (document.activeElement !== hexIn) hexIn.value = hex.toUpperCase();
            ['r', 'g', 'b'].forEach((ch) => {
                sliders[ch].input.value = String(c[ch]);
                sliders[ch].out.textContent = String(c[ch]);
            });
            // Slider tracks show what the other two channels currently are
            qa(presets, '.tn-swatch').forEach((b) => b.setAttribute('aria-checked', b.dataset.hex === hex ? 'true' : 'false'));
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

        wrap.append(
            picker,
            el('div', { class: 'tn-rgb-hex' }, [hexIn]),
            sliderRow('r', '#000000', '#ff0000'),
            sliderRow('g', '#000000', '#00ff00'),
            sliderRow('b', '#000000', '#0000ff'),
            presets,
        );
        return [wrap];
    }

    // Selected / installed markers in the open leaf
    function paintLeaf() {
        const node = lastNav();
        if (!ui || !node || node.type === 'sub') return;
        const cur = S.cur[node.id];
        if (node.type === 'colour') {
            qa(ui.view, '.tn-swatch').forEach((b) => {
                b.setAttribute('aria-checked', int(b.dataset.value) === cur ? 'true' : 'false');
            });
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
    // Footer: cart | swap confirm
    // ---------------------------------------------------------------------------------------------

    function renderFoot() {
        if (!ui) return;
        const act = document.activeElement;
        const refocus = act && ui.foot.contains(act) ? act.dataset.key : null;
        ui.foot.classList.remove('is-open');

        if (S.swap) {
            const cart = cartEntries();
            const text = el('p', { class: 'tn-swap-text', text: T('ui_swap_confirm', S.swap.label, S.swap.levelLabel) });
            const kids = [text];
            if (cart.length) kids.push(el('p', { class: 'tn-swap-note', text: T('ui_swap_discard') }));
            kids.push(el('div', { class: 'tn-swap-actions' }, [
                el('button', { class: 'tn-btn is-secondary', text: T('ui_cancel'), attrs: { type: 'button', 'data-key': 'swap-cancel' }, on: { click: () => { S.swap = null; refreshPerfRows(); renderFoot(); } } }),
                el('button', { class: 'tn-btn is-primary' + (S.busy ? ' is-busy' : ''), attrs: { type: 'button', 'data-key': 'swap-do' }, on: { click: confirmSwap } }, [S.busy ? icon('fa-solid fa-circle-notch') : null, el('span', { text: T('ui_swap_do') })]),
            ]));
            const box = el('div', { class: 'tn-swap', attrs: { role: 'alertdialog' } }, kids);
            ui.foot.replaceChildren(box);
            const primary = box.querySelector('[data-key="swap-do"]');
            if (primary) primary.disabled = S.busy;
            if (refocus === 'swap-do' || !refocus) { /* keep the user's place; focus the confirm button the first time */ }
            const wasThere = refocus && box.querySelector('[data-key="' + refocus + '"]');
            if (wasThere) wasThere.focus({ preventScroll: true });
            else if (primary && !primary.disabled) primary.focus({ preventScroll: true });
            return;
        }

        const cart = cartEntries();
        const total = cart.reduce((s, e) => s + e.price, 0);
        const kids = [];

        if (S.cartOpen) {
            ui.foot.classList.add('is-open');
            const list = el('div', { class: 'tn-cart-list', attrs: { role: 'list' } });
            if (!cart.length) list.append(el('p', { class: 'tn-cart-empty', text: T('ui_empty_cart') }));
            cart.forEach((e) => {
                list.append(el('div', { class: 'tn-cart-line', attrs: { role: 'listitem' } }, [
                    el('span', { class: 'tn-cart-name', text: e.label, attrs: { title: e.label } }),
                    el('span', { class: 'tn-cart-price', text: e.shared ? '' : money(e.price) }),
                    el('button', { class: 'tn-iconbtn', attrs: { type: 'button', 'aria-label': T('ui_undo'), title: T('ui_undo') }, on: { click: () => revert(e.node) } }, [icon('fa-solid fa-xmark')]),
                ]));
            });
            kids.push(list);
        }

        const toggle = el('button', {
            class: 'tn-cart-toggle',
            attrs: { type: 'button', 'aria-expanded': S.cartOpen ? 'true' : 'false', 'data-key': 'cart-toggle' },
            on: { click: () => { S.cartOpen = !S.cartOpen; renderFoot(); } },
        }, [
            icon('fa-solid fa-cart-shopping'),
            el('span', { class: 'tn-cart-title', text: T('ui_cart') }),
            cart.length ? el('span', { class: 'tn-count', text: cart.length }) : null,
            icon('fa-solid fa-chevron-up tn-cart-chev'),
        ]);
        const install = el('button', {
            class: 'tn-btn is-primary' + (S.busy ? ' is-busy' : ''),
            attrs: { type: 'button', 'data-key': 'install' },
            on: { click: installAll },
        }, [S.busy ? icon('fa-solid fa-circle-notch') : icon('fa-solid fa-wrench'), el('span', { text: T('ui_install') })]);
        install.disabled = !cart.length || S.busy;

        kids.push(el('div', { class: 'tn-cart-bar' }, [
            toggle,
            el('span', { class: 'tn-cart-total', text: money(total), attrs: { title: T('ui_total') } }),
            install,
        ]));
        ui.foot.replaceChildren(...kids);
        if (refocus) {
            const again = ui.foot.querySelector('[data-key="' + refocus + '"]');
            if (again && !again.disabled) again.focus({ preventScroll: true });
        }
    }

    function shake(node) {
        if (!node) return;
        node.classList.remove('is-shake');
        void node.offsetWidth;
        node.classList.add('is-shake');
    }

    async function installAll() {
        const cart = cartEntries();
        if (S.busy || !cart.length) return;
        S.busy = true;
        renderFoot();
        resetPreviewState();
        const changes = cart.map((e) => ({ id: e.id, value: e.value, label: e.label, price: e.price }));
        const res = await post('tuning:install', { changes });
        S.busy = false;
        if (res && res.ok) {
            hide();
        } else {
            shake(ui && ui.foot);
            renderFoot();
        }
    }

    async function confirmSwap() {
        const sw = S.swap;
        if (!sw || S.busy || !S.data.vehicle.owned) return;
        S.busy = true;
        renderFoot();
        const res = await post('tuning:swap', { category: sw.category, level: sw.level });
        S.busy = false;
        if (res && res.ok) {
            hide();
        } else {
            shake(ui && ui.foot);
            renderFoot();
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Open / close
    // ---------------------------------------------------------------------------------------------

    function open(raw) {
        raw = raw && typeof raw === 'object' ? raw : {};
        clearTimeout(leaveTimer);
        resetPreviewState();

        const v = raw.vehicle || {};
        const groups = (Array.isArray(raw.groups) ? raw.groups : []).map((g) => ({
            id: String((g && g.id) ?? ''),
            label: String((g && g.label) ?? ''),
            icon: g && g.icon,
            items: (Array.isArray(g && g.items) ? g.items : []).map((n) => normNode(n, 0)).filter(Boolean),
        })).filter((g) => g.items.length > 0);
        if (!groups.length) { post('tuning:close'); return; }

        S.data = { vehicle: { label: String(v.label ?? ''), plate: String(v.plate ?? ''), owned: v.owned === true } };
        S.groups = groups;
        S.gi = 0;
        S.nav = [];
        S.cur = {}; S.orig = {}; S.touched = {}; S.seq = 0;
        S.nodes = new Map(); S.bases = new Map(); S.colourNames = new Map();
        S.colourTab = {}; S.search = {}; S.memory = {};
        S.perfOpen = ''; S.swap = null; S.ordered = {}; S.orderBusy = {}; S.orderErr = {};
        S.cartOpen = false; S.busy = false; S.cam = 'default';
        groups.forEach((g, i) => indexNodes(g.items, i));
        // Open the first performance card so the group does not start as a wall of headers
        const firstPerf = groups[0].items.find((n) => n.type === 'performance');
        if (firstPerf) S.perfOpen = firstPerf.id;

        S.open = true;
        buildSkeleton();
        root.classList.remove('is-leaving');
        root.classList.add('is-open');
        root.hidden = false;
        renderAll(1);
    }

    function hide() {
        if (!S.open) return;
        S.open = false;
        endDrag();
        resetPreviewState();
        root.classList.add('is-leaving');
        root.classList.remove('is-open');
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
        hide();
        post('tuning:close');
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
        if (!S.open || drag || (e.button !== 0 && e.button !== 2)) return;
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
        if (!S.open) return;
        if (e.target.closest('.tn-panel')) return;
        e.preventDefault();
        const notches = clamp(Math.round(Math.abs(e.deltaY) / 100) || 1, 1, 3);
        zoomAcc = clamp(zoomAcc + (e.deltaY > 0 ? notches : -notches), -3, 3);
        const wait = FLUSH_MS - (performance.now() - zoomLast);
        if (wait <= 0) flushZoom();
        else if (!zoomTimer) zoomTimer = setTimeout(flushZoom, wait);
    }, { passive: false });

    // ---------------------------------------------------------------------------------------------
    // Keyboard: arrows, Enter/Space (native button click), Backspace/Escape = back, PageUp/Down = group
    // ---------------------------------------------------------------------------------------------

    function visible(nodes) {
        return nodes.filter((n) => !n.hidden && !n.disabled && n.getClientRects().length > 0);
    }

    function focusNode(n) {
        if (!n) return;
        n.focus({ preventScroll: true });
        n.scrollIntoView({ block: 'nearest' });
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
            const i = sw.indexOf(act);
            const j = i + dir * cols;
            if (j < 0) {
                const tab = ui.view.querySelector('.tn-tab[aria-selected="true"]');
                if (tab) focusNode(tab);
            } else if (j < sw.length) focusNode(sw[j]);
            return;
        }
        if (act && act.classList.contains('tn-tab')) {
            if (dir > 0) {
                const sw = ui.view.querySelector('.tn-swatch[aria-checked="true"]') || ui.view.querySelector('.tn-swatch');
                focusNode(sw);
            }
            return;
        }
        const items = visible(qa(ui.view, '[data-nav]').filter((n) => !n.classList.contains('tn-swatch') || n.closest('.tn-presets')));
        if (!items.length) return;
        const i = items.indexOf(act);
        if (i === -1) { focusNode(items[dir > 0 ? 0 : items.length - 1]); return; }
        focusNode(items[clamp(i + dir, 0, items.length - 1)]);
    }

    function moveHorizontal(dir) {
        const act = document.activeElement;
        if (!act) return;
        if (ui.rail.contains(act)) {
            if (dir > 0) focusInitial(false);
            return;
        }
        if (act.classList.contains('tn-tab')) {
            const tabs = qa(ui.view, '.tn-tab');
            const t = tabs[clamp(tabs.indexOf(act) + dir, 0, tabs.length - 1)];
            if (t && t !== act) { t.click(); const again = ui.view.querySelector('.tn-tab[aria-selected="true"]'); focusNode(again); }
            return;
        }
        if (act.classList.contains('tn-swatch')) {
            const grid = act.parentElement;
            const sw = qa(grid, '.tn-swatch');
            const j = clamp(sw.indexOf(act) + dir, 0, sw.length - 1);
            focusNode(sw[j]);
            return;
        }
        if (dir < 0) {
            if (S.nav.length) goBack();
            else focusNode(ui.rail.querySelector('.tn-rail-btn.is-active'));
            return;
        }
        if (act.dataset.open === '1') act.click();
    }

    document.addEventListener('keydown', (e) => {
        if (!S.open || root.hidden || !ui) return;
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        const tgt = e.target;
        const tag = tgt && tgt.tagName;
        const typing = tag === 'INPUT' && tgt.type !== 'range' && tgt.type !== 'color' && tgt.type !== 'checkbox';
        const range = tag === 'INPUT' && (tgt.type === 'range' || tgt.type === 'color');

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
                if (!S.busy) stepGroup(e.key === 'PageDown' ? 1 : -1);
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

    // ---------------------------------------------------------------------------------------------
    // Demo mode (page opened in a normal browser): window.__demo() renders a realistic payload
    // ---------------------------------------------------------------------------------------------

    if (!App.isGame) {
        const DEMO_LOCALE = Object.assign({}, FALLBACK);

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
        const sub = (id, label, items) => ({ type: 'sub', id, label, items });
        const perf = (id, label, current, counts, prices) => ({
            type: 'performance', id, label, current,
            options: [{ level: 0, label: 'Standard' }].concat(counts.map((stock, i) => ({
                level: i + 1, label: id === 'turbo' ? 'Turbo' : 'Niveau ' + (i + 1), item: id + (id === 'turbo' ? '' : '_lvl' + (i + 1)), stock, price: prices[i],
            }))),
        });

        function demoColourGroups() {
            if (Array.isArray(window.__demoColours) && window.__demoColours.length) return window.__demoColours;
            const mk = (list) => list.map(([label, hex], i) => ({ index: i, label, hex }));
            return [
                { id: 'metallic', label: 'Metallisk', colours: mk([['Sort', '#202322'], ['Grafit', '#232524'], ['Sølv', '#626C75'], ['Hvid', '#E8E8E4'], ['Rød', '#B01E23'], ['Orange', '#E0701B'], ['Gul', '#E7C429'], ['Grøn', '#1D6B3A'], ['Blå', '#2F4C8F'], ['Lilla', '#5B2A78'], ['Pink', '#D45A8E'], ['Brun', '#4A3425']]) },
                { id: 'matte', label: 'Mat', colours: mk([['Mat sort', '#161819'], ['Mat grå', '#3C4044'], ['Mat hvid', '#D9D7CF'], ['Mat rød', '#8E1D22'], ['Mat blå', '#27427A'], ['Mat grøn', '#3E5B3A']]) },
                { id: 'metals', label: 'Metaller', colours: mk([['Børstet stål', '#8D939A'], ['Sort stål', '#43484D'], ['Aluminium', '#B8BCC0'], ['Guld', '#B28E3C']]) },
                { id: 'chrome', label: 'Krom', colours: mk([['Krom', '#C6CACE']]) },
                { id: 'worn', label: 'Slidt/brugs', colours: mk([['Slidt sort', '#2A2C2D'], ['Slidt rød', '#6F2B28'], ['Slidt grøn', '#35493A'], ['Slidt blå', '#35455E'], ['Ørkensand', '#9A8A66']]) },
                { id: 'chameleon', label: 'Kamæleon', colours: mk([['Kamæleon 1', '#2E8B6E'], ['Kamæleon 2', '#6B4BB0'], ['Kamæleon 3', '#C46A2C'], ['Kamæleon 4', '#2C6AC4'], ['Kamæleon 5', '#B03C7E']]) },
            ];
        }

        function demoPayload() {
            const groupsC = demoColourGroups();
            const colour = (id, label, price, current) => ({ type: 'colour', id, label, price, current, groups: groupsC });
            const firstIdx = (gid, n) => { const g = groupsC.find((x) => x.id === gid); return g ? g.colours[Math.min(n, g.colours.length - 1)].index : 0; };

            const wheelTypes = [
                ['sport', 'Sport', 50], ['muscle', 'Muscle', 36], ['lowrider', 'Lowrider', 30], ['suv', 'SUV', 38], ['offroad', 'Offroad', 32],
                ['tuner', 'Tuner', 48], ['highend', 'High End', 40], ['bennys', 'Benny\'s Original', 36], ['bespoke', 'Benny\'s Bespoke', 36],
                ['openwheel', 'Open Wheel', 30], ['street', 'Street', 30], ['track', 'Track', 30],
            ].map(([id, label, n]) => sub('wheeltype_' + id, label, [mod('modFrontWheels:' + id, 'Fælge', 2000, id === 'sport' ? 4 : -1, n, 'Fælg')]));

            return {
                vehicle: { label: 'Karin Sultan RS', plate: 'LS 4821', owned: !window.__demoNotOwned },
                groups: [
                    { id: 'performance', label: 'Ydelse', icon: 'gauge-high', items: [
                        perf('engine', 'Motor', 2, [3, 1, 0, 0], [6000, 11000, 18000, 27000]),
                        perf('brakes', 'Bremser', 0, [2, 0, 0], [3000, 6000, 10000]),
                        perf('transmission', 'Gearkasse', 1, [4, 2, 0], [5000, 9000, 14000]),
                        perf('suspension', 'Undervogn', 0, [1, 1, 0, 0], [2500, 4500, 7000, 10000]),
                        perf('armor', 'Panser', 0, [0, 0, 0, 0, 0], [5000, 9000, 14000, 20000, 28000]),
                        perf('turbo', 'Turbo', 0, [0], [15000]),
                    ] },
                    { id: 'bodywork', label: 'Karosseri', icon: 'car-side', items: [
                        sub('front', 'Front', [mod('modFrontBumper', 'Frontkofanger', 1500, -1, 6, 'Kofanger'), mod('modGrille', 'Grill', 800, 0, 7, 'Grill'), mod('modHood', 'Motorhjelm', 1500, -1, 8, 'Motorhjelm')]),
                        sub('rear', 'Bagende', [mod('modSpoilers', 'Spoiler', 1500, 2, 9, 'Spoiler', SPOILERS), mod('modRearBumper', 'Bagkofanger', 1500, 1, 5, 'Kofanger'), mod('modExhaust', 'Udstødning', 1000, -1, 5, 'Udstødning')]),
                        sub('sides', 'Sider', [mod('modSideSkirt', 'Sideskørter', 1200, -1, 4, 'Skørter'), mod('modFrame', 'Rullebur', 2000, -1, 3, 'Rullebur'), mod('modFender', 'Venstre skærm', 1000, -1, 3, 'Skærm'), mod('modRightFender', 'Højre skærm', 1000, -1, 3, 'Skærm'), mod('modTrimA', 'Pynteliste', 800, -1, 4, 'Liste'), mod('modTank', 'Tankdæksel', 500, -1, 3, 'Dæksel'), mod('modWindows', 'Ruder', 800, -1, 2, 'Rude')]),
                        sub('roof', 'Tag', [mod('modRoof', 'Tag', 1200, -1, 3, 'Tag'), mod('modAerials', 'Antenner', 500, -1, 3, 'Antenne')]),
                    ] },
                    { id: 'wheels', label: 'Hjul', icon: 'circle-dot', items: wheelTypes.concat([
                        sub('tyres', 'Dæk', [
                            { type: 'toggle', id: 'modCustomTiresF', label: 'Specialdæk', price: 800, current: false },
                            { type: 'toggle', id: 'modSmokeEnabled', label: 'Dækrøg', price: 1500, current: false },
                            { type: 'rgb', id: 'tyreSmokeColor', label: 'Dækrøgfarve', price: 0, current: { r: 255, g: 255, b: 255 } },
                        ]),
                        colour('wheelColor', 'Fælgfarve', 1000, firstIdx('metallic', 2)),
                    ]) },
                    { id: 'respray', label: 'Lakering', icon: 'fill-drip', items: [
                        colour('color1', 'Primærfarve', 2500, firstIdx('metallic', 4)),
                        colour('color2', 'Sekundærfarve', 2000, firstIdx('metallic', 0)),
                        colour('pearlescent', 'Perlemor', 1500, firstIdx('metallic', 3)),
                    ] },
                    { id: 'interior', label: 'Kabine', icon: 'couch', items: [
                        sub('dash', 'Instrumentbræt', [mod('modOrnaments', 'Ornamenter', 400, -1, 4, 'Ornament'), mod('modDashboard', 'Instrumentbræt', 1200, -1, 5, 'Instrumentbræt'), mod('modDial', 'Måleur', 800, -1, 6, 'Måleur'), mod('modSteeringWheel', 'Rat', 1000, -1, 8, 'Rat'), mod('modShifterLeavers', 'Gearstang', 600, -1, 5, 'Gearstang')]),
                        sub('seats', 'Sæder', [mod('modSeats', 'Sæder', 1500, -1, 6, 'Sæde'), mod('modAPlate', 'Skilte', 400, -1, 4, 'Skilt')]),
                        sub('audio', 'Lyd', [mod('modDoorSpeaker', 'Dørhøjttalere', 800, -1, 3, 'Højttaler'), mod('modSpeakers', 'Højttalere', 1000, -1, 3, 'Højttaler')]),
                        sub('trunk', 'Bagagerum', [mod('modTrunk', 'Bagagerum', 1200, -1, 3, 'Bagagerum')]),
                        colour('interiorColor', 'Kabinefarve', 1000, firstIdx('matte', 1)),
                        colour('dashboardColor', 'Instrumentfarve', 800, firstIdx('matte', 0)),
                    ] },
                    { id: 'engine', label: 'Motorrum', icon: 'gears', items: [
                        mod('modEngineBlock', 'Motorblok', 1500, -1, 4, 'Motorblok'), mod('modAirFilter', 'Luftfilter', 800, -1, 4, 'Luftfilter'),
                        mod('modStruts', 'Fjederbensstivere', 1000, -1, 4, 'Stivere'), mod('modArchCover', 'Hjulkasser', 800, -1, 4, 'Hjulkasse'),
                        mod('modTrimB', 'Motorpynt', 600, -1, 3, 'Pynt'), mod('modHydrolic', 'Hydraulik', 3000, -1, 3, 'Hydraulik'),
                    ] },
                    { id: 'lights', label: 'Lys', icon: 'lightbulb', items: [
                        sub('xenon', 'Xenon', [
                            { type: 'toggle', id: 'modXenon', label: 'Xenon', price: 1500, current: false },
                            {
                                type: 'list', id: 'xenonColor', label: 'Xenonfarve', price: 0, current: 255,
                                options: [{ value: 255, label: 'Standard' }].concat(['Hvid', 'Blå', 'Elektrisk blå', 'Mintgrøn', 'Limegrøn', 'Gul', 'Gylden', 'Orange', 'Rød', 'Pink', 'Hot pink', 'Lilla', 'Blacklight'].map((l, i) => ({ value: i, label: l }))),
                            },
                        ]),
                        sub('neon', 'Neon', [
                            { type: 'toggle', id: 'neonEnabled', label: 'Neon', price: 3000, current: false },
                            list('neonLayout', 'Placering', 0, 0, ['Alle sider', 'Foran og bagved', 'Kun sider', 'Kun under']),
                            { type: 'rgb', id: 'neonColor', label: 'Neonfarve', price: 0, current: { r: 255, g: 0, b: 80 } },
                        ]),
                    ] },
                    { id: 'plates', label: 'Nummerplade', icon: 'id-card', items: [
                        list('plateIndex', 'Pladetype', 300, 0, ['Blå på hvid 1', 'Gul på sort', 'Gul på blå', 'Blå på hvid 2', 'Blå på hvid 3', 'San Andreas']),
                        mod('modPlateHolder', 'Pladeholder', 300, -1, 4, 'Holder'), mod('modVanityPlate', 'Forfængelighedsplade', 300, -1, 4, 'Plade'),
                    ] },
                    { id: 'other', label: 'Andet', icon: 'ellipsis', items: [
                        list('windowTint', 'Rudetoning', 800, 0, ['Ingen', 'Helt sort', 'Mørk røg', 'Lys røg', 'Standard', 'Limo', 'Grøn']),
                        mod('modLivery', 'Livery', 2500, -1, 6, 'Livery'),
                        mod('modHorns', 'Horn', 500, -1, 40, 'Horn'),
                    ] },
                ],
            };
        }

        window.__demo = (opts) => {
            App.setLocale(DEMO_LOCALE);
            window.postMessage({ action: 'openTuning', data: demoPayload() }, '*');
            return opts;
        };
        window.__demoClose = () => window.postMessage({ action: 'closeTuning', data: {} }, '*');
    }
})();
