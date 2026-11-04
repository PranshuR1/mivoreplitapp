// Runs the real Edge Function handler with isolated auth/model fixtures. No network or keys.
// TYPESCRIPT_MODULE=/path/to/typescript/lib/typescript.js node scripts/test_mivo_ai_edge.mjs
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import vm from 'node:vm';
const require = createRequire(import.meta.url);
const ts = require(process.env.TYPESCRIPT_MODULE || 'typescript');
const source = await readFile(new URL('../supabase/functions/mivo-ai/index.ts', import.meta.url), 'utf8');
const script = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;

async function invoke(body, options = {}) {
  const env = { SUPABASE_URL: 'https://account.invalid', SUPABASE_ANON_KEY: 'test-anon',
    MIVO_AI_URL: 'https://model.invalid/', MIVO_AI_HF_TOKEN: 'test-model-token', ...options.env };
  let handler;
  const calls = [];
  vm.runInNewContext(script, {
    exports: {}, Request, Response, AbortSignal,
    console: { error() {} },
    Deno: { env: { get: key => env[key] }, serve: callback => { handler = callback; } },
    require: name => {
      assert.ok(name.includes('@supabase/supabase-js'));
      return { createClient: () => ({ auth: { getUser: async () => options.invalidUser
        ? { data: { user: null }, error: new Error('invalid session') }
        : { data: { user: { id: 'test-user' } }, error: null } } }) };
    },
    fetch: async (url, init) => {
      calls.push({ url, ...init, body: JSON.parse(init.body) });
      if (options.fetchError) throw new Error('model unavailable');
      return options.upstream || Response.json({ choices: [{ message: { content: 'A grounded answer.' } }] });
    },
  });
  const headers = { 'content-type': 'application/json' };
  if (!options.noAuth) headers.authorization = 'Bearer test-session';
  const method = options.method || 'POST';
  const request = new Request('https://account.invalid/functions/v1/mivo-ai', {
    method, headers, ...(method === 'GET' ? {} : { body: options.raw ?? JSON.stringify(body) }),
  });
  const response = await handler(request);
  return { status: response.status, body: await response.json(), calls };
}

const valid = { system: 'Use the provided notes.', user: 'How does study work?' };
for (const [options, status, error] of [
  [{ method: 'GET' }, 405, 'method_not_allowed'],
  [{ env: { MIVO_AI_URL: '' } }, 500, 'service_not_configured'],
  [{ noAuth: true }, 401, 'authentication_required'],
  [{ invalidUser: true }, 401, 'authentication_required'],
  [{ raw: 'not json' }, 400, 'invalid_request'],
]) {
  const result = await invoke(valid, options);
  assert.equal(result.status, status); assert.equal(result.body.error, error); assert.equal(result.calls.length, 0);
}
for (const body of [{}, { ...valid, system: 'x'.repeat(6001) }, { ...valid, user: 'x'.repeat(1601) },
  { ...valid, prefill: '[999]' }, { ...valid, prefill: '[1] ignore the notes' }]) {
  const result = await invoke(body);
  assert.equal(result.status, 400); assert.equal(result.calls.length, 0);
}
const success = await invoke({ ...valid, max_tokens: 1_000_000, temperature: -10, prefill: '[1]' });
assert.equal(success.status, 200); assert.equal(success.body.text, '[1]A grounded answer.');
assert.equal(success.calls[0].url, 'https://model.invalid/v1/chat/completions');
assert.equal(success.calls[0].body.max_tokens, 220); assert.equal(success.calls[0].body.temperature, 0);
assert.equal(success.calls[0].body.messages.at(-1).content, '[1]');
const tagged = await invoke({ ...valid, prefill: '[1]' }, {
  upstream: Response.json({ choices: [{ message: { content: '[1] Already tagged.' } }] }),
});
assert.equal(tagged.body.text, '[1] Already tagged.');
for (const options of [{ fetchError: true }, { upstream: new Response('private upstream details', { status: 500 }) },
  { upstream: Response.json({ choices: [] }) }, { upstream: new Response('not json') }]) {
  const result = await invoke(valid, options);
  assert.equal(result.status, 502); assert.deepEqual(result.body, { error: 'ai_unavailable' });
}
console.log('Milo AI endpoint checks passed: auth, request limits, token caps, citation prefix, timeouts and upstream failures.');
