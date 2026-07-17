# Runtime context

Verified against herdr 0.7.4.

- [Environment variables](#environment-variables)
- [The context JSON](#the-context-json)
- [Calling herdr back](#calling-herdr-back)
- [Language idioms](#language-idioms)
- [Directories](#directories)

## Environment variables

Injected into every runtime command (actions, events, panes) — but **not** into build commands, which run bare.

- `HERDR_ENV=1` — running under herdr.
- `HERDR_BIN_PATH` — the running herdr binary. Prefer this over a bare `herdr`.
- `HERDR_SOCKET_PATH` — raw socket, for hand-written JSON requests.
- `HERDR_PLUGIN_ID`, `HERDR_PLUGIN_ROOT`, `HERDR_PLUGIN_CONFIG_DIR`, `HERDR_PLUGIN_STATE_DIR`.
- `HERDR_PLUGIN_CONTEXT_JSON` — the full invocation context.
- `HERDR_WORKSPACE_ID`, `HERDR_TAB_ID`, `HERDR_PANE_ID` — when available.

Per entrypoint type:

- Actions also get `HERDR_PLUGIN_ACTION_ID` (the bare local id, not the qualified one).
- Event hooks also get `HERDR_PLUGIN_EVENT` and `HERDR_PLUGIN_EVENT_JSON`.
- Pane commands also get `HERDR_PLUGIN_ENTRYPOINT_ID`.
- Link-handler actions also get `HERDR_PLUGIN_CLICKED_URL` and `HERDR_PLUGIN_LINK_HANDLER_ID`.

Popup panes never get `HERDR_PANE_ID` — a popup has no pane id at all.

## The context JSON

An actual `HERDR_PLUGIN_CONTEXT_JSON` from an action invoked via the CLI:

```json
{
  "workspace_id": "w5",
  "workspace_label": "skill-factory",
  "workspace_cwd": "/Users/abrose/workspace/skill-factory",
  "tab_id": "w5:t1",
  "tab_label": "1",
  "focused_pane_id": "w5:p1",
  "focused_pane_cwd": "/Users/abrose/workspace/skill-factory",
  "focused_pane_agent": "claude",
  "focused_pane_status": "working",
  "invocation_source": "cli",
  "correlation_id": "cli:plugin"
}
```

The shape is flat. Fields appear when herdr can determine them for that invocation, so treat presence as conditional but nesting as fixed — a single `??` fallback to a default is right, a chain of guesses through hypothetical nested shapes is not.

`invocation_source` distinguishes how the action was triggered: `cli`, `keybinding`, `link_click`. Link clicks add `clicked_url` and `link_handler_id`. Worktree, agent, and selected-text fields appear when relevant.

Herdr fills missing fields from the active workspace, tab, focused pane, and worktree provenance before launching the command.

`tab_label` defaults to the tab's index as a string (`"1"`), so a bare number means "unnamed", not a real name.

## Calling herdr back

The entire herdr CLI is the plugin API — anything runnable as `herdr ...` is available. Go through `HERDR_BIN_PATH`: it targets the running binary and avoids the transport split between Unix sockets and Windows named pipes. Use `HERDR_SOCKET_PATH` only for hand-rolled JSON.

CLI commands print a JSON envelope on stdout — there is no `--json` flag to add, and inventing one is a common wrong guess. Success and failure are distinguished by which key is present, not by shape:

```json
{"id":"cli:workspace:list","result":{"type":"workspace_list","workspaces":[...]}}
{"error":{"code":"plugin_requires_newer_herdr","message":"..."},"id":"cli:plugin"}
```

Unwrap `.result` before use, and check for `.error` rather than trusting the exit code alone. `herdr plugin list` is the exception: it prints human-readable text unless given `--json`.

Plugin stdout and stderr are captured, not displayed. `herdr plugin log list --plugin <id>` returns `stdout`, `stderr`, `exit_code`, and `status` per run — the only way to see what a command printed.

## Language idioms

These illustrate the principle. Consider what fits your context.

Bash — read the ids directly and skip JSON parsing entirely:

```bash
#!/usr/bin/env bash
set -euo pipefail

herdr="${HERDR_BIN_PATH:-herdr}"
url="${HERDR_PLUGIN_CLICKED_URL:-}"

[[ -n "$url" ]] || { echo "no clicked url" >&2; exit 0; }

exec "$herdr" plugin pane open \
  --plugin examples.github-link-preview \
  --entrypoint preview \
  --placement split --direction right \
  --env "GITHUB_URL=$url" --focus
```

Node — parse the context, spawn the CLI:

```javascript
import { spawnSync } from "node:child_process";

const herdr = process.env.HERDR_BIN_PATH ?? "herdr";
const ctx = JSON.parse(process.env.HERDR_PLUGIN_CONTEXT_JSON ?? "{}");

if (!ctx.workspace_id) process.exit(0);

const { stdout, status } = spawnSync(herdr, ["workspace", "list"], {
  encoding: "utf8",
});

const { workspaces } = JSON.parse(stdout).result;
console.log(workspaces.map((w) => w.label).join("\n"));
process.exit(status ?? 1);
```

Rust — `serde` for the context, `std::process::Command` for the callback. Declare the build so the binary exists before herdr registers the plugin:

```toml
[[build]]
command = ["cargo", "build", "--release"]

[[actions]]
id = "check"
title = "Run release check"
command = ["./target/release/my-plugin"]
```

The relative path works because runtime commands run with the plugin directory as cwd.

```rust
use serde::Deserialize;
use std::{env, process::Command};

#[derive(Deserialize, Default)]
struct Context {
    workspace_cwd: Option<String>,
    focused_pane_status: Option<String>,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let ctx: Context = env::var("HERDR_PLUGIN_CONTEXT_JSON")
        .ok()
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default();

    if ctx.focused_pane_status.as_deref() != Some("idle") {
        return Ok(());
    }
    let Some(cwd) = ctx.workspace_cwd else { return Ok(()) };

    let herdr = env::var("HERDR_BIN_PATH").unwrap_or_else(|_| "herdr".into());
    let out = Command::new(herdr)
        .args(["workspace", "list"])
        .current_dir(cwd)
        .output()?;

    print!("{}", String::from_utf8_lossy(&out.stdout));
    Ok(())
}
```

`Option` fields match the context's conditional-presence contract, and returning early beats unwrapping. A Rust plugin ships source, not a binary — `cargo` must exist on the user's machine, so declare it in the README and keep `platforms` honest.

## Directories

`HERDR_PLUGIN_ROOT` — the installed or linked plugin directory. For GitHub installs this is a herdr-managed source checkout, and reinstalling replaces it wholesale. Nothing durable belongs here.

`HERDR_PLUGIN_CONFIG_DIR` — user-editable config, `.env` files, credentials. `herdr plugin config-dir <id>` prints the path; point setup docs at that command rather than a hardcoded path. Herdr seeds it from legacy plugin config locations when present.

`HERDR_PLUGIN_STATE_DIR` — runtime state, caches, databases.

Herdr creates both directories on `install` and `link`, then leaves them alone: no validation, no syncing, no cleanup on uninstall. There is no herdr-managed storage API in v1 — these are path discovery only, and the plugin owns formats, schemas, migrations, and deletion.
