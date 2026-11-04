// Run with: npm install --prefix /tmp/mivo-study-db @electric-sql/pglite
// PGLITE_MODULE=/tmp/mivo-study-db/node_modules/@electric-sql/pglite/dist/index.js node scripts/test_linked_study_db.mjs
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
const user = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
const session = '33333333-3333-4333-8333-333333333333';
const desktop = '44444444-4444-4444-8444-444444444444';
const phone = '55555555-5555-4555-8555-555555555555';
await db.exec(`create role anon; create role authenticated; create schema auth;
create table auth.users(id uuid primary key, email text, raw_user_meta_data jsonb default '{}');
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
insert into auth.users(id) values ('${user}'), ('${other}');
grant usage on schema auth to authenticated, anon; grant execute on function auth.uid() to authenticated, anon;`);
for (const file of ['20261029120000_study_sync_and_rooms.sql', '20261101120000_linked_computer_study.sql']) {
    await db.exec(await readFile(new URL(`../supabase/migrations/${file}`, import.meta.url), 'utf8'));
}
const uid = async id => db.exec(`select set_config('test.uid','${id}',false)`);
const rpc = async (name, args = '') => (await db.query(`select public.${name}(${args}) as value`)).rows[0].value;
const ageTick = async seconds => db.exec(`update linked_study_sessions set last_seen_at = now() - interval '${seconds} seconds' where id = '${session}'`);
await uid('');
await assert.rejects(rpc('my_linked_study'), /authentication_required/);
await uid(user);
await db.exec('set role authenticated');
await assert.rejects(db.query('select * from linked_study_sessions'), /permission denied/);
await assert.rejects(rpc('_linked_study_tick', `'${session}'`), /permission denied/);
let result = await rpc('request_linked_study', `'${session}', '  Chapter   4  '`);
assert.equal(result.status, 'waiting'); assert.equal(result.task, 'Chapter 4');
assert.equal((await rpc('request_linked_study', `'${other}', 'Different task'`)).id, session);
await uid(other);
assert.equal(await rpc('my_linked_study'), null);
await assert.rejects(rpc('connect_linked_study', `'${session}', '${desktop}'`), /session_not_found/);
await assert.rejects(rpc('finish_linked_study', `'${session}'`), /session_not_found/);
await uid(user);
result = await rpc('connect_linked_study', `'${session}', '${desktop}'`);
assert.equal(result.status, 'active'); assert.equal(result.focusedSeconds, 0);
await assert.rejects(rpc('connect_linked_study', `'${session}', '${other}'`), /computer_already_connected/);
await assert.rejects(rpc('ping_linked_study', `'${session}', '${other}', 'focus'`), /wrong_computer/);
await rpc('ping_linked_study', `'${session}', '${desktop}', 'focus'`);
await db.exec('reset role'); await ageTick(10); await db.exec('set role authenticated');
result = await rpc('ping_linked_study', `'${session}', '${desktop}', 'drift'`);
assert.ok(result.focusedSeconds >= 10 && result.focusedSeconds <= 11);
await db.exec('reset role'); await ageTick(120); await db.exec('set role authenticated');
const before = result.focusedSeconds;
result = await rpc('ping_linked_study', `'${session}', '${desktop}', 'focus'`);
assert.equal(result.focusedSeconds, before); assert.equal(result.distractedSeconds, 0, 'no offline backfill');
await assert.rejects(rpc('ping_linked_study', `'${session}', '${desktop}', 'made-up'`), /invalid_activity/);
// Seed elapsed focus to exercise a realistic receipt and reward, without waiting ten minutes.
await db.exec(`reset role; update linked_study_sessions set started_at = now() - interval '900 seconds',
 focused_seconds = 600, distracted_seconds = 200, away_seconds = 100, last_seen_at = now() - interval '120 seconds'
 where id = '${session}'; set role authenticated;`);
result = await rpc('finish_linked_study', `'${session}'`);
assert.equal(result.status, 'finished'); assert.equal(result.focusedSeconds, 600);
await rpc('finish_linked_study', `'${session}'`);
let history = await rpc('my_study_sessions');
assert.equal(history.length, 1); assert.equal(history[0].source, 'desktop'); assert.equal(history[0].focused_seconds, 600);
const rewards = await rpc('linked_study_rewards', `'${phone}', false, 'America/New_York'`);
assert.equal(rewards.length, 1); assert.equal(rewards[0].scrollSeconds, 200);
assert.deepEqual(await rpc('linked_study_rewards', `'${phone}', false, 'America/New_York'`), rewards);
assert.deepEqual(await rpc('linked_study_rewards', `'${other}', true, 'America/New_York'`), []);
assert.equal((await rpc('ping_linked_study', `'${session}', '${desktop}', 'focus'`)).focusedSeconds, 600);
// A request cancelled before desktop connection creates no study record.
await rpc('request_linked_study', `'${other}', 'Never connected'`);
assert.equal((await rpc('finish_linked_study', `'${other}'`)).status, 'cancelled');
assert.equal((await rpc('my_study_sessions')).length, 1);
// Expired trial locks rewards; Plus can unlock on the same day.
await db.exec(`reset role; update study_sessions set started_at = now() - interval '9 days', ended_at = now() - interval '9 days' + interval '900 seconds' where id = '${session}'; set role authenticated;`);
await rpc('request_linked_study', `'${phone}', 'After trial'`);
await rpc('connect_linked_study', `'${phone}', '${desktop}'`);
await db.exec(`reset role; update linked_study_sessions set started_at = now() - interval '600 seconds', focused_seconds = 600,
 last_seen_at = now() - interval '120 seconds' where id = '${phone}'; set role authenticated;`);
await rpc('finish_linked_study', `'${phone}'`);
assert.equal((await rpc('linked_study_rewards', `'${phone}', false, 'America/New_York'`)).length, 1);
assert.equal((await rpc('linked_study_rewards', `'${phone}', true, 'America/New_York'`)).length, 2);
await uid(other);
assert.deepEqual(await rpc('linked_study_rewards', `'${phone}', true, 'America/New_York'`), []);
await db.close();
console.log('Linked study database checks passed: migrations, permissions, isolation, reconnect, focused totals, finish, cancellation, reward replay and trial.');
