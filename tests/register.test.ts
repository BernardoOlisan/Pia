import { expect, test } from 'claude-code/testing'

const WORK = {
  dir: '/p/.pia/work/002-borescope-reborn', id: '002-borescope-reborn', kind: 'repo',
  title: 'Rebuild Borescope', phase: 'test', round: 3, mode: 'in-the-loop', lead_session: 'S1',
  now: { doing: 'implementer-002-3-1 building round 3', updated: '2026-10-17 12:00' },
  agents: [{ name: 'implementer-002-3-1', doing: 'step 2', updated: '2026-10-17 12:00' }],
}
const STATUS = { holdingAwake: true, installed: true, lidClosed: true, battery: 62, onAC: false, network: 'hotspot' }

// Everything the mod reaches outside itself, answered as a lead session of work 002 would see it.
function world(on: Parameters<Parameters<typeof test>[1] extends infer B ? B extends (...a: infer A) => unknown ? (...a: A) => unknown : never : never>[1], session = 'S1') {
  on('session.id', async () => ({ value: session }))
  on('session.cwd', async () => ({ value: '/p' }))
  on('env.get', async () => ({ value: '/Users/someone' }))
  on('store.get', async () => ({ value: undefined }))
  on('store.set', async () => ({ value: undefined }))
  on('fs.exists', async () => ({ value: true }))
  on('clock.every', async () => ({ value: { id: 't' } }))
  on('clock.now', async () => ({ value: Date.now() }))
  on('session.start', async () => ({ cwd: '/p' }))
  on('fs.read', async (_$: unknown, e: { path: string }) => {
    if (e.path.endsWith('status.json')) return { value: JSON.stringify(STATUS) }
    if (e.path.endsWith('config.json')) return { value: '{"language":"es"}' }
    throw new Error('no such file')
  })
  on('process.run', async () => ({ value: { exitCode: 0, stdout: JSON.stringify(WORK) + '\n', stderr: '' } }))
  on('agent.list', async () => ({
    value: [{ id: 'a1', teammateId: 'implementer-002-3-1@pia', status: 'running', description: '', type: 'teammate' }],
  }))
}

const BAND = {
  component: 'AbovePrompt' as const,
  props: { hasSurvey: false, isWorking: true, maxRows: 20, bodyColumns: 100 } as never,
}

test('a /pia: command typed inside a message reaches Claude as context', async ($, on) => {
  world(on as never)
  let context: readonly string[] | undefined
  on('prompt.submit', async (_$, e) => {
    context = e.context
    return { text: e.text }
  })
  await $.prompt.submit({ text: 'va, buenas noches /pia:out-of-the-loop' })
  expect((context ?? []).join(' ')).toContain('skills/out-of-the-loop/SKILL.md')
})

test('a message with no /pia: command is left alone', async ($, on) => {
  world(on as never)
  let context: readonly string[] | undefined = ['untouched']
  on('prompt.submit', async (_$, e) => {
    context = e.context
    return { text: e.text }
  })
  await $.prompt.submit({ text: 'el sidebar no guarda su lugar' })
  expect(context ?? []).toEqual([])
})

test('the band shows the work this session leads, its round, its teammate and the lid-closed hold', async ($, on) => {
  world(on as never)
  on('ui.render', async ($, e) => ($.ui.resolve(e) as { Box: (p: object) => never }).Box({}))
  await ($ as unknown as { session: { start: (e: object) => Promise<unknown> } }).session.start({ cwd: '/p' })
  await new Promise(resolve => setTimeout(resolve, 100))
  const ui = await $.ui.mount({ plugin: 'pia', surface: 'terminal', ...BAND })
  expect(await ui.find({ type: 'Text', text: /PIA lead 002/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /ronda 3/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /implementer-002-3-1 trabajando/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /tapa cerrada/ })).toBeDefined()
  expect(await ui.find({ key: 'owl' })).toBeDefined()
  await ui.unmount()
})

test('no band in a session that leads no work', async ($, on) => {
  world(on as never, 'someone-else')
  on('ui.render', async ($, e) => ($.ui.resolve(e) as { Box: (p: object) => never }).Box({}))
  const ui = await $.ui.mount({ plugin: 'pia', surface: 'terminal', ...BAND })
  await new Promise(resolve => setTimeout(resolve, 100))
  expect(await ui.find({ type: 'Text', text: /PIA lead/ })).toBeUndefined()
  await ui.unmount()
})
