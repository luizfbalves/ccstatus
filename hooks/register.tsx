import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Git, Limit, Snapshot } from '../types'

const snapshot = atom({ plugin: 'ccstatus', key: 'snapshot' } as const, null)

// tons médios/saturados (estilo tailwind-600) — contraste ok tanto em terminal
// claro quanto escuro; pastéis claros somem no claro, quase-pretos somem no escuro.
const LIME = '#4d7c0f'
const CYAN = '#0e7490'
const PINK = '#be185d'
const GREY = '#646978'
const DARK = '#808080'
const RED = '#b91c1c'
const ORANGE = '#c2410c'

const COST_CEILING_USD = 30
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']

const hex = (r: number, g: number, b: number) =>
  '#' + [r, g, b].map(c => Math.round(c).toString(16).padStart(2, '0')).join('')

// gradiente contínuo: 0% verde (21,128,61) → 50% âmbar (180,131,15) → 100% vermelho (185,28,28)
const pctColor = (pct: number) => {
  const p = Math.min(100, Math.max(0, pct))
  if (p <= 50) {
    const t = p / 50
    return hex(21 + t * (180 - 21), 128 + t * (131 - 128), 61 + t * (15 - 61))
  }
  const t = (p - 50) / 50
  return hex(180 + t * (185 - 180), 131 + t * (28 - 131), 15 + t * (28 - 15))
}

const fmtTokens = (n: number) =>
  n >= 1_000_000 ? `${(n / 1_000_000).toFixed(1)}M` : n >= 1000 ? `${Math.round(n / 1000)}k` : `${n}`

const fmtReset = (kind: string, iso: string | undefined) => {
  if (!iso) return undefined
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return undefined
  return kind === 'seven_day'
    ? WEEKDAYS[d.getDay()]
    : `${String(d.getHours()).padStart(2, '0')}h${String(d.getMinutes()).padStart(2, '0')}`
}

const basename = (path: string) => path.replace(/\/+$/, '').split('/').pop() || path

async function readGit($: EngineInterface, cwd: string): Promise<Git | null> {
  const { exitCode, stdout } = await $.process.run(
    ['git', '--no-optional-locks', 'status', '--porcelain=v2', '--branch'],
    { cwd, timeoutMs: 2000 },
  )
  if (exitCode !== 0) return null

  let branch = ''
  let oid = ''
  let ahead = 0
  let behind = 0
  let dirty = 0
  for (const line of stdout.split('\n')) {
    if (line.startsWith('# branch.head ')) branch = line.slice(14)
    else if (line.startsWith('# branch.oid ')) oid = line.slice(13, 20)
    else if (line.startsWith('# branch.ab ')) {
      const [a, b] = line.slice(12).split(' ')
      ahead = Number(a)
      behind = -Number(b)
    } else if (line && !line.startsWith('#')) dirty += 1
  }
  return { branch: branch === '(detached)' ? oid : branch, dirty, ahead, behind }
}

// effort só chega no turn.step; guardado aqui para o refresh ler
let effort: string | undefined

async function refresh($: EngineInterface) {
  const cwd = await $.session.cwd()
  const [git, model, usage] = await Promise.all([
    readGit($, cwd).catch(() => null),
    $.session.model(),
    $.session.usage(),
  ])
  const next: Snapshot = {
    dir: basename(cwd),
    git,
    model,
    effort,
    tokens: usage.context.tokens,
    window: usage.context.window,
    percent: usage.context.percent,
    costUsd: usage.cost?.usd,
    limits: usage.rateLimits
      .filter(l => l.kind === 'five_hour' || l.kind === 'seven_day')
      .map(l => ({ kind: l.kind, percent: l.percentUsed, resetsAt: l.resetsAt })),
  }
  await update($, snapshot, () => next)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await refresh($)
    return started
  })

  on('turn.step', async function* ($, e, next) {
    if (e.agentId === undefined && typeof e.effort === 'string') effort = e.effort
    return yield* next(e)
  })

  on('session.measure', async ($, e, next) => {
    const measured = await next(e)
    await refresh($)
    return measured
  })

  on('turn.complete', async ($, e, next) => {
    const completed = await next(e)
    if (e.agentId === undefined) await refresh($)
    return completed
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const s = await read($, snapshot)
    if (e.props.hasSurvey || s === null) return next(e)

    const { Box, Text } = $.ui.resolve(e)

    const bar = (pct: number, width: number) => {
      const filled = Math.min(width, Math.max(0, Math.round((pct * width) / 100)))
      return (
        <Text>
          <Text color={pctColor(pct)}>{'▓'.repeat(filled)}</Text>
          <Text color={DARK}>{'░'.repeat(width - filled)}</Text>
        </Text>
      )
    }

    const parts = [
      <Text bold color={CYAN}>{s.dir}</Text>,
    ]

    if (s.git) {
      const { branch, dirty, ahead, behind } = s.git
      parts.push(
        <Text>
          <Text color={PINK}>{branch}</Text>
          {dirty > 0 && <Text bold color={RED}> *{dirty}</Text>}
          {(ahead > 0 || behind > 0) && ' '}
          {ahead > 0 && <Text><Text bold color={LIME}>↑</Text>{ahead}</Text>}
          {behind > 0 && <Text><Text bold color={ORANGE}>↓</Text>{behind}</Text>}
        </Text>,
      )
    }

    if (s.model) {
      parts.push(
        <Text>
          <Text bold>{s.model}</Text>
          {s.effort && <Text dimColor color={GREY}> {s.effort}</Text>}
        </Text>,
      )
    }

    if (s.tokens !== undefined && s.window) {
      const pct = s.percent ?? (s.tokens * 100) / s.window
      parts.push(
        <Text>
          <Text color={GREY}>ctx </Text>
          {bar(pct, 10)}
          <Text color={pctColor(pct)}> {Math.round(pct)}%</Text>
          <Text dimColor color={GREY}> {fmtTokens(s.tokens)}/{fmtTokens(s.window)}</Text>
        </Text>,
      )
    }

    if (s.costUsd !== undefined) {
      const usd = s.costUsd
      parts.push(
        <Text bold color={pctColor((usd * 100) / COST_CEILING_USD)}>
          ${usd < 10 ? usd.toFixed(2) : usd.toFixed(1)}
        </Text>,
      )
    }

    const limits = (['five_hour', 'seven_day'] as const)
      .map(kind => s.limits.find((l: Limit) => l.kind === kind))
      .filter((l): l is Limit => l !== undefined)
    if (limits.length > 0) {
      parts.push(
        <Text>
          {limits.map((l, i) => {
            const reset = fmtReset(l.kind, l.resetsAt)
            return (
              <Text>
                {i > 0 && '  '}
                <Text color={GREY}>{l.kind === 'five_hour' ? '5h ' : '7d '}</Text>
                {bar(l.percent, 6)}
                <Text color={pctColor(l.percent)}> {Math.round(l.percent)}%</Text>
                {reset && <Text dimColor color={GREY}> {reset}</Text>}
              </Text>
            )
          })}
        </Text>,
      )
    }

    return (
      <Box flexDirection="column">
        {/* separador: linha longa quebrando dentro de uma Box de 1 linha, cortada na largura do terminal */}
        <Box height={1} overflow="hidden" marginBottom={1}>
          <Text color={DARK}>{'─'.repeat(500)}</Text>
        </Box>
        <Text wrap="truncate-end">
          {parts.map((part, i) => (
            <Text>
              {i > 0 && <Text color={DARK}> │ </Text>}
              {part}
            </Text>
          ))}
        </Text>
      </Box>
    )
  })
}
