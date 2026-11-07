"""Exercise the real CLI and independently check the workshop plan."""

import argparse
import csv
import json
import os
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def check(node: str, cli: Path) -> None:
    manifest = ROOT / "examples/workshop.json"

    def run(*args: object, code: int = 0) -> subprocess.CompletedProcess:
        result = subprocess.run(
            [node, str(cli), *map(str, args)],
            capture_output=True,
            encoding="utf-8",
            timeout=20,
        )
        assert result.returncode == code, (args, result.stderr, result.stdout)
        return result

    source = manifest.read_bytes()
    report = json.loads(run("plan", manifest).stdout)
    assert report["schema"] == "benchkitmap/plan-v1"
    assert [o["buildable"] for o in report["orders"]] == [4, 2]
    totals = {p["part"]: p for p in report["parts"]}
    expected = {
        "sensor": (6, 14, 6, 0, 8),
        "board": (10, 14, 6, 4, 4),
        "lead": (30, 48, 22, 8, 18),
        "enclosure": (4, 6, 4, 0, 2),
        "bolt": (30, 40, 20, 10, 10),
    }
    columns = ("stock", "required", "issued", "remaining_stock", "shortage")
    assert {part: tuple(row[c] for c in columns) for part, row in totals.items()} == expected
    purchases = {p["part"]: p for p in report["purchases"]}
    assert report["purchase_total_cents"] == "3110"
    assert report["purchase_complete"] is False
    assert purchases["enclosure"] == {"part": "enclosure", "shortage": 2, "status": "unsourced"}
    assert [(p["id"], p["count"]) for p in purchases["sensor"]["packs"]] == [
        ("sensor-3", 1),
        ("sensor-5", 1),
    ]

    with tempfile.TemporaryDirectory(prefix="benchkitmap-smoke-") as directory:
        work = Path(directory)
        pick, buy = work / "pick.csv", work / "buy.csv"
        assert run("plan", manifest, "--format", "pick-csv", "--out", pick).stdout == ""
        run("plan", manifest, "--format", "buy-csv", "--out", buy)
        with pick.open(encoding="utf-8", newline="") as handle:
            pick_rows = list(csv.DictReader(handle))
        with buy.open(encoding="utf-8", newline="") as handle:
            buy_rows = list(csv.DictReader(handle))
        assert len(pick_rows) == 9
        assert sum(int(r["pick_units"]) for r in pick_rows if r["part"] == "sensor") == 6
        assert sum(int(r["line_price_cents"]) for r in buy_rows if r["status"] == "priced") == 3110
        assert [r["part"] for r in buy_rows if r["status"] == "unsourced"] == ["enclosure"]

        original = pick.read_bytes()
        exists = run("plan", manifest, "--out", pick, code=2)
        assert "already exists" in exists.stderr
        assert pick.read_bytes() == original
        assert not list(work.glob(".benchkitmap-*"))

        invalid = work / "invalid.json"
        absent = work / "absent.json"
        invalid.write_bytes(b"\xff")
        assert "UTF-8" in run("plan", invalid, "--out", absent, code=2).stderr
        assert not absent.exists()
        invalid.write_bytes(b" " * (2 * 1024 * 1024 + 1))
        assert "2 MiB" in run("plan", invalid, code=2).stderr
        assert "duplicate --format" in run(
            "plan", manifest, "--format", "json", "--format", "pick-csv", code=2
        ).stderr
    assert manifest.read_bytes() == source
    print("BenchKitMap CLI workshop, CSV and failure checks passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--node", default=os.environ.get("BENCHKITMAP_NODE", "node"))
    parser.add_argument("--cli", type=Path, default=ROOT / "_build/js/release/build/cmd/main/main.js")
    args = parser.parse_args()
    check(args.node, args.cli.resolve())
