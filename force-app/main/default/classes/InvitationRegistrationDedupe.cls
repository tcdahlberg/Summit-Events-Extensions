/**
 * Deduplication framework for invitation-stage Summit Events Registrations.
 *
 * Identity rule: one Registration per person per Event Instance. The person is the Contact, or the
 * Lead when there is no Contact. Requests and Registrations without a Contact or Lead are never
 * matched, so blank values cannot collide.
 *
 * The guarantee comes from the unique External Id field Invitation_Key__c; the queries in this class
 * only make the common path cheap and let existing (e.g. public form) Registrations be adopted.
 *
 * Intended use by the Campaign Member -> Registration automation (both calls keyed by Campaign Member Id):
 *   1. resolve(requests)                          find + adopt existing Registrations
 *   2. build Registrations for NEW_REGISTRATION_NEEDED results
 *   3. insertRegistrations(newRegistrationsByCmId) race-safe insert; duplicates are adopted as in step 1
 *
 * Campaign Member link (DEC-007, proposal option 3): an existing Registration is linked to the Campaign Member
 * through Campaign_Member_Id__c when it has no link yet or its linked Campaign Member no longer exists (LINKED).
 * If it is linked to this same Campaign Member the outcome is EXISTING_FOUND (re-run). If it is linked to another
 * Campaign Member that still exists the outcome is LINKED_TO_OTHER_MEMBER and the caller blocks the new member.
 *
 * without sharing + SYSTEM_MODE: duplicate detection must see every Registration of the Event Instance and
 * the key field regardless of the running user's sharing and field access (at API 68.0 queries otherwise fail
 * with "Variable does not exist: tmpVar1" for users without access to Invitation_Key__c). Without this, records
 * not shared with the running user would be missed, or a restricted user re-running the automation would create
 * duplicates. Call this from trusted automation only, never from guest-facing code.
 */
public without sharing class InvitationRegistrationDedupe {
    public enum Outcome {
        CREATED,
        EXISTING_FOUND,
        LINKED,
        LINKED_TO_OTHER_MEMBER,
        NEW_REGISTRATION_NEEDED,
        DUPLICATE_IN_REQUEST,
        SKIPPED_NO_PERSON,
        FAILED
    }

    private static final String KEY_SEPARATOR = ':';
    // Matches are still reported for these statuses, but an active Registration is preferred over them
    private static final Set<String> INACTIVE_STATUSES = new Set<String>{ 'Cancelled', 'No-Show' };

    public class Request {
        public Id eventInstanceId;
        public Id contactId;
        public Id leadId;
        public Id campaignMemberId;

        public Request(Id eventInstanceId, Id contactId, Id leadId, Id campaignMemberId) {
            this.eventInstanceId = eventInstanceId;
            this.contactId = contactId;
            this.leadId = leadId;
            this.campaignMemberId = campaignMemberId;
        }
    }

    public class Result {
        public Request request;
        public String invitationKey;
        public Outcome outcome;
        public summit__Summit_Events_Registration__c registration;
        public String message;

        private Result(Request request) {
            this.request = request;
            this.invitationKey = buildKey(request.eventInstanceId, request.contactId, request.leadId);
        }
    }

    /**
     * Returns '<EventInstanceId>:<ContactId or LeadId>' using 18-character Ids (safe for the
     * case-insensitive unique index), or null when there is no Event Instance or no person.
     */
    public static String buildKey(Id eventInstanceId, Id contactId, Id leadId) {
        Id personId = contactId != null ? contactId : leadId;
        if (eventInstanceId == null || personId == null) {
            return null;
        }
        return String.valueOf(eventInstanceId) + KEY_SEPARATOR + String.valueOf(personId);
    }

    /**
     * Finds existing Registrations and stamps the invitation key on adopted ones that do not have it yet.
     * Every request must carry a unique Campaign Member Id; results are keyed by it.
     */
    public static Map<Id, Result> resolve(List<Request> requests) {
        Set<Id> campaignMemberIds = new Set<Id>();
        for (Request req : requests) {
            if (req == null || req.campaignMemberId == null || !campaignMemberIds.add(req.campaignMemberId)) {
                throw new InvitationProcessingException('Every invitation request needs a unique Campaign Member Id.');
            }
        }
        List<Result> results = findExisting(requests);
        adoptExisting(results);
        return keyByCampaignMember(results);
    }

    /**
     * Read-only lookup. Results are returned in request order with outcome EXISTING_FOUND,
     * NEW_REGISTRATION_NEEDED, DUPLICATE_IN_REQUEST or SKIPPED_NO_PERSON.
     */
    public static List<Result> findExisting(List<Request> requests) {
        List<Result> results = new List<Result>();
        Set<Id> instanceIds = new Set<Id>();
        Set<Id> contactIds = new Set<Id>();
        Set<Id> leadIds = new Set<Id>();
        Set<String> keys = new Set<String>();

        for (Request req : requests) {
            if (req == null || req.eventInstanceId == null) {
                throw new InvitationProcessingException('Every invitation request needs an Event Instance Id.');
            }
            Result res = new Result(req);
            results.add(res);
            if (res.invitationKey == null) {
                res.outcome = Outcome.SKIPPED_NO_PERSON;
                continue;
            }
            // Only non-null Ids go into the sets: "IN :ids" with a null would match blank lookups
            instanceIds.add(req.eventInstanceId);
            keys.add(res.invitationKey);
            if (req.contactId != null) {
                contactIds.add(req.contactId);
            }
            if (req.leadId != null) {
                leadIds.add(req.leadId);
            }
        }

        Map<String, List<summit__Summit_Events_Registration__c>> candidatesByPerson = queryCandidates(instanceIds, contactIds, leadIds, keys);

        Set<String> seenKeys = new Set<String>();
        for (Result res : results) {
            if (res.outcome == Outcome.SKIPPED_NO_PERSON) {
                continue;
            }
            if (!seenKeys.add(res.invitationKey)) {
                res.outcome = Outcome.DUPLICATE_IN_REQUEST;
                continue;
            }
            List<summit__Summit_Events_Registration__c> candidates = new List<summit__Summit_Events_Registration__c>();
            for (Id personId : new List<Id>{ res.request.contactId, res.request.leadId }) {
                String personKey = buildKey(res.request.eventInstanceId, personId, null);
                if (personKey != null && candidatesByPerson.containsKey(personKey)) {
                    candidates.addAll(candidatesByPerson.get(personKey));
                }
            }
            res.registration = pickBest(candidates, res.invitationKey);
            res.outcome = res.registration != null ? Outcome.EXISTING_FOUND : Outcome.NEW_REGISTRATION_NEEDED;
        }
        return results;
    }

    /**
     * For EXISTING_FOUND results: stamps a blank invitation key and applies the Campaign Member link rule
     * (LINKED / EXISTING_FOUND / LINKED_TO_OTHER_MEMBER, see class comment). Only Invitation_Key__c and
     * Campaign_Member_Id__c are ever written; status and other fields are untouched. Failures set FAILED.
     */
    public static void adoptExisting(List<Result> results) {
        Set<Id> registrationIds = new Set<Id>();
        for (Result res : results) {
            if (res.outcome == Outcome.EXISTING_FOUND) {
                registrationIds.add(res.registration.Id);
            }
        }
        if (registrationIds.isEmpty()) {
            return;
        }

        // Re-read with a row lock so two concurrent runs cannot link the same Registration to different members
        Map<Id, summit__Summit_Events_Registration__c> current = new Map<Id, summit__Summit_Events_Registration__c>(
            [
                SELECT Id, Invitation_Key__c, Campaign_Member_Id__c
                FROM summit__Summit_Events_Registration__c
                WHERE Id IN :registrationIds
                WITH SYSTEM_MODE
                FOR UPDATE
            ]
        );
        Set<String> liveCampaignMemberIds = findLiveCampaignMemberIds(current.values());

        Set<Id> changedIds = new Set<Id>();
        Map<Id, List<Result>> resultsByRegistrationId = new Map<Id, List<Result>>();
        for (Result res : results) {
            if (res.outcome != Outcome.EXISTING_FOUND) {
                continue;
            }
            summit__Summit_Events_Registration__c reg = current.get(res.registration.Id);
            if (reg == null) {
                res.outcome = Outcome.FAILED;
                res.message = 'The matching Registration was deleted during processing: ' + res.registration.Id;
                continue;
            }
            if (String.isBlank(reg.Invitation_Key__c) && res.invitationKey != null) {
                reg.Invitation_Key__c = res.invitationKey;
                changedIds.add(reg.Id);
            }

            String campaignMemberId = res.request.campaignMemberId == null ? null : String.valueOf(res.request.campaignMemberId);
            if (campaignMemberId == null || reg.Campaign_Member_Id__c == campaignMemberId) {
                // Read-only callers without a Campaign Member, or a re-run for the same member
                res.outcome = Outcome.EXISTING_FOUND;
            } else if (String.isBlank(reg.Campaign_Member_Id__c) || !liveCampaignMemberIds.contains(reg.Campaign_Member_Id__c)) {
                // Not linked yet (e.g. public form) or the linked member was removed: link to this member
                reg.Campaign_Member_Id__c = campaignMemberId;
                liveCampaignMemberIds.add(campaignMemberId);
                changedIds.add(reg.Id);
                res.outcome = Outcome.LINKED;
            } else {
                // Linked to another member that still exists, including one linked earlier in this same call
                res.outcome = Outcome.LINKED_TO_OTHER_MEMBER;
            }

            if (!resultsByRegistrationId.containsKey(reg.Id)) {
                resultsByRegistrationId.put(reg.Id, new List<Result>());
            }
            resultsByRegistrationId.get(reg.Id).add(res);
            res.registration.Invitation_Key__c = reg.Invitation_Key__c;
            res.registration.Campaign_Member_Id__c = reg.Campaign_Member_Id__c;
        }
        if (changedIds.isEmpty()) {
            return;
        }

        // Only the two invitation fields are written
        List<summit__Summit_Events_Registration__c> updates = new List<summit__Summit_Events_Registration__c>();
        for (Id registrationId : changedIds) {
            summit__Summit_Events_Registration__c reg = current.get(registrationId);
            updates.add(
                new summit__Summit_Events_Registration__c(Id = reg.Id, Invitation_Key__c = reg.Invitation_Key__c, Campaign_Member_Id__c = reg.Campaign_Member_Id__c)
            );
        }
        List<Database.SaveResult> saveResults = Database.update(updates, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < saveResults.size(); i++) {
            if (saveResults[i].isSuccess()) {
                continue;
            }
            for (Result res : resultsByRegistrationId.get(updates[i].Id)) {
                res.outcome = Outcome.FAILED;
                res.message = joinErrors(saveResults[i].getErrors());
            }
        }
    }

    // Campaign_Member_Id__c is text, so check which linked Campaign Members still exist
    private static Set<String> findLiveCampaignMemberIds(List<summit__Summit_Events_Registration__c> registrations) {
        Set<Id> linkedIds = new Set<Id>();
        for (summit__Summit_Events_Registration__c reg : registrations) {
            if (String.isNotBlank(reg.Campaign_Member_Id__c)) {
                try {
                    linkedIds.add(Id.valueOf(reg.Campaign_Member_Id__c));
                } catch (StringException e) {
                    // Not a valid Id (manual edit): treated as not linked
                }
            }
        }
        Set<String> liveIds = new Set<String>();
        if (!linkedIds.isEmpty()) {
            for (CampaignMember member : [SELECT Id FROM CampaignMember WHERE Id IN :linkedIds WITH SYSTEM_MODE]) {
                liveIds.add(String.valueOf(member.Id));
            }
        }
        return liveIds;
    }

    /**
     * Inserts new Registrations with their invitation key set. Uses partial success so one bad row does
     * not roll back the batch. A unique-key violation (a concurrent or repeated run got there first) is
     * returned as EXISTING_FOUND with the winning Registration; other errors as FAILED.
     * Registrations without a Contact or Lead are inserted without a key (outcome CREATED).
     * Input and results are keyed by the Campaign Member Id the Registration is created for.
     */
    public static Map<Id, Result> insertRegistrations(Map<Id, summit__Summit_Events_Registration__c> registrationsByCampaignMemberId) {
        List<summit__Summit_Events_Registration__c> registrations = new List<summit__Summit_Events_Registration__c>();
        List<Result> results = new List<Result>();
        for (Id campaignMemberId : registrationsByCampaignMemberId.keySet()) {
            summit__Summit_Events_Registration__c reg = registrationsByCampaignMemberId.get(campaignMemberId);
            if (campaignMemberId == null || reg == null || reg.Id != null || reg.summit__Event_Instance__c == null) {
                throw new InvitationProcessingException('insertRegistrations only accepts new Registrations with an Event Instance, keyed by Campaign Member Id.');
            }
            Result res = new Result(new Request(reg.summit__Event_Instance__c, reg.summit__Contact__c, reg.summit__Lead__c, campaignMemberId));
            res.registration = reg;
            reg.Invitation_Key__c = res.invitationKey;
            reg.Campaign_Member_Id__c = String.valueOf(campaignMemberId);
            registrations.add(reg);
            results.add(res);
        }

        List<Database.SaveResult> saveResults = Database.insert(registrations, false, AccessLevel.SYSTEM_MODE);
        Set<String> duplicateKeys = new Set<String>();
        for (Integer i = 0; i < saveResults.size(); i++) {
            Result res = results[i];
            res.message = saveResults[i].isSuccess() ? null : joinErrors(saveResults[i].getErrors());
            if (saveResults[i].isSuccess()) {
                res.outcome = Outcome.CREATED;
            } else if (res.invitationKey != null && hasDuplicateValueError(saveResults[i].getErrors())) {
                // Unconfirmed until the re-query below finds a Registration holding this key
                duplicateKeys.add(res.invitationKey);
            } else {
                res.outcome = Outcome.FAILED;
            }
        }
        if (duplicateKeys.isEmpty()) {
            return keyByCampaignMember(results);
        }

        Map<String, summit__Summit_Events_Registration__c> winnersByKey = new Map<String, summit__Summit_Events_Registration__c>();
        for (summit__Summit_Events_Registration__c reg : [
            SELECT Id, Name, summit__Event_Instance__c, summit__Contact__c, summit__Lead__c, summit__Status__c, Invitation_Key__c, Campaign_Member_Id__c, LastModifiedDate
            FROM summit__Summit_Events_Registration__c
            WHERE Invitation_Key__c IN :duplicateKeys
            WITH SYSTEM_MODE
        ]) {
            winnersByKey.put(reg.Invitation_Key__c.toLowerCase(), reg);
        }
        List<Result> lostRace = new List<Result>();
        for (Result res : results) {
            if (res.outcome != null) {
                continue;
            }
            summit__Summit_Events_Registration__c winner = winnersByKey.get(res.invitationKey.toLowerCase());
            if (winner != null) {
                res.outcome = Outcome.EXISTING_FOUND;
                res.registration = winner;
                res.message = null;
                lostRace.add(res);
            } else {
                // DUPLICATE_VALUE came from something other than the invitation key; keep the original error
                res.outcome = Outcome.FAILED;
            }
        }
        // Apply the same Campaign Member link rule as resolve()
        adoptExisting(lostRace);
        return keyByCampaignMember(results);
    }

    private static Map<Id, Result> keyByCampaignMember(List<Result> results) {
        Map<Id, Result> resultsByCampaignMemberId = new Map<Id, Result>();
        for (Result res : results) {
            resultsByCampaignMemberId.put(res.request.campaignMemberId, res);
        }
        return resultsByCampaignMemberId;
    }

    /**
     * Returns candidate Registrations indexed by '<EventInstanceId>:<PersonId>' for both their Contact and Lead,
     * newest first. The key format equals buildKey, so a stamped key lands under the same index.
     */
    private static Map<String, List<summit__Summit_Events_Registration__c>> queryCandidates(Set<Id> instanceIds, Set<Id> contactIds, Set<Id> leadIds, Set<String> keys) {
        Map<String, List<summit__Summit_Events_Registration__c>> candidatesByPerson = new Map<String, List<summit__Summit_Events_Registration__c>>();
        if (instanceIds.isEmpty()) {
            return candidatesByPerson;
        }
        for (summit__Summit_Events_Registration__c reg : [
            SELECT Id, Name, summit__Event_Instance__c, summit__Contact__c, summit__Lead__c, summit__Status__c, Invitation_Key__c, Campaign_Member_Id__c, LastModifiedDate
            FROM summit__Summit_Events_Registration__c
            WHERE summit__Event_Instance__c IN :instanceIds
            AND (Invitation_Key__c IN :keys OR summit__Contact__c IN :contactIds OR summit__Lead__c IN :leadIds)
            WITH SYSTEM_MODE
            ORDER BY LastModifiedDate DESC
        ]) {
            Set<String> personKeys = new Set<String>{
                buildKey(reg.summit__Event_Instance__c, reg.summit__Contact__c, null),
                buildKey(reg.summit__Event_Instance__c, reg.summit__Lead__c, null)
            };
            personKeys.remove(null);
            for (String personKey : personKeys) {
                if (!candidatesByPerson.containsKey(personKey)) {
                    candidatesByPerson.put(personKey, new List<summit__Summit_Events_Registration__c>());
                }
                candidatesByPerson.get(personKey).add(reg);
            }
        }
        return candidatesByPerson;
    }

    /**
     * Preference: Registration already holding this key, then an active Registration, then any; newest first within a rank.
     */
    private static summit__Summit_Events_Registration__c pickBest(List<summit__Summit_Events_Registration__c> candidates, String invitationKey) {
        summit__Summit_Events_Registration__c best = null;
        for (summit__Summit_Events_Registration__c reg : candidates) {
            if (best == null || rank(reg, invitationKey) < rank(best, invitationKey) || (rank(reg, invitationKey) == rank(best, invitationKey) && reg.LastModifiedDate > best.LastModifiedDate)) {
                best = reg;
            }
        }
        return best;
    }

    private static Integer rank(summit__Summit_Events_Registration__c reg, String invitationKey) {
        if (reg.Invitation_Key__c != null && reg.Invitation_Key__c.equalsIgnoreCase(invitationKey)) {
            return 0;
        }
        return INACTIVE_STATUSES.contains(reg.summit__Status__c) ? 2 : 1;
    }

    // Salesforce does not name the field for unique-index violations on insert
    // ("duplicate value found: <unknown> duplicates value on record with id: <unknown>"), so callers confirm by re-query
    private static Boolean hasDuplicateValueError(List<Database.Error> errors) {
        for (Database.Error err : errors) {
            if (err.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
                return true;
            }
        }
        return false;
    }

    private static String joinErrors(List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error err : errors) {
            messages.add(err.getStatusCode() + ': ' + err.getMessage());
        }
        return String.join(messages, '; ');
    }
}
