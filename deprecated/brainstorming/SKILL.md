---
name: brainstorming
description: "Use before any implementation task — building, adding, modifying, designing, planning, or speccing out features, components, or behavior. Explores user intent, requirements, and design before implementation."
---

# Brainstorming Ideas Into Designs and Specs

## Process

**Understanding the idea:**

Before asking any question, ask yourself: *What decision does this answer unlock? What assumption am I testing?* If you can't name one, skip the question. Always state the reason when you ask.

- Check the current project state first (files, docs, recent commits) — don't ask what already exists
- One question per message; prefer multiple choice, but explain what range of answers would change your approach

**Exploring approaches:**

Before proposing options, ask yourself: *Is there one clearly dominant choice?* If yes, state it with your confidence rather than manufacturing false balance.

- For each approach, make trade-offs explicit: what you gain, what you give up, and under what conditions it wins or loses
- Lead with your recommendation and explain what about *this specific situation* makes it the right call — not generic pros/cons

**Presenting the design:**

Before presenting, ask yourself: *What's the single most likely thing I got wrong?* Name it explicitly and ask about it first.

- Scale sections to complexity: a few sentences if straightforward, up to 200-300 words if nuanced
- Check in after each section before moving on
- Cover what's relevant: architecture, components, data flow — add error handling and testing only if non-trivial

## When to Stop Asking

Stop and present the design when you have:
- What problem this solves and who is affected
- The smallest thing that would count as working
- At least one constraint that would have changed your default design

Keep asking when:
- The stated want and actual problem don't match (probe for the real constraint)
- You're about to add scope the user didn't ask for (challenge it first)
- "Just make it work" — always get one concrete success scenario before designing

If remaining questions are about implementation details, stop — make a decision and surface it explicitly in the design.

## NEVER

- NEVER ask a question or make a design decision without explaining the reasoning behind it — the user needs to understand trade-offs to make good decisions, not just respond to prompts. Bad: "Should we use REST or GraphQL?" Good: "Should we use REST or GraphQL? — your answer determines whether I design around flexible querying or simple endpoint contracts."
- NEVER ask about implementation approach before understanding the problem — users anchor to the first solution they hear. Bad: jumping to "here are 3 database options" before knowing the access patterns.
- NEVER present a design without identifying the single most likely thing you got wrong and asking about that explicitly
- NEVER treat "I want X" as the requirement — probe for the actual constraint driving it. Bad: designing a cache because "it's slow"; good: discovering the real bottleneck is a single expensive query that runs on every page load.
- NEVER ask multiple questions in one message even if they seem related — pick the most important one
- NEVER skip asking what success looks like on open-ended features — it surfaces unstated acceptance criteria that would otherwise invalidate the design
- NEVER manufacture 2-3 options when one is clearly dominant — false balance signals indecision and wastes time
