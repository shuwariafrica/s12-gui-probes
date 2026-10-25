#!/usr/bin/env bash
# The JavaFX probe's TestFX test (click and type into a window, read its
# label) on a hosted macOS runner, against JavaFX's macOS arm64 build and the
# image's JDK 25. Exit 0 on PASS.
set -euo pipefail
export JAVA_HOME="${JAVA_HOME_25_arm64:?the arm64 macOS image sets JAVA_HOME_25_arm64}"
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mvn --batch-mode --quiet -f "${here}/javafx/pom.xml" -Djavafx.platform=mac-aarch64 \
  -Dsurefire.timeout=300 -DsurefireArgs=-Dtestfx.robot=glass test | tee javafx.log
grep -q 'glass platform:' javafx.log
echo 'PASS macos-javafx: TestFX typed and clicked; the label answered'
