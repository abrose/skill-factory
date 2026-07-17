# Publishing and distribution

Verified against herdr 0.7.4.

- [Install and link](#install-and-link)
- [Build commands](#build-commands)
- [Versioning](#versioning)
- [Marketplace](#marketplace)
- [Trust](#trust)
- [Repo layout](#repo-layout)

## Install and link

`link` is for authoring, `install` is for consuming. They differ in ways that bite.

```bash
herdr plugin link /path/to/plugin        # register a working directory in place
herdr plugin unlink <plugin_id>          # unregister, leave files alone
```

```bash
herdr plugin install <owner>/<repo>[/subdir...] [--ref REF] [--yes]
herdr plugin uninstall <plugin_id|owner/repo[/subdir...]>
```

`link` accepts a directory containing `herdr-plugin.toml` or a direct manifest path. It does not run build commands, and it does not copy anything — herdr reads the manifest from where it sits, which is why re-running `link` picks up edits.

`install` accepts **GitHub shorthand only**. It clones with git, shows a source-and-commands preview in interactive terminals, runs build commands, stores the checkout under herdr-managed plugin data, and registers it. `--yes` skips the preview for noninteractive installs; `--ref` pins a revision.

Reinstalling a GitHub-managed plugin replaces its managed checkout. Installing over a locally linked plugin is refused — unlink first. There is no `plugin update` in v1; reinstall to refresh.

`uninstall` takes either the plugin id or the same `owner/repo[/subdir]` shorthand, and removes the managed checkout for GitHub installs. `unlink` only unregisters.

Both `install` and `link` create the plugin's config and state directories.

## Build commands

```toml
[[build]]
command = ["cargo", "build", "--release"]
platforms = ["linux", "macos"]
```

Build runs on `install` — after the preview, before registration. A failure aborts the install and the plugin is never registered. The error reports the plugin id, build index, working directory, command, exit status or spawn error, and capped stdout/stderr, without interpreting tool output.

Build does **not** run on `link`. Local authors build their own working tree, which is the single most common surprise when a linked plugin's `command` points at a binary that was never compiled.

Build commands are plain argv like any other, but they receive no runtime plugin context and no herdr socket env.

Builds may generate files. Changing `herdr-plugin.toml` after the install preview aborts the install — the user approved a specific manifest.

Herdr reports missing toolchains; it never installs them. A plugin needing `cargo`, `npm`, `bun`, or `lua` documents that itself.

## Versioning

`min_herdr_version` is a hard gate, not advice:

```
{"error":{"code":"plugin_requires_newer_herdr",
  "message":"plugin requires Herdr 99.0.0 or newer; current Herdr is 0.7.4"}}
```

Set it to the oldest herdr carrying every manifest field, API, and event name in use — not the version on the development machine. Overshooting locks out users for no reason; undershooting turns a clean error into a confusing runtime failure, because an event name the old binary lacks produces only an unknown-event warning.

Raise it when adopting a newer field or event. `version` is the plugin's own semver and carries no herdr meaning.

## Marketplace

The marketplace is an automatic index of public GitHub repositories carrying the topic `herdr-plugin`. There is no submission, review, or account.

To list a plugin: make the repo public, include a `herdr-plugin.toml`, add the `herdr-plugin` topic. The index refreshes every 30 minutes.

Plugins stay ordinary GitHub repos. Sharing is just `herdr plugin install owner/repo[/subdir]` — the marketplace is discovery, not a distribution channel.

## Trust

Herdr validates manifests and gives each plugin its own config and state directories. It does not review or sandbox anything. Build and runtime commands run as the user, with the user's environment, and can call the full herdr CLI.

That shapes what a published plugin owes its users: a manifest and scripts that read clearly, since `plugin install` shows a preview and users are told to skim it. Credentials go through `HERDR_PLUGIN_CONFIG_DIR` with a documented `.env`, never committed and never in the plugin root.

## Repo layout

One plugin per repo, or several in subdirectories — `install` takes a subdir path, which is how the official cookbook ships four plugins from `ogulcancelik/herdr-plugin-examples`:

```
herdr-plugin-examples/
  agent-telegram-notify/    node   — event hook, config dir, .env.example
  dev-layout-bootstrap/     lua    — action building a pane layout
  github-link-preview/      bash   — link handler + split pane
  rust-release-check/       rust   — build command, compiled binary
```

Each subdirectory holds its own `herdr-plugin.toml` and `README.md`. These are examples to copy, not maintained official plugins.

A `README.md` covering required toolchains, config keys, and the `herdr plugin config-dir <id>` setup step is the practical contract with users — nothing in the manifest conveys any of it.
