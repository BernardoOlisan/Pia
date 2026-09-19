# Decision Driven Development

*The philosophy behind PIA.*

> Inspired by the talk [The Programming Ape](https://www.youtube.com/watch?v=e_6gkfTomUQ), by Coda Hale (Philly ETE).

## The problem

Working with coding agents changed my job. I'm not touching code anymore. I'm designing. And designing with agents means reading: research documents, plans, logs, reviews. Exhaustive, detailed, well written. Hours of them.

That is exactly right for agents. They are text models: the more coherent and complete the text, the better they work.

Humans are different. A human doesn't need to be filled with text. A human needs something **intuitive** to keep moving, and needs what truly requires attention separated from everything that doesn't.

## Autonomy in coding agents

### The hypothesis

> **If you have a good agentic system, you should be able to give it a goal, resources and context, and let it work for hours, even all night.**

### The current problem

The problem is the **human in the loop**. The fact that the human has to be present makes the human the bottleneck. The work waits for the human to read.

So the real question is: **how does the system keep working when the boss isn't there?**

## Intuition, not attention

The goal is a human in the loop that is intuitive, not exhausting. Attention is delegated to agents. Only what really needs a human reaches the human. The human shouldn't have to pay attention to what can be handled intuitively.

## Human in the loop is decision in the loop

> "Human, read all of the agent's work." → **"Human, review the decisions that govern the work."**

### Two readers, two documents

We still need long, technically written documents, so that any LLM can load them into its context. The full textual document is the **source of truth for coding agents**.

But that is not what the human reads. The human reads a **decision map**. We turn the textual documentation into a decision map.

Even so, the long technical documents are built with **progressive disclosure**: a short overview first, then sections that open into detail. So when a human does want to go deeper, they can read and discover it step by step instead of facing a wall of text.

The idea is that **the agent does the heavy cognitive work of understanding the system**. The human doesn't have to rebuild that model by reading 40 pages.

### This is the key

By reading the decisions, I'll know whether the coding agent understood everything.

Everything that is done and written must be a decision. It must be written down as a decision. **That is what gives coding agents autonomy in the workflow.**

## Everything is a decision

Every action is a decision, and everything written down must be a decision. That is what makes autonomy possible: if every choice that governs the work is explicit, the work can proceed without someone watching it.

## How do I know the agent understands?

**When it asks me the right questions.**

- What assumptions did you have to make?
- Which decisions would change the implementation the most?
- What do you need from me to leave the plan fully determined?

**The quality of the questions becomes a metric of the quality of the agent's understanding.**

And good questions can't come from an agent that hasn't looked. A question worth asking usually depends on something the agent found: what already exists, what it would cost, which fork is real. So understanding the intention and investigating it are not two phases. They are one conversation, where each answer sends the investigation somewhere and the investigation supplies the next question.

## Like a company

The system should behave like a company. The boss doesn't need to be present for every operation.

The boss sets:
- goals
- principles
- constraints
- the important decisions

And the organization executes. **The human in the loop is really a decision in the loop.**

So what happens when the boss isn't there? **The agents decide.** The system doesn't stop just because the human is asleep, just like a company.

When the boss comes back, they want a report of decisions. They can approve them or change them, and the system recalculates whatever depends on that decision. Decisions are independent, changeable pieces: changing decision D-017 shows exactly which parts of the system are affected.

## A decision must read on its own

The human comes back and reads a decision cold. So every decision is written for a reader who has read nothing else: a short introduction to what's being built, the question, the options, and the answer the agent chose, which the human can change.

**Simple to read and deep at the same time.**

## Not all decisions weigh the same

Some decisions are hard to undo and shape everything; others are local and cheap to change. Every decision carries a weight, and the map is ordered by it, so the human's attention goes first where it matters most.

## The work never stops

If an agent runs out of context, the work must not stop. There must be handoffs and reviewers, plus logs and automatic compaction. A reviewer challenges the research until nothing important is missing. The human doesn't step into those loops.

## What the harness is for

A harness should do the boring work, not the hard work.

**The rule: PIA owns what a session cannot do for itself.** Memory across works. Continuity after a compaction. Autonomy while you're away. The map you read when you come back. Everything else — how to investigate, how to plan, how to write the code — the model already does well. Every rule we give a model about *how to think* is a rule that will age.

**Thick competes, thin compounds.** A thick harness competes with the models: every time they get better, the process we imposed gets more in the way. A thin one compounds with them: the model improves and the harness improves for free. So the right direction for this system over time is down, not up.

**Complexity isn't detected, it's made irrelevant.** A one-line fix and a three-day migration don't need different processes, and the system shouldn't have to work out which is which — guessing would be its own complexity, and it would guess wrong. If the harness only does what a session can't do alone, it fits both: the one thing always required is the decisions, and small work simply has few of them. The conversation is what sizes the work, because by the end of it you already know whether there are three decisions or thirty.

## Decisions become memory

The human's decisions become reusable knowledge: a kind of **organizational memory**. Every new piece of work reads the decisions already made in the project to learn how the human thinks:

> "In past work you preferred online-only for this kind of architecture, so I'll assume online-only, unless there's a reason to deviate."
