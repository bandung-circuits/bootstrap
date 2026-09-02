# Provider: Alibaba Cloud Model Studio (国际)

阿里云国际版（Model Studio / DashScope intl）同样提供 Anthropic 兼容端点，托管 DeepSeek V4 Flash。给大陆以外、用 Visa/Mastercard 订阅的用户。

## 适用

- 中国大陆以外用户（默认路径）。
- 想统一在阿里平台管理、避免自己搭的用户。

## 注册与获取 API Key

1. 打开 Model Studio 国际站：https://dashscope-intl.console.aliyun.com/
2. 注册（海外账号，信用卡开通）。
3. 创建 API Key，复制保存。

## bootstrap 自动写入的配置

```yaml
# ~/ai-workspace/.dsh/settings.yaml
llm-pi-ai:
  providers:
    bailian-intl:
      apiKeyEnv: DSH_API_KEY
      api: anthropic
      baseURL: https://dashscope-intl.aliyuncs.com/apps/anthropic
      models:
        - id: deepseek-v4-flash
```

密钥在 `~/ai-workspace/.dsh/secrets.env` 的 `DSH_API_KEY=` 行（或 Web UI Settings → Models 粘贴）。

## 已知坑

- 同百炼国内：Anthropic 兼容端点，`api: anthropic` 显式声明协议；协议名变更时逃生路线同 `bailian.md` 末尾。