/**
 * Controller for the InvitationRegister page (board US-06, US-14): where the public invitation link issued by
 * SummitEventsInvitationService (?t=<token>) lands.
 *
 * The page does not copy the package registration form. It finds the Registration by the token's hash and hands the
 * invitee to the package's own SummitEventsRegister page, with the package's encrypted SummitEvents cookie pointing at
 * that Registration. The package page then shows the saved answers, lets the invitee change them, and updates the same
 * Registration through the rest of the package flow (questions, appointments, fees, confirmation). Every visit with the
 * link does this again, so a returning invitee always sees, and can change, what they entered before.
 *
 * - Loading the page changes nothing: email link scanners open links. The Continue button (a POST) fills blank
 *   registrant fields from the Contact or Lead, sets the cookie and redirects.
 * - The redirect starts on this site, so the browser sends the SameSite=Strict package cookie with it.
 * - The cookie mirrors SummitEventsShared.createEncryptedCookie, which is not callable from outside the package
 *   (InvitationLink mirrors the same format). valid=true makes the package resume the Registration whatever its
 *   status; the package's own cookie uses valid=false after confirmation, which the register page ignores.
 *   If a package upgrade changes that format, these links stop resuming: after an upgrade, test a link end to end.
 */
public with sharing class InvitationRegisterController {
    public static final String COOKIE_NAME = 'SummitEvents';
    // Statuses where the invitee has already completed the package flow
    private static final Set<String> COMPLETED_STATUSES = new Set<String>{ 'Registered', 'Confirmed' };
    // Templates shipped in the package; any other value is a template page in this org
    private static final Set<String> PACKAGE_TEMPLATES = new Set<String>{ 'GeneralSLDS', 'crowncollege2020', 'OPUSTemplate2018', 'CastorTemplate2017' };
    private static final Pattern TOKEN_FORMAT = Pattern.compile('[0-9a-f]{64}');

    public summit__Summit_Events_Registration__c eventRegistration { get; private set; }
    public summit__Summit_Events__c eventPage { get; private set; }
    public String templateSelected { get; private set; }
    public Boolean invitationNotFound { get; private set; }
    public Boolean alreadyRegistered { get; private set; }
    private Id registrationId;

    @TestVisible
    private static String issuedCookieValue;

    public InvitationRegisterController() {
        invitationNotFound = true;
        alreadyRegistered = false;
        eventRegistration = new summit__Summit_Events_Registration__c();
        eventPage = new summit__Summit_Events__c();
        templateSelected = getTemplate(null);

        String token = ApexPages.currentPage().getParameters().get('t');
        if (String.isBlank(token) || !TOKEN_FORMAT.matcher(token).matches()) {
            return;
        }
        RegistrationAccess access = new RegistrationAccess();
        summit__Summit_Events_Registration__c registration = access.getRegistrationByTokenHash(SummitEventsInvitationService.hashToken(token));
        if (registration == null) {
            return;
        }

        eventRegistration = registration;
        eventPage = access.getEvent(registration.summit__Event__c);
        registrationId = registration.Id;
        templateSelected = getTemplate(eventPage.summit__Template__c);
        invitationNotFound = false;
        alreadyRegistered = COMPLETED_STATUSES.contains(registration.summit__Status__c);
    }

    public PageReference continueRegistration() {
        if (registrationId == null) {
            return null;
        }
        RegistrationAccess access = new RegistrationAccess();
        summit__Summit_Events_Registration__c registration = access.getRegistrationById(registrationId);
        String key = access.getCookieKey();
        if (registration == null || String.isBlank(key)) {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.WARNING, 'We could not open your registration. Please try again or contact the event organizer.'));
            return null;
        }

        if (prefillFromPerson(registration, access) && !access.updateRegistration(registration)) {
            ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.WARNING, 'We could not open your registration. Please try again or contact the event organizer.'));
            return null;
        }

        setPackageCookie(registration, key);
        PageReference registerPage = Page.summit__SummitEventsRegister;
        registerPage.setRedirect(true);
        return registerPage;
    }

    /**
     * Copies the Contact's (or else the Lead's) details into blank registrant fields, following the package's own
     * mapping for logged-in users (SummitEventsRegisterController.mapContactToRegistration). Never overwrites what is
     * already on the Registration, so a returning invitee keeps their own changes. Returns true if anything changed.
     */
    @TestVisible
    private static Boolean prefillFromPerson(summit__Summit_Events_Registration__c registration, RegistrationAccess access) {
        Map<String, Object> values = new Map<String, Object>();
        String country;
        if (registration.summit__Contact__c != null) {
            Contact person = access.getContact(registration.summit__Contact__c);
            if (person != null) {
                values.put('summit__Registrant_First_Name__c', person.FirstName);
                values.put('summit__Registrant_Last_Name__c', person.LastName);
                values.put('summit__Registrant_Email__c', person.Email);
                values.put('summit__Registrant_Phone__c', String.isNotBlank(person.HomePhone) ? person.HomePhone : person.Phone);
                values.put('summit__Registrant_Mobile_Phone__c', person.MobilePhone);
                values.put('summit__Registrant_Street_1__c', person.MailingStreet);
                values.put('summit__Registrant_City__c', person.MailingCity);
                values.put('summit__Registrant_State__c', person.MailingState);
                values.put('summit__Registrant_Postal_Code__c', person.MailingPostalCode);
                values.put('summit__Registrant_Zip__c', person.MailingPostalCode);
                country = person.MailingCountry;
            }
        } else if (registration.summit__Lead__c != null) {
            Lead person = access.getLead(registration.summit__Lead__c);
            if (person != null) {
                values.put('summit__Registrant_First_Name__c', person.FirstName);
                values.put('summit__Registrant_Last_Name__c', person.LastName);
                values.put('summit__Registrant_Email__c', person.Email);
                values.put('summit__Registrant_Phone__c', person.Phone);
                values.put('summit__Registrant_Mobile_Phone__c', person.MobilePhone);
                values.put('summit__Registrant_Street_1__c', person.Street);
                values.put('summit__Registrant_City__c', person.City);
                values.put('summit__Registrant_State__c', person.State);
                values.put('summit__Registrant_Postal_Code__c', person.PostalCode);
                values.put('summit__Registrant_Zip__c', person.PostalCode);
                values.put('summit__Registrant_Company_Organization__c', person.Company);
                country = person.Country;
            }
        }

        // Country is a picklist; a value that is not in it goes to the free-text field, as the package does
        if (String.isNotBlank(country) && registration.summit__Registrant_Country__c == null && registration.summit__Registrant_Country_Text__c == null) {
            String matchedCountry = matchPicklistValue(summit__Summit_Events_Registration__c.summit__Registrant_Country__c, country);
            if (matchedCountry != null) {
                values.put('summit__Registrant_Country__c', matchedCountry);
            } else {
                values.put('summit__Registrant_Country_Text__c', country);
            }
        }

        Boolean changed = false;
        Map<String, Schema.SObjectField> fields = summit__Summit_Events_Registration__c.SObjectType.getDescribe().fields.getMap();
        for (String fieldName : values.keySet()) {
            String value = (String) values.get(fieldName);
            if (String.isBlank(value) || registration.get(fieldName) != null) {
                continue;
            }
            Integer maxLength = fields.get(fieldName).getDescribe().getLength();
            registration.put(fieldName, maxLength > 0 ? value.left(maxLength) : value);
            changed = true;
        }
        return changed;
    }

    private static String matchPicklistValue(Schema.SObjectField field, String value) {
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue().equalsIgnoreCase(value)) {
                return entry.getValue();
            }
        }
        return null;
    }

    // Same JSON keys and encryption as SummitEventsShared.createEncryptedCookieWithNow
    private static void setPackageCookie(summit__Summit_Events_Registration__c registration, String key) {
        Map<String, String> payload = new Map<String, String>{
            'audience' => '',
            'instanceId' => registration.summit__Event_Instance__c,
            'eventId' => registration.summit__Event__c,
            'registrationId' => registration.Id,
            'dt' => String.valueOf(Datetime.now()),
            'valid' => 'true'
        };
        Blob encrypted = Crypto.encryptWithManagedIV('AES256', Blob.valueOf(key), Blob.valueOf(JSON.serialize(payload)));
        issuedCookieValue = EncodingUtil.urlEncode(EncodingUtil.base64Encode(encrypted), 'UTF-8');
        ApexPages.currentPage().setCookies(new List<Cookie>{ new Cookie(COOKIE_NAME, issuedCookieValue, null, -1, true, 'Strict') });
    }

    // Mirrors the package's SummitEventsShared.getTemplate, which is not callable from outside the package
    @TestVisible
    private static String getTemplate(String templateName) {
        if (String.isBlank(templateName)) {
            return 'summit__GeneralSLDS';
        }
        return PACKAGE_TEMPLATES.contains(templateName) ? 'summit__' + templateName : templateName;
    }

    /**
     * The guest user does not own the Registration, its Contact or its Lead, so these reads and the prefill update
     * run without sharing and in system mode. The caller has already proved access with the token; only blank
     * registrant fields are written.
     */
    @TestVisible
    private without sharing class RegistrationAccess {

        // No user has field access to the key, and at API 68.0 getOrgDefaults() returns it blank without access
        public String getCookieKey() {
            List<summit__Summit_Events_Settings__c> settings = [
                SELECT summit__Cookie_Encryption_Key__c
                FROM summit__Summit_Events_Settings__c
                WHERE SetupOwnerId = :UserInfo.getOrganizationId()
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            return settings.isEmpty() ? null : settings[0].summit__Cookie_Encryption_Key__c;
        }

        public summit__Summit_Events_Registration__c getRegistrationByTokenHash(String tokenHash) {
            List<summit__Summit_Events_Registration__c> registrations = [
                SELECT Id, summit__Status__c, summit__Event__c, summit__Event_Instance_Title__c, summit__Event_Instance_Date_Time_Formatted__c
                FROM summit__Summit_Events_Registration__c
                WHERE Public_Invitation_Token_Hash__c = :tokenHash
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            return registrations.isEmpty() ? null : registrations[0];
        }

        public summit__Summit_Events_Registration__c getRegistrationById(Id regId) {
            List<summit__Summit_Events_Registration__c> registrations = [
                SELECT Id, summit__Event__c, summit__Event_Instance__c, summit__Contact__c, summit__Lead__c,
                    summit__Registrant_First_Name__c, summit__Registrant_Last_Name__c, summit__Registrant_Email__c,
                    summit__Registrant_Phone__c, summit__Registrant_Mobile_Phone__c, summit__Registrant_Street_1__c,
                    summit__Registrant_City__c, summit__Registrant_State__c, summit__Registrant_Postal_Code__c,
                    summit__Registrant_Zip__c, summit__Registrant_Country__c, summit__Registrant_Country_Text__c,
                    summit__Registrant_Company_Organization__c
                FROM summit__Summit_Events_Registration__c
                WHERE Id = :regId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            return registrations.isEmpty() ? null : registrations[0];
        }

        public summit__Summit_Events__c getEvent(Id eventId) {
            List<summit__Summit_Events__c> events = [
                SELECT Id, summit__Event_Name__c, summit__Event_description__c, summit__Event_Footer__c, summit__Template__c,
                    summit__Event_Home_Link_URL__c, summit__Event_Home_Link_Title__c, summit__Audience__c
                FROM summit__Summit_Events__c
                WHERE Id = :eventId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            return events.isEmpty() ? new summit__Summit_Events__c() : events[0];
        }

        public Contact getContact(Id contactId) {
            List<Contact> contacts = [
                SELECT FirstName, LastName, Email, Phone, HomePhone, MobilePhone,
                    MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry
                FROM Contact
                WHERE Id = :contactId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            return contacts.isEmpty() ? null : contacts[0];
        }

        public Lead getLead(Id leadId) {
            List<Lead> leads = [
                SELECT FirstName, LastName, Email, Phone, MobilePhone, Company, Street, City, State, PostalCode, Country
                FROM Lead
                WHERE Id = :leadId
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            return leads.isEmpty() ? null : leads[0];
        }

        public Boolean updateRegistration(summit__Summit_Events_Registration__c registration) {
            Database.SaveResult result = Database.update(registration, false, AccessLevel.SYSTEM_MODE);
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Invitation prefill failed for ' + registration.Id + ': ' + result.getErrors());
            }
            return result.isSuccess();
        }
    }
}
