---
name: spec-reader
description: Read and summarize all spec files in the specs/ directory
tools: Read, Glob, Grep
---

## Instructions

Read all project specs and produce a structured JSON summary.

1. Use Glob to find all `specs/spec-*.md` files.
2. Read each spec file. For large spec directories (10+ files), use subagents to read files in parallel batches.
3. For each spec, extract:
   - **id**: The spec number (e.g., `spec-01`)
   - **name**: The title from the `# Spec NN: Title` heading
   - **purpose**: The first paragraph under `## Purpose`
   - **dependencies**: List of spec IDs this spec depends on, from the `## Dependencies` section (empty array if none)
   - **files**: List of file paths from the `## Files to Modify` section (empty array if none)
4. Output the result as a single JSON object:

```json
{
  "specs": [
    {
      "id": "spec-01",
      "name": "Orchestrator",
      "purpose": "The orchestrator is the master bash script...",
      "dependencies": [],
      "files": ["automaton.sh"]
    }
  ],
  "total": 37
}
```

## Constraints

- This skill is read-only. Do not modify any files.
- Output must be valid JSON. Do not include markdown formatting around the JSON output.
- If a spec lacks a `## Dependencies` or `## Files to Modify` section, use empty arrays.
- Sort specs by numeric ID in ascending order.
- Keep purpose strings to one sentence (the first sentence of the Purpose section).
