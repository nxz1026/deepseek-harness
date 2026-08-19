# DeepSeek Harness — Windows 本地构建与服务端启动知识库

本仓库是 pnpm workspace monorepo（DeepSeek Harness，`@deepseek-ai/dsh`）。
本文记录在本机（Windows 11 / Node v24.14.0 / PowerShell 5.1）从源码构建并启动 Web 服务端的完整过程，以及踩过的坑，供后续重建参考。

核心理念：**一切从本地源码运行**，不打包、不分发 exe。
运行链路：`pnpm install` → `pnpm run build` → `dsh web`（`dsh` 为全局函数，内部用 `node --import tsx/esm ...` 直启，避开 Windows `process_title` 崩溃；**不要**用 `pnpm dsh web`）。

---

## 1. 环境结论

- Node.js：`^22.19.0 || >=24`（本机 v24.14.0，满足）。
- 包管理器：仓库 `package.json` 固定 `pnpm@11.7.0`。**corepack 与裸 `pnpm` 均为 11.7.0**：
  裸 `pnpm` 已通过 `npm i -g pnpm@11.7.0` 装到 `C:\Users\ND\AppData\Roaming\npm`（在 PATH 上），
  与 corepack 受 `packageManager` 固定的版本一致，可直接敲 `pnpm`（无需 `corepack` 前缀）。
- `corepack enable` 因无管理员权限失败（写 `C:\Program Files\nodejs\pnpm` 报 `EPERM`），
  故走 npm 全局安装而非 corepack shim；版本一致，行为无差异。
- **服务端启动禁止走 pnpm**：`pnpm dsh web` 在 Windows 会让 pnpm 重定向 node 的 stdio，
  触发 Node `Assertion failed: process_title, file src\win\util.c`（STATUS_STACK_BUFFER_OVERRUN），
  必须用 `node --import tsx/esm apps/cli/src/bin.ts web` 直启（即全局 `dsh` 函数）。
- 沙箱：landlock 仅 Linux（`native/landlock-run` 明确 win32 不支持）；Windows 走
  `sandbox-windows-acl`（`WRITE_RESTRICTED` token，`enforcement: 'partial'`），开箱即用，无需额外配置。
- Python SDK 的 `scripts/build-exe-for-python-sdk.ts` 明确不支持 Windows（仅 linux/macos），
  因此"编译"指从源码构建并用 `dsh` 启动，不是打单文件 exe。

---

## 2. 一键脚本

仓库根目录提供 `build.ps1` 一键重建（install + build:lib + web 前端）。

> 启动 / 托盘脚本（`start-dsh-web.ps1`、`start-dsh-web.bat`、`dsh-tray.ps1`、
> `tail-dsh-web-logs.ps1`、`dsh-web-launcher.lnk`）已随托盘功能迁移到独立项目，
> 本仓库不再提供；自定义端口 / 主机、无窗口启动、托盘控制等能力请使用迁移后的项目。

```powershell
# 重建
.\build.ps1

# 启动服务端（node 直启，已规避坑 1a）
dsh web
```

---

## 3. 构建踩坑清单

### 坑 1：`corepack enable` 无权限，改用 npm 全局装 pnpm（版本须 = packageManager）
- 现象：`corepack enable` 报 `EPERM: operation not permitted, open 'C:\Program Files\nodejs\pnpm'`。
- 影响：`corepack enable` 无法把 pnpm shim 写进 Node 安装目录，裸 `pnpm` 不在 PATH。
- 解决：用 `npm i -g pnpm@11.7.0`（版本须与仓库 `packageManager` 固定值一致）装到
  `Roaming\npm`，裸 `pnpm` 即可用，且与 corepack 版本一致。
- 注意：**绝不可用 `pnpm dsh web` 启动服务端**（见坑 1a）。

### 坑 1a：Windows 上 `pnpm dsh web` 崩溃（process_title 断言）
- 现象：`corepack pnpm dsh web` / `pnpm dsh web` 启动即崩，Node 报
  `Assertion failed: process_title, file src\win\util.c` / 退出码 `-1073740791 (0xC0000409)`。
- 根因：pnpm 在拉起 node 子进程时重定向 stdio，触发 Node Windows 层 `process_title` 断言；
  与 pnpm 版本、是否 corepack 无关。
- 解决：服务端一律用 node 直启：`node --import tsx/esm apps/cli/src/bin.ts web`。
  交互环境直接敲 `dsh web`（已写进 `$PROFILE` 的全局函数）。

### 坑 2（已缓解）：`pnpm run build` 整体卡最后一步
- 原现象：`pnpm run build` 跑到 `build:web` 报 `'pnpm' 不是内部或外部命令`（`ELIFECYCLE`），
  因为 `build:web` 内裸调用 `pnpm --filter @deepseek-ai/dsh-web-frontend run build`，
  而当时裸 `pnpm` 不在 PATH。
- 现状：裸 `pnpm` 已在 PATH（坑 1 解决后），`pnpm run build` 可完整跑通；
  `build.ps1` 仍是一键推荐脚本。

### 坑 3：PowerShell 5.1 读取无 BOM 的 UTF-8 会解析乱码（中文引号字符串）
- 现象：用 `Write-Host "未找到 .env ($envFile)..."` 时，PowerShell 报
  `字符串缺少终止符` / `TerminatorExpectedAtEndOfString`，且错误行号漂移。
- 根因：PowerShell 5.1 按系统代码页读取无 BOM 的 UTF-8 `.ps1`，中文被误读，
  导致字符串边界错乱。
- 解决：**`.ps1` 脚本内所有提示与注释一律用 ASCII**（本仓库的 `*.ps1` 已改为全 ASCII）。
  Markdown / 文本文档不受此限，可正常用中文。

### 坑 4：`Start-Process` 不能把 stdout 和 stderr 重定向到同一文件
- 现象：`Start-Process ... -RedirectStandardOutput x -RedirectStandardError x` 报
  `RedirectStandardOutput 和 RedirectStandardError 不能指向同一文件`。
- 解决：smoke test 时拆成两个日志文件再合并读取。

### 坑 5：API key 变量名不匹配
- 现象：harness 读取 `DEEPSEEK_API_KEY`；而本机共享 `.env`（`E:\2026Workplace\Code\.env`）
  里是 `DEEPSEEK_KEY`。
- 解决：把 `DEEPSEEK_API_KEY=sk-...` 写进仓库根 `.env`，或设置
  `$env:DSH_ENV_FILE='E:\2026Workplace\Code\.env'` 并在启动前手动映射
  `$env:DEEPSEEK_API_KEY = $env:DEEPSEEK_KEY`。

### 坑 6：landlock / Python exe 不适用 Windows
- landlock 沙箱仅 Linux（`win32` 平台被跳过，属预期）。Windows 自动走 ACL 沙箱。
- `scripts/build-exe-for-python-sdk.ts` 的 `PLATFORMS = ['linux','macos']`，
  Windows 是 documented non-goal，不要尝试给 Python SDK 打 Windows exe。

### 坑 7：dshmarket / 新鲜插件安装被供应链策略拦截
- 现象：`dsh plugin --profile web add <新插件>` 或在该 profile 目录跑 `pnpm install` 报
  `ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION`，因 pnpm `verifyDepsBeforeRun` 的
  `minimumReleaseAge`（约 24h）拦截当天发布的新包（如 `dshmarket` 自身）。
- 后果：安装中断、`dsh.profile.bundles` 已写入但 `node_modules`/lockfile 未定稿，
  下次启动报 `cannot resolve profile bundle`。
- 解决：web profile 目录 `C:\Users\ND\.dsh\profiles\web\.npmrc` 已写
  `verify-deps-before-run=false`（仅作用于该 profile），放宽后安装可完整跑完。

### 坑 8：`Start-Process` 重定向日志里中文乱码（GBK 写入）
- 现象：`Start-Process -RedirectStandardOutput` 重定向的日志里中文变乱码（如 lark-link
  警告显示为 `鏈鏈...` 或 `δ...`）。
- 根因：重定向把服务端输出按**系统 ANSI 代码页（zh-CN 为 GBK）**写进日志文件，
  并非 UTF-8；按 UTF-8 或默认读取即乱码。
- 解决：先强制控制台 UTF-8（`chcp 65001` + `[Console]::OutputEncoding`），再把
  `Get-Content` 默认编码设为 `Default`（= 系统 ANSI，与写入代码页一致）来还原中文。

### 坑 9：`dsh web` 多实例因 task-board ledger 全局锁崩溃（只能单开）
- 现象：本机已有一个 `dsh web` 在跑（任意端口），再启动第二个实例，第二个在加载
  `@linxin666/dsh-client-ui-task-board` 时报
  `Error: task-board ledger is already owned by process <PID>` 然后退出。
- 根因：该插件的 `HostTaskLedger` 按**用户/全局**加锁，不是按端口；所以两个实例端口不同，
  第二个也会因锁已被第一个持有而失败。
- 影响：若 3080 之外还有别的 `dsh web` 在跑，新实例仍会撞锁崩溃。
- 解决 / 注意：**同一时间只能有一个 `dsh web` 实例**。启动新实例前先停掉其它实例
  （按占用端口找到进程并 `Stop-Process`）。

---

## 4. 验证记录

- `dsh --help`（全局函数，内部 `node --import tsx/esm ...`）：正常输出 CLI 帮助，确认从源码（`tsx`）启动链路可用。
- Web 服务 smoke test：后台以 `--port 18080` 启动，输出 `dsh web: http://127.0.0.1:18080`，
  TCP 探测 `LISTENING: True`，进程树可正常清理。证明服务端确实能起来。
- 原生模块 node-pty / koffi 均通过预编译（prebuild）安装，无需本机编译工具链。

---

## 5. 后续重建速查

```powershell
# 若依赖或 lockfile 有变化，先安装；否则可只跑下面两步
pnpm install                       # 裸 pnpm 已在 PATH，版本 = corepack = 11.7.0
pnpm run build:lib
pnpm --filter @deepseek-ai/dsh-web-frontend run build

# 启动
$env:DSH_ENV_FILE = 'E:\2026Workplace\Code\.env'   # 提供 DEEPSEEK_KEY（或写入仓库根 .env）
dsh web                            # 全局函数，node 直启，避开 pnpm process_title 崩溃
```
