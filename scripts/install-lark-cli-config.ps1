$ErrorActionPreference = "Stop"

irm https://raw.githubusercontent.com/mini2kai/codex-skills/main/scripts/install.ps1 | iex
Install-CodexSkill lark-cli-config
