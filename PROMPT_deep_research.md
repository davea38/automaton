<!-- STATIC CONTENT — do not inject per-iteration data above this line -->

# Deep Research Mode

You are performing a deep comparative research session. Your goal is to produce a
structured analysis document that helps developers make informed architectural decisions.

## Task

Research the topic provided in `<dynamic_context>` below. Follow this process:

### 1. Understand the Domain

Read the research topic carefully. If a project PRD or specs exist (context will say so),
read them to understand the project's constraints, scale, and technology stack. This
ensures your recommendation fits the specific project context, not just the general case.

In standalone mode (no PRD/specs), focus purely on the topic without project context.

### 2. Research 3-5 Approaches

Identify 3-5 distinct approaches, architectures, libraries, or solutions for the topic.
Choose approaches that are meaningfully different from each other — not variations on a
theme. Use web search to gather current information: check documentation, GitHub stars,
recent releases, known issues, and real-world adoption.

For each approach, gather:
- **Overview**: What is it, how does it work?
- **Pros**: What does it do well?
- **Cons**: What are its limitations, pain points, or failure modes?
- **Complexity**: low / medium / high (to adopt, not to understand)
- **Ecosystem**: mature / growing / emerging
- **Learning curve**: What does a developer need to know to use it effectively?
- **Used by**: Notable projects, companies, or domains that use it
- **Project fit**: If project context exists, how well does this approach fit?

### 3. Produce a Comparative Matrix

After analyzing all approaches, produce a comparison table:

| Criterion | Approach 1 | Approach 2 | Approach 3 | ... |
|-----------|-----------|-----------|-----------|-----|
| Complexity | | | | |
| Performance | | | | |
| Ecosystem | | | | |
| Learning Curve | | | | |
| Project Fit | | | | |

### 4. Make a Recommendation

Choose ONE approach and explain WHY. Be specific:
- What trade-offs are you accepting?
- What would make a different approach the right choice?
- If migrating from an existing approach, what does adoption look like?

### 5. Output Format

Structure your entire response as a markdown document following this format exactly:

```
# Deep Research: {topic}

**Generated:** {timestamp}
**Project context:** {PRD title or "standalone research"}
**Budget used:** {your estimate of tokens consumed}

## Executive Summary
[2-3 sentences: what you found and what you recommend]

## Approaches Analyzed

### 1. {Approach Name}
**Overview:** [Description]
**Pros:**
- ...
**Cons:**
- ...
**Complexity:** {low|medium|high}
**Ecosystem:** {mature|growing|emerging}
**Used by:** [Examples]

[Repeat for each approach]

## Comparative Matrix

[Table as specified above]

## Recommendation

**Recommended:** {Approach Name}

**Rationale:** [Why this approach, what trade-offs are accepted]

**Migration path:** [If applicable — how to adopt if project already has related code]
```

## Important Notes

- If budget is running low, stop analyzing new approaches and write the recommendation
  with the information you have. Partial results are better than no results.
- Keep the document self-contained — someone reading it cold should understand
  the context and recommendation without external references.
- Prefer specific, concrete examples over abstract descriptions.

<dynamic_context>
</dynamic_context>
