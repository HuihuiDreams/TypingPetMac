import assert from 'node:assert/strict';
import { sanitizeCapture } from '../src/analytics-policy.ts';

const sample = {
  uuid: '019a0000-0000-7000-8000-000000000001', event: '$pageview',
  $set: { email: 'private@example.test' }, $set_once: { initial_url: 'private' },
  properties: {
    token: 'project-token', distinct_id: 'anonymous-visitor', locale: 'ko',
    $current_url: 'https://typing-pet.miel.ing/ko/?email=private@example.test#private',
    $referrer: 'https://example.test/private-path?token=private#private',
    $elements: [{ value: 'typed text' }], input: 'typed text', $initial_current_url: 'private',
  },
};
const clean = sanitizeCapture(sample);
assert.equal(clean.properties.$current_url, 'https://typing-pet.miel.ing/ko/');
assert.equal(clean.properties.$referrer, 'https://example.test');
assert.equal(clean.properties.token, 'project-token');
assert.equal(clean.properties.distinct_id, 'anonymous-visitor');
assert.ok(!JSON.stringify(clean).includes('private'));
assert.ok(!JSON.stringify(clean).includes('typed text'));
for (const event of ['$autocapture', '$snapshot', '$exception', '$identify', 'unplanned_event']) {
  assert.equal(sanitizeCapture({ ...sample, event }), null, event);
}
for (const event of ['download_clicked', 'homebrew_copied', 'language_changed']) {
  assert.equal(sanitizeCapture({ ...sample, event }).event, event);
}
console.log('Verified analytics event allowlist and removal of input, person, and private URL data.');
