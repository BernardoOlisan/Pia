import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { AwakeView, BandWork, Mate } from '../types'

// PIA's mod: what a lead session shows and watches, inside Claude Code.
//
// - The band above the prompt: the owl, the works this session leads (phase, round, what is happening
//   now, who is working) and whether PIA Awake is holding the Mac. Only in a PIA lead session.
// - A watchdog: an implementer that stops logging for 15 minutes is reported to the lead and, while the
//   human is in the loop, to the human with a notification. The lead used to report silence as work.
// - `/pia:x` typed inside a message ("buenas noches /pia:out-of-the-loop") runs that command too.

const works = atom({ plugin: 'pia', key: 'works' } as const, [] as BandWork[])
const awake = atom({ plugin: 'pia', key: 'awake' } as const, null as AwakeView | null)
const mates = atom({ plugin: 'pia', key: 'mates' } as const, [] as Mate[])
const collapsed = atom({ plugin: 'pia', key: 'collapsed' } as const, false)
const spanish = atom({ plugin: 'pia', key: 'spanish' } as const, false)

// The README's owl, drawn by hand at 8×8 so the band stays four rows tall: ears, amber eyes with their
// pupils, the beak, the light belly, the wing line and the feet. Two pixels per terminal cell: ▀ paints
// the top one in the foreground and the bottom one behind it; ▄ when only the bottom one is there; a
// space when neither. The outline is lighter than the README's so it reads on a dark terminal.
const OWL = [
  'DD....DD',
  'DBBBBBBD',
  'BEEBBEEB',
  'BEPBBPEB',
  'BBBKKBBB',
  'BLLLLLLB',
  'BWLLLLWB',
  '.K....K.',
]
const PALETTE: Record<string, number> = {
  D: 0x6b6fd6, B: 0x3d3f9e, E: 0xffd166, P: 0x1a1b3a, K: 0xff8c42, L: 0x8d92f0, W: 0x2c2e78,
}
const DEFAULT = 0x01000000
const UPPER_HALF = 0x2580
const LOWER_HALF = 0x2584
const SPACE = 0x20

function base64(bytes: Uint8Array): string {
  const abc = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  let out = ''
  for (let i = 0; i < bytes.length; i += 3) {
    const n = ((bytes[i] ?? 0) << 16) | ((bytes[i + 1] ?? 0) << 8) | (bytes[i + 2] ?? 0)
    out += abc.charAt((n >> 18) & 63) + abc.charAt((n >> 12) & 63)
    out += i + 1 < bytes.length ? abc.charAt((n >> 6) & 63) : '='
    out += i + 2 < bytes.length ? abc.charAt(n & 63) : '='
  }
  return out
}

const OWL_COLUMNS = 8
const OWL_ROWS = 4

function owlCells(): string {
  const words = new Uint32Array(OWL_COLUMNS * OWL_ROWS * 3)
  let k = 0
  for (let row = 0; row < OWL_ROWS * 2; row += 2) {
    for (let col = 0; col < OWL_COLUMNS; col++) {
      const top = PALETTE[OWL[row]?.charAt(col) ?? '.']
      const bottom = PALETTE[OWL[row + 1]?.charAt(col) ?? '.']
      if (top !== undefined) {
        words[k++] = UPPER_HALF
        words[k++] = top
        words[k++] = bottom ?? DEFAULT
      } else if (bottom !== undefined) {
        words[k++] = LOWER_HALF
        words[k++] = bottom
        words[k++] = DEFAULT
      } else {
        words[k++] = SPACE
        words[k++] = DEFAULT
        words[k++] = DEFAULT
      }
    }
  }
  return base64(new Uint8Array(words.buffer))
}
const OWL_CELLS = owlCells()

const WORDS = {
  es: {
    round: 'ronda', working: 'trabajando', idle: 'sin moverse', waiting: 'esperando',
    holding: 'despierto', lid: 'tapa cerrada', canSleep: 'puede dormir', notInstalled: 'tapa cerrada: no instalado',
    charging: 'cargando', battery: 'batería', hotspot: 'hotspot iPhone', wifi: 'Wi-Fi', offline: 'sin red',
    hide: 'Ocultar', show: 'PIA',
  },
  en: {
    round: 'round', working: 'working', idle: 'not moving', waiting: 'waiting',
    holding: 'awake', lid: 'lid closed', canSleep: 'may sleep', notInstalled: 'lid closed: not installed',
    charging: 'charging', battery: 'battery', hotspot: 'iPhone hotspot', wifi: 'Wi-Fi', offline: 'offline',
    hide: 'Hide', show: 'PIA',
  },
}

const STALL_MINUTES = 15

function minutesSince(stamp: string, now: number): number | null {
  const m = /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})/.exec(stamp)
  if (!m) return null
  const [, y, mo, d, h, mi] = m.map(Number) as number[]
  const then = new Date(y ?? 0, (mo ?? 1) - 1, d ?? 1, h ?? 0, mi ?? 0).getTime()
  return (now - then) / 60000
}

function workLabel(w: BandWork): string {
  const number = w.id.split('-')[0]
  return w.kind === 'disposable' ? `PIA disposable ${number}` : `PIA lead ${number}`
}

let me = ''
let root = ''
let home = ''
const warned = new Map<string, number>()
let titled = ''

type Dollar = EngineInterface

async function refresh($: Dollar) {
    try {
      const cwd = await $.session.cwd()
      const r = await $.process.run(['python3', `${root}/scripts/works.py`, 'list', cwd], { timeoutMs: 8000 })
      const mine: BandWork[] = []
      for (const line of r.stdout.split('\n')) {
        if (!line.trim()) continue
        const w = JSON.parse(line)
        if (w.lead_session !== me || w.phase === 'done' || !w.phase) continue
        mine.push({
          id: w.id, dir: w.dir, kind: w.kind, title: w.title, phase: w.phase, round: w.round ?? 0,
          mode: w.mode, doing: w.now?.doing ?? '', agents: w.agents ?? [],
        })
      }
      await update($, works, () => mine)

      // A new lead is named the moment its work exists, not at the next prompt (session-title.sh
      // covers starts and resumes). /rename is Claude Code's own; it runs once per name.
      // Only where someone looks at it: under claude -p a command's output replaces the run's result.
      const first = mine[0]
      if (first && titled !== workLabel(first) && (await $.session.surfaces()).length > 0) {
        titled = workLabel(first)
        await $.command.run({ command: 'rename', args: titled }).catch(() => undefined)
      }

      let view: AwakeView | null = null
      if (mine.length) {
        try {
          const s = JSON.parse(await $.fs.read(`${home}/Library/Application Support/PIA/awake/status.json`))
          view = {
            holding: !!s.holdingAwake, installed: !!s.installed, lidClosed: !!s.lidClosed,
            battery: s.battery ?? null, onAC: !!s.onAC, network: s.network ?? '',
          }
        } catch {
          view = null
        }
      }
      await update($, awake, () => view)

      const team = (await $.agent.list())
        .filter((a: { teammateId?: string; status: string }) => a.teammateId && !['completed', 'killed', 'failed'].includes(a.status))
        .map((a: { teammateId?: string; status: string }) => ({ name: (a.teammateId as string).split('@')[0], status: a.status }))
      await update($, mates, () => team)
    } catch {
      // A failed refresh keeps the last picture; the next one tries again.
    }
  }

async function watchdog($: Dollar) {
    const now = await $.clock.now()
    const led = await read($, works)
    const team = await read($, mates)
    for (const w of led) {
      if (w.phase !== 'implement' && w.phase !== 'test' && w.phase !== 'work') continue
      for (const mate of team) {
        if (!/^(implementer|helper)-/.test(mate.name)) continue
        const log = w.agents.find(a => a.name === mate.name)
        const quiet = log ? minutesSince(log.updated, now) : null
        if (quiet === null || quiet < STALL_MINUTES) continue
        const last = warned.get(mate.name) ?? 0
        if (now - last < 30 * 60000) continue
        warned.set(mate.name, now)
        const minutes = Math.round(quiet)
        const body = `${mate.name} lleva ${minutes} min sin registrar nada (${mate.status}).`
        void $.process.run(['python3', `${root}/scripts/notify.py`, w.dir, 'stalled', body], { timeoutMs: 15000 }).catch(() => {})
        void $.prompt.submit({
          text: `PIA watchdog: ${mate.name} (work ${w.id}) has logged nothing for ${minutes} minutes and is ${mate.status}. `
            + `Check its log and its processes now; if it is stuck, replace it with the next attempt (PIA.md → Team). `
            + `Log what you find with the log script, starting with "STALLED" if it really is.`,
        }).catch(() => {})
      }
    }
  }

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    me = await $.session.id()
    root = $.plugin.root
    home = (await $.env.get('HOME')) ?? ''
    try {
      const config = JSON.parse(await $.fs.read(`${home}/.pia/config.json`))
      await update($, spanish, () => String(config.language ?? 'en').toLowerCase().startsWith('es'))
    } catch {
      // No config: English, PIA's default.
    }
    const stored = await $.store.get('collapsed')
    if (typeof stored === 'boolean') await update($, collapsed, () => stored)
    void refresh($)
    $.clock.every(5000, () => { void refresh($) })
    $.clock.every(60000, () => { void watchdog($) })
    return next(e)
  })

  // A turn that created or resumed a work: draw it and name the session now, not five seconds later.
  on('turn.complete', async ($, e, next) => {
    await refresh($)
    return next(e)
  })

  // "/pia:x" in the middle of a message: the skill never loads that way, so say it to Claude.
  on('prompt.submit', async ($, e, next) => {
    if (e.command) return next(e)
    const m = /(?:^|\s)\/pia:([a-z][a-z-]*)\b([^\n]*)/.exec(e.text)
    if (!m || e.text.trimStart().startsWith('/pia:')) return next(e)
    const skill = m[1] ?? ''
    const rest = (m[2] ?? '').trim()
    const exists = await $.fs.exists(`${root}/skills/${skill}/SKILL.md`)
    if (!exists) return next(e)
    const note = `The human typed /pia:${skill} inside this message, where Claude Code does not run it. `
      + `Treat it as running that command: after the rest of the message, read ${root}/skills/${skill}/SKILL.md `
      + `and follow it${rest ? `, with the arguments "${rest}"` : ''}.`
    return next({ ...e, context: [...(e.context ?? []), note] })
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const led = await read($, works)
    if (!led.length || e.props.hasSurvey) return next(e)
    const t = (await read($, spanish)) ? WORDS.es : WORDS.en
    const a = await read($, awake)
    const team = await read($, mates)
    const small = await read($, collapsed)
    const ui = $.ui.resolve(e)
    const { Box, Text, Button } = ui
    const owl = e.surface === 'terminal' && 'Raster' in ui
      ? <ui.Raster key="owl" columns={OWL_COLUMNS} rows={OWL_ROWS} cells={OWL_CELLS} />
      : null

    const toggle = async () => {
      const flipped = !small
      await update($, collapsed, () => flipped)
      await $.store.set('collapsed', flipped)
    }

    const awakeText = !a ? '' : a.holding
      ? `${t.holding}${a.lidClosed ? ` · ${t.lid}` : ''}`
      : (a.installed ? t.canSleep : t.notInstalled)
    const powerText = !a || a.battery === null ? '' : `${a.onAC ? t.charging : t.battery} ${a.battery}%`
    const netText = !a ? '' : a.network === 'hotspot' ? t.hotspot : a.network === 'wifi' ? t.wifi : a.network === 'none' ? t.offline : ''
    const statusWord = (s: string) => s === 'running' ? t.working : s === 'idle' ? t.idle : s === 'waiting' ? t.waiting : s
    const statusColor = (s: string) => s === 'running' ? 'green' : s === 'idle' ? 'yellow' : 'gray'

    const lines = led.map(w => (
      <Box key={w.id} flexDirection="column">
        <Text wrap="truncate-end">
          <Text bold>{workLabel(w)}</Text>
          <Text dimColor>{` · ${w.phase}${w.round ? ` · ${t.round} ${w.round}` : ''} · ${w.mode}`}</Text>
        </Text>
        {small ? null : <Text dimColor wrap="truncate-end">{w.doing}</Text>}
      </Box>
    ))
    const teamLine = team.length ? (
      <Text wrap="truncate-end">
        {team.map((m, i) => (
          <Text key={m.name}>
            {i ? <Text dimColor>{' · '}</Text> : null}
            <Text color={statusColor(m.status)}>{`${m.name} ${statusWord(m.status)}`}</Text>
          </Text>
        ))}
      </Text>
    ) : null
    const awakeLine = a ? (
      <Text wrap="truncate-end">
        <Text color={a.holding ? 'yellow' : 'gray'}>{awakeText}</Text>
        <Text dimColor>{[powerText, netText].filter(Boolean).map(x => ` · ${x}`).join('')}</Text>
      </Text>
    ) : null

    if (small) {
      return (
        <Box flexDirection="row" gap={1}>
          <Box flexDirection="column" flexGrow={1}>
            {lines}
            {teamLine}
            {awakeLine}
          </Box>
          <Button key="toggle" label={t.show} plain dimColor onPress={toggle} />
        </Box>
      )
    }
    return (
      <Box flexDirection="row" gap={2}>
        {owl ? (
          // A fixed box, top-aligned: in a taller band the row would otherwise stretch the owl apart.
          <Box key="owl-box" width={OWL_COLUMNS} height={OWL_ROWS} flexShrink={0} flexGrow={0} alignSelf="flex-start" marginRight={1}>
            {owl}
          </Box>
        ) : null}
        <Box flexDirection="column" flexGrow={1} flexShrink={1} minWidth={0}>
          {lines}
          {teamLine}
          {awakeLine}
        </Box>
        <Button key="toggle" label={t.hide} plain dimColor onPress={toggle} />
      </Box>
    )
  })
}
