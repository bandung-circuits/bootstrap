# AGENTS.md — Workspace Conventions

This file defines the working conventions for AI agents (and humans) operating in this workspace. Agents opened in this folder are expected to follow it.

## 1. Default working language: English

- The default working language of this workspace is **simple, plain English**.
- All agent outputs, documentation, and deliverables default to English, unless a task explicitly requests another language.
- This workspace is being prepared as a training template for **non-technical AI beginners**. Write for that audience: short sentences, common vocabulary, concrete examples, and no jargon without a one-line explanation.

## 2. Grounded search principles

These rules apply whenever an agent searches the web or consults external sources.

**Search summaries are not trustworthy — always fetch the full text of the original page before citing anything.**

Reference: [BHV-05 Grounded Web Research](https://github.com/eXtremeProgramming-cn/pomasa/blob/main/skills/pomasa/pattern-catalog/BHV-05-grounded-web-research.md)

1. **Locate sources first.** Use search only to find potentially relevant sources; never treat summaries, snippets, or cached snapshots as evidence.
2. **Verify against the original.** All key information — conclusions, numbers, names, and attributions — must be checked against the full text of the original page or the original source file.
3. **Cite to origin.** Every claim written into an output must trace back to an original source text. Any statement that cannot be supported by an original source must not be included in the output.

## 3. The `.dsh/` folder is the harness home, not your files

`~/ai-workspace/.dsh/` is the DeepSeek Harness home (settings, credentials, plugins, session logs). Treat it as machinery:
- Never edit or delete files under `.dsh/` unless a task explicitly asks for a config change.
- Prefer storing new work in the workspace root or a project subfolder.

## 4. Scope note

Additional conventions (web tooling, safety defaults, packaging) will be added to this file in later iterations.