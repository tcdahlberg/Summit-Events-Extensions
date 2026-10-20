
public without sharing class SummitInvitationQueueable implements Queueable {

    private Set<Id> campaignMemberIds;
    private static final String CAMPAIGN_INSTANCE_FIELD = 'summit_events_instance__c';
    // Only Invited Registrations get an invitation link; the decline page only accepts this status (DEC-003)
    private static final String INVITED_STATUS = 'Invited';
   
    public SummitInvitationQueueable(Set<Id> memberIds) {
        System.debug(LoggingLevel.ERROR, 'QUEUEABLE CONSTRUCTOR INPUT=' + memberIds);
        campaignMemberIds = memberIds == null ? new Set<Id>(): new Set<Id>(memberIds);
        System.debug(LoggingLevel.ERROR,'QUEUEABLE CONSTRUCTOR STORED IDS=' + campaignMemberIds);
    }
    public void execute(QueueableContext context) {
        if (campaignMemberIds.isEmpty()) {
            System.debug(LoggingLevel.ERROR,'QUEUEABLE EXIT: No CampaignMember IDs.'); return;
        }
        System.debug(LoggingLevel.ERROR, 'QUEUEABLE INPUT IDS=' + campaignMemberIds);

        for (CampaignMember cm : [SELECT Id, Status, CampaignId FROM CampaignMember WHERE Id IN :campaignMemberIds]) {
            System.debug(LoggingLevel.ERROR,'MEMBER BEFORE STATUS FILTER' + ' | Id=' + cm.Id + ' | Status=' + cm.Status + ' | CampaignId=' + cm.CampaignId);
        }
            // 1. Retrieve invited Campaign Members.
        List<CampaignMember> members = [SELECT Id, CampaignId, ContactId, LeadId, Status FROM CampaignMember WHERE Id IN :campaignMemberIds  AND Status = 'Invited'];

        System.debug(LoggingLevel.ERROR,'QUEUEABLE MEMBERS FOUND=' + members.size());
        if (members.isEmpty()) {
            return;
        }

        // 2. Retrieve the Event Instance associated with each Campaign.
        Set<Id> campaignIds = new Set<Id>();

        for (CampaignMember member : members) {
            if (member.CampaignId != null) {
                campaignIds.add(member.CampaignId);
            }
        }

        if (campaignIds.isEmpty()) {
            return;
        }

        String campaignQuery = 'SELECT Id, ' + CAMPAIGN_INSTANCE_FIELD + ' FROM Campaign WHERE Id IN :campaignIds';
        List<SObject> campaigns = Database.queryWithBinds(
            campaignQuery,
            new Map<String, Object>{
                'campaignIds' => campaignIds
            },
            AccessLevel.SYSTEM_MODE
        );

        Map<Id, Id> eventByCampaign = new Map<Id, Id>();

        for (SObject campaign : campaigns) {
            Id eventId = (Id) campaign.get(CAMPAIGN_INSTANCE_FIELD);

            if (eventId != null) {
                eventByCampaign.put((Id) campaign.get('Id'), eventId);
            }
        }

        // 3. Build one deduplication request per eligible member.
        List<InvitationRegistrationDedupe.Request> requests = new List<InvitationRegistrationDedupe.Request>();
        for (CampaignMember member : members) {
            Id eventId = eventByCampaign.get(member.CampaignId);
            // A Campaign without an Event Instance is ignored.
            if (eventId == null) {
                System.debug(LoggingLevel.ERROR,'SKIPPING: No Event Instance for CampaignMember ' + member.Id);
                continue;
            }

            requests.add(new InvitationRegistrationDedupe.Request(eventId, member.ContactId, member.LeadId, member.Id));
        }

        if (requests.isEmpty()) {
            System.debug(LoggingLevel.ERROR, 'QUEUEABLE EXIT: No eligible requests.');
            return;
        }

        // 4. Find existing registrations and resolve duplicates.
        Map<Id, InvitationRegistrationDedupe.Result> resolved = InvitationRegistrationDedupe.resolve(requests);

        Map<Id, summit__Summit_Events_Registration__c>
            registrationsToInsert = new Map<Id, summit__Summit_Events_Registration__c>();
        // Existing Registrations count too, so a re-run issues links that a failed run did not
        Set<Id> invitedRegistrationIds = new Set<Id>();

        for (Id memberId : resolved.keySet()) {
            InvitationRegistrationDedupe.Result result = resolved.get(memberId);
            addIfInvited(result, invitedRegistrationIds);

            System.debug(LoggingLevel.ERROR, 'DEDUPE RESOLVE'  + ' | memberId=' + memberId + ' | outcome=' + result.outcome + ' | key=' + result.invitationKey + ' | message=' + result.message + ' | registrationId=' + (result.registration == null ? 'null': String.valueOf(result.registration.Id)))            ;
            // Only genuinely new registrations are inserted.
            if (result.outcome != InvitationRegistrationDedupe.Outcome.NEW_REGISTRATION_NEEDED) {
                continue;
            }
            InvitationRegistrationDedupe.Request req = result.request;
            summit__Summit_Events_Registration__c registration = new summit__Summit_Events_Registration__c();
            registration.summit__Event_Instance__c = req.eventInstanceId;
            registration.summit__Contact__c = req.contactId;
            registration.summit__Lead__c = req.leadId;

            registration.summit__Status__c = INVITED_STATUS;
            registrationsToInsert.put(memberId, registration);
        }

        System.debug(LoggingLevel.ERROR,'REGISTRATIONS TO INSERT=' + registrationsToInsert.size());

        if (registrationsToInsert.isEmpty()) {
            issueInvitationLinks(invitedRegistrationIds);
            return;
        }

        // 5. Insert registrations using the dedupe service.
        // This stamps Invitation_Key__c and Campaign_Member_Id__c,
        // handles partial failures, and adopts duplicate-key winners.
        Map<Id, InvitationRegistrationDedupe.Result> insertResults = InvitationRegistrationDedupe.insertRegistrations(registrationsToInsert);

        for (Id memberId : insertResults.keySet()) {
            InvitationRegistrationDedupe.Result result = insertResults.get(memberId);
            System.debug(LoggingLevel.ERROR, 'DEDUPE INSERT' + ' | memberId=' + memberId + ' | outcome=' + result.outcome + ' | registrationId=' + (result.registration == null ? 'null' : String.valueOf(result.registration.Id))  + ' | message=' + result.message);
            addIfInvited(result, invitedRegistrationIds);
        }

        // 6. Issue the public invitation link (US-06/US-14, DEC-004).
        issueInvitationLinks(invitedRegistrationIds);
    }

    private static void addIfInvited(InvitationRegistrationDedupe.Result result, Set<Id> registrationIds) {
        if (result.registration != null
            && result.registration.Id != null
            && result.registration.summit__Status__c == INVITED_STATUS) {
            registrationIds.add(result.registration.Id);
        }
    }

    /**
     * A link failure must not undo the Registrations: they are kept, the error is logged, and the next run for
     * these members issues the missing links (existing links are reused, never replaced).
     */
    private static void issueInvitationLinks(Set<Id> registrationIds) {
        if (registrationIds.isEmpty()) {
            return;
        }
        try {
            SummitEventsInvitationService.getOrCreateLinksForAutomation(registrationIds);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'INVITATION LINKS FAILED | registrations=' + registrationIds.size() + ' | ' + e.getTypeName() + ': ' + e.getMessage());
        }
    }
}
