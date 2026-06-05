from __future__ import annotations

from pathlib import Path
from typing import Optional

import typer
from InquirerPy import inquirer
from rich.table import Table

from .constants import DEFAULT_REF, DEFAULT_REPO, default_targets
from .doctor import run_doctor
from .installer import install_skill
from .local_config import find_local_config_files
from .manifest import SkillManifest, read_remote_manifest
from .opener import open_path
from .paths import resolve_target_dir, short_path
from .records import short_commit
from .status import SkillStatus, find_status, get_skill_status
from .ui import console, make_status_table, print_banner, print_error, print_success, print_warning, section

app = typer.Typer(add_completion=False, invoke_without_command=True, help="漂亮的 M2K skills 命令行管理工具。")


class AppState:
    def __init__(self, repo: str, ref: str, target: str | None, skills_dir: str | None) -> None:
        self.repo = repo
        self.ref = ref
        self.target_was_explicit = bool(target or skills_dir)
        self.target_dir = resolve_target_dir(target, skills_dir)
        self.manifest: SkillManifest | None = None
        self.remote_commit: str | None = None


def _load_manifest(state: AppState) -> SkillManifest:
    if state.manifest is None:
        state.manifest = read_remote_manifest(state.repo, state.ref)
    return state.manifest


def _remote_commit(state: AppState) -> str:
    if state.remote_commit is None:
        from .github import download_repo_archive, get_ref_commit_or_ref

        state.remote_commit = get_ref_commit_or_ref(state.repo, state.ref)
        if state.remote_commit == state.ref:
            remote = download_repo_archive(state.repo, state.ref)
            try:
                state.remote_commit = remote.commit
            finally:
                remote.cleanup()
    return state.remote_commit


def _statuses(state: AppState) -> list[SkillStatus]:
    return get_skill_status(_load_manifest(state), state.target_dir, _remote_commit(state), state.repo)


def _state(ctx: typer.Context) -> AppState:
    return ctx.obj


@app.callback()
def main(
    ctx: typer.Context,
    repo: str = typer.Option(DEFAULT_REPO, "--repo", help="GitHub 仓库，格式 owner/repo。"),
    ref: str = typer.Option(DEFAULT_REF, "--ref", help="分支、tag 或 commit。"),
    target: Optional[str] = typer.Option(None, "--target", help="目标目录：codex、claude、current。"),
    skills_dir: Optional[str] = typer.Option(None, "--skills-dir", help="自定义绝对 skills 目录。"),
) -> None:
    ctx.obj = AppState(repo, ref, target, skills_dir)
    if ctx.invoked_subcommand is None:
        from .tui import run_tui

        run_tui(repo=repo, ref=ref, target=target, skills_dir=skills_dir)
        raise typer.Exit()


def _select_target_dir() -> tuple[str | None, str | None]:
    targets = default_targets()
    choices = [
        {"name": f"Codex    {targets['codex']}", "value": ("codex", None)},
        {"name": f"Claude   {targets['claude']}", "value": ("claude", None)},
        {"name": f"当前目录  {targets['current']}", "value": ("current", None)},
        {"name": "自定义绝对目录", "value": (None, "custom")},
    ]
    target, custom = inquirer.select(message="请选择要管理的 Skills 目录", choices=choices).execute()
    if custom == "custom":
        value = inquirer.text(message="请输入绝对目录路径").execute()
        return None, value
    return target, None


def interactive(ctx: typer.Context) -> None:
    print_banner()
    state = _state(ctx)
    if not state.target_was_explicit:
        target, skills_dir = _select_target_dir()
        state.target_dir = resolve_target_dir(target, skills_dir)
    console.print(f"当前目录: [cyan]{short_path(state.target_dir)}[/cyan]")
    console.print(f"远端仓库: [cyan]{state.repo}@{state.ref}[/cyan]\n")

    while True:
        action = inquirer.select(
            message="请选择操作",
            choices=[
                {"name": "查看安装状态", "value": "status"},
                {"name": "安装 Skill", "value": "add"},
                {"name": "更新 Skill", "value": "update"},
                {"name": "查看 Skill 详情", "value": "info"},
                {"name": "打开配置文件", "value": "config"},
                {"name": "检查环境", "value": "doctor"},
                {"name": "切换目标目录", "value": "switch"},
                {"name": "退出", "value": "quit"},
            ],
        ).execute()
        if action == "quit":
            return
        if action == "switch":
            target, skills_dir = _select_target_dir()
            state.target_dir = resolve_target_dir(target, skills_dir)
            state.manifest = None
            state.remote_commit = None
            console.print(f"当前目录: [cyan]{short_path(state.target_dir)}[/cyan]")
            continue
        if action == "status":
            show_status(state)
        elif action == "add":
            selected = _choose_skills(state, allow_all=True, message="请选择要安装的 Skill")
            if selected:
                add_selected(state, selected, force=False)
        elif action == "update":
            selected = _choose_skills(state, allow_all=True, installed_only=True, message="请选择要更新的 Skill")
            if selected:
                add_selected(state, selected, force=True, update_mode=True)
        elif action == "info":
            selected = _choose_one_skill(state, "请选择要查看的 Skill")
            if selected:
                show_info(state, selected)
        elif action == "config":
            selected = _choose_one_skill(state, "请选择要查看配置的 Skill")
            if selected:
                open_config(state, selected)
        elif action == "doctor":
            show_doctor(state)


def _choose_one_skill(state: AppState, message: str) -> str | None:
    manifest = _load_manifest(state)
    if not manifest.skills:
        print_warning("远端 manifest 中没有 skill。")
        return None
    return inquirer.select(message=message, choices=list(sorted(manifest.skills))).execute()


def _choose_skills(state: AppState, allow_all: bool, message: str, installed_only: bool = False) -> list[str]:
    rows = _statuses(state)
    choices = []
    if allow_all:
        choices.append({"name": "全部", "value": "all"})
    for row in rows:
        if installed_only and row.state == "未安装":
            continue
        choices.append({"name": f"{row.name}  [{row.state}]", "value": row.name})
    selected = inquirer.checkbox(message=message, choices=choices).execute()
    if "all" in selected:
        confirm = inquirer.confirm(message="确认对全部 Skill 执行该操作？", default=False).execute()
        if not confirm:
            return []
        return [row.name for row in rows if not installed_only or row.state != "未安装"]
    return selected


def show_status(state: AppState) -> None:
    table = make_status_table()
    for row in _statuses(state):
        status_style = {
            "最新": "green",
            "有更新": "yellow",
            "未安装": "dim",
            "已安装，无记录": "red",
            "来源不同": "magenta",
        }.get(row.state, "white")
        table.add_row(
            row.name,
            f"[{status_style}]{row.state}[/{status_style}]",
            short_path(row.path) if row.path.exists() else "-",
            short_commit(row.local_commit),
            short_commit(row.remote_commit),
            row.installed_at or "-",
        )
    console.print(table)


def add_selected(state: AppState, skills: list[str], force: bool, update_mode: bool = False) -> None:
    manifest = _load_manifest(state)
    for name in skills:
        skill = manifest.skills.get(name)
        if skill is None:
            print_error(f"未知 skill：{name}")
            continue
        console.print(f"\n[bold]正在{'更新' if update_mode else '安装'} {name}[/bold]")
        try:
            result = install_skill(skill, state.target_dir, state.repo, state.ref, force=force)
        except Exception as exc:
            print_error(str(exc))
            continue
        if result.installed:
            print_success(f"{name} 已安装到 {result.destination}")
            if result.backup:
                console.print(f"  备份: [dim]{result.backup}[/dim]")
            if result.restored:
                console.print("  已恢复配置: " + ", ".join(result.restored))
            for warning in result.warnings:
                print_warning(warning)
        else:
            print_warning(result.warnings[0] if result.warnings else f"{name} 未安装。")


@app.command("status")
def status_command(ctx: typer.Context) -> None:
    print_banner()
    show_status(_state(ctx))


@app.command("add")
def add_command(
    ctx: typer.Context,
    skills: list[str] = typer.Argument(None, help="要安装的 skill 名称，或 all。"),
    force: bool = typer.Option(False, "--force", help="已存在时覆盖安装。"),
) -> None:
    print_banner()
    state = _state(ctx)
    if not skills:
        skills = _choose_skills(state, allow_all=True, message="请选择要安装的 Skill")
    if "all" in skills:
        if not typer.confirm("确认安装全部 Skill？", default=False):
            raise typer.Exit()
        skills = list(_load_manifest(state).skills)
    add_selected(state, skills, force=force)


@app.command("update")
def update_command(
    ctx: typer.Context,
    skills: list[str] = typer.Argument(None, help="要更新的 skill 名称，或 all。"),
) -> None:
    print_banner()
    state = _state(ctx)
    if not skills:
        skills = _choose_skills(state, allow_all=True, installed_only=True, message="请选择要更新的 Skill")
    if "all" in skills:
        if not typer.confirm("确认更新全部已安装 Skill？", default=False):
            raise typer.Exit()
        skills = [row.name for row in _statuses(state) if row.state != "未安装"]
    add_selected(state, skills, force=True, update_mode=True)


def show_info(state: AppState, name: str) -> None:
    rows = _statuses(state)
    row = find_status(rows, name)
    if row is None:
        print_error(f"未知 skill：{name}")
        return
    body = "\n".join(
        [
            f"名称: {row.name}",
            f"状态: {row.state}",
            f"安装目录: {short_path(row.path) if row.path.exists() else '-'}",
            f"本地 commit: {row.local_commit or '-'}",
            f"线上 commit: {row.remote_commit}",
            f"安装时间: {row.installed_at or '-'}",
            f"标签: {', '.join(row.tags) if row.tags else '-'}",
            f"依赖: {', '.join(row.requires) if row.requires else '-'}",
            "",
            row.description or "无描述。",
        ]
    )
    section(f"{name} 详情", body)


@app.command("info")
def info_command(ctx: typer.Context, skill: str = typer.Argument(..., help="skill 名称。")) -> None:
    print_banner()
    show_info(_state(ctx), skill)


def open_config(state: AppState, name: str) -> None:
    skill_dir = state.target_dir / name
    if not skill_dir.exists():
        print_warning(f"未安装：{name}")
        return
    configs = find_local_config_files(skill_dir)
    if not configs:
        print_warning("未发现 *.local.json 或 *.local.jsonc 配置文件。")
        open_folder = inquirer.confirm(message="是否打开 skill 目录？", default=False).execute()
        if open_folder:
            open_path(skill_dir)
        return
    choice = inquirer.select(
        message="请选择配置文件",
        choices=[{"name": str(path.relative_to(skill_dir)), "value": path} for path in configs],
    ).execute()
    action = inquirer.select(
        message="请选择操作",
        choices=[{"name": "打开文件", "value": "file"}, {"name": "打开所在目录", "value": "folder"}],
    ).execute()
    open_path(choice if action == "file" else choice.parent)
    print_success("已打开。")


@app.command("config")
def config_command(ctx: typer.Context, skill: str = typer.Argument(..., help="skill 名称。")) -> None:
    print_banner()
    open_config(_state(ctx), skill)


def show_doctor(state: AppState) -> None:
    table = Table(title="环境检查")
    table.add_column("项目", style="bold")
    table.add_column("状态")
    table.add_column("详情")
    for check in run_doctor(state.target_dir, state.repo, state.ref):
        table.add_row(check.name, "[green]OK[/green]" if check.ok else "[red]缺失/异常[/red]", check.detail)
    console.print(table)


@app.command("doctor")
def doctor_command(ctx: typer.Context) -> None:
    print_banner()
    show_doctor(_state(ctx))


if __name__ == "__main__":
    app()
