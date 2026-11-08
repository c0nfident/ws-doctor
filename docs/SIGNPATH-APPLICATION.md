# SignPath Foundation 免费开源签名 — 申请与接入

本项目选择 **SignPath Foundation** 免费代码签名路线（OV 级证书，私钥由 SignPath 的 HSM 保管，签名在 CI 中自动完成）。
本文件是申请清单、配置步骤和发布流程。

## 官方链接

- 申请入口：<https://signpath.org/apply>
- 项目条件（务必先读）：<https://signpath.org/terms.html>
- GitHub 集成文档：<https://docs.signpath.io/trusted-build-systems/github>
- Artifact Configuration 示例：<https://docs.signpath.io/artifact-configuration/examples>
- 已获签名的项目列表：<https://signpath.org/projects>

## 资格自查（对照 terms.html）

| 条件 | 本仓库状态 |
|---|---|
| 使用 OSI 认证开源许可证、无商业双许可 | ✅ MIT（`LICENSE`） |
| 无专有/闭源代码 | ✅ 全部源码可见（PS 模块 + C# GUI） |
| 活跃维护 | ✅ 持续发布（CHANGELOG / Releases） |
| **已经发布过**（申请前必须） | ⬜ 推送后先跑 `.github/workflows/release-unsigned.yml` 发一个 release |
| 功能有文档说明 | ✅ `README.md` + `docs/README.md` |
| 首页有 Code signing policy | ✅ `README.md` 的 Code signing policy 段 |
| 隐私政策声明 | ✅ "不向其他联网系统传输信息" |
| 提供卸载方式（安装类程序） | ✅ 绿色版，删除目录即卸载 |
| 维护者开启 MFA | ⬜ 请在 GitHub 账号设置中确认已开启 2FA |
| 指定角色：Authors / Reviewers / Approvers | ✅ 单维护者 `@c0nfident`（README 已写明） |
| 签名产物 metadata 约束（product-name/version） | ✅ `signpath/artifact-configuration.xml` |
| 所有构建 job 使用 GitHub 托管 runner | ✅ `.github/workflows/release-signed.yml` |

> ⚠️ 注意：SignPath 明确说明 **新项目可能因"无法验证项目声誉"被拒**。建议先发布 2–3 个版本、积累 star/下载量后再申请；若被拒，备选方案见文末。

## 申请步骤

### 第 1 步：发布仓库（必须公开）

```powershell
cd D:\1Work\项目\ws-doctor

# 仓库已在本地初始化好（main 分支、v1.4.0 tag）
# 在 GitHub 网页创建空仓库 c0nfident/ws-doctor（Public，不要勾选 README/LICENSE）
git remote add origin https://github.com/c0nfident/ws-doctor.git
git push -u origin main
git push origin v1.4.0
```

（或用 GitHub CLI：`gh repo create c0nfident/ws-doctor --public --source . --push`）

推送后检查：

1. `.github/workflows/ci.yml` 两个 job 全绿
2. tag `v1.4.0` 触发 `.github/workflows/release-unsigned.yml`，产生第一个 unsigned Release（满足"已发布"条件）

### 第 2 步：提交 Foundation 申请

打开 <https://signpath.org/apply>，按下面模板填写（英文）：

```
Project name: WsDoctor
Repository URL: https://github.com/c0nfident/ws-doctor
License: MIT (OSI-approved)
Project description: WsDoctor is a Windows workspace maintenance tool (PowerShell 7 module + C# WinForms GUI)
  to scan directories, find large/duplicate files, clean empty directories, audit workspace rules and export reports.
  The GUI is also published as a self-contained Windows executable.
Download page: https://github.com/c0nfident/ws-doctor/releases
Build workflow: https://github.com/c0nfident/ws-doctor/blob/main/.github/workflows/release-signed.yml
Maintainer / GitHub handle: c0nfident
Contact email: <你的邮箱>
Signing needs: Authenticode SHA256 for WsDoctorGui.exe (self-contained single-file WinForms app)
  built by GitHub Actions on windows-latest. Artifact is uploaded as a ZIP (root <zip-file>).
I confirm: MIT license, no proprietary components, no malware, MFA enabled, I am the owner and approver.
```

### 第 3 步：审核通过后配置 SignPath

登录 <https://app.signpath.io>：

1. **Organization**：确认 Foundation 已绑定你的 GitHub 账号组织
2. **Trusted Build System**：添加/确认 `GitHub.com`，并关联本项目（需要安装 [SignPath GitHub App](https://github.com/apps/signpath) 并授权仓库）
3. **Project**：`wsdoctor`（slug 建议 `wsdoctor`）
4. **Artifact Configuration**：新建，slug `wsdoctor-gui`，内容粘贴 `signpath/artifact-configuration.xml`
5. **Signing Policy**：新建 "Open Source Code Signing" 策略，slug `release-signing`，选择上面的 artifact configuration；
   Pipeline Policy 粘贴 `signpath/pipeline-policy.yml` 内容（强制 GitHub 托管 runner）；设置 Approver 为 `c0nfident`
6. **API Token**：Settings → API Tokens → 新建（角色：submitter，项目 wsdoctor / 策略 release-signing）

然后到 GitHub 仓库 → Settings：

**Secrets**
| 名称 | 值 |
|---|---|
| `SIGNPATH_API_TOKEN` | 上一步创建的 token |

**Variables**
| 名称 | 值 |
|---|---|
| `SIGNPATH_ORGANIZATION_ID` | SignPath 界面 Organization 页面显示的 ID |
| `SIGNPATH_PROJECT_SLUG` | `wsdoctor` |
| `SIGNPATH_ARTIFACT_CONFIGURATION_SLUG` | `wsdoctor-gui` |
| `SIGNPATH_SIGNING_POLICY_SLUG` | `release-signing` |

### 第 4 步：发布签名版本

```powershell
git tag v1.4.1
git push origin v1.4.1
```

流程：构建 → 上传 artifact → 提交 SignPath 签名请求 → **你在 SignPath 界面点击 Approve** → 下载签名产物 → 校验 →
创建/更新 GitHub Release（`release-signed.yml` 已实现）。

验证：

```powershell
Get-AuthenticodeSignature .\WsDoctorGui.exe | Format-List Status, StatusMessage, SignerCertificate
# Status : Valid
# SignerCertificate.Subject : CN=SignPath Foundation, ...
```

## 维护义务（签名后）

- 保持 README 的 **Code signing policy** 段更新（角色、隐私声明）
- 每次 release 需要在 SignPath 人工批准（Approver 角色）
- 不签名第三方/上游二进制；只签自己仓库构建的产物
- 遵守 SignPath Foundation Code of Conduct

## 备选方案（若申请被拒）

| 方案 | 说明 |
|---|---|
| **先积累声誉再申请** | 发布 2–3 个版本、README 完善、star/下载量上来后重新申请（推荐） |
| **Certum Open Source Code Signing** | 个人可申请，约 €50–150/年，需项目审核：<https://certum.eu/> |
| **Microsoft Store（MSIX）** | 上架后微软免费重签名，用户无 SmartScreen 提示；需 MSIX 打包与商店审核 |
| **Azure Artifact Signing** | ~$9.99/月，但个人仅限美国/加拿大（中国大陆不适用） |
| **自签名 + 企业分发** | 仅内部可用（证书通过 GPO/Intune 下发信任） |
