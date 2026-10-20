@IsTest
private class InvitationRegisterControllerTest {
    private static final String TOKEN = 'a1b2c3d4'.repeat(8);

    @TestSetup
    static void setup() {
        summit__Summit_Events_Settings__c settings = summit__Summit_Events_Settings__c.getOrgDefaults();
        settings.summit__Cookie_Encryption_Key__c = EncodingUtil.base64Encode(Crypto.generateAesKey(256)).substring(0, 32);
        upsert as system settings;

        summit__Summit_Events__c evt = new summit__Summit_Events__c(Name = 'Invitation Register Test Gala', summit__Event_Name__c = 'Invitation Register Test Gala');
        insert evt;
        insert new summit__Summit_Events_Instance__c(summit__Event__c = evt.Id, summit__Instance_Title__c = 'Invitation Register Test Gala 2026');

        insert new Contact(
            FirstName = 'Maria',
            LastName = 'Invregtest',
            Email = 'maria.invregtest@example.invalid',
            HomePhone = '+31 20 000 0001',
            MobilePhone = '+31 6 0000 0001',
            MailingStreet = 'Herengracht 1',
            MailingCity = 'Amsterdam',
            MailingPostalCode = '1015 BA',
            MailingCountry = 'Atlantis'
        );
        insert new Lead(FirstName = 'Lea', LastName = 'Invregtest', Company = 'Invregtest Foundation', Email = 'lea.invregtest@example.invalid', Phone = '+31 20 000 0002');
    }

    private static summit__Summit_Events_Registration__c createRegistration(String status, Id contactId, Id leadId) {
        summit__Summit_Events_Instance__c instance = [
            SELECT Id, summit__Event__c
            FROM summit__Summit_Events_Instance__c
            WHERE summit__Instance_Title__c = 'Invitation Register Test Gala 2026'
            LIMIT 1
        ];
        summit__Summit_Events_Registration__c registration = new summit__Summit_Events_Registration__c(
            summit__Event_Instance__c = instance.Id,
            summit__Event__c = instance.summit__Event__c,
            summit__Contact__c = contactId,
            summit__Lead__c = leadId,
            summit__Status__c = status,
            Public_Invitation_Token_Hash__c = SummitEventsInvitationService.hashToken(TOKEN)
        );
        insert as system registration;
        return registration;
    }

    private static Id mariaId() {
        return [SELECT Id FROM Contact WHERE LastName = 'Invregtest' LIMIT 1].Id;
    }

    private static Id leaId() {
        return [SELECT Id FROM Lead WHERE LastName = 'Invregtest' LIMIT 1].Id;
    }

    private static InvitationRegisterController openPage(String token) {
        Test.setCurrentPage(Page.InvitationRegister);
        if (token != null) {
            ApexPages.currentPage().getParameters().put('t', token);
        }
        return new InvitationRegisterController();
    }

    private static summit__Summit_Events_Registration__c reload(Id registrationId) {
        return [
            SELECT summit__Status__c, summit__Registrant_First_Name__c, summit__Registrant_Last_Name__c, summit__Registrant_Email__c,
                summit__Registrant_Phone__c, summit__Registrant_Mobile_Phone__c, summit__Registrant_Street_1__c, summit__Registrant_City__c,
                summit__Registrant_Postal_Code__c, summit__Registrant_Zip__c, summit__Registrant_Country__c, summit__Registrant_Country_Text__c,
                summit__Registrant_Company_Organization__c
            FROM summit__Summit_Events_Registration__c
            WHERE Id = :registrationId
            WITH SYSTEM_MODE
        ];
    }

    // Decrypts the cookie the way SummitEventsShared.getDecryptCookie does
    private static Map<String, Object> decryptIssuedCookie() {
        Assert.isNotNull(InvitationRegisterController.issuedCookieValue, 'A cookie was issued');
        String key = [SELECT summit__Cookie_Encryption_Key__c FROM summit__Summit_Events_Settings__c WHERE SetupOwnerId = :UserInfo.getOrganizationId() WITH SYSTEM_MODE].summit__Cookie_Encryption_Key__c;
        Blob decrypted = Crypto.decryptWithManagedIV(
            'AES256',
            Blob.valueOf(key),
            EncodingUtil.base64Decode(EncodingUtil.urlDecode(InvitationRegisterController.issuedCookieValue, 'UTF-8'))
        );
        return (Map<String, Object>) JSON.deserializeUntyped(decrypted.toString());
    }

    // The Summit Events site guest user: owns none of the records and has only the site's guest permissions.
    // Falls back to the running user in an org without that site.
    private static User invitee() {
        List<Site> sites = [SELECT GuestUserId FROM Site WHERE Name = 'Summit_Events' LIMIT 1];
        return new User(Id = sites.isEmpty() ? UserInfo.getUserId() : sites[0].GuestUserId);
    }

    @IsTest
    static void validTokenShowsInvitationWithoutChangingAnything() {
        summit__Summit_Events_Registration__c registration = createRegistration('Invited', mariaId(), null);

        InvitationRegisterController controller = openPage(TOKEN);

        Assert.isFalse(controller.invitationNotFound);
        Assert.isFalse(controller.alreadyRegistered);
        Assert.areEqual('Invitation Register Test Gala', controller.eventPage.summit__Event_Name__c);
        Assert.areEqual('summit__GeneralSLDS', controller.templateSelected);
        Assert.isNull(reload(registration.Id).summit__Registrant_First_Name__c, 'Opening the link does not prefill');
        Assert.isNull(InvitationRegisterController.issuedCookieValue, 'Opening the link does not set the cookie');
    }

    @IsTest
    static void badTokensFindNothing() {
        createRegistration('Invited', mariaId(), null);

        for (String token : new List<String>{ null, '', 'not-a-token', TOKEN.toUpperCase(), TOKEN.left(63), 'f'.repeat(64) }) {
            InvitationRegisterController controller = openPage(token);
            Assert.isTrue(controller.invitationNotFound, 'Not found for ' + token);
            Assert.isNull(controller.continueRegistration());
        }
        Assert.isNull(InvitationRegisterController.issuedCookieValue);
    }

    @IsTest
    static void continueSetsPackageCookieAndOpensPackageRegisterPage() {
        summit__Summit_Events_Registration__c registration = createRegistration('Invited', mariaId(), null);
        InvitationRegisterController controller = openPage(TOKEN);

        Test.startTest();
        PageReference next = controller.continueRegistration();
        Test.stopTest();

        Assert.isNotNull(next);
        Assert.isTrue(next.getUrl().containsIgnoreCase('summit__SummitEventsRegister'), next.getUrl());
        Assert.isFalse(next.getUrl().contains(String.valueOf(registration.Id).left(15)), 'The URL carries no record Id');

        Map<String, Object> cookie = decryptIssuedCookie();
        Assert.areEqual(String.valueOf(registration.Id), cookie.get('registrationId'));
        Assert.areEqual(String.valueOf(registration.summit__Event_Instance__c), cookie.get('instanceId'));
        Assert.areEqual(String.valueOf(registration.summit__Event__c), cookie.get('eventId'));
        Assert.areEqual('true', cookie.get('valid'), 'Only valid=true makes the package register page resume the Registration');
        Assert.areEqual('', cookie.get('audience'));
        Assert.isNotNull(cookie.get('dt'));
    }

    @IsTest
    static void continuePrefillsFromContact() {
        summit__Summit_Events_Registration__c registration = createRegistration('Invited', mariaId(), null);
        String defaultCountry = reload(registration.Id).summit__Registrant_Country__c;

        System.runAs(invitee()) {
            Assert.isNotNull(openPage(TOKEN).continueRegistration(), String.valueOf(ApexPages.getMessages()));
        }

        summit__Summit_Events_Registration__c saved = reload(registration.Id);
        Assert.areEqual('Maria', saved.summit__Registrant_First_Name__c);
        Assert.areEqual('Invregtest', saved.summit__Registrant_Last_Name__c);
        Assert.areEqual('maria.invregtest@example.invalid', saved.summit__Registrant_Email__c);
        Assert.areEqual('+31 20 000 0001', saved.summit__Registrant_Phone__c);
        Assert.areEqual('+31 6 0000 0001', saved.summit__Registrant_Mobile_Phone__c);
        Assert.areEqual('Herengracht 1', saved.summit__Registrant_Street_1__c);
        Assert.areEqual('Amsterdam', saved.summit__Registrant_City__c);
        Assert.areEqual('1015 BA', saved.summit__Registrant_Postal_Code__c);
        Assert.areEqual('1015 BA', saved.summit__Registrant_Zip__c);
        // A Country picklist default counts as a value and is kept; otherwise the unknown country goes to the
        // free-text field, as in the package
        Assert.areEqual(defaultCountry, saved.summit__Registrant_Country__c);
        Assert.areEqual(defaultCountry == null ? 'Atlantis' : null, saved.summit__Registrant_Country_Text__c);
        Assert.isNotNull(InvitationRegisterController.issuedCookieValue);
    }

    @IsTest
    static void continuePrefillsFromLead() {
        summit__Summit_Events_Registration__c registration = createRegistration('Invited', null, leaId());

        System.runAs(invitee()) {
            Assert.isNotNull(openPage(TOKEN).continueRegistration(), String.valueOf(ApexPages.getMessages()));
        }

        summit__Summit_Events_Registration__c saved = reload(registration.Id);
        Assert.areEqual('Lea', saved.summit__Registrant_First_Name__c);
        Assert.areEqual('lea.invregtest@example.invalid', saved.summit__Registrant_Email__c);
        Assert.areEqual('+31 20 000 0002', saved.summit__Registrant_Phone__c);
        Assert.areEqual('Invregtest Foundation', saved.summit__Registrant_Company_Organization__c);
    }

    @IsTest
    static void matchingCountryUsesPicklist() {
        List<Schema.PicklistEntry> countries = summit__Summit_Events_Registration__c.summit__Registrant_Country__c.getDescribe().getPicklistValues();
        if (countries.isEmpty()) {
            return;
        }
        Contact maria = new Contact(Id = mariaId(), MailingCountry = countries[0].getValue().toUpperCase());
        update as system maria;
        summit__Summit_Events_Registration__c registration = createRegistration('Invited', maria.Id, null);

        openPage(TOKEN).continueRegistration();

        summit__Summit_Events_Registration__c saved = reload(registration.Id);
        Assert.areEqual(countries[0].getValue(), saved.summit__Registrant_Country__c);
        Assert.isNull(saved.summit__Registrant_Country_Text__c);
    }

    @IsTest
    static void returningInviteeKeepsTheirChanges() {
        summit__Summit_Events_Registration__c registration = createRegistration('Registered', mariaId(), null);
        // What the invitee entered on an earlier visit, through the package page
        registration.summit__Registrant_Email__c = 'maria.new@example.invalid';
        registration.summit__Registrant_City__c = 'Utrecht';
        update as system registration;

        InvitationRegisterController controller = openPage(TOKEN);
        Assert.isTrue(controller.alreadyRegistered);
        controller.continueRegistration();

        summit__Summit_Events_Registration__c saved = reload(registration.Id);
        Assert.areEqual('maria.new@example.invalid', saved.summit__Registrant_Email__c);
        Assert.areEqual('Utrecht', saved.summit__Registrant_City__c);
        Assert.areEqual('Maria', saved.summit__Registrant_First_Name__c, 'Blank fields are still filled');
        Assert.areEqual('Registered', saved.summit__Status__c, 'The status is left to the package flow');
        Assert.areEqual(String.valueOf(registration.Id), decryptIssuedCookie().get('registrationId'));
    }

    @IsTest
    static void everyVisitIssuesAFreshCookie() {
        createRegistration('Registered', mariaId(), null);

        openPage(TOKEN).continueRegistration();
        String first = InvitationRegisterController.issuedCookieValue;
        openPage(TOKEN).continueRegistration();

        Assert.areNotEqual(first, InvitationRegisterController.issuedCookieValue, 'Managed IV: each cookie is encrypted afresh');
        Assert.areEqual('true', decryptIssuedCookie().get('valid'));
    }

    @IsTest
    static void registrationWithoutPersonStillOpens() {
        summit__Summit_Events_Registration__c registration = createRegistration('Invited', null, null);

        Assert.isNotNull(openPage(TOKEN).continueRegistration());
        Assert.isNull(reload(registration.Id).summit__Registrant_First_Name__c);
    }

    @IsTest
    static void deletedRegistrationAfterLoadingShowsMessage() {
        summit__Summit_Events_Registration__c registration = createRegistration('Invited', mariaId(), null);
        InvitationRegisterController controller = openPage(TOKEN);
        delete registration;

        Assert.isNull(controller.continueRegistration());
        Assert.isTrue(ApexPages.hasMessages(ApexPages.Severity.WARNING));
        Assert.isNull(InvitationRegisterController.issuedCookieValue);
    }

    @IsTest
    static void missingEncryptionKeyShowsMessage() {
        createRegistration('Invited', mariaId(), null);
        summit__Summit_Events_Settings__c settings = summit__Summit_Events_Settings__c.getOrgDefaults();
        settings.summit__Cookie_Encryption_Key__c = null;
        update as system settings;

        Assert.isNull(openPage(TOKEN).continueRegistration());
        Assert.isTrue(ApexPages.hasMessages(ApexPages.Severity.WARNING));
    }

    @IsTest
    static void templateNamesFollowThePackage() {
        // The org's Template picklist may hold only GeneralSLDS, so the mapping is tested directly
        Assert.areEqual('summit__GeneralSLDS', InvitationRegisterController.getTemplate(null));
        Assert.areEqual('summit__CastorTemplate2017', InvitationRegisterController.getTemplate('CastorTemplate2017'));
        Assert.areEqual('MyOrgTemplate', InvitationRegisterController.getTemplate('MyOrgTemplate'));
    }
}
