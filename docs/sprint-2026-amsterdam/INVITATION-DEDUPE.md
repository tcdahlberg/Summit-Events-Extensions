# Invitation deduplication — how to call it

**Story:** Sprint board US-05 "Prevent duplicate Gala registrations" (context pack US-03, criterion 4)
**Code:** `InvitationRegistrationDedupe` (branch `feature/us05-registration-dedupe`, deployed to the SummitEvents sandbox)
**For:** the Campaign Member → Registration batch job (US-03)

The service guarantees **one Registration per person per Event Instance**. The person is the Contact, or the Lead when there is no Contact. The guarantee comes from the unique External ID field `Invitation_Key__c` on `summit__Summit_Events_Registration__c` (`<EventInstanceId>:<ContactId or LeadId>`), so it holds even when runs overlap or are retried.

Each invitation Registration also records the Campaign Member that invited the person in `Campaign_Member_Id__c` (Text 18, External ID, not unique: a Campaign can be linked to several Event Instances). Campaign Member cannot be a lookup target, so this is a text field. Linking is done under a row lock, so two runs cannot link the same Registration to different members.

## Calls per `execute()` chunk, in order

1. **`new InvitationRegistrationDedupe.Request(eventInstanceId, contactId, leadId, campaignMemberId)`**, once per Campaign Member.
   Only builds the input; nothing is queried or saved. Pass both `ContactId` and `LeadId` when the member has both (after Lead conversion): the Contact wins, and the Lead is used to find older Registrations. The Campaign Member Id is required.

2. **`InvitationRegistrationDedupe.resolve(requests)`**, once per chunk.
   Finds existing Registrations for all requests in one query and applies the DEC-007 link rule (Peter's proposal, option 3). Only `Invitation_Key__c` and `Campaign_Member_Id__c` are ever written; Status, answers and other fields are never changed. Returns `Map<CampaignMemberId, Result>` with one result per member:

   | Outcome | Meaning | What the job does |
   | --- | --- | --- |
   | `LINKED` | Existing Registration had no Campaign Member, or its member was removed; it is now linked to this member | Nothing (counts as invited) |
   | `EXISTING_FOUND` | Registration is already linked to this same member (re-run) | Nothing |
   | `LINKED_TO_OTHER_MEMBER` | Registration is linked to another Campaign Member that still exists (e.g. second Campaign) | Block this member (`addError`) |
   | `NEW_REGISTRATION_NEEDED` | No Registration yet | Build one (step 3) |
   | `DUPLICATE_IN_REQUEST` | Same person through another member in this chunk | Skip; next run returns `LINKED_TO_OTHER_MEMBER` |
   | `SKIPPED_NO_PERSON` | No Contact or Lead | Log |
   | `FAILED` | Linking failed, see `result.message` | Log |

3. **`InvitationRegistrationDedupe.insertRegistrations(Map<CampaignMemberId, Registration>)`**, once per chunk, with only the `NEW_REGISTRATION_NEEDED` members.
   Sets the key and the Campaign Member link, and inserts with partial success, so one bad row does not stop the rest. If another run inserted the same person a moment earlier, the existing Registration goes through the same link rule as step 2. Returns `Map<CampaignMemberId, Result>`:

   | Outcome | Meaning | What the job does |
   | --- | --- | --- |
   | `CREATED` | Inserted and linked | Done |
   | `LINKED` / `EXISTING_FOUND` / `LINKED_TO_OTHER_MEMBER` | Another run got there first; same meaning as step 2 | Same as step 2 |
   | `FAILED` | Other error, see `result.message` | Log |

Do not call these yourself: `findExisting` and `adoptExisting` are the two halves of `resolve` (`findExisting` alone is fine for a read-only preview), and `buildKey` is used internally.

## Rules for the batch job

- **Set `summit__Event_Instance__c`, `summit__Event__c`, and `summit__Contact__c` or `summit__Lead__c`** on every new Registration. Without the person, SEA's trigger runs contact matching record by record, which is slow and expensive at 200 per chunk. The person is also what the key is built from.
- **Don't throw in `execute()`.** An exception rolls back the whole chunk. Duplicates come back as outcomes, not exceptions. `InvitationProcessingException` is only thrown for programming errors: a request without an Event Instance, or a missing or repeated Campaign Member Id.
- **Choose the Registration status carefully (DEC-003).** SEA sends an email right after insert when `summit__Registrant_Email__c` is filled and the status matches one of the event's email templates. The sandbox sample templates fire on "Registered". The sandbox is a Full copy with real-looking Contacts, so use synthetic Contacts for tests.
- **Re-runs and parallel jobs are safe.** A person handled in an earlier chunk or run returns `EXISTING_FOUND`.
- **Use `Database.Stateful`** if you want outcome totals in `finish()`.

## Permissions and dependencies

- The service runs `without sharing` and in system mode, so it sees every Registration regardless of the running user. Call it only from trusted automation, never from guest-facing code.
- The running user needs SEA's **Summit Events Admin** permission set. SEA's own Registration trigger throws a NullPointerException for users who cannot read `Summit_Events__c` (an SEA bug, to be reported upstream).
- Bhuvana's `Summit_Events_Invite_Manager` permission set gives read-only access to `Invitation_Key__c` and `Campaign_Member_Id__c`. The service does not need it. The permission set is maintained directly in the sandbox; the repo copy was retrieved from the sandbox on 2026-10-19. It also grants access to `Campaign.Summit_Events_Instance__c` and `Contact.Donor_Type__c`, which are not in this repo yet, so a deploy to a fresh org needs those fields as well.
- Campaign → Event Instance mapping: Jelena's unmanaged `Campaign__c` lookup on Event Instance (DEC-001, not yet in this repo).
- Campaign Member link rule: DEC-007, implemented as Peter's proposal (option 3) while the decision is still Proposed.

## Tests

`InvitationRegistrationDedupeTest`: 16 tests, including:
- reprocessing 600 invitees
- linking a public-form Registration without changing its data
- re-linking after a member was removed and re-added
- blocking a member of a second Campaign while the first member exists
- blank-person handling
- an Event Manager without access to the invitation fields

The test setup creates Campaigns as a test user with the Marketing User setting, so it does not depend on the test runner having it. Passed in the SummitEvents sandbox on 2026-10-19 (run `707di0000LD7wDi`).
