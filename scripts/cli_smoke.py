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
    projection = json.loads(run("project", manifest).stdout)
    assert projection["purchase_complete"] is False
    assert [(row["buildable_now"], row["buildable_after_priced_purchases"]) for row in projection["orders"]] == [(4, 4), (2, 8)]

    with tempfile.TemporaryDirectory(prefix="benchkitmap-smoke-") as directory:
        work = Path(directory)
        counts, refreshed = work / "counts.csv", work / "refreshed.json"
        counts.write_bytes(b'"part","stock"\r\n"enclosure","6"\r\n')
        run("refresh-stock", manifest, counts, "--out", refreshed)
        refreshed_plan = json.loads(run("plan", refreshed).stdout)
        assert [row["buildable"] for row in refreshed_plan["orders"]] == [6, 0]
        assert refreshed_plan["purchase_complete"] is True
        issued = work / "issued.json"
        run("issue", manifest, "desk-session", "3", "--out", issued, code=2)
        assert not issued.exists()
        run("issue", manifest, "field-session", "3", "--out", issued)
        next_input = json.loads(issued.read_text(encoding="utf-8"))
        assert [part["stock"] for part in next_input["parts"]] == [3, 7, 18, 1, 18]
        assert [order["quantity"] for order in next_input["orders"]] == [3, 8]
        next_plan = json.loads(run("plan", issued).stdout)
        assert [row["buildable"] for row in next_plan["orders"]] == [1, 2]

        first_csv = ROOT / "examples/delivery-first.csv"
        second_csv = ROOT / "examples/delivery-second.csv"
        before_deliveries = (first_csv.read_bytes(), second_csv.read_bytes())
        first, second = work / "received-first.json", work / "received-second.json"
        run("receive", manifest, first_csv, "--out", first)
        after_first = first.read_bytes()
        first_plan = json.loads(run("plan", first).stdout)
        assert [row["buildable"] for row in first_plan["orders"]] == [4, 5]
        assert first_plan["parts"][0]["stock"] == 9
        assert first_plan["parts"][0]["shortage"] == 5
        run("receive", first, second_csv, "--out", second)
        after_second = second.read_bytes()
        second_plan = json.loads(run("plan", second).stdout)
        assert [row["buildable"] for row in second_plan["orders"]] == [4, 8]
        assert [p["stock"] for p in second_plan["parts"]] == [14, 15, 50, 4, 40]
        assert second_plan["purchases"] == [{"part": "enclosure", "shortage": 2, "status": "unsourced"}]
        assert [o["quantity"] for o in json.loads(after_second)["orders"]] == [6, 8]
        assert "already exists" in run("receive", first, second_csv, "--out", second, code=2).stderr
        assert second.read_bytes() == after_second
        assert first.read_bytes() == after_first
        assert (first_csv.read_bytes(), second_csv.read_bytes()) == before_deliveries
        invalid_delivery, missing_snapshot = work / "invalid-delivery.csv", work / "not-published.json"
        invalid_delivery.write_bytes(b"part,pack,count\nsensor,sensor-3,1\nsensor,unknown,1\n")
        assert "unknown pack" in run("receive", manifest, invalid_delivery, "--out", missing_snapshot, code=2).stderr
        assert not missing_snapshot.exists()

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
    print("BenchKitMap CLI workshop, deliveries, CSV and failure checks passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--node", default=os.environ.get("BENCHKITMAP_NODE", "node"))
    parser.add_argument("--cli", type=Path, default=ROOT / "_build/js/release/build/cmd/main/main.js")
    args = parser.parse_args()
    check(args.node, args.cli.resolve())
