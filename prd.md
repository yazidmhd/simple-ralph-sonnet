# Product Requirements Document (PRD)

## Project Overview
**Project Name:** Example Project  
**Version:** 1.0  
**Last Updated:** 2025-01-21

## Objective
Brief description of what this project aims to accomplish.

---

## Features

### User Authentication
**Priority:** High  
**Status:** Not Started

**Description:**  
Implement user login and logout functionality.

**Requirements:**
- Login form with username and password fields
- Form validation
- Session management
- Logout button that clears session

**Acceptance Criteria:**
- User can log in with valid credentials
- Invalid credentials show error message
- User can log out and session is cleared

**Files to modify:**
- `src/auth/login.component.ts`
- `src/auth/auth.service.ts`

---

### Dashboard View
**Priority:** High  
**Status:** Not Started

**Description:**  
Create the main dashboard with summary widgets.

**Requirements:**
- Summary cards showing key metrics
- Responsive grid layout
- Loading states for async data

**Acceptance Criteria:**
- Dashboard displays 4 summary cards
- Layout adjusts for mobile/desktop
- Shows loading spinner while fetching data

**Files to modify:**
- `src/dashboard/dashboard.component.ts`
- `src/dashboard/dashboard.component.html`
- `src/dashboard/dashboard.component.scss`

---

### API Integration
**Priority:** Medium  
**Status:** Not Started

**Description:**  
Connect frontend to backend REST API.

**Requirements:**
- HTTP service for API calls
- Error handling
- Request/response interceptors

**Acceptance Criteria:**
- Service can make GET/POST/PUT/DELETE requests
- Errors are caught and logged
- Auth token is attached to requests

**Files to modify:**
- `src/services/api.service.ts`
- `src/interceptors/auth.interceptor.ts`

---

## Technical Notes

**Tech Stack:**
- Angular 11
- Spring Boot (backend)
- MariaDB

**Conventions:**
- Use Angular reactive forms
- Follow existing service patterns
- Add JSDoc comments to public methods

---

## Instructions for Claude

When implementing features:
1. Read this PRD and understand the full context
2. Read `features.json` for feature-specific notes and guidelines
3. Check `progress.txt` for current status
4. Implement ONE feature at a time
5. Follow the notes in `features.json` for that specific feature
6. Update `progress.txt` after completing each feature
