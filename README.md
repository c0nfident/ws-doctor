# WsDoctor · 工作区体检

[![CI](https://github.com/c0nfident/ws-doctor/actions/workflows/ci.yml/badge.svg)](https://github.com/c0nfident/ws-doctor/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**WsDoctor** 是一个 Windows 工作区体检工具：扫描目录、找大文件、查重复文件、清理空目录、规则体检、导出报告，并带一个 C# WinForms 前端（C# 16 个语言知识点全覆盖，前端通过 PowerShell 桥接调用核心模块）。

- PowerShell 7 模块 + CLI：`WsDoctor.psm1` / `wsdoctor.ps1`
- C# WinForms GUI：`gui/`（Roslyn 动态编译 + .NET SDK csproj 两种构建方式）
- 自包含发布：免安装 .NET 的单文件 exe
- 代码签名：本项目**正在申请 SignPath Foundation 免费开源签名**（见下文 Code signing policy）

## 快速开始

### 方式一：下载 release（推荐）

1. 到 [Releases](https://github.com/c0nfident/ws-doctor/releases) 下载最新 `wsdoctor-gui-*-selfcontained-signed.zip`（免 .NET）
2. 解压后运行 `WsDoctorGui.exe`（需要 [PowerShell 7](https://aka.ms/powershell-release?setchannel=Stable)）
3. 校验：`Get-AuthenticodeSignature .\WsDoctorGui.exe`（签名版 Status=Valid）

### 方式二：从源码运行

```powershell
git clone https://github.com/c0nfident/ws-doctor.git
cd ws-doctor
Import-Module .\WsDoctor.psd1
Invoke-WsScan -Path D:\1Work            # 目录扫描
Find-WsDuplicateFile -Path D:\1Work     # 重复文件（两阶段哈希）
```

GUI 构建：

```powershell
cd gui
.\build-exe.ps1                  # 标准 .NET SDK 构建
.\publish-selfcontained.ps1      # 自包含单文件（免 .NET）
.\build.ps1                      # Roslyn 动态编译（无 SDK 也可）
```

## 功能

| 功能 | 命令 / GUI |
|---|---|
| 目录扫描（串行/并行 DirBucket/Subtree/Chunk） | `Invoke-WsScan` / 「扫描」 |
| 大文件 TopN、目录占用 | 扫描结果 / 「目录」「大文件」页 |
| 重复文件（枚举剪枝 + 两阶段取样哈希 + 并行） | `Find-WsDuplicateFile` / 「重复文件」 |
| 空目录清理（支持 DryRun） | `Remove-WsEmptyDirectory` / 「清空目录」 |
| 工作区规则体检 | `Invoke-WsWorkspaceAudit` / 「规则体检」 |
| 报告导出（JSON/CSV/HTML） | `Export-WsReport` / 「导出报告」 |
| 预计加载时间（扫描/重复检测先估算再确认） | GUI 弹窗 |

性能参考（`D:\1Work`，17.6 GB 候选）：重复检测从 203.9s 优化到 **5.6s（热缓存）/ 40s（冷缓存）**；扫描预计 2–3s。

## 兼容性

- Windows 10 22H2 / Windows 11，x64
- self-contained 包**无需安装 .NET**；框架依赖包需要 .NET 10 Desktop Runtime
- 需要 **PowerShell 7**（启动时自动检测并提示）
- 普通用户权限（asInvoker）

## 构建与测试

```powershell
# 模块质量门禁（lint + Pester 50 项 + 可选覆盖率）
.\build.ps1

# GUI 构建 + C# 自检 73 项 + UI 回归 + 集成测试
cd gui
.\build-exe.ps1
.\dist-exe\WsDoctorGui.exe --selftest
.\dist-exe\WsDoctorGui.exe --uitest
.\dist-exe\WsDoctorGui.exe --integration
```

CI 配置见 `.github/workflows/ci.yml`（模块测试 + GUI 构建/自检/集成）。

## Code signing policy

**Free code signing provided by [SignPath.io](https://about.signpath.io), certificate by [SignPath Foundation](https://signpath.org).**

- Committers and reviewers: [@c0nfident](https://github.com/c0nfident)（仓库 Owner，见 [People](https://github.com/c0nfident)）
- Approvers: [@c0nfident](https://github.com/c0nfident)（每个 release 的签名请求需人工批准）
- Privacy policy: **This program will not transfer any information to other networked systems unless specifically requested by the user or the person installing or operating it.**（本程序只读取用户指定的本地目录，不联网传输数据）
- 签名工作流：`.github/workflows/release-signed.yml`，artifact 配置：`signpath/artifact-configuration.xml`
- 申请与接入说明：[docs/SIGNPATH-APPLICATION.md](docs/SIGNPATH-APPLICATION.md)

## 目录结构

```
WsDoctor.psd1 / WsDoctor.psm1    PowerShell 模块（核心）
wsdoctor.ps1                     CLI
build.ps1 / lint-wsdoctor.ps1    质量门禁（Pester 3.4 + AST lint）
tests/                           Pester 测试
gui/                             C# WinForms 前端（含 bridge、签名、self-contained 发布脚本）
docs/                            使用文档、CHANGELOG、兼容性、SignPath 申请说明
signpath/                        SignPath artifact configuration / pipeline policy 草稿
```

## License

[MIT](LICENSE)
