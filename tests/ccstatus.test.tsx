import { expect, test } from 'claude-code/testing'

const BAND = {
  plugin: 'ccstatus',
  component: 'AbovePrompt',
  props: { hasSurvey: false, isWorking: false, maxRows: 10 },
} as const

const SNAPSHOT = {
  dir: 'orulpro',
  git: { branch: 'main', dirty: 3, ahead: 1, behind: 0 },
  model: 'Sonnet 5',
  effort: 'high',
  tokens: 550_000,
  window: 1_000_000,
  percent: 55,
  costUsd: 1.95,
  limits: [{ kind: 'five_hour', percent: 55 }, { kind: 'seven_day', percent: 26 }],
}

test('the band draws every section of the snapshot', async ($, on) => {
  on('state.get', () => ({ value: { value: SNAPSHOT, version: 1 } }))

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...BAND, surface })
    const line = (await ui.find({ type: 'Text', text: /orulpro/ }))?.text ?? ''

    expect(line).toContain('main *3 ↑1')
    expect(line).toContain('Sonnet 5 high')
    expect(line).toContain('ctx ▓▓▓▓▓▓░░░░ 55% 550k/1.0M')
    expect(line).toContain('$1.95')
    expect(line).toContain('5h ▓▓▓░░░ 55%')
    expect(line).toContain('7d ▓▓░░░░ 26%')
    expect(await ui.find({ type: 'Text', text: /^─+$/ })).toBeDefined()
    await ui.unmount()
  }
})

test('the clear button runs /clear', async ($, on) => {
  on('state.get', () => ({ value: { value: SNAPSHOT, version: 1 } }))
  const ran: string[] = []
  on('command.run', (_, e) => {
    ran.push(e.command)
    return { text: '' }
  })

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  await ui.press({ key: 'clear' })
  expect(ran).toEqual(['clear'])
  await ui.unmount()
})

test('with no snapshot the band is left to the engine', async ($, on) => {
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })

  const ui = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await ui.find({ type: 'Text' }))?.text).toBe('engine')
  await ui.unmount()
})
