from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from uuid import uuid4

from textual import events, work
from textual.app import App, ComposeResult
from textual.containers import Container, Horizontal, Vertical
from textual.reactive import reactive
from textual.screen import ModalScreen
from textual.widgets import Button, DataTable, Footer, Header, Input, Label, ListItem, ListView, Log, ProgressBar, Static

from .constants import DEFAULT_REF, DEFAULT_REPO, default_targets
from .doctor import CheckResult, iter_doctor_checks
from .installer import install_skill
from .local_config import find_local_config_files
from .manifest import SkillManifest, read_remote_manifest
from .opener import open_path
from .paths import resolve_target_dir, short_path
from .status import SkillStatus, find_status, get_skill_status
from .ui import BANNER


CSS = """
Screen {
    background: #0f1419;
    color: #d8dee9;
}

#shell {
    height: 100%;
}

#brand {
    height: 9;
    padding: 1 2;
    color: #62d6e8;
    background: #101820;
    border-bottom: solid #244b5a;
}

#content-row {
    height: 1fr;
}

#sidebar {
    width: 30;
    padding: 1;
    background: #151b22;
    border-right: solid #2e3b46;
}

#main {
    width: 1fr;
    padding: 1 2;
}

.meta {
    color: #aab7c4;
}

.title {
    text-style: bold;
    color: #ffffff;
}

.hint {
    color: #93a1ad;
}

DataTable {
    height: 1fr;
}

Button {
    margin: 1 1 0 0;
}

Log {
    height: 10;
    border: solid #2e3b46;
}

ProgressBar {
    margin: 1 0;
}

ListItem {
    height: auto;
}

.skill-entry {
    height: auto;
    width: 100%;
}

.skill-line {
    height: 1;
    width: 100%;
}

.skill-name {
    width: 1fr;
}

.skill-state {
    width: 22;
    content-align: right middle;
    color: #aab7c4;
}

.skill-desc {
    padding-left: 4;
    color: #c3ccd5;
}

.skill-deps {
    padding-left: 4;
    color: #93a1ad;
}
"""


@dataclass
class ToolState:
    repo: str = DEFAULT_REPO
    ref: str = DEFAULT_REF
    target_key: str | None = None
    skills_dir: str | None = None
    target_dir: Path | None = None
    manifest: SkillManifest | None = None


class MessageScreen(ModalScreen[bool]):
    def __init__(self, title: str, message: str, confirm_label: str = "确认") -> None:
        super().__init__()
        self.title = title
        self.message = message
        self.confirm_label = confirm_label

    def compose(self) -> ComposeResult:
        with Container(id="dialog"):
            yield Label(self.title, classes="title")
            yield Static(self.message)
            yield Button(self.confirm_label, id="ok", variant="primary")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "ok":
            self.dismiss(True)


class ConfirmScreen(ModalScreen[bool]):
    def __init__(self, title: str, message: str) -> None:
        super().__init__()
        self.title = title
        self.message = message

    def compose(self) -> ComposeResult:
        with Container(id="dialog"):
            yield Label(self.title, classes="title")
            yield Static(self.message)
            with Horizontal():
                yield Button("确认", id="yes", variant="primary")
                yield Button("取消", id="no")

    def on_button_pressed(self, event: Button.Pressed) -> None:
        self.dismiss(event.button.id == "yes")


class M2KSkillsApp(App[None]):
    CSS = CSS
    BINDINGS = [
        ("q", "quit", "退出"),
        ("b", "home", "返回首页"),
        ("r", "refresh", "刷新"),
        ("enter", "primary", "确认"),
        ("left", "focus_left", "左侧"),
        ("right", "focus_right", "右侧"),
        ("space", "toggle_select", "选择"),
        ("/", "focus_filter", "筛选"),
        ("tab", "noop", ""),
    ]

    current_view: reactive[str] = reactive("targets")

    def __init__(self, repo: str, ref: str, target: str | None = None, skills_dir: str | None = None) -> None:
        super().__init__()
        self.state = ToolState(repo=repo, ref=ref, target_key=target, skills_dir=skills_dir)
        self.progress_id = "install-progress"
        self.log_id = "install-log"
        self.open_targets: dict[str, Path] = {}
        self.status_table_id = "status-table"
        self.doctor_lines_id = "doctor-lines"
        self.doctor_cache: list[CheckResult] | None = None
        self.doctor_current: dict[str, CheckResult | None] = {}
        self.status_cache: list[SkillStatus] | None = None
        self.status_loading = False
        self.doctor_loading = False
        self.picker_mode: str | None = None
        self.picker_items: dict[str, SkillStatus] = {}
        self.selectable_skill_names: set[str] = set()
        self.selected_skill_names: set[str] = set()
        self.filter_queries: dict[str, str] = {"manage": "", "info": "", "config": ""}
        if target or skills_dir:
            self.state.target_dir = resolve_target_dir(target, skills_dir)
            self.current_view = "home"

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        with Vertical(id="shell"):
            yield Static(BANNER + "\nM2K Skills Tools", id="brand")
            with Horizontal(id="content-row"):
                with Vertical(id="sidebar"):
                    yield Label("目标目录", classes="title")
                    yield Static("未选择", id="target-info", classes="meta")
                    yield Static("\n操作", classes="title")
                    yield ListView(
                        ListItem(Label("查看安装状态"), id="menu-status"),
                        ListItem(Label("安装 / 更新 Skill"), id="menu-manage"),
                        ListItem(Label("查看详情"), id="menu-info"),
                        ListItem(Label("打开配置"), id="menu-config"),
                        ListItem(Label("环境检查"), id="menu-doctor"),
                        ListItem(Label("切换目录"), id="menu-targets"),
                        ListItem(Label("退出"), id="menu-quit"),
                        id="menu",
                    )
                with Vertical(id="main"):
                    yield Static("", id="view-title", classes="title")
                    yield Static("", id="view-hint", classes="hint")
                    yield Container(id="view")
        yield Footer()

    def on_mount(self) -> None:
        self.refresh_target_info()
        if self.state.target_dir is not None:
            self.show_home()
        else:
            self.show_targets()

    def refresh_target_info(self) -> None:
        target = self.query_one("#target-info", Static)
        if self.state.target_dir:
            target.update(short_path(self.state.target_dir))
        else:
            target.update("未选择")

    def reset_view(self, title: str, hint: str = "") -> Container:
        self.query_one("#view-title", Static).update(title)
        self.query_one("#view-hint", Static).update(hint)
        view = self.query_one("#view", Container)
        view.remove_children()
        return view

    def clear_cache(self) -> None:
        self.state.manifest = None
        self.doctor_cache = None
        self.doctor_current = {}
        self.status_cache = None
        self.status_loading = False
        self.doctor_loading = False
        self.filter_queries = {"manage": "", "info": "", "config": ""}

    def preload_after_target_selected(self) -> None:
        self.preload_status_worker()
        self.preload_doctor_worker()

    def on_key(self, event: events.Key) -> None:
        if event.key == "right":
            self.action_focus_right()
            event.prevent_default()
            event.stop()
        elif event.key == "left":
            self.action_focus_left()
            event.prevent_default()
            event.stop()
        elif event.key in {"tab", "shift+tab"}:
            event.prevent_default()
            event.stop()

    def unique_id(self, prefix: str) -> str:
        return f"{prefix}-{uuid4().hex[:8]}"

    def show_home(self) -> None:
        self.current_view = "home"
        view = self.reset_view("首页", "↑/↓ 选择菜单，Enter 进入；b 返回首页，q 退出。")
        view.mount(Static("请选择左侧操作。Logo 会常驻顶部，页面在这里切换。"))
        if self.state.target_dir is not None:
            self.preload_after_target_selected()

    def show_targets(self) -> None:
        self.current_view = "targets"
        view = self.reset_view("选择目标目录", "选择要管理的 skills 目录。")
        targets = default_targets()
        items: list[ListItem] = []
        for key, label in [("codex", "Codex"), ("claude", "Claude"), ("current", "当前目录")]:
            items.append(ListItem(Label(f"{label}    {targets[key]}"), id=f"target-{key}"))
        items.append(ListItem(Label("自定义绝对目录"), id="target-custom"))
        target_list = ListView(*items, id=self.unique_id("target-list"))
        view.mount(target_list)
        target_list.focus()

    def on_list_view_selected(self, event: ListView.Selected) -> None:
        item_id = event.item.id or ""
        if self.current_view == "manage" and (item_id == "pick-all" or item_id.startswith("pick-")):
            self.confirm_and_run()
            return

        if item_id.startswith("target-"):
            key = item_id.removeprefix("target-")
            if key == "custom":
                self.show_custom_target()
                return
            self.state.target_key = key
            self.state.skills_dir = None
            self.state.target_dir = resolve_target_dir(key, None)
            self.clear_cache()
            self.refresh_target_info()
            self.show_home()
            return

        if item_id == "menu-status":
            self.show_status()
        elif item_id == "menu-manage":
            self.show_skill_picker("manage")
        elif item_id == "menu-info":
            self.show_single_skill("info")
        elif item_id == "menu-config":
            self.show_single_skill("config")
        elif item_id == "menu-doctor":
            self.show_doctor()
        elif item_id == "menu-targets":
            self.show_targets()
        elif item_id == "menu-quit":
            self.exit()

        if item_id.startswith("info-"):
            self.render_info(item_id.removeprefix("info-"))
        elif item_id.startswith("config-"):
            self.render_config(item_id.removeprefix("config-"))
        elif item_id in self.open_targets:
            open_path(self.open_targets[item_id])
            self.notify("已打开。")

    def show_custom_target(self) -> None:
        view = self.reset_view("自定义目录", "请输入绝对路径，然后按 Enter。")
        input_widget = Input(placeholder="例如 D:\\skills 或 /home/me/.codex/skills", id=self.unique_id("custom-target-input"))
        view.mount(input_widget)
        input_widget.focus()

    def on_input_submitted(self, event: Input.Submitted) -> None:
        if not event.input.id or not event.input.id.startswith("custom-target-input"):
            if event.input.id and event.input.id.startswith("skill-filter-"):
                mode = event.input.id.removeprefix("skill-filter-").split("-", 1)[0]
                self.apply_skill_filter(mode, event.value)
                return
            return
        try:
            self.state.target_dir = resolve_target_dir(None, event.value)
        except Exception as exc:
            self.notify(str(exc), severity="error")
            return
        self.state.skills_dir = event.value
        self.state.target_key = None
        self.clear_cache()
        self.refresh_target_info()
        self.show_home()

    def skill_matches_filter(self, row: SkillStatus, query: str) -> bool:
        query = query.strip().lower()
        if not query:
            return True
        haystack = " ".join(
            [
                row.name,
                row.state,
                row.description,
                row.local_version or "",
                row.remote_version,
                " ".join(row.tags),
                " ".join(row.requires),
            ]
        ).lower()
        return query in haystack

    def filtered_rows(self, rows: list[SkillStatus], mode: str) -> list[SkillStatus]:
        query = self.filter_queries.get(mode, "")
        return [row for row in rows if self.skill_matches_filter(row, query)]

    def apply_skill_filter(self, mode: str, value: str) -> None:
        if mode not in {"manage", "info", "config"}:
            return
        self.filter_queries[mode] = value.strip()
        rows = self.status_cache or self.statuses()
        if mode == "manage":
            self.render_skill_picker(mode, rows, focus_filter=False)
        else:
            self.render_single_skill_picker(mode, rows, focus_filter=False)

    def require_target(self) -> bool:
        if self.state.target_dir is None:
            self.show_targets()
            return False
        return True

    def load_manifest(self) -> SkillManifest:
        if self.state.manifest is None:
            self.state.manifest = read_remote_manifest(self.state.repo, self.state.ref)
        return self.state.manifest

    def statuses(self) -> list[SkillStatus]:
        assert self.state.target_dir is not None
        return get_skill_status(self.load_manifest(), self.state.target_dir, self.state.repo)

    @work(exclusive=True, thread=True, group="status")
    def preload_status_worker(self) -> None:
        if self.status_cache is not None or self.status_loading:
            return
        self.status_loading = True
        try:
            rows = self.statuses()
        except Exception as exc:
            self.call_from_thread(self.handle_status_error, str(exc))
            return
        finally:
            self.status_loading = False
        self.call_from_thread(self.handle_status_ready, rows)

    @work(exclusive=True, thread=True, group="doctor")
    def preload_doctor_worker(self) -> None:
        if self.doctor_cache is not None or self.doctor_loading or self.state.target_dir is None:
            return
        self.doctor_loading = True
        results: list[CheckResult] = []
        try:
            for check in iter_doctor_checks(self.state.target_dir, self.state.repo, self.state.ref):
                results.append(check)
                self.call_from_thread(self.handle_doctor_check_ready, check)
            self.doctor_cache = results
            self.doctor_current = {item.name: item for item in results}
        finally:
            self.doctor_loading = False

    @work(exclusive=True, thread=True, group="status")
    def load_status_worker(self) -> None:
        if self.status_loading:
            return
        self.status_loading = True
        try:
            rows = self.statuses()
        except Exception as exc:
            self.call_from_thread(self.show_error, "读取状态失败", str(exc))
            return
        finally:
            self.status_loading = False
        self.call_from_thread(self.handle_status_ready, rows)

    def handle_status_ready(self, rows: list[SkillStatus]) -> None:
        self.status_cache = rows
        if self.current_view == "status":
            self.render_status_table(rows)
        elif self.current_view == "manage":
            self.render_skill_picker(self.current_view, rows)
        elif self.current_view in {"info", "config"}:
            self.render_single_skill_picker(self.current_view, rows)

    def handle_status_error(self, message: str) -> None:
        if self.current_view in {"status", "manage"}:
            self.show_error("读取状态失败", message)

    def handle_doctor_check_ready(self, check: CheckResult) -> None:
        if not self.doctor_current:
            self.doctor_current = {name: None for name in ["python", "uv", "git", "node", "npx", "powershell", "skills-dir", "manifest"]}
        self.doctor_current[check.name] = check
        if self.current_view != "doctor":
            return
        try:
            widget = self.query_one(f"#{self.doctor_lines_id}", Static)
        except Exception:
            return
        widget.update(self.format_doctor_lines(self.doctor_current))

    def show_status(self) -> None:
        if not self.require_target():
            return
        self.current_view = "status"
        if self.status_cache is not None:
            self.render_status_table(self.status_cache)
            return
        view = self.reset_view("安装状态", "正在后台读取远端 manifest 和本机安装记录。")
        self.status_table_id = self.unique_id("status-table")
        table = DataTable(zebra_stripes=True, id=self.status_table_id)
        table.add_columns("Skill", "状态", "本地", "线上", "安装时间")
        table.add_row("加载中...", "checking", "-", "-", "-")
        view.mount(table)
        table.focus()
        if not self.status_loading:
            self.load_status_worker()

    def render_status_table(self, rows: list[SkillStatus]) -> None:
        view = self.reset_view("安装状态", "r 刷新，b 返回首页，q 退出。")
        self.status_table_id = self.unique_id("status-table")
        table = DataTable(zebra_stripes=True, id=self.status_table_id)
        table.add_columns("Skill", "状态", "本地", "线上", "安装时间")
        for row in rows:
            table.add_row(row.name, row.state, row.local_version or "-", row.remote_version, row.installed_at or "-")
        view.mount(table)
        table.focus()

    def show_skill_picker(self, mode: str) -> None:
        if not self.require_target():
            return
        self.current_view = mode
        view = self.reset_view("安装 / 更新 Skill", "←/→ 切换左右区域，↑/↓ 移动，Space 选择，Enter 开始。")
        try:
            if self.status_cache is None:
                view.mount(Static("正在后台加载 skill 状态，请稍候..."))
                if not self.status_loading:
                    self.load_picker_worker(mode)
                return
            rows = self.status_cache
        except Exception as exc:
            self.show_error("读取 skill 列表失败", str(exc))
            return
        self.render_skill_picker(mode, rows)

    @work(exclusive=True, thread=True, group="status")
    def load_picker_worker(self, mode: str) -> None:
        try:
            rows = self.statuses()
        except Exception as exc:
            self.call_from_thread(self.show_error, "读取 skill 列表失败", str(exc))
            return
        self.call_from_thread(self.handle_status_ready, rows)

    def render_skill_picker(self, mode: str, rows: list[SkillStatus], focus_filter: bool = False) -> None:
        self.current_view = "manage"
        query = self.filter_queries.get("manage", "")
        filtered = self.filtered_rows(rows, "manage")
        view = self.reset_view("安装 / 更新 Skill", f"/ 筛选，Space 选择，Enter 开始；当前 {len(filtered)}/{len(rows)} 个。")
        self.picker_mode = "manage"
        self.picker_items = {}
        self.selectable_skill_names = set()
        self.selected_skill_names = set()
        filter_input = Input(value=query, placeholder="筛选名称、状态、描述、标签、依赖后按 Enter", id=f"skill-filter-manage-{self.unique_id('input')}")
        view.mount(filter_input)
        if not filtered:
            view.mount(Static("无匹配 Skill。清空筛选框后按 Enter 显示全部。"))
            filter_input.focus()
            return
        items: list[ListItem] = [ListItem(Label("□  全选 / 取消全选"), id="pick-all")]
        for row in filtered:
            self.picker_items[row.name] = row
            if self.is_selectable(row):
                self.selectable_skill_names.add(row.name)
            items.append(self.build_picker_item(row.name))
        picker = ListView(*items, id=self.unique_id("skill-picker"))
        view.mount(picker)
        if focus_filter:
            filter_input.focus()
        else:
            picker.focus()

    def is_selectable(self, row: SkillStatus) -> bool:
        return row.state != "最新"

    def operation_for_row(self, row: SkillStatus) -> str:
        return "安装" if row.state == "未安装" else "更新"

    def operation_status_for_row(self, row: SkillStatus) -> str:
        if row.state == "最新":
            return "最新"
        if row.state == "未安装":
            return "安装 / 未安装"
        if row.state == "已安装，无记录":
            return "更新 / 无记录"
        return f"更新 / {row.state}"

    def picker_display(self, name: str) -> tuple[str, str, str, str, str]:
        row = self.picker_items[name]
        selectable = self.is_selectable(row)
        if name in self.selected_skill_names:
            mark = "✓"
        elif selectable:
            mark = "□"
        else:
            mark = " "
        status = self.operation_status_for_row(row)
        desc = row.description.strip() if row.description else "无描述。"
        if len(desc) > 72:
            desc = desc[:69] + "..."
        requires = ", ".join(row.requires[:3]) if row.requires else "无"
        name = row.name if len(row.name) <= 46 else row.name[:43] + "..."
        return mark, name, status, desc, f"依赖: {requires}"

    def build_picker_item(self, name: str) -> ListItem:
        mark, display_name, status, desc, deps = self.picker_display(name)
        return ListItem(
            Vertical(
                Horizontal(
                    Label(f"{mark}  {display_name}", classes="skill-name"),
                    Label(status, classes="skill-state"),
                    classes="skill-line",
                ),
                Label(desc, classes="skill-desc"),
                Label(deps, classes="skill-deps"),
                classes="skill-entry",
            ),
            id=f"pick-{name}",
        )

    def refresh_picker_item(self, item: ListItem, name: str) -> None:
        mark, display_name, status, desc, deps = self.picker_display(name)
        item.query_one(".skill-name", Label).update(f"{mark}  {display_name}")
        item.query_one(".skill-state", Label).update(status)
        item.query_one(".skill-desc", Label).update(desc)
        item.query_one(".skill-deps", Label).update(deps)

    def format_select_all_label(self) -> str:
        all_selected = bool(self.selectable_skill_names) and self.selected_skill_names == self.selectable_skill_names
        return f"{'✓' if all_selected else '□'}  全选 / 取消全选"

    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "run-manage":
            self.confirm_and_run()
        elif event.button.id and event.button.id in self.open_targets:
            open_path(self.open_targets[event.button.id])
            self.notify("已打开。")

    def selected_skills(self) -> list[str]:
        return sorted(self.selected_skill_names)

    def confirm_and_run(self) -> None:
        skills = self.selected_skills()
        if not skills:
            self.notify("请先选择至少一个 skill。", severity="warning")
            return
        install_count = sum(1 for name in skills if self.picker_items[name].state == "未安装")
        update_count = len(skills) - install_count
        summary = f"将处理 {len(skills)} 个 skill：安装 {install_count} 个，更新 {update_count} 个。\n\n{', '.join(skills)}"
        self.push_screen(ConfirmScreen("确认安装 / 更新", summary), lambda ok: self.run_install(skills) if ok else None)

    def run_install(self, skills: list[str]) -> None:
        self.current_view = "progress"
        view = self.reset_view("安装 / 更新进度", "进度条展示当前步骤，日志展示细节。")
        self.progress_id = self.unique_id("install-progress")
        self.log_id = self.unique_id("install-log")
        progress = ProgressBar(total=100, id=self.progress_id)
        log = Log(id=self.log_id)
        view.mount(progress)
        view.mount(log)
        operations = {name: self.operation_for_row(self.picker_items[name]) for name in skills}
        self.install_worker(skills, operations)

    @work(exclusive=True, thread=True, group="install")
    def install_worker(self, skills: list[str], operations: dict[str, str]) -> None:
        assert self.state.target_dir is not None
        manifest = self.load_manifest()

        def update_progress(skill_index: int, step: int, total: int, message: str) -> None:
            total_units = max(1, len(skills) * total)
            value = int(((skill_index * total) + step) / total_units * 100)
            self.call_from_thread(self.update_install_progress, min(value, 100), message)

        for index, name in enumerate(skills):
            skill = manifest.skills.get(name)
            if skill is None:
                self.call_from_thread(self.log_install, f"未知 skill：{name}")
                continue
            operation = operations.get(name, "更新")
            self.call_from_thread(self.log_install, f"开始{operation} {name}")
            try:
                result = install_skill(
                    skill,
                    self.state.target_dir,
                    self.state.repo,
                    self.state.ref,
                    force=(operation == "更新"),
                    progress=lambda step, total, msg, i=index: update_progress(i, step, total, f"{name}: {msg}"),
                )
            except Exception as exc:
                self.call_from_thread(self.log_install, f"失败：{name} - {exc}")
                continue
            if result.installed:
                self.call_from_thread(self.log_install, f"完成：{name} -> {result.destination}")
                if result.backup:
                    self.call_from_thread(self.log_install, f"备份：{result.backup}")
                for item in result.restored:
                    self.call_from_thread(self.log_install, f"恢复配置：{item}")
                for warning in result.warnings:
                    self.call_from_thread(self.log_install, f"提示：{warning}")
            else:
                self.call_from_thread(self.log_install, result.warnings[0] if result.warnings else f"跳过：{name}")
        self.call_from_thread(self.update_install_progress, 100, "完成")
        self.call_from_thread(self.log_install, "全部任务结束。按 b 返回首页，或 q 退出。")
        self.status_cache = None
        try:
            self.status_cache = self.statuses()
        except Exception:
            pass

    def update_install_progress(self, value: int, message: str) -> None:
        self.query_one(f"#{self.progress_id}", ProgressBar).update(progress=value)
        self.log_install(message)

    def log_install(self, message: str) -> None:
        self.query_one(f"#{self.log_id}", Log).write_line(message)

    def show_single_skill(self, mode: str) -> None:
        if not self.require_target():
            return
        self.current_view = mode
        view = self.reset_view("选择 Skill", "Enter 进入，b 返回首页。")
        if self.status_cache is None:
            view.mount(Static("正在后台加载 skill 状态，请稍候..."))
            if not self.status_loading:
                self.load_status_worker()
            return
        self.render_single_skill_picker(mode, self.status_cache)

    def render_single_skill_picker(self, mode: str, rows: list[SkillStatus], focus_filter: bool = False) -> None:
        self.current_view = mode
        query = self.filter_queries.get(mode, "")
        filtered = self.filtered_rows(rows, mode)
        view = self.reset_view("选择 Skill", f"/ 筛选，Enter 进入，b 返回首页；当前 {len(filtered)}/{len(rows)} 个。")
        filter_input = Input(value=query, placeholder="筛选名称、状态、描述、标签、依赖后按 Enter", id=f"skill-filter-{mode}-{self.unique_id('input')}")
        view.mount(filter_input)
        if not filtered:
            view.mount(Static("无匹配 Skill。清空筛选框后按 Enter 显示全部。"))
            filter_input.focus()
            return
        items = [ListItem(Label(self.format_single_skill_label(row)), id=f"{mode}-{row.name}") for row in filtered]
        skill_list = ListView(*items, id=self.unique_id(f"single-{mode}"))
        view.mount(skill_list)
        if focus_filter:
            filter_input.focus()
        else:
            skill_list.focus()

    def format_single_skill_label(self, row: SkillStatus) -> str:
        desc = row.description.strip() if row.description else "无描述。"
        if len(desc) > 72:
            desc = desc[:69] + "..."
        return f"{row.name}  [{row.state}]\n    {desc}"

    def render_info(self, name: str) -> None:
        rows = self.status_cache or self.statuses()
        row = find_status(rows, name)
        if row is None:
            self.show_error("未知 Skill", name)
            return
        body = "\n".join(
            [
                f"名称: {row.name}",
                f"状态: {row.state}",
                f"安装目录: {short_path(row.path) if row.path.exists() else '-'}",
                f"本地版本: {row.local_version or '-'}",
                f"线上版本: {row.remote_version}",
                f"安装来源 commit: {row.local_commit or '-'}",
                f"安装时间: {row.installed_at or '-'}",
                f"标签: {', '.join(row.tags) if row.tags else '-'}",
                f"依赖: {', '.join(row.requires) if row.requires else '-'}",
                "",
                row.description or "无描述。",
            ]
        )
        view = self.reset_view(f"{name} 详情", "b 返回首页，q 退出。")
        view.mount(Static(body))

    def render_config(self, name: str) -> None:
        assert self.state.target_dir is not None
        skill_dir = self.state.target_dir / name
        view = self.reset_view(f"{name} 配置", "Enter 打开文件，b 返回首页，q 退出。")
        if not skill_dir.exists():
            view.mount(Static("该 skill 未安装。"))
            return
        configs = find_local_config_files(skill_dir)
        if not configs:
            view.mount(Static("未发现 *.local.json 或 *.local.jsonc 配置文件。"))
            open_id = self.unique_id("open-dir")
            self.open_targets[open_id] = skill_dir
            button = Button("打开 skill 目录", id=open_id, variant="primary")
            view.mount(button)
            button.focus()
            return
        items = []
        for path in configs:
            open_id = self.unique_id("open-file")
            self.open_targets[open_id] = path
            items.append(ListItem(Label(str(path.relative_to(skill_dir))), id=open_id))
        dir_id = self.unique_id("open-dir")
        self.open_targets[dir_id] = skill_dir
        items.append(ListItem(Label("打开 skill 目录"), id=dir_id))
        config_list = ListView(*items, id=self.unique_id("config-list"))
        view.mount(config_list)
        config_list.focus()

    def show_error(self, title: str, message: str) -> None:
        view = self.reset_view(title, "b 返回首页，q 退出。")
        view.mount(Static(message))

    def show_doctor(self) -> None:
        if not self.require_target():
            return
        self.current_view = "doctor"
        view = self.reset_view("环境检查", "页面先打开，后台逐项检查；详情自动换行，不再截断。")
        self.doctor_lines_id = self.unique_id("doctor-lines")
        if self.doctor_cache is not None:
            lines = self.format_doctor_lines({item.name: item for item in self.doctor_cache})
            view.mount(Static(lines, id=self.doctor_lines_id))
            return
        if not self.doctor_current:
            self.doctor_current = {name: None for name in ["python", "uv", "git", "node", "npx", "powershell", "skills-dir", "manifest"]}
        view.mount(Static(self.format_doctor_lines(self.doctor_current), id=self.doctor_lines_id))
        if not self.doctor_loading:
            self.doctor_worker()

    @work(exclusive=True, thread=True, group="doctor")
    def doctor_worker(self) -> None:
        assert self.state.target_dir is not None
        self.doctor_loading = True
        results: list[CheckResult] = []
        try:
            for check in iter_doctor_checks(self.state.target_dir, self.state.repo, self.state.ref):
                results.append(check)
                self.call_from_thread(self.handle_doctor_check_ready, check)
            self.doctor_cache = results
        finally:
            self.doctor_loading = False

    def format_doctor_lines(self, rows: dict[str, CheckResult | None]) -> str:
        lines = []
        for name, check in rows.items():
            if check is None:
                lines.append(f"{name:<12} checking...  -")
            else:
                state = "OK" if check.ok else "异常"
                lines.append(f"{name:<12} {state:<10} {check.detail}")
        return "\n".join(lines)

    def action_home(self) -> None:
        self.show_home()

    def action_refresh(self) -> None:
        current = self.current_view
        self.clear_cache()
        if current == "home":
            self.show_home()
        elif current == "doctor":
            self.show_doctor()
        elif current == "manage":
            self.show_skill_picker(current)
        else:
            self.show_status()

    def action_primary(self) -> None:
        if self.current_view == "manage":
            self.confirm_and_run()

    def action_toggle_select(self) -> None:
        if self.current_view != "manage":
            return
        picker = next(iter(self.query("#view ListView")), None)
        if not isinstance(picker, ListView) or picker.highlighted_child is None:
            return
        item_id = picker.highlighted_child.id or ""
        if item_id == "pick-all":
            if not self.selectable_skill_names:
                self.notify("没有可操作的 skill。", severity="warning")
                return
            if self.selected_skill_names == self.selectable_skill_names:
                self.selected_skill_names.clear()
            else:
                self.selected_skill_names = set(self.selectable_skill_names)
            self.refresh_picker_labels(picker)
            return
        if not item_id.startswith("pick-"):
            return
        name = item_id.removeprefix("pick-")
        if name not in self.selectable_skill_names:
            self.notify("最新版本无需操作。", severity="warning")
            return
        if name in self.selected_skill_names:
            self.selected_skill_names.remove(name)
        else:
            self.selected_skill_names.add(name)
        self.refresh_picker_item(picker.highlighted_child, name)
        self.refresh_select_all_label(picker)

    def refresh_picker_labels(self, picker: ListView) -> None:
        for item in picker.children:
            if not isinstance(item, ListItem) or not item.id:
                continue
            label = item.query_one(Label)
            if item.id == "pick-all":
                label.update(self.format_select_all_label())
            elif item.id.startswith("pick-"):
                self.refresh_picker_item(item, item.id.removeprefix("pick-"))

    def refresh_select_all_label(self, picker: ListView) -> None:
        for item in picker.children:
            if isinstance(item, ListItem) and item.id == "pick-all":
                item.query_one(Label).update(self.format_select_all_label())
                return

    def action_focus_left(self) -> None:
        self.query_one("#menu", ListView).focus()

    def action_focus_right(self) -> None:
        focusable = next(iter(self.query("#view ListView, #view DataTable, #view Input, #view Button")), None)
        if focusable is not None:
            focusable.focus()

    def action_focus_filter(self) -> None:
        if self.current_view not in {"manage", "info", "config"}:
            return
        filter_input = next(iter(self.query("#view Input")), None)
        if filter_input is not None:
            filter_input.focus()

    def action_noop(self) -> None:
        return


def run_tui(repo: str = DEFAULT_REPO, ref: str = DEFAULT_REF, target: str | None = None, skills_dir: str | None = None) -> None:
    M2KSkillsApp(repo=repo, ref=ref, target=target, skills_dir=skills_dir).run()
