#!/usr/bin/env python3
"""Run the real Foundation-only journey rules without booting an iOS simulator.

The app's XCTest file is reused unchanged. Supporting model declarations are
extracted verbatim; this doesn't substitute implementations or mock behavior.
Full app compilation and device acceptance checks remain separate.
"""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent


def section(text: str, start: str, end: str) -> str:
    first = text.index(start)
    return text[first:text.index(end, first)]


with tempfile.TemporaryDirectory(prefix="mivo-attention-core-") as directory:
    package = Path(directory)
    sources = package / "Sources" / "Mivo"
    tests = package / "Tests" / "AttentionTests"
    sources.mkdir(parents=True)
    tests.mkdir(parents=True)
    (package / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "MivoAttentionCore",
    platforms: [.macOS(.v13)],
    targets: [.target(name: "Mivo"), .testTarget(name: "AttentionTests", dependencies: ["Mivo"])]
)
''')
    for source in ["Mivo/Models/AttentionJourney.swift", "Mivo/Services/StorageService.swift"]:
        shutil.copyfile(root / source, sources / Path(source).name)
    models = (root / "Mivo/Models/Models.swift").read_text()
    clear = (root / "Mivo/Models/MivoClearModels.swift").read_text()
    support = "import Foundation\n\n" + section(models, "enum WeeklyExperimentType:", "struct WeeklyExperimentRule:")
    support += section(clear, "enum MivoClearPlatform:", "enum MivoClearMappingError:")
    support += section(clear, "struct MivoClearRoute:", "struct MivoClearQuickAction:")
    (sources / "SupportingModels.swift").write_text(support)
    shutil.copyfile(root / "MivoClearGuardTests/AttentionJourneyTests.swift", tests / "AttentionJourneyTests.swift")
    result = subprocess.run(["swift", "test", "--package-path", str(package), "-j", "2"], check=False)
    raise SystemExit(result.returncode)
