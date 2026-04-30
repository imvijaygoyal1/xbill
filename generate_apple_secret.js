#!/usr/bin/env node
// Generates the Apple client secret JWT required by Supabase.
// Run: node generate_apple_secret.js
// Paste the output into Supabase → Auth → Providers → Apple → Secret Key.

const crypto = require('crypto');
const fs = require('fs');

// ── Fill these in ──────────────────────────────────────────────
const TEAM_ID   = '7B5U5LACV3';
const KEY_ID    = 'F4377VXK5F';
const CLIENT_ID = 'com.vijaygoyal.xbill';
const KEY_FILE  = '/Users/vijaygoyal/Downloads/AuthKey_F4377VXK5F.p8';
// ──────────────────────────────────────────────────────────────

if (TEAM_ID === 'YOUR_TEAM_ID' || KEY_ID === 'YOUR_KEY_ID' || KEY_FILE.includes('XXXXXXXXXX')) {
    console.error('ERROR: Fill in TEAM_ID, KEY_ID, and KEY_FILE before running.');
    process.exit(1);
}

const privateKey = fs.readFileSync(KEY_FILE, 'utf8');
const now = Math.floor(Date.now() / 1000);
const exp = now + 15777000; // 6 months (Apple's maximum)

const header  = Buffer.from(JSON.stringify({ alg: 'ES256', kid: KEY_ID })).toString('base64url');
const payload = Buffer.from(JSON.stringify({
    iss: TEAM_ID,
    iat: now,
    exp,
    aud: 'https://appleid.apple.com',
    sub: CLIENT_ID,
})).toString('base64url');

const signingInput = `${header}.${payload}`;
const sign = crypto.createSign('SHA256');
sign.update(signingInput);
// ieee-p1363 gives raw r||s format required by JWT (not DER)
const signature = sign.sign({ key: privateKey, dsaEncoding: 'ieee-p1363' }).toString('base64url');

const jwt = `${signingInput}.${signature}`;
console.log('\n── Apple Client Secret JWT ──────────────────────────────────');
console.log(jwt);
console.log('─────────────────────────────────────────────────────────────');
console.log(`\nExpires: ${new Date((exp) * 1000).toDateString()} — set a reminder to regenerate before then.\n`);
