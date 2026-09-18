#!/usr/bin/env python3
"""Build the matching macOS harness and code-mode helper with pinned V8 artifacts."""

import os
import platform
from pathlib import Path
import subprocess
import sys


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    if platform.system() != "Darwin":
        raise SystemExit("This build script targets macOS.")
    targets = {"arm64": "aarch64-apple-darwin", "x86_64": "x86_64-apple-darwin"}
    target = targets.get(platform.machine())
    if target is None:
        raise SystemExit("Unsupported macOS architecture.")
    os.environ["CODEX_REPO_ROOT"] = str(root)
    sys.path.insert(0, str(root / "scripts"))
    from codex_package.targets import TARGET_SPECS
    from codex_package.v8 import resolve_codex_v8_cargo_env

    env = dict(os.environ)
    env.update(resolve_codex_v8_cargo_env(TARGET_SPECS[target]))
    env["CARGO_PROFILE_DEV_SMALL_STRIP"] = "none"
    env.setdefault("CARGO_BUILD_JOBS", "6")
    subprocess.run(
        [
            "cargo",
            "build",
            "--locked",
            "--profile",
            "dev-small",
            "-p",
            "codex-cli",
            "-p",
            "codex-code-mode-host",
        ],
        cwd=root / "codex-rs",
        env=env,
        check=True,
    )


if __name__ == "__main__":
    main()
