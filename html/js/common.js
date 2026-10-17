/* Shared NUI helpers for ap1le_mechanicjob (owned by the lead; apps must not redefine these).
 *   App.post(name, body)      -> Promise<any>  POST to a Lua NUI callback, null on failure
 *   App.on(action, fn)        register a handler for SendNUIMessage({ action, data })
 *   App.t(key, ...args)       translated string ('%s'/'%d' replaced in order), falls back to the key
 *   App.ready                 Promise resolved once the locale is loaded
 *   App.isGame                false when the page is opened in a normal browser (demo mode)
 *   App.el(tag, opts, kids)   tiny DOM builder; opts: { class, text, attrs, on: { click: fn } }
 * Chrome 103 (FiveM CEF): no :has(), color-mix(), CSS nesting or linear() easing.
 */
(function () {
    'use strict';

    const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : null;
    const handlers = {};
    let LOC = {};

    async function post(name, body) {
        if (!RES) return null;
        try {
            const res = await fetch(`https://${RES}/${name}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(body || {}),
            });
            const text = await res.text();
            return text ? JSON.parse(text) : null;
        } catch (e) {
            return null;
        }
    }

    function t(key, ...args) {
        let s = LOC[key];
        if (typeof s !== 'string') return key;
        let i = 0;
        return s.replace(/%[sd]/g, () => (i < args.length ? String(args[i++]) : ''));
    }

    function el(tag, opts, kids) {
        const node = document.createElement(tag);
        opts = opts || {};
        if (opts.class) node.className = opts.class;
        if (opts.text !== undefined && opts.text !== null) node.textContent = String(opts.text);
        if (opts.attrs) for (const k in opts.attrs) if (opts.attrs[k] !== undefined && opts.attrs[k] !== null) node.setAttribute(k, opts.attrs[k]);
        if (opts.on) for (const k in opts.on) node.addEventListener(k, opts.on[k]);
        (kids || []).forEach((c) => { if (c) node.appendChild(typeof c === 'string' ? document.createTextNode(c) : c); });
        return node;
    }

    async function loadLocale() {
        for (let i = 0; i < 10; i++) {
            const res = await post('locale');
            if (res && typeof res === 'object' && Object.keys(res).length) { LOC = res; return; }
            if (!RES) return;
            await new Promise((r) => setTimeout(r, 500));
        }
    }

    window.addEventListener('message', (e) => {
        const msg = e.data;
        if (!msg || typeof msg.action !== 'string') return;
        const fn = handlers[msg.action];
        if (fn) App.ready.then(() => fn(msg.data || {}));
    });

    window.App = {
        post,
        t,
        el,
        isGame: !!RES,
        on(action, fn) { handlers[action] = fn; },
        setLocale(obj) { LOC = obj || {}; },  // demo mode only
        ready: null,
    };
    App.ready = loadLocale();
})();
