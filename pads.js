/* pads.js — controllers for browser games, once, properly.
 *
 * Include with:  <script src="pads.js"></script>
 * Use per frame: const pads = Pads.poll();          // up to 4 normalised pads
 * Status/show:   Pads.status()                      // human-readable line
 * Diagnose:      Pads.diag()                        // policy, focus, sources
 * Events:        Pads.onChange(fn)
 *
 * Two sources, same shape (a browser gamepad):
 *   1. navigator.getGamepads() — works whenever the browser exposes pads.
 *      Browsers hide pads until the page has focus and a button is pressed;
 *      inside an iframe the page also needs allow="gamepad" (or the host's
 *      Permissions-Policy will return an empty list forever).
 *   2. The local pad bridge (pad-bridge/naga-pads) on 127.0.0.1:8777, which
 *      reads pads with macOS GameController and streams them. Used only when
 *      the browser reports none, so a working Gamepad API always wins.
 *
 * Pad shape, whether it came from the browser or the bridge:
 *   {index, id, mapping, connected, axes:[lx,ly,rx,ry], buttons:[{pressed,value}]}
 */
(function (global) {
  'use strict';

  var BRIDGE_URL = 'http://127.0.0.1:8777/pads';
  var MAX_PADS = 4;

  var bridgePads = [];
  var bridgeState = 'idle';          // idle | connecting | live | closed
  var es = null;
  var lastSignature = '';
  var changeHandlers = [];

  function normaliseBridgePad(p) {
    return {
      index: p.index,
      id: p.id + ' ·bridge',
      mapping: 'standard',
      connected: true,
      source: 'bridge',
      axes: p.axes,
      buttons: p.buttons.map(function (v) { return { pressed: !!v, value: v ? 1 : 0 }; })
    };
  }

  function connectBridge() {
    if (!global.EventSource) { bridgeState = 'closed'; return; }
    try { es = new global.EventSource(BRIDGE_URL); } catch (e) { bridgeState = 'closed'; return; }
    bridgeState = 'connecting';
    es.onopen = function () { bridgeState = 'live'; };
    es.onmessage = function (e) {
      bridgeState = 'live';
      try {
        var d = JSON.parse(e.data);
        bridgePads = (d.pads || []).map(normaliseBridgePad);
      } catch (err) { /* keep the last good frame */ }
    };
    // Chrome retries on its own; only give up when the stream is closed for good.
    es.onerror = function () {
      if (es.readyState === 2) { bridgeState = 'closed'; bridgePads = []; }
    };
  }

  function browserPads() {
    var list = [];
    try {
      var raw = navigator.getGamepads ? navigator.getGamepads() : [];
      for (var i = 0; i < raw.length; i++) if (raw[i] && raw[i].connected !== false) list.push(raw[i]);
    } catch (e) { /* sandboxed document */ }
    list.sort(function (a, b) { return a.index - b.index; });
    return list;
  }

  function signatureOf(list) {
    return list.map(function (p) { return p.index + ':' + p.id; }).join(',');
  }

  function poll() {
    var browser = browserPads();
    var list = bridgePads.length ? bridgePads : browser;
    var sig = signatureOf(list);
    if (sig !== lastSignature) {
      var previous = lastSignature;
      lastSignature = sig;
      changeHandlers.forEach(function (fn) {
        try { fn(list.slice(0, MAX_PADS), previous, list); } catch (e) { /* user callback */ }
      });
    }
    return list.slice(0, MAX_PADS);
  }

  function diag() {
    var policy = true;
    try {
      if (document.featurePolicy && document.featurePolicy.allowsFeature) {
        policy = document.featurePolicy.allowsFeature('gamepad');
      }
    } catch (e) { /* older browsers */ }
    var browser = browserPads();
    var frames = false;
    try { frames = global.self !== global.top; } catch (e) { frames = true; }
    return {
      policy: policy,
      framed: frames,
      focused: document.hasFocus(),
      activated: !!(navigator.userActivation && navigator.userActivation.hasBeenActive),
      browser: browser.length,
      bridge: bridgePads.length,
      bridgeState: bridgeState,
      source: bridgePads.length ? 'bridge' : (browser.length ? 'browser' : 'none'),
      blockedByPolicy: !policy
    };
  }

  function status() {
    var d = diag();
    if (d.blockedByPolicy) return 'CONTROLLERS BLOCKED — this frame does not allow gamepad access. Open the game in its own tab.';
    if (d.source === 'bridge') return 'PADS ' + d.bridge + '/' + MAX_PADS + ' (bridge)';
    if (d.source === 'browser') return 'PADS ' + d.browser + '/' + MAX_PADS;
    return 'NO PADS — click the window, then press a button on each controller' +
      (d.framed ? ' · in a frame, gamepads may be blocked' : '');
  }

  function axis(pad, i) {
    if (!pad || !pad.axes) return 0;
    var v = pad.axes[i] || 0, dz = 0.18;
    return Math.abs(v) < dz ? 0 : (v - Math.sign(v) * dz) / (1 - dz);
  }

  function pressed(pad, i) {
    return !!(pad && pad.buttons && pad.buttons[i] && pad.buttons[i].pressed);
  }

  global.Pads = {
    poll: poll,
    diag: diag,
    status: status,
    axis: axis,
    pressed: pressed,
    max: MAX_PADS,
    onChange: function (fn) { if (typeof fn === 'function') changeHandlers.push(fn); }
  };

  connectBridge();
  poll();
})(window);
