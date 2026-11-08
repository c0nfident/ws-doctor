# signpath/ — SignPath 签名配置草稿

| 文件 | 用途 |
|---|---|
| `artifact-configuration.xml` | 粘贴到 SignPath 项目的 **Artifact Configuration**。根元素是 `<zip-file>`（GitHub `upload-artifact` 默认打 ZIP）；只签 `WsDoctorGui.exe`，并强制 metadata：product-name=`WsDoctor GUI`、product-version/file-version=`${version}` |
| `pipeline-policy.yml` | 粘贴到 SignPath **Signing Policy → Pipeline Policy**。强制所有构建 job 跑在 GitHub 托管 runner 上 |

完整申请/接入步骤见 [`../docs/SIGNPATH-APPLICATION.md`](../docs/SIGNPATH-APPLICATION.md)。

签名工作流：`.github/workflows/release-signed.yml`（构建 → upload artifact → `signpath/github-action-submit-signing-request@v3` → 人工批准 → 校验 → 发布）。

> 本目录只包含配置草稿，不包含任何私钥/证书文件。SignPath 的证书和私钥在 HSM 中，不会进入本仓库。
