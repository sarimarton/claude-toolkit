import * as vscode from 'vscode'
import * as fs from 'fs'
import * as path from 'path'
import { exec } from 'child_process'

const TOPICS_DIR = path.join(
  process.env.HOME || '/tmp',
  '.config',
  'claude-toolkit',
  'topics'
)
const ACTIVE_TERMINAL_FILE = '/tmp/vscode-active-terminal.json'

interface TopicData {
  topic: string
  completeness?: number
  state?: string
  ts?: number
}

// Map of PID → terminal for quick lookup
const pidToTerminal = new Map<number, vscode.Terminal>()
// Map of PID → last processed timestamp (for polling dedup)
const lastProcessedTs = new Map<number, number>()

let output: vscode.OutputChannel
let statusBarItem: vscode.StatusBarItem
let pollingTimer: ReturnType<typeof setInterval> | undefined

export function activate(context: vscode.ExtensionContext) {
  output = vscode.window.createOutputChannel('Terminal Topic')
  output.appendLine(`[terminal-topic] activated, watching: ${TOPICS_DIR}`)

  // Status bar item — visible proof of life
  statusBarItem = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Right,
    10
  )
  statusBarItem.text = '$(terminal) topic'
  statusBarItem.tooltip = 'Terminal Topic Renamer active'
  statusBarItem.command = 'terminal-topic.showLog'
  statusBarItem.show()
  context.subscriptions.push(statusBarItem)

  // Command to open output channel
  context.subscriptions.push(
    vscode.commands.registerCommand('terminal-topic.showLog', () => {
      output.show()
    })
  )

  // Ensure topics directory exists
  fs.mkdirSync(TOPICS_DIR, { recursive: true })

  // Build initial PID → terminal map
  for (const terminal of vscode.window.terminals) {
    registerTerminal(terminal)
  }

  // Track new terminals
  context.subscriptions.push(
    vscode.window.onDidOpenTerminal((terminal) => {
      registerTerminal(terminal)
    })
  )

  // Write active terminal PID for Hammerspoon + sync title from tmux
  context.subscriptions.push(
    vscode.window.onDidChangeActiveTerminal((terminal) => {
      if (!terminal) {
        writeActiveTerminal(null)
        return
      }
      terminal.processId.then((pid) => {
        if (pid) writeActiveTerminal(pid)
      })
      // Sync topic from tmux after a short delay (tmux session switch settles)
      setTimeout(() => syncActiveTerminalFromTmux(), 300)
    })
  )

  // Cleanup on terminal close — distinguish user intent from reload/shutdown
  context.subscriptions.push(
    vscode.window.onDidCloseTerminal((terminal) => {
      const reason = terminal.exitStatus?.reason
      terminal.processId.then((pid) => {
        if (!pid) return
        lastProcessedTs.delete(pid)
        pidToTerminal.delete(pid)
        lastSetTopic.delete(pid)

        if (reason === vscode.TerminalExitReason.User) {
          output.appendLine(`[terminal-topic] user closed terminal: PID ${pid}`)
          killTmuxSession(pid)
          cleanupTopicFile(pid)
        } else {
          output.appendLine(`[terminal-topic] terminal closed (reason=${reason}): PID ${pid}`)
        }
      })
    })
  )

  // Watch the topics directory for JSON file changes
  const watcher = fs.watch(TOPICS_DIR, (eventType, filename) => {
    if (!filename || !filename.endsWith('.json')) return
    output.appendLine(`[terminal-topic] file ${eventType}: ${filename}`)
    handleTopicFile(filename)
  })

  context.subscriptions.push({ dispose: () => watcher.close() })

  // URI handler: vscode://sarim.vscode-terminal-topic/focus?pid=12345
  context.subscriptions.push(
    vscode.window.registerUriHandler({
      handleUri(uri: vscode.Uri) {
        if (uri.path === '/focus') {
          const pid = parseInt(new URLSearchParams(uri.query).get('pid') || '', 10)
          if (!pid) {
            output.appendLine(`[terminal-topic] focus URI: missing or invalid PID`)
            return
          }
          const terminal = pidToTerminal.get(pid)
          if (terminal) {
            terminal.show()
            output.appendLine(`[terminal-topic] focused terminal PID ${pid} via URI`)
          } else {
            output.appendLine(`[terminal-topic] focus URI: no terminal for PID ${pid}`)
          }
        }
      }
    })
  )

  // Process any existing topic files on startup
  try {
    const files = fs.readdirSync(TOPICS_DIR).filter(f => f.endsWith('.json'))
    output.appendLine(`[terminal-topic] found ${files.length} existing topic file(s)`)
    for (const file of files) {
      handleTopicFile(file)
    }
  } catch {
    // Directory might be empty or not readable yet
  }

  // Polling fallback: scan topics dir every 5s to catch fs.watch misses,
  // and sync active terminal title from tmux (catches tmux session switches)
  pollingTimer = setInterval(() => {
    try {
      const files = fs.readdirSync(TOPICS_DIR).filter(f => f.endsWith('.json'))
      for (const file of files) {
        handleTopicFile(file)
      }
    } catch {
      // Ignore transient read errors
    }
    syncActiveTerminalFromTmux()
  }, 5000)
  context.subscriptions.push({ dispose: () => { if (pollingTimer) clearInterval(pollingTimer) } })

  // Write active terminal PID on startup
  const activeTerminal = vscode.window.activeTerminal
  if (activeTerminal) {
    activeTerminal.processId.then((pid) => {
      if (pid) writeActiveTerminal(pid)
    })
  }

  output.appendLine(`[terminal-topic] ${vscode.window.terminals.length} terminal(s) registered`)
}

function writeActiveTerminal(pid: number | null) {
  try {
    const data = pid ? { pid, ts: Math.floor(Date.now() / 1000) } : { pid: null, ts: Math.floor(Date.now() / 1000) }
    fs.writeFileSync(ACTIVE_TERMINAL_FILE, JSON.stringify(data) + '\n')
  } catch {
    // /tmp should always be writable
  }
}

function registerTerminal(terminal: vscode.Terminal) {
  terminal.processId.then((pid) => {
    if (pid) {
      pidToTerminal.set(pid, terminal)
      output.appendLine(`[terminal-topic] registered terminal "${terminal.name}" PID ${pid}`)
    }
  })
}

function handleTopicFile(filename: string) {
  const filePath = path.join(TOPICS_DIR, filename)

  let data: TopicData
  try {
    const content = fs.readFileSync(filePath, 'utf-8')
    data = JSON.parse(content)
  } catch {
    output.appendLine(`[terminal-topic] failed to parse ${filename}`)
    return
  }

  if (!data.topic) return

  // Extract PID from filename: "vscode_-config_12345.json" → 12345
  const pid = extractPid(filename)
  if (!pid) {
    output.appendLine(`[terminal-topic] no PID in filename: ${filename}`)
    return
  }

  // Dedup: skip if we already processed this exact timestamp
  const ts = data.ts || 0
  if (lastProcessedTs.get(pid) === ts) return
  lastProcessedTs.set(pid, ts)

  const terminal = pidToTerminal.get(pid)
  if (!terminal) {
    output.appendLine(`[terminal-topic] no terminal for PID ${pid}, skipping rename: "${data.topic}"`)
    return
  }

  const isActive = vscode.window.activeTerminal === terminal
  if (isActive) {
    output.appendLine(`[terminal-topic] renaming active terminal PID ${pid} → "${data.topic}"`)
    renameTerminal(data.topic)
  } else {
    // Switch to target terminal, rename, switch back
    output.appendLine(`[terminal-topic] renaming non-active terminal PID ${pid} → "${data.topic}"`)
    const originalActive = vscode.window.activeTerminal
    terminal.show(true) // preserveFocus=true
    // Small delay to let VS Code update the active terminal
    setTimeout(() => {
      renameTerminal(data.topic)
      // Restore original active terminal
      if (originalActive) {
        setTimeout(() => originalActive.show(true), 50)
      }
    }, 50)
  }
  statusBarItem.text = `$(terminal) ${data.topic}`
}

function extractPid(filename: string): number | null {
  // Filename format: "vscode_workspacename_PID.json"
  // The PID is the last numeric segment before .json
  const match = filename.replace('.json', '').match(/_(\d+)$/)
  return match ? parseInt(match[1], 10) : null
}

function renameTerminal(topic: string) {
  vscode.commands.executeCommand('workbench.action.terminal.renameWithArg', {
    name: `✻ ${topic}`
  })
}

const HS = '/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs'

function killTmuxSession(pid: number) {
  // Check if Alt was held during close — only kill on Alt+close
  exec(
    `${HS} -c "hs.eventtap.checkKeyboardModifiers().alt"`,
    (err, altResult) => {
      if (err || altResult?.trim() !== 'true') {
        output.appendLine(`[terminal-topic] no Alt held, preserving tmux session for PID ${pid}`)
        return
      }
      // Alt was held — find and kill the tmux session
      exec(
        `tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "_${pid}$"`,
        (_, stdout) => {
          const session = stdout?.trim()
          if (!session) return
          exec(`tmux kill-session -t ${JSON.stringify(session)}`, (killErr) => {
            if (!killErr) {
              output.appendLine(`[terminal-topic] Alt+close: killed tmux session: ${session}`)
            }
          })
        }
      )
    }
  )
}

// Track the last topic set per terminal PID (to avoid redundant renames)
const lastSetTopic = new Map<number, string>()

function syncActiveTerminalFromTmux() {
  const terminal = vscode.window.activeTerminal
  if (!terminal) return
  terminal.processId.then((pid) => {
    if (!pid) return
    // Ask tmux which session this client is viewing, then look up the topic file
    exec(
      `/opt/homebrew/bin/tmux list-clients -F '#{client_pid} #{session_name}' 2>/dev/null | grep '^${pid} '`,
      (err, stdout) => {
        if (err || !stdout?.trim()) return
        const sessionName = stdout.trim().split(' ').slice(1).join(' ')
        if (!sessionName) return
        const topicFile = path.join(TOPICS_DIR, `${sessionName}.json`)
        try {
          const content = fs.readFileSync(topicFile, 'utf-8')
          const data: TopicData = JSON.parse(content)
          if (data.topic && lastSetTopic.get(pid) !== data.topic) {
            lastSetTopic.set(pid, data.topic)
            // Ensure this terminal is active before renaming
            if (vscode.window.activeTerminal === terminal) {
              renameTerminal(data.topic)
              output.appendLine(`[terminal-topic] tmux sync: PID ${pid} → "${data.topic}"`)
            }
          }
        } catch {
          // No topic file for this session — could be a plain shell session
        }
      }
    )
  })
}

function cleanupTopicFile(pid: number) {
  try {
    const files = fs.readdirSync(TOPICS_DIR).filter(f => f.endsWith('.json') && f.endsWith(`_${pid}.json`))
    for (const file of files) {
      const filePath = path.join(TOPICS_DIR, file)
      fs.unlinkSync(filePath)
      output.appendLine(`[terminal-topic] removed topic file: ${file}`)
    }
  } catch {
    // File may already be gone
  }
}

export function deactivate() {
  if (pollingTimer) clearInterval(pollingTimer)
  pidToTerminal.clear()
  lastProcessedTs.clear()
}
