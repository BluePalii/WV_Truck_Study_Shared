// Pure, DOM-free, Leaflet-free logic for the toll/traffic layers of the WV
// truck-parking dashboard. This file is inlined verbatim into the built
// wv-truck-parking-dashboard.html by tools/build-dashboard.ps1 (so the
// generated dashboard stays a single portable file) and is also required
// directly by tools/traffic-lib.test.js. Keep it free of `window`/`document`/
// `L` references so both uses keep working.

function toNumberOrNull(v) {
  if (v === null || v === undefined) return null;
  var s = String(v).trim();
  if (s === '') return null;
  var n = Number(s);
  return isNaN(n) ? null : n;
}

function toDateOrNull(v) {
  if (v === null || v === undefined) return null;
  var s = String(v).trim();
  if (s === '') return null;
  var d = new Date(s);
  return isNaN(d.getTime()) ? null : d;
}

function fmtCount(v) {
  var n = (typeof v === 'number') ? v : toNumberOrNull(v);
  return (n === null) ? 'Not available' : String(n);
}

function fmtPct(v) {
  var n = (typeof v === 'number') ? v : toNumberOrNull(v);
  return (n === null) ? 'Not available' : (n + '%');
}

function formatSource(v) {
  if (v === null || v === undefined) return 'Not available';
  var s = String(v).trim();
  return s === '' ? 'Not available' : s;
}

// filterState: { facetKey: { value: true, ... }, ... } — same shape as the
// dashboard's existing FACETS/filterState pattern. A facet with no active
// values is a passthrough; unknown facetKeys not present in filterState are
// ignored (no filtering applied for them).
function filterRows(rows, filterState) {
  filterState = filterState || {};
  var keys = Object.keys(filterState);
  return (rows || []).filter(function (r) {
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i];
      var active = Object.keys(filterState[key] || {}).filter(function (v) { return filterState[key][v]; });
      if (active.length && active.indexOf(String(r[key])) === -1) return false;
    }
    return true;
  });
}

function isLayerEmpty(layerMeta) {
  return !layerMeta || !layerMeta.hasData;
}

function emptyStateFor(layerMeta) {
  if (!layerMeta) {
    return { empty: true, message: 'No data reported for this layer.', reason: 'Layer not configured.' };
  }
  if (!layerMeta.hasData) {
    return {
      empty: true,
      message: 'No data reported for ' + layerMeta.label + ' — see methodology.',
      reason: layerMeta.unavailableReason || 'No data source currently available.'
    };
  }
  return { empty: false };
}

// coverage = { geo: string, periodStart: dateish, periodEnd: dateish }.
// Two coverages "match" only if the geography label is the same (case/space
// insensitive) and the date ranges are identical — matching a wider/narrower
// or offset range is deliberately NOT treated as a match, per the spec's
// "only calculate a rate when numerator/denominator coverage matches
// reliably" requirement.
function coverageMatches(a, b) {
  if (!a || !b) return false;
  if (!a.geo || !b.geo) return false;
  if (String(a.geo).trim().toLowerCase() !== String(b.geo).trim().toLowerCase()) return false;
  var aStart = toDateOrNull(a.periodStart), aEnd = toDateOrNull(a.periodEnd);
  var bStart = toDateOrNull(b.periodStart), bEnd = toDateOrNull(b.periodEnd);
  if (!aStart || !aEnd || !bStart || !bEnd) return false;
  return aStart.getTime() === bStart.getTime() && aEnd.getTime() === bEnd.getTime();
}

// Returns null (never a misleading number) unless coverage matches and both
// inputs are usable. Formula: citations / estimated vehicle exposure * 1e6.
function citationsPerMillion(citationCount, vehicleExposure, numeratorCoverage, denominatorCoverage) {
  var c = toNumberOrNull(citationCount);
  var exposure = toNumberOrNull(vehicleExposure);
  if (c === null || exposure === null || exposure <= 0) return null;
  if (!coverageMatches(numeratorCoverage, denominatorCoverage)) return null;
  return (c / exposure) * 1000000;
}

// state: plain object; array-valued keys (per arrayKeys) become
// comma-joined, percent-encoded-per-element lists; boolean keys (per
// boolKeys) become '1'/'0'; everything else is a percent-encoded scalar.
// Empty/undefined/null values are omitted entirely (absent = no filter).
function serializeParams(state, arrayKeys, boolKeys) {
  arrayKeys = arrayKeys || [];
  boolKeys = boolKeys || [];
  var parts = [];
  Object.keys(state || {}).forEach(function (k) {
    var v = state[k];
    if (v === undefined || v === null) return;
    if (arrayKeys.indexOf(k) !== -1) {
      if (!Array.isArray(v) || !v.length) return;
      parts.push(k + '=' + v.map(encodeURIComponent).join(','));
    } else if (boolKeys.indexOf(k) !== -1) {
      parts.push(k + '=' + (v ? '1' : '0'));
    } else {
      if (v === '') return;
      parts.push(k + '=' + encodeURIComponent(String(v)));
    }
  });
  return parts.join('&');
}

function parseParams(qs, arrayKeys, boolKeys) {
  arrayKeys = arrayKeys || [];
  boolKeys = boolKeys || [];
  var out = {};
  var s = String(qs || '').replace(/^[?#]/, '');
  if (!s) return out;
  s.split('&').forEach(function (pair) {
    if (!pair) return;
    var idx = pair.indexOf('=');
    var k = idx === -1 ? pair : pair.slice(0, idx);
    var raw = idx === -1 ? '' : pair.slice(idx + 1);
    if (!k) return;
    if (arrayKeys.indexOf(k) !== -1) {
      out[k] = raw ? raw.split(',').map(function (x) { return decodeURIComponent(x); }) : [];
    } else if (boolKeys.indexOf(k) !== -1) {
      out[k] = raw === '1';
    } else {
      out[k] = decodeURIComponent(raw);
    }
  });
  return out;
}

var TrafficLib = {
  toNumberOrNull: toNumberOrNull,
  toDateOrNull: toDateOrNull,
  fmtCount: fmtCount,
  fmtPct: fmtPct,
  formatSource: formatSource,
  filterRows: filterRows,
  isLayerEmpty: isLayerEmpty,
  emptyStateFor: emptyStateFor,
  coverageMatches: coverageMatches,
  citationsPerMillion: citationsPerMillion,
  serializeParams: serializeParams,
  parseParams: parseParams
};

if (typeof module !== 'undefined' && module.exports) {
  module.exports = TrafficLib;
}
