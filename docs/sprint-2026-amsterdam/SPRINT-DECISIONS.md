# Amsterdam Sprint — Decision Log

**Dates:** 19–20 October 2026  
**Purpose:** Maintain a shared, human-approved record of architecture and scope decisions.  
**Rule:** Only the team/maintainers can accept a decision. AI suggestions are not decisions.

## Status definitions

- **Proposed:** Under discussion, not binding.
- **Accepted:** Confirmed by the responsible team/maintainer.
- **Superseded:** Replaced by a later decision.
- **Deferred:** Not being decided during this Sprint.

## Decisions

No architectural decisions are recorded as accepted in this initial pack.

### DEC-001 — Campaign to Event Instance relationship

- **Date:** 2026-10-19
- **Status:** Proposed
- **Question:** Can an Event Instance be linked to one or multiple Campaigns? What is the lookup direction and how is it exposed to admins?
- **Options:** Campaign lookup to Event Instance; junction model; another pattern after metadata review.
- **Decision:** Pending team review.
- **Rationale:** Pending.
- **Affected stories:** US-01, US-02, US-07.
- **Owner / approver:** TBD.

### DEC-002 — Registration creation automation

- **Date:** 2026-10-19
- **Status:** Proposed
- **Question:** Flow or Apex for Campaign Member → Registration creation, and what makes processing idempotent?
- **Decision:** Pending repository and data-model investigation.
- **Affected stories:** US-02, US-03.
- **Owner / approver:** TBD.

### DEC-003 — Invitation and registration statuses

- **Date:** 2026-10-19
- **Status:** Proposed
- **Question:** Can existing Registration statuses represent `Invited` and `Declined`, and which system owns Campaign Member status synchronization?
- **Decision:** Pending verification of picklists and current behavior.
- **Affected stories:** US-03, US-05, US-06, US-07.
- **Owner / approver:** TBD.

### DEC-004 — Personalized invitation links

- **Date:** 2026-10-19
- **Status:** Proposed
- **Question:** How are invitees securely associated with an existing Registration, including token expiry, revocation, replay and forwarded links?
- **Decision:** Pending security design.
- **Affected stories:** US-04, US-05, US-06.
- **Owner / approver:** TBD.

### DEC-005 — Decline experience

- **Date:** 2026-10-19
- **Status:** Proposed
- **Question:** Should decline be a dedicated public page or an option in the existing registration experience? Is a reason collected?
- **Decision:** Pending UX and guest-security review.
- **Affected stories:** US-06.
- **Owner / approver:** TBD.

### DEC-006 — Invitation email delivery

- **Date:** 2026-10-19
- **Status:** Proposed
- **Question:** What Salesforce-native email capabilities are in scope for MVP, and what integration boundary should support future marketing products?
- **Decision:** Pending feature/licensing review.
- **Affected stories:** US-04.
- **Owner / approver:** TBD.

### DEC-007 — Campaign Member handling when a matching Registration already exists

- **Date:** 2026-10-19
- **Status:** Proposed
- **Question:** When invitation processing finds an existing Registration for the same person and Event Instance, what happens to the Campaign Member being saved? Is the Campaign Member linked to the existing Registration, saved without a link, or blocked?
- **Options considered:**
  1. Always save the Campaign Member and log the duplicate; the Registration is unchanged.
  2. Always block the Campaign Member save (`addError`).
  3. Link if the existing Registration has no Campaign Member yet; otherwise block the save.
- **Decision:** Pending team review. Proposal (Peter): option 3. If the existing Registration has no associated Campaign Member, link it to this Campaign Member. If it already has one, block the new Campaign Member save with a clear error.
- **Rationale:** Registrations created through the public form are adopted into the invitation process instead of being duplicated. A person cannot silently pick up two invitation memberships for one Event Instance, for example through two Campaigns linked to the same Instance.
- **Consequences / risks:**
  - Standard Salesforce does not allow a lookup field to Campaign Member. The link would be a text field holding the 18-character Campaign Member Id (field name to be agreed).
  - "Already has a Campaign Member" must mean a Campaign Member that **still exists**. Otherwise, removing and re-adding a person (the US story example) would be blocked by the stale Id of the deleted member.
  - Blocking uses per-record `addError`. Data Loader and partial-success imports save the other members; callers that insert with all-or-none (some Flows and Apex) fail the whole batch.
  - The error message shown to admins must not reveal donor details beyond what the user can already see.
- **Affected stories:** Sprint board US-05 "Prevent duplicate Gala registrations" (context pack US-03, criterion 4); US-02 (membership policy); US-07 (status reconciliation).
- **Owner / approver:** @Peter-vdmeij
- **Evidence:** Sandbox metadata review 2026-10-19: `summit__Summit_Events_Registration__c` has no Campaign or Campaign Member link and no unique field.

## How to add a decision

Copy the template below and assign the next ID. Include links to the related GitHub issue, PR, Slack discussion, or meeting notes when available.

```markdown
### DEC-007 — [Title]

- **Date:** YYYY-MM-DD
- **Status:** Proposed / Accepted / Superseded / Deferred
- **Question:** [Decision to make]
- **Options considered:** [Alternatives]
- **Decision:** [Explicit choice]
- **Rationale:** [Why]
- **Consequences / risks:** [Tradeoffs]
- **Affected stories:** [IDs]
- **Owner / approver:** [Name or role]
- **Evidence:** [Links]
```

## Change protocol

When a decision becomes **Accepted**, update this file, link the relevant work item, and announce it to the team. Participants should refresh the file in their AI assistant. Never infer approval from a generated answer.
