---
name: translate-long-markdown
description: Use when translating large or long-running Markdown documents with Azure Co-op Translator, especially when setup is missing, file progress remains at 0%, durable logs are needed, or metadata, URLs, code, and paths must be protected.
---

# Translate Long Markdown

## Overview

Use an isolated `.co_op_translator` root with native chunking. Back up the source, retain DEBUG logs, and verify structure.

## Install

Reuse `.venv/bin/translate`, or run:

```bash
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python co-op-translator
.venv/bin/python -c 'from importlib.metadata import version; print(version("co-op-translator"))'
.venv/bin/translate --help
```

Configure provider credentials in `.env` or the environment. OpenAI requires `OPENAI_API_KEY` and `OPENAI_CHAT_MODEL_ID`; Azure OpenAI requires key, endpoint, model, deployment, and API version. Custom `OPENAI_BASE_URL` values must include required `/v1`. Never print credentials.

## Stage Safely

1. Create a verified byte-identical backup at an unused path.
2. Create `.co_op_translator` without deleting prior artifacts.
3. Copy only the target Markdown into that directory. Keep provider credentials available to the process; if `.env` is copied into the isolated root, remove that copy after diagnosis.
4. Keep the source and backup read-only until validation completes.

## Translate

Run from the project root, replacing the filename and BCP 47 language code as needed:

```bash
(
set -e -o pipefail
export CO_OP_TRANSLATOR_OUTPUT_STYLE=plain
export CO_OP_TRANSLATOR_NO_PROGRESS=1
test ! -e document.md.pre-translation.bak || { echo "Backup exists" >&2; exit 1; }
cp -p document.md document.md.pre-translation.bak
shasum -a 256 document.md document.md.pre-translation.bak
cmp -s document.md document.md.pre-translation.bak
mkdir -p .co_op_translator
test ! -e .co_op_translator/document.md || { echo "Staged file exists" >&2; exit 1; }
cp -p document.md .co_op_translator/document.md
.venv/bin/translate -l "zh-CN" -md --no-disclaimer -y -d -s \
  -r .co_op_translator 2>&1 | tee -a .co_op_translator/translate.log
)
```

Do not externally split the document or claim Markdown concurrency. Co-op Translator splits Markdown into approximately 2,600-token chunks and sends them sequentially.

## Monitor

File progress can remain at `0%` until completion. Do not abort for that display or a quiet console. Inspect chunk progress:

```bash
rg 'Running translation prompt|Translation completed' \
  .co_op_translator/logs/latest.log | tail -n 20
```

Diagnose only when chunk numbers stop advancing. Preserve the isolated root and logs while investigating.

## Verify

Require all of these before publishing:

- CLI exit status `0`.
- Nonempty `.co_op_translator/translations/<language>/document.md`.
- Valid `.co_op_translator/translations/<language>/.co-op-translator.json` containing the source entry and hash.
- Original and backup still match.
- Balanced Markdown fences and target-language text.
- Protected metadata, URLs, code, and paths satisfy the user's exact requirements.

Co-op Translator may rewrite links or surrounding metadata. For selective translation, treat output as intermediate and restore protected nodes from the backup using structured Markdown parsing before replacing the source.

## Common Mistakes

| Mistake | Correction |
| --- | --- |
| Guessing `-p` or `--version` | Read `translate --help`; use import metadata for version. |
| Killing a run at file-level `0%` | Check `Running translation prompt N/total` first. |
| Translating the whole project | Isolate one target under `.co_op_translator`. |
| Declaring success from progress alone | Require exit, output, metadata, and preservation checks. |
