# Provider: Alibaba Cloud Bailian (国内默认)

阿里云百炼平台提供 Anthropic 兼容端点，可让 DeepSeek Harness（dsh）把后端模型接到 DeepSeek V4 Flash 0731。

## 适用

- 中国大陆用户，有支付宝或中国实体。

## 注册与获取 API Key

1. 打开阿里云百炼控制台：https://bailian.console.aliyun.com/
2. 开通百炼服务（首次有免费额度）。
3. 进入 "API-KEY 管理" 创建 API Key，复制保存。

## bootstrap 自动写入的配置

dsh 方案把模型路由写进 `~/ai-workspace/.dsh/settings.yaml`（`llm-pi-ai` 插件），密钥写在 `~/ai-workspace/.dsh/secrets.env` 的 `DSH_API_KEY=` 行（也可在 Web UI 的 Settings → Models 里粘贴）：

```yaml
# ~/ai-workspace/.dsh/settings.yaml
llm-pi-ai:
  providers:
    bailian:
      apiKeyEnv: DSH_API_KEY
      api: anthropic
      baseURL: https://dashscope.aliyuncs.com/apps/anthropic
      models:
        - id: deepseek-v4-flash-0731
```

## 已知坑

- base URL 是 Anthropic 兼容端点（`/apps/anthropic`）。pi-ai 对不认识地址的请求默认按 OpenAI 处理；`api: anthropic` 显式声明走 Anthropic 协议（实现期已用 `dsh web --dump-config` 实测核实；若上游协议名变化，逃生路线是 `api: openai-completions` + `compat: {supportsDeveloperRole: false, maxTokensField: max_tokens}`）。
- 国外用户通常无法订阅（要中国实体/支付宝）。国外默认走百炼国际端点或 DeepSeek 官方，见 `bailian-intl.md` / `deepseek-official.md`。