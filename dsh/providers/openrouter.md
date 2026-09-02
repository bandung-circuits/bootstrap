# Provider: OpenRouter（备选）

OpenRouter 是多模型聚合网关，一个 key 可调用几乎所有主流模型，包括 DeepSeek V4 Flash。适合想一个 key 通吃多家模型的用户。DeepSeek 走它会有中间加价，仅作备选。

## 适用

- 已有 OpenRouter 账号的用户。
- 想用一个 key 在多家模型间切换的用户。

## 注册与获取 API Key

1. 打开 https://openrouter.ai/
2. 注册账号，充值（支持信用卡）。
3. "Keys" 页创建 API Key，复制保存。

## bootstrap 自动写入的配置

OpenRouter 是 **OpenAI 兼容**（非 Anthropic 兼容），所以 dsh route 用 `api: openai-completions`，并带 pi-ai 对 OpenAI 兼容网关的官方兼容开关（拒绝 developer role、只认 `max_tokens`）：

```yaml
# ~/ai-workspace/.dsh/settings.yaml
llm-pi-ai:
  providers:
    openrouter:
      apiKeyEnv: DSH_API_KEY
      api: openai-completions
      baseURL: https://openrouter.ai/api/v1
      compat:
        supportsDeveloperRole: false
        maxTokensField: max_tokens
      models:
        - id: deepseek/deepseek-v4-flash
```

密钥在 `~/ai-workspace/.dsh/secrets.env` 的 `DSH_API_KEY=` 行（或 Web UI Settings → Models 粘贴）。

## 模型 slug（已确认）

OpenRouter 上 DeepSeek V4 Flash 的 slug 是 `deepseek/deepseek-v4-flash`（页面标注 "DeepSeek V4 Flash 0423"，OpenRouter 自动指向最新版）。