# Always-listed skills — tier 1 of docs/architecture/agent-context-architecture.md
#
# Every other marketplace skill is marked `disable-model-invocation: true` and
# leaves the session's skill listing, staying callable by /name. These are the
# ones an agent has to be able to *discover* without being told they exist,
# because they govern how it works rather than what it works on.
#
# Cost of being on this list, measured 2026-09-02 in nix-ai: ~518 tokens of
# every session, against ~10 for a manual-invoke skill. Adding a name here is a
# deliberate purchase, not a default — the default is manual-invoke.
[
  # Session lifecycle: an agent must know these exist to resume, hand off, or
  # report state without being prompted.
  "goal"
  "handoff"
  "resume"
  "session-status"

  # Discovery of everything else. Without this the manual-invoke tier is a
  # trapdoor: skills exist but nothing tells an agent how to find them.
  "skills-registry"

  # Standing behavioural rules the harness expects to apply unprompted.
  "ponytail"
  "native-first"
  "code-quality-standards"

  # Process skills that must fire before work starts, not after someone
  # remembers to ask for them.
  "brainstorming"
  "systematic-debugging"
  "using-superpowers"

  # Routing: deferred work and delegation decisions happen mid-task, when
  # nobody is going to look up a skill name.
  "track-followups"
  "delegate-to-ai"
]
