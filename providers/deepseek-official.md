# Provider: DeepSeek official (fallback)

DeepSeek 官方平台原生提供 Anthropic 兼容端点。直连无中间商。现在作为**备选**（默认国外路径已改为百炼国际）；想用 DeepSeek 自家平台而非阿里的用户可选这个。

## 适用

- 想直连 DeepSeek、用其自家平台的用户（备选）。


## 注册与获取 API Key

1. 打开 DeepSeek 开放平台：https://platform.deepseek.com/
2. 注册账号，绑定信用卡充值（按量计费，DeepSeek V4 Flash 极便宜）。
3. 进入 "API Keys" 创建并复制 API Key。

## bootstrap 自动写入的配置

`~/.claude/settings.json`:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.deepseek.com/anthropic",
    "ANTHROPIC_AUTH_TOKEN": "<你的 DeepSeek API Key>",
    "ANTHROPIC_MODEL": "deepseek-v4-flash"
  },
  "hasCompletedOnboarding": true
}
```

## 依据

官方文档（api-docs.deepseek.com）明确：base_url (Anthropic) = `https://api.deepseek.com/anthropic`；`deepseek-v4-flash` 已更新为 V4-Flash-0731，调用方式不变。文档专门点名 Claude Code 可直接用 DeepSeek 做后端模型。
