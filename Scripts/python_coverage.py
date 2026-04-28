from __future__ import annotations

import argparse
import sys
import trace
import types
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
TARGETS = [
    REPO_ROOT / "Backend" / "agendum_backend" / "helper.py",
]


def main() -> int:
    parser = argparse.ArgumentParser(description="Run backend tests with stdlib line coverage.")
    parser.add_argument(
        "--fail-under",
        type=float,
        default=0.0,
        help="Fail if total covered executable lines are below this percentage.",
    )
    args = parser.parse_args()

    if str(REPO_ROOT) not in sys.path:
        sys.path.insert(0, str(REPO_ROOT))

    runner = trace.Trace(
        count=True,
        trace=False,
        ignoredirs=[sys.base_prefix, sys.base_exec_prefix],
    )
    tests_ok = runner.runfunc(run_tests)
    counts = runner.results().counts

    coverage = build_report(counts)
    print_report(coverage)

    if not tests_ok:
        return 1
    if coverage.total_percent < args.fail_under:
        print(
            f"Coverage {coverage.total_percent:.1f}% is below required {args.fail_under:.1f}%.",
            file=sys.stderr,
        )
        return 1
    return 0


def run_tests() -> bool:
    suite = unittest.defaultTestLoader.discover(str(REPO_ROOT / "Tests"))
    result = unittest.TextTestRunner(verbosity=1).run(suite)
    return result.wasSuccessful()


class CoverageReport:
    def __init__(self, files: list["FileCoverage"]) -> None:
        self.files = files

    @property
    def covered(self) -> int:
        return sum(file.covered for file in self.files)

    @property
    def executable(self) -> int:
        return sum(file.executable for file in self.files)

    @property
    def total_percent(self) -> float:
        if self.executable == 0:
            return 100.0
        return self.covered / self.executable * 100


class FileCoverage:
    def __init__(self, path: Path, executable_lines: set[int], covered_lines: set[int]) -> None:
        self.path = path
        self.executable_lines = executable_lines
        self.covered_lines = executable_lines & covered_lines

    @property
    def covered(self) -> int:
        return len(self.covered_lines)

    @property
    def executable(self) -> int:
        return len(self.executable_lines)

    @property
    def percent(self) -> float:
        if self.executable == 0:
            return 100.0
        return self.covered / self.executable * 100

    @property
    def missing_lines(self) -> list[int]:
        return sorted(self.executable_lines - self.covered_lines)


def build_report(counts: dict[tuple[str, int], int]) -> CoverageReport:
    executed_by_file: dict[Path, set[int]] = {}
    for filename, line_number in counts:
        path = Path(filename).resolve()
        executed_by_file.setdefault(path, set()).add(line_number)

    files = [
        FileCoverage(
            path=target,
            executable_lines=executable_lines(target),
            covered_lines=executed_by_file.get(target.resolve(), set()),
        )
        for target in TARGETS
    ]
    return CoverageReport(files)


def executable_lines(path: Path) -> set[int]:
    code = compile(path.read_text(), str(path), "exec")
    return collect_code_lines(code)


def collect_code_lines(code: types.CodeType) -> set[int]:
    lines = {
        line_number
        for _, _, line_number in code.co_lines()
        if line_number is not None and line_number > 0
    }
    for constant in code.co_consts:
        if isinstance(constant, types.CodeType):
            lines.update(collect_code_lines(constant))
    return lines


def print_report(report: CoverageReport) -> None:
    print("\nBackend coverage")
    for file in report.files:
        relative = file.path.relative_to(REPO_ROOT)
        print(f"{relative}: {file.covered}/{file.executable} lines ({file.percent:.1f}%)")
        if file.missing_lines:
            missing = ", ".join(str(line) for line in file.missing_lines)
            print(f"  missing: {missing}")
    print(f"TOTAL: {report.covered}/{report.executable} lines ({report.total_percent:.1f}%)")


if __name__ == "__main__":
    raise SystemExit(main())
