/* Workshop computer (NUI side of contract sections 0.6 and 7). Builds all DOM inside #laptop-root.
 *
 * Lua -> NUI:  laptop:open { name, grade, gradeLabel, isBoss, workshop, shop }, laptop:close {}
 * NUI -> Lua:  laptop:request { method, args } -> { ok, data, error }, laptop:close {}
 *
 * A MacBook-style desktop: menu bar, dock with magnification, draggable windows, and the apps
 * Lager, Bestil, Ordrer (everyone) plus Personale, Okonomi, Prisliste (chef only; the server
 * re-checks every call). All dynamic text goes through textContent (App.el).
 * Chrome 103: no :has(), color-mix(), nesting.
 */
(function () {
    'use strict';

    const root = document.getElementById('laptop-root');
    if (!root || !window.App) return;

    const el = App.el;

    // ---------------------------------------------------------------------------------------------
    // Strings: App.t() returns the key when the locale lacks it, so every key has a Danish fallback.
    // The comment after each entry is the English meaning (for en.json).
    // ---------------------------------------------------------------------------------------------

    const FALLBACK = {
        pc_app_stock: 'Lager', // Stock (app)
        pc_app_order: 'Bestil', // Order (app)
        pc_app_orders: 'Ordrer', // Orders (app)
        pc_app_staff: 'Personale', // Staff (app)
        pc_app_eco: 'Økonomi', // Finances (app)
        pc_app_prices: 'Prisliste', // Price list (app)
        pc_desktop: 'Skrivebord', // Desktop (app name in the menu bar when no window is focused)
        pc_menu_about: 'Om denne computer', // About this computer
        pc_menu_close_pc: 'Luk computer', // Shut down / close the computer
        pc_menu_apps: 'Programmer', // Apps (menu)
        pc_menu_window: 'Vindue', // Window (menu)
        pc_menu_refresh: 'Opdater', // Refresh
        pc_menu_minimize: 'Minimér', // Minimise
        pc_menu_zoom: 'Zoom', // Zoom
        pc_menu_close_win: 'Luk vindue', // Close window
        pc_menu_minimize_all: 'Minimér alle', // Minimise all
        pc_menu_close_all: 'Luk alle vinduer', // Close all windows
        pc_menu_no_windows: 'Ingen åbne vinduer', // No open windows
        pc_about_title: 'Værkstedscomputer', // Workshop computer
        pc_about_ok: 'OK', // OK
        pc_close: 'Luk', // Close
        pc_cancel: 'Annuller', // Cancel
        pc_retry: 'Prøv igen', // Try again
        pc_refresh: 'Opdater', // Refresh (tooltip)
        pc_search: 'Søg', // Search (placeholder)
        pc_err_generic: 'Noget gik galt. Prøv igen.', // Something went wrong. Try again.
        pc_err_network: 'Ingen forbindelse til serveren.', // No connection to the server.
        pc_widget_orders: 'Ordrer undervejs', // Orders on the way (desktop widget)
        pc_widget_balance: 'Firmakonto', // Society balance (desktop widget)
        pc_widget_ready: 'Klar til afhentning', // Crates ready for pickup (desktop widget)
        pc_filter_all: 'Alle varer', // All items
        pc_filter_in: 'På lager', // In stock
        pc_filter_low: 'Lav beholdning', // Low stock
        pc_filter_out: 'Mangler', // Out of stock
        pc_side_stock: 'Lager', // Stock (sidebar section)
        pc_side_categories: 'Kategorier', // Categories (sidebar section)
        pc_cat_repair: 'Reparation', // Repair (category)
        pc_cat_engine: 'Motor', // Engine (category)
        pc_cat_brakes: 'Bremser', // Brakes (category)
        pc_cat_transmission: 'Gearkasse', // Transmission (category)
        pc_cat_suspension: 'Undervogn', // Suspension (category)
        pc_cat_armor: 'Panser', // Armor (category)
        pc_cat_turbo: 'Turbo', // Turbo (category)
        pc_cat_other: 'Andet', // Other (category)
        pc_col_item: 'Vare', // Item (column)
        pc_col_category: 'Kategori', // Category (column)
        pc_col_price: 'Pris', // Price (column)
        pc_col_qty: 'Antal', // Quantity (column)
        pc_col_default: 'Standard', // Default (column)
        pc_order_btn: 'Bestil', // Order (button)
        pc_stock_empty: 'Ingen varer matcher.', // No items match.
        pc_stock_summary: '%s varer · %s stk. på lager', // N items · N pcs in stock
        pc_in_stock: '%s på lager', // N in stock
        pc_out_of_stock: 'Ikke på lager', // Not in stock
        pc_low_stock: 'Lav beholdning', // Low stock (badge)
        pc_add_cart: 'Læg i kurv', // Add to cart
        pc_cart: 'Kurv', // Cart
        pc_cart_empty: 'Kurven er tom.', // The cart is empty.
        pc_cart_clear: 'Tøm', // Clear (cart)
        pc_cart_remove: 'Fjern', // Remove (tooltip)
        pc_total: 'I alt', // Total
        pc_society_pays: 'Firmakontoen betaler', // The society account pays
        pc_delivery_eta: 'Leveres om ca. %s min', // Delivered in about N min
        pc_place_order: 'Bestil', // Place order (button)
        pc_ordering: 'Bestiller...', // Ordering...
        pc_order_placed: 'Ordre #%s afgivet: %s. Leveres om ca. %s min.', // Order #N placed: $X. Delivered in about N min.
        pc_max_lines: 'Højst %s forskellige varer pr. ordre.', // At most N different items per order.
        pc_max_qty: 'Højst %s stk. pr. vare.', // At most N pieces per item.
        pc_catalog_empty: 'Ingen varer i kataloget.', // No items in the catalog.
        pc_orders_all: 'Alle', // All (orders filter)
        pc_st_ordered: 'Undervejs', // On the way (order status)
        pc_st_arrived: 'Klar til afhentning', // Ready for pickup (order status)
        pc_st_collected: 'Afhentet', // Collected (order status)
        pc_orders_empty: 'Ingen ordrer endnu.', // No orders yet.
        pc_order_no: 'Ordre #%s', // Order #N
        pc_order_by: 'af %s', // by NAME
        pc_order_arrives: 'Ankommer om %s', // Arrives in M:SS
        pc_order_arriving: 'Ankommer snart...', // Arriving soon...
        pc_order_ready: 'Kassen står ved leveringspunktet. Pak den ud i lageret.', // The crate is at the delivery point. Unpack it into the stock.
        pc_staff_all: 'Alle', // All (staff filter)
        pc_staff_online: 'Online', // Online
        pc_staff_offline: 'Offline', // Offline
        pc_staff_hire: 'Ansæt', // Hire
        pc_staff_group: 'Medarbejdere', // Employees (sidebar section)
        pc_staff_empty: 'Ingen medarbejdere.', // No employees.
        pc_staff_you: 'Dig', // You
        pc_staff_fire: 'Fyr', // Fire
        pc_staff_locked: 'Kan ikke ændres', // Cannot be changed
        pc_staff_grade: 'Stilling', // Rank
        pc_fire_title: 'Fyr %s?', // Fire NAME?
        pc_fire_text: '%s mister adgang til værkstedet og bliver arbejdsløs. Det kan ikke fortrydes.', // NAME loses access to the workshop and becomes unemployed. This cannot be undone.
        pc_nearby_empty: 'Ingen i nærheden af computeren.', // Nobody near the computer.
        pc_nearby_hint: 'Spillere inden for rækkevidde af computeren, som endnu ikke er mekanikere.', // Players within range of the computer who are not mechanics yet.
        pc_hire_btn: 'Ansæt', // Hire (button)
        pc_hired: '%s er ansat.', // NAME has been hired.
        pc_hire_waiting: 'Venter på svar fra %s...', // Waiting for NAME to answer...
        pc_fired: '%s er fyret.', // NAME has been fired.
        pc_grade_set: 'Stilling opdateret.', // Rank updated.
        pc_server_id: 'ID %s', // ID N
        pc_eco_title: 'Firmakontoen', // The society account
        pc_eco_income: 'Indtægter', // Income
        pc_eco_expense: 'Udgifter', // Expenses
        pc_eco_transfer: 'Overfør penge', // Transfer money
        pc_eco_amount: 'Beløb', // Amount
        pc_eco_deposit: 'Indsæt', // Deposit
        pc_eco_withdraw: 'Hæv', // Withdraw
        pc_eco_history: 'Historik', // History
        pc_eco_empty: 'Ingen posteringer endnu.', // No transactions yet.
        pc_eco_bad_amount: 'Indtast et helt beløb på mindst $1.', // Enter a whole amount of at least $1.
        pc_eco_max: 'Højst %s pr. overførsel.', // At most X per transfer.
        pc_eco_done_deposit: '%s indsat i firmakontoen.', // X deposited into the society account.
        pc_eco_done_withdraw: '%s hævet fra firmakontoen.', // X withdrawn from the society account.
        pc_eco_all: 'Alle', // All (history filter)
        pc_eco_invoices: 'Fakturaer', // Invoices (history filter)
        pc_eco_orders: 'Bestillinger', // Orders (history filter)
        pc_eco_transfers: 'Overførsler', // Transfers (history filter)
        pc_eco_t_invoice: 'Faktura', // Invoice (history type)
        pc_eco_t_order: 'Bestilling', // Order (history type)
        pc_eco_t_deposit: 'Indsæt', // Deposit (history type)
        pc_eco_t_withdraw: 'Hævning', // Withdrawal (history type)
        pc_eco_by: 'af %s', // by NAME
        pc_prices_all: 'Alle priser', // All prices
        pc_prices_changed: 'Ændrede', // Changed
        pc_prices_groups: 'Grupper', // Groups (sidebar section)
        pc_prices_save: 'Gem priser', // Save prices
        pc_prices_discard: 'Fortryd', // Discard
        pc_prices_reset_row: 'Nulstil til standard', // Reset to default
        pc_prices_saved: 'Priserne er gemt (%s ændret).', // The prices are saved (N changed).
        pc_prices_none: 'Ingen ændringer', // No changes
        pc_prices_one: '1 ændring', // 1 change
        pc_prices_many: '%s ændringer', // N changes
        pc_prices_invalid: 'En eller flere priser er ugyldige (0-%s).', // One or more prices are invalid (0-N).
        pc_prices_empty: 'Ingen priser matcher.', // No prices match.
        pc_prices_unsaved_title: 'Gem ændringerne?', // Save the changes?
        pc_prices_unsaved_text: 'Du har ændret priser, som ikke er gemt.', // You have changed prices that are not saved.
        pc_prices_dont_save: 'Gem ikke', // Don't save
        pc_grp_bodywork: 'Karosseri', // Bodywork
        pc_grp_wheels: 'Hjul', // Wheels
        pc_grp_respray: 'Lakering', // Paint
        pc_grp_interior: 'Kabine', // Interior
        pc_grp_engine: 'Motorrum', // Engine bay
        pc_grp_lights: 'Lys', // Lights
        pc_grp_plates: 'Nummerplade', // Number plate
        pc_grp_other: 'Andet', // Other
    };

    function fmt(s, args) {
        let i = 0;
        return String(s).replace(/%[sd]/g, () => (i < args.length ? String(args[i++]) : ''));
    }

    function T(key, ...args) {
        const s = App.t(key, ...args);
        if (s !== key) return s;
        return FALLBACK[key] !== undefined ? fmt(FALLBACK[key], args) : key;
    }

    // ---------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------

    const num = (v) => { const n = Number(v); return isFinite(n) ? n : 0; };
    const pad2 = (n) => (n < 10 ? '0' : '') + n;

    // "$12.500" (Danish thousands separator)
    function money(n) {
        n = Math.round(num(n));
        const neg = n < 0;
        return (neg ? '-' : '') + '$' + String(Math.abs(n)).replace(/\B(?=(\d{3})+(?!\d))/g, '.');
    }

    const DAYS = ['søn.', 'man.', 'tir.', 'ons.', 'tor.', 'fre.', 'lør.'];
    const MONTHS = ['jan.', 'feb.', 'mar.', 'apr.', 'maj', 'jun.', 'jul.', 'aug.', 'sep.', 'okt.', 'nov.', 'dec.'];
    const DAYS_LONG = ['søndag', 'mandag', 'tirsdag', 'onsdag', 'torsdag', 'fredag', 'lørdag'];

    function toDate(v) {
        if (v === null || v === undefined || v === '') return null;
        if (v instanceof Date) return v;
        if (typeof v === 'number') return new Date(v < 1e12 ? v * 1000 : v);
        if (typeof v === 'string') {
            if (/^\d+$/.test(v)) return toDate(Number(v));
            const d = new Date(v.replace(' ', 'T'));
            return isNaN(d.getTime()) ? null : d;
        }
        return null;
    }

    function fmtDate(v) {
        const d = toDate(v);
        if (!d) return '';
        return d.getDate() + '. ' + MONTHS[d.getMonth()] + ' ' + pad2(d.getHours()) + ':' + pad2(d.getMinutes());
    }

    function fmtClock(sec) {
        sec = Math.max(0, Math.floor(sec));
        return pad2(Math.floor(sec / 60)) + ':' + pad2(sec % 60);
    }

    const ic = (name, extra) => el('i', { class: 'fa-solid fa-' + name + (extra ? ' ' + extra : ''), attrs: { 'aria-hidden': 'true' } });

    function emPx() {
        return parseFloat(getComputedStyle(root).fontSize) || 13;
    }

    // ---------------------------------------------------------------------------------------------
    // Requests to Lua (or the demo mock)
    // ---------------------------------------------------------------------------------------------

    let demoHandler = null;

    // Read-only methods: identical calls in flight share one request, so two windows refreshing in the
    // same tick do not trip the server's rate limits (the second call would get 'too_fast')
    const READ_METHODS = new Set(['stock:get', 'order:list', 'computer:catalog', 'computer:staff', 'computer:nearby', 'computer:economy', 'computer:prices']);
    const inflight = new Map();

    // Longest server rate limit of a read method (computer:economy / computer:staff) plus a little slack
    const READ_RETRY_MS = 1100;

    function rpc(method, args) {
        if (!READ_METHODS.has(method)) return rpcSend(method, args);
        const key = method + '|' + JSON.stringify(args || []);
        const pending = inflight.get(key);
        if (pending) return pending;
        // A read that still hits a rate limit (same call shortly before) is retried once after the limit
        const p = rpcSend(method, args)
            .then((r) => (!r.ok && r.code === 'too_fast'
                ? new Promise((resolve) => setTimeout(resolve, READ_RETRY_MS)).then(() => rpcSend(method, args))
                : r))
            .finally(() => inflight.delete(key));
        inflight.set(key, p);
        return p;
    }

    async function rpcSend(method, args) {
        let res;
        try {
            res = demoHandler
                ? await demoHandler(method, args || [])
                : await App.post('laptop:request', { method, args: args || [] });
        } catch (e) {
            res = null;
        }
        if (!res || typeof res !== 'object') return { ok: false, error: T('pc_err_network') };
        if (!res.ok) return { ok: false, error: (typeof res.error === 'string' && res.error) || T('pc_err_generic'), code: typeof res.code === 'string' ? res.code : null };
        return { ok: true, data: res.data };
    }

    // ---------------------------------------------------------------------------------------------
    // State
    // ---------------------------------------------------------------------------------------------

    const S = {
        open: false,
        data: null,
        isBoss: false,
        wins: new Map(),
        z: 10,
        focused: null,
        cart: {},
        cartSubs: new Set(),
        menu: null,
        modals: [],
        intervals: [],
        dockMeta: null,
    };
    const dom = {};

    // Item categories (derived from the item name; the catalog only has item, label, price, stock)
    const CATS = [
        { id: 'repair', icon: 'screwdriver-wrench', c: ['#ff9f0a', '#e8590c'] },
        { id: 'engine', icon: 'gauge-high', c: ['#ff453a', '#b3261e'] },
        { id: 'brakes', icon: 'compact-disc', c: ['#64d2ff', '#0a84ff'] },
        { id: 'transmission', icon: 'gears', c: ['#bf5af2', '#8944ab'] },
        { id: 'suspension', icon: 'arrows-up-down', c: ['#30d158', '#1f9d40'] },
        { id: 'armor', icon: 'shield-halved', c: ['#7d7aff', '#4a46c8'] },
        { id: 'turbo', icon: 'fan', c: ['#ffd60a', '#d99a00'] },
        { id: 'other', icon: 'box', c: ['#98989d', '#636366'] },
    ];
    const CAT_BY = {};
    CATS.forEach((c) => { CAT_BY[c.id] = c; });

    const ITEM_ICON = {
        repair_kit: 'wrench',
        engine_repair_kit: 'screwdriver-wrench',
        body_repair_kit: 'car-burst',
        tyre: 'circle-dot',
    };

    function catOf(name) {
        name = String(name);
        if (/^(repair_kit|engine_repair_kit|body_repair_kit|tyre)$/.test(name)) return 'repair';
        if (name === 'turbo') return 'turbo';
        const m = /^([a-z]+)_lvl\d+$/.exec(name);
        if (m && CAT_BY[m[1]] && m[1] !== 'repair') return m[1];
        return 'other';
    }

    function lvlOf(name) {
        const m = /_lvl(\d+)$/.exec(String(name));
        return m ? m[1] : '';
    }

    function itemTile(name, size) {
        const cat = CAT_BY[catOf(name)];
        const lvl = lvlOf(name);
        const t = el('div', { class: 'lp-tile', attrs: { style: '--c1:' + cat.c[0] + ';--c2:' + cat.c[1] + (size ? ';--t:' + size : '') } },
            [ic(ITEM_ICON[name] || cat.icon), lvl ? el('em', { text: lvl }) : null]);
        return t;
    }

    function limits() {
        const shop = (S.data && S.data.shop) || {};
        return {
            perLine: num(shop.maxPerLine) > 0 ? num(shop.maxPerLine) : 20,
            lines: num(shop.maxLines) > 0 ? num(shop.maxLines) : 15,
            minutes: num(shop.deliveryMinutes) > 0 ? num(shop.deliveryMinutes) : 5,
            maxPrice: num(shop.maxPrice) > 0 ? num(shop.maxPrice) : 250000,
            maxTransfer: num(shop.maxTransfer) > 0 ? num(shop.maxTransfer) : 1000000,
        };
    }

    // ---------------------------------------------------------------------------------------------
    // Small UI components
    // ---------------------------------------------------------------------------------------------

    function loader() {
        return el('div', { class: 'lp-empty' }, [el('div', { class: 'lp-spin' })]);
    }

    function emptyState(icon, text) {
        return el('div', { class: 'lp-empty' }, [ic(icon), el('p', { text })]);
    }

    function errorState(msg, retry) {
        return el('div', { class: 'lp-empty' }, [
            ic('triangle-exclamation'),
            el('p', { text: msg }),
            retry ? el('button', { class: 'lp-btn', text: T('pc_retry'), attrs: { type: 'button' }, on: { click: retry } }) : null,
        ]);
    }

    // Inline message strip. kind: 'err' | 'ok'
    function banner(kind, text, onClose) {
        return el('div', { class: 'lp-alert' + (kind === 'ok' ? ' ok' : ''), attrs: { role: kind === 'ok' ? 'status' : 'alert' } }, [
            ic(kind === 'ok' ? 'circle-check' : 'triangle-exclamation'),
            el('span', { class: 'txt', text }),
            onClose ? el('button', { attrs: { type: 'button', 'aria-label': T('pc_close') }, on: { click: onClose } }, [ic('xmark')]) : null,
        ]);
    }

    function searchBox(onInput) {
        const input = el('input', { attrs: { type: 'text', placeholder: T('pc_search'), maxlength: '40', autocomplete: 'off', spellcheck: 'false' } });
        input.addEventListener('input', () => onInput(input.value));
        return { node: el('label', { class: 'lp-search' }, [ic('magnifying-glass'), input]), input };
    }

    // options: [{ id, label }]
    function segmented(options, value, onChange) {
        const btns = {};
        const node = el('div', { class: 'lp-seg', attrs: { role: 'tablist' } });
        options.forEach((o) => {
            const b = el('button', { text: o.label, attrs: { type: 'button', role: 'tab' }, on: { click: () => { set(o.id); onChange(o.id); } } });
            btns[o.id] = b;
            node.appendChild(b);
        });
        function set(v) {
            Object.keys(btns).forEach((k) => btns[k].classList.toggle('is-active', k === v));
        }
        set(value);
        return { node, set };
    }

    function sideItem(icon, label, count, active, onClick) {
        return el('button', { class: 'lp-side-item' + (active ? ' is-active' : ''), attrs: { type: 'button' }, on: { click: onClick } }, [
            ic(icon),
            el('span', { class: 'label', text: label }),
            count !== null && count !== undefined ? el('span', { class: 'count', text: count }) : null,
        ]);
    }

    function sideHead(text) {
        return el('div', { class: 'lp-side-head', text });
    }

    function hueOf(str) {
        let h = 0;
        for (let i = 0; i < str.length; i++) h = (h * 31 + str.charCodeAt(i)) % 360;
        return h;
    }

    function avatar(name, online) {
        const initials = String(name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map((p) => p[0].toUpperCase()).join('');
        return el('div', { class: 'lp-avatar', attrs: { style: '--h:' + hueOf(String(name || '')) } },
            [initials || '?', online === undefined ? null : el('span', { class: 'dot' + (online ? ' on' : '') })]);
    }

    // ---------------------------------------------------------------------------------------------
    // Sheets (macOS style confirm dialogs, inside a window) and modals (on the desktop)
    // ---------------------------------------------------------------------------------------------

    // o: { icon, danger, title, text, buttons: [{ label, kind, default, action }] }
    // A button's action may return { ok:false, error } to keep the sheet open with an inline error.
    function buildSheet(o, close) {
        const err = el('div', { class: 'lp-sheet-err', attrs: { role: 'alert' } });
        err.hidden = true;
        const row = el('div', { class: 'lp-sheet-btns' });
        const btns = [];
        let def = null;
        let busy = false;
        const setBusy = (b) => { busy = b; btns.forEach((x) => { x.disabled = b; }); };
        (o.buttons || []).forEach((b) => {
            const btn = el('button', { class: 'lp-btn lg ' + (b.kind || ''), text: b.label, attrs: { type: 'button' } });
            btn.addEventListener('click', async () => {
                if (busy) return;
                if (!b.action) { close(); return; }
                setBusy(true);
                let r;
                try { r = await b.action(); } catch (e) { r = { ok: false, error: T('pc_err_generic') }; }
                setBusy(false);
                if (r && r.ok === false) {
                    err.textContent = r.error || T('pc_err_generic');
                    err.hidden = false;
                    return;
                }
                close();
            });
            btns.push(btn);
            row.appendChild(btn);
            if (b.default) def = btn;
        });
        const node = el('div', { class: 'lp-sheet', attrs: { role: 'alertdialog', 'aria-modal': 'true' } }, [
            el('div', { class: 'glyph' + (o.danger ? ' danger' : '') }, [ic(o.icon || 'circle-info')]),
            el('h3', { text: o.title || '' }),
            o.text ? el('p', { text: o.text }) : null,
            err,
            row,
        ]);
        return {
            node,
            focus() { (def || btns[btns.length - 1]).focus(); },
            cancel() { if (!busy) close(); },
        };
    }

    function winSheet(w, o) {
        const bg = el('div', { class: 'lp-sheet-bg' });
        let entry;
        const close = () => {
            w.sheets = w.sheets.filter((x) => x !== entry);
            if (bg.parentNode) bg.parentNode.removeChild(bg);
        };
        entry = buildSheet(o, close);
        bg.appendChild(entry.node);
        w.el.appendChild(bg);
        w.sheets.push(entry);
        entry.focus();
        return entry;
    }

    function showModal(o) {
        const bg = el('div', { class: 'lp-modal-bg' });
        let entry;
        const close = () => {
            S.modals = S.modals.filter((x) => x !== entry);
            if (bg.parentNode) bg.parentNode.removeChild(bg);
        };
        entry = buildSheet(o, close);
        bg.appendChild(entry.node);
        dom.screen.appendChild(bg);
        S.modals.push(entry);
        entry.focus();
    }

    // ---------------------------------------------------------------------------------------------
    // Cart (shared between Lager and Bestil)
    // ---------------------------------------------------------------------------------------------

    function notifyCart() {
        S.cartSubs.forEach((fn) => { try { fn(); } catch (e) { /* a closed window */ } });
    }

    function cartLines() {
        return Object.keys(S.cart).length;
    }

    // Returns null on success or a message
    function cartAdd(item, n) {
        const lim = limits();
        const cur = S.cart[item] || 0;
        if (cur === 0 && cartLines() >= lim.lines) return T('pc_max_lines', lim.lines);
        const next = cur + n;
        if (next > lim.perLine) {
            S.cart[item] = lim.perLine;
            notifyCart();
            return T('pc_max_qty', lim.perLine);
        }
        if (next <= 0) delete S.cart[item];
        else S.cart[item] = next;
        notifyCart();
        return null;
    }

    function cartSet(item, n) {
        if (n <= 0) delete S.cart[item];
        else S.cart[item] = Math.min(limits().perLine, n);
        notifyCart();
    }

    function refreshApps(ids) {
        ids.forEach((id) => {
            const w = S.wins.get(id);
            if (w && w.api && w.api.refresh) w.api.refresh();
        });
    }

    // ---------------------------------------------------------------------------------------------
    // Window manager
    // ---------------------------------------------------------------------------------------------

    function visibleApps() {
        return APPS.filter((a) => !a.boss || S.isBoss);
    }

    function deskSize() {
        return { w: dom.windows.clientWidth, h: dom.windows.clientHeight };
    }

    function dockReserve() {
        return (dom.dock ? dom.dock.offsetHeight : 0) + emPx() * 1.2;
    }

    function applyRect(w) {
        const r = w.rect;
        w.el.style.left = Math.round(r.x) + 'px';
        w.el.style.top = Math.round(r.y) + 'px';
        w.el.style.width = Math.round(r.w) + 'px';
        w.el.style.height = Math.round(r.h) + 'px';
    }

    function clampRect(w) {
        const d = deskSize();
        const em = emPx();
        const r = w.rect;
        if (w.zoomed) {
            r.x = 0; r.y = 0; r.w = d.w; r.h = d.h - dockReserve() + em * 0.6;
            return;
        }
        r.w = Math.min(r.w, d.w - em * 0.8);
        r.h = Math.min(r.h, d.h - dockReserve() + em * 0.4);
        r.x = Math.max(-(r.w - em * 7), Math.min(r.x, d.w - em * 7));
        r.y = Math.max(0, Math.min(r.y, d.h - em * 3.2));
    }

    function createWindow(app) {
        const em = emPx();
        const d = deskSize();
        const w = {
            id: app.id,
            app,
            minimized: false,
            zoomed: false,
            prev: null,
            sheets: [],
            timers: [],
            dead: false,
            api: null,
            rect: { x: 0, y: 0, w: app.size[0] * em, h: app.size[1] * em },
        };
        const n = S.wins.size % 4;
        w.rect.w = Math.min(w.rect.w, d.w - em * 1.6);
        w.rect.h = Math.min(w.rect.h, d.h - dockReserve() + em * 0.2);
        w.rect.x = Math.max(em * 0.4, (d.w - w.rect.w) / 2 + (n - 1.5) * em * 1.8);
        w.rect.y = Math.max(em * 0.5, Math.min(em * 0.8 + n * em * 1.8, d.h - dockReserve() - w.rect.h + em * 0.2));

        const lights = el('div', { class: 'lp-lights' }, [
            el('button', { class: 'lp-light close', attrs: { type: 'button', 'aria-label': T('pc_menu_close_win') }, on: { click: () => closeWin(w) } }, [ic('xmark')]),
            el('button', { class: 'lp-light min', attrs: { type: 'button', 'aria-label': T('pc_menu_minimize') }, on: { click: () => minimize(w) } }, [ic('minus')]),
            el('button', { class: 'lp-light zoom', attrs: { type: 'button', 'aria-label': T('pc_menu_zoom') }, on: { click: () => toggleZoom(w) } }, [ic('up-right-and-down-left-from-center')]),
        ]);
        w.tools = el('div', { class: 'lp-win-tools' });
        const bar = el('div', { class: 'lp-win-bar' }, [
            lights,
            el('div', { class: 'lp-win-title' }, [ic(app.icon), el('span', { text: T(app.key) })]),
            w.tools,
        ]);
        w.body = el('div', { class: 'lp-win-body' });
        const grip = el('div', { class: 'lp-resize' });
        w.el = el('div', { class: 'lp-win', attrs: { tabindex: '-1', role: 'dialog', 'aria-label': T(app.key), 'data-app': app.id } }, [bar, w.body, grip]);
        applyRect(w);
        dom.windows.appendChild(w.el);

        w.alive = () => !w.dead;
        w.timer = (fn, ms) => { const id = setInterval(fn, ms); w.timers.push(id); return id; };

        // Focus on any press inside the window
        w.el.addEventListener('pointerdown', () => focusWin(w), true);

        // Dragging by the title bar
        bar.addEventListener('pointerdown', (e) => {
            if (e.button !== 0 || e.target.closest('button,input,select,.lp-seg,.lp-search')) return;
            if (w.zoomed) return;
            const sx = e.clientX; const sy = e.clientY; const ox = w.rect.x; const oy = w.rect.y;
            bar.setPointerCapture(e.pointerId);
            const move = (ev) => {
                w.rect.x = ox + ev.clientX - sx;
                w.rect.y = oy + ev.clientY - sy;
                clampRect(w);
                applyRect(w);
            };
            const up = () => {
                bar.removeEventListener('pointermove', move);
                bar.removeEventListener('pointerup', up);
                bar.removeEventListener('pointercancel', up);
            };
            bar.addEventListener('pointermove', move);
            bar.addEventListener('pointerup', up);
            bar.addEventListener('pointercancel', up);
        });
        bar.addEventListener('dblclick', (e) => {
            if (!e.target.closest('button,input,select,.lp-seg,.lp-search')) toggleZoom(w);
        });

        // Resizing from the bottom-right corner
        grip.addEventListener('pointerdown', (e) => {
            if (e.button !== 0 || w.zoomed) return;
            const sx = e.clientX; const sy = e.clientY; const ow = w.rect.w; const oh = w.rect.h;
            grip.setPointerCapture(e.pointerId);
            const move = (ev) => {
                const dd = deskSize();
                w.rect.w = Math.max(app.min[0] * em, Math.min(ow + ev.clientX - sx, dd.w - w.rect.x));
                w.rect.h = Math.max(app.min[1] * em, Math.min(oh + ev.clientY - sy, dd.h - w.rect.y));
                applyRect(w);
            };
            const up = () => {
                grip.removeEventListener('pointermove', move);
                grip.removeEventListener('pointerup', up);
                grip.removeEventListener('pointercancel', up);
            };
            grip.addEventListener('pointermove', move);
            grip.addEventListener('pointerup', up);
            grip.addEventListener('pointercancel', up);
        });

        w.api = app.mount(w) || {};
        return w;
    }

    function focusWin(w) {
        if (!w || w.dead) return;
        if (S.focused === w && !w.minimized) return;
        S.focused = w;
        w.el.style.zIndex = String(++S.z);
        S.wins.forEach((x) => x.el.classList.toggle('is-focused', x === w));
        updateChrome();
    }

    function focusTop() {
        let best = null;
        S.wins.forEach((x) => {
            if (!x.minimized && !x.dead && (!best || num(x.el.style.zIndex) > num(best.el.style.zIndex))) best = x;
        });
        S.focused = null;
        S.wins.forEach((x) => x.el.classList.remove('is-focused'));
        if (best) focusWin(best);
        else updateChrome();
    }

    function openApp(id) {
        const app = APPS.find((a) => a.id === id);
        if (!app || (app.boss && !S.isBoss)) return null;
        let w = S.wins.get(id);
        if (w) {
            if (w.minimized) restoreWin(w);
            focusWin(w);
            return w;
        }
        w = createWindow(app);
        S.wins.set(id, w);
        focusWin(w);
        const item = dom.dockItems && dom.dockItems[id];
        if (item) {
            item.classList.remove('is-bounce');
            void item.offsetWidth;
            item.classList.add('is-bounce');
            setTimeout(() => item.classList.remove('is-bounce'), 900);
        }
        return w;
    }

    function dockOrigin(w) {
        const item = dom.dockItems && dom.dockItems[w.id];
        const wr = w.el.getBoundingClientRect();
        if (!item) return '50% 100%';
        const ir = item.getBoundingClientRect();
        return Math.round(ir.left + ir.width / 2 - wr.left) + 'px ' + Math.round(ir.top + ir.height / 2 - wr.top) + 'px';
    }

    function minimize(w) {
        if (w.minimized) return;
        w.el.style.transformOrigin = dockOrigin(w);
        w.minimized = true;
        w.el.classList.add('is-min');
        if (S.focused === w) focusTop();
        else updateChrome();
    }

    function restoreWin(w) {
        w.el.style.transformOrigin = dockOrigin(w);
        w.minimized = false;
        w.el.classList.remove('is-min');
        focusWin(w);
    }

    function toggleZoom(w) {
        if (w.minimized) return;
        w.el.classList.add('is-anim');
        if (w.zoomed) {
            w.zoomed = false;
            w.rect = w.prev || w.rect;
            w.prev = null;
        } else {
            w.prev = { x: w.rect.x, y: w.rect.y, w: w.rect.w, h: w.rect.h };
            w.zoomed = true;
        }
        clampRect(w);
        applyRect(w);
        setTimeout(() => w.el.classList.remove('is-anim'), 320);
    }

    function destroyWin(w) {
        w.dead = true;
        w.timers.forEach(clearInterval);
        w.timers = [];
        try { if (w.api && w.api.destroy) w.api.destroy(); } catch (e) { /* ignore */ }
        S.wins.delete(w.id);
    }

    // force skips the app's "unsaved changes" check
    function closeWin(w, force) {
        if (!w || w.dead) return;
        if (!force && w.api && w.api.beforeClose && w.api.beforeClose() === false) return;
        const wasFocused = S.focused === w;
        destroyWin(w);
        w.el.classList.add('is-closing');
        setTimeout(() => { if (w.el.parentNode) w.el.parentNode.removeChild(w.el); }, 170);
        if (wasFocused) focusTop();
        else updateChrome();
    }

    // ---------------------------------------------------------------------------------------------
    // Menu bar, dock, desktop widget
    // ---------------------------------------------------------------------------------------------

    function closeMenu() {
        if (dom.menuEl && dom.menuEl.parentNode) dom.menuEl.parentNode.removeChild(dom.menuEl);
        dom.menuEl = null;
        if (S.menu && dom.mbItems && dom.mbItems[S.menu]) dom.mbItems[S.menu].classList.remove('is-open');
        S.menu = null;
    }

    function menuItems(id) {
        const w = S.focused;
        if (id === 'logo') {
            return [
                { label: T('pc_menu_about'), action: showAbout },
                '-',
                { label: T('pc_menu_close_pc'), action: () => closeLaptop(true) },
            ];
        }
        if (id === 'app') {
            if (!w) return visibleApps().map((a) => ({ label: T(a.key), action: () => openApp(a.id) }));
            return [
                { label: T('pc_menu_refresh'), action: () => { if (w.api && w.api.refresh) w.api.refresh(); } },
                '-',
                { label: T('pc_menu_minimize'), action: () => minimize(w) },
                { label: T('pc_menu_zoom'), action: () => toggleZoom(w) },
                { label: T('pc_menu_close_win'), keys: 'Esc', action: () => closeWin(w) },
            ];
        }
        if (id === 'apps') {
            return visibleApps().map((a) => ({ label: T(a.key), check: S.wins.has(a.id), action: () => openApp(a.id) }));
        }
        if (id === 'window') {
            const list = [];
            S.wins.forEach((x) => list.push({ label: T(x.app.key), check: S.focused === x, action: () => { if (x.minimized) restoreWin(x); else focusWin(x); } }));
            if (!list.length) return [{ label: T('pc_menu_no_windows'), disabled: true }];
            list.push('-');
            list.push({ label: T('pc_menu_minimize_all'), action: () => S.wins.forEach(minimize) });
            list.push({ label: T('pc_menu_close_all'), action: () => Array.from(S.wins.values()).forEach((x) => closeWin(x)) });
            return list;
        }
        return [];
    }

    function openMenu(id) {
        closeMenu();
        const btn = dom.mbItems[id];
        if (!btn) return;
        S.menu = id;
        btn.classList.add('is-open');
        const menu = el('div', { class: 'lp-menu', attrs: { role: 'menu' } });
        menuItems(id).forEach((it) => {
            if (it === '-') { menu.appendChild(el('div', { class: 'lp-menu-sep' })); return; }
            const row = el('button', { class: 'lp-menu-item', attrs: { type: 'button', role: 'menuitem' }, on: { click: () => { closeMenu(); if (it.action) it.action(); } } }, [
                el('span', { class: 'check' }, [it.check ? ic('check') : null]),
                el('span', { class: 'label', text: it.label }),
                it.keys ? el('span', { class: 'keys', text: it.keys }) : null,
            ]);
            if (it.disabled) row.disabled = true;
            menu.appendChild(row);
        });
        const sr = dom.screen.getBoundingClientRect();
        const br = btn.getBoundingClientRect();
        menu.style.left = Math.round(br.left - sr.left) + 'px';
        menu.style.top = Math.round(br.bottom - sr.top + 1) + 'px';
        dom.screen.appendChild(menu);
        dom.menuEl = menu;
    }

    function showAbout() {
        const d = S.data || {};
        showModal({
            icon: 'wrench',
            title: (d.workshop && d.workshop.label) || T('pc_about_title'),
            text: [d.name, d.gradeLabel].filter(Boolean).join(' · '),
            buttons: [{ label: T('pc_about_ok'), kind: 'primary', default: true }],
        });
    }

    function updateChrome() {
        if (!dom.appName) return;
        dom.appName.textContent = S.focused ? T(S.focused.app.key) : T('pc_desktop');
        if (dom.menuEl && S.menu) openMenu(S.menu);
        if (dom.dockItems) {
            Object.keys(dom.dockItems).forEach((id) => {
                dom.dockItems[id].classList.toggle('is-running', S.wins.has(id));
            });
        }
    }

    function buildMenubar() {
        dom.mbItems = {};
        const mk = (id, cls, kids) => {
            const b = el('button', { class: 'lp-mb-item ' + cls, attrs: { type: 'button', 'aria-haspopup': 'menu' } }, kids);
            b.addEventListener('click', () => { if (S.menu === id) closeMenu(); else openMenu(id); });
            b.addEventListener('mouseenter', () => { if (S.menu && S.menu !== id) openMenu(id); });
            dom.mbItems[id] = b;
            return b;
        };
        dom.appName = el('span', { text: T('pc_desktop') });
        const left = el('div', { class: 'lp-mb-group' }, [
            mk('logo', 'logo', [ic('wrench')]),
            mk('app', 'strong', [dom.appName]),
            mk('apps', '', [el('span', { text: T('pc_menu_apps') })]),
            mk('window', '', [el('span', { text: T('pc_menu_window') })]),
        ]);
        dom.clock = el('span', { text: '' });
        const ws = (S.data.workshop && S.data.workshop.label) || '';
        const right = el('div', { class: 'lp-mb-group' }, [
            el('span', { class: 'lp-mb-item static' }, [ic('wifi')]),
            el('span', { class: 'lp-mb-item static' }, [ic('battery-full')]),
            ws ? el('span', { class: 'lp-mb-item static lp-mb-ws', text: ws }) : null,
            el('span', { class: 'lp-mb-item static' }, [dom.clock]),
        ]);
        return el('div', { class: 'lp-menubar', attrs: { role: 'menubar' } }, [left, right]);
    }

    function tickClock() {
        const d = new Date();
        const hm = pad2(d.getHours()) + ':' + pad2(d.getMinutes());
        if (dom.clock) dom.clock.textContent = DAYS[d.getDay()] + ' ' + hm;
        if (dom.wTime) dom.wTime.textContent = hm;
        if (dom.wDate) {
            const dn = DAYS_LONG[d.getDay()];
            dom.wDate.textContent = dn.charAt(0).toUpperCase() + dn.slice(1) + ' ' + d.getDate() + '. ' + MONTHS[d.getMonth()];
        }
    }

    function buildDock() {
        dom.dockItems = {};
        const dock = el('div', { class: 'lp-dock', attrs: { role: 'toolbar' } });
        const apps = visibleApps();
        apps.forEach((a, i) => {
            if (a.boss && !apps[i - 1].boss) dock.appendChild(el('div', { class: 'lp-dock-sep' }));
            const item = el('button', { class: 'lp-dock-item', attrs: { type: 'button', 'aria-label': T(a.key) } }, [
                el('div', { class: 'lp-dock-icon', attrs: { style: '--c1:' + a.c[0] + ';--c2:' + a.c[1] } }, [ic(a.icon)]),
                el('span', { class: 'lp-dock-label', text: T(a.key) }),
                el('span', { class: 'lp-dock-dot' }),
            ]);
            item.addEventListener('click', () => openApp(a.id));
            dom.dockItems[a.id] = item;
            dock.appendChild(item);
        });

        // Magnification: scales come from the resting layout so they do not feed back on themselves.
        // The dock stays centred, so mouse x relative to the dock centre is stable.
        let raf = 0;
        let lastX = 0;
        const measure = () => {
            if (!dock.isConnected) return;
            const dr = dock.getBoundingClientRect();
            const cx = dr.left + dr.width / 2;
            S.dockMeta = Object.keys(dom.dockItems).map((id) => {
                const r = dom.dockItems[id].getBoundingClientRect();
                return { id, c: r.left + r.width / 2 - cx, w: r.width, cx };
            });
        };
        dom.measureDock = measure;
        const apply = () => {
            raf = 0;
            if (!S.dockMeta) return;
            const cx = dock.getBoundingClientRect().left + dock.getBoundingClientRect().width / 2;
            const m = lastX - cx;
            const base = S.dockMeta[0] ? S.dockMeta[0].w : 40;
            const sigma = base * 1.7;
            S.dockMeta.forEach((it) => {
                const dist = m - it.c;
                const s = 1 + 0.62 * Math.exp(-(dist * dist) / (2 * sigma * sigma));
                dom.dockItems[it.id].style.setProperty('--s', s.toFixed(3));
            });
        };
        dock.addEventListener('mouseenter', () => { dock.classList.add('is-live'); });
        dock.addEventListener('mousemove', (e) => {
            lastX = e.clientX;
            if (!raf) raf = requestAnimationFrame(apply);
        });
        dock.addEventListener('mouseleave', () => {
            if (raf) cancelAnimationFrame(raf);
            raf = 0;
            dock.classList.remove('is-live');
            Object.keys(dom.dockItems).forEach((id) => dom.dockItems[id].style.setProperty('--s', '1'));
        });
        return dock;
    }

    function buildWidget() {
        const d = S.data;
        dom.wTime = el('div', { class: 'time' });
        dom.wDate = el('div', { class: 'date' });
        const widget = el('div', { class: 'lp-widget' }, [
            dom.wTime,
            dom.wDate,
            el('div', { class: 'who' }, [d.name || '', el('span', { text: d.gradeLabel || '' })]),
        ]);
        const row = (icon, label, appId) => {
            const val = el('b', { text: '-' });
            const r = el('button', { class: 'lp-widget-row', attrs: { type: 'button' }, on: { click: () => openApp(appId) } }, [ic(icon), el('span', { text: label }), val]);
            widget.appendChild(r);
            return val;
        };
        const ordersVal = row('truck-fast', T('pc_widget_orders'), 'orders');
        const readyVal = row('box', T('pc_widget_ready'), 'orders');
        let balVal = null;
        if (S.isBoss) balVal = row('building-columns', T('pc_widget_balance'), 'eco');

        // Quick facts for the widget (best effort; failures leave the dash)
        rpc('order:list').then((r) => {
            if (!r.ok || !Array.isArray(r.data) || !S.open) return;
            ordersVal.textContent = String(r.data.filter((o) => o.status === 'ordered').length);
            readyVal.textContent = String(r.data.filter((o) => o.status === 'arrived').length);
        });
        if (balVal) {
            rpc('computer:economy').then((r) => {
                if (r.ok && r.data && S.open) balVal.textContent = money(r.data.balance);
            });
        }
        return widget;
    }

    // ---------------------------------------------------------------------------------------------
    // Open / close
    // ---------------------------------------------------------------------------------------------

    function teardown() {
        S.intervals.forEach(clearInterval);
        S.intervals = [];
        Array.from(S.wins.values()).forEach(destroyWin);
        S.wins.clear();
        S.cartSubs.clear();
        S.focused = null;
        S.menu = null;
        S.modals = [];
        S.cart = {};
        S.dockMeta = null;
        root.textContent = '';
        Object.keys(dom).forEach((k) => { delete dom[k]; });
    }

    function openLaptop(data) {
        if (S.open || !root.hidden) {
            S.open = false;
            teardown();
        }
        S.data = {
            name: String(data.name || ''),
            grade: num(data.grade),
            gradeLabel: String(data.gradeLabel || ''),
            isBoss: !!data.isBoss,
            workshop: data.workshop || {},
            shop: data.shop || {},
        };
        S.isBoss = S.data.isBoss;
        S.z = 10;

        dom.windows = el('div', { class: 'lp-windows' });
        dom.desk = el('div', { class: 'lp-desk' }, [buildWidget(), dom.windows]);
        dom.dock = buildDock();
        dom.screen = el('div', { class: 'lp-screen' }, [
            el('div', { class: 'lp-wallpaper' }),
            dom.desk,
            buildMenubar(),
            el('div', { class: 'lp-notch' }),
            dom.dock,
        ]);
        dom.device = el('div', { class: 'lp-device' }, [
            el('div', { class: 'lp-lid' }, [dom.screen]),
            el('div', { class: 'lp-base' }),
        ]);
        root.textContent = '';
        root.appendChild(dom.device);
        root.hidden = false;
        void root.offsetWidth;
        root.classList.add('is-open');
        S.open = true;

        tickClock();
        S.intervals.push(setInterval(tickClock, 10000));
        setTimeout(() => { if (dom.measureDock) dom.measureDock(); }, 650);
        updateChrome();
    }

    // fromUser: tell Lua (Esc, menu); Lua-initiated closes must not post back
    function closeLaptop(fromUser) {
        if (!S.open) return;
        S.open = false;
        if (fromUser) App.post('laptop:close', {});
        closeMenu();
        if (dom.device) dom.device.classList.add('is-closing');
        root.classList.remove('is-open');
        setTimeout(() => {
            if (!S.open) {
                teardown();
                root.hidden = true;
            }
        }, 240);
    }

    // Esc: close the menu, then a sheet or dialog, then the focused window, then the computer
    document.addEventListener('keydown', (e) => {
        if (!S.open) return;
        if (e.key !== 'Escape') return;
        e.preventDefault();
        e.stopPropagation();
        const a = document.activeElement;
        if (a && a.tagName === 'INPUT' && a.value && a.closest('.lp-search')) {
            a.value = '';
            a.dispatchEvent(new Event('input'));
            return;
        }
        if (S.menu) { closeMenu(); return; }
        if (S.modals.length) { S.modals[S.modals.length - 1].cancel(); return; }
        const w = S.focused;
        if (w && !w.dead) {
            if (w.sheets.length) { w.sheets[w.sheets.length - 1].cancel(); return; }
            closeWin(w);
            return;
        }
        closeLaptop(true);
    }, true);

    document.addEventListener('pointerdown', (e) => {
        if (S.menu && !e.target.closest('.lp-menu, .lp-mb-item')) closeMenu();
    }, true);

    window.addEventListener('resize', () => {
        if (!S.open) return;
        S.wins.forEach((w) => { clampRect(w); applyRect(w); });
        setTimeout(() => { if (dom.measureDock) dom.measureDock(); }, 50);
    });

    // ---------------------------------------------------------------------------------------------
    // App: Lager (stock)
    // ---------------------------------------------------------------------------------------------

    const LOW = 2;

    function mountStock(win) {
        let rows = [];
        let filter = 'all';
        let q = '';
        let loadedOnce = false;
        let failed = null;

        const side = el('aside', { class: 'lp-side' });
        const title = el('div', { class: 'lp-h1' });
        const listBox = el('div', { class: 'lp-scroll' });
        const status = el('div', { class: 'lp-status' });
        const main = el('div', { class: 'lp-main' }, [title, listBox, status]);
        win.body.append(side, main);

        const search = searchBox((v) => { q = v.trim().toLowerCase(); renderList(); });
        const refreshBtn = el('button', { class: 'lp-btn icon', attrs: { type: 'button', title: T('pc_refresh') }, on: { click: () => load() } }, [ic('arrows-rotate')]);
        win.tools.append(search.node, refreshBtn);

        const inStock = (r) => r.count > 0;
        const isLow = (r) => r.count > 0 && r.count <= LOW;

        function renderSide() {
            side.textContent = '';
            const present = {};
            rows.forEach((r) => { present[catOf(r.name)] = (present[catOf(r.name)] || 0) + 1; });
            side.append(
                sideHead(T('pc_side_stock')),
                sideItem('boxes-stacked', T('pc_filter_all'), rows.length, filter === 'all', () => setFilter('all')),
                sideItem('circle-check', T('pc_filter_in'), rows.filter(inStock).length, filter === 'in', () => setFilter('in')),
                sideItem('triangle-exclamation', T('pc_filter_low'), rows.filter(isLow).length, filter === 'low', () => setFilter('low')),
                sideItem('circle-xmark', T('pc_filter_out'), rows.filter((r) => !inStock(r)).length, filter === 'out', () => setFilter('out')),
                sideHead(T('pc_side_categories')),
            );
            CATS.forEach((c) => {
                if (!present[c.id]) return;
                side.appendChild(sideItem(c.icon, T('pc_cat_' + c.id), present[c.id], filter === 'cat:' + c.id, () => setFilter('cat:' + c.id)));
            });
        }

        function setFilter(f) {
            filter = f;
            renderSide();
            renderList();
        }

        function filterLabel() {
            if (filter === 'all') return T('pc_filter_all');
            if (filter === 'in') return T('pc_filter_in');
            if (filter === 'low') return T('pc_filter_low');
            if (filter === 'out') return T('pc_filter_out');
            return T('pc_cat_' + filter.slice(4));
        }

        function matches(r) {
            if (filter === 'in' && !inStock(r)) return false;
            if (filter === 'low' && !isLow(r)) return false;
            if (filter === 'out' && inStock(r)) return false;
            if (filter.indexOf('cat:') === 0 && catOf(r.name) !== filter.slice(4)) return false;
            if (q && r.label.toLowerCase().indexOf(q) < 0) return false;
            return true;
        }

        function renderList() {
            if (failed) {
                title.textContent = '';
                listBox.textContent = '';
                listBox.appendChild(errorState(failed, load));
                status.textContent = '';
                return;
            }
            const list = rows.filter(matches);
            title.textContent = '';
            title.append(filterLabel());
            listBox.textContent = '';
            if (!list.length) {
                listBox.appendChild(emptyState('box-open', T('pc_stock_empty')));
            } else {
                const table = el('div', { class: 'lp-table', attrs: { style: '--cols:minmax(0,2.3fr) minmax(0,1.1fr) 5.5em minmax(0,1.5fr) 6.5em' } });
                table.appendChild(el('div', { class: 'lp-thead' }, [
                    el('span', { text: T('pc_col_item') }),
                    el('span', { text: T('pc_col_category') }),
                    el('span', { class: 'lp-right', text: T('pc_col_price') }),
                    el('span', { text: T('pc_col_qty') }),
                    el('span'),
                ]));
                list.forEach((r) => {
                    const cls = r.count <= 0 ? 'out' : (isLow(r) ? 'low' : '');
                    const pill = r.count <= 0
                        ? el('span', { class: 'lp-pill err', text: T('pc_out_of_stock') })
                        : (isLow(r) ? el('span', { class: 'lp-pill warn', text: r.count + ' · ' + T('pc_low_stock') })
                            : el('span', { class: 'lp-pill ok', text: T('pc_in_stock', r.count) }));
                    const bar = el('div', { class: 'lp-stockbar ' + cls }, [el('i', { attrs: { style: 'width:' + Math.round(Math.min(1, r.count / 12) * 100) + '%' } })]);
                    const orderBtn = r.price !== null
                        ? el('button', { class: 'lp-btn sm ' + (r.count <= LOW ? 'primary' : ''), attrs: { type: 'button' }, on: { click: () => orderItem(r.name) } }, [ic('cart-plus'), T('pc_order_btn')])
                        : el('span');
                    table.appendChild(el('div', { class: 'lp-trow' }, [
                        el('div', { class: 'name' }, [itemTile(r.name), el('span', { text: r.label })]),
                        el('span', { class: 'lp-muted', text: T('pc_cat_' + catOf(r.name)) }),
                        el('span', { class: 'lp-right', text: r.price !== null ? money(r.price) : '' }),
                        el('div', { class: 'qty' }, [pill, bar]),
                        el('div', { class: 'lp-right' }, [orderBtn]),
                    ]));
                });
                listBox.appendChild(table);
            }
            const total = rows.reduce((s, r) => s + r.count, 0);
            status.textContent = '';
            status.append(el('span', { text: T('pc_stock_summary', rows.length, total) }));
            if (S.data.workshop && S.data.workshop.label) status.append(el('span', { text: S.data.workshop.label }));
        }

        function orderItem(name) {
            cartAdd(name, 1);
            openApp('order');
        }

        async function load() {
            if (!loadedOnce) {
                listBox.textContent = '';
                listBox.appendChild(loader());
            }
            const [st, cat] = await Promise.all([rpc('stock:get'), rpc('computer:catalog')]);
            if (!win.alive()) return;
            if (!st.ok) {
                failed = st.error;
                renderList();
                return;
            }
            failed = null;
            loadedOnce = true;
            const map = new Map();
            if (cat.ok && Array.isArray(cat.data)) {
                cat.data.forEach((c) => map.set(c.item, { name: c.item, label: String(c.label || c.item), price: num(c.price), count: 0 }));
            }
            const items = (st.data && Array.isArray(st.data.items)) ? st.data.items : [];
            items.forEach((i) => {
                const r = map.get(i.name);
                if (r) { r.count = num(i.count); } else { map.set(i.name, { name: i.name, label: String(i.label || i.name), price: null, count: num(i.count) }); }
            });
            rows = Array.from(map.values()).sort((a, b) => {
                const ca = CATS.findIndex((c) => c.id === catOf(a.name));
                const cb = CATS.findIndex((c) => c.id === catOf(b.name));
                if (ca !== cb) return ca - cb;
                return a.name < b.name ? -1 : (a.name > b.name ? 1 : 0);
            });
            renderSide();
            renderList();
        }

        renderSide();
        load();
        return { refresh: load };
    }

    // ---------------------------------------------------------------------------------------------
    // App: Bestil (order parts)
    // ---------------------------------------------------------------------------------------------

    function mountOrder(win) {
        let catalog = [];
        let cat = 'all';
        let q = '';
        let failed = null;
        let loadedOnce = false;
        let busy = false;
        let msg = null; // { kind, text }

        const side = el('aside', { class: 'lp-side' });
        const grid = el('div', { class: 'lp-scroll' });
        const main = el('div', { class: 'lp-main' }, [grid]);
        const cartPane = el('aside', { class: 'lp-cart' });
        win.body.append(side, main, cartPane);

        const search = searchBox((v) => { q = v.trim().toLowerCase(); renderGrid(); });
        const refreshBtn = el('button', { class: 'lp-btn icon', attrs: { type: 'button', title: T('pc_refresh') }, on: { click: () => load() } }, [ic('arrows-rotate')]);
        win.tools.append(search.node, refreshBtn);

        const byItem = () => {
            const m = {};
            catalog.forEach((c) => { m[c.item] = c; });
            return m;
        };

        function renderSide() {
            side.textContent = '';
            const present = {};
            catalog.forEach((c) => { present[catOf(c.item)] = (present[catOf(c.item)] || 0) + 1; });
            side.append(
                sideHead(T('pc_side_categories')),
                sideItem('boxes-stacked', T('pc_filter_all'), catalog.length, cat === 'all', () => { cat = 'all'; renderSide(); renderGrid(); }),
            );
            CATS.forEach((c) => {
                if (!present[c.id]) return;
                side.appendChild(sideItem(c.icon, T('pc_cat_' + c.id), present[c.id], cat === c.id, () => { cat = c.id; renderSide(); renderGrid(); }));
            });
        }

        function renderGrid() {
            grid.textContent = '';
            if (failed) { grid.appendChild(errorState(failed, load)); return; }
            const lim = limits();
            const list = catalog.filter((c) => (cat === 'all' || catOf(c.item) === cat) && (!q || c.label.toLowerCase().indexOf(q) >= 0));
            if (!list.length) { grid.appendChild(emptyState('box-open', T('pc_catalog_empty'))); return; }
            const wrap = el('div', { class: 'lp-grid' });
            list.forEach((c) => {
                const qty = S.cart[c.item] || 0;
                const stock = num(c.stock);
                const badge = stock <= 0
                    ? el('span', { class: 'lp-pill err', text: T('pc_out_of_stock') })
                    : (stock <= LOW ? el('span', { class: 'lp-pill warn', text: T('pc_in_stock', stock) }) : el('span', { class: 'lp-pill ok', text: T('pc_in_stock', stock) }));
                let control;
                if (qty > 0) {
                    control = el('div', { class: 'lp-step' }, [
                        el('button', { attrs: { type: 'button', 'aria-label': '-' }, on: { click: () => cartAdd(c.item, -1) } }, [ic('minus')]),
                        el('b', { text: qty }),
                        el('button', { attrs: { type: 'button', 'aria-label': '+' }, on: { click: () => flash(cartAdd(c.item, 1)) } }, [ic('plus')]),
                    ]);
                    if (qty >= lim.perLine) control.lastChild.disabled = true;
                } else {
                    control = el('button', { class: 'lp-btn sm primary', attrs: { type: 'button' }, on: { click: () => flash(cartAdd(c.item, 1)) } }, [ic('cart-plus'), T('pc_add_cart')]);
                }
                wrap.appendChild(el('div', { class: 'lp-card' + (qty > 0 ? ' in-cart' : '') }, [
                    el('div', { class: 'top' }, [itemTile(c.item, '3em'), badge]),
                    el('div', { class: 'nm', text: c.label }),
                    el('div', { class: 'price', text: money(c.price) }),
                    el('div', { class: 'foot' }, [control]),
                ]));
            });
            grid.appendChild(wrap);
        }

        function flash(err) {
            if (err) { msg = { kind: 'err', text: err }; renderCart(); }
        }

        function renderCart() {
            const m = byItem();
            const lines = Object.keys(S.cart);
            const lim = limits();
            let total = 0;
            lines.forEach((k) => { total += (m[k] ? num(m[k].price) : 0) * S.cart[k]; });
            cartPane.textContent = '';
            const head = el('div', { class: 'lp-cart-head' }, [
                el('span', { text: T('pc_cart') }),
                lines.length ? el('button', { class: 'lp-btn sm', text: T('pc_cart_clear'), attrs: { type: 'button' }, on: { click: () => { S.cart = {}; msg = null; notifyCart(); } } }) : null,
            ]);
            const box = el('div', { class: 'lp-cart-lines' });
            if (!lines.length) {
                box.appendChild(el('div', { class: 'lp-empty' }, [ic('cart-shopping'), el('p', { text: T('pc_cart_empty') })]));
            }
            lines.forEach((k) => {
                const c = m[k];
                const label = c ? c.label : k;
                box.appendChild(el('div', { class: 'lp-cart-line' }, [
                    itemTile(k, '2.2em'),
                    el('div', { class: 'nm', text: label }),
                    el('button', { class: 'lp-btn sm icon', attrs: { type: 'button', title: T('pc_cart_remove') }, on: { click: () => cartSet(k, 0) } }, [ic('xmark')]),
                    el('div', { class: 'sub' }, [
                        el('div', { class: 'lp-step' }, [
                            el('button', { attrs: { type: 'button', 'aria-label': '-' }, on: { click: () => cartAdd(k, -1) } }, [ic('minus')]),
                            el('b', { text: S.cart[k] }),
                            (() => {
                                const b = el('button', { attrs: { type: 'button', 'aria-label': '+' }, on: { click: () => flash(cartAdd(k, 1)) } }, [ic('plus')]);
                                if (S.cart[k] >= lim.perLine) b.disabled = true;
                                return b;
                            })(),
                        ]),
                        el('span', { class: 'lp-muted', text: money((c ? num(c.price) : 0) * S.cart[k]) }),
                    ]),
                ]));
            });
            const foot = el('div', { class: 'lp-cart-foot' });
            if (msg) foot.appendChild(banner(msg.kind, msg.text, () => { msg = null; renderCart(); }));
            foot.append(
                el('div', { class: 'lp-cart-note' }, [ic('building-columns'), el('span', { text: T('pc_society_pays') })]),
                el('div', { class: 'lp-cart-note' }, [ic('clock'), el('span', { text: T('pc_delivery_eta', lim.minutes) })]),
                el('div', { class: 'total' }, [el('span', { class: 'lp-muted', text: T('pc_total') }), el('b', { text: money(total) })]),
                (() => {
                    const b = el('button', { class: 'lp-btn lg primary block', attrs: { type: 'button' }, on: { click: submit } },
                        [ic(busy ? 'spinner' : 'truck-fast', busy ? 'fa-spin' : ''), busy ? T('pc_ordering') : T('pc_place_order')]);
                    b.disabled = busy || !lines.length;
                    return b;
                })(),
            );
            cartPane.append(head, box, foot);
        }

        async function submit() {
            if (busy) return;
            const lines = Object.keys(S.cart).map((item) => ({ item, count: S.cart[item] }));
            if (!lines.length) return;
            busy = true;
            msg = null;
            renderCart();
            const r = await rpc('order:place', [lines]);
            busy = false;
            if (!win.alive()) return;
            if (!r.ok) {
                msg = { kind: 'err', text: r.error };
                renderCart();
                return;
            }
            const d = r.data || {};
            const mins = Math.max(1, Math.round(num(d.eta) > 0 ? num(d.eta) / 60 : limits().minutes));
            msg = { kind: 'ok', text: T('pc_order_placed', d.id !== undefined ? d.id : '', money(d.total), mins) };
            S.cart = {};
            notifyCart();
            refreshApps(['orders', 'stock']);
            load(true);
        }

        async function load(quiet) {
            if (!loadedOnce && !quiet) {
                grid.textContent = '';
                grid.appendChild(loader());
            }
            const r = await rpc('computer:catalog');
            if (!win.alive()) return;
            if (!r.ok) {
                // A failed quiet refresh keeps the catalog that is already shown
                if (quiet && loadedOnce) return;
                failed = r.error;
            } else {
                failed = null;
                loadedOnce = true;
                catalog = (Array.isArray(r.data) ? r.data : []).map((c) => ({ item: String(c.item), label: String(c.label || c.item), price: num(c.price), stock: num(c.stock) }));
                catalog.sort((a, b) => {
                    const ca = CATS.findIndex((x) => x.id === catOf(a.item));
                    const cb = CATS.findIndex((x) => x.id === catOf(b.item));
                    return ca !== cb ? ca - cb : (a.item < b.item ? -1 : 1);
                });
            }
            renderSide();
            renderGrid();
            renderCart();
        }

        const onCart = () => { renderGrid(); renderCart(); };
        S.cartSubs.add(onCart);

        renderSide();
        renderCart();
        load();
        return { refresh: () => load(true), destroy: () => S.cartSubs.delete(onCart) };
    }

    // ---------------------------------------------------------------------------------------------
    // App: Ordrer (order status)
    // ---------------------------------------------------------------------------------------------

    function mountOrders(win) {
        let orders = [];
        let fetchedAt = Date.now();
        let filter = 'all';
        let failed = null;
        let loadedOnce = false;
        let lastPoll = 0;
        let live = [];

        const box = el('div', { class: 'lp-scroll' });
        const main = el('div', { class: 'lp-main' }, [box]);
        win.body.append(main);

        const seg = segmented([
            { id: 'all', label: T('pc_orders_all') },
            { id: 'ordered', label: T('pc_st_ordered') },
            { id: 'arrived', label: T('pc_st_arrived') },
            { id: 'collected', label: T('pc_st_collected') },
        ], filter, (v) => { filter = v; render(); });
        const refreshBtn = el('button', { class: 'lp-btn icon', attrs: { type: 'button', title: T('pc_refresh') }, on: { click: () => load() } }, [ic('arrows-rotate')]);
        win.tools.append(seg.node, refreshBtn);

        const STATUS = {
            ordered: { icon: 'truck-fast', c: ['#0a84ff', '#0a5bc4'], pill: 'info' },
            arrived: { icon: 'box', c: ['#32d74b', '#1f9d40'], pill: 'ok' },
            collected: { icon: 'circle-check', c: ['#98989d', '#636366'], pill: '' },
        };

        function remaining(o) {
            return num(o.eta) - (Date.now() - fetchedAt) / 1000;
        }

        function render() {
            live = [];
            box.textContent = '';
            if (failed) { box.appendChild(errorState(failed, load)); return; }
            const list = orders.filter((o) => filter === 'all' || o.status === filter);
            if (!list.length) { box.appendChild(emptyState('truck-ramp-box', T('pc_orders_empty'))); return; }
            const total = limits().minutes * 60;
            list.forEach((o) => {
                const st = STATUS[o.status] || STATUS.collected;
                const items = el('div', { class: 'items' });
                (Array.isArray(o.items) ? o.items : []).forEach((i) => {
                    items.appendChild(el('span', { class: 'lp-chip', text: num(i.count) + '× ' + (i.label || i.item) }));
                });
                const meta = [o.ordered_by ? T('pc_order_by', o.ordered_by) : '', fmtDate(o.created_at)].filter(Boolean).join(' · ');
                const card = el('div', { class: 'lp-order' }, [
                    el('div', { class: 'lp-tile ico', attrs: { style: '--c1:' + st.c[0] + ';--c2:' + st.c[1] } }, [ic(st.icon)]),
                    el('div', { class: 'mid' }, [el('div', { class: 'ttl', text: T('pc_order_no', o.id) }), el('div', { class: 'meta', text: meta })]),
                    el('div', { class: 'side' }, [
                        el('b', { text: money(o.total) }),
                        el('span', { class: 'lp-pill ' + st.pill, text: T('pc_st_' + (STATUS[o.status] ? o.status : 'collected')) }),
                    ]),
                    items,
                ]);
                if (o.status === 'ordered') {
                    const fill = el('i');
                    const eta = el('span', { class: 'eta' });
                    card.appendChild(el('div', { class: 'prog' }, [el('div', { class: 'bar' }, [fill]), eta]));
                    live.push({ o, fill, eta, total: Math.max(total, num(o.eta)) });
                } else if (o.status === 'arrived') {
                    card.appendChild(el('div', { class: 'ready' }, [ic('hand-point-up'), el('span', { text: T('pc_order_ready') })]));
                }
                box.appendChild(card);
            });
            tick();
        }

        function tick() {
            let overdue = false;
            live.forEach((l) => {
                const rem = remaining(l.o);
                if (rem > 0) {
                    l.eta.textContent = T('pc_order_arrives', fmtClock(rem));
                    l.fill.style.width = Math.max(2, Math.min(100, (1 - rem / l.total) * 100)) + '%';
                } else {
                    l.eta.textContent = T('pc_order_arriving');
                    l.fill.style.width = '100%';
                    overdue = true;
                }
            });
            // The server moves due orders to "arrived" every 15 s, so poll while one is overdue
            if (overdue && Date.now() - lastPoll > 6000) load(true);
        }

        async function load(quiet) {
            if (!loadedOnce && !quiet) { box.textContent = ''; box.appendChild(loader()); }
            lastPoll = Date.now();
            const r = await rpc('order:list');
            if (!win.alive()) return;
            if (!r.ok) {
                failed = r.error;
            } else {
                failed = null;
                loadedOnce = true;
                orders = Array.isArray(r.data) ? r.data : [];
                fetchedAt = Date.now();
            }
            render();
        }

        win.timer(tick, 1000);
        win.timer(() => load(true), 30000);
        load();
        return { refresh: () => load(true) };
    }

    // ---------------------------------------------------------------------------------------------
    // App: Personale (staff, chef only)
    // ---------------------------------------------------------------------------------------------

    function mountStaff(win) {
        let staff = [];
        let grades = [];
        let nearby = [];
        let view = 'all'; // all | online | offline | hire
        let q = '';
        let failed = null;
        let loadedOnce = false;
        let msg = null;
        const me = S.data;

        const side = el('aside', { class: 'lp-side' });
        const alertBox = el('div');
        const listBox = el('div', { class: 'lp-scroll' });
        const main = el('div', { class: 'lp-main' }, [alertBox, listBox]);
        win.body.append(side, main);

        const search = searchBox((v) => { q = v.trim().toLowerCase(); renderList(); });
        const refreshBtn = el('button', { class: 'lp-btn icon', attrs: { type: 'button', title: T('pc_refresh') }, on: { click: () => load() } }, [ic('arrows-rotate')]);
        win.tools.append(search.node, refreshBtn);

        function setMsg(kind, text) {
            msg = text ? { kind, text } : null;
            alertBox.textContent = '';
            if (msg) alertBox.appendChild(banner(msg.kind, msg.text, () => setMsg(null)));
        }

        function renderSide() {
            side.textContent = '';
            side.append(
                sideHead(T('pc_staff_group')),
                sideItem('users', T('pc_staff_all'), staff.length, view === 'all', () => setView('all')),
                sideItem('circle', T('pc_staff_online'), staff.filter((s) => s.online).length, view === 'online', () => setView('online')),
                sideItem('moon', T('pc_staff_offline'), staff.filter((s) => !s.online).length, view === 'offline', () => setView('offline')),
                sideHead(T('pc_staff_hire')),
                sideItem('user-plus', T('pc_staff_hire'), nearby.length ? nearby.length : null, view === 'hire', () => setView('hire')),
            );
        }

        function setView(v) {
            view = v;
            setMsg(null);
            renderSide();
            if (v === 'hire') loadNearby(); else renderList();
        }

        function gradeLabel(g) {
            const f = grades.find((x) => num(x.grade) === num(g));
            return f ? String(f.label) : String(g);
        }

        function renderList() {
            listBox.textContent = '';
            if (failed) { listBox.appendChild(errorState(failed, load)); return; }
            if (view === 'hire') { renderHire(); return; }
            const list = staff.filter((s) => (view === 'all' || (view === 'online' ? s.online : !s.online)) && (!q || String(s.name).toLowerCase().indexOf(q) >= 0));
            if (!list.length) { listBox.appendChild(emptyState('users', T('pc_staff_empty'))); return; }
            list.sort((a, b) => (b.grade - a.grade) || String(a.name).localeCompare(String(b.name)));
            const selectable = grades.filter((g) => num(g.grade) < me.grade);
            list.forEach((s) => {
                const locked = s.grade >= me.grade;
                const isMe = s.name === me.name && s.grade === me.grade;
                const who = el('div', { class: 'who' }, [
                    avatar(s.name, s.online),
                    el('div', { attrs: { style: 'min-width:0' } }, [
                        el('b', { text: s.name }),
                        isMe ? el('small', { text: T('pc_staff_you') }) : null,
                    ]),
                ]);
                let rank;
                if (locked) {
                    rank = el('span', { class: 'lp-pill', attrs: { title: T('pc_staff_locked') } }, [ic('lock'), s.gradeLabel || gradeLabel(s.grade)]);
                } else {
                    rank = el('select', { class: 'lp-select', attrs: { 'aria-label': T('pc_staff_grade') } });
                    selectable.forEach((g) => {
                        const o = el('option', { text: g.label, attrs: { value: String(g.grade) } });
                        if (num(g.grade) === s.grade) o.selected = true;
                        rank.appendChild(o);
                    });
                    rank.addEventListener('change', async () => {
                        rank.disabled = true;
                        const r = await rpc('computer:setGrade', [s.identifier, parseInt(rank.value, 10)]);
                        if (!win.alive()) return;
                        setMsg(r.ok ? 'ok' : 'err', r.ok ? T('pc_grade_set') : r.error);
                        load(true);
                    });
                }
                const acts = el('div', { class: 'acts' }, [
                    locked ? null : el('button', { class: 'lp-btn sm ghost-danger', attrs: { type: 'button' }, on: { click: () => confirmFire(s) } }, [ic('user-minus'), T('pc_staff_fire')]),
                ]);
                listBox.appendChild(el('div', { class: 'lp-person' }, [
                    who,
                    el('div', {}, [rank]),
                    el('div', { class: 'state ' + (s.online ? 'on' : 'off') }, [ic('circle'), el('span', { text: s.online ? T('pc_staff_online') : T('pc_staff_offline') })]),
                    acts,
                ]));
            });
        }

        function renderHire() {
            listBox.appendChild(el('div', { class: 'lp-pad lp-muted', text: T('pc_nearby_hint') }));
            const list = nearby.filter((n) => !q || String(n.name).toLowerCase().indexOf(q) >= 0);
            if (!list.length) { listBox.appendChild(emptyState('user-plus', T('pc_nearby_empty'))); return; }
            list.forEach((n) => {
                const btn = el('button', { class: 'lp-btn sm primary', attrs: { type: 'button' } }, [ic('user-plus'), T('pc_hire_btn')]);
                btn.addEventListener('click', async () => {
                    btn.disabled = true;
                    // The player has to accept the offer on their own screen first (up to 30 s)
                    setMsg('ok', T('pc_hire_waiting', n.name));
                    const r = await rpc('computer:hire', [n.serverId]);
                    if (!win.alive()) return;
                    setMsg(r.ok ? 'ok' : 'err', r.ok ? T('pc_hired', n.name) : r.error);
                    await load(true);
                    loadNearby(true);
                });
                listBox.appendChild(el('div', { class: 'lp-person', attrs: { style: 'grid-template-columns:minmax(0,1fr) auto' } }, [
                    el('div', { class: 'who' }, [avatar(n.name), el('div', { attrs: { style: 'min-width:0' } }, [el('b', { text: n.name }), el('small', { text: T('pc_server_id', n.serverId) })])]),
                    el('div', { class: 'acts' }, [btn]),
                ]));
            });
        }

        function confirmFire(s) {
            winSheet(win, {
                icon: 'user-minus',
                danger: true,
                title: T('pc_fire_title', s.name),
                text: T('pc_fire_text', s.name),
                buttons: [
                    { label: T('pc_cancel') },
                    {
                        label: T('pc_staff_fire'),
                        kind: 'danger',
                        action: async () => {
                            const r = await rpc('computer:fire', [s.identifier]);
                            if (!win.alive()) return { ok: true };
                            if (!r.ok) return { ok: false, error: r.error };
                            setMsg('ok', T('pc_fired', s.name));
                            load(true);
                            return { ok: true };
                        },
                    },
                ],
            });
        }

        async function loadNearby(quiet) {
            if (!quiet) { listBox.textContent = ''; listBox.appendChild(loader()); }
            const r = await rpc('computer:nearby');
            if (!win.alive()) return;
            if (!r.ok) { failed = r.error; renderList(); return; }
            failed = null;
            nearby = (Array.isArray(r.data) ? r.data : []).map((n) => ({ serverId: n.serverId, name: String(n.name || '?') }));
            renderSide();
            if (view === 'hire') renderList();
        }

        async function load(quiet) {
            if (!loadedOnce && !quiet) { listBox.textContent = ''; listBox.appendChild(loader()); }
            const r = await rpc('computer:staff');
            if (!win.alive()) return;
            if (!r.ok) {
                failed = r.error;
            } else {
                failed = null;
                loadedOnce = true;
                const d = r.data;
                const rawStaff = Array.isArray(d) ? d : (d && Array.isArray(d.staff) ? d.staff : []);
                grades = (d && Array.isArray(d.grades)) ? d.grades.map((g) => ({ grade: num(g.grade), label: String(g.label || g.grade) })) : [];
                staff = rawStaff.map((s) => ({
                    identifier: s.identifier,
                    name: String(s.name || '?'),
                    grade: num(s.grade),
                    gradeLabel: s.gradeLabel ? String(s.gradeLabel) : '',
                    online: !!s.online,
                    serverId: s.serverId,
                }));
                if (!grades.length) {
                    const seen = {};
                    staff.forEach((s) => { if (!seen[s.grade]) { seen[s.grade] = true; grades.push({ grade: s.grade, label: s.gradeLabel || String(s.grade) }); } });
                    grades.sort((a, b) => a.grade - b.grade);
                }
            }
            renderSide();
            renderList();
        }

        renderSide();
        load();
        return { refresh: () => { load(true); if (view === 'hire') loadNearby(true); } };
    }

    // ---------------------------------------------------------------------------------------------
    // App: Okonomi (finances, chef only)
    // ---------------------------------------------------------------------------------------------

    const HIST = {
        invoice: { icon: 'file-invoice-dollar', c: ['#32d74b', '#1f9d40'], sign: 1 },
        order: { icon: 'box', c: ['#ff9f0a', '#e8590c'], sign: -1 },
        deposit: { icon: 'arrow-down', c: ['#0a84ff', '#0a5bc4'], sign: 1 },
        withdraw: { icon: 'arrow-up', c: ['#bf5af2', '#8944ab'], sign: -1 },
    };

    function mountEco(win) {
        let balance = 0;
        let history = [];
        let filter = 'all';
        let failed = null;
        let loadedOnce = false;
        let busy = false;
        let xferMsg = null;

        const scroll = el('div', { class: 'lp-scroll' });
        const main = el('div', { class: 'lp-main' }, [scroll]);
        win.body.append(main);

        const refreshBtn = el('button', { class: 'lp-btn icon', attrs: { type: 'button', title: T('pc_refresh') }, on: { click: () => load() } }, [ic('arrows-rotate')]);
        win.tools.append(refreshBtn);

        const amountInput = el('input', { class: 'lp-input', attrs: { type: 'text', inputmode: 'numeric', maxlength: '9', placeholder: '0', autocomplete: 'off', 'aria-label': T('pc_eco_amount') } });
        amountInput.addEventListener('input', () => {
            amountInput.value = amountInput.value.replace(/[^\d]/g, '');
            amountInput.classList.remove('is-bad');
        });
        amountInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') e.stopPropagation(); });

        let histBox = null;

        function typeKey(t) { return HIST[t] ? t : 'order'; }

        function buildTop() {
            const lim = limits();
            let income = 0;
            let expense = 0;
            history.forEach((h) => { const a = num(h.amount); if (HIST[typeKey(h.type)].sign > 0) income += a; else expense += a; });

            const hero = el('div', { class: 'lp-balance' }, [
                el('div', { class: 'lbl' }, [ic('building-columns'), T('pc_eco_title')]),
                el('div', { class: 'amt', text: money(balance) }),
                el('div', { class: 'sums' }, [
                    el('span', { text: T('pc_eco_income') + ' ' + money(income) }),
                    el('span', { text: T('pc_eco_expense') + ' ' + money(expense) }),
                ]),
            ]);

            const xfer = el('div', { class: 'lp-transfer' });
            xfer.appendChild(el('h3', { text: T('pc_eco_transfer') }));
            const field = el('div', { class: 'lp-money-input' }, [el('span', { text: '$' }), amountInput]);
            xfer.appendChild(field);
            const chips = el('div', { class: 'chips' });
            [1000, 5000, 10000, 50000].forEach((v) => {
                chips.appendChild(el('button', { text: money(v), attrs: { type: 'button' }, on: { click: () => { amountInput.value = String(v); amountInput.classList.remove('is-bad'); amountInput.focus(); } } }));
            });
            xfer.appendChild(chips);
            if (xferMsg) xfer.appendChild(banner(xferMsg.kind, xferMsg.text));
            const dep = el('button', { class: 'lp-btn primary', attrs: { type: 'button' }, on: { click: () => transfer('computer:deposit') } }, [ic('arrow-down'), T('pc_eco_deposit')]);
            const wd = el('button', { class: 'lp-btn', attrs: { type: 'button' }, on: { click: () => transfer('computer:withdraw') } }, [ic('arrow-up'), T('pc_eco_withdraw')]);
            dep.disabled = busy;
            wd.disabled = busy;
            xfer.appendChild(el('div', { class: 'btns' }, [dep, wd]));
            void lim;
            return el('div', { class: 'lp-hero' }, [hero, xfer]);
        }

        function buildHistoryList() {
            histBox.textContent = '';
            const list = history.filter((h) => filter === 'all'
                || (filter === 'transfer' ? (h.type === 'deposit' || h.type === 'withdraw') : h.type === filter));
            if (!list.length) { histBox.appendChild(emptyState('receipt', T('pc_eco_empty'))); return; }
            const table = el('div', { class: 'lp-table', attrs: { style: '--cols:minmax(0,2.2fr) minmax(0,1.2fr) 8.5em 7em' } });
            list.forEach((h) => {
                const tk = typeKey(h.type);
                const cfg = HIST[tk];
                const amt = num(h.amount);
                table.appendChild(el('div', { class: 'lp-trow' }, [
                    el('div', { class: 'name' }, [
                        el('div', { class: 'lp-tile lp-hist-ico', attrs: { style: '--c1:' + cfg.c[0] + ';--c2:' + cfg.c[1] } }, [ic(cfg.icon)]),
                        el('span', { text: [T('pc_eco_t_' + tk), h.detail].filter(Boolean).join(' · ') }),
                    ]),
                    el('span', { class: 'lp-muted', text: h.by ? T('pc_eco_by', h.by) : '' }),
                    el('span', { class: 'lp-muted', text: fmtDate(h.created_at) }),
                    el('b', { class: 'lp-right ' + (cfg.sign > 0 ? 'lp-pos' : 'lp-neg'), text: (cfg.sign > 0 ? '+' : '-') + money(amt) }),
                ]));
            });
            histBox.appendChild(table);
        }

        function render() {
            scroll.textContent = '';
            if (failed) { scroll.appendChild(errorState(failed, load)); return; }
            scroll.appendChild(buildTop());
            const seg = segmented([
                { id: 'all', label: T('pc_eco_all') },
                { id: 'invoice', label: T('pc_eco_invoices') },
                { id: 'order', label: T('pc_eco_orders') },
                { id: 'transfer', label: T('pc_eco_transfers') },
            ], filter, (v) => { filter = v; buildHistoryList(); });
            scroll.appendChild(el('div', { class: 'lp-section' }, [el('h3', { text: T('pc_eco_history') }), seg.node]));
            histBox = el('div');
            scroll.appendChild(histBox);
            buildHistoryList();
        }

        async function transfer(method) {
            if (busy) return;
            const lim = limits();
            const raw = amountInput.value;
            const n = parseInt(raw, 10);
            if (!raw || !isFinite(n) || n < 1) {
                amountInput.classList.add('is-bad');
                xferMsg = { kind: 'err', text: T('pc_eco_bad_amount') };
                render();
                return;
            }
            if (n > lim.maxTransfer) {
                amountInput.classList.add('is-bad');
                xferMsg = { kind: 'err', text: T('pc_eco_max', money(lim.maxTransfer)) };
                render();
                return;
            }
            busy = true;
            xferMsg = null;
            render();
            const r = await rpc(method, [n]);
            busy = false;
            if (!win.alive()) return;
            if (!r.ok) {
                xferMsg = { kind: 'err', text: r.error };
            } else {
                xferMsg = { kind: 'ok', text: T(method === 'computer:deposit' ? 'pc_eco_done_deposit' : 'pc_eco_done_withdraw', money(n)) };
                amountInput.value = '';
            }
            await load(true);
        }

        async function load(quiet) {
            if (!loadedOnce && !quiet) { scroll.textContent = ''; scroll.appendChild(loader()); }
            const r = await rpc('computer:economy');
            if (!win.alive()) return;
            if (!r.ok) {
                failed = r.error;
            } else {
                failed = null;
                loadedOnce = true;
                balance = num(r.data && r.data.balance);
                history = (r.data && Array.isArray(r.data.history)) ? r.data.history : [];
            }
            render();
        }

        load();
        return { refresh: () => load(true) };
    }

    // ---------------------------------------------------------------------------------------------
    // App: Prisliste (price list, chef only)
    // ---------------------------------------------------------------------------------------------

    function mountPrices(win) {
        let rows = [];
        let raw = {}; // id -> the text in the input
        let groupOrder = [];
        let filter = 'all'; // all | changed | group:<id>
        let q = '';
        let failed = null;
        let loadedOnce = false;
        let saving = false;
        let msg = null;
        let rowEls = {};

        const side = el('aside', { class: 'lp-side' });
        const alertBox = el('div');
        const listBox = el('div', { class: 'lp-scroll' });
        const saveBar = el('div', { class: 'lp-savebar' });
        const main = el('div', { class: 'lp-main' }, [alertBox, listBox, saveBar]);
        win.body.append(side, main);

        const search = searchBox((v) => { q = v.trim().toLowerCase(); renderList(); });
        const refreshBtn = el('button', { class: 'lp-btn icon', attrs: { type: 'button', title: T('pc_refresh') }, on: { click: () => load() } }, [ic('arrows-rotate')]);
        win.tools.append(search.node, refreshBtn);

        const maxPrice = () => limits().maxPrice;
        const parsed = (id) => {
            const s = raw[id];
            if (s === '' || s === undefined) return NaN;
            const n = parseInt(s, 10);
            return (isFinite(n) && n >= 0 && n <= maxPrice()) ? n : NaN;
        };
        const changedRows = () => rows.filter((r) => { const n = parsed(r.id); return !isNaN(n) && n !== r.price; });
        const invalidRows = () => rows.filter((r) => isNaN(parsed(r.id)));
        const groupLabel = (r) => r.groupLabel || (FALLBACK['pc_grp_' + r.group] ? T('pc_grp_' + r.group) : String(r.group || ''));

        function setMsg(kind, text) {
            msg = text ? { kind, text } : null;
            alertBox.textContent = '';
            if (msg) alertBox.appendChild(banner(msg.kind, msg.text, () => setMsg(null)));
        }

        function renderSide() {
            side.textContent = '';
            side.append(
                sideHead(T('pc_prices_groups')),
                sideItem('tags', T('pc_prices_all'), rows.length, filter === 'all', () => setFilter('all')),
                sideItem('pen', T('pc_prices_changed'), changedRows().length, filter === 'changed', () => setFilter('changed')),
            );
            groupOrder.forEach((g) => {
                const inG = rows.filter((r) => r.group === g);
                side.appendChild(sideItem('folder', groupLabel(inG[0]), inG.length, filter === 'group:' + g, () => setFilter('group:' + g)));
            });
        }

        function setFilter(f) {
            filter = f;
            renderSide();
            renderList();
        }

        function updateRow(id) {
            const e = rowEls[id];
            if (!e) return;
            const r = e.row;
            const n = parsed(id);
            e.input.classList.toggle('is-bad', isNaN(n));
            e.el.classList.toggle('is-changed', !isNaN(n) && n !== r.price);
            e.reset.hidden = !(isNaN(n) || n !== r.default);
        }

        function updateFooter() {
            const ch = changedRows().length;
            const bad = invalidRows().length;
            saveBar.textContent = '';
            const label = bad ? T('pc_prices_invalid', maxPrice()) : (ch === 0 ? T('pc_prices_none') : (ch === 1 ? T('pc_prices_one') : T('pc_prices_many', ch)));
            const discard = el('button', { class: 'lp-btn', text: T('pc_prices_discard'), attrs: { type: 'button' }, on: { click: discardAll } });
            const save = el('button', { class: 'lp-btn primary', attrs: { type: 'button' }, on: { click: save_ } }, [ic(saving ? 'spinner' : 'floppy-disk', saving ? 'fa-spin' : ''), T('pc_prices_save')]);
            discard.disabled = saving || (ch === 0 && !bad);
            save.disabled = saving || ch === 0 || bad > 0;
            saveBar.append(el('span', { class: 'grow', text: label }), discard, save);
            const side0 = side.querySelectorAll('.lp-side-item .count');
            if (side0[1]) side0[1].textContent = String(ch);
        }

        function renderList() {
            listBox.textContent = '';
            rowEls = {};
            if (failed) { listBox.appendChild(errorState(failed, load)); updateFooter(); return; }
            const list = rows.filter((r) => {
                if (filter === 'changed') { const n = parsed(r.id); if (!(isNaN(n) || n !== r.price)) return false; }
                else if (filter.indexOf('group:') === 0 && r.group !== filter.slice(6)) return false;
                if (q && r.label.toLowerCase().indexOf(q) < 0) return false;
                return true;
            });
            if (!list.length) { listBox.appendChild(emptyState('tags', T('pc_prices_empty'))); updateFooter(); return; }
            const table = el('div', { class: 'lp-table', attrs: { style: '--cols:minmax(0,2fr) 7em 9em 2.4em' } });
            table.appendChild(el('div', { class: 'lp-thead' }, [
                el('span', { text: T('pc_col_item') }),
                el('span', { class: 'lp-right', text: T('pc_col_default') }),
                el('span', { class: 'lp-right', text: T('pc_col_price') }),
                el('span'),
            ]));
            let lastGroup = null;
            list.forEach((r) => {
                if (filter === 'all' || filter === 'changed') {
                    if (r.group !== lastGroup) { table.appendChild(el('div', { class: 'lp-groupbar', text: groupLabel(r) })); lastGroup = r.group; }
                }
                const input = el('input', { class: 'lp-input lp-price-in', attrs: { type: 'text', inputmode: 'numeric', maxlength: '7', autocomplete: 'off', 'aria-label': r.label } });
                input.value = raw[r.id];
                input.style.textAlign = 'right';
                const reset = el('button', { class: 'lp-btn sm icon', attrs: { type: 'button', title: T('pc_prices_reset_row') }, on: { click: () => { raw[r.id] = String(r.default); input.value = raw[r.id]; updateRow(r.id); updateFooter(); } } }, [ic('rotate-left')]);
                const field = el('div', { class: 'lp-money-input' }, [el('span', { text: '$' }), input]);
                const row = el('div', { class: 'lp-trow' }, [
                    el('div', { class: 'name' }, [el('span', { text: r.label })]),
                    el('span', { class: 'lp-right lp-muted', text: money(r.default) }),
                    field,
                    reset,
                ]);
                input.addEventListener('input', () => {
                    input.value = input.value.replace(/[^\d]/g, '');
                    raw[r.id] = input.value;
                    updateRow(r.id);
                    updateFooter();
                });
                input.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); e.stopPropagation(); input.blur(); } });
                rowEls[r.id] = { el: row, input, reset, row: r };
                table.appendChild(row);
                updateRow(r.id);
            });
            listBox.appendChild(table);
            updateFooter();
        }

        function discardAll() {
            rows.forEach((r) => { raw[r.id] = String(r.price); });
            setMsg(null);
            renderSide();
            renderList();
        }

        async function save_() {
            if (saving) return false;
            const ch = changedRows();
            if (!ch.length || invalidRows().length) return false;
            const map = {};
            ch.forEach((r) => { map[r.id] = parsed(r.id); });
            saving = true;
            updateFooter();
            const r = await rpc('computer:setPrices', [map]);
            saving = false;
            if (!win.alive()) return true;
            if (!r.ok) {
                setMsg('err', r.error);
                updateFooter();
                return false;
            }
            setMsg('ok', T('pc_prices_saved', ch.length));
            await load(true, true);
            return true;
        }

        // resetDrafts: after a save the server prices become the baseline for every input.
        // A plain refresh keeps unsaved edits.
        async function load(quiet, resetDrafts) {
            if (!loadedOnce && !quiet) { listBox.textContent = ''; listBox.appendChild(loader()); }
            const r = await rpc('computer:prices');
            if (!win.alive()) return;
            if (!r.ok) {
                failed = r.error;
            } else {
                failed = null;
                loadedOnce = true;
                const list = Array.isArray(r.data) ? r.data : (r.data && Array.isArray(r.data.prices) ? r.data.prices : []);
                rows = list.map((p) => ({
                    id: String(p.id),
                    label: String(p.label || p.id),
                    group: String(p.group || 'other'),
                    groupLabel: p.groupLabel ? String(p.groupLabel) : '',
                    default: Math.round(num(p.default)),
                    price: Math.round(num(p.price)),
                }));
                const keep = {};
                rows.forEach((x) => { keep[x.id] = (!resetDrafts && raw[x.id] !== undefined) ? raw[x.id] : String(x.price); });
                raw = keep;
                groupOrder = [];
                rows.forEach((x) => { if (groupOrder.indexOf(x.group) < 0) groupOrder.push(x.group); });
            }
            renderSide();
            renderList();
        }

        load();
        return {
            refresh: () => load(true),
            beforeClose() {
                if (!changedRows().length || failed) return true;
                winSheet(win, {
                    icon: 'tags',
                    title: T('pc_prices_unsaved_title'),
                    text: T('pc_prices_unsaved_text'),
                    buttons: [
                        { label: T('pc_cancel') },
                        { label: T('pc_prices_dont_save'), action: async () => { closeWin(win, true); return { ok: true }; } },
                        {
                            label: T('pc_prices_save'),
                            kind: 'primary',
                            default: true,
                            action: async () => {
                                const ok = await save_();
                                if (!ok) return { ok: false, error: (msg && msg.text) || T('pc_err_generic') };
                                closeWin(win, true);
                                return { ok: true };
                            },
                        },
                    ],
                });
                return false;
            },
        };
    }

    // ---------------------------------------------------------------------------------------------
    // App registry
    // ---------------------------------------------------------------------------------------------

    const APPS = [
        { id: 'stock', key: 'pc_app_stock', icon: 'boxes-stacked', c: ['#ffb340', '#f06a00'], size: [72, 46], min: [42, 26], mount: mountStock },
        { id: 'order', key: 'pc_app_order', icon: 'cart-shopping', c: ['#52d97b', '#1b9e44'], size: [82, 48], min: [52, 28], mount: mountOrder },
        { id: 'orders', key: 'pc_app_orders', icon: 'truck-fast', c: ['#5ac8fa', '#0a6fe0'], size: [64, 44], min: [40, 24], mount: mountOrders },
        { id: 'staff', key: 'pc_app_staff', icon: 'users', c: ['#c77dff', '#7d3cc4'], size: [68, 44], min: [44, 24], boss: true, mount: mountStaff },
        { id: 'eco', key: 'pc_app_eco', icon: 'chart-line', c: ['#40e0c8', '#0d8f86'], size: [70, 48], min: [46, 28], boss: true, mount: mountEco },
        { id: 'prices', key: 'pc_app_prices', icon: 'tags', c: ['#ff7a9c', '#d6264f'], size: [68, 48], min: [46, 26], boss: true, mount: mountPrices },
    ];

    // ---------------------------------------------------------------------------------------------
    // Lua messages
    // ---------------------------------------------------------------------------------------------

    App.on('laptop:open', (data) => openLaptop(data || {}));
    App.on('laptop:close', () => closeLaptop(false));

    // ---------------------------------------------------------------------------------------------
    // Demo mode (page opened in a normal browser): window.__demo(isBoss) with mocked responses.
    // ---------------------------------------------------------------------------------------------

    if (!App.isGame) {
        function demoBackend(isBoss) {
            const NAMES = {
                repair_kit: 'Reparationskit', engine_repair_kit: 'Motorreparationskit', body_repair_kit: 'Karosserireparationskit', tyre: 'Dæk',
                engine_lvl1: 'Motor niveau 1', engine_lvl2: 'Motor niveau 2', engine_lvl3: 'Motor niveau 3', engine_lvl4: 'Motor niveau 4',
                brakes_lvl1: 'Bremser niveau 1', brakes_lvl2: 'Bremser niveau 2', brakes_lvl3: 'Bremser niveau 3',
                transmission_lvl1: 'Gearkasse niveau 1', transmission_lvl2: 'Gearkasse niveau 2', transmission_lvl3: 'Gearkasse niveau 3',
                suspension_lvl1: 'Undervogn niveau 1', suspension_lvl2: 'Undervogn niveau 2', suspension_lvl3: 'Undervogn niveau 3', suspension_lvl4: 'Undervogn niveau 4',
                armor_lvl1: 'Panser niveau 1', armor_lvl2: 'Panser niveau 2', armor_lvl3: 'Panser niveau 3', armor_lvl4: 'Panser niveau 4', armor_lvl5: 'Panser niveau 5',
                turbo: 'Turbo',
            };
            const PRICE = {
                repair_kit: 400, engine_repair_kit: 900, body_repair_kit: 900, tyre: 250,
                engine_lvl1: 6000, engine_lvl2: 11000, engine_lvl3: 18000, engine_lvl4: 27000,
                brakes_lvl1: 3000, brakes_lvl2: 6000, brakes_lvl3: 10000,
                transmission_lvl1: 5000, transmission_lvl2: 9000, transmission_lvl3: 14000,
                suspension_lvl1: 2500, suspension_lvl2: 4500, suspension_lvl3: 7000, suspension_lvl4: 10000,
                armor_lvl1: 5000, armor_lvl2: 9000, armor_lvl3: 14000, armor_lvl4: 20000, armor_lvl5: 28000,
                turbo: 15000,
            };
            const stock = {
                repair_kit: 12, engine_repair_kit: 4, body_repair_kit: 1, tyre: 0,
                engine_lvl1: 3, engine_lvl2: 1, engine_lvl3: 0, engine_lvl4: 0,
                brakes_lvl1: 5, brakes_lvl2: 2, brakes_lvl3: 0,
                transmission_lvl1: 2, transmission_lvl2: 0, transmission_lvl3: 0,
                suspension_lvl1: 6, suspension_lvl2: 3, suspension_lvl3: 1, suspension_lvl4: 0,
                armor_lvl1: 4, armor_lvl2: 0, armor_lvl3: 0, armor_lvl4: 0, armor_lvl5: 0,
                turbo: 2,
            };
            const now = Date.now();
            const orders = [
                { id: 14, status: 'ordered', eta: 214, total: 18000 + 12000, ordered_by: 'Mikkel Jensen', created_at: now - 86000, items: [{ item: 'engine_lvl3', label: NAMES.engine_lvl3, count: 1 }, { item: 'brakes_lvl2', label: NAMES.brakes_lvl2, count: 2 }] },
                { id: 13, status: 'arrived', eta: 0, total: 8000, ordered_by: 'Sofie Lund', created_at: now - 780000, items: [{ item: 'tyre', label: NAMES.tyre, count: 20 }, { item: 'repair_kit', label: NAMES.repair_kit, count: 8 }] },
                { id: 12, status: 'collected', eta: 0, total: 27000, ordered_by: 'Mikkel Jensen', created_at: now - 7200000, items: [{ item: 'engine_lvl4', label: NAMES.engine_lvl4, count: 1 }] },
                { id: 11, status: 'collected', eta: 0, total: 28000, ordered_by: 'Jonas Holm', created_at: now - 90000000, items: [{ item: 'armor_lvl5', label: NAMES.armor_lvl5, count: 1 }] },
            ];
            let nextOrder = 15;
            const gradesList = [{ grade: 0, label: 'Lærling' }, { grade: 1, label: 'Mekaniker' }, { grade: 2, label: 'Senior mekaniker' }, { grade: 3, label: 'Chef' }];
            const gl = (g) => gradesList[g].label;
            let staff = [
                { identifier: 'a1', name: 'Mikkel Jensen', grade: 3, online: true },
                { identifier: 'a2', name: 'Sofie Lund', grade: 2, online: true },
                { identifier: 'a3', name: 'Jonas Holm', grade: 1, online: false },
                { identifier: 'a4', name: 'Emma Kjær', grade: 1, online: true },
                { identifier: 'a5', name: 'Oliver Bruun', grade: 0, online: false },
                { identifier: 'a6', name: 'Freja Madsen', grade: 0, online: true },
                { identifier: 'a7', name: 'Lars Winther', grade: 2, online: false },
            ];
            let nearby = [{ serverId: 12, name: 'Noah Andersen' }, { serverId: 31, name: 'Ida Poulsen' }, { serverId: 7, name: 'Victor Sand' }];
            let balance = 184500;
            let history = [
                { type: 'invoice', amount: 8400, by: 'Sofie Lund', detail: 'Motor niveau 2', created_at: now - 600000 },
                { type: 'order', amount: 30000, by: 'Mikkel Jensen', detail: 'Ordre #14', created_at: now - 86000 },
                { type: 'invoice', amount: 3500, by: 'Emma Kjær', detail: 'Lakering', created_at: now - 3600000 },
                { type: 'deposit', amount: 20000, by: 'Mikkel Jensen', detail: '', created_at: now - 5400000 },
                { type: 'order', amount: 8000, by: 'Sofie Lund', detail: 'Ordre #13', created_at: now - 780000 },
                { type: 'invoice', amount: 12600, by: 'Jonas Holm', detail: 'Bremser niveau 3', created_at: now - 8600000 },
                { type: 'withdraw', amount: 15000, by: 'Mikkel Jensen', detail: '', created_at: now - 20000000 },
                { type: 'invoice', amount: 2200, by: 'Freja Madsen', detail: 'Reparation', created_at: now - 30000000 },
                { type: 'order', amount: 27000, by: 'Mikkel Jensen', detail: 'Ordre #12', created_at: now - 7200000 },
                { type: 'invoice', amount: 5900, by: 'Emma Kjær', detail: 'Neon og xenon', created_at: now - 50000000 },
                { type: 'order', amount: 28000, by: 'Jonas Holm', detail: 'Ordre #11', created_at: now - 90000000 },
                { type: 'invoice', amount: 14300, by: 'Sofie Lund', detail: 'Turbo', created_at: now - 100000000 },
            ];
            const P = [
                ['modSpoilers', 'Spoiler', 'bodywork', 1500], ['modFrontBumper', 'Frontkofanger', 'bodywork', 1500], ['modRearBumper', 'Bagkofanger', 'bodywork', 1500],
                ['modSideSkirt', 'Sideskørter', 'bodywork', 1200], ['modExhaust', 'Udstødning', 'bodywork', 1000], ['modFrame', 'Rullebur', 'bodywork', 2000],
                ['modGrille', 'Grill', 'bodywork', 800], ['modHood', 'Motorhjelm', 'bodywork', 1500], ['modRoof', 'Tag', 'bodywork', 1200],
                ['modFrontWheels', 'Fælge', 'wheels', 2000], ['wheelType', 'Fælgtype', 'wheels', 0], ['customTires', 'Specialdæk', 'wheels', 800],
                ['tyreSmoke', 'Dækrøg', 'wheels', 1500], ['wheelColor', 'Fælgfarve', 'wheels', 1000],
                ['color1', 'Primærfarve', 'respray', 2500], ['color2', 'Sekundærfarve', 'respray', 2000], ['pearlescent', 'Perlemor', 'respray', 1500],
                ['modDashboard', 'Instrumentbræt', 'interior', 1200], ['modSeats', 'Sæder', 'interior', 1500], ['modSteeringWheel', 'Rat', 'interior', 1000],
                ['interiorColor', 'Kabinefarve', 'interior', 1000], ['dashboardColor', 'Instrumentfarve', 'interior', 800],
                ['modEngineBlock', 'Motorblok', 'engine', 1500], ['modAirFilter', 'Luftfilter', 'engine', 800], ['modStruts', 'Fjederbensstivere', 'engine', 1000],
                ['xenon', 'Xenon', 'lights', 1500], ['neon', 'Neon', 'lights', 3000],
                ['modPlateHolder', 'Pladeholder', 'plates', 300], ['plateIndex', 'Pladetype', 'plates', 300],
                ['modHorns', 'Horn', 'other', 500], ['modLivery', 'Livery', 'other', 2500], ['windowTint', 'Rudetoning', 'other', 800],
            ];
            const prices = P.map((p) => ({ id: p[0], label: p[1], group: p[2], default: p[3], price: p[3] }));
            prices[0].price = 1800; prices[13].price = 900; prices[16].price = 2200;

            const bossOnly = new Set(['computer:staff', 'computer:nearby', 'computer:hire', 'computer:setGrade', 'computer:fire', 'computer:economy', 'computer:deposit', 'computer:withdraw', 'computer:prices', 'computer:setPrices']);
            const ok = (data) => ({ ok: true, data });
            const fail = (error) => ({ ok: false, error });

            return async function (method, args) {
                await new Promise((r) => setTimeout(r, 120));
                if (window.__demoFail) return fail('Serveren svarer ikke.');
                if (bossOnly.has(method) && !isBoss) return fail('Kun chefen kan bruge denne app.');
                switch (method) {
                    case 'stock:get':
                        return ok({ workshop: 'bennys', label: "Benny's lager", items: Object.keys(stock).filter((k) => stock[k] > 0).map((k) => ({ name: k, label: NAMES[k], count: stock[k] })) });
                    case 'computer:catalog':
                        return ok(Object.keys(PRICE).map((k) => ({ item: k, label: NAMES[k], price: PRICE[k], stock: stock[k] })));
                    case 'order:list':
                        return ok(orders.map((o) => Object.assign({}, o)));
                    case 'order:place': {
                        const lines = args[0] || [];
                        let total = 0;
                        const items = lines.map((l) => { total += PRICE[l.item] * l.count; return { item: l.item, label: NAMES[l.item], count: l.count }; });
                        if (total > balance) return fail('Firmakontoen har ikke råd.');
                        balance -= total;
                        const id = nextOrder++;
                        orders.unshift({ id, status: 'ordered', eta: 300, total, ordered_by: 'Mikkel Jensen', created_at: Date.now(), items });
                        history.unshift({ type: 'order', amount: total, by: 'Mikkel Jensen', detail: 'Ordre #' + id, created_at: Date.now() });
                        return ok({ id, total, eta: 300 });
                    }
                    case 'computer:staff':
                        return ok({ staff: staff.map((s) => Object.assign({ gradeLabel: gl(s.grade) }, s)), grades: gradesList });
                    case 'computer:nearby':
                        return ok(nearby.slice());
                    case 'computer:hire': {
                        const n = nearby.find((x) => x.serverId === args[0]);
                        if (!n) return fail('Spilleren er ikke længere i nærheden.');
                        nearby = nearby.filter((x) => x !== n);
                        staff.push({ identifier: 'h' + n.serverId, name: n.name, grade: 0, online: true });
                        return ok(true);
                    }
                    case 'computer:setGrade': {
                        const s = staff.find((x) => x.identifier === args[0]);
                        if (!s) return fail('Medarbejderen findes ikke.');
                        s.grade = args[1];
                        return ok(true);
                    }
                    case 'computer:fire':
                        staff = staff.filter((x) => x.identifier !== args[0]);
                        return ok(true);
                    case 'computer:economy':
                        return ok({ balance, history: history.slice() });
                    case 'computer:deposit':
                        balance += args[0];
                        history.unshift({ type: 'deposit', amount: args[0], by: 'Mikkel Jensen', detail: '', created_at: Date.now() });
                        return ok(true);
                    case 'computer:withdraw':
                        if (args[0] > balance) return fail('Firmakontoen har ikke nok penge.');
                        balance -= args[0];
                        history.unshift({ type: 'withdraw', amount: args[0], by: 'Mikkel Jensen', detail: '', created_at: Date.now() });
                        return ok(true);
                    case 'computer:prices':
                        return ok(prices.map((p) => Object.assign({}, p)));
                    case 'computer:setPrices': {
                        const m = args[0] || {};
                        Object.keys(m).forEach((id) => { const p = prices.find((x) => x.id === id); if (p) p.price = m[id]; });
                        return ok(true);
                    }
                    default:
                        return fail('Ukendt metode.');
                }
            };
        }

        window.__demo = (isBoss) => {
            const boss = isBoss === undefined ? true : !!isBoss;
            demoHandler = demoBackend(boss);
            // Closing from the NUI would call Lua; in demo mode the page just hides
            window.postMessage({
                action: 'laptop:open',
                data: {
                    name: 'Mikkel Jensen',
                    grade: boss ? 3 : 1,
                    gradeLabel: boss ? 'Chef' : 'Mekaniker',
                    isBoss: boss,
                    workshop: { id: 'bennys', label: "Benny's Original Motor Works" },
                    shop: { deliveryMinutes: 5 },
                },
            }, '*');
        };
        window.__demoOpenApp = (id) => openApp(id);
        window.__demoClose = () => window.postMessage({ action: 'laptop:close', data: {} }, '*');
    }
})();
