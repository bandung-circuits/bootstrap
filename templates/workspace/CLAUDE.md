# CLAUDE.md — workspace rules for Claude Code

## Web tools: prefer crawl4ai
When you need to read a web page or search the web, prefer the crawl4ai MCP
(`mcp__crawl4ai__read_url` to fetch a page, `mcp__crawl4ai__search` to search).
It is free and needs no API key. If crawl4ai is unavailable for some reason,
fall back to WebFetch / WebSearch.

## Grounded search (avoid hallucination)
When you search the web, never trust a search summary alone. Fetch the real web
page (or PDF) in full with `mcp__crawl4ai__read_url` and read its actual content
before you answer. Cite the source URL in your reply.

## Backend
This workspace talks to DeepSeek V4 Flash 0731 through the provider configured in
`.claude/settings.local.json` (where you pasted your API key). No Anthropic sign-in
is needed.