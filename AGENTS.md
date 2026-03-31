# AGENTS.md

## Project Overview

This is a Flutter + Supabase application for REMA Arquitectura.

The system manages:

* Clients
* Projects
* Quotations (by universe)
* Catalog of construction concepts

---

## Core Business Rules

* One project can have multiple quotations
* One quotation = one universe ONLY
* Staff creates draft data (field work)
* Admin completes and sends quotations
* Catalog drives concept generation (no manual free-text concepts)

---

## Architecture

* Frontend: Flutter (modular by feature)
* Backend: Supabase
* State management: Riverpod
* Features:

  * clientes
  * proyectos
  * cotizaciones
  * catalogo

---

## Critical Rules (DO NOT BREAK)

* Do not duplicate business logic
* Do not create new flows if one already exists
* Reuse existing functions (ex: selectConcept, hydrateFromTemplate)
* Do not modify database structure unless explicitly requested
* UI changes must not affect logic

---

## Flutter UI Rules

* Avoid using Row for complex layouts on mobile
* Use Wrap or Column for responsive layouts
* Never use Expanded inside unbounded height (scroll views)
* Always handle text overflow with ellipsis

---

## Supabase Rules

* Prefer views for computed data
* Do not run multiple queries if one can solve it
* Keep queries simple and efficient

---

## Agent Usage

Use specialized agents for tasks:

* UI → ui.agent.md
* Catalog → catalog.agent.md
* Quotes → quotes.agent.md
* Database → supabase.agent.md

Agents must follow this file as the source of truth.
