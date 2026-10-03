// npx tsx test/prove-schema.ts
// For every constraint schema.test.ts relies on: drop just that one, run the
// file, and expect it to fail. A test that still passes proves nothing.
import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

const source = readFileSync('test/schema.test.ts', 'utf8')
const names = [...new Set([...source.matchAll(/refusedBy\('([a-z_]+)'\)/g)].map((m) => m[1]!))]
let missed = 0
for (const name of names) {
  const run = spawnSync(process.execPath, ['--import', 'tsx', '--test', 'test/schema.test.ts'], {
    env: { ...process.env, SCHEMA_DROP: name },
    encoding: 'utf8',
  })
  const caught = run.status !== 0 && !/No constraint named/.test(run.stdout + run.stderr)
  if (!caught) missed += 1
  console.log(`${caught ? 'caught    ' : 'NOT CAUGHT'}  ${name}`)
}
console.log(`\n${names.length - missed} of ${names.length} constraints proved.`)
process.exitCode = missed === 0 ? 0 : 1
