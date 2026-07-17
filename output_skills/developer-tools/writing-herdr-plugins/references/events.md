# Event hooks

Verified against herdr 0.7.4.

- [Hook semantics](#hook-semantics)
- [Event names](#event-names)
- [What a command receives](#what-a-command-receives)
- [Which commands emit which events](#which-commands-emit-which-events)
- [Filtering](#filtering)

## Hook semantics

```toml
[[events]]
on = "worktree.created"
command = ["bun", "run", "bootstrap.ts"]
```

Hooks run for enabled, installed plugins whenever herdr emits a matching event name. `on` takes exactly one name — no wildcards, no filters, no conditions.

Names are validated at link time against herdr's known events, but an unrecognised name **is not an error**. The link succeeds and the response carries `warnings: ["unknown event 'worktree.craeted'"]`. A hook that never fires is almost always a typo hiding in that array.

Event hooks fire on herdr's schedule, not a user's request. Nobody is watching for an error message, and a hook that fails noisily on every event becomes a persistent irritant. Exit 0 when the hook does not apply.

## Event names

Not every subscribable socket event invokes a plugin hook. `workspace.metadata_updated` reports token changes and TTL expiry **without** invoking plugin event hooks.

Workspace: `workspace.created`, `workspace.updated`, `workspace.metadata_updated`, `workspace.renamed`, `workspace.moved`, `workspace.closed`, `workspace.focused`.

Tab: `tab.created`, `tab.closed`, `tab.focused`, `tab.renamed`, `tab.moved`.

Pane: `pane.created`, `pane.updated`, `pane.closed`, `pane.focused`, `pane.moved`, `pane.exited`, `pane.agent_detected`, `pane.output_matched`, `pane.agent_status_changed`, `pane.scroll_changed`.

Layout: `layout.updated`.

Worktree: `worktree.created`, `worktree.opened`, `worktree.removed`.

Notable payload details: `workspace.created` carries optional worktree provenance when the workspace belongs to a worktree group. `workspace.closed` includes a final snapshot when herdr can still identify it. `worktree.opened` includes `already_open`; `worktree.removed` includes `forced`. `layout.updated` carries the updated `PaneLayoutSnapshot` for one tab. Terminal-title changes emit `pane.updated`, but spinner-only raw-title churn does not when `terminal_title_stripped` is unchanged.

## What a command receives

Event commands get the standard `HERDR_*` environment (see [runtime-context.md](runtime-context.md)) plus:

- `HERDR_PLUGIN_EVENT` — the event name, in the **dotted** manifest form (`worktree.created`).
- `HERDR_PLUGIN_EVENT_JSON` — the event payload. Event-specific fields sit under `data`.

Read the payload from `HERDR_PLUGIN_EVENT_JSON` first and treat `HERDR_PLUGIN_CONTEXT_JSON` as ambient state. For `pane.agent_status_changed`, the status lives at `data.agent_status` in the event, while `focused_pane_status` in the context describes whatever pane happens to be focused — not necessarily the pane that changed.

The event name is spelled two ways in one invocation, and a hook dispatching on the wrong one silently matches nothing. `HERDR_PLUGIN_EVENT` is dotted (`worktree.created`), but inside `HERDR_PLUGIN_EVENT_JSON` both `.event` and `.data.type` are snake_case (`worktree_created`). A hook handling several events should switch on `HERDR_PLUGIN_EVENT` and compare against the same dotted strings it declared in the manifest — not against the JSON's `event` field.

## Which commands emit which events

Worth knowing because one user gesture fans out into several hooks.

`worktree.create` emits `workspace.created`, `tab.created`, `pane.created`, and `worktree.created`.

`worktree.open` emits `worktree.opened`, plus workspace/tab/pane creation events when it opens a new workspace.

`worktree.remove` emits `worktree.removed`, plus `workspace.closed` when the linked workspace was still open.

Worktree commands can emit `workspace.updated` when an existing workspace gains or changes worktree provenance.

A hook on `worktree.created` fires once per worktree. A hook on `pane.created` also fires for every pane a worktree brings with it.

## Filtering

Filtering is the command's job. Subscribe to the name, decide inside, exit 0 early. The official `agent-telegram-notify` example hooks `pane.agent_status_changed` — which fires on *every* status transition of *every* pane — and narrows it down itself:

```javascript
const event = JSON.parse(process.env.HERDR_PLUGIN_EVENT_JSON ?? "{}");
const status = event?.data?.agent_status?.toLowerCase();

if (!["done", "blocked"].includes(status)) {
  process.exit(0);
}
```

This illustrates the principle. Consider what fits your context — the same early-exit shape covers "only this repo", "only when config exists", "only on the first pane of a worktree".

Spawning a hook is cheap, but the work inside it is not. A hook on a high-frequency event (`pane.updated`, `pane.scroll_changed`, `layout.updated`) should reach its exit-0 decision before doing anything expensive.
