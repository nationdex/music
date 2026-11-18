import assert from 'node:assert/strict';
import { test } from 'node:test';
import { parseAudiusSearch } from '../../site/assets/js/sources.js';

test('Audius rows get an au: id and a same-origin stream URL; locked tracks are dropped', () => {
  const rows = parseAudiusSearch(
    {
      data: [
        { id: 'vZJJz', title: 'A', user: { name: 'Chan' }, artwork: { '480x480': 'https://a/b.jpg' }, duration: 190, is_streamable: true },
        { id: 'zz', title: 'locked', access: { stream: false } }
      ]
    },
    'http://h'
  );
  assert.equal(rows.length, 1);
  assert.equal(rows[0].id, 'au:vZJJz');
  assert.equal(rows[0].channel, 'Chan');
  assert.equal(rows[0].artwork, 'https://a/b.jpg');
  assert.equal(rows[0].stream, 'http://h/up/audius/v1/tracks/vZJJz/stream');
  assert.deepEqual(parseAudiusSearch(null), []);
});
