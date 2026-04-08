#!/usr/bin/env bash
# scripts/heal_accessibility.sh — Self-heal ACCESSIBILITY-class test failures
#
# Verifies accessibility modifiers exist in production source files.
set -euo pipefail

PACKAGE_PATH="${1:-QuartzKit}"
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
RESET='\033[0m'

echo -e "${YELLOW}[HEAL:ACCESSIBILITY] Running accessibility self-heal checks...${RESET}"
HEAL_NEEDED=0

# 1. Check for required accessibility identifiers in key views
REQUIRED_IDS=("sidebar-file-tree" "sidebar-new-note" "workspace-split-view" "editor-text-view" "dashboard-view")
for id in "${REQUIRED_IDS[@]}"; do
    COUNT=$(grep -r "\"$id\"" "$PACKAGE_PATH/Sources/" --include="*.swift" | wc -l | tr -d ' ')
    if [ "$COUNT" -eq 0 ]; then
        echo -e "  ${RED}✗ Missing accessibility identifier: $id${RESET}"
        HEAL_NEEDED=1
    else
        echo "  ✓ Found identifier: $id"
    fi
done

# 2. Check for .accessibilityLabel on interactive elements
LABEL_COUNT=$(grep -r "\.accessibilityLabel" "$PACKAGE_PATH/Sources/QuartzKit/Presentation/" --include="*.swift" | wc -l | tr -d ' ')
if [ "$LABEL_COUNT" -lt 3 ]; then
    echo -e "  ${RED}✗ Only $LABEL_COUNT .accessibilityLabel found — expected at least 3${RESET}"
    HEAL_NEEDED=1
else
    echo "  ✓ Found $LABEL_COUNT .accessibilityLabel instances"
fi

# 3. Check for .accessibilityHint on discoverable elements
HINT_COUNT=$(grep -r "\.accessibilityHint" "$PACKAGE_PATH/Sources/QuartzKit/Presentation/" --include="*.swift" | wc -l | tr -d ' ')
echo "  Found $HINT_COUNT .accessibilityHint instances"

# 4. Check for hardcoded colors in text foreground (Increase Contrast compliance)
HARDCODED=$(grep -r "Color\.black\|Color\.white\|Color(hex" "$PACKAGE_PATH/Sources/QuartzKit/Presentation/" --include="*.swift" | grep -i "foreground" | wc -l | tr -d ' ')
if [ "$HARDCODED" -gt 0 ]; then
    echo -e "  ${RED}✗ Found $HARDCODED hardcoded color foreground uses — may violate Increase Contrast${RESET}"
    HEAL_NEEDED=1
else
    echo "  ✓ No hardcoded foreground colors found"
fi

if [ "$HEAL_NEEDED" -gt 0 ]; then
    echo -e "${RED}[HEAL:ACCESSIBILITY] Manual fixes needed — see above${RESET}"
    exit 1
fi

echo -e "${GREEN}[HEAL:ACCESSIBILITY] All accessibility checks passed${RESET}"
