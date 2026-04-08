#!/usr/bin/env bash
# scripts/heal_performance.sh — Self-heal PERFORMANCE-class test failures
#
# Checks for performance anti-patterns and reports actionable diagnostics.
set -uo pipefail

PACKAGE_PATH="${1:-QuartzKit}"
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

echo -e "${YELLOW}[HEAL:PERFORMANCE] Running performance self-heal checks...${RESET}"
HEAL_NEEDED=0

# 1. Check for synchronous file I/O in Presentation layer
SYNC_IO=$(grep -rn "String(contentsOf:" "$PACKAGE_PATH/Sources/QuartzKit/Presentation/" --include="*.swift" 2>/dev/null | wc -l | tr -d ' ')
SYNC_IO=${SYNC_IO:-0}
if [ "$SYNC_IO" -gt 0 ]; then
    echo -e "  ${RED}✗ Found $SYNC_IO synchronous file reads in Presentation layer (excluding Widgets)${RESET}"
    grep -rn "String(contentsOf:" "$PACKAGE_PATH/Sources/QuartzKit/Presentation/" --include="*.swift" | head -5
    HEAL_NEEDED=1
else
    echo "  ✓ No synchronous file I/O in Presentation layer"
fi

# 2. Check for unbounded collections in @Observable types
PUBLISHED_ARRAYS=$(grep -rn "\[.*\] =" "$PACKAGE_PATH/Sources/QuartzKit/Presentation/" --include="*.swift" 2>/dev/null | grep -i "var " | wc -l | tr -d ' ')
PUBLISHED_ARRAYS=${PUBLISHED_ARRAYS:-0}
echo "  Found $PUBLISHED_ARRAYS array properties in Presentation (review for unbounded growth)"

# 3. Check for missing @MainActor on ViewModels
VIEWMODELS=$(find "$PACKAGE_PATH/Sources/" -name "*ViewModel.swift" -exec grep -L "@MainActor\|@Observable" {} \;)
if [ -n "$VIEWMODELS" ]; then
    echo -e "  ${RED}✗ ViewModels without @MainActor or @Observable:${RESET}"
    echo "$VIEWMODELS"
    HEAL_NEEDED=1
else
    echo "  ✓ All ViewModels have proper actor isolation"
fi

if [ "$HEAL_NEEDED" -gt 0 ]; then
    echo -e "${RED}[HEAL:PERFORMANCE] Manual fixes needed — see above${RESET}"
    exit 1
fi

echo -e "${GREEN}[HEAL:PERFORMANCE] All performance checks passed${RESET}"
