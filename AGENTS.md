# AGENTS.md

## Purpose

This file is the source of truth for delegating work to specialized agents in REMA.

Use these rules to decide ownership, avoid duplicated logic, and keep changes safe.

---

## Project Context

Stack:
- Flutter (feature-modular)
- Riverpod (state)
- Supabase (data/auth)

Core domains:
- clientes
- proyectos
- cotizaciones
- catalogo

---

## Non-Negotiable Rules

1. Never duplicate business logic.
2. Never create a parallel flow when an existing flow already exists.
3. Reuse existing functions before creating new ones.
4. Never modify database schema unless explicitly requested.
5. UI changes must not alter domain behavior.
6. Keep mobile-first responsive behavior in every UI change.

---

## Business Invariants

1. One project can have multiple quotations.
2. One quotation belongs to exactly one universe.
3. Staff captures draft field data.
4. Admin finalizes and sends quotations.
5. Catalog is the source of truth for concept generation.

---

## Delegation Matrix

Use one owner agent per task. Add support agents only when needed.

Primary ownership:
- UI and responsive layout -> .github/agents/ui.agent.md
- Quote flow and quote item behavior -> .github/agents/quotes.agent.md
- Catalog templates, attributes and generation constraints -> .github/agents/catalog.agent.md
- Supabase queries, performance and data access -> .github/agents/supabase.agent.md
- Auth, authorization, input validation, RLS and OWASP risks -> .github/agents/security.agent.md
- Unit tests, widget tests, mocks and test coverage -> .github/agents/testing.agent.md

If a task spans multiple areas:
1. Select one owner agent.
2. Owner requests scoped inputs from support agents.
3. Owner integrates changes and keeps final consistency.

---

## Standard Workflow

1. Discovery
- Identify impacted files and current flow entry points.
- Confirm no existing function already solves the ask.

2. Plan
- Define owner agent and support agents.
- Define exact files to change and acceptance criteria.

3. Implement
- Apply minimal, targeted changes.
- Keep architecture boundaries intact.

4. Validate
- Run static analysis on changed files.
- Test the affected flow manually in mobile and desktop when UI is touched.

5. Report
- Summarize changed files, behavior impact, and residual risks.

---

## Responsive Rules (UI)

1. Avoid complex Row layouts on mobile.
2. Use Wrap or Column where content may overflow.
3. Do not use Expanded/Flexible inside unbounded height parents.
4. Always set text overflow handling for long labels.
5. Mobile under 600 should prefer stacked/card-based layout.

---

## Supabase Rules

1. Prefer a single efficient query over multiple roundtrips.
2. Prefer views for computed projections when schema already provides them.
3. Keep query shape explicit and bounded (order, limit, filters).
4. Do not change schema or RLS unless explicitly requested.

---

## Definition of Done

A delegated task is complete only if:
1. It satisfies all functional requirements.
2. It respects invariants and non-negotiable rules.
3. It passes analyzer checks for modified files.
4. It does not introduce regressions in existing flows.

---

## Handoff Contract

Every agent handoff must include:
1. What changed.
2. Which files changed.
3. What was intentionally not changed.
4. Validation executed.
5. Remaining risks or follow-up tasks.
