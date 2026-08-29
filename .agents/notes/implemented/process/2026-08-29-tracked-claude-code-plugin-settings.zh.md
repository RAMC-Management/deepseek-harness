# Agent Note: Claude Code 项目设置纳入版本控制

Status: implemented

[English](2026-08-29-tracked-claude-code-plugin-settings.md) | 中文

## 问题

`.gitignore` 排除了 `.claude/settings.json`，因此任何 Claude Code 配置都无法在贡献者之间共享。它也没有为 `.claude/settings.local.json` 设置规则——而这正是 Claude Code 写入各贡献者个人覆盖配置的文件——于是贡献者的个人设置会以未跟踪文件的形式出现在仓库中，并可能被误提交。该忽略规则覆盖了共享文件、放过了个人文件，与 Claude Code 定义的作用域划分正好相反。

这一缺口在 Claude Code 网页版上有具体代价。每个网页会话都从全新容器启动，且这类会话没有交互式 `/plugin` 面板，因此手工安装的插件在容器回收后即消失，也无法通过交互方式重新安装。纳入版本控制的 `enabledPlugins` 是插件抵达网页会话的唯一途径。

## 决策

`.gitignore` 忽略 `.claude/settings.local.json`，取代原先的 `.claude/settings.json`。共享的项目设置像其他仓库配置一样纳入版本控制并接受评审；各贡献者的覆盖配置保持在本地。`.claude/commands/` 和 `.claude/launch.json` 继续被忽略。

`.claude/settings.json` 在 `extraKnownMarketplaces` 下声明 `claude-watch` 市场，来源为 GitHub 仓库 `RAMC-Management/claude-watch`，并在 `enabledPlugins` 下启用 `watch@claude-watch`。该插件提供 `/watch` 技能，以及一个报告技能所需二进制是否存在的 `SessionStart` hook。

声明市场并不会安装来自外部来源的插件。贡献者需在每台机器上执行一次 `claude plugin install watch@claude-watch`；在此之前 Claude Code 会报告插件未安装，并打印该命令。

本仓库不提供该技能的运行时依赖。`/watch` 调用 `ffmpeg` 和 `yt-dlp`，其转写回退路径读取 `GROQ_API_KEY` 或 `OPENAI_API_KEY`。没有任何仓库门禁、脚本或安装步骤会安装或要求它们，缺少 API key 的机器仍可走字幕路径。

## 曾考虑的替代方案

**继续忽略 `.claude/settings.json`，改为逐机器安装。** 这让每项 Claude Code 选择都保持个人化，仓库中也不含编辑器配置，但网页会话容器启动时并无该安装，且无法执行交互式安装路径，插件因此恰恰无法抵达最需要声明它的场景。

**纳入 `.claude/settings.json`，但不忽略 `.claude/settings.local.json`。** 这个改动更小，只跟踪共享文件，却让贡献者的个人覆盖配置处于既未跟踪也未忽略的状态——这正是原规则想要避免的问题，也正是两个文件分开存在的理由。

**把插件内联到 `.claude/skills/` 下。** 树内副本无需安装步骤和市场即可加载，但这会把上游源码分叉进本仓库：更新变成手工重新复制，副本的历史与 `RAMC-Management/claude-watch` 分道扬镳，且没有任何机制去对齐两者。

**只在用户作用域声明市场。** 在纳入版本控制的设置中启用插件、却把市场留在未跟踪的用户文件里，会把同一个决策拆到两个文件中，全新检出的仓库随后会引用一个无法解析的市场名。

## 后果

信任本仓库目录的贡献者无需额外确认即可获得 `claude-watch` 市场，一条 `claude plugin install` 即可使用 `/watch`。网页会话直接从检出内容中获得该声明。

这份信任就是代价：该声明将 Claude Code 指向一个第三方市场的克隆，插件安装后还指向一个在每次会话都会运行的 `SessionStart` hook。两者均由仓库控制、可供评审，这正是该声明纳入版本控制而非保持个人化的原因。

此后添加到 `.claude/settings.json` 的每一项 Claude Code 设置——权限、hook、环境变量——都成为经过评审的仓库变更。本地试验应放在 `.claude/settings.local.json`，该文件继续被忽略。
