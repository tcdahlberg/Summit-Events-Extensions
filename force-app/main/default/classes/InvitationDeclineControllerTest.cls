/**
 * Tests for US-08 (decline an invitation) and US-09 (optional decline reason): InvitationDeclineController.
 *
 * Requires the 'Invited' and 'Declined' values on summit__Summit_Events_Registration__c.summit__Status__c in the
 * target org; the package does not ship them.
 */
@IsTest
private class InvitationDeclineControllerTest {
    // Plain invitation token per Registration; only its hash is stored, as SummitEventsInvitationService does
    private static Map<Id, String> tokens = new Map<Id, String>();

    @TestSetup
    static void setup() {
        summit__Summit_Events__c evt = new summit__Summit_Events__c(Name = 'Decline Test Gala', summit__Event_Name__c = 'Decline Test Gala');
        insert evt;
        insert new summit__Summit_Events_Instance__c(summit__Event__c = evt.Id, summit__Instance_Title__c = 'Decline Test Gala 2026');
    }

    private static summit__Summit_Events_Registration__c createRegistration(String status) {
        summit__Summit_Events_Instance__c instance = [
            SELECT Id, summit__Event__c
            FROM summit__Summit_Events_Instance__c
            WHERE summit__Instance_Title__c = 'Decline Test Gala 2026'
            LIMIT 1
        ];
        summit__Summit_Events_Registration__c registration = new summit__Summit_Events_Registration__c(
            summit__Event_Instance__c = instance.Id,
            summit__Event__c = instance.summit__Event__c,
            summit__Registrant_First_Name__c = 'Thomas',
            summit__Registrant_Last_Name__c = 'Ambassador',
            summit__Registrant_Email__c = 'thomas@example.invalid',
            summit__Status__c = status
        );
        String token = newToken();
        registration.Public_Invitation_Token_Hash__c = SummitEventsInvitationService.hashToken(token);
        // System mode: the token hash is hidden from users (DEC-004), and at API 68.0 test DML checks field access
        insert as system registration;
        tokens.put(registration.Id, token);
        return registration;
    }

    private static String newToken() {
        return EncodingUtil.convertToHex(Crypto.generateAesKey(256));
    }

    private static String getLinkParameter(summit__Summit_Events_Registration__c registration) {
        return tokens.get(registration.Id);
    }

    private static InvitationDeclineController openDeclinePage(String token) {
        Test.setCurrentPage(Page.InvitationDecline);
        if (token != null) {
            ApexPages.currentPage().getParameters().put('t', token);
        }
        return new InvitationDeclineController();
    }

    private static String getStatus(Id registrationId) {
        return [SELECT summit__Status__c FROM summit__Summit_Events_Registration__c WHERE Id = :registrationId].summit__Status__c;
    }

    // A user who doesn't own the Registration, with the site guest user's permission set. Without it the package's
    // SummitEventsRegistrationTrigger fails on update (NullPointerException) in this user's context.
    private static User invitee() {
        User u = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User'].Id,
            LastName = 'Declinetest',
            Alias = 'dcltest',
            Email = 'dcltest@example.invalid',
            Username = 'dcltest' + System.currentTimeMillis() + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'Europe/Amsterdam'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            insert new PermissionSetAssignment(
                AssigneeId = u.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Summit_Events_Registrant_Custom'].Id
            );
        }
        return u;
    }

    @IsTest
    static void declinesInvitationWithoutCreatingRecords() {
        summit__Summit_Events_Registration__c invitation = createRegistration('Invited');
        User testUser = invitee();
        InvitationDeclineController declineCtrl;

        System.runAs(testUser) {
            declineCtrl = openDeclinePage(getLinkParameter(invitation));
            Assert.isFalse(declineCtrl.eventNotFound);
            Assert.isTrue(declineCtrl.canDecline);
        }
        // Read back outside runAs: the invitee itself has no access to Registrations
        Assert.areEqual('Invited', getStatus(invitation.Id), 'Opening the page must not change the registration');

        System.runAs(testUser) {
            Test.startTest();
            Assert.isNotNull(declineCtrl.declineInvitation());
            Test.stopTest();
        }

        Assert.areEqual('Declined', getStatus(invitation.Id));
        Assert.areEqual(1, [SELECT COUNT() FROM summit__Summit_Events_Registration__c], 'Decline must update the existing registration, not create one');

        System.runAs(testUser) {
            InvitationDeclineController reloadedCtrl = openDeclinePage(getLinkParameter(invitation));
            Assert.isTrue(reloadedCtrl.alreadyDeclined);
            Assert.isFalse(reloadedCtrl.canDecline);
        }
    }

    @IsTest
    static void repeatDeclineLeavesRegistrationDeclined() {
        summit__Summit_Events_Registration__c invitation = createRegistration('Declined');

        System.runAs(invitee()) {
            Test.startTest();
            InvitationDeclineController declineCtrl = openDeclinePage(getLinkParameter(invitation));
            Assert.isTrue(declineCtrl.alreadyDeclined);
            declineCtrl.declineInvitation();
            Test.stopTest();
        }

        Assert.areEqual('Declined', getStatus(invitation.Id));
    }

    @IsTest
    static void registeredInviteeCannotDecline() {
        summit__Summit_Events_Registration__c registration = createRegistration('Registered');

        System.runAs(invitee()) {
            Test.startTest();
            InvitationDeclineController declineCtrl = openDeclinePage(getLinkParameter(registration));
            Assert.isTrue(declineCtrl.notDeclinable);
            Assert.isFalse(declineCtrl.canDecline);
            declineCtrl.declineInvitation();
            Test.stopTest();
        }

        Assert.areEqual('Registered', getStatus(registration.Id));
    }

    @IsTest
    static void statusChangedAfterPageLoadIsNotDeclined() {
        summit__Summit_Events_Registration__c invitation = createRegistration('Invited');
        User testUser = invitee();
        InvitationDeclineController declineCtrl;

        System.runAs(testUser) {
            declineCtrl = openDeclinePage(getLinkParameter(invitation));
            Assert.isTrue(declineCtrl.canDecline);
        }

        // The invitee completes registration in another tab before confirming the decline
        invitation.summit__Status__c = 'Registered';
        update as system invitation;

        System.runAs(testUser) {
            Test.startTest();
            declineCtrl.declineInvitation();
            Test.stopTest();
        }

        Assert.areEqual('Registered', getStatus(invitation.Id));
    }

    @IsTest
    static void tamperedLinkShowsNotFound() {
        summit__Summit_Events_Registration__c invitation = createRegistration('Invited');

        System.runAs(invitee()) {
            Test.startTest();
            InvitationDeclineController declineCtrl = openDeclinePage(getLinkParameter(invitation) + 'TAMPER');
            Assert.isTrue(declineCtrl.eventNotFound);
            Assert.isFalse(declineCtrl.canDecline);
            declineCtrl.declineInvitation();
            Test.stopTest();
        }

        Assert.areEqual('Invited', getStatus(invitation.Id));
    }

    @IsTest
    static void missingLinkShowsNotFound() {
        System.runAs(invitee()) {
            Test.startTest();
            InvitationDeclineController declineCtrl = openDeclinePage(null);
            Assert.isTrue(declineCtrl.eventNotFound);
            Assert.isFalse(declineCtrl.canDecline);
            Test.stopTest();
        }
    }

    @IsTest
    static void unknownTokenShowsNotFound() {
        summit__Summit_Events_Registration__c invitation = createRegistration('Invited');

        System.runAs(invitee()) {
            Test.startTest();
            InvitationDeclineController declineCtrl = openDeclinePage(newToken());
            Assert.isTrue(declineCtrl.eventNotFound);
            declineCtrl.declineInvitation();
            Test.stopTest();
        }

        Assert.areEqual('Invited', getStatus(invitation.Id));
    }

    // Tokens are lowercase hex and the hash lookup is case-sensitive
    @IsTest
    static void uppercasedTokenShowsNotFound() {
        summit__Summit_Events_Registration__c invitation = createRegistration('Invited');

        System.runAs(invitee()) {
            Test.startTest();
            Assert.isTrue(openDeclinePage(getLinkParameter(invitation).toUpperCase()).eventNotFound);
            Test.stopTest();
        }
    }

    // T09: a token only ever reaches its own Registration
    @IsTest
    static void tokenDeclinesOnlyItsOwnInvitation() {
        summit__Summit_Events_Registration__c thomas = createRegistration('Invited');
        summit__Summit_Events_Registration__c other = createRegistration('Invited');

        System.runAs(invitee()) {
            Test.startTest();
            InvitationDeclineController declineCtrl = openDeclinePage(getLinkParameter(thomas));
            Assert.areEqual(thomas.Id, declineCtrl.eventRegistration.Id);
            declineCtrl.declineInvitation();
            Test.stopTest();
        }

        Assert.areEqual('Declined', getStatus(thomas.Id));
        Assert.areEqual('Invited', getStatus(other.Id));
    }

    // US-09: optional decline reason and comment

    private static summit__Summit_Events_Registration__c getDecline(Id registrationId) {
        return [
            SELECT summit__Status__c, Decline_Reason__c, Decline_Comment__c
            FROM summit__Summit_Events_Registration__c
            WHERE Id = :registrationId
            WITH SYSTEM_MODE
        ];
    }

    private static summit__Summit_Events_Registration__c declineWith(String reason, String comment) {
        summit__Summit_Events_Registration__c invitation = createRegistration('Invited');

        System.runAs(invitee()) {
            Test.startTest();
            InvitationDeclineController declineCtrl = openDeclinePage(getLinkParameter(invitation));
            declineCtrl.declineReason = reason;
            declineCtrl.declineComment = comment;
            declineCtrl.declineInvitation();
            Test.stopTest();
        }
        return getDecline(invitation.Id);
    }

    @IsTest
    static void declineStoresReasonAndComment() {
        summit__Summit_Events_Registration__c declined = declineWith('Travelling', '  Abroad that week, good luck!  ');

        Assert.areEqual('Declined', declined.summit__Status__c);
        Assert.areEqual('Travelling', declined.Decline_Reason__c);
        Assert.areEqual('Abroad that week, good luck!', declined.Decline_Comment__c);
    }

    @IsTest
    static void declineWithoutReasonLeavesFieldsBlank() {
        summit__Summit_Events_Registration__c declined = declineWith('', '   ');

        Assert.areEqual('Declined', declined.summit__Status__c);
        Assert.isNull(declined.Decline_Reason__c);
        Assert.isNull(declined.Decline_Comment__c);
    }

    @IsTest
    static void unknownReasonIsDroppedButDeclineSucceeds() {
        summit__Summit_Events_Registration__c declined = declineWith('Tampered value', null);

        Assert.areEqual('Declined', declined.summit__Status__c);
        Assert.isNull(declined.Decline_Reason__c);
    }

    @IsTest
    static void longCommentIsCutToFieldLength() {
        Integer maxLength = Schema.SObjectType.summit__Summit_Events_Registration__c.fields.Decline_Comment__c.getLength();
        summit__Summit_Events_Registration__c declined = declineWith(null, 'x'.repeat(maxLength + 500));

        Assert.areEqual('Declined', declined.summit__Status__c);
        Assert.areEqual(maxLength, declined.Decline_Comment__c.length());
    }

    @IsTest
    static void repeatDeclineKeepsFirstReason() {
        summit__Summit_Events_Registration__c invitation = createRegistration('Declined');
        invitation.Decline_Reason__c = 'Other';
        invitation.Decline_Comment__c = 'First answer';
        update as system invitation;

        System.runAs(invitee()) {
            Test.startTest();
            InvitationDeclineController declineCtrl = openDeclinePage(getLinkParameter(invitation));
            declineCtrl.declineReason = 'Travelling';
            declineCtrl.declineComment = 'Second answer';
            declineCtrl.declineInvitation();
            Test.stopTest();
        }

        summit__Summit_Events_Registration__c declined = getDecline(invitation.Id);
        Assert.areEqual('Other', declined.Decline_Reason__c);
        Assert.areEqual('First answer', declined.Decline_Comment__c);
    }

    @IsTest
    static void registeredInviteeReasonIsNotStored() {
        summit__Summit_Events_Registration__c registration = createRegistration('Registered');

        System.runAs(invitee()) {
            Test.startTest();
            InvitationDeclineController declineCtrl = openDeclinePage(getLinkParameter(registration));
            declineCtrl.declineReason = 'Travelling';
            declineCtrl.declineInvitation();
            Test.stopTest();
        }

        summit__Summit_Events_Registration__c result = getDecline(registration.Id);
        Assert.areEqual('Registered', result.summit__Status__c);
        Assert.isNull(result.Decline_Reason__c);
    }

    @IsTest
    static void reasonOptionsStartWithPreferNotToSay() {
        summit__Summit_Events_Registration__c invitation = createRegistration('Invited');

        System.runAs(invitee()) {
            Test.startTest();
            List<SelectOption> options = openDeclinePage(getLinkParameter(invitation)).getDeclineReasonOptions();
            Test.stopTest();

            Assert.areEqual('', options[0].getValue());
            Assert.isTrue(options.size() > 1, 'The active Decline Reason values must be offered');
        }
    }
}
