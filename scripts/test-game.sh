#!/usr/bin/env bash
# Prüft das originale Spielmodell mit festen Karten und kontrollierten Animationspausen.
set -euo pipefail
cd "$(dirname "$0")/.."
SCRATCH="$(mktemp -d /tmp/blackjack-checks.XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT
python3 - "$SCRATCH/GameChecks.swift" <<'PY'
from pathlib import Path
import sys
source = Path("BlackJack/ContentView.swift").read_text()
settings = source[source.index("private enum Rules {"):source.index("private enum Palette {")]
engine = source[source.index("// MARK: - Karten & Hände"):source.index("// MARK: - Jeton-Werte")]
dialogue = source[source.index("private enum Lines {"):source.index("// MARK: - Erfolge")]
chips = source[source.index("private func chipValues("):source.index("// MARK: - Tische & Bar-Ladys")]
recharge = source[source.index("private enum Deck {"):source.index("/// TimelineView-Zeitplan")]
formatting = source[source.index("private let euroFormat"):source.index("extension EnvironmentValues")]
tests = Path("Tests/GameChecks.swift").read_text()
Path(sys.argv[1]).write_text("import SwiftUI\nimport Foundation\n" + settings + formatting + engine + dialogue + chips + recharge + tests)
PY
xcrun swiftc -parse-as-library -swift-version 6 "$SCRATCH/GameChecks.swift" -o "$SCRATCH/game-checks"
"$SCRATCH/game-checks"
