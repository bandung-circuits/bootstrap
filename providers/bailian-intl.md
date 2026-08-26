# Provider: Alibaba Cloud Model Studio (international, default for users outside China)

For users outside China: DeepSeek V4 Flash 0731 via Alibaba Cloud's international
Model Studio (Singapore entity, English UI, Visa/Mastercard). Verified against the
official alibabacloud.com docs (Anthropic-compatible endpoint + deepseek-v4-flash
listed as a supported third-party model).

## 适用

- 中国大陆以外的用户（默认路由）。

## 注册与获取 API Key

1. 打开国际 Model Studio 控制台：https://dashscope-intl.console.aliyun.com/
2. 注册 Alibaba Cloud International 账号（邮箱 + 国际手机号）。
3. 绑定 Visa/Mastercard，激活 Model Studio。
4. 在 "API Keys" 创建并复制 API Key。

## bootstrap 自动写入的配置

`~/ai-workspace/.claude/settings.local.json`:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://dashscope-intl.aliyuncs.com/apps/anthropic",
    "ANTHROPIC_AUTH_TOKEN": "<你的 Model Studio API Key>",
    "ANTHROPIC_MODEL": "deepseek-v4-flash"
  }
}
```

## 说明

- 国际端点 model 名用 `deepseek-v4-flash`（官方国际文档列的就是这个别名，自动指向 V4-Flash-0731）。
- base URL 同样不以 `/v1/` 结尾（百炼坑）。
- 该路径经 alibabacloud.com 官方文档核实，但未用真实国际 key 实测（CI 用的是国内百炼 key 测国内路径）。若有国际 key 可补充实测。
