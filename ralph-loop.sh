#!/bin/bash

# Ralph Loop Script - Optimized for Claude Sonnet 4
# External loop control to handle Sonnet's tendency to exit early

# Configuration
MAX_ITERATIONS=50
SLEEP_BETWEEN=5
LOG_DIR="loop-logs"
LOG_FILE="$LOG_DIR/ralph-loop-$(date +%Y%m%d-%H%M%S).log"

# Files
PRD_FILE="prd.md"
PROGRESS_FILE="progress.txt"
FEATURES_FILE="features.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Trap Ctrl+C and other exit signals
cleanup() {
    echo ""
    echo -e "${YELLOW}=== Script interrupted ===${NC}"
    echo "Progress saved in: $PROGRESS_FILE"
    echo "Log saved in: $LOG_FILE"
    echo "Run ./ralph-loop.sh again to continue"
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
echo "=== Ralph Loop Started: $(date) ===" > "$LOG_FILE"

# Function to check if all tasks are complete
check_completion() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        echo "false"
        return
    fi
    
    # Count incomplete tasks (lines with [ ])
    # Use tr to remove any whitespace/newlines from grep output
    incomplete=$(grep -c '\[ \]' "$PROGRESS_FILE" 2>/dev/null | tr -d '[:space:]' || echo "0")
    
    # Default to 0 if empty
    if [[ -z "$incomplete" ]]; then
        incomplete=0
    fi
    
    if [[ "$incomplete" -eq 0 ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# Function to get current task number
get_progress() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        echo "0/?"
        return
    fi
    
    # Use tr to clean grep output
    total=$(grep -c '\[' "$PROGRESS_FILE" 2>/dev/null | tr -d '[:space:]' || echo "0")
    done=$(grep -c '\[x\]' "$PROGRESS_FILE" 2>/dev/null | tr -d '[:space:]' || echo "0")
    
    # Default to 0 if empty
    [[ -z "$total" ]] && total=0
    [[ -z "$done" ]] && done=0
    
    echo "$done/$total"
}

# Function to run one iteration
run_iteration() {
    local iteration=$1
    
    # Keep prompt SHORT and EXPLICIT for Sonnet
    # Critical: Tell it to do ONE thing, not loop
    local prompt="You are continuing a development task. This is iteration $iteration.

INSTRUCTIONS - READ CAREFULLY:
1. Read these files first: $FEATURES_FILE, $PRD_FILE, $PROGRESS_FILE
2. Find the HIGHEST PRIORITY incomplete task:
   - Look at $PROGRESS_FILE for tasks marked [ ] (incomplete)
   - Check $FEATURES_FILE for their priority (lower number = higher priority)
   - Pick the task with the lowest priority number
   - If multiple tasks have the same priority, pick any one
3. Check the 'type' field in $FEATURES_FILE for this task:
   - 'implementation': Just implement the feature. No test verification needed.
   - 'bugfix': Fix the bug AND run unit tests to verify the fix.
   - 'testing': Write or fix the unit tests AND verify they pass.
   - If no type specified, treat as 'implementation'.
4. Check if this feature is ALREADY IMPLEMENTED/FIXED in the codebase
5. If ALREADY DONE: verify it works (and tests pass if bugfix/unittest). If yes, mark it [x] in $PROGRESS_FILE and say 'ALREADY_DONE: <feature name>'. Do NOT redo.
6. If NOT DONE: implement/fix following the notes in $FEATURES_FILE
7. For 'bugfix' and 'testing' types:
   - Run tests ONLY on the specific file you modified (not all tests)
   - Use the test command pattern from $PRD_FILE with the specific file path
   - Example (Angular): ng test --include=**/auth.service.spec.ts --browsers=ChromeHeadless --watch=false
   - Example (Spring Boot): ./mvnw test -Dtest=AuthServiceTest
   - Only mark [x] if the specific file's tests pass
8. CLEANUP before marking complete:
   - Delete any temporary files you created (test outputs, logs, debug files)
   - Remove any console.log or debug statements you added
   - Do NOT delete actual source code or test files
   - Leave the codebase clean and production-ready
9. After completing, update $PROGRESS_FILE: change [ ] to [x] for the completed task
10. STOP after completing ONE task - do not continue to the next

IMPORTANT:
- Do ONE task only, then stop
- Always pick the highest priority (lowest number) incomplete task
- For bugfix/testing: run tests ONLY on the affected file, not all tests
- For bugfix/testing: tests MUST pass before marking [x]
- CLEANUP: Delete temp files, logs, debug code before marking complete
- Do NOT redo existing work
- Update $PROGRESS_FILE before stopping
- If no [ ] tasks remain, say 'ALL_TASKS_COMPLETE'

Begin now. Read the files and handle the highest priority incomplete task."

    echo -e "${YELLOW}[Iteration $iteration]${NC} Running Claude..." | tee -a "$LOG_FILE"
    echo "Prompt: $prompt" >> "$LOG_FILE"
    echo "---" >> "$LOG_FILE"
    
    # Run Claude without timeout - let it complete naturally
    claude --dangerously-skip-permissions -p "$prompt" 2>&1 | tee -a "$LOG_FILE"
    
    local exit_code=${PIPESTATUS[0]}
    
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${RED}[Iteration $iteration]${NC} Claude exited with code $exit_code" | tee -a "$LOG_FILE"
        return 1
    fi
    
    echo "---" >> "$LOG_FILE"
    return 0
}

# Pre-flight checks
echo -e "${GREEN}=== Ralph Loop ===${NC}"
echo "Checking required files..."

missing_files=0
for f in "$PRD_FILE" "$FEATURES_FILE"; do
    if [[ ! -f "$f" ]]; then
        echo -e "${RED}Missing: $f${NC}"
        missing_files=1
    else
        echo -e "${GREEN}Found: $f${NC}"
    fi
done

if [[ $missing_files -eq 1 ]]; then
    echo -e "${RED}Please create missing files before running.${NC}"
    exit 1
fi

# Create or sync progress.txt with features.json
sync_progress_file() {
    # Extract feature names from features.json
    local temp_features=$(mktemp)
    grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$FEATURES_FILE" 2>/dev/null | \
        sed 's/"name"[[:space:]]*:[[:space:]]*"//; s/"$//' > "$temp_features"
    
    # If no "name" fields found, try "title" fields
    if [[ ! -s "$temp_features" ]]; then
        grep -o '"title"[[:space:]]*:[[:space:]]*"[^"]*"' "$FEATURES_FILE" 2>/dev/null | \
            sed 's/"title"[[:space:]]*:[[:space:]]*"//; s/"$//' > "$temp_features"
    fi
    
    # If still empty, warn and exit function
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
        # Check if feature already exists in progress.txt (either [ ] or [x])
        if ! grep -qF "$feature" "$PROGRESS_FILE" 2>/dev/null; then
            # Feature not found, append it
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

# Run sync
sync_progress_file

echo ""
echo "Starting loop with max $MAX_ITERATIONS iterations..."
echo "Progress: $(get_progress)"
echo ""

# Main loop - EXTERNAL control, not relying on Claude to loop
iteration=1
consecutive_failures=0
max_failures=3

while [[ $iteration -le $MAX_ITERATIONS ]]; do
    # Check if complete before running
    if [[ "$(check_completion)" == "true" ]]; then
        echo -e "${GREEN}=== ALL TASKS COMPLETE ===${NC}"
        echo "Finished at iteration $iteration"
        echo "=== Completed: $(date) ===" >> "$LOG_FILE"
        exit 0
    fi
    
    echo -e "${GREEN}Progress: $(get_progress)${NC}"
    
    # Run one iteration
    if run_iteration $iteration; then
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
