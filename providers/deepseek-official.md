# Provider: DeepSeek official (international default)

DeepSeek 官方平台原生提供 Anthropic 兼容端点。Claude Code 可直接用它做后端，无需中间商。model 名 `deepseek-v4-flash` 已自动指向最新的 V4-Flash-0731。

## 适用

- 国外用户（默认路由）。
- 国内用户想绕过百炼也可用（DeepSeek 官方平台接受国际信用卡）。

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
