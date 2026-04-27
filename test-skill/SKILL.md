---
name: test-skill
description: Minimal smoke-test skill for validating that custom skills are discovered and invoked correctly. Use when checking skill installation, explicit `$test-skill` invocation, prompt injection behavior, or simple end-to-end skill execution in a workspace.
---

# Test Skill

Use this skill to confirm that Codex loaded a custom skill and is following its instructions.

## Workflow

1. State that `$test-skill` is active.
2. Summarize the user's request in one sentence.
3. Complete the request normally if it is simple and safe.
4. If the request is only a smoke test, return a short confirmation that includes `TEST_SKILL_ACTIVE`.

## Response Rules

- Keep the response concise.
- Include the literal string `TEST_SKILL_ACTIVE` exactly once when the user is explicitly testing skill loading.
- Do not claim extra capabilities.
- If the request depends on unavailable files, tools, or permissions, say so directly.

## Example Triggers

- `Use $test-skill to verify that custom skills work in this workspace.`
- `Run a smoke test for skill invocation.`
- `Check whether my test skill is being loaded.`
