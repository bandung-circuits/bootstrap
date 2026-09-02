# Provider: DeepSeek 官方（备选）

DeepSeek 官方平台原生提供 Anthropic 兼容端点（`https://api.deepseek.com/anthropic`），直连无中间商。想用 DeepSeek 自家平台而非阿里生态的用户可显式选 `--provider=deepseek`。

## 适用

- 想直连 DeepSeek、用其自家平台的用户（备选）。

## 注册与获取 API Key

1. 打开 DeepSeek 开放平台：https://platform.deepseek.com/
2. 注册账号，绑定信用卡充值（按量计费，DeepSeek V4 Flash 极便宜）。
3. 进入 "API Keys" 创建并复制 API Key。

## bootstrap 自动写入的配置

```yaml
# ~/ai-workspace/.dsh/settings.yaml
llm-pi-ai:
  providers:
    deepseek:
      apiKeyEnv: DSH_API_KEY
      api: anthropic
      baseURL: https://api.deepseek.com/anthropic
      models:
        - id: deepseek-v4-flash
```

密钥在 `~/ai-workspace/.dsh/.env` 的 `DSH_API_KEY=` 行（或 Web UI Settings → Models 粘贴）。

## 依据

官方文档（api-docs.deepseek.com）明确：Anthropic 兼容 base URL = `https://api.deepseek.com/anthropic`；`deepseek-v4-flash` 已更新为 V4-Flash-0731，调用方式不变。dsh 底座也自带原生 DeepSeek 适配器（Settings → Models 里的 "DeepSeek" 卡片即它），若想完全默认走官方原生路径，可在 Web UI 里直接用 DeepSeek 卡片添加密钥而不用本配置。