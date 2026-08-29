# Agent Note: Claude Code project settings are tracked

Status: implemented

English | [中文](2026-08-29-tracked-claude-code-plugin-settings.zh.md)

## Problem

`.gitignore` excluded `.claude/settings.json`, so no Claude Code configuration could be shared across contributors. It also carried no rule for `.claude/settings.local.json`, the file Claude Code writes for per-contributor overrides, so a contributor's own settings appeared as untracked repository noise and could be committed by accident. The ignore rule covered the shared file and left the personal one exposed — the inverse of the scope split Claude Code defines.

The gap has a concrete cost on Claude Code for the web. Each web session starts from a fresh container, and those sessions have no interactive `/plugin` panel, so a plugin installed by hand is gone when the container is reclaimed and cannot be reinstalled interactively. Tracked `enabledPlugins` is the only path by which a plugin reaches a web session.

## Decision

`.gitignore` ignores `.claude/settings.local.json` in place of `.claude/settings.json`. Shared project settings are tracked and reviewed like any other repository configuration; per-contributor overrides stay local. `.claude/commands/` and `.claude/launch.json` remain ignored.

`.claude/settings.json` declares the `claude-watch` marketplace under `extraKnownMarketplaces`, sourced from the GitHub repository `RAMC-Management/claude-watch`, and enables `watch@claude-watch` under `enabledPlugins`. The plugin contributes the `/watch` skill and a `SessionStart` hook that reports whether the skill's binaries are present.

Declaring a marketplace does not install a plugin that comes from an external source. A contributor runs `claude plugin install watch@claude-watch` once per machine; until then Claude Code reports the plugin as not installed and prints that command.

The repository does not supply the skill's runtime dependencies. `/watch` shells out to `ffmpeg` and `yt-dlp`, and its transcription fallback reads `GROQ_API_KEY` or `OPENAI_API_KEY`. No repository gate, script, or setup step installs or requires them, and a machine without the API key still runs the caption path.

## Alternatives considered

**Keep `.claude/settings.json` ignored and install per machine.** This keeps every Claude Code choice personal and the repository free of editor configuration, but a web session container starts without the install and cannot run the interactive install path, so the plugin never reaches the surface that most needs it declared.

**Track `.claude/settings.json` without ignoring `.claude/settings.local.json`.** The smaller change tracks the shared file alone, but it leaves a contributor's personal overrides untracked and unignored, which is the failure the original rule was aimed at and the reason the two files exist separately.

**Vendor the plugin under `.claude/skills/`.** An in-tree copy loads with no install step and no marketplace, but it forks upstream source into this repository: updates become manual re-copies, and the copy's history diverges from `RAMC-Management/claude-watch` with nothing to reconcile it.

**Declare the marketplace at user scope only.** Enabling the plugin in tracked settings while its marketplace lives in an untracked user file splits one decision across two files, and a fresh checkout then names a marketplace it cannot resolve.

## Consequences

A contributor who trusts this repository folder gets the `claude-watch` marketplace without a further prompt, and one `claude plugin install` makes `/watch` available. Web sessions carry the declaration from the checkout.

That trust is the cost: the declaration points Claude Code at a third-party marketplace clone and, once installed, at a `SessionStart` hook that runs on every session. Both are repository-controlled and reviewable, which is why the declaration is tracked rather than personal.

Every future Claude Code setting added to `.claude/settings.json` — permissions, hooks, environment — is now a reviewed repository change. Local experiments belong in `.claude/settings.local.json`, which stays ignored.
