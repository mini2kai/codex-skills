$ErrorActionPreference = "Stop"

try {
    irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex
    Install-CodexSkill lark-cli-config
}
catch {
    Write-Host "安装失败：$($_.Exception.Message)" -ForegroundColor Red
}
