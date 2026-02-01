# Ralph Loop V2 - Documentation

A bash automation script that orchestrates Claude CLI to work through a list of tasks autonomously. It reads tasks from a `features.json` file, tracks progress in `progress.txt`, and runs Claude in a loop until all tasks are complete.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Required Files](#required-files)
4. [How to Run](#how-to-run)
5. [How It Works](#how-it-works)
6. [Configuration](#configuration)
7. [Task Types](#task-types)
8. [Progress Tracking](#progress-tracking)
9. [Logging](#logging)
10. [Error Handling](#error-handling)
11. [For Developers](#for-developers)

---

## Overview

Ralph Loop V2 is a simplified prompt-based automation script that:

- Reads a list of features/tasks from `features.json`
- Processes tasks in priority order (lowest number = highest priority)
- Generates focused, single-task prompts for Claude CLI
- Tracks progress in `progress.txt` with checkbox notation
- Handles different task types (implementation, bugfix, testing)
- Logs all activity for debugging and review

**Key Design Philosophy:** Move complexity from the AI prompt to the bash script. Claude receives a simple, focused prompt for one task at a time, similar to how you would invoke Claude directly.

---

## Prerequisites

### Required Software

| Software | Purpose | Installation |
|----------|---------|--------------|
| **Bash** | Shell to run the script | Pre-installed on macOS/Linux |
| **Claude CLI** | AI assistant that does the work | `npm install -g @anthropic-ai/claude-code` |

### Claude CLI Setup

1. Install Claude CLI globally
2. Authenticate with your Anthropic API key
3. Verify installation: `claude --version`

**Important:** The script uses `--dangerously-skip-permissions` flag which bypasses Claude's permission prompts. Ensure you trust the tasks being executed.

---

## Required Files

Before running the script, you need one file in the same directory:

### `features.json` - Task List

A JSON file containing all tasks/features to be implemented. Each feature has:

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | The task name (used in progress tracking) |
| `priority` | No | Number indicating order (1 = first, default: 999) |
| `type` | No | Task type: `implementation`, `bugfix`, or `testing` (default: implementation) |
| `notes` | No | Array of context/instructions for Claude |
| `testCommand` | No | Specific test command to run (for bugfix/testing types) |

**Example:**

```json
{
  "project": "My Project",
  "features": [
    {
      "name": "User Authentication",
      "priority": 1,
      "type": "implementation",
      "notes": [
        "Use Angular reactive forms",
        "Follow existing auth.service.ts pattern",
        "Store token in localStorage"
      ]
    },
    {
      "name": "Fix Login Validation Bug",
      "priority": 1,
      "type": "bugfix",
      "notes": [
        "Token expiry not handled correctly",
        "Check auth.service.ts"
      ],
      "testCommand": "ng test --include=**/auth.service.spec.ts"
    },
    {
      "name": "Auth Service Unit Tests",
      "priority": 2,
      "type": "testing",
      "notes": [
        "Cover login, logout, token refresh",
        "Mock HTTP calls"
      ]
    }
  ]
}
```

---

## How to Run

### Basic Usage

```bash
# Navigate to your project directory
cd /path/to/your/project

# Make the script executable (first time only)
chmod +x ralph-loop-v2.sh

# Run the script
./ralph-loop-v2.sh
```

### What Happens on First Run

1. Script checks for `features.json`
2. Creates `progress.txt` from `features.json` (if it doesn't exist)
3. Creates `loop-logs/` directory for logs
4. Starts processing tasks in priority order

### Resuming After Interruption

If you stop the script (Ctrl+C) or it fails:

```bash
# Simply run again - it picks up where it left off
./ralph-loop-v2.sh
```

The script reads `progress.txt` to determine which tasks are still pending.

---

## How It Works

### Execution Flow

```
┌─────────────────────────────────────────────────────────────┐
│                     STARTUP PHASE                           │
├─────────────────────────────────────────────────────────────┤
│ 1. Check for required file (features.json)                  │
│ 2. Sync progress.txt with features.json                     │
│    - Create if doesn't exist                                │
│    - Add new features if features.json was updated          │
│ 3. Display current progress and next task                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      MAIN LOOP                              │
├─────────────────────────────────────────────────────────────┤
│ For each iteration (max 50):                                │
│                                                             │
│   1. Check if all tasks complete → Exit if done             │
│                                                             │
│   2. Get next task (highest priority incomplete task)       │
│                                                             │
│   3. Get task details from features.json                    │
│      - Type (implementation/bugfix/testing)                 │
│      - Priority                                             │
│      - Notes                                                │
│      - Test command (optional)                              │
│                                                             │
│   4. Build prompt based on task type                        │
│      - Implementation: Focus on building the feature        │
│      - Bugfix/Testing: Include test verification steps      │
│                                                             │
│   5. Run Claude CLI with the prompt                         │
│      claude --dangerously-skip-permissions -p "$prompt"     │
│                                                             │
│   6. Handle result                                          │
│      - Success: Reset failure counter                       │
│      - Failure: Increment counter, stop after 3 failures    │
│                                                             │
│   7. Wait 5 seconds before next iteration                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    EXIT CONDITIONS                          │
├─────────────────────────────────────────────────────────────┤
│ - All tasks marked [x] or [SKIP] → Success exit             │
│ - Max iterations (50) reached → Exit with warning           │
│ - 3 consecutive failures → Error exit                       │
│ - Ctrl+C interrupt → Graceful cleanup                       │
└─────────────────────────────────────────────────────────────┘
```

### Task Selection Logic

1. Parse all features from `features.json` with their priorities
2. Sort by priority (ascending - lower number = higher priority)
3. Find the first task that is still `[ ]` in `progress.txt`
4. Skip tasks marked `[x]` (complete) or `[SKIP]` (skipped)

### Prompt Generation

The script generates different prompts based on task type:

**For Implementation Tasks:**
```
Your task: [Task Name]

Context from project requirements:
- [Notes from features.json]

Instructions:
1. Implement the feature following the context above
2. Follow existing code patterns in the codebase
3. After implementation, update progress.txt: change [ ] to [x] for "[Task Name]"
4. If you cannot complete the task after multiple attempts:
   - Change [ ] to [SKIP] followed by a brief reason
5. Cleanup: Remove any debug code or temp files before marking complete
```

**For Bugfix/Testing Tasks:**
```
Your task: [Task Name]

Context from project requirements:
- [Notes from features.json]

Instructions:
1. Fix the bug / Write/fix the tests in the relevant file(s)
2. Run the unit tests for the file(s) you modified
   (or specific testCommand if provided in features.json)
3. Check the test output carefully:
   - Look for '0 failures', 'Tests passed', or similar success indicators
   - If ANY test fails, fix the code and run tests again
   - Repeat until ALL tests pass
4. ONLY when all tests pass, update progress.txt: change [ ] to [x]
5. If you cannot make tests pass after multiple attempts:
   - Change [ ] to [SKIP] followed by a brief reason
6. Cleanup: Remove any debug code or temp files

IMPORTANT:
- You MUST actually run the tests and verify the output
- Do NOT mark [x] if any test is failing
```

---

## Configuration

Configuration variables are at the top of the script:

| Variable | Default | Description |
|----------|---------|-------------|
| `MAX_ITERATIONS` | 50 | Maximum loop iterations before stopping |
| `SLEEP_BETWEEN` | 5 | Seconds to wait between iterations |
| `LOG_DIR` | `loop-logs` | Directory for log files |
| `PROGRESS_FILE` | `progress.txt` | Path to progress tracking file |
| `FEATURES_FILE` | `features.json` | Path to task definitions |

To modify, edit the script directly:

```bash
# Example: Increase max iterations to 100
MAX_ITERATIONS=100
```

---

## Task Types

### 1. Implementation (default)

Standard feature implementation. Claude:
- Implements the feature based on notes
- Follows existing code patterns
- Marks complete when done

```json
{
  "name": "User Dashboard",
  "type": "implementation",
  "notes": ["Use CSS grid", "Add loading states"]
}
```

### 2. Bugfix

Bug fixing with test verification. Claude:
- Fixes the bug
- Runs tests (auto-detected or from `testCommand`)
- Only marks complete when tests pass

```json
{
  "name": "Fix Token Expiry",
  "type": "bugfix",
  "notes": ["Token expires after 30 min"],
  "testCommand": "ng test --include=**/auth.spec.ts"
}
```

### 3. Testing

Test writing/fixing with verification. Claude:
- Writes or fixes tests
- Runs the tests
- Only marks complete when tests pass

```json
{
  "name": "API Service Tests",
  "type": "testing",
  "notes": ["Cover all endpoints", "Mock HTTP calls"]
}
```

### Test Command Behavior

| Scenario | Behavior |
|----------|----------|
| `testCommand` specified | Claude runs that exact command |
| `testCommand` not specified | Claude decides which tests to run based on modified files |

---

## Progress Tracking

### progress.txt Format

```
[ ] User Authentication
[x] Fix Login Bug
[SKIP] OAuth Integration - third-party API unavailable
[ ] Dashboard View
```

### Status Markers

| Marker | Meaning |
|--------|---------|
| `[ ]` | Pending - task not started or in progress |
| `[x]` | Complete - task finished successfully |
| `[SKIP]` | Skipped - task couldn't be completed (with reason) |

### Automatic Sync

When you add new features to `features.json`:
- Run the script again
- It automatically adds new features to `progress.txt`
- Existing progress is preserved

---

## Logging

### Log Location

```
loop-logs/ralph-loop-v2-YYYYMMDD-HHMMSS.log
```

### Log Contents

- Timestamp of script start/end
- Each iteration number and task being processed
- Task type and priority
- Full prompts sent to Claude
- Claude's complete output
- Error messages and exit codes

### Viewing Logs

```bash
# View latest log
cat loop-logs/$(ls -t loop-logs | head -1)

# Follow log in real-time (another terminal)
tail -f loop-logs/ralph-loop-v2-*.log
```

---

## Error Handling

### Interrupt Handling (Ctrl+C)

When you press Ctrl+C:
1. Script catches the signal
2. Displays current progress state
3. Shows log file location
4. Saves state (progress.txt is already saved by Claude)
5. Exits gracefully

### Consecutive Failures

- After 3 consecutive Claude failures, script stops
- Prevents infinite loops on broken configurations
- Check logs for error details

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success - all tasks complete or max iterations |
| 1 | Error - missing features.json or too many failures |
| 130 | Interrupted - user pressed Ctrl+C |

---

## For Developers

### Script Architecture

```
ralph-loop-v2.sh
├── Configuration Section (lines 11-27)
│   └── Variables for paths, limits, colors
│
├── Utility Functions
│   ├── cleanup()              - Handle Ctrl+C gracefully
│   ├── check_completion()     - Check if all tasks done
│   ├── get_progress()         - Get "X/Y" progress string
│   └── get_incomplete_tasks() - List pending tasks
│
├── Feature Parsing Functions
│   ├── get_task_from_features()   - Get feature block by name
│   ├── get_features_by_priority() - Get sorted priority|name|type
│   ├── get_task_details()         - Parse priority, type, notes, testCommand
│   ├── get_next_task()            - Find highest priority pending task
│   └── get_test_command()         - Extract testCommand if specified
│
├── Prompt Building Functions
│   ├── build_implementation_prompt() - For implementation tasks
│   └── build_verification_prompt()   - For bugfix/testing tasks
│
├── Core Functions
│   ├── run_iteration()     - Execute one Claude invocation
│   └── sync_progress_file() - Sync progress.txt with features.json
│
└── Main Execution
    ├── Pre-flight checks
    ├── Progress sync
    └── Main loop with failure tracking
```

### Key Implementation Details

**AWK Parsing:** The script uses AWK for JSON parsing (no `jq` dependency):
- `get_features_by_priority()`: Splits on `},` to separate features
- `get_task_details()`: Tracks brace depth for nested objects

**Exact Matching:** Uses `grep -Fx` for exact line matching to avoid:
- "Auth" matching "[ ] Auth Provider"
- Substring false positives

**Test Command Logic:**
- If `testCommand` is `null` or missing, returns empty string
- Empty string tells Claude to auto-detect which tests to run

### Customization Points

**Add a new task type:**
1. Add handling in `run_iteration()` function (line 415)
2. Create a new `build_*_prompt()` function
3. Update documentation

**Change prompt format:**
1. Modify `build_implementation_prompt()` or `build_verification_prompt()`
2. Prompts use heredoc-style multiline strings

**Add new feature fields:**
1. Update AWK parsing in `get_task_details()`
2. Extract new field in `run_iteration()`
3. Pass to prompt builder function

### Dependencies

The script uses only standard Unix tools:
- `bash` (shell)
- `grep`, `sed`, `awk` (text processing)
- `tee` (output duplication)
- `date`, `mktemp` (utilities)

No external dependencies like `jq`, `yq`, or Node.js are required.

---

## Troubleshooting

### "Missing: features.json"

Create `features.json` in the same directory as the script. See the [Required Files](#required-files) section for the format.

### Claude not running

1. Verify Claude CLI is installed: `claude --version`
2. Check authentication: `claude` (should start interactive mode)
3. Check logs for error messages

### Tasks not being picked up

1. Check `features.json` syntax (valid JSON)
2. Verify feature `name` matches exactly in `progress.txt`
3. Check priority values (lower = runs first)

### Progress not saving

Claude is responsible for updating `progress.txt`. Check:
1. Claude has write permissions to the file
2. Claude is following the prompt instructions
3. Check logs for Claude's output

---

## Quick Reference

```bash
# Run the loop
./ralph-loop-v2.sh

# Check current progress
cat progress.txt

# View latest log
cat loop-logs/$(ls -t loop-logs | head -1)

# Reset and start fresh
rm progress.txt
./ralph-loop-v2.sh
```
