/* Workshop computer (NUI side of contract sections 0.6 and 7). Builds all DOM inside #laptop-root.
 *
 * Lua -> NUI:  laptop:open { name, grade, gradeLabel, isBoss, workshop, shop }, laptop:close {}
 * NUI -> Lua:  laptop:request { method, args } -> { ok, data, error }, laptop:close {}
 *
 * A MacBook desktop in ap1le_core's design language: menu bar, dock, draggable windows, and the apps
 * Lager, Bestil, Ordrer (everyone) plus Personale, Okonomi, Prisliste (chef only; the server
 * re-checks every call). All dynamic text goes through textContent (App.el).
 * Look (v3): one accent (ap1le_core's --brand), monochrome icons in grey circles, status colours only
 * as a small dot next to a word. See css/laptop.css.
 * Errors: the text Lua sends (`error`, the server's/esx_society's reason) is shown as is. If the locale
 * has no text for the key (`error` === `code`), the Danish fallback below is used.
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
        pc_menu_close_pc: 'Luk computeren', // Close the computer
        pc_menu_apps: 'Programmer', // Apps (menu)
        pc_menu_window: 'Vindue', // Window (menu)
        pc_menu_refresh: 'Opdater', // Refresh
        pc_menu_minimize: 'Minimer', // Minimise
        pc_menu_zoom: 'Zoom', // Zoom
        pc_menu_close_win: 'Luk vindue', // Close window
        pc_menu_minimize_all: 'Minimer alle', // Minimise all
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
        pc_err_network: 'Computeren fik ikke svar. Prøv igen.', // The computer got no answer. Try again.
        pc_widget_orders: 'Undervejs', // Orders on the way (desktop widget)
        pc_widget_balance: 'Firmakonto', // Society balance (desktop widget)
        pc_widget_ready: 'Klar til afhentning', // Crates ready for pickup (desktop widget)
        pc_filter_all: 'Alle varer', // All items
        pc_filter_in: 'På lager', // In stock
        pc_filter_low: 'Lav beholdning', // Low stock
        pc_filter_out: 'Ikke på lager', // Out of stock
        pc_side_stock: 'Beholdning', // Stock level (sidebar section)
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
        pc_low_stock: 'Lav beholdning', // Low stock
        pc_add_cart: 'Læg i kurv', // Add to cart
        pc_cart: 'Kurv', // Cart
        pc_cart_empty: 'Kurven er tom. Vælg dele i kataloget.', // The cart is empty. Pick parts in the catalog.
        pc_cart_clear: 'Tøm', // Clear (cart)
        pc_cart_remove: 'Fjern', // Remove (tooltip)
        pc_total: 'I alt', // Total
        pc_society_pays: 'Betales af firmakontoen.', // Paid from the society account.
        pc_delivery_eta: 'Leveres om ca. %s min.', // Delivered in about N min.
        pc_place_order: 'Bestil', // Place order (button)
        pc_ordering: 'Bestiller …', // Ordering …
        pc_order_placed: 'Ordre #%s er bestilt for %s. Leveres om ca. %s min.', // Order #N placed for $X. Delivered in about N min.
        pc_max_lines: 'Højst %s forskellige varer pr. ordre.', // At most N different items per order.
        pc_max_qty: 'Højst %s stk. pr. vare.', // At most N pieces per item.
        pc_catalog_empty: 'Ingen varer matcher.', // No items match.
        pc_orders_all: 'Alle', // All (orders filter)
        pc_st_ordered: 'Undervejs', // On the way (order status)
        pc_st_arrived: 'Klar til afhentning', // Ready for pickup (order status)
        pc_st_collected: 'Afhentet', // Collected (order status)
        pc_orders_empty: 'Ingen ordrer her.', // No orders here.
        pc_order_no: 'Ordre #%s', // Order #N
        pc_order_by: 'af %s', // by NAME
        pc_order_arrives: 'Ankommer om %s', // Arrives in M:SS
        pc_order_arriving: 'Ankommer snart', // Arriving soon
        pc_order_ready: 'Kassen står ved leveringspladsen. Pak den ud, så delene kommer på lager.', // The crate is at the delivery spot. Unpack it to put the parts in stock.
        pc_staff_all: 'Alle', // All (staff filter)
        pc_staff_online: 'Online', // Online
        pc_staff_offline: 'Offline', // Offline
        pc_staff_hire: 'Ansæt', // Hire
        pc_staff_group: 'Medarbejdere', // Employees (sidebar section)
        pc_staff_nearby: 'I nærheden', // Nearby (sidebar item: people who can be hired)
        pc_staff_empty: 'Ingen medarbejdere her.', // No employees here.
        pc_staff_you: 'Dig', // You
        pc_staff_fire: 'Fyr', // Fire
        pc_staff_locked: 'Samme eller højere stilling end dig', // Same or higher rank than you (cannot be changed)
        pc_staff_grade: 'Stilling', // Rank
        pc_fire_title: 'Fyr %s?', // Fire NAME?
        pc_fire_text: '%s mister jobbet som mekaniker med det samme. Det kan ikke fortrydes.', // NAME loses the mechanic job right away. This cannot be undone.
        pc_nearby_empty: 'Ingen i nærheden. Bed personen stille sig ved computeren.', // Nobody nearby. Ask the person to stand by the computer.
        pc_nearby_hint: 'Personer ved computeren, som ikke er mekanikere.', // People at the computer who are not mechanics.
        pc_hire_btn: 'Ansæt', // Hire (button)
        pc_hired: '%s er ansat.', // NAME has been hired.
        pc_hire_waiting: 'Venter på svar fra %s …', // Waiting for NAME to answer …
        pc_fired: '%s er fyret.', // NAME has been fired.
        pc_grade_set: 'Stillingen er ændret.', // The rank has been changed.
        pc_server_id: 'ID %s', // ID N
        pc_eco_title: 'Firmakonto', // Society account
        pc_eco_income: 'Indtægter', // Income
        pc_eco_expense: 'Udgifter', // Expenses
        pc_eco_period: 'Seneste %s posteringer', // Last N entries (caption under income/expenses)
        pc_eco_transfer: 'Overfør', // Transfer
        pc_eco_amount: 'Beløb', // Amount
        pc_eco_deposit: 'Indsæt', // Deposit
        pc_eco_withdraw: 'Hæv', // Withdraw
        pc_eco_cash_hint: 'Pengene flyttes mellem din bankkonto og firmakontoen.', // The money moves between your cash and the society account.
        pc_eco_history: 'Historik', // History
        pc_eco_empty: 'Ingen posteringer her.', // No entries here.
        pc_eco_bad_amount: 'Skriv et helt beløb på mindst $1.', // Enter a whole amount of at least $1.
        pc_eco_max: 'Højst %s pr. overførsel.', // At most X per transfer.
        pc_eco_done_deposit: '%s er indsat på firmakontoen.', // X deposited into the society account.
        pc_eco_done_withdraw: '%s er hævet fra firmakontoen.', // X withdrawn from the society account.
        pc_eco_all: 'Alle', // All (history filter)
        pc_eco_invoices: 'Fakturaer', // Invoices (history filter)
        pc_eco_orders: 'Bestillinger', // Orders (history filter)
        pc_eco_transfers: 'Overførsler', // Transfers (history filter)
        pc_eco_t_invoice: 'Faktura', // Invoice (history type)
        pc_eco_t_order: 'Bestilling', // Order (history type)
        pc_eco_t_deposit: 'Indsat', // Deposited (history type)
        pc_eco_t_withdraw: 'Hævet', // Withdrawn (history type)
        pc_eco_by: 'af %s', // by NAME
        pc_prices_all: 'Alle priser', // All prices
        pc_prices_changed: 'Ændrede', // Changed
        pc_prices_groups: 'Grupper', // Groups (sidebar section)
        pc_prices_save: 'Gem priser', // Save prices
        pc_prices_discard: 'Fortryd', // Discard
        pc_prices_reset_row: 'Brug standardprisen', // Use the default price
        pc_prices_saved: 'Priserne er gemt (%s ændret).', // The prices are saved (N changed).
        pc_prices_none: 'Ingen ændringer', // No changes
        pc_prices_one: '1 ændring', // 1 change
        pc_prices_many: '%s ændringer', // N changes
        pc_prices_invalid: 'En pris er ugyldig. Brug 0-%s.', // A price is invalid. Use 0-N.
        pc_prices_empty: 'Ingen priser matcher.', // No prices match.
        pc_prices_unsaved_title: 'Gem de ændrede priser?', // Save the changed prices?
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
        // Server error keys (owned by the server dev and locales/*.json). Only used when the locale has no
        // text for a key, so the player still sees the real reason instead of the raw key
        error: 'Noget gik galt.', // Something went wrong.
        too_fast: 'Det gik for hurtigt. Prøv igen om lidt.', // Too fast. Try again in a moment.
        pc_not_boss: 'Kun chefen kan gøre det.', // Only the boss can do that.
        pc_too_far: 'Du er for langt fra computeren.', // You are too far from the computer.
        pc_invalid_amount: 'Ugyldigt beløb.', // Invalid amount.
        pc_no_money: 'Du har ikke penge nok på din bankkonto.', // You do not have enough cash.
        pc_society_no_money: 'Firmakontoen har ikke penge nok.', // The society account does not have enough money.
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

    // "12.500" (Danish thousands separator)
    function groupNum(n) {
        return String(Math.abs(Math.round(num(n)))).replace(/\B(?=(\d{3})+(?!\d))/g, '.');
    }

    // "$12.500"
    function money(n) {
        n = Math.round(num(n));
        return (n < 0 ? '-' : '') + '$' + groupNum(n);
    }

    const DAYS = ['søn.', 'man.', 'tir.', 'ons.', 'tor.', 'fre.', 'lør.'];
    const MONTHS = ['jan.', 'feb.', 'mar.', 'apr.', 'maj', 'jun.', 'jul.', 'aug.', 'sep.', 'okt.', 'nov.', 'dec.'];

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
        if (!res.ok) {
            const code = typeof res.code === 'string' ? res.code : null;
            return { ok: false, error: errorText(res.error, code), code };
        }
        return { ok: true, data: res.data };
    }

    // The reason Lua sent (already translated by the client from the server's locale key). When the
    // locale lacks the key, ox_lib returns the key itself; then use our fallback text for that key.
    function errorText(error, code) {
        const text = typeof error === 'string' ? error.trim() : '';
        const key = code || text;
        const untranslated = !text || text === code || /^[a-z0-9_]+$/.test(text);
        if (!untranslated) return text;
        if (key && FALLBACK[key] !== undefined) return T(key);
        return T('pc_err_generic');
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
        widget: null,
    };
    const dom = {};

    // Item categories (derived from the item name; the catalog only has item, label, price, stock).
    // Icons are monochrome; the category is told by the glyph and the label, never by a colour.
    const CATS = [
        { id: 'repair', icon: 'screwdriver-wrench' },
        { id: 'engine', icon: 'gauge-high' },
        { id: 'brakes', icon: 'compact-disc' },
        { id: 'transmission', icon: 'gears' },
        { id: 'suspension', icon: 'arrows-up-down' },
        { id: 'armor', icon: 'shield-halved' },
        { id: 'turbo', icon: 'fan' },
        { id: 'other', icon: 'box' },
    ];
    const CAT_BY = {};
    CATS.forEach((c) => { CAT_BY[c.id] = c; });

    const ITEM_ICON = {
        repair_kit: 'wrench',
        engine_repair_kit: 'screwdriver-wrench',
        body_repair_kit: 'car-burst',
        tyre: 'circle-dot',
        cleaning_kit: 'spray-can-sparkles',
    };

    function catOf(name) {
        name = String(name);
        if (/^(repair_kit|engine_repair_kit|body_repair_kit|tyre|cleaning_kit)$/.test(name)) return 'repair';
        if (name === 'turbo') return 'turbo';
        const m = /^([a-z]+)_lvl\d+$/.exec(name);
        if (m && CAT_BY[m[1]] && m[1] !== 'repair') return m[1];
        return 'other';
    }

    function catIndex(name) {
        return CATS.findIndex((c) => c.id === catOf(name));
    }

    // Sort by category, then by name (so levels 1, 2, 3 follow each other)
    function byCategory(a, b) {
        const ca = catIndex(a);
        const cb = catIndex(b);
        if (ca !== cb) return ca - cb;
        return a < b ? -1 : (a > b ? 1 : 0);
    }

    // The item's glyph in a grey circle (ap1le_core's menu icon). size: '' | 'sm' | 'lg'
    function itemIcon(name, size) {
        return iconCircle(ITEM_ICON[name] || CAT_BY[catOf(name)].icon, size);
    }

    function iconCircle(icon, size) {
        return el('span', { class: 'lp-ico' + (size ? ' ' + size : ''), attrs: { 'aria-hidden': 'true' } }, [ic(icon)]);
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

    // Initials in a grey circle (no per-person colours); online = small green dot
    function avatar(name, online) {
        const initials = String(name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map((p) => p[0].toUpperCase()).join('');
        return el('div', { class: 'lp-avatar', attrs: { 'aria-hidden': 'true' } },
            [initials || '?', online === undefined ? null : el('span', { class: 'dot' + (online ? ' on' : '') })]);
    }

    // A status word with a small dot. kind: 'ok' | 'warn' | 'err' | 'info' | '' (grey) | 'plain' (no dot)
    function stateTag(kind, text) {
        return el('span', { class: 'lp-state' + (kind ? ' ' + kind : ''), text });
    }

    // ---------------------------------------------------------------------------------------------
    // Sheets (macOS style confirm dialogs, inside a window) and modals (on the desktop)
    // ---------------------------------------------------------------------------------------------

    // o: { title, text, buttons: [{ label, kind, default, action }] } (ap1le_core's confirm dialog: title,
    // muted text, equal capsule buttons). With a 'danger' button and no explicit default, the first button
    // (cancel) gets focus, so a quick Enter never does the destructive thing (as in ap1le_core).
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
        const hasDanger = (o.buttons || []).some((b) => b.kind === 'danger');
        const node = el('div', { class: 'lp-sheet', attrs: { role: 'alertdialog', 'aria-modal': 'true' } }, [
            el('h3', { text: o.title || '' }),
            o.text ? el('p', { text: o.text }) : null,
            err,
            row,
        ]);
        return {
            node,
            focus() { (def || (hasDanger ? btns[0] : btns[btns.length - 1])).focus(); },
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
            el('div', { class: 'lp-win-title', text: T(app.key) }),
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
        // Right side: only what is real (workshop and clock); no fake wifi/battery glyphs
        const right = el('div', { class: 'lp-mb-group' }, [
            ws ? el('span', { class: 'lp-mb-item static lp-mb-ws', text: ws }) : null,
            el('span', { class: 'lp-mb-item' }, [dom.clock]),
        ]);
        return el('div', { class: 'lp-menubar', attrs: { role: 'menubar' } }, [left, right]);
    }

    function tickClock() {
        const d = new Date();
        const hm = pad2(d.getHours()) + ':' + pad2(d.getMinutes());
        if (dom.clock) dom.clock.textContent = DAYS[d.getDay()] + ' ' + hm;
    }

    function buildDock() {
        dom.dockItems = {};
        const dock = el('div', { class: 'lp-dock', attrs: { role: 'toolbar' } });
        const apps = visibleApps();
        apps.forEach((a, i) => {
            if (a.boss && !apps[i - 1].boss) dock.appendChild(el('div', { class: 'lp-dock-sep' }));
            const item = el('button', { class: 'lp-dock-item', attrs: { type: 'button', 'aria-label': T(a.key) } }, [
                el('div', { class: 'lp-dock-icon' }, [ic(a.icon)]),
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
            const sigma = base * 1.4;
            S.dockMeta.forEach((it) => {
                const dist = m - it.c;
                // Gentle magnification (macOS-like, but calm)
            const s = 1 + 0.28 * Math.exp(-(dist * dist) / (2 * sigma * sigma));
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

    // One small glass panel top right: who is logged in, orders on the way / ready, and (chef) the
    // society balance. Each row opens its app. No decorative clock (the menu bar has the time).
    function buildWidget() {
        const d = S.data;
        const widget = el('div', { class: 'lp-widget' }, [
            el('div', { class: 'lp-widget-head' }, [
                el('b', { text: d.name || '' }),
                el('span', { text: d.gradeLabel || '' }),
            ]),
        ]);
        const row = (icon, label, appId) => {
            const val = el('b', { text: '–' });
            widget.appendChild(el('button', { class: 'lp-widget-row', attrs: { type: 'button' }, on: { click: () => openApp(appId) } },
                [iconCircle(icon, 'sm'), el('span', { class: 'lbl', text: label }), val]));
            return val;
        };
        const ordersVal = row('truck-fast', T('pc_widget_orders'), 'orders');
        const readyVal = row('box-open', T('pc_widget_ready'), 'orders');
        const balVal = S.isBoss ? row('building-columns', T('pc_widget_balance'), 'eco') : null;

        // Best effort: a failed call leaves the dash
        const refreshOrders = () => rpc('order:list').then((r) => {
            if (!r.ok || !Array.isArray(r.data) || !S.open) return;
            ordersVal.textContent = String(r.data.filter((o) => o.status === 'ordered').length);
            readyVal.textContent = String(r.data.filter((o) => o.status === 'arrived').length);
        });
        const setBalance = (v) => {
            if (balVal && v !== null && v !== undefined && isFinite(Number(v))) balVal.textContent = money(v);
        };
        S.widget = { refreshOrders, setBalance };

        refreshOrders();
        if (balVal) {
            rpc('computer:economy').then((r) => {
                if (r.ok && r.data && S.open) setBalance(r.data.balance);
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
        S.widget = null;
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
            el('div', { class: 'lp-wallpaper' }, [
                el('div', { class: 'lp-wallpaper-mark' }, [ic('wrench'), el('span', { text: (S.data.workshop && S.data.workshop.label) || '' })]),
            ]),
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
        const status = el('div', { class: 'lp-statusbar' });
        const main = el('div', { class: 'lp-main' }, [title, listBox, status]);
        win.body.append(side, main);

        const search = searchBox((v) => { q = v.trim().toLowerCase(); renderList(); });
        const refreshBtn = el('button', { class: 'lp-btn icon ghost', attrs: { type: 'button', title: T('pc_refresh'), 'aria-label': T('pc_refresh') }, on: { click: () => load() } }, [ic('arrows-rotate')]);
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
                sideItem('battery-quarter', T('pc_filter_low'), rows.filter(isLow).length, filter === 'low', () => setFilter('low')),
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

        // Count + one status word. Colour only when something needs attention (low / out)
        function qtyCell(r) {
            if (r.count <= 0) return el('div', { class: 'lp-qty is-out' }, [el('b', { text: '0' }), stateTag('err', T('pc_out_of_stock'))]);
            if (isLow(r)) return el('div', { class: 'lp-qty' }, [el('b', { text: r.count }), stateTag('warn', T('pc_low_stock'))]);
            return el('div', { class: 'lp-qty' }, [el('b', { text: r.count })]);
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
            title.textContent = filterLabel();
            listBox.textContent = '';
            if (!list.length) {
                listBox.appendChild(emptyState('box-open', T('pc_stock_empty')));
            } else {
                const table = el('div', { class: 'lp-table', attrs: { style: '--cols:minmax(0,2.4fr) minmax(0,1fr) 6em minmax(0,1.5fr) 6.5em' } });
                table.appendChild(el('div', { class: 'lp-thead' }, [
                    el('span', { text: T('pc_col_item') }),
                    el('span', { text: T('pc_col_category') }),
                    el('span', { class: 'lp-right', text: T('pc_col_price') }),
                    el('span', { text: T('pc_col_qty') }),
                    el('span'),
                ]));
                list.forEach((r) => {
                    // Every row the same quiet button: the status dot already says which ones need ordering
                    const orderBtn = r.price !== null
                        ? el('button', { class: 'lp-btn sm', text: T('pc_order_btn'), attrs: { type: 'button' }, on: { click: () => orderItem(r.name) } })
                        : el('span');
                    table.appendChild(el('div', { class: 'lp-trow' }, [
                        el('div', { class: 'name' }, [itemIcon(r.name, 'sm'), el('span', { text: r.label })]),
                        el('span', { class: 'lp-muted', text: T('pc_cat_' + catOf(r.name)) }),
                        el('span', { class: 'lp-right', text: r.price !== null ? money(r.price) : '' }),
                        qtyCell(r),
                        el('div', { class: 'lp-right' }, [orderBtn]),
                    ]));
                });
                listBox.appendChild(table);
            }
            const total = rows.reduce((sum, r) => sum + r.count, 0);
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
                // A failed refresh keeps the list that is already shown
                if (loadedOnce) return;
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
            rows = Array.from(map.values()).sort((a, b) => byCategory(a.name, b.name));
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
        const refreshBtn = el('button', { class: 'lp-btn icon ghost', attrs: { type: 'button', title: T('pc_refresh'), 'aria-label': T('pc_refresh') }, on: { click: () => load() } }, [ic('arrows-rotate')]);
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

        // Stock in the workshop, as a quiet line: "3 på lager" (grey), low (yellow dot), none (red dot)
        function stockTag(stock) {
            if (stock <= 0) return stateTag('err', T('pc_out_of_stock'));
            if (stock <= LOW) return stateTag('warn', T('pc_in_stock', stock));
            return stateTag('plain', T('pc_in_stock', stock));
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
                let control;
                if (qty > 0) {
                    control = stepper(qty, () => cartAdd(c.item, -1), () => flash(cartAdd(c.item, 1)), qty >= lim.perLine);
                } else {
                    control = el('button', { class: 'lp-btn sm', text: T('pc_add_cart'), attrs: { type: 'button' }, on: { click: () => flash(cartAdd(c.item, 1)) } });
                }
                wrap.appendChild(el('div', { class: 'lp-card' + (qty > 0 ? ' in-cart' : '') }, [
                    el('div', { class: 'top' }, [itemIcon(c.item), stockTag(num(c.stock))]),
                    el('div', { class: 'nm', text: c.label, attrs: { title: c.label } }),
                    el('div', { class: 'price', text: money(c.price) }),
                    el('div', { class: 'foot' }, [control]),
                ]));
            });
            grid.appendChild(wrap);
        }

        function stepper(qty, onMinus, onPlus, plusDisabled) {
            const plus = el('button', { attrs: { type: 'button', 'aria-label': '+' }, on: { click: onPlus } }, [ic('plus')]);
            if (plusDisabled) plus.disabled = true;
            return el('div', { class: 'lp-step' }, [
                el('button', { attrs: { type: 'button', 'aria-label': '-' }, on: { click: onMinus } }, [ic('minus')]),
                el('b', { text: qty }),
                plus,
            ]);
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
                lines.length ? el('button', { class: 'lp-btn sm ghost', text: T('pc_cart_clear'), attrs: { type: 'button' }, on: { click: () => { S.cart = {}; msg = null; notifyCart(); } } }) : null,
            ]);
            const box = el('div', { class: 'lp-cart-lines' });
            if (!lines.length) {
                box.appendChild(el('div', { class: 'lp-empty' }, [el('p', { text: T('pc_cart_empty') })]));
            }
            lines.sort(byCategory).forEach((k) => {
                const c = m[k];
                const label = c ? c.label : k;
                box.appendChild(el('div', { class: 'lp-cart-line' }, [
                    itemIcon(k, 'sm'),
                    el('div', { class: 'nm', text: label, attrs: { title: label } }),
                    el('button', { class: 'lp-btn sm icon ghost', attrs: { type: 'button', title: T('pc_cart_remove'), 'aria-label': T('pc_cart_remove') }, on: { click: () => cartSet(k, 0) } }, [ic('xmark')]),
                    el('div', { class: 'sub' }, [
                        stepper(S.cart[k], () => cartAdd(k, -1), () => flash(cartAdd(k, 1)), S.cart[k] >= lim.perLine),
                        el('span', { class: 'lp-muted', text: money((c ? num(c.price) : 0) * S.cart[k]) }),
                    ]),
                ]));
            });
            const foot = el('div', { class: 'lp-cart-foot' });
            if (msg) foot.appendChild(banner(msg.kind, msg.text, () => { msg = null; renderCart(); }));
            const submitBtn = el('button', { class: 'lp-btn lg primary block', attrs: { type: 'button' }, on: { click: submit } },
                busy ? [el('span', { class: 'lp-spin', attrs: { style: 'width:1em;height:1em;border-width:0.13em' } }), T('pc_ordering')] : [T('pc_place_order')]);
            submitBtn.disabled = busy || !lines.length;
            foot.append(
                el('div', { class: 'total' }, [el('span', { class: 'lp-muted', text: T('pc_total') }), el('b', { text: money(total) })]),
                el('div', { class: 'lp-cart-note', text: T('pc_society_pays') + ' ' + T('pc_delivery_eta', lim.minutes) }),
                submitBtn,
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
            refreshApps(['orders', 'stock', 'eco']);
            if (S.widget) S.widget.refreshOrders();
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
                // A failed refresh keeps the catalog that is already shown
                if (loadedOnce) return;
                failed = r.error;
            } else {
                failed = null;
                loadedOnce = true;
                catalog = (Array.isArray(r.data) ? r.data : []).map((c) => ({ item: String(c.item), label: String(c.label || c.item), price: num(c.price), stock: num(c.stock) }));
                catalog.sort((a, b) => byCategory(a.item, b.item));
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
        const refreshBtn = el('button', { class: 'lp-btn icon ghost', attrs: { type: 'button', title: T('pc_refresh'), 'aria-label': T('pc_refresh') }, on: { click: () => load() } }, [ic('arrows-rotate')]);
        win.tools.append(seg.node, refreshBtn);

        // Glyph + status dot. Only "ready" uses a status colour: it is the one that needs someone to act
        const STATUS = {
            ordered: { icon: 'truck-fast', state: 'info' },
            arrived: { icon: 'box-open', state: 'ok' },
            collected: { icon: 'check', state: '' },
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
            const wrap = el('div', { class: 'lp-list' });
            list.forEach((o) => {
                const key = STATUS[o.status] ? o.status : 'collected';
                const st = STATUS[key];
                const items = (Array.isArray(o.items) ? o.items : []).map((i) => num(i.count) + '× ' + (i.label || i.item)).join(', ');
                const meta = [o.ordered_by ? T('pc_order_by', o.ordered_by) : '', fmtDate(o.created_at)].filter(Boolean).join(' · ');
                const card = el('div', { class: 'lp-order' }, [
                    iconCircle(st.icon),
                    el('div', { class: 'mid' }, [
                        el('div', { class: 'ttl', text: T('pc_order_no', o.id) }),
                        el('div', { class: 'meta', text: meta }),
                        items ? el('div', { class: 'items', text: items }) : null,
                    ]),
                    el('div', { class: 'side' }, [
                        el('b', { text: money(o.total) }),
                        stateTag(st.state, T('pc_st_' + key)),
                    ]),
                ]);
                if (o.status === 'ordered') {
                    const fill = el('i');
                    const eta = el('span', { class: 'eta' });
                    card.appendChild(el('div', { class: 'prog' }, [el('div', { class: 'bar' }, [fill]), eta]));
                    live.push({ o, fill, eta, total: Math.max(total, num(o.eta)) });
                } else if (o.status === 'arrived') {
                    card.appendChild(el('div', { class: 'ready', text: T('pc_order_ready') }));
                }
                wrap.appendChild(card);
            });
            box.appendChild(wrap);
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
                // A failed refresh keeps the list that is already shown
                if (loadedOnce) return;
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
        const alertBox = el('div', { class: 'lp-alert-wrap' });
        const listBox = el('div', { class: 'lp-scroll' });
        const main = el('div', { class: 'lp-main' }, [alertBox, listBox]);
        win.body.append(side, main);

        const search = searchBox((v) => { q = v.trim().toLowerCase(); renderList(); });
        const refreshBtn = el('button', { class: 'lp-btn icon ghost', attrs: { type: 'button', title: T('pc_refresh'), 'aria-label': T('pc_refresh') }, on: { click: () => load() } }, [ic('arrows-rotate')]);
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
                sideItem('signal', T('pc_staff_online'), staff.filter((s) => s.online).length, view === 'online', () => setView('online')),
                sideItem('moon', T('pc_staff_offline'), staff.filter((s) => !s.online).length, view === 'offline', () => setView('offline')),
                sideHead(T('pc_staff_hire')),
                sideItem('user-plus', T('pc_staff_nearby'), nearby.length ? nearby.length : null, view === 'hire', () => setView('hire')),
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
            const wrap = el('div', { class: 'lp-list' });
            listBox.appendChild(wrap);
            list.forEach((s) => {
                const locked = s.grade >= me.grade;
                const isMe = s.name === me.name && s.grade === me.grade;
                const who = el('div', { class: 'who' }, [
                    avatar(s.name, s.online),
                    el('div', {}, [
                        el('b', { text: s.name }),
                        isMe ? el('small', { text: T('pc_staff_you') }) : null,
                    ]),
                ]);
                let rank;
                if (locked) {
                    // Same or higher rank than the chef: shown, not editable
                    rank = el('span', { class: 'rank-fixed', attrs: { title: T('pc_staff_locked') } }, [ic('lock'), el('span', { text: s.gradeLabel || gradeLabel(s.grade) })]);
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
                    locked ? null : el('button', { class: 'lp-btn sm quiet-danger', text: T('pc_staff_fire'), attrs: { type: 'button' }, on: { click: () => confirmFire(s) } }),
                ]);
                wrap.appendChild(el('div', { class: 'lp-person' }, [
                    who,
                    el('div', {}, [rank]),
                    stateTag(s.online ? 'ok' : '', s.online ? T('pc_staff_online') : T('pc_staff_offline')),
                    acts,
                ]));
            });
        }

        function renderHire() {
            const wrap = el('div', { class: 'lp-list' });
            listBox.appendChild(el('div', { class: 'lp-pad lp-muted', text: T('pc_nearby_hint') }));
            const list = nearby.filter((n) => !q || String(n.name).toLowerCase().indexOf(q) >= 0);
            if (!list.length) { listBox.appendChild(emptyState('user-plus', T('pc_nearby_empty'))); return; }
            listBox.appendChild(wrap);
            list.forEach((n) => {
                const btn = el('button', { class: 'lp-btn sm primary', text: T('pc_hire_btn'), attrs: { type: 'button' } });
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
                wrap.appendChild(el('div', { class: 'lp-person hire' }, [
                    el('div', { class: 'who' }, [avatar(n.name), el('div', {}, [el('b', { text: n.name }), el('small', { text: T('pc_server_id', n.serverId) })])]),
                    el('div', { class: 'acts' }, [btn]),
                ]));
            });
        }

        function confirmFire(s) {
            winSheet(win, {
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

    // History rows: a monochrome glyph per type; incoming amounts in green, outgoing in plain text
    const HIST = {
        invoice: { icon: 'file-invoice-dollar', sign: 1 },
        order: { icon: 'box', sign: -1 },
        deposit: { icon: 'arrow-down', sign: 1 },
        withdraw: { icon: 'arrow-up', sign: -1 },
    };

    // Society deposit/withdraw (v3 A1). Lua runs esx_society's own events (see client/computer.lua) and
    // answers { ok, data = { kind, amount, balance }, error, code }. The NUI:
    //   - shows `error` exactly as Lua sent it (the server's / esx_society's reason, e.g. "not enough
    //     cash", "only the boss can withdraw", "the transfer did not go through"), never a generic text
    //     when a real reason exists;
    //   - shows the new balance from the answer at once (data.balance), then reloads the history;
    //   - keeps the shown balance and history if that reload fails (it does not swap the whole app for
    //     an error screen, which in v2 also hid the transfer result).
    function mountEco(win) {
        let balance = null;
        let history = [];
        let filter = 'all';
        let failed = null;
        let loadedOnce = false;
        let busy = null; // null | 'computer:deposit' | 'computer:withdraw'
        let xferMsg = null;

        const scroll = el('div', { class: 'lp-scroll' });
        const main = el('div', { class: 'lp-main' }, [scroll]);
        win.body.append(main);

        const refreshBtn = el('button', { class: 'lp-btn icon ghost', attrs: { type: 'button', title: T('pc_refresh'), 'aria-label': T('pc_refresh') }, on: { click: () => load() } }, [ic('arrows-rotate')]);
        win.tools.append(refreshBtn);

        // The amount field lives across re-renders (keeps focus and what was typed)
        const amountInput = el('input', { attrs: { type: 'text', inputmode: 'numeric', maxlength: '9', placeholder: '0', autocomplete: 'off', 'aria-label': T('pc_eco_amount') } });
        const amountField = el('label', { class: 'lp-money-input lg' }, [el('span', { text: '$' }), amountInput]);
        amountInput.addEventListener('input', () => {
            amountInput.value = amountInput.value.replace(/[^\d]/g, '');
            amountField.classList.remove('is-bad');
        });
        amountInput.addEventListener('focus', () => amountField.classList.add('is-focus'));
        amountInput.addEventListener('blur', () => amountField.classList.remove('is-focus'));
        // Enter does nothing here on purpose: deposit and withdraw are both one click away, and a stray
        // Enter must not move money
        amountInput.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); e.stopPropagation(); } });

        let histBox = null;
        let balanceEl = null;

        function typeKey(t) { return HIST[t] ? t : 'order'; }

        function buildTop() {
            let income = 0;
            let expense = 0;
            history.forEach((h) => { const v = num(h.amount); if (HIST[typeKey(h.type)].sign > 0) income += v; else expense += v; });

            balanceEl = el('div', { class: 'amt', text: balance === null ? '–' : money(balance) });
            const bal = el('div', { class: 'lp-panel lp-balance' }, [
                el('div', { class: 'lbl', text: T('pc_eco_title') }),
                balanceEl,
                el('div', { class: 'sums' }, [
                    el('div', {}, [el('small', { text: T('pc_eco_income') }), el('b', { text: money(income) })]),
                    el('div', {}, [el('small', { text: T('pc_eco_expense') }), el('b', { text: money(expense) })]),
                    history.length ? el('div', { class: 'cap', text: T('pc_eco_period', history.length) }) : null,
                ]),
            ]);

            const quick = el('div', { class: 'quick' });
            [1000, 5000, 10000, 50000].forEach((v) => {
                quick.appendChild(el('button', { class: 'lp-btn sm', text: money(v), attrs: { type: 'button' }, on: { click: () => { amountInput.value = String(v); amountField.classList.remove('is-bad'); amountInput.focus(); } } }));
            });
            const btnKids = (method, label) => (busy === method
                ? [el('span', { class: 'lp-spin', attrs: { style: 'width:1em;height:1em;border-width:0.13em' } }), label]
                : [label]);
            const dep = el('button', { class: 'lp-btn primary', attrs: { type: 'button' }, on: { click: () => transfer('computer:deposit') } }, btnKids('computer:deposit', T('pc_eco_deposit')));
            const wd = el('button', { class: 'lp-btn', attrs: { type: 'button' }, on: { click: () => transfer('computer:withdraw') } }, btnKids('computer:withdraw', T('pc_eco_withdraw')));
            dep.disabled = !!busy;
            wd.disabled = !!busy;
            amountInput.disabled = !!busy;

            const xfer = el('div', { class: 'lp-panel lp-transfer' }, [
                el('h3', { text: T('pc_eco_transfer') }),
                amountField,
                quick,
                el('div', { class: 'hint', text: T('pc_eco_cash_hint') }),
                xferMsg ? banner(xferMsg.kind, xferMsg.text, () => { xferMsg = null; render(); }) : null,
                el('div', { class: 'btns' }, [dep, wd]),
            ]);
            return el('div', { class: 'lp-eco-top' }, [bal, xfer]);
        }

        function buildHistoryList() {
            histBox.textContent = '';
            const list = history.filter((h) => filter === 'all'
                || (filter === 'transfer' ? (h.type === 'deposit' || h.type === 'withdraw') : h.type === filter));
            if (!list.length) { histBox.appendChild(emptyState('receipt', T('pc_eco_empty'))); return; }
            const table = el('div', { class: 'lp-table', attrs: { style: '--cols:minmax(0,2.2fr) minmax(0,1.2fr) 8.5em 7.5em' } });
            list.forEach((h) => {
                const tk = typeKey(h.type);
                const cfg = HIST[tk];
                const v = num(h.amount);
                table.appendChild(el('div', { class: 'lp-trow' }, [
                    el('div', { class: 'name' }, [
                        iconCircle(cfg.icon, 'sm'),
                        el('span', { text: [T('pc_eco_t_' + tk), h.detail].filter(Boolean).join(' · ') }),
                    ]),
                    el('span', { class: 'lp-muted', text: h.by ? T('pc_eco_by', h.by) : '' }),
                    el('span', { class: 'lp-muted', text: fmtDate(h.created_at) }),
                    el('b', { class: 'lp-right ' + (cfg.sign > 0 ? 'lp-pos' : 'lp-neg'), text: (cfg.sign > 0 ? '+' : '−') + money(v) }),
                ]));
            });
            histBox.appendChild(table);
        }

        function render() {
            const hadFocus = document.activeElement === amountInput;
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
            if (hadFocus && !amountInput.disabled) amountInput.focus();
        }

        function setBalance(v) {
            if (v === null || v === undefined || !isFinite(Number(v))) return;
            balance = num(v);
            if (balanceEl) balanceEl.textContent = money(balance);
            if (S.widget) S.widget.setBalance(balance);
        }

        async function transfer(method) {
            if (busy) return;
            const lim = limits();
            const raw = amountInput.value;
            const n = parseInt(raw, 10);
            if (!raw || !isFinite(n) || n < 1) {
                amountField.classList.add('is-bad');
                xferMsg = { kind: 'err', text: T('pc_eco_bad_amount') };
                render();
                amountInput.focus();
                return;
            }
            if (n > lim.maxTransfer) {
                amountField.classList.add('is-bad');
                xferMsg = { kind: 'err', text: T('pc_eco_max', money(lim.maxTransfer)) };
                render();
                amountInput.focus();
                return;
            }
            busy = method;
            xferMsg = null;
            render();
            const r = await rpc(method, [n]);
            busy = null;
            if (!win.alive()) return;
            if (!r.ok) {
                // The real reason from the server / esx_society, as Lua sent it
                xferMsg = { kind: 'err', text: r.error };
                render();
                // The balance may still have changed (e.g. esx_society was slow); show the truth
                load(true);
                return;
            }
            const d = (r.data && typeof r.data === 'object') ? r.data : {};
            const done = num(d.amount) > 0 ? num(d.amount) : n;
            xferMsg = { kind: 'ok', text: T(method === 'computer:deposit' ? 'pc_eco_done_deposit' : 'pc_eco_done_withdraw', money(done)) };
            amountInput.value = '';
            setBalance(d.balance);
            render();
            // New history row (and the balance as the server sees it now)
            load(true);
        }

        async function load(quiet) {
            if (!loadedOnce && !quiet) { scroll.textContent = ''; scroll.appendChild(loader()); }
            const r = await rpc('computer:economy');
            if (!win.alive()) return;
            if (!r.ok) {
                // A failed refresh keeps the balance and history that are shown
                if (loadedOnce) return;
                failed = r.error;
            } else {
                failed = null;
                loadedOnce = true;
                history = (r.data && Array.isArray(r.data.history)) ? r.data.history : [];
                setBalance(r.data && r.data.balance);
            }
            render();
        }

        load();
        return { refresh: () => load(true) };
    }

    // ---------------------------------------------------------------------------------------------
    // App: Prisliste (price list, chef only)
    // ---------------------------------------------------------------------------------------------

    // Sidebar glyphs of the price groups (Config.Cosmetic.groups ids)
    const GROUP_ICON = {
        bodywork: 'car-side', wheels: 'circle-dot', respray: 'spray-can', interior: 'couch',
        engine: 'gears', lights: 'lightbulb', plates: 'car-rear', other: 'ellipsis', wash: 'soap',
    };

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
        const alertBox = el('div', { class: 'lp-alert-wrap' });
        const listBox = el('div', { class: 'lp-scroll' });
        const saveBar = el('div', { class: 'lp-savebar' });
        const main = el('div', { class: 'lp-main' }, [alertBox, listBox, saveBar]);
        win.body.append(side, main);

        const search = searchBox((v) => { q = v.trim().toLowerCase(); renderList(); });
        const refreshBtn = el('button', { class: 'lp-btn icon ghost', attrs: { type: 'button', title: T('pc_refresh'), 'aria-label': T('pc_refresh') }, on: { click: () => load() } }, [ic('arrows-rotate')]);
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
                side.appendChild(sideItem(GROUP_ICON[g] || 'folder', groupLabel(inG[0]), inG.length, filter === 'group:' + g, () => setFilter('group:' + g)));
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
            e.field.classList.toggle('is-bad', isNaN(n));
            e.el.classList.toggle('is-changed', !isNaN(n) && n !== r.price);
            e.reset.hidden = !(isNaN(n) || n !== r.default);
        }

        function updateFooter() {
            const ch = changedRows().length;
            const bad = invalidRows().length;
            saveBar.textContent = '';
            const label = bad ? T('pc_prices_invalid', groupNum(maxPrice())) : (ch === 0 ? T('pc_prices_none') : (ch === 1 ? T('pc_prices_one') : T('pc_prices_many', ch)));
            const discard = el('button', { class: 'lp-btn', text: T('pc_prices_discard'), attrs: { type: 'button' }, on: { click: discardAll } });
            const save = el('button', { class: 'lp-btn primary', attrs: { type: 'button' }, on: { click: save_ } },
                saving ? [el('span', { class: 'lp-spin', attrs: { style: 'width:1em;height:1em;border-width:0.13em' } }), T('pc_prices_save')] : [T('pc_prices_save')]);
            discard.disabled = saving || (ch === 0 && !bad);
            save.disabled = saving || ch === 0 || bad > 0;
            saveBar.append(el('span', { class: 'grow' + (bad ? ' is-bad' : ''), text: label }), discard, save);
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
                const input = el('input', { attrs: { type: 'text', inputmode: 'numeric', maxlength: '7', autocomplete: 'off', 'aria-label': r.label } });
                input.value = raw[r.id];
                const reset = el('button', { class: 'lp-btn sm icon ghost', attrs: { type: 'button', title: T('pc_prices_reset_row'), 'aria-label': T('pc_prices_reset_row') }, on: { click: () => { raw[r.id] = String(r.default); input.value = raw[r.id]; updateRow(r.id); updateFooter(); } } }, [ic('rotate-left')]);
                const field = el('label', { class: 'lp-money-input lp-price-in' }, [el('span', { text: '$' }), input]);
                input.addEventListener('focus', () => field.classList.add('is-focus'));
                input.addEventListener('blur', () => field.classList.remove('is-focus'));
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
                rowEls[r.id] = { el: row, input, field, reset, row: r };
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
        { id: 'stock', key: 'pc_app_stock', icon: 'boxes-stacked', size: [72, 46], min: [42, 26], mount: mountStock },
        { id: 'order', key: 'pc_app_order', icon: 'cart-shopping', size: [82, 48], min: [52, 28], mount: mountOrder },
        { id: 'orders', key: 'pc_app_orders', icon: 'truck-fast', size: [64, 44], min: [40, 24], mount: mountOrders },
        { id: 'staff', key: 'pc_app_staff', icon: 'users', size: [68, 44], min: [44, 24], boss: true, mount: mountStaff },
        { id: 'eco', key: 'pc_app_eco', icon: 'building-columns', size: [70, 48], min: [46, 28], boss: true, mount: mountEco },
        { id: 'prices', key: 'pc_app_prices', icon: 'tags', size: [68, 48], min: [46, 26], boss: true, mount: mountPrices },
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
            // error = the translated text Lua sends, code = the locale key (as client/computer.lua answers)
            const fail = (error, code) => ({ ok: false, error, code: code || null });
            let cash = 50000;

            return async function (method, args) {
                await new Promise((r) => setTimeout(r, 120));
                if (window.__demoFail) return fail('Noget gik galt.', 'error');
                if (bossOnly.has(method) && !isBoss) return fail('Kun chefen kan gøre det.', 'pc_not_boss');
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
                    // Same answer shape as the esx_society flow in client/computer.lua: { kind, amount, balance }
                    case 'computer:deposit':
                        await new Promise((r) => setTimeout(r, 500));
                        if (args[0] > cash) return fail('Du har ikke penge nok på din bankkonto.', 'pc_no_money');
                        cash -= args[0];
                        balance += args[0];
                        history.unshift({ type: 'deposit', amount: args[0], by: 'Mikkel Jensen', detail: "Benny's Original Motor Works", created_at: Date.now() });
                        return ok({ kind: 'deposit', amount: args[0], balance });
                    case 'computer:withdraw':
                        await new Promise((r) => setTimeout(r, 500));
                        if (args[0] > balance) return fail('Firmakontoen har ikke penge nok.', 'pc_society_no_money');
                        balance -= args[0];
                        cash += args[0];
                        history.unshift({ type: 'withdraw', amount: args[0], by: 'Mikkel Jensen', detail: "Benny's Original Motor Works", created_at: Date.now() });
                        return ok({ kind: 'withdraw', amount: args[0], balance });
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
                    shop: { deliveryMinutes: 5, maxPerLine: boss ? 20 : 2, maxLines: boss ? 15 : 1, maxTransfer: 1000000, maxPrice: 250000 },
                },
            }, '*');
        };
        window.__demoOpenApp = (id) => openApp(id);
        window.__demoClose = () => window.postMessage({ action: 'laptop:close', data: {} }, '*');
    }
})();
