# Provider: OpenRouter (fallback)

OpenRouter 是多模型聚合网关，一个 key 可调用几乎所有主流模型，包括 DeepSeek V4 Flash。适合想一个 key 通吃多家模型的用户。DeepSeek 走它会有中间加价。

## 适用

- 已有 OpenRouter 账号的用户。
- 想用一个 key 在多家模型间切换的用户。

## 注册与获取 API Key

1. 打开 https://openrouter.ai/
2. 注册账号，充值（支持信用卡）。
3. "Keys" 页创建 API Key，复制保存。

## 现状（待确认接法）

OpenRouter 官方文档明确其 API 是 **OpenAI 兼容**（非 Anthropic 兼容）。但 OpenRouter 上 DeepSeek V4 Flash 的模型页显示 Claude Code 通过它跑了 237B tokens，说明能用。两种可能接法：

1. OpenRouter 在某路径下接受 Anthropic Messages 格式（待核实是否存在 `/api/v1` 之外的 anthropic 端点）；
2. 或通过 Claude Code 对 OpenAI 兼容自定义 provider 的支持接入。

由于 DeepSeek 官方端点已是干净直连的国外主推路径，OpenRouter 仅作备选。实现期抓取 OpenRouter API reference 全文确认接法后再定稿下发配置；在确认前，`--provider=openrouter` 暂不保证可用，默认路由也不会选它（默认国外走 DeepSeek 官方）。

## 模型 slug（已确认）

OpenRouter 上 DeepSeek V4 Flash 的 slug 是 `deepseek/deepseek-v4-flash`（页面标注 "DeepSeek V4 Flash 0423"，OpenRouter 自动指向最新版）。
