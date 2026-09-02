// Run with: node --test tools/traffic-lib.test.js
const test = require('node:test');
const assert = require('node:assert/strict');
const T = require('./traffic-lib.js');

test('toNumberOrNull', () => {
  assert.equal(T.toNumberOrNull('42'), 42);
  assert.equal(T.toNumberOrNull('  3.5 '), 3.5);
  assert.equal(T.toNumberOrNull('0'), 0);
  assert.equal(T.toNumberOrNull(''), null);
  assert.equal(T.toNumberOrNull(null), null);
  assert.equal(T.toNumberOrNull(undefined), null);
  assert.equal(T.toNumberOrNull('not a number'), null);
  assert.equal(T.toNumberOrNull('12abc'), null);
});

test('toDateOrNull', () => {
  assert.ok(T.toDateOrNull('2024-05-01') instanceof Date);
  assert.equal(T.toDateOrNull(''), null);
  assert.equal(T.toDateOrNull(null), null);
  assert.equal(T.toDateOrNull('not a date'), null);
});

test('fmtCount / fmtPct / formatSource treat 0 as a real value, not missing', () => {
  assert.equal(T.fmtCount(0), '0');
  assert.equal(T.fmtCount('0'), '0');
  assert.equal(T.fmtCount(null), 'Not available');
  assert.equal(T.fmtCount(undefined), 'Not available');
  assert.equal(T.fmtCount(''), 'Not available');

  assert.equal(T.fmtPct(0), '0%');
  assert.equal(T.fmtPct(null), 'Not available');

  assert.equal(T.formatSource('turnpike.wv.gov'), 'turnpike.wv.gov');
  assert.equal(T.formatSource(''), 'Not available');
  assert.equal(T.formatSource(null), 'Not available');
  assert.equal(T.formatSource(undefined), 'Not available');
  assert.equal(T.formatSource('   '), 'Not available');
});

test('filterRows: empty filterState is passthrough', () => {
  const rows = [{ id: 1, route: 'I-77' }, { id: 2, route: 'I-64' }];
  assert.deepEqual(T.filterRows(rows, {}), rows);
});

test('filterRows: single facet with one active value', () => {
  const rows = [{ id: 1, route: 'I-77' }, { id: 2, route: 'I-64' }, { id: 3, route: 'I-77' }];
  const out = T.filterRows(rows, { route: { 'I-77': true } });
  assert.deepEqual(out.map(r => r.id), [1, 3]);
});

test('filterRows: multi-facet AND logic', () => {
  const rows = [
    { id: 1, route: 'I-77', county: 'Raleigh' },
    { id: 2, route: 'I-77', county: 'Fayette' },
    { id: 3, route: 'I-64', county: 'Raleigh' }
  ];
  const out = T.filterRows(rows, { route: { 'I-77': true }, county: { Raleigh: true } });
  assert.deepEqual(out.map(r => r.id), [1]);
});

test('filterRows: unknown facet key not present on rows filters everything out if activated', () => {
  const rows = [{ id: 1, route: 'I-77' }];
  const out = T.filterRows(rows, { nope: { x: true } });
  assert.deepEqual(out, []);
});

test('isLayerEmpty / emptyStateFor', () => {
  assert.equal(T.isLayerEmpty({ hasData: true }), false);
  assert.equal(T.isLayerEmpty({ hasData: false }), true);
  assert.equal(T.isLayerEmpty(null), true);

  const full = T.emptyStateFor({ hasData: true });
  assert.equal(full.empty, false);

  const empty = T.emptyStateFor({ hasData: false, label: 'AADT', unavailableReason: 'No public export found.' });
  assert.equal(empty.empty, true);
  assert.match(empty.message, /AADT/);
  assert.equal(empty.reason, 'No public export found.');

  const noMeta = T.emptyStateFor(null);
  assert.equal(noMeta.empty, true);
  assert.equal(noMeta.reason, 'Layer not configured.');
});

test('coverageMatches: identical geo + identical period matches', () => {
  const a = { geo: 'Kanawha County', periodStart: '2024-01-01', periodEnd: '2024-01-31' };
  const b = { geo: '  kanawha county  ', periodStart: '2024-01-01', periodEnd: '2024-01-31' };
  assert.equal(T.coverageMatches(a, b), true);
});

test('coverageMatches: mismatched geography does not match', () => {
  const a = { geo: 'Kanawha County', periodStart: '2024-01-01', periodEnd: '2024-01-31' };
  const b = { geo: 'Fayette County', periodStart: '2024-01-01', periodEnd: '2024-01-31' };
  assert.equal(T.coverageMatches(a, b), false);
});

test('coverageMatches: mismatched period does not match', () => {
  const a = { geo: 'Kanawha County', periodStart: '2024-01-01', periodEnd: '2024-01-31' };
  const b = { geo: 'Kanawha County', periodStart: '2024-02-01', periodEnd: '2024-02-29' };
  assert.equal(T.coverageMatches(a, b), false);
});

test('coverageMatches: missing coverage objects do not match', () => {
  assert.equal(T.coverageMatches(null, { geo: 'x', periodStart: '2024-01-01', periodEnd: '2024-01-31' }), false);
  assert.equal(T.coverageMatches({ geo: 'x' }, { geo: 'x' }), false);
});

test('citationsPerMillion: matching coverage computes the rate', () => {
  const cov = { geo: 'Raleigh County', periodStart: '2024-01-01', periodEnd: '2024-12-31' };
  const rate = T.citationsPerMillion(150, 300000, cov, cov);
  assert.equal(rate, 500);
});

test('citationsPerMillion: mismatched coverage returns null, not a fabricated number', () => {
  const covA = { geo: 'Raleigh County', periodStart: '2024-01-01', periodEnd: '2024-12-31' };
  const covB = { geo: 'Fayette County', periodStart: '2024-01-01', periodEnd: '2024-12-31' };
  assert.equal(T.citationsPerMillion(150, 300000, covA, covB), null);
});

test('citationsPerMillion: zero or missing exposure is guarded', () => {
  const cov = { geo: 'x', periodStart: '2024-01-01', periodEnd: '2024-12-31' };
  assert.equal(T.citationsPerMillion(150, 0, cov, cov), null);
  assert.equal(T.citationsPerMillion(150, null, cov, cov), null);
  assert.equal(T.citationsPerMillion(null, 300000, cov, cov), null);
});

test('serializeParams / parseParams round-trip: scalars, booleans, arrays', () => {
  const arrayKeys = ['layers', 'route'];
  const boolKeys = ['traffic', 'toll'];
  const state = {
    traffic: true,
    toll: false,
    layers: ['count', 'wim'],
    route: ['I-77', 'I-64'],
    year: '2024'
  };
  const qs = T.serializeParams(state, arrayKeys, boolKeys);
  const parsed = T.parseParams(qs, arrayKeys, boolKeys);
  assert.deepEqual(parsed, state);
});

test('serializeParams / parseParams round-trip: empty array and empty string are omitted', () => {
  const arrayKeys = ['layers'];
  const boolKeys = ['traffic'];
  const qs = T.serializeParams({ traffic: true, layers: [], year: '' }, arrayKeys, boolKeys);
  assert.equal(qs.includes('layers'), false);
  assert.equal(qs.includes('year'), false);
});

test('serializeParams / parseParams round-trip: values needing URI-encoding', () => {
  const arrayKeys = ['route'];
  const boolKeys = [];
  const state = { route: ['Toll Plaza A, Ghent', 'US 19/I-79'] };
  const qs = T.serializeParams(state, arrayKeys, boolKeys);
  const parsed = T.parseParams(qs, arrayKeys, boolKeys);
  assert.deepEqual(parsed.route, state.route);
});

test('parseParams: leading "?" is tolerated', () => {
  const parsed = T.parseParams('?traffic=1&year=2024', [], ['traffic']);
  assert.equal(parsed.traffic, true);
  assert.equal(parsed.year, '2024');
});
