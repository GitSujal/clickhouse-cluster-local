#!/bin/bash
# Helper script to extract specific sections from test_sql.sql
# Usage: ./extract_sql.sh SECTION_NAME

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 SECTION_NAME"
    echo ""
    echo "Available sections:"
    grep "^-- SECTION:" test_sql.sql | sed 's/-- SECTION: /  - /'
    exit 1
fi

SECTION=$1
SQL_FILE="test_sql.sql"

if [ ! -f "$SQL_FILE" ]; then
    echo "Error: $SQL_FILE not found"
    exit 1
fi

# Extract the section between "-- SECTION: $SECTION" and the next "-- ===" line with "SECTION:"
awk -v section="$SECTION" '
    /^-- SECTION: / {
        # Check if this is our target section
        found_section = 0
        for (i = 3; i <= NF; i++) {
            if ($i == section) {
                found_section = 1
                break
            }
        }

        if (found_section) {
            in_section = 1
            next
        } else if (in_section) {
            # We hit a new section, stop
            exit
        }
    }

    # Stop at the next section divider if we are in a section
    /^-- =====.*SECTION:/ && in_section {
        exit
    }

    # Print non-comment lines when in section, also preserve blank lines for readability
    in_section {
        # Skip comment lines but keep SQL
        if (!/^--/) {
            print
        }
    }
' "$SQL_FILE"
