// Shared helpers of the result cards. Each card's HTML holds its numbers in one DATA object at the top and calls
// these helpers. No number lives in this file. bench/render_cards.ps1 renders every card with headless Edge.
// Query: ?focus=8gb puts the 8 GB column or series first (the tier pages render that way); no focus = 12 GB first.
var NS = 'http://www.w3.org/2000/svg';
var Q = new URLSearchParams(location.search);
var FOCUS = Q.get('focus') === '8gb' ? '8gb' : (Q.get('focus') === '12gb' ? '12gb' : null);
var ORDER = FOCUS === '8gb' ? ['8gb', '12gb'] : ['12gb', '8gb'];
var TIER = {
  '12gb': { name: '12 GB', gpu: 'RTX 4070', color: 'var(--t12)', soft: 'var(--t12-soft)' },
  '8gb': { name: '8 GB', gpu: 'RTX 2060 SUPER', color: 'var(--t8)', soft: 'var(--t8-soft)' }
};
var NM = 'not measured';
var REPO = 'github.com/professorpalmer/bonsai-ada-surgery';

function el(tag, attrs, text) {
  var e = document.createElementNS(NS, tag);
  for (var k in attrs) e.setAttribute(k, attrs[k]);
  if (text !== undefined) e.textContent = text;
  return e;
}
function svg(w, h) { return el('svg', { viewBox: '0 0 ' + w + ' ' + h, preserveAspectRatio: 'xMidYMid meet' }); }
function fmt(v, d) {
  if (v === null || v === undefined) return NM;
  return Number(v).toLocaleString('en-US', { minimumFractionDigits: d || 0, maximumFractionDigits: d || 0 });
}
function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;'); }

// The card frame: eyebrow, title, optional sub line and legend, the body, and the small-print sources.
// foot: array of strings (one per tier or source), printed in small type at the bottom.
function card(o) {
  var leg = o.legend ? '<div class="legend">' + o.legend.map(function (i) {
    return '<span><i class="sw" style="background:' + i[0] + '"></i>' + esc(i[1]) + '</span>';
  }).join('') + '</div>' : '';
  document.getElementById('card').innerHTML =
    '<div class="top"><span class="eyebrow">' + esc(o.eyebrow) + '</span><b>' + REPO + '</b></div><h1>' + esc(o.title) + '</h1>' +
    (o.sub ? '<p class="sub">' + esc(o.sub) + '</p>' : '') + leg +
    '<div class="body" id="body"></div>' +
    '<div class="foot">' + (o.foot || []).map(esc).join('<br>') + '</div>';
  return document.getElementById('body');
}
function tierLegend() { return ORDER.map(function (t) { return [TIER[t].color, TIER[t].name + ' · ' + TIER[t].gpu]; }); }

// A two-tier table. rows: [{ label, note, '12gb': cell, '8gb': cell }], cell = null (not measured) or
// { v: 'text', unit: 'small text' }. heads: { '12gb': 'small line under the tier name', '8gb': ... }.
function tierTable(body, rows, heads) {
  var h = '<div class="tt"><div></div>';
  ORDER.forEach(function (t) {
    h += '<div class="hd" style="color:' + TIER[t].color + '">' + TIER[t].name + ' · ' + TIER[t].gpu +
      '<small>' + esc(heads[t] || '') + '</small></div>';
  });
  rows.forEach(function (r) {
    h += '<div class="lb">' + esc(r.label) + (r.note ? '<small>' + esc(r.note) + '</small>' : '') + '</div>';
    ORDER.forEach(function (t) {
      var c = r[t];
      var cls = 'v' + (FOCUS === t ? ' focus' : '');
      if (!c) h += '<div class="' + cls + ' nm">' + NM + '</div>';
      else h += '<div class="' + cls + '"><span>' + esc(c.v) + (c.unit ? '<small>' + esc(c.unit) + '</small>' : '') + '</span></div>';
    });
  });
  body.innerHTML = h + '</div>';
  var tt = body.firstChild;
  tt.style.gridTemplateRows = 'auto repeat(' + rows.length + ', minmax(0, 1fr))';
  tt.style.alignContent = 'stretch';
}

// Horizontal bars, one bar per tier in each row. rows: [{ label, note, '12gb': cell, '8gb': cell }],
// cell = null (not measured) or { v: number (bar length), text: 'label after the bar' }. o: { max, H, labelW }.
function tierBars(body, rows, o) {
  var W = 1104, H = o.H || 360, LW = o.labelW || 330, R = 230, gap = 6;
  var rowH = H / rows.length, barH = Math.min(26, (rowH - 18 - gap) / 2);
  var s = svg(W, H);
  var x = function (v) { return LW + v / o.max * (W - LW - R); };
  rows.forEach(function (r, i) {
    var y0 = i * rowH, mid = y0 + rowH / 2;
    if (i) s.appendChild(el('line', { x1: 0, x2: W, y1: y0, y2: y0, stroke: 'var(--line)' }));
    s.appendChild(el('text', { class: 'cat', x: 0, y: mid + (r.note ? -4 : 7) }, r.label));
    if (r.note) s.appendChild(el('text', { x: 0, y: mid + 20, style: 'font-size:15px' }, r.note));
    ORDER.forEach(function (t, j) {
      var c = r[t], yy = mid - barH - gap / 2 + j * (barH + gap);
      if (!c) {
        s.appendChild(el('rect', { x: LW, y: yy, width: 6, height: barH, rx: 2, fill: 'var(--nm)', opacity: 0.5 }));
        s.appendChild(el('text', { class: 'nm', x: LW + 16, y: yy + barH / 2 + 6 }, TIER[t].name + ': ' + NM));
        return;
      }
      var w = Math.max(x(c.v) - LW, 4);
      s.appendChild(el('rect', { x: LW, y: yy, width: w, height: barH, rx: 3, fill: TIER[t].color }));
      s.appendChild(el('text', { class: 'val', x: LW + w + 10, y: yy + barH / 2 + 8, style: 'font-size:21px;fill:' + TIER[t].color }, c.text));
    });
  });
  body.appendChild(s);
}
