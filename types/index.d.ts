/** A work this session leads, as the band draws it. */
export type BandWork = {
  id: string
  dir: string
  kind: 'repo' | 'disposable'
  title: string
  phase: string
  round: number
  mode: string
  doing: string
  agents: { name: string; doing: string; updated: string }[]
}

/** What PIA Awake last wrote, trimmed to what the band shows. */
export type AwakeView = {
  holding: boolean
  installed: boolean
  lidClosed: boolean
  battery: number | null
  onAC: boolean
  network: string
}

/** A teammate of this session, by its name in the team. */
export type Mate = { name: string; status: string }

declare module 'claude-code' {
  interface PluginState {
    pia: {
      works: BandWork[]
      awake: AwakeView | null
      mates: Mate[]
      collapsed: boolean
      spanish: boolean
    }
  }
}
