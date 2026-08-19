# Rebuild DeepSeek Harness from source on Windows (local source mode).
#
# Run from the repo root. Requires Node 22.19+/24+ and corepack (repo pins pnpm@11.7.0).
# NOTE: `pnpm` is NOT on PATH here (corepack enable needs admin), so every
# command uses `corepack pnpm`. `pnpm run build` as a whole FAILS because its
# build:web step calls bare `pnpm`, which is absent from PATH; we run the two
# halves explicitly instead.

$ErrorActionPreference = 'Stop'
$repoRoot = $PSScriptRoot
Set-Location -LiteralPath $repoRoot

# 1. Install dependencies (skip if already installed and the lockfile is unchanged).
corepack pnpm install

# 2. Build host + client libraries (tsc -b + tsdown).
corepack pnpm run build:lib

# 3. Build the web frontend (vite). Do NOT use `pnpm run build:web` here:
#    that npm-script step invokes bare `pnpm`, which is missing from PATH.
corepack pnpm --filter @deepseek-ai/dsh-web-frontend run build

Write-Host 'Build complete. Start the server with: dsh web'
