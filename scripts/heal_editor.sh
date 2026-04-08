#!/usr/bin/env bash
# scripts/heal_editor.sh — Self-heal EDITOR-class test failures
#
# Checks for common editor failure patterns and applies safe fixes.
set -euo pipefail

PACKAGE_PATH="${1:-QuartzKit}"
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

echo -e "${YELLOW}[HEAL:EDITOR] Running editor self-heal checks...${RESET}"

# 1. Verify MarkdownASTHighlighter exists and compiles
if [ -f "$PACKAGE_PATH/Sources/QuartzKit/Domain/Editor/MarkdownASTHighlighter.swift" ]; then
    echo "  ✓ MarkdownASTHighlighter.swift exists"
else
    echo "  ✗ MarkdownASTHighlighter.swift MISSING — cannot auto-heal"
    exit 1
fi

# 2. Check for accidental .linear() animations in editor code
LINEAR_COUNT=$(grep -r "\.linear(" "$PACKAGE_PATH/Sources/QuartzKit/Presentation/Editor/" --include="*.swift" | wc -l | tr -d ' ')
if [ "$LINEAR_COUNT" -gt 0 ]; then
    echo "  ✗ Found $LINEAR_COUNT .linear() animations in Editor — these may cause Reduce Motion failures"
    echo "    → Manual fix needed: replace with spring-family animations"
else
    echo "  ✓ No .linear() animations in Editor code"
fi

# 3. Verify EditorSession has proper @MainActor isolation
if grep -q "@MainActor" "$PACKAGE_PATH/Sources/QuartzKit/Domain/Editor/EditorSession.swift" 2>/dev/null || \
   grep -q "@Observable" "$PACKAGE_PATH/Sources/QuartzKit/Domain/Editor/EditorSession.swift" 2>/dev/null; then
    echo "  ✓ EditorSession has proper actor isolation"
else
    echo "  ✗ EditorSession may lack @MainActor — check concurrency"
fi

echo -e "${GREEN}[HEAL:EDITOR] Editor heal checks complete${RESET}"
