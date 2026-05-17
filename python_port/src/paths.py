"""Path helpers for running scripts from the project root or python_port."""

from __future__ import annotations

from pathlib import Path


PYTHON_PORT_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = PYTHON_PORT_ROOT.parent
DATA_DIR = PROJECT_ROOT / "data"
RESULTS_DIR = PYTHON_PORT_ROOT / "results"
FIGURES_DIR = PYTHON_PORT_ROOT / "figures"
CACHE_DIR = PYTHON_PORT_ROOT / "cache"


def require_file(path: Path) -> Path:
    if not path.exists():
        raise FileNotFoundError(f"Required file not found: {path}")
    return path
