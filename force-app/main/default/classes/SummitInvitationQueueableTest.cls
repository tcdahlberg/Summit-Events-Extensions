@IsTest
private class SummitInvitationQueueableTest {

    private static final String EVENT_FIELD = 'summit_events_instance__c';
    private static final String REGISTRATION_OBJECT = 'summit__Summit_Events_Registration__c';
    private static final String EVENT_LOOKUP = 'summit__Event_Instance__c';
    private static final String CONTACT_LOOKUP = 'summit__Contact__c';
    private static final String LEAD_LOOKUP = 'summit__Lead__c';
    private static final String STATUS_FIELD = 'summit__Status__c';

    private static Id createEventInstance() {
        Schema.SObjectField campaignField = Schema.SObjectType.Campaign.fields.getMap().get(EVENT_FIELD);
        System.assertNotEquals(null, campaignField,'Campaign event lookup field must exist.');
        Schema.SObjectType instanceType = campaignField.getDescribe().getReferenceTo()[0];
        SObject instanceRecord = instanceType.newSObject();
        Map<String, Schema.SObjectField> instanceFields = instanceType.getDescribe().fields.getMap();
        Schema.SObjectField parentField = instanceFields.get('summit__Event__c');
        System.assertNotEquals(null, parentField, 'Event Instance must have summit__Event__c.');
        Schema.SObjectType parentType = parentField.getDescribe().getReferenceTo()[0];
        SObject parentEvent = parentType.newSObject();
        setNameIfAvailable(parentEvent, 'Test Summit Event');
        insert parentEvent;

        instanceRecord.put('summit__Event__c', parentEvent.get('Id'));
        setNameIfAvailable(instanceRecord, 'Test Summit Event Instance');
        insert instanceRecord;
        return (Id) instanceRecord.get('Id');
    }

    private static void setNameIfAvailable(SObject record, String value) {
        Map<String, Schema.SObjectField> fields = record.getSObjectType().getDescribe().fields.getMap();
        if (fields.containsKey('Name')) {
            Schema.DescribeFieldResult description = fields.get('Name').getDescribe();

            if (description.isCreateable()
                && !description.isAutoNumber()) {
                record.put('Name', value);
            }
        }
    }

    private static Campaign createCampaign(Id eventId) {
        Campaign campaign = new Campaign( Name = 'Test Invitation Campaign', IsActive = true);

        if (eventId != null) {
            campaign.put(EVENT_FIELD, eventId);
        }

        insert campaign;
        insert new CampaignMemberStatus(CampaignId = campaign.Id, Label = 'Invited');
        System.debug('xxxCreated campaign: ' + campaign.Id);
        System.debug('xxxAdded Campaign Member Status: Invited');
        return campaign;
    }

    private static Contact createContact() {
        Contact contact = new Contact(LastName = 'Test Contact');
        insert contact;
        return contact;
    }

    private static Lead createLead() {
        Lead lead = new Lead(LastName = 'Test Lead', Company = 'Test Company');
        insert lead;
        return lead;
    }
    private static CampaignMember createMember(Campaign campaign, Id contactId, Id leadId, String status) {
        CampaignMember member = new CampaignMember(CampaignId = campaign.Id, Status = status);

        if (contactId != null) {
            member.ContactId = contactId;
        } else if (leadId != null) {
            member.LeadId = leadId;
        }

        insert member;
        System.debug('xxxCAMPAIGN MEMBER INSERTED: Id=' + member.Id + ', Requested Status=' + status);
        return member;
    }

    private static Integer countRegistrations(Id eventId, Id contactId, Id leadId) {
        String query = 'SELECT Id FROM ' + REGISTRATION_OBJECT + ' WHERE ' + EVENT_LOOKUP + ' = :eventId';
        if (contactId != null) {
            query += ' AND ' + CONTACT_LOOKUP + ' = :contactId';
        } else {
            query += ' AND ' + LEAD_LOOKUP + ' = :leadId';
        }
        return Database.query(query).size();
    }

    private static summit__Summit_Events_Registration__c
        createExistingRegistration(Id eventId, Id contactId, Id leadId) {
        summit__Summit_Events_Registration__c registration = new summit__Summit_Events_Registration__c();
        registration.summit__Event_Instance__c = eventId;
        registration.summit__Status__c = 'Registered';

        if (contactId != null) {
            registration.summit__Contact__c = contactId;
        } else {
            registration.summit__Lead__c = leadId;
        }

        // Add any additional mandatory Summit Registration fields
        // required by your org here.

        insert registration;
        return registration;
    }

    @IsTest
    static void testNullAndEmptyInput() {
        Test.startTest();
        System.enqueueJob(new SummitInvitationQueueable(null));
        System.enqueueJob(new SummitInvitationQueueable(new Set<Id>()));
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM summit__Summit_Events_Registration__c], 'Empty input must not create registrations.');
    }
    @IsTest
    static void testInvitedContactCreatesRegistration() {
        Id eventId = createEventInstance();
        Campaign campaign = createCampaign(eventId);
        Contact contact = createContact();
        CampaignMember member = createMember(campaign, contact.Id, null, 'Invited');

        Test.startTest();
        System.enqueueJob(new SummitInvitationQueueable( new Set<Id>{ member.Id }));
        Test.stopTest();
        System.debug('xxxx TEST ' + member + campaign + contact);
        System.assertEquals(1, countRegistrations(eventId, contact.Id, null), 'One registration should be created for the invited Contact.');

        summit__Summit_Events_Registration__c registration = [SELECT Id, summit__Status__c, Invitation_Key__c, Campaign_Member_Id__c FROM summit__Summit_Events_Registration__c WHERE summit__Event_Instance__c = :eventId AND summit__Contact__c = :contact.Id LIMIT 1];

        System.assertEquals('Registered', registration.summit__Status__c);
        System.assertEquals(InvitationRegistrationDedupe.buildKey(eventId, contact.Id, null), registration.Invitation_Key__c);
        System.assertEquals(String.valueOf(member.Id), registration.Campaign_Member_Id__c);
    }

    @IsTest
    static void testInvitedLeadCreatesRegistration() {
        Id eventId = createEventInstance();
        Campaign campaign = createCampaign(eventId);
        Lead lead = createLead();
        CampaignMember member = createMember(campaign, null, lead.Id, 'Invited');
        System.debug(LoggingLevel.ERROR, 'xxx LEAD TEST MEMBER' + ' | ID=' + member.Id + ' | STATUS=' + member.Status + ' | LEAD ID=' + member.LeadId + ' | CONTACT ID=' + member.ContactId + ' | EVENT ID=' + campaign.summit_events_instance__c);
        Test.startTest();
        System.enqueueJob(new SummitInvitationQueueable(new Set<Id>{ member.Id }));
        Test.stopTest();

        System.assertEquals(1, countRegistrations(eventId, null, lead.Id),'One registration should be created for the invited Lead.');
    }

    @IsTest
    static void testExistingRegistrationIsReused() {
        Id eventId = createEventInstance();
        Campaign campaign = createCampaign(eventId);
        Contact contact = createContact();
        CampaignMember member = createMember(campaign, contact.Id, null, 'Invited');
        summit__Summit_Events_Registration__c existing = createExistingRegistration(eventId, contact.Id, null);

        Test.startTest();
        System.enqueueJob(new SummitInvitationQueueable(new Set<Id>{ member.Id }));
        Test.stopTest();
        System.assertEquals(1, countRegistrations(eventId, contact.Id, null),'The existing registration must be reused.');
        summit__Summit_Events_Registration__c afterRun = [SELECT Id, summit__Status__c, Invitation_Key__c, Campaign_Member_Id__c FROM summit__Summit_Events_Registration__c WHERE Id = :existing.Id];

        System.assertEquals('Registered', afterRun.summit__Status__c,'The existing registration status must be preserved.');

        System.assertEquals(String.valueOf(member.Id), afterRun.Campaign_Member_Id__c,'The existing registration should be linked to the member.');
    }

    @IsTest
    static void testDuplicateInvitationsAcrossCampaigns() {
        Id eventId = createEventInstance();

        Campaign campaign1 = createCampaign(eventId);
        Campaign campaign2 = createCampaign(eventId);
        Contact contact = createContact();

        CampaignMember member1 = createMember(campaign1, contact.Id, null, 'Invited');
        CampaignMember member2 = createMember(campaign2, contact.Id, null, 'Invited');

        Test.startTest();
        System.enqueueJob(new SummitInvitationQueueable(new Set<Id>{ member1.Id, member2.Id }));
        Test.stopTest();

        System.assertEquals(1, countRegistrations(eventId, contact.Id, null), 'Only one Registration should exist per Event Instance and person.');
    }

    @IsTest
    static void testNonInvitedMemberIsIgnored() {
        Id eventId = createEventInstance();
        Campaign campaign = createCampaign(eventId);
        Contact contact = createContact();
        // Replace 'Sent' if it is not a valid Campaign Member status
        // in your Salesforce org.
        CampaignMember member = createMember(campaign, contact.Id, null, 'Sent');

        Test.startTest();
        System.enqueueJob(new SummitInvitationQueueable(new Set<Id>{ member.Id }));
        Test.stopTest();

        System.assertEquals(0, countRegistrations(eventId, contact.Id, null),'Non-invited Campaign Members must be ignored.');
    }

    @IsTest
    static void testCampaignWithoutEventInstanceIsIgnored() {
        Campaign campaign = createCampaign(null);
        Contact contact = createContact();
        CampaignMember member = createMember(campaign, contact.Id, null, 'Invited');
        Test.startTest();
        System.enqueueJob(new SummitInvitationQueueable(new Set<Id>{ member.Id }));
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM summit__Summit_Events_Registration__c WHERE summit__Contact__c = :contact.Id], 'A Campaign without an Event Instance must be skipped.');
    }
}
