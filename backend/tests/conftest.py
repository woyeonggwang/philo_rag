"""모든 테스트 공통. 사용량 DB 를 임시 파일로 돌려 실제 backend/data/usage.db 를 건드리지 않는다."""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.config import get_settings  # noqa: E402


@pytest.fixture(autouse=True)
def _temp_usage_db(tmp_path, monkeypatch):
    monkeypatch.setattr(get_settings(), "usage_db", tmp_path / "usage.db")
