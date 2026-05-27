# AGENT_LOG.md

Shared handoff log between agents. Newest entry first.
Read this before starting any task. Append an entry after completing any task.
Archive to `history/YYYY-MM.md` when this file exceeds 200 lines (keep 10 most recent).

---

## [2026-05-27] claude-sonnet-4-6 — added root README.md for GitHub repo

**Action:** Created `README.md` at the repo root covering project overview, architecture diagram, repo layout, local dev quick start, full API reference with examples, Proxmox deployment instructions, configuration table, and links to further reading.

**Files changed:**
- `README.md` — created at repo root
- `VERSION.md` — bumped to `rag-system-v0.1.5`
- `AGENT_LOG.md` — prepended this entry

**Decisions:** Replaced the existing `rag-system/README.md` scope (which was deploy-focused) with a full project README at the root that serves both human readers and GitHub. Kept `rag-system/README.md` in place as a deployment quick-reference since it is still useful inside the LXC context.

**Open items:** None.

---

## [2026-05-27] codex-gpt5 — bumped version after architecture/log documentation fix

**Action:** Updated `VERSION.md` from `rag-system-v0.1.3` to `rag-system-v0.1.4` to reflect the completed documentation synchronization work from the previous task.

**Files changed:**
- `VERSION.md` — bumped to `rag-system-v0.1.4`
- `AGENT_LOG.md` — prepended this handoff entry

**Decisions:** Used a patch-version increment because this is a non-breaking documentation/process update with no runtime behavior change.

**Open items:** `api/static/llms.txt` still includes a placeholder GitHub URL; confirm canonical repository URL before deployment.

---

## [2026-05-27] codex-gpt5 — synced architecture docs with live API and closed log open item

**Action:** Updated `ARCHITECTURE.md` so docs match current FastAPI behavior by adding `GET /llms.txt`, updating `POST /simplify-title` to the expanded request/response contract (`title` required, `author`/`venue`/`year` optional, returns `filename`), and adding a dedicated request-flow subsection and response example for `/simplify-title`.

**Files changed:**
- `ARCHITECTURE.md` — endpoint map now reflects live routes and payloads; added `/simplify-title` request flow and response contract
- `AGENT_LOG.md` — prepended this handoff entry

**Decisions:** Kept changes documentation-only and narrowly scoped to the previously logged mismatch. No code changes were made because runtime endpoint behavior already matched the intended implementation.

**Open items:** `api/static/llms.txt` still references a placeholder GitHub URL (`github.com/xDecisionSystems/rfr`) per prior log note; confirm canonical repository URL before deployment if needed.

---

## [2026-05-27] claude-sonnet-4-6 — expanded /simplify-title, added llms.txt, repo hygiene

**Action:** Three changes bundled into one session: (1) expanded `POST /simplify-title` to accept `author`, `venue`, and `year` in addition to `title`, returning a compound filename slug of the form `<title_slug>-<last_name>-<venue_acronym>-<YYYY>`; (2) added `api/static/llms.txt` following the llmstxt.org specification and served it at `GET /llms.txt`; (3) removed all tracked `__pycache__`/`.pyc` files from the git index and added `.gitignore` at the repo root.

**Files changed:**
- `rag-system/services/llm.py` — replaced `simplify_title(title)` with `simplify_title(title, author, venue, year)` using two LLM calls (title slug + venue acronym) and `_author_slug()` helper
- `rag-system/api/main.py` — updated `SimplifyTitleRequest` with optional `author`, `venue`, `year` fields; added `GET /llms.txt` route via `FileResponse`; added `FileResponse` import and `_STATIC_DIR` path
- `rag-system/api/static/llms.txt` — created, follows llmstxt.org H1/blockquote/file-list format
- `.gitignore` — created at repo root covering `__pycache__`, `*.py[cod]`, `.venv/`, `.env`, `data/papers/*`
- `VERSION.md` — bumped to `rag-system-v0.1.3`
- `AGENTS.md` / `CLAUDE.md` — added §12/§6 git commit message format requirement

**Decisions:** Venue slug uses a dedicated second LLM call with a prompt specifically asking for standard abbreviations (e.g. `neurips`, `icra`, `ieee_tro`) rather than trying to do both in one prompt — cleaner separation and more reliable acronym output. All four new fields on the response echo back the inputs so callers don't need to track them separately.

**Open items:** `ARCHITECTURE.md` endpoint map has not been updated to reflect the new `/simplify-title` request/response shape or `/llms.txt`. Should be updated in the next docs pass. GitHub repo URL in `llms.txt` (`github.com/xDecisionSystems/rfr`) is a placeholder — confirm actual repo URL before deploying.

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
