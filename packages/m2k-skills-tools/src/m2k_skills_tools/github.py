from __future__ import annotations

import zipfile
from dataclasses import dataclass
from pathlib import Path
from tempfile import TemporaryDirectory
import shutil
import subprocess
from typing import Callable

import httpx

ProgressCallback = Callable[[str], None]


@dataclass(frozen=True)
class RemoteRepo:
    repo: str
    ref: str
    commit: str
    root: Path
    temp: TemporaryDirectory[str]

    def cleanup(self) -> None:
        self.temp.cleanup()


def raw_url(repo: str, ref: str, path: str) -> str:
    return f"https://raw.githubusercontent.com/{repo}/{ref}/{path.lstrip('/')}"


def github_api_url(repo: str, ref: str) -> str:
    return f"https://api.github.com/repos/{repo}/commits/{ref}"


def get_ref_commit_with_git(repo: str, ref: str, timeout: float = 20.0) -> str | None:
    git = shutil.which("git")
    if not git:
        return None
    url = f"https://github.com/{repo}.git"
    patterns = [ref, f"refs/heads/{ref}", f"refs/tags/{ref}^{{}}", f"refs/tags/{ref}"]
    for pattern in patterns:
        try:
            result = subprocess.run(
                [git, "ls-remote", url, pattern],
                check=False,
                capture_output=True,
                text=True,
                timeout=timeout,
            )
        except Exception:
            continue
        if result.returncode != 0 or not result.stdout.strip():
            continue
        first = result.stdout.strip().splitlines()[0].split()[0]
        if len(first) >= 7:
            return first
    return None


def archive_candidates(repo: str, ref: str) -> list[str]:
    return [
        f"https://github.com/{repo}/archive/refs/heads/{ref}.zip",
        f"https://github.com/{repo}/archive/refs/tags/{ref}.zip",
        f"https://github.com/{repo}/archive/{ref}.zip",
    ]


def get_ref_commit(repo: str, ref: str, timeout: float = 20.0) -> str:
    git_commit = get_ref_commit_with_git(repo, ref, timeout=timeout)
    if git_commit:
        return git_commit
    with httpx.Client(follow_redirects=True, timeout=timeout) as client:
        response = client.get(github_api_url(repo, ref))
        response.raise_for_status()
        data = response.json()
    sha = data.get("sha")
    if not sha:
        raise RuntimeError(f"GitHub 没有返回 commit sha：{repo}@{ref}")
    return sha


def get_ref_commit_or_ref(repo: str, ref: str, timeout: float = 20.0) -> str:
    try:
        return get_ref_commit(repo, ref, timeout=timeout)
    except Exception:
        return ref


def download_text(repo: str, ref: str, path: str, timeout: float = 20.0) -> str:
    with httpx.Client(follow_redirects=True, timeout=timeout) as client:
        response = client.get(raw_url(repo, ref, path))
        response.raise_for_status()
        return response.text


def download_repo_archive(repo: str, ref: str, timeout: float = 60.0, progress: ProgressCallback | None = None) -> RemoteRepo:
    def emit(message: str) -> None:
        if progress:
            progress(message)

    emit("解析远端 commit")
    commit = get_ref_commit_or_ref(repo, ref)
    temp = TemporaryDirectory(prefix="m2k-skills-")
    temp_path = Path(temp.name)
    zip_path = temp_path / "repo.zip"
    errors: list[str] = []

    with httpx.Client(follow_redirects=True, timeout=timeout) as client:
        for url in archive_candidates(repo, ref):
            try:
                emit(f"下载仓库压缩包：{url}")
                with client.stream("GET", url) as response:
                    response.raise_for_status()
                    with zip_path.open("wb") as file:
                        for chunk in response.iter_bytes():
                            if chunk:
                                file.write(chunk)
                if zip_path.stat().st_size > 0:
                    break
            except Exception as exc:  # pragma: no cover - message-only path
                errors.append(f"{url} -> {exc}")
        else:
            temp.cleanup()
            raise RuntimeError("下载仓库压缩包失败：\n" + "\n".join(errors))

    extract_path = temp_path / "repo"
    emit("解压仓库压缩包")
    with zipfile.ZipFile(zip_path) as archive:
        archive.extractall(extract_path)

    children = [p for p in extract_path.iterdir() if p.is_dir()]
    if not children:
        temp.cleanup()
        raise RuntimeError("下载的仓库压缩包无效：没有仓库目录。")
    parts = children[0].name.rsplit("-", 1)
    if len(parts) == 2 and len(parts[1]) >= 7:
        commit = parts[1]
    return RemoteRepo(repo=repo, ref=ref, commit=commit, root=children[0], temp=temp)
