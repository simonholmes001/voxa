#!/usr/bin/env python3
"""Combine Cobertura line hits across test suites and enforce measured floors."""
import json
import math
import sys
from pathlib import Path
import xml.etree.ElementTree as ET


def check(results, config):
    thresholds = json.loads(Path(config).read_text())
    floors = {"overall": thresholds["overall"], **thresholds["layers"]}
    if not thresholds["layers"] or any(
        isinstance(value, bool) or not isinstance(value, (int, float))
        or not math.isfinite(value) or not 0 <= value <= 100
        for value in floors.values()
    ):
        raise ValueError("Coverage thresholds must be finite percentages between 0 and 100.")
    reports = sorted(Path(results).rglob("*.cobertura.xml"))
    if not reports:
        raise ValueError("No Cobertura reports found.")
    lines = {}
    for report in reports:
        root = ET.parse(report).getroot()
        if root.tag != "coverage":
            raise ValueError(f"Invalid Cobertura document: {report}")
        for item in root.findall("./packages/package/classes/class"):
            filename = item.attrib["filename"].replace("\\", "/")
            if any(part in ("obj", "bin") for part in filename.split("/")):
                continue
            for line in item.findall("./lines/line"):
                number, hits = int(line.attrib["number"]), int(line.attrib["hits"])
                if number <= 0 or hits < 0:
                    raise ValueError("Invalid line number or hit count.")
                key = (filename, number)
                lines[key] = max(lines.get(key, 0), hits)
    passed = True
    for layer, floor in floors.items():
        values = [hits for (filename, _), hits in lines.items()
                  if layer == "overall" or filename.startswith(layer + "/")]
        if not values:
            raise ValueError(f"No source coverage for required layer {layer}.")
        covered = sum(hits > 0 for hits in values)
        percentage = 100 * covered / len(values)
        print(f"{layer}: {covered}/{len(values)} lines ({percentage:.2f}%), minimum {floor}%")
        passed &= percentage >= floor
    return 0 if passed else 1


if __name__ == "__main__":
    try:
        sys.exit(check(sys.argv[1], sys.argv[2]))
    except (ValueError, KeyError, IndexError, OSError, ET.ParseError) as error:
        print(f"Coverage gate failed: {error}", file=sys.stderr)
        sys.exit(1)
