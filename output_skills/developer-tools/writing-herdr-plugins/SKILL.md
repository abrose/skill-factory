---
name: writing-herdr-plugins
description: Writes herdr plugins — the herdr-plugin.toml manifest, actions, event hooks, panes, and link handlers — and ships them to the marketplace. Use when building, debugging, or publishing a plugin that extends the herdr terminal workspace.
---

STARTER_CHARACTER = 🐑

# Writing herdr plugins

A plugin is a directory holding a `herdr-plugin.toml` manifest and commands herdr can launch. There is no SDK and no restricted command set. Herdr validates the manifest, launches the declared commands as argv, injects context through environment variables, and captures their output. The commands call back into herdr through its CLI. Any language that runs as an argv command qualifies — Bash, Node, Lua, Rust, a compiled binary.

Every entrypoint is declared in the manifest. Runtime registration does not exist in v1: a running plugin cannot add an action, and panes cannot be created from arbitrary argv.

## The manifest

`id`, `name`, `version`, and `min_herdr_version` are required at the top level. Declare `platforms` as well — omitting it links with a warning.

```toml
id = "example.layout"
name = "Layout"
version = "0.1.0"
min_herdr_version = "0.7.0"
platforms = ["linux", "macos"]

[[actions]]
id = "apply"
title = "Apply layout"
contexts = ["workspace"]
command = ["node", "apply.js"]
```

Set `min_herdr_version` to the oldest herdr that carries every field, API, and event name the plugin depends on. Herdr refuses to link a plugin that names a version newer than the running binary.

`contexts` is optional and accepts only `global`, `workspace`, `tab`, `pane`, `selection` — every official example omits it. Every field, id charset, and enum: [references/manifest.md](references/manifest.md).

## Choosing an entrypoint

`[[actions]]` for anything a person triggers — a keybinding, `herdr plugin action invoke`, or a link handler.

`[[events]]` for herdr lifecycle reacting on its own: a worktree appears, an agent goes idle. See [references/events.md](references/events.md).

`[[panes]]` for terminal UI. Placement defaults to `overlay`; `popup` is session-modal and outside the pane APIs entirely.

`[[link_handlers]]` to intercept Ctrl+click on matching terminal URLs and route them to one of the plugin's own actions.

## Commands are argv, never a shell

Herdr does not run commands through a shell. `command = ["echo", "$HOME/*.log"]` passes the literal characters `$HOME/*.log`. No variable expansion, no globbing, no pipes, no redirection, no `&&`. Start a shell explicitly when the work needs one:

```toml
command = ["bash", "-c", "cargo build 2>&1 | tail -5"]
```

Commands run with the plugin directory as their working directory, so relative paths resolve against it: `command = ["./target/release/my-plugin"]`.

## Context arrives in the environment

Herdr injects `HERDR_BIN_PATH`, `HERDR_PLUGIN_ROOT`, `HERDR_PLUGIN_CONFIG_DIR`, `HERDR_PLUGIN_STATE_DIR`, and `HERDR_PLUGIN_CONTEXT_JSON` into every command, plus ids like `HERDR_WORKSPACE_ID` when they apply.

Call herdr back through `HERDR_BIN_PATH`, not a bare `herdr`. It points at the running binary and sidesteps the transport difference between Unix sockets and Windows named pipes. Reach for the raw socket at `HERDR_SOCKET_PATH` only to send JSON requests yourself.

Env var list, the real `HERDR_PLUGIN_CONTEXT_JSON` shape, and Bash/Node/Rust idioms for reading it: [references/runtime-context.md](references/runtime-context.md).

## Three directories, three jobs

`HERDR_PLUGIN_ROOT` is the source checkout — read-only in spirit. A GitHub-installed root is managed by herdr and a reinstall replaces it, taking anything written there with it.

`HERDR_PLUGIN_CONFIG_DIR` holds user-editable config such as a `.env`. `herdr plugin config-dir <id>` prints it, which is what setup instructions should point at.

`HERDR_PLUGIN_STATE_DIR` holds runtime state. Herdr creates both directories and never validates, syncs, or cleans them — the plugin owns its formats and migrations. There is no herdr-managed storage API in v1.

## The dev loop

```bash
herdr plugin link "$PWD"                                 # check the warnings field
herdr plugin action list --plugin example.layout
herdr plugin action invoke example.layout.apply
herdr plugin log list --plugin example.layout --limit 5  # stdout, stderr, exit_code
```

Re-run `link` after editing the manifest. `link` never runs `[[build]]` commands — build the working tree directly.

Plugin output is captured, not printed. `plugin log list` is the only place stdout, stderr, and the exit code surface, which makes it the debugging tool rather than an afterthought.

Publishing, build commands, and versioning: [references/publishing.md](references/publishing.md).

## Anti-patterns

**Trusting `link` to reject a bad event name.** A misspelled `on = "worktree.craeted"` links *successfully*. The hook silently never fires, and the only evidence is `"warnings": ["unknown event 'worktree.craeted'"]` in the response. Read the warnings after every link. This is the opposite of a bad `contexts` value, which fails the parse loudly.

**Expecting the manifest to filter events.** `on` accepts an event name and nothing else — no pane filter, no status filter. A hook on `pane.agent_status_changed` fires on *every* status change. Filter inside the command and exit 0 when it does not apply.

**Writing state into the plugin directory.** Credentials and databases under `HERDR_PLUGIN_ROOT` vanish on the next reinstall. Config belongs in `HERDR_PLUGIN_CONFIG_DIR`, state in `HERDR_PLUGIN_STATE_DIR`.

**Failing loudly from an event hook.** Hooks run on herdr's lifecycle, not on a user's request. A missing optional config is a reason to exit 0 quietly, not to error on every worktree the user creates.

**Defensive `??` chains over the context JSON.** The shape is flat and its field names are fixed — only their presence varies. Read `focused_pane_status`, not `context.status ?? context.agent_status ?? context.event?.pane?.agent?.status`. Guessing at nested shapes produces dead branches that outlive the confusion that caused them.

**Assuming a toolchain exists.** Herdr reports a build failure; it does not install `cargo`, `npm`, or `lua`. Document required tools and declare `platforms` honestly.
