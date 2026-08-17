# DeepSeek Harness — Windows 本地构建与服务端启动知识库

本仓库是 pnpm workspace monorepo（DeepSeek Harness，`@deepseek-ai/dsh`）。
本文记录在本机（Windows 11 / Node v24.14.0 / PowerShell 5.1）从源码构建并启动 Web 服务端的完整过程，以及踩过的坑，供后续重建参考。

核心理念：**一切从本地源码运行**，不打包、不分发 exe。
运行链路：`pnpm install` → `pnpm run build` → `corepack pnpm dsh web`。

---

## 1. 环境结论

- Node.js：`^22.19.0 || >=24`（本机 v24.14.0，满足）。
- 包管理器：仓库 `package.json` 固定 `pnpm@11.7.0`，通过 **corepack** 启动。
- **`pnpm` 不在系统 PATH 上**。本机 `corepack enable` 因无管理员权限失败
  （写 `C:\Program Files\nodejs\yarn` 报 `EPERM`），所以全环境只能用 `corepack pnpm`，
  不能直接敲 `pnpm`。
- 沙箱：landlock 仅 Linux（`native/landlock-run` 明确 win32 不支持）；Windows 走
  `sandbox-windows-acl`（`WRITE_RESTRICTED` token，`enforcement: 'partial'`），开箱即用，无需额外配置。
- Python SDK 的 `scripts/build-exe-for-python-sdk.ts` 明确不支持 Windows（仅 linux/macos），
  因此"编译"指从源码构建并用 `dsh` 启动，不是打单文件 exe。

---

## 2. 一键脚本

仓库根目录已提供：

| 文件 | 作用 |
|---|---|
| `build.ps1` | 一键重建：install + build:lib + web 前端 |
| `start-dsh-web.ps1` | 加载 `.env`、映射 key、前台启动 `dsh web` |
| `start-dsh-web.bat` | 双击入口（调用上面的 ps1） |

用法：
```powershell
# 重建
.\build.ps1

# 启动服务端（默认 http://127.0.0.1:8080）
.\start-dsh-web.bat
# 或自定义端口 / 监听所有网卡
powershell -ExecutionPolicy Bypass -File start-dsh-web.ps1 --port 8080 --host 0.0.0.0
```

---

## 3. 构建踩坑清单

### 坑 1：`corepack enable` 无权限，pnpm 无法进 PATH
- 现象：`corepack enable` 报 `EPERM: operation not permitted, open 'C:\Program Files\nodejs\yarn'`。
- 影响：直接敲 `pnpm` 命令 `CommandNotFoundException`。
- 解决：永远用 `corepack pnpm ...` 代替 `pnpm ...`。脚本里也一律用 `corepack pnpm`。

### 坑 2：`pnpm run build` 整体会卡在最后一步
- 现象：`pnpm run build` 跑到 `build:web` 阶段报
  `'pnpm' 不是内部或外部命令`（即 `ELIFECYCLE`）。
- 根因：`package.json` 中 `build:web` 是 `"pnpm --filter @deepseek-ai/dsh-web-frontend run build"`，
  该子步骤裸调用 `pnpm`，而本机 `pnpm` 不在 PATH。
- 解决：拆成两半执行（即 `build.ps1` 的做法）：
  ```powershell
  corepack pnpm run build:lib
  corepack pnpm --filter @deepseek-ai/dsh-web-frontend run build
  ```
  （`build:lib` 内部用 `tsc -b` + `tsdown`，不依赖裸 `pnpm` 子调用，可正常完成。）

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
- 解决：`start-dsh-web.ps1` 已加 fallback——若缺 `DEEPSEEK_API_KEY` 但存在 `DEEPSEEK_KEY`，
  自动映射。运行前设置 `$env:DSH_ENV_FILE='E:\2026Workplace\Code\.env'` 即可开箱即用；
  或把 `DEEPSEEK_API_KEY=sk-...` 写进仓库根 `.env`。

### 坑 6：landlock / Python exe 不适用 Windows
- landlock 沙箱仅 Linux（`win32` 平台被跳过，属预期）。Windows 自动走 ACL 沙箱。
- `scripts/build-exe-for-python-sdk.ts` 的 `PLATFORMS = ['linux','macos']`，
  Windows 是 documented non-goal，不要尝试给 Python SDK 打 Windows exe。

---

## 4. 验证记录

- `corepack pnpm dsh --help`：正常输出 CLI 帮助，确认从源码（`tsx`）启动链路可用。
- Web 服务 smoke test：后台以 `--port 18080` 启动，输出 `dsh web: http://127.0.0.1:18080`，
  TCP 探测 `LISTENING: True`，进程树可正常清理。证明服务端确实能起来。
- 原生模块 node-pty / koffi 均通过预编译（prebuild）安装，无需本机编译工具链。

---

## 5. 后续重建速查

```powershell
# 若依赖或 lockfile 有变化，先安装；否则可只跑下面两步
corepack pnpm install
corepack pnpm run build:lib
corepack pnpm --filter @deepseek-ai/dsh-web-frontend run build

# 启动
$env:DSH_ENV_FILE = 'E:\2026Workplace\Code\.env'   # 提供 DEEPSEEK_KEY
.\start-dsh-web.bat
```
