
public without sharing class SummitInvitationQueueable implements Queueable {

    private Set<Id> campaignMemberIds;
    private static final String CAMPAIGN_INSTANCE_FIELD = 'summit_events_instance__c';
   
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

        for (Id memberId : resolved.keySet()) {
            InvitationRegistrationDedupe.Result result = resolved.get(memberId);

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

            // Change this value if the package uses a different
            // valid registration-status picklist value.
            registration.summit__Status__c = 'Registered';
            registrationsToInsert.put(memberId, registration);
        }

        System.debug(LoggingLevel.ERROR,'REGISTRATIONS TO INSERT=' + registrationsToInsert.size());

        if (registrationsToInsert.isEmpty()) {
            return;
        }

        // 5. Insert registrations using the dedupe service.
        // This stamps Invitation_Key__c and Campaign_Member_Id__c,
        // handles partial failures, and adopts duplicate-key winners.
        Map<Id, InvitationRegistrationDedupe.Result> insertResults = InvitationRegistrationDedupe.insertRegistrations(registrationsToInsert);

        for (Id memberId : insertResults.keySet()) {
            InvitationRegistrationDedupe.Result result = insertResults.get(memberId);
            System.debug(LoggingLevel.ERROR, 'DEDUPE INSERT' + ' | memberId=' + memberId + ' | outcome=' + result.outcome + ' | registrationId=' + (result.registration == null ? 'null' : String.valueOf(result.registration.Id))  + ' | message=' + result.message);
        }
    }
}
