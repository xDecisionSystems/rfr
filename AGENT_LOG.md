# AGENT_LOG.md

Shared handoff log between agents. Newest entry first.
Read this before starting any task. Append an entry after completing any task.
Archive to `history/YYYY-MM.md` when this file exceeds 200 lines (keep 10 most recent).

---

## [2026-05-27] claude-sonnet-4-6 — added agent handoff log protocol and POST /simplify-title

**Action:** Added `AGENT_LOG.md` handoff protocol to `CLAUDE.md` (§6) and `AGENTS.md` (§10/§11) so every agent reads this file before acting and prepends an entry after acting. Also added `POST /simplify-title` endpoint that uses the existing Azure OpenAI chat client to produce a 4–6 word snake_case slug from a full paper title, for use as a PDF filename component in the paper-library service.

**Files changed:**
- `CLAUDE.md` — added §6 Agent Handoff Log
- `AGENTS.md` — added §10 Agent Handoff Log, renumbered Change Workflow to §11 (added read-log and write-log steps)
- `AGENT_LOG.md` — created (this file)
- `rag-system/services/llm.py` — added `simplify_title()` function and `_SLUG_SYSTEM_PROMPT`
- `rag-system/api/main.py` — added `SimplifyTitleRequest` model and `POST /simplify-title` endpoint
- `ARCHITECTURE.md` — added `/simplify-title` to endpoint map with workflow description
- `VERSION.md` — bumped to `rag-system-v0.1.1`

**Decisions:** `simplify_title()` is placed in `llm.py` alongside `generate_answer()` because both use the same Azure OpenAI chat client — no new module or dependency needed. The endpoint sanitizes the LLM response (lowercases, strips non-word chars, collapses underscores) so a malformed model output never produces an unusable slug. Fallback return value is `"untitled"` rather than an error, keeping the paper-library upload workflow non-blocking.

**Open items:** The paper-library upload workflow currently requires three steps (POST metadata → PATCH title_slug → POST PDF). These could be streamlined by adding a `--simplify` flag to `import_searcher.py` that calls this endpoint automatically during bulk import.
