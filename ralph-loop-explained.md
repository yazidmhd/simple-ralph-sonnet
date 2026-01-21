# Ralph Loop: Why We Loop & Opus vs Sonnet

## Why We Use External Loops

Even with powerful AI models, we use external bash loops for several reasons:

### 1. Context Window Limit

**What it is:**  
Every model has a maximum "memory" per session (200k tokens for both Opus and Sonnet). This includes everything:
- System prompt
- Your prompt
- Files read
- Code generated
- Conversation history within that session

Once filled, bad things happen.

**What happens when context limit is hit:**

| Scenario | What Happens |
|----------|--------------|
| **Truncation** | Model silently drops earlier content. It "forgets" the beginning of the session - including your instructions, earlier files it read, or code it wrote. |
| **Degraded output** | Model starts producing garbage, incomplete code, or repetitive responses. Quality drops sharply. |
| **Hallucination** | Model "remembers" things incorrectly. Might reference variables that don't exist or mix up file names. |
| **Task confusion** | Model forgets what it was doing. Might redo work, skip steps, or work on wrong feature. |
| **API error** | In extreme cases, API returns an error and refuses to process the request. |

**Example of context filling up (without external loop):**

```
Start: 0/200k tokens used

Read features.json     →  5k tokens
Read prd.md            → 10k tokens
Read progress.txt      → 12k tokens
Read file1.ts          → 20k tokens
Read file2.ts          → 30k tokens
Write code             → 50k tokens
Read more files        → 80k tokens
Write more code        → 120k tokens
Conversation grows     → 160k tokens
...
Read another file      → 195k tokens
Write code             → 210k tokens ← LIMIT HIT

Model: *starts forgetting early instructions*
Model: *produces broken code*
Model: *forgets which feature it was implementing*
```

**How our script handles it:**  
Each iteration starts with a **fresh context**. The model only loads what it needs for ONE feature:
- `features.json`
- `prd.md`
- `progress.txt`
- Relevant code files

After the iteration ends, context resets. No buildup.

```
Iteration 1: [prompt + files] → 30k tokens → done → RESET
Iteration 2: [prompt + files] → 35k tokens → done → RESET
Iteration 3: [prompt + files] → 28k tokens → done → RESET
```

Each iteration starts clean. Context never accumulates across iterations.

---

### 2. Timeout Safety

**What it is:**  
API calls can timeout due to:
- Network latency (especially corporate proxies)
- Long-running tasks
- API rate limits

**How our script handles it:**  
- Each iteration has a timeout cap (`TIMEOUT_SECONDS=300`)
- If timeout occurs, script catches it and retries
- Work from previous iterations is already saved

---

### 3. Checkpoint Recovery

**What it is:**  
If the connection drops, power goes out, or you need to stop - you don't want to lose all progress.

**How our script handles it:**  
- `progress.txt` is updated after EACH completed feature
- If script stops, progress is saved
- Re-run script → continues from where it left off

---

### 4. Retry Logic

**What it is:**  
Models sometimes fail, stall, or produce errors. Without retries, the whole process dies.

**How our script handles it:**  
- Tracks consecutive failures
- Retries automatically on failure
- Only stops after 3 consecutive failures

---

### 5. Model Behavior Control (Sonnet-specific)

**What it is:**  
Sonnet tends to:
- Do one thing and stop
- Exit early thinking it's "done"
- Get confused with multi-task instructions

**How our script handles it:**  
- External loop forces continuation
- Explicit "do ONE task, then STOP" instructions
- Already-implemented detection prevents re-work

---

## How We Implemented It

### The Loop Structure

```bash
while [[ $iteration -le $MAX_ITERATIONS ]]; do
    
    # Check if all features complete
    if [[ "$(check_completion)" == "true" ]]; then
        echo "=== ALL TASKS COMPLETE ==="
        exit 0
    fi
    
    # Run ONE iteration (one feature)
    run_iteration $iteration
    
    # Wait between iterations
    sleep $SLEEP_BETWEEN
    
    # Next
    ((iteration++))
    
done
```

### The Prompt (for Sonnet)

```
1. Read files: features.json, prd.md, progress.txt
2. Find FIRST task marked [ ] (incomplete)
3. Check if ALREADY IMPLEMENTED - if yes, mark [x] and skip
4. If not implemented - implement it
5. Update progress.txt
6. STOP after ONE task
```

### Progress Tracking

```
[ ] Feature 1    →    [x] Feature 1
[ ] Feature 2         [ ] Feature 2
[ ] Feature 3         [ ] Feature 3
```

Script checks for remaining `[ ]` items to know when to stop.

---

## Opus vs Sonnet Comparison

### Overview

| Aspect | Opus | Sonnet |
|--------|------|--------|
| Intelligence | Higher | Lower |
| Speed | Slower | Faster |
| Cost | ~5x more expensive | Cheaper |
| Self-looping | Yes, can loop internally | No, stops after one task |
| Context tracking | Better | Gets confused |
| Instruction following | Understands nuance | Needs explicit instructions |

---

### Loop Behavior

**Opus:**
```
┌─────────────────────────────────────────────┐
│ Single Claude invocation                    │
│                                             │
│ "Do all features"                           │
│     │                                       │
│     ├──► Does Feature 1                     │
│     ├──► Does Feature 2                     │
│     ├──► Does Feature 3                     │
│     └──► Done (loops internally)            │
└─────────────────────────────────────────────┘
```

**Sonnet:**
```
┌──────────┐     ┌──────────┐     ┌──────────┐
│ Call 1   │────►│ Call 2   │────►│ Call 3   │
│ Do 1     │     │ Do 1     │     │ Do 1     │
│ Stop     │     │ Stop     │     │ Stop     │
└──────────┘     └──────────┘     └──────────┘
     │                │                │
  Feature 1       Feature 2       Feature 3
```

---

### Why Opus Still Uses a Loop

Even though Opus CAN self-loop, we still wrap it in a bash loop for:

1. **Context window limit** - Very long sessions fill up memory
2. **Timeout safety** - Long tasks might hit API limits  
3. **Checkpoint recovery** - Save progress in case of failure

**But the loop behaves differently:**

| Aspect | Sonnet Loop | Opus Loop |
|--------|-------------|-----------|
| Purpose | Force continuation | Safety net |
| Tasks per iteration | ONE only | Multiple until natural stop |
| Prompt style | "Do ONE, STOP" | "Keep going until done" |
| Why re-enters loop | Sonnet stopped (by design) | Hit context/timeout limit |

---

### When to Use Which

**Use Sonnet when:**
- Budget is limited
- Features are straightforward
- You don't mind the external loop overhead
- Speed matters (faster per response)

**Use Opus when:**
- Features are complex
- Need higher code quality
- Want less babysitting
- Multi-step reasoning required
- Budget allows

**Use Opus with one-task-per-iteration when:**
- Honestly? Rarely. You're paying premium without using Opus's main strength (self-looping, complex reasoning).

---

## Summary Table

| Reason for Loop | Sonnet | Opus |
|-----------------|--------|------|
| Context window limit | ✓ Fresh each iteration | ✓ Safety checkpoint |
| Timeout safety | ✓ Catches and retries | ✓ Catches and retries |
| Checkpoint recovery | ✓ progress.txt saves state | ✓ progress.txt saves state |
| Retry logic | ✓ Auto-retry on failure | ✓ Auto-retry on failure |
| Force continuation | ✓ **REQUIRED** (Sonnet stops) | ✗ Not needed (Opus self-loops) |

---

## TL;DR

- **External loops** protect against context limits, timeouts, and failures
- **Sonnet** needs loops because it won't continue on its own
- **Opus** can self-loop but we still wrap it for safety
- **Our script** does one feature per iteration, perfect for Sonnet
- **Progress is saved** after each feature, so you never lose work
