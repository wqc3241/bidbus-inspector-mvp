import subprocess
import sys

import pytest
from conftest import ROOT, sample

from app.cr import build_cr

SAMPLES = ["bmw-x3", "tesla-model-y"]


@pytest.mark.parametrize("name", SAMPLES)
def test_samples_pass_validation(name):
    assert build_cr(sample(name))["validation"]["ok"]


@pytest.mark.parametrize("name", SAMPLES)
def test_cli_output_equals_sample(name, tmp_path):
    out = tmp_path / "cr.json"
    subprocess.run([sys.executable, "-I", str(ROOT / "tools/cr_from_inspection.py"), str(ROOT / f"samples/inspection-{name}.json"), str(out)],
                   check=True, capture_output=True)
    assert out.read_bytes() == (ROOT / f"samples/cr-{name}.json").read_bytes()


def test_unknown_place_is_refused_with_its_reason():
    rec = sample("bmw-x3")
    rec["damages"][0]["place"] = "Moon roof"
    v = build_cr(rec)["validation"]
    assert not v["ok"]
    assert "damage 1: place 'Moon roof' is not in the Exterior list" in v["errors"]
