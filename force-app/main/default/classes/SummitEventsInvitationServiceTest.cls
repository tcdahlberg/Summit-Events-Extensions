@IsTest
private class SummitEventsInvitationServiceTest {
    private static final Integer BULK_SIZE = 600;
    private static final String BASE_URL = 'https://invitations.example.invalid/summit__SummitEventsRegister';
    private static final Map<String, Boolean> SENDER_FIELD_ACCESS = new Map<String, Boolean>{
        'Public_Invitation_Link__c' => true,
        'Public_Invitation_Token_Hash__c' => true,
        'Public_Invitation_Issued_At__c' => true
    };

    @TestSetup
    static void setup() {
        summit__Summit_Events__c evt = new summit__Summit_Events__c(Name = 'Invitation Link Test Gala');
        insert evt;
        insert new summit__Summit_Events_Instance__c(summit__Event__c = evt.Id, summit__Instance_Title__c = 'Invitation Link Test Gala 2026');
    }

    private static List<summit__Summit_Events_Registration__c> insertRegistrations(Integer count) {
        summit__Summit_Events_Instance__c instance = [
            SELECT Id, summit__Event__c
            FROM summit__Summit_Events_Instance__c
            WHERE summit__Instance_Title__c = 'Invitation Link Test Gala 2026'
            LIMIT 1
        ];
        List<summit__Summit_Events_Registration__c> registrations = new List<summit__Summit_Events_Registration__c>();
        for (Integer i = 0; i < count; i++) {
            registrations.add(new summit__Summit_Events_Registration__c(summit__Event_Instance__c = instance.Id, summit__Event__c = instance.summit__Event__c));
        }
        insert registrations;
        return registrations;
    }

    private static summit__Summit_Events_Registration__c insertRegistration() {
        return insertRegistrations(1)[0];
    }

    private static summit__Summit_Events_Registration__c reload(Id registrationId) {
        return [
            SELECT Public_Invitation_Link__c, Public_Invitation_Token_Hash__c, Public_Invitation_Issued_At__c
            FROM summit__Summit_Events_Registration__c
            WHERE Id = :registrationId
            WITH SYSTEM_MODE
        ];
    }

    private static String tokenOf(String link) {
        return link.substringAfter('?t=');
    }

    private static void assertFails(Id registrationId, String expectedMessage) {
        try {
            SummitEventsInvitationService.getOrCreateLink(registrationId);
            Assert.fail('Expected InvitationException: ' + expectedMessage);
        } catch (SummitEventsInvitationService.InvitationException e) {
            Assert.areEqual(expectedMessage, e.getMessage());
        }
    }

    private static User newMinimumAccessUser(String alias) {
        User user = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce'].Id,
            LastName = 'Invitationlinktest',
            Alias = alias,
            Email = alias + '@example.invalid',
            Username = alias + System.currentTimeMillis() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Europe/Amsterdam'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert user;
        }
        return user;
    }

    // Read and edit on Registration (all records, so sharing does not hide the test data) and read on its parents
    private static PermissionSet newRegistrationAccessPermissionSet(String name) {
        PermissionSet permissionSet = new PermissionSet(Name = name, Label = name);
        insert permissionSet;
        insert new List<ObjectPermissions>{
            new ObjectPermissions(ParentId = permissionSet.Id, SobjectType = 'summit__Summit_Events__c', PermissionsRead = true),
            new ObjectPermissions(ParentId = permissionSet.Id, SobjectType = 'summit__Summit_Events_Instance__c', PermissionsRead = true),
            new ObjectPermissions(
                ParentId = permissionSet.Id,
                SobjectType = 'summit__Summit_Events_Registration__c',
                PermissionsRead = true,
                PermissionsEdit = true,
                PermissionsDelete = true,
                PermissionsViewAllRecords = true,
                PermissionsModifyAllRecords = true
            )
        };
        return permissionSet;
    }

    private static FieldPermissions fieldPermission(Id permissionSetId, String fieldName, Boolean editable) {
        return new FieldPermissions(
            ParentId = permissionSetId,
            SobjectType = 'summit__Summit_Events_Registration__c',
            Field = 'summit__Summit_Events_Registration__c.' + fieldName,
            PermissionsRead = true,
            PermissionsEdit = editable
        );
    }

    /**
     * A user who can send invitations: Registration access plus the given field access (field name => editable).
     * Tests run as this user rather than the test runner, so they don't depend on the org's field-level security.
     */
    private static User newSender(String alias, Map<String, Boolean> editableByField) {
        User user = newMinimumAccessUser(alias);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet permissionSet = newRegistrationAccessPermissionSet('SEIS_Test_' + alias);
            List<FieldPermissions> fieldPermissions = new List<FieldPermissions>();
            for (String fieldName : editableByField.keySet()) {
                fieldPermissions.add(fieldPermission(permissionSet.Id, fieldName, editableByField.get(fieldName)));
            }
            insert fieldPermissions;
            insert new PermissionSetAssignment(AssigneeId = user.Id, PermissionSetId = permissionSet.Id);
        }
        return user;
    }

    // A sender with edit access to the invitation fields, as getOrCreateLinks (user mode) requires
    private static User newSender() {
        return newSender('silsend', SENDER_FIELD_ACCESS);
    }

    // Field access from the real Summit_Events_Invite_Manager permission set, so the tests also check its grants
    private static User newInviteManager() {
        User user = newMinimumAccessUser('silinvm');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet objectAccess = newRegistrationAccessPermissionSet('SEIS_Test_Object_Access');
            Id inviteManagerId = [SELECT Id FROM PermissionSet WHERE Name = 'Summit_Events_Invite_Manager' LIMIT 1].Id;
            insert new List<PermissionSetAssignment>{
                new PermissionSetAssignment(AssigneeId = user.Id, PermissionSetId = objectAccess.Id),
                new PermissionSetAssignment(AssigneeId = user.Id, PermissionSetId = inviteManagerId)
            };
        }
        return user;
    }

    @IsTest
    static void createsLinkWithRandomTokenAndStoresHash() {
        SummitEventsInvitationService.baseUrl = BASE_URL;
        summit__Summit_Events_Registration__c registration = insertRegistration();

        String link;
        System.runAs(newSender()) {
            Test.startTest();
            link = SummitEventsInvitationService.getOrCreateLink(registration.Id);
            Test.stopTest();
        }

        String token = tokenOf(link);
        Assert.isTrue(link.startsWith(BASE_URL + '?t='), 'Link uses the configured base URL: ' + link);
        Assert.isTrue(token.length() == 64 && token.isAlphanumeric(), 'Token is 64 hex characters: ' + token);
        Assert.isFalse(link.contains(String.valueOf(registration.Id).left(15)), 'Link does not contain the Registration Id');

        summit__Summit_Events_Registration__c saved = reload(registration.Id);
        Assert.areEqual(link, saved.Public_Invitation_Link__c);
        Assert.areEqual(SummitEventsInvitationService.hashToken(token), saved.Public_Invitation_Token_Hash__c);
        Assert.areNotEqual(token, saved.Public_Invitation_Token_Hash__c, 'The token itself is not stored as the hash');
        Assert.isNotNull(saved.Public_Invitation_Issued_At__c);
    }

    @IsTest
    static void hashIsSha256Hex() {
        // Known SHA-256 of "abc", so the page that resolves tokens can rely on the format
        Assert.areEqual('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad', SummitEventsInvitationService.hashToken('abc'));
    }

    @IsTest
    static void reusesExistingLink() {
        SummitEventsInvitationService.baseUrl = BASE_URL;
        summit__Summit_Events_Registration__c registration = insertRegistration();

        System.runAs(newSender()) {
            String firstLink = SummitEventsInvitationService.getOrCreateLink(registration.Id);
            summit__Summit_Events_Registration__c afterFirst = reload(registration.Id);

            Test.startTest();
            String secondLink = SummitEventsInvitationService.getOrCreateLink(registration.Id);
            Test.stopTest();

            summit__Summit_Events_Registration__c afterSecond = reload(registration.Id);
            Assert.areEqual(firstLink, secondLink);
            Assert.areEqual(afterFirst.Public_Invitation_Token_Hash__c, afterSecond.Public_Invitation_Token_Hash__c);
            Assert.areEqual(afterFirst.Public_Invitation_Issued_At__c, afterSecond.Public_Invitation_Issued_At__c);
        }
    }

    @IsTest
    static void eachRegistrationGetsItsOwnToken() {
        SummitEventsInvitationService.baseUrl = BASE_URL;
        List<summit__Summit_Events_Registration__c> registrations = insertRegistrations(2);

        System.runAs(newSender()) {
            String first = SummitEventsInvitationService.getOrCreateLink(registrations[0].Id);
            String second = SummitEventsInvitationService.getOrCreateLink(registrations[1].Id);
            Assert.areNotEqual(first, second);
        }
    }

    @IsTest
    static void bulkAudienceOf600InOneCall() {
        SummitEventsInvitationService.baseUrl = BASE_URL;
        Map<Id, summit__Summit_Events_Registration__c> registrations = new Map<Id, summit__Summit_Events_Registration__c>(insertRegistrations(BULK_SIZE));

        System.runAs(newSender()) {
            Test.startTest();
            Map<Id, String> links = SummitEventsInvitationService.getOrCreateLinks(registrations.keySet());
            Integer queriesUsed = Limits.getQueries();
            Integer dmlUsed = Limits.getDmlStatements();
            Test.stopTest();

            Assert.areEqual(BULK_SIZE, links.size());
            Assert.areEqual(BULK_SIZE, new Set<String>(links.values()).size(), 'Every link is unique');
            Assert.areEqual(1, dmlUsed, 'One update for the whole audience');
            Assert.isTrue(queriesUsed < 10, 'Query count does not grow with audience size: ' + queriesUsed);
            Assert.areEqual(
                BULK_SIZE,
                [SELECT COUNT() FROM summit__Summit_Events_Registration__c WHERE Id IN :registrations.keySet() AND Public_Invitation_Token_Hash__c != NULL WITH SYSTEM_MODE]
            );

            // Running it again (a retry) issues nothing new
            Map<Id, String> retry = SummitEventsInvitationService.getOrCreateLinks(registrations.keySet());
            Assert.areEqual(links, retry);
        }
    }

    @IsTest
    static void bulkIsAllOrNothing() {
        SummitEventsInvitationService.baseUrl = BASE_URL;
        List<summit__Summit_Events_Registration__c> registrations = insertRegistrations(2);
        registrations[1].Public_Invitation_Link__c = BASE_URL + '?t=orphan';
        update as system registrations[1];

        System.runAs(newSender()) {
            try {
                SummitEventsInvitationService.getOrCreateLinks(new Set<Id>{ registrations[0].Id, registrations[1].Id });
                Assert.fail('Expected InvitationException');
            } catch (SummitEventsInvitationService.InvitationException e) {
                Assert.areEqual('Incomplete invitation credentials: ' + registrations[1].Id, e.getMessage());
            }
        }
        Assert.isNull(reload(registrations[0].Id).Public_Invitation_Link__c, 'No link is saved when the batch fails');
    }

    @IsTest
    static void incompleteCredentialsAreNotReplaced() {
        SummitEventsInvitationService.baseUrl = BASE_URL;
        List<summit__Summit_Events_Registration__c> registrations = insertRegistrations(2);
        registrations[0].Public_Invitation_Link__c = BASE_URL + '?t=orphan';
        registrations[1].Public_Invitation_Token_Hash__c = SummitEventsInvitationService.hashToken('orphan');
        update as system registrations;

        System.runAs(newSender()) {
            assertFails(registrations[0].Id, 'Incomplete invitation credentials: ' + registrations[0].Id);
            assertFails(registrations[1].Id, 'Incomplete invitation credentials: ' + registrations[1].Id);
        }
        Assert.areEqual(BASE_URL + '?t=orphan', reload(registrations[0].Id).Public_Invitation_Link__c);
        Assert.isNull(reload(registrations[1].Id).Public_Invitation_Link__c);
    }

    @IsTest
    static void missingIdIsRejected() {
        assertFails(null, 'Registration ID is required.');
        for (Set<Id> registrationIds : new List<Set<Id>>{ null, new Set<Id>(), new Set<Id>{ null } }) {
            try {
                SummitEventsInvitationService.getOrCreateLinks(registrationIds);
                Assert.fail('Expected InvitationException for ' + registrationIds);
            } catch (SummitEventsInvitationService.InvitationException e) {
                Assert.areEqual('Registration ID is required.', e.getMessage());
            }
        }
    }

    @IsTest
    static void deletedRegistrationIsUnavailable() {
        SummitEventsInvitationService.baseUrl = BASE_URL;
        summit__Summit_Events_Registration__c registration = insertRegistration();
        delete registration;

        System.runAs(newSender()) {
            assertFails(registration.Id, 'Registration unavailable.');
        }
    }

    @IsTest
    static void invalidBaseUrlIsRejected() {
        summit__Summit_Events_Registration__c registration = insertRegistration();
        System.runAs(newSender()) {
            for (String url : new List<String>{ null, '', 'http://insecure.example.invalid/register', BASE_URL + '?instanceID=x', BASE_URL + '#top' }) {
                SummitEventsInvitationService.baseUrl = url;
                assertFails(registration.Id, 'Invalid invitation URL configuration.');
            }
        }
        Assert.isNull(reload(registration.Id).Public_Invitation_Link__c);
    }

    @IsTest
    static void tooLongBaseUrlIsRejected() {
        summit__Summit_Events_Registration__c registration = insertRegistration();
        // 189 + '?t=' + 64-character token = 256, one over the field length
        SummitEventsInvitationService.baseUrl = 'https://' + 'a'.repeat(181);

        System.runAs(newSender()) {
            assertFails(registration.Id, 'Invitation URL exceeds field length.');
        }
    }

    @IsTest
    static void configuredLabelIsUsedByDefault() {
        Assert.areEqual(System.Label.Summit_Events_Public_Invitation_URL, SummitEventsInvitationService.baseUrl);
    }

    @IsTest
    static void userWithoutRegistrationAccessIsRejected() {
        summit__Summit_Events_Registration__c registration = insertRegistration();

        System.runAs(newMinimumAccessUser('silnoacc')) {
            assertFails(registration.Id, 'Insufficient permissions.');
        }
    }

    @IsTest
    static void userWithoutEditOnAWrittenFieldIsRejected() {
        SummitEventsInvitationService.baseUrl = BASE_URL;
        summit__Summit_Events_Registration__c registration = insertRegistration();
        Map<String, Boolean> fieldAccess = SENDER_FIELD_ACCESS.clone();
        fieldAccess.put('Public_Invitation_Issued_At__c', false);

        System.runAs(newSender('silnofls', fieldAccess)) {
            assertFails(registration.Id, 'Insufficient field permissions.');
        }
        Assert.isNull(reload(registration.Id).Public_Invitation_Link__c);
    }

    // DEC-004: the invitation fields are read-only for the Invite Manager and the token hash is hidden
    @IsTest
    static void inviteManagerCanReadLinkButNotWriteOrSeeHash() {
        summit__Summit_Events_Registration__c registration = insertRegistration();

        System.runAs(newInviteManager()) {
            Map<String, Schema.SObjectField> fields = Schema.SObjectType.summit__Summit_Events_Registration__c.fields.getMap();
            Assert.isTrue(fields.get('Public_Invitation_Link__c').getDescribe().isAccessible());
            Assert.isFalse(fields.get('Public_Invitation_Link__c').getDescribe().isUpdateable());
            Assert.isFalse(fields.get('Public_Invitation_Token_Hash__c').getDescribe().isAccessible());

            assertFails(registration.Id, 'Insufficient field permissions.');
        }
    }

    @IsTest
    static void automationIssuesLinkForInviteManager() {
        SummitEventsInvitationService.baseUrl = BASE_URL;
        summit__Summit_Events_Registration__c registration = insertRegistration();
        Map<Id, String> links;

        System.runAs(newInviteManager()) {
            Test.startTest();
            links = SummitEventsInvitationService.getOrCreateLinksForAutomation(new Set<Id>{ registration.Id });
            Test.stopTest();
        }

        summit__Summit_Events_Registration__c stored = reload(registration.Id);
        Assert.areEqual(stored.Public_Invitation_Link__c, links.get(registration.Id));
        Assert.isTrue(stored.Public_Invitation_Link__c.startsWith(BASE_URL + '?t='));
        Assert.areEqual(SummitEventsInvitationService.hashToken(tokenOf(stored.Public_Invitation_Link__c)), stored.Public_Invitation_Token_Hash__c);
        Assert.isNotNull(stored.Public_Invitation_Issued_At__c);
    }

    @IsTest
    static void automationReusesExistingLink() {
        SummitEventsInvitationService.baseUrl = BASE_URL;
        summit__Summit_Events_Registration__c registration = insertRegistration();
        Set<Id> registrationIds = new Set<Id>{ registration.Id };

        Test.startTest();
        String first = SummitEventsInvitationService.getOrCreateLinksForAutomation(registrationIds).get(registration.Id);
        String second = SummitEventsInvitationService.getOrCreateLinksForAutomation(registrationIds).get(registration.Id);
        Test.stopTest();

        Assert.areEqual(first, second);
    }

    @IsTest
    static void automationRejectsMissingIds() {
        try {
            SummitEventsInvitationService.getOrCreateLinksForAutomation(new Set<Id>());
            Assert.fail('Expected InvitationException');
        } catch (SummitEventsInvitationService.InvitationException e) {
            Assert.areEqual('Registration ID is required.', e.getMessage());
        }
    }
}
