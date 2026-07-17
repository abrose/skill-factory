# herdr-plugin.toml reference

Verified against herdr 0.7.4.

- [Top level](#top-level)
- [Ids](#ids)
- [Platforms](#platforms)
- [build](#build)
- [actions](#actions)
- [events](#events)
- [panes](#panes)
- [link_handlers](#link_handlers)
- [Keybindings](#keybindings)
- [Validation behaviour](#validation-behaviour)

## Top level

Required: `id`, `name`, `version`, `min_herdr_version`.
Optional: `description`, `platforms`.

```toml
id = "example.layout"
name = "Layout"
version = "0.1.0"
min_herdr_version = "0.7.0"
description = "Apply project layouts"
platforms = ["linux", "macos", "windows"]
```

`min_herdr_version` is the oldest herdr supporting every manifest field, API, and event name in use. Linking against an older binary fails:

```
{"error":{"code":"plugin_requires_newer_herdr",
  "message":"plugin requires Herdr 99.0.0 or newer; current Herdr is 0.7.4"}}
```

## Ids

Plugin `id` accepts ASCII letters, digits, dot, colon, underscore, hyphen. The dotted-namespace convention (`examples.agent-telegram-notify`) is what the official examples use.

Action, pane, and link handler ids are local to the plugin and accept the same characters **except dots**. Each id must be unique within its own type. Herdr qualifies action ids as `plugin.id.action` when it needs a global name — `example.layout.apply`.

## Platforms

`platforms` takes `linux`, `macos`, `windows`. Top-level declares plugin-wide support; individual build commands, actions, events, panes, and link handlers may declare their own, overriding the top-level list rather than intersecting with it. Items without their own `platforms` inherit.

Omitting top-level `platforms` links with a warning. Invoking an action or opening a pane whose effective platforms exclude the current OS returns a `platform_unsupported` error.

On Windows, build/action/event commands resolve PATHEXT shims such as `npm.cmd` and `bun.cmd` when the bare command is on PATH. Pane commands must be valid Windows argv.

## build

```toml
[[build]]
command = ["npm", "ci"]

[[build]]
command = ["npm", "run", "build"]
platforms = ["linux", "macos"]
```

Build commands run during `plugin install`, after the confirmation preview and before registration. A failing build aborts the install and the plugin is never registered.

`plugin link` does **not** run build commands. They also receive no runtime plugin context and no herdr socket env — they are plain argv commands with none of the `HERDR_*` injection.

Builds may generate files, but modifying `herdr-plugin.toml` after the install preview aborts the install.

## actions

```toml
[[actions]]
id = "apply"
title = "Apply layout"
contexts = ["workspace"]
command = ["node", "apply.js"]
```

`contexts` is an optional strict enum: `global`, `workspace`, `tab`, `pane`, `selection`. An unknown value is a hard parse failure at link time, naming the valid variants. All four official example plugins omit `contexts` entirely.

Invoke by qualified id (`example.layout.apply`) or bare action id. Invoking an action on a disabled plugin returns `plugin_disabled`.

## events

```toml
[[events]]
on = "worktree.created"
command = ["node", "on-worktree.js"]
```

`on` takes one event name and nothing else — there is no filtering by pane, workspace, or status. See [events.md](events.md) for names and hook semantics.

Unknown event names are **not** rejected. See [Validation behaviour](#validation-behaviour).

## panes

```toml
[[panes]]
id = "picker"
title = "Picker"
placement = "popup"
width = "80%"
height = 20
command = ["sh", "picker.sh"]
```

`placement` accepts `overlay` (default), `popup`, `split`, `tab`, `zoomed`. A `plugin.pane.open` request can override the manifest placement.

`overlay` opens a temporary zoomed overlay over the active pane, restoring the previous focus and zoom on close.

`popup` is session-modal and does not disturb the tiled layout. `width`/`height` take terminal-cell numbers or percentage strings like `"80%"`; omitted, they default to half the terminal, and too-small values clamp to a minimum. A popup receives all terminal input including Escape, and closes when its command exits or on a `popup.close` request. Opening one while Settings or Copy mode is active returns `ui_busy`.

A popup is a singleton session resource, not a pane: no pane id, no `HERDR_PANE_ID`, no pane lifecycle events, and absent from the pane, layout, persistence, and agent APIs. The underlying tiled pane still shows up in the context JSON.

`split`, `tab`, `zoomed`, and `overlay` panes are ordinary herdr panes once open — `pane.move`, `pane.swap`, `pane.resize`, and `pane.zoom` all work, and ownership follows the pane across tabs and workspaces.

## link_handlers

```toml
[[link_handlers]]
id = "github-issue"
title = "Open GitHub issue"
pattern = "^https://github\\.com/[^/]+/[^/]+/(issues|pull)/[0-9]+$"
action = "apply"
```

`pattern` is a Rust regular expression matched against the clicked URL. `action` must name an action declared by the same plugin. Handlers are checked in manifest order within each plugin.

The modifier is **Control on every platform, including macOS** — captured terminal mouse reports cannot distinguish Command from a plain click.

Handler-invoked actions receive `invocation_source = "link_click"`, plus `clicked_url` and `link_handler_id` in the context JSON, mirrored as `HERDR_PLUGIN_CLICKED_URL` and `HERDR_PLUGIN_LINK_HANDLER_ID`.

## Keybindings

Users bind keys to actions in herdr config, not in the plugin manifest:

```toml
[[keys.command]]
key = "prefix+l"
type = "plugin_action"
command = "example.layout.apply"
description = "apply layout"
```

## Validation behaviour

The two failure modes are asymmetric, and the difference matters.

**Loud** — a bad `contexts` value, malformed TOML, a missing required field, or a too-new `min_herdr_version` all fail the link with an error code:

```
{"error":{"code":"plugin_manifest_parse_failed","message":"... unknown variant
  `totally-made-up-context`, expected one of `global`, `workspace`, `tab`, `pane`, `selection`"}}
```

**Quiet** — an unknown event name and a missing top-level `platforms` both link *successfully* and report through a `warnings` array:

```json
{"result":{"plugin":{"plugin_id":"probe.trapcheck","enabled":true,
  "warnings":["unknown event 'worktree.craeted'"]}}}
```

Nothing else surfaces a quiet warning. Read `warnings` after `plugin link`, and again in `plugin list --json` when a hook mysteriously never fires.

Herdr writes a `plugins.json` registry beside `session.json` and re-reads each manifest from its original path on startup. A manifest that has gone missing or unparseable keeps its registry entry and surfaces a warning through `plugin.list`.
