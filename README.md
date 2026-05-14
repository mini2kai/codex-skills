# Codex Skills

This repository is a collection of Codex skills. Each subdirectory under `skills/` is a complete standalone skill that can be installed into the current user's Codex skills directory.

## Repository Layout

```text
codex-skills/
├── skills/
│   └── lark-cli-config/
│       ├── SKILL.md
│       ├── agents/
│       ├── references/
│       └── scripts/
├── scripts/
│   └── install.ps1
├── manifest.json
└── README.md
```

## Install With PowerShell

Recommended two-step install:

```powershell
Invoke-WebRequest https://raw.githubusercontent.com/lzsj/codex-skills/main/scripts/install.ps1 -OutFile install.ps1
powershell -ExecutionPolicy Bypass -File .\install.ps1 lark-cli-config
```

The command can be run from any directory. It installs to the current user's Codex skills directory:

```text
$HOME\.codex\skills\<skill-name>
```

It never depends on the directory where the command is executed.

## Install From A Local Clone

From this repository:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 lark-cli-config
```

List available skills:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -List
```

Install from a tag or branch:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 lark-cli-config -Ref v1.0.0
```

Replace an existing skill and keep a backup:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 lark-cli-config -Force
```

Backups are written under:

```text
$HOME\.codex\skills\.backup\<skill-name>-yyyyMMdd-HHmmss
```

## Optional One-Line Install

This style is convenient, but review the script first before using it in a team environment.

```powershell
iwr https://raw.githubusercontent.com/lzsj/codex-skills/main/scripts/install.ps1 -UseB | iex; Install-CodexSkill lark-cli-config
```

## Official Codex Installer

You can also install a skill with Codex's built-in skill installer:

```powershell
python $HOME\.codex\skills\.system\skill-installer\scripts\install-skill-from-github.py --repo lzsj/codex-skills --path skills/lark-cli-config
```

Restart Codex after installation so the new skill is loaded.

## PowerShell Installer Behavior

`scripts/install.ps1` follows these rules:

- Accepts `Skill`, `Repo`, `Ref`, `Force`, and `List` parameters.
- Uses the current user's home directory dynamically; no machine-specific user path is hard-coded.
- If run from a local clone, installs from local `skills/<skill-name>`.
- If run as a standalone downloaded script, downloads the GitHub repository zip and installs from `skills/<skill-name>`.
- Refuses to overwrite an existing skill by default.
- With `-Force`, moves the existing skill to `.backup` before copying the new one.
- Validates that the resolved destination stays inside `$HOME\.codex\skills`.
- Copies files only; it does not execute scripts inside the installed skill.

## Add A Skill

Each skill directory should be complete by itself:

```text
skills/<skill-name>/
├── SKILL.md
├── agents/
├── references/
└── scripts/
```

Keep the directory name and the `name` field in `SKILL.md` aligned.
