from __future__ import annotations

from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.text import Text

console = Console()

BANNER = r"""
███╗   ███╗██████╗ ██╗  ██╗
████╗ ████║╚════██╗██║ ██╔╝
██╔████╔██║ █████╔╝█████╔╝
██║╚██╔╝██║██╔═══╝ ██╔═██╗
██║ ╚═╝ ██║███████╗██║  ██╗
╚═╝     ╚═╝╚══════╝╚═╝  ╚═╝
""".strip("\n")


def print_banner() -> None:
    text = Text(BANNER, style="bold cyan")
    console.print(text)
    console.print("[bold]M2K Skills Tools[/bold]\n")


def print_error(message: str) -> None:
    console.print(f"[bold red]✗[/bold red] {message}")


def print_success(message: str) -> None:
    console.print(f"[bold green]✓[/bold green] {message}")


def print_warning(message: str) -> None:
    console.print(f"[bold yellow]![/bold yellow] {message}")


def section(title: str, body: str) -> None:
    console.print(Panel(body, title=title, border_style="cyan"))


def make_status_table() -> Table:
    table = Table(title="Skills 安装状态", show_lines=False)
    table.add_column("Skill", style="bold")
    table.add_column("状态")
    table.add_column("安装目录")
    table.add_column("本地版本")
    table.add_column("线上版本")
    table.add_column("安装时间")
    return table
