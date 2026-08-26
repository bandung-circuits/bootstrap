# Provider: Alibaba Cloud Bailian (国内默认)

阿里云百炼平台提供 Anthropic 兼容端点，可在 Claude Code 里把后端模型换成 DeepSeek V4 Flash 0731。

## 适用

- 中国大陆用户，有支付宝或中国实体。

## 注册与获取 API Key

1. 打开阿里云百炼控制台：https://bailian.console.aliyun.com/
2. 开通百炼服务（首次有免费额度）。
3. 进入 "API-KEY 管理" 创建 API Key，复制保存。

## bootstrap 自动写入的配置

`~/.claude/settings.json`:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://dashscope.aliyuncs.com/apps/anthropic",
    "ANTHROPIC_AUTH_TOKEN": "<你的百炼 API Key>",
    "ANTHROPIC_MODEL": "deepseek-v4-flash-0731"
  },
  "hasCompletedOnboarding": true
}
```

## 已知坑

- base URL 不可以 `/v1/` 结尾，否则 Claude Code 模型发现会拼成 `/v1/v1/models` 报 404。
- 百炼端点不提供模型列表接口，模型发现 404 是正常现象，靠 `ANTHROPIC_MODEL` 指定即可跳过。
- 国外用户通常无法订阅（要中国实体/支付宝）。国外请用 DeepSeek 官方端点，见 `deepseek-official.md`。
