#!/bin/bash

# Ralph Loop V2 - Simplified Prompt Approach
# Moves complexity from prompt to bash script
# Claude gets a focused, single-task prompt similar to direct invocation
#
# For bugfix/testing tasks:
# - Test framework is auto-detected (Maven, Gradle, Jest, etc.)
# - Claude runs targeted tests on modified files only

# Configuration
MAX_ITERATIONS=50
SLEEP_BETWEEN=5
LOG_DIR="loop-logs"
LOG_FILE="$LOG_DIR/ralph-loop-v2-$(date +%Y%m%d-%H%M%S).log"

# Files
PROGRESS_FILE="progress.txt"
FEATURES_FILE="features.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Trap Ctrl+C and other exit signals
cleanup() {
    echo ""
    echo -e "${YELLOW}=== Script interrupted ===${NC}"
    echo "Progress saved in: $PROGRESS_FILE"
    echo "Log saved in: $LOG_FILE"
    echo "Run ./ralph-loop-v2.sh again to continue"
    echo "=== Interrupted: $(date) ===" >> "$LOG_FILE"
    exit 130
}
trap cleanup SIGINT SIGTERM

# Create log directory if it doesn't exist
if [[ ! -d "$LOG_DIR" ]]; then
    mkdir -p "$LOG_DIR"
    echo -e "${GREEN}Created log directory: $LOG_DIR${NC}"
fi

# Initialize log
echo "=== Ralph Loop V2 Started: $(date) ===" > "$LOG_FILE"

# Function to check if all tasks are complete
# Tasks marked [SKIP] or [SKIP2] are treated as "done" (not blocking completion)
check_completion() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        echo "false"
        return
    fi

    local incomplete
    # Count only [ ] tasks, not [SKIP], [SKIP2], or [x]
    incomplete=$(grep -c '^\[ \]' "$PROGRESS_FILE" 2>/dev/null | tr -d '[:space:]' || echo "0")

    if [[ -z "$incomplete" ]]; then
        incomplete=0
    fi

    if [[ "$incomplete" -eq 0 ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Function to handle completion — retries [SKIP] tasks once before declaring done
# [SKIP] = first skip, eligible for retry
# [SKIP2] = already retried, permanent skip
handle_completion() {
    # Check for first-time skips (not [SKIP2])
    local first_skip_count
    first_skip_count=$(grep -c '^\[SKIP\] ' "$PROGRESS_FILE" 2>/dev/null | tr -d '[:space:]' || echo "0")

    if [[ "$first_skip_count" -gt 0 ]]; then
        # Revert [SKIP] back to [ ] for retry
        local requeued=0
        local temp_prog
        temp_prog=$(mktemp)
        while IFS= read -r line; do
            if [[ "$line" == "[SKIP] "* ]]; then
                local task_name
                task_name=$(echo "$line" | sed 's/^\[SKIP\] //; s/ - .*//')
                echo "[ ] $task_name"
                retried_tasks+=("$task_name")
                echo -e "${YELLOW}[Retry]${NC} Re-queuing skipped task: $task_name" | tee -a "$LOG_FILE"
                ((requeued++))
            else
                echo "$line"
            fi
        done < "$PROGRESS_FILE" > "$temp_prog"
        mv "$temp_prog" "$PROGRESS_FILE"

        echo -e "${YELLOW}[Retry Pass]${NC} Re-queued $requeued skipped task(s) for a second attempt" | tee -a "$LOG_FILE"
        return 1  # Not done yet, continue loop
    fi

    # Truly complete (no [ ] tasks, only [x] and [SKIP2])
    local final_skipped
    final_skipped=$(grep -c '^\[SKIP2\]' "$PROGRESS_FILE" 2>/dev/null | tr -d '[:space:]' || echo "0")

    echo -e "${GREEN}=== ALL TASKS COMPLETE ===${NC}"
    if [[ "$final_skipped" -gt 0 ]]; then
        echo -e "${YELLOW}$final_skipped task(s) permanently skipped after retry:${NC}"
        grep '^\[SKIP2\]' "$PROGRESS_FILE" | while IFS= read -r line; do
            echo -e "  ${YELLOW}$line${NC}"
        done
    fi
    echo "=== Completed: $(date) ===" >> "$LOG_FILE"
    return 0
}

# Function to get current progress
get_progress() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        echo "0/?"
        return
    fi

    local total done skipped
    # Count all task lines: [ ], [x], [SKIP], or [SKIP2]
    total=$(grep -c '^\[' "$PROGRESS_FILE" 2>/dev/null | tr -d '[:space:]' || echo "0")
    done=$(grep -c '^\[x\]' "$PROGRESS_FILE" 2>/dev/null | tr -d '[:space:]' || echo "0")
    local skip1 skip2
    skip1=$(grep -c '^\[SKIP\] ' "$PROGRESS_FILE" 2>/dev/null | tr -d '[:space:]' || echo "0")
    skip2=$(grep -c '^\[SKIP2\]' "$PROGRESS_FILE" 2>/dev/null | tr -d '[:space:]' || echo "0")
    skipped=$((skip1 + skip2))

    [[ -z "$total" ]] && total=0
    [[ -z "$done" ]] && done=0
    [[ -z "$skipped" ]] && skipped=0

    if [[ "$skipped" -gt 0 ]]; then
        echo "$done/$total ($skipped skipped)"
    else
        echo "$done/$total"
    fi
}

# Function to get incomplete tasks from progress.txt
# Skips tasks marked with [SKIP], [SKIP2]
get_incomplete_tasks() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        return
    fi
    # Only match [ ] at start of line, excludes [SKIP] and [x]
    grep '^\[ \]' "$PROGRESS_FILE" | sed 's/^\[ \] //'
}

# Function to get all features with their priorities
# Returns: priority|name|type lines, sorted by priority
get_features_by_priority() {
    # Parse features using awk - extract priority, name, type triplets
    awk '
        BEGIN { RS="},"; FS="\n" }
        {
            name=""; priority="999"; type="implementation"
            for (i=1; i<=NF; i++) {
                if ($i ~ /"name"/) {
                    gsub(/.*"name"[[:space:]]*:[[:space:]]*"/, "", $i)
                    gsub(/".*/, "", $i)
                    name = $i
                }
                if ($i ~ /"priority"/) {
                    gsub(/.*"priority"[[:space:]]*:[[:space:]]*/, "", $i)
                    gsub(/[^0-9].*/, "", $i)
                    priority = $i
                }
                if ($i ~ /"type"/) {
                    gsub(/.*"type"[[:space:]]*:[[:space:]]*"/, "", $i)
                    gsub(/".*/, "", $i)
                    type = $i
                }
            }
            if (name != "") print priority "|" name "|" type
        }
    ' "$FEATURES_FILE" | sort -t'|' -k1 -n
}

# Function to get task details (priority, type, notes)
get_task_details() {
    local task_name="$1"

    # Parse using awk - extract all details from the matching feature block
    awk -v name="$task_name" '
        BEGIN {
            found = 0
            in_feature = 0
            in_notes = 0
            brace_depth = 0
            priority = "999"
            type = "implementation"
            notes = ""
        }

        # Find the feature with matching name
        /"name"[[:space:]]*:[[:space:]]*"/ {
            if (index($0, "\"" name "\"") > 0) {
                found = 1
                in_feature = 1
                brace_depth = 1  # We are inside a feature object
            }
        }

        # Track brace depth within feature (after finding match)
        found && in_feature {
            for (i=1; i<=length($0); i++) {
                c = substr($0, i, 1)
                if (c == "{") brace_depth++
                if (c == "}") brace_depth--
            }
        }

        # Extract priority
        found && in_feature && /"priority"[[:space:]]*:/ {
            line = $0
            gsub(/.*"priority"[[:space:]]*:[[:space:]]*/, "", line)
            gsub(/[^0-9].*/, "", line)
            if (line != "") priority = line
        }

        # Extract type
        found && in_feature && /"type"[[:space:]]*:[[:space:]]*"/ {
            line = $0
            gsub(/.*"type"[[:space:]]*:[[:space:]]*"/, "", line)
            gsub(/".*/, "", line)
            if (line != "") type = line
        }

        # Handle notes array - detect start
        found && in_feature && /"notes"[[:space:]]*:[[:space:]]*\[/ {
            in_notes = 1
        }

        # Collect notes items (multi-line array)
        found && in_feature && in_notes && /"[^"]*"/ && !/notes/ {
            line = $0
            while (match(line, /"[^"]*"/)) {
                item = substr(line, RSTART+1, RLENGTH-2)
                if (notes != "") notes = notes "\n- "
                notes = notes item
                line = substr(line, RSTART + RLENGTH)
            }
        }

        # End of notes array
        found && in_feature && in_notes && /\]/ {
            in_notes = 0
        }

        # End of feature block
        found && in_feature && brace_depth <= 0 {
            in_feature = 0
        }

        END {
            print "PRIORITY:" priority
            print "TYPE:" type
            print "NOTES:" notes
        }
    ' "$FEATURES_FILE"
}

# Function to get the next task (highest priority incomplete task)
get_next_task() {
    local incomplete_tasks features_by_priority

    # Get list of incomplete task names
    incomplete_tasks=$(get_incomplete_tasks)

    if [[ -z "$incomplete_tasks" ]]; then
        echo ""
        return
    fi

    # Get all features sorted by priority
    features_by_priority=$(get_features_by_priority)

    # Find the first (highest priority) incomplete task
    while IFS='|' read -r priority name type; do
        # Use -x for exact line match to avoid substring false positives
        if echo "$incomplete_tasks" | grep -qFx "$name"; then
            echo "$name"
            return
        fi
    done <<< "$features_by_priority"

    # Fallback: return first incomplete task if not found in features.json
    echo "$incomplete_tasks" | head -1
}

# Function to auto-detect the test framework and return a command hint
detect_test_hint() {
    if [[ -f "pom.xml" ]] || [[ -f "mvnw" ]] || [[ -f "../pom.xml" ]]; then
        local mvn_cmd="mvn"
        [[ -f "./mvnw" ]] && mvn_cmd="./mvnw"
        [[ -f "../mvnw" ]] && mvn_cmd="../mvnw"
        echo "This is a Maven/Spring Boot project. To run a specific test class: $mvn_cmd test -Dtest=TestClassName"
    elif [[ -f "build.gradle" ]] || [[ -f "build.gradle.kts" ]]; then
        local gradle_cmd="gradle"
        [[ -f "./gradlew" ]] && gradle_cmd="./gradlew"
        echo "This is a Gradle project. To run a specific test class: $gradle_cmd test --tests ClassName"
    elif [[ -f "angular.json" ]]; then
        echo "This is an Angular project. To run a specific test: ng test --include=**/file.spec.ts --browsers=ChromeHeadless --watch=false"
    elif [[ -f "package.json" ]]; then
        if grep -q '"jest"' package.json 2>/dev/null || [[ -f "jest.config.js" ]] || [[ -f "jest.config.ts" ]]; then
            echo "This is a Jest project. To run a specific test: npx jest path/to/file.test.ts"
        elif grep -q '"vitest"' package.json 2>/dev/null || [[ -f "vitest.config.ts" ]]; then
            echo "This is a Vitest project. To run a specific test: npx vitest run path/to/file.test.ts"
        elif grep -q '"mocha"' package.json 2>/dev/null; then
            echo "This is a Mocha project. To run a specific test: npx mocha path/to/file.test.js"
        else
            echo "Run ONLY the specific test file(s) related to your changes, NOT the entire test suite."
        fi
    elif [[ -f "pyproject.toml" ]] || [[ -f "pytest.ini" ]] || [[ -f "setup.cfg" ]]; then
        echo "This is a Python project. To run a specific test: pytest path/to/test_file.py -v"
    elif [[ -f "go.mod" ]]; then
        echo "This is a Go project. To run a specific test: go test ./path/to/package -v"
    elif [[ -f "Cargo.toml" ]]; then
        echo "This is a Rust project. To run a specific test: cargo test test_name"
    else
        echo "Run ONLY the specific test file(s) related to your changes, NOT the entire test suite."
    fi
}

# Function to build prompt for implementation tasks
build_implementation_prompt() {
    local task_name="$1"
    local notes="$2"

    local prompt="Your task: $task_name

Context from project requirements:
- $notes

Instructions:
1. Implement the feature following the context above
2. Follow existing code patterns in the codebase
3. After implementation, update $PROGRESS_FILE: change [ ] to [x] for \"$task_name\"
4. ONLY mark [SKIP] for genuine blockers you cannot fix:
   - Missing dependency that cannot be installed
   - Requires an external service/API that is unavailable
   - Build or compile error unrelated to this task
   - Do NOT skip because the task is difficult or you are unsure
   - Format: [SKIP] $task_name - <specific blocker reason>
5. Cleanup: Remove any debug code or temp files before marking complete"

    echo "$prompt"
}

# Function to build prompt for bugfix/testing tasks
build_verification_prompt() {
    local task_name="$1"
    local task_type="$2"
    local notes="$3"

    local action_word
    if [[ "$task_type" == "bugfix" ]]; then
        action_word="Fix the bug"
    else
        action_word="Write/fix the tests"
    fi

    local test_hint
    test_hint=$(detect_test_hint)
    local test_instruction="Run the unit tests for the file(s) you modified.
   $test_hint
   Do NOT run the entire test suite — only the specific test class/file for what you changed."

    local prompt="Your task: $task_name

Context from project requirements:
- $notes

Instructions:
1. $action_word in the relevant file(s)
2. $test_instruction
3. Check the test output carefully:
   - Look for '0 failures', 'Tests passed', or similar success indicators
   - If ANY test fails, fix the code and run tests again
   - Repeat until ALL tests pass
4. ONLY when all tests pass with 0 failures, update $PROGRESS_FILE: change [ ] to [x] for \"$task_name\"
5. ONLY mark [SKIP] for genuine blockers you cannot fix:
   - Missing dependency that cannot be installed
   - Requires an external service/API that is unavailable
   - Build or compile error unrelated to this task
   - Do NOT skip because tests are hard to fix or you are unsure
   - Format: [SKIP] $task_name - <specific blocker reason>
6. Cleanup: Remove any debug code or temp files before marking complete

IMPORTANT:
- You MUST actually run the tests and verify the output
- Do NOT mark [x] if any test is failing
- If tests fail, fix the issue and re-run tests
- Only mark complete when you see 0 failures in the test output"

    echo "$prompt"
}

# Function to run one iteration with simplified prompt
run_iteration() {
    local iteration=$1

    # Get the next task
    local task_name
    task_name=$(get_next_task)

    if [[ -z "$task_name" ]]; then
        echo -e "${GREEN}No more tasks to process${NC}"
        return 2  # Special return code for "all done"
    fi

    echo -e "${BLUE}[Task]${NC} $task_name" | tee -a "$LOG_FILE"

    # Get task details
    local task_details priority task_type notes
    task_details=$(get_task_details "$task_name")

    priority=$(echo "$task_details" | grep "^PRIORITY:" | cut -d: -f2-)
    task_type=$(echo "$task_details" | grep "^TYPE:" | cut -d: -f2-)
    notes=$(echo "$task_details" | grep "^NOTES:" | cut -d: -f2-)

    # Default type if not found
    [[ -z "$task_type" ]] && task_type="implementation"

    echo -e "${BLUE}[Type]${NC} $task_type (priority: $priority)" | tee -a "$LOG_FILE"

    # Build the appropriate prompt based on task type
    local prompt
    if [[ "$task_type" == "bugfix" ]] || [[ "$task_type" == "testing" ]]; then
        prompt=$(build_verification_prompt "$task_name" "$task_type" "$notes")
    else
        prompt=$(build_implementation_prompt "$task_name" "$notes")
    fi

    echo "---" >> "$LOG_FILE"
    echo "Prompt:" >> "$LOG_FILE"
    echo "$prompt" >> "$LOG_FILE"
    echo "---" >> "$LOG_FILE"

    echo -e "${YELLOW}[Iteration $iteration]${NC} Running Claude with focused prompt..." | tee -a "$LOG_FILE"

    # Run Claude with the simplified prompt
    claude --dangerously-skip-permissions -p "$prompt" 2>&1 | tee -a "$LOG_FILE"

    local exit_code=${PIPESTATUS[0]}

    if [[ $exit_code -ne 0 ]]; then
        echo -e "${RED}[Iteration $iteration]${NC} Claude exited with code $exit_code" | tee -a "$LOG_FILE"
        return 1
    fi

    echo "---" >> "$LOG_FILE"
    return 0
}

# Create or sync progress.txt with features.json
sync_progress_file() {
    local temp_features
    temp_features=$(mktemp)

    # Extract feature names from features.json using grep/sed
    grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$FEATURES_FILE" 2>/dev/null | \
        sed 's/"name"[[:space:]]*:[[:space:]]*"//; s/"$//' > "$temp_features"

    # If still empty, try "title" fields
    if [[ ! -s "$temp_features" ]]; then
        grep -o '"title"[[:space:]]*:[[:space:]]*"[^"]*"' "$FEATURES_FILE" 2>/dev/null | \
            sed 's/"title"[[:space:]]*:[[:space:]]*"//; s/"$//' > "$temp_features"
    fi

    if [[ ! -s "$temp_features" ]]; then
        echo -e "${YELLOW}Could not parse $FEATURES_FILE automatically${NC}"
        rm "$temp_features"
        return
    fi

    # If progress.txt doesn't exist, create it fresh
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        echo -e "${YELLOW}Creating $PROGRESS_FILE from $FEATURES_FILE...${NC}"
        while IFS= read -r feature; do
            echo "[ ] $feature"
        done < "$temp_features" > "$PROGRESS_FILE"
        echo -e "${GREEN}Created $PROGRESS_FILE${NC}"
        rm "$temp_features"
        return
    fi

    # progress.txt exists - sync new features
    echo -e "${YELLOW}Syncing $PROGRESS_FILE with $FEATURES_FILE...${NC}"

    local added=0
    while IFS= read -r feature; do
        # Use exact line matching to avoid substring false positives
        # e.g., "Auth" shouldn't match "[ ] Auth Provider"
        if ! grep -qFx "[ ] $feature" "$PROGRESS_FILE" 2>/dev/null && \
           ! grep -qFx "[x] $feature" "$PROGRESS_FILE" 2>/dev/null && \
           ! grep -q "^\[SKIP\] ${feature}$\|^\[SKIP\] ${feature} - " "$PROGRESS_FILE" 2>/dev/null && \
           ! grep -q "^\[SKIP2\] ${feature}$\|^\[SKIP2\] ${feature} - " "$PROGRESS_FILE" 2>/dev/null; then
            echo "[ ] $feature" >> "$PROGRESS_FILE"
            echo -e "${GREEN}Added new feature: $feature${NC}"
            ((added++))
        fi
    done < "$temp_features"

    if [[ $added -eq 0 ]]; then
        echo -e "${GREEN}$PROGRESS_FILE is up to date${NC}"
    else
        echo -e "${GREEN}Added $added new feature(s) to $PROGRESS_FILE${NC}"
    fi

    rm "$temp_features"
}

# Pre-flight checks
echo -e "${GREEN}=== Ralph Loop V2 (Simplified Prompts) ===${NC}"
echo "Checking required files..."

if [[ ! -f "$FEATURES_FILE" ]]; then
    echo -e "${RED}Missing: $FEATURES_FILE${NC}"
    echo -e "${RED}Please create features.json before running.${NC}"
    exit 1
else
    echo -e "${GREEN}Found: $FEATURES_FILE${NC}"
fi

# Run sync
sync_progress_file

echo ""
echo "Starting loop with max $MAX_ITERATIONS iterations..."
echo "Progress: $(get_progress)"
echo ""

# Show next task preview
next_task=$(get_next_task)
if [[ -n "$next_task" ]]; then
    echo -e "${BLUE}Next task:${NC} $next_task"
    echo ""
fi

# Main loop
iteration=1
consecutive_failures=0
max_failures=3
declare -a retried_tasks=()  # Track tasks that have been retried

# Function to promote [SKIP] → [SKIP2] for tasks that were already retried
promote_skips() {
    local promoted=0
    for retried in "${retried_tasks[@]}"; do
        if grep -q "^\[SKIP\] ${retried}$\|^\[SKIP\] ${retried} - " "$PROGRESS_FILE" 2>/dev/null; then
            local temp_prog
            temp_prog=$(mktemp)
            while IFS= read -r line; do
                if [[ "$line" == "[SKIP] $retried" ]] || [[ "$line" == "[SKIP] $retried - "* ]]; then
                    # Replace [SKIP] with [SKIP2] — keep the reason
                    echo "${line/\[SKIP\]/[SKIP2]}"
                    ((promoted++))
                else
                    echo "$line"
                fi
            done < "$PROGRESS_FILE" > "$temp_prog"
            mv "$temp_prog" "$PROGRESS_FILE"
        fi
    done
    if [[ $promoted -gt 0 ]]; then
        echo -e "${YELLOW}[Skip]${NC} $promoted task(s) skipped again after retry — marked permanent" | tee -a "$LOG_FILE"
    fi
}

while [[ $iteration -le $MAX_ITERATIONS ]]; do
    # Check if complete before running
    if [[ "$(check_completion)" == "true" ]]; then
        if handle_completion; then
            exit 0
        fi
        # Skipped tasks were re-queued, continue loop
    fi

    echo -e "${GREEN}Progress: $(get_progress)${NC}"

    # Run one iteration
    run_result=0
    run_iteration $iteration || run_result=$?

    # Promote any retried tasks that got skipped again to [SKIP2]
    promote_skips

    if [[ $run_result -eq 2 ]]; then
        # All [ ] tasks done — check if skipped tasks need retry
        if handle_completion; then
            exit 0
        fi
        # Skipped tasks were re-queued, continue loop
    elif [[ $run_result -eq 0 ]]; then
        consecutive_failures=0
    else
        ((consecutive_failures++))
        echo -e "${YELLOW}Consecutive failures: $consecutive_failures/$max_failures${NC}"

        if [[ $consecutive_failures -ge $max_failures ]]; then
            echo -e "${RED}Too many consecutive failures. Stopping.${NC}"
            echo "=== Failed after $consecutive_failures consecutive failures: $(date) ===" >> "$LOG_FILE"
            exit 1
        fi
    fi

    # Brief pause between iterations
    echo "Waiting ${SLEEP_BETWEEN}s before next iteration..."
    sleep "$SLEEP_BETWEEN"

    ((iteration++))
    echo ""
done

echo -e "${YELLOW}Reached max iterations ($MAX_ITERATIONS). Check progress manually.${NC}"
echo "=== Reached max iterations: $(date) ===" >> "$LOG_FILE"
exit 0
