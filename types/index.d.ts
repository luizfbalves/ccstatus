export type Git = { branch: string; dirty: number; ahead: number; behind: number }

export type Limit = { kind: string; percent: number; resetsAt?: string }

export type Snapshot = {
  dir: string
  git: Git | null
  model: string
  effort?: string
  tokens?: number
  window?: number
  percent?: number
  costUsd?: number
  limits: Limit[]
}

declare module 'claude-code' {
  interface PluginState {
    ccstatus: { snapshot: Snapshot | null }
  }
}
