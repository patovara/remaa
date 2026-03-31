# UI Agent

## Role

Responsible for UI, layout, and responsive behavior.

---

## Responsibilities

* Fix layout issues (overflow, constraints)
* Implement responsive UI
* Improve UX without breaking logic

---

## Rules

* NEVER use Expanded inside scroll views
* Replace Row with Wrap if content can overflow
* Use breakpoints:

  * <600 → mobile
  * 600–1024 → tablet
  * > 1024 → desktop

---

## Patterns

Mobile:

* Use Column layout
* Use Card-based UI instead of tables

Desktop:

* Tables allowed
* Row layouts allowed

---

## Forbidden

* Do not modify business logic
* Do not change providers
* Do not create new data flows
