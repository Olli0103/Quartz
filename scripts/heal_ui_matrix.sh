#!/usr/bin/env bash
# scripts/heal_ui_matrix.sh — Self-heal UI_MATRIX-class test failures
#
# Verifies UI test infrastructure is intact and mock vault is functional.
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

echo -e "${YELLOW}[HEAL:UI_MATRIX] Running UI matrix self-heal checks...${RESET}"
HEAL_NEEDED=0

# 1. Check UITestFixtureVault exists
if [ -f "Quartz/UITestFixtureVault.swift" ]; then
    echo "  ✓ UITestFixtureVault.swift exists"
else
    echo -e "  ${RED}✗ UITestFixtureVault.swift MISSING — UI tests cannot create mock vault${RESET}"
    HEAL_NEEDED=1
fi

# 2. Check accessibility identifiers used in UI tests are present in production code
UI_IDS=$(grep -roh '"[a-z-]*"' QuartzUITests/ --include="*.swift" 2>/dev/null | sort -u)
for id in $UI_IDS; do
    CLEAN_ID=$(echo "$id" | tr -d '"')
    if [ ${#CLEAN_ID} -gt 5 ] && echo "$CLEAN_ID" | grep -q "-"; then
        FOUND=$(grep -r "\"$CLEAN_ID\"" QuartzKit/Sources/ Quartz/ --include="*.swift" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$FOUND" -eq 0 ]; then
            echo -e "  ${YELLOW}⚠ UI test references \"$CLEAN_ID\" but not found in production code${RESET}"
        fi
    fi
done

# 3. Check that simulators are available (informational)
if command -v xcrun &>/dev/null; then
    IPHONE=$(xcrun simctl list devices available 2>/dev/null | grep -c "iPhone" || true)
    IPAD=$(xcrun simctl list devices available 2>/dev/null | grep -c "iPad" || true)
    echo "  Simulators available: $IPHONE iPhone, $IPAD iPad"
    if [ "$IPHONE" -eq 0 ]; then
        echo -e "  ${YELLOW}⚠ No iPhone simulators — iOS UI tests will be skipped${RESET}"
    fi
    if [ "$IPAD" -eq 0 ]; then
        echo -e "  ${YELLOW}⚠ No iPad simulators — iPadOS UI tests will be skipped${RESET}"
    fi
fi

if [ "$HEAL_NEEDED" -gt 0 ]; then
    echo -e "${RED}[HEAL:UI_MATRIX] Manual fixes needed — see above${RESET}"
    exit 1
fi

echo -e "${GREEN}[HEAL:UI_MATRIX] UI matrix checks passed${RESET}"
