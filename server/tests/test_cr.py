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


def test_a_mirror_headlight_or_tail_light_damage_says_its_side():
    """the app sends which side (where: Left or Right) for these three places; the CR accepts it and words it"""
    rec = sample("bmw-x3")
    d = dict(rec["damages"][0])
    d.update({"n": len(rec["damages"]) + 1, "section": "Exterior", "place": "Mirror", "type": "Mirror damaged", "severity": "Minor",
              "size_in": None, "check_id": "ck_glass", "check_option": "Mirror damaged", "where": "Left", "file": "damage-9.jpg"})
    rec["damages"].append(d)
    glass = next(c for c in rec["checks"] if c["id"] == "ck_glass")
    glass.update({"result": "Problem", "problems": [{"option": "Mirror damaged", "level": "Disclosed", "from_damage_photo": True}]})
    out = build_cr(rec)
    assert out["validation"]["ok"], out["validation"]["errors"]
    issue = next(i for i in out["condition_report"]["issues"] if i["photo"] == "damage-9.jpg")
    assert issue["text"].startswith("Mirror: ") and "(left)" in issue["text"] and issue["where"] == "Left"
