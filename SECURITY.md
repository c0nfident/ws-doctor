# 安全策略 / Security Policy

## 报告漏洞

请通过 GitHub Security Advisories 私密报告，或邮件联系维护者（见仓库 Owner 资料）。
请勿在公开 Issue 中披露未修复的安全问题。

## 敏感信息

- 本仓库**不包含**任何代码签名私钥、API key 或 token。
- `gui/signing/*.pfx`、`gui/.dotnet-home/`、`dist*/`、`gui/bin/`、`gui/obj/` 均被 `.gitignore` 排除。
- 发布签名由 SignPath Foundation 在 HSM 中完成（详见 `README.md` 的 Code signing policy）。

## 支持的版本

| 版本 | 支持 |
|---|---|
| 1.4.x | ✅ |
| < 1.4 | ❌ |
