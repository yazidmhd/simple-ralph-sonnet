# Product Requirements Document (PRD)

## Project Overview
**Project Name:** Example Project  
**Version:** 1.0  
**Last Updated:** 2025-01-21

## Objective
Brief description of what this project aims to accomplish.

---

## Tech Stack
- Angular 11 (Frontend)
- Spring Boot (Backend)
- MariaDB

---

## Conventions
- Use Angular reactive forms
- Follow existing service patterns
- Add JSDoc comments to public methods
- Use kebab-case for filenames
- Services end with `.service.ts`
- Components end with `.component.ts`

---

## Test Commands

### Angular (Frontend)
- Run all tests: `ng test --browsers=ChromeHeadless --watch=false`
- Run single file: `ng test --include=**/filename.spec.ts --browsers=ChromeHeadless --watch=false`
- Run with coverage: `ng test --code-coverage --browsers=ChromeHeadless --watch=false`

### Spring Boot (Backend)
- Run all tests: `./mvnw test`
- Run single test class: `./mvnw test -Dtest=TestClassName`
- Run single test method: `./mvnw test -Dtest=TestClassName#testMethodName`

---

## Instructions for Claude

When implementing features:
1. Read `features.json` for the feature list, names, type, and notes
2. Read this PRD for project context and conventions
3. Check `progress.txt` for current status
4. Implement ONE feature at a time
5. Follow the notes in `features.json` for that specific feature
6. Check the `type` field in `features.json`:
   - `implementation`: Just implement, no test verification needed
   - `bugfix`: Fix the bug AND verify unit tests pass
   - `testing`: Write/fix tests AND verify they pass
7. For tests, use the appropriate command based on file type:
   - `.ts` files → use Angular test commands
   - `.java` files → use Spring Boot test commands
8. For `bugfix` and `testing` types:
   - You MUST run the test command
   - Check output for "0 failures" or "Tests passed"
   - If ANY test fails, fix it before marking [x]
   - Do NOT assume tests pass - actually run and verify
9. Cleanup before completing:
   - Delete temp files, logs, debug files
   - Remove console.log or debug statements
   - Leave codebase clean
10. Update `progress.txt` after completing each feature
