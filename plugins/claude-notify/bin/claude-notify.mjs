#!/usr/bin/env node

// src/config.ts
import { readFile } from "node:fs/promises";

// src/logger.ts
import { appendFileSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";

// src/types.ts
var CHANNEL_TYPES = {
  TERMINAL_NOTIFIER: "terminal-notifier",
  NTFY: "ntfy"
};

// src/utils/channel-selector.ts
function selectChannels(state, configuredChannels, force = false) {
  if (force) {
    debug("Force mode - selecting all configured channels");
    return [...configuredChannels];
  }
  if (state.is_screen_locked) {
    const hasNtfy = configuredChannels.includes(CHANNEL_TYPES.NTFY);
    debug(`Screen locked - selecting ntfy only: ${hasNtfy}`);
    return hasNtfy ? [CHANNEL_TYPES.NTFY] : [];
  }
  if (!state.is_terminal_active) {
    const hasTerminalNotifier = configuredChannels.includes(CHANNEL_TYPES.TERMINAL_NOTIFIER);
    debug(`Away from terminal - selecting terminal-notifier: ${hasTerminalNotifier}`);
    return hasTerminalNotifier ? [CHANNEL_TYPES.TERMINAL_NOTIFIER] : [];
  }
  return [...configuredChannels];
}
function shouldSkipNotification(state, skipWhenActive, force = false) {
  if (force) {
    return false;
  }
  if (state.is_screen_locked) {
    return false;
  }
  return state.is_terminal_active && skipWhenActive;
}
// src/utils/env.ts
function getHome() {
  const home = process.env.HOME;
  if (home) {
    return home;
  }
  return "/tmp";
}
function getEnv(key, defaultValue) {
  return process.env[key] ?? defaultValue;
}
function getBoolEnv(key, defaultValue = false) {
  const value = getEnv(key);
  if (!value) {
    return defaultValue;
  }
  return ["true", "1", "yes"].includes(value.toLowerCase());
}
function isForceMode() {
  return getBoolEnv("CLAUDE_NOTIFY_FORCE", false);
}
// src/utils/exec.ts
import { execFile } from "node:child_process";
function runCommand(file, args) {
  return new Promise((resolve) => {
    execFile(file, args, { encoding: "utf-8" }, (err, stdout, stderr) => {
      if (!err) {
        resolve({ exitCode: 0, stdout, stderr });
        return;
      }
      const exitCode = typeof err.code === "number" ? err.code : -1;
      resolve({ exitCode, stdout, stderr });
    });
  });
}
// src/utils/sanitize.ts
function sanitizeForShell(input) {
  if (!input) {
    return "";
  }
  return input.replace(/[\x00-\x1f\x7f]/g, "");
}
function isValidHookInput(input) {
  if (typeof input !== "object" || input === null) {
    return false;
  }
  const obj = input;
  if (typeof obj.hook_event_name !== "string") {
    return false;
  }
  return ["Notification", "Stop"].includes(obj.hook_event_name);
}
var sanitize_default = isValidHookInput;
// src/utils/terminal-detector.ts
var TERMINAL_BUNDLE_IDS = [
  "com.apple.Terminal",
  "com.googlecode.iterm2",
  "dev.warp.Warp-Stable",
  "com.github.wez.wezterm",
  "io.alacritty",
  "net.kovidgoyal.kitty",
  "com.mitchellh.ghostty",
  "com.jetbrains.intellij",
  "com.jetbrains.intellij.ce",
  "com.jetbrains.AppCode",
  "com.jetbrains.CLion",
  "com.jetbrains.PhpStorm",
  "com.jetbrains.WebStorm",
  "com.jetbrains.PyCharm",
  "com.microsoft.VSCode",
  "com.microsoft.VSCodeInsiders",
  "com.todesktop.230313mzl4w4u92",
  "com.apple.dt.Xcode",
  "com.sublimetext.4",
  "com.sublimetext.3"
];
var TERMINAL_KEYWORDS = ["terminal", "console", "iterm", "shell", "prompt"];
function isTerminalApp(bundleId) {
  if (!bundleId) {
    return false;
  }
  const lowerBundleId = bundleId.toLowerCase();
  if (TERMINAL_BUNDLE_IDS.includes(bundleId)) {
    return true;
  }
  if (bundleId.startsWith("com.jetbrains.")) {
    return true;
  }
  return TERMINAL_KEYWORDS.some((keyword) => lowerBundleId.includes(keyword));
}
async function getFrontmostAppBundleId() {
  const result = await runCommand("osascript", [
    "-e",
    "id of application (path to frontmost application as text)"
  ]);
  if (result.exitCode !== 0) {
    return "";
  }
  return result.stdout.trim();
}
function detectTerminalBundleId() {
  const env = process.env;
  if (env.LC_TERMINAL === "iTerm2" || env.ITERM_SESSION_ID) {
    return "com.googlecode.iterm2";
  }
  if (env.TERMINAL_EMULATOR === "JetBrains-JediTerm") {
    const jetbrainsBundleId = env.__CFBundleIdentifier;
    if (jetbrainsBundleId?.startsWith("com.jetbrains.")) {
      return jetbrainsBundleId;
    }
  }
  if (env.VSCODE_INJECTION === "1" || env.VSCODE_PID) {
    const cfBundleId2 = env.__CFBundleIdentifier;
    if (cfBundleId2 === "com.microsoft.VSCodeInsiders") {
      return "com.microsoft.VSCodeInsiders";
    }
    if (cfBundleId2 === "com.todesktop.230313mzl4w4u92") {
      return "com.todesktop.230313mzl4w4u92";
    }
    return "com.microsoft.VSCode";
  }
  if (env.GHOSTTY_RESOURCES_DIR) {
    return "com.mitchellh.ghostty";
  }
  if (env.WEZTERM_EXECUTABLE) {
    return "com.github.wez.wezterm";
  }
  if (env.KITTY_WINDOW_ID) {
    return "net.kovidgoyal.kitty";
  }
  if (env.ALACRITTY_SOCKET) {
    return "io.alacritty";
  }
  if (env.WARP_IS_LOCAL_SHELL_SESSION) {
    return "dev.warp.Warp-Stable";
  }
  const termProgram = env.TERM_PROGRAM;
  if (termProgram && termProgram !== "tmux") {
    const mapping = {
      Apple_Terminal: "com.apple.Terminal",
      "iTerm.app": "com.googlecode.iterm2",
      WarpTerminal: "dev.warp.Warp-Stable",
      WezTerm: "com.github.wez.wezterm",
      Alacritty: "io.alacritty",
      kitty: "net.kovidgoyal.kitty",
      ghostty: "com.mitchellh.ghostty",
      vscode: "com.microsoft.VSCode"
    };
    if (mapping[termProgram]) {
      return mapping[termProgram];
    }
  }
  const cfBundleId = env.__CFBundleIdentifier;
  if (cfBundleId) {
    return cfBundleId;
  }
  return;
}

// src/utils/state-detector.ts
async function isScreenLocked() {
  const result = await runCommand("ioreg", ["-n", "Root", "-d1"]);
  if (result.exitCode !== 0) {
    warn(`Failed to detect screen lock status: exit code ${result.exitCode}`);
    return false;
  }
  const isLocked = result.stdout.includes('"IOConsoleLocked" = Yes');
  debug(`Screen lock status: ${isLocked}`);
  return isLocked;
}
async function isCurrentTerminalForeground() {
  const currentTerminalBundleId = detectTerminalBundleId();
  const frontmostBundleId = await getFrontmostAppBundleId();
  debug(`Current terminal: ${currentTerminalBundleId}, Frontmost app: ${frontmostBundleId}`);
  if (currentTerminalBundleId) {
    const isMatch = currentTerminalBundleId === frontmostBundleId;
    debug(`Terminal Bundle ID match: ${isMatch}`);
    return isMatch;
  }
  const isFrontmostTerminal = isTerminalApp(frontmostBundleId);
  debug(`Fallback check - Frontmost app is terminal: ${isFrontmostTerminal}`);
  return isFrontmostTerminal;
}
async function detectSystemState() {
  const [is_screen_locked, is_terminal_active] = await Promise.all([
    isScreenLocked(),
    isCurrentTerminalForeground()
  ]);
  debug(`System state detected: screen_locked=${is_screen_locked}, terminal_active=${is_terminal_active}`);
  return {
    is_screen_locked,
    is_terminal_active
  };
}
// src/logger.ts
var LOG_LEVELS = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3
};
function isLoggingEnabled() {
  return getBoolEnv("CLAUDE_NOTIFY_LOG", false);
}
function getConfiguredLogLevel() {
  const level = getEnv("CLAUDE_NOTIFY_LOG_LEVEL", "info");
  return LOG_LEVELS[level] !== undefined ? level : "info";
}
function getLogFilePath() {
  const home = getHome();
  return `${home}/.config/claude-notify/notify.log`;
}
function log(level, message) {
  if (!isLoggingEnabled()) {
    return;
  }
  const configuredLevel = getConfiguredLogLevel();
  if (LOG_LEVELS[level] < LOG_LEVELS[configuredLevel]) {
    return;
  }
  const timestamp = new Date().toISOString();
  const logEntry = `[${timestamp}] [${level.toUpperCase()}] ${message}
`;
  const logFilePath = getLogFilePath();
  try {
    mkdirSync(dirname(logFilePath), { recursive: true });
    appendFileSync(logFilePath, logEntry);
  } catch (err) {
    console.error(`Failed to write log: ${err}`);
  }
}
function debug(message) {
  log("debug", message);
}
function info(message) {
  log("info", message);
}
function warn(message) {
  log("warn", message);
}
function error(message) {
  log("error", message);
}

// src/config.ts
function getDefaultConfig() {
  return {
    ntfy: {
      server: "https://ntfy.sh",
      topic: ""
    },
    terminal_notifier: {
      enabled: true
    },
    log: {
      enabled: false,
      level: "info"
    },
    skip_when_active: true
  };
}
function mergeWithDefaults(partial) {
  const defaults = getDefaultConfig();
  return {
    ntfy: {
      ...defaults.ntfy,
      ...partial.ntfy
    },
    terminal_notifier: {
      ...defaults.terminal_notifier,
      ...partial.terminal_notifier
    },
    log: {
      ...defaults.log,
      ...partial.log
    },
    skip_when_active: partial.skip_when_active ?? defaults.skip_when_active,
    notifications: partial.notifications ?? defaults.notifications
  };
}
async function loadConfig() {
  const configPath = `${getHome()}/.config/claude-notify/config.json`;
  debug(`Loading config from: ${configPath}`);
  let content;
  try {
    content = await readFile(configPath, "utf-8");
  } catch {
    debug("Config file not found, using defaults");
    return getDefaultConfig();
  }
  try {
    const parsed = JSON.parse(content);
    debug("Config file loaded successfully");
    return mergeWithDefaults(parsed);
  } catch (err) {
    debug(`Failed to parse config file: ${err}`);
    return getDefaultConfig();
  }
}

// src/adapters/ntfy.ts
function createNtfyAdapter(config) {
  return {
    async send(payload) {
      const server = getEnv("NTFY_SERVER") ?? config.server ?? "https://ntfy.sh";
      const topic = getEnv("NTFY_TOPIC") ?? config.topic;
      const token = getEnv("NTFY_TOKEN") ?? config.token;
      if (!topic) {
        warn("Ntfy: 토픽이 설정되지 않아 발송을 건너뜁니다 (/notify-setup 또는 NTFY_TOPIC 설정)");
        return false;
      }
      const url = `${server}/${topic}`;
      const { title, message, priority = 3 } = payload;
      debug(`Ntfy: Sending notification to ${url} - title="${title}", priority=${priority}`);
      const headers = {
        "Content-Type": "text/plain; charset=utf-8",
        "X-Title": title,
        "X-Priority": priority.toString()
      };
      if (token) {
        headers.Authorization = `Bearer ${token}`;
        debug("Ntfy: Using authentication token");
      }
      const response = await fetch(url, {
        method: "POST",
        headers,
        body: message
      });
      if (!response.ok) {
        error(`Ntfy: HTTP ${response.status} - ${response.statusText}`);
        throw new Error(`ntfy API request failed: ${response.status} ${response.statusText}`);
      }
      debug("Ntfy: Notification sent successfully");
      return true;
    }
  };
}
// src/adapters/terminal-notifier.ts
var TerminalNotifierAdapter = {
  async send(payload) {
    const { title, message, activateBundleId } = payload;
    debug(`TerminalNotifier: Sending notification - title="${title}", message="${message}"`);
    if (activateBundleId) {
      debug(`TerminalNotifier: Will activate bundle ID: ${activateBundleId}`);
    }
    const args = [
      "-title",
      sanitizeForShell(title),
      "-message",
      sanitizeForShell(message),
      "-sound",
      "default"
    ];
    if (activateBundleId) {
      args.push("-activate", sanitizeForShell(activateBundleId));
    }
    const result = await runCommand("terminal-notifier", args);
    if (result.exitCode === 0) {
      debug("TerminalNotifier: Notification sent successfully");
      return true;
    }
    if (result.exitCode === -1) {
      error("TerminalNotifier: terminal-notifier 를 실행할 수 없습니다 (brew install terminal-notifier)");
      throw new Error("terminal-notifier not found");
    }
    error(`TerminalNotifier: Failed with exit code ${result.exitCode} ${result.stderr.trim()}`);
    throw new Error(`terminal-notifier failed with exit code ${result.exitCode}`);
  }
};
// src/handlers/notification.ts
var DEFAULT_NOTIFICATION_CONFIG = {
  enabled: true,
  title: "Claude Code",
  message_template: "{message}",
  channels: [CHANNEL_TYPES.TERMINAL_NOTIFIER, CHANNEL_TYPES.NTFY]
};
async function handleNotification(input, config) {
  const { notification_type, message } = input;
  debug(`Notification received: ${notification_type}`);
  debug(`Message: ${message}`);
  const state = await detectSystemState();
  const force = isForceMode();
  debug(`System state: ${JSON.stringify(state)}, force: ${force}`);
  const notificationConfig = config.notifications?.[notification_type] ?? DEFAULT_NOTIFICATION_CONFIG;
  if (!notificationConfig.enabled) {
    info(`Notification type ${notification_type} is disabled`);
    return;
  }
  const shouldSkip = shouldSkipNotification(state, config.skip_when_active ?? true, force);
  if (shouldSkip) {
    info("Skipping notification (terminal is active)");
    return;
  }
  const channels = selectChannels(state, notificationConfig.channels, force);
  debug(`Selected channels: ${channels.join(", ")}`);
  if (channels.length === 0) {
    info("No channels available for notification");
    return;
  }
  const bundleId = detectTerminalBundleId();
  if (bundleId) {
    debug(`Detected terminal Bundle ID: ${bundleId}`);
  }
  await sendNotifications(channels, notificationConfig, message, config, bundleId);
}
async function sendNotifications(channels, notificationConfig, message, config, activateBundleId) {
  const finalMessage = notificationConfig.message_template.replace("{message}", message);
  const promises = channels.map(async (channel) => {
    try {
      if (channel === CHANNEL_TYPES.TERMINAL_NOTIFIER) {
        const sent = await TerminalNotifierAdapter.send({
          title: notificationConfig.title,
          message: finalMessage,
          activateBundleId
        });
        if (sent) {
          info("Notification sent via terminal-notifier");
        }
      } else if (channel === CHANNEL_TYPES.NTFY) {
        const adapter = createNtfyAdapter(config.ntfy);
        const sent = await adapter.send({
          title: notificationConfig.title,
          message: finalMessage
        });
        if (sent) {
          info("Notification sent via ntfy");
        }
      }
    } catch (error2) {
      warn(`Failed to send notification via ${channel}: ${error2}`);
    }
  });
  await Promise.all(promises);
}
// src/handlers/stop.ts
var DEFAULT_STOP_CONFIG = {
  enabled: true,
  title: "Claude Code Session",
  message_template: "Session completed",
  channels: [CHANNEL_TYPES.TERMINAL_NOTIFIER, CHANNEL_TYPES.NTFY]
};
async function handleStop(input, config) {
  const { session_id } = input;
  debug(`Session stopped: ${session_id}`);
  const state = await detectSystemState();
  const force = isForceMode();
  debug(`System state: ${JSON.stringify(state)}, force: ${force}`);
  const stopConfig = config.notifications?.stop ?? DEFAULT_STOP_CONFIG;
  if (!stopConfig.enabled) {
    info("Stop notification is disabled");
    return;
  }
  if (shouldSkipNotification(state, config.skip_when_active ?? true, force)) {
    info("Skipping stop notification (terminal is active)");
    return;
  }
  const channels = selectChannels(state, stopConfig.channels, force);
  debug(`Selected channels: ${channels.join(", ")}`);
  if (channels.length === 0) {
    info("No channels available for stop notification");
    return;
  }
  await sendStopNotifications(channels, stopConfig, config);
}
async function sendStopNotifications(channels, stopConfig, config) {
  const finalMessage = stopConfig.message_template;
  const bundleId = detectTerminalBundleId();
  if (bundleId) {
    debug(`Detected terminal Bundle ID: ${bundleId}`);
  }
  for (const channel of channels) {
    try {
      if (channel === CHANNEL_TYPES.TERMINAL_NOTIFIER) {
        const sent = await TerminalNotifierAdapter.send({
          title: stopConfig.title,
          message: finalMessage,
          activateBundleId: bundleId
        });
        if (sent) {
          info("Stop notification sent via terminal-notifier");
        }
      } else if (channel === CHANNEL_TYPES.NTFY) {
        const adapter = createNtfyAdapter(config.ntfy);
        const sent = await adapter.send({
          title: stopConfig.title,
          message: finalMessage
        });
        if (sent) {
          info("Stop notification sent via ntfy");
        }
      }
    } catch (error2) {
      warn(`Failed to send stop notification via ${channel}: ${error2}`);
    }
  }
}
// src/index.ts
async function readStdin() {
  if (process.stdin.isTTY) {
    return "";
  }
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString("utf-8");
}
async function main() {
  try {
    const inputText = await readStdin();
    if (!inputText.trim()) {
      debug("Empty input received");
      return;
    }
    const parsed = JSON.parse(inputText);
    if (!sanitize_default(parsed)) {
      error("Invalid hook input format");
      process.exit(1);
    }
    const input = parsed;
    debug(`Received event: ${input.hook_event_name}`);
    const config = await loadConfig();
    switch (input.hook_event_name) {
      case "Notification":
        await handleNotification(input, config);
        break;
      case "Stop":
        await handleStop(input, config);
        break;
      default: {
        const unknownInput = input;
        debug(`Unknown event: ${unknownInput.hook_event_name ?? "undefined"}`);
      }
    }
    info("Hook processing completed");
  } catch (err) {
    error(`Failed to process hook: ${err}`);
    process.exit(1);
  }
}
main();
