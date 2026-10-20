/**
 * Issues the public invitation link for invitation Registrations (Sprint board US-06, US-14).
 *
 * The link carries a random 256-bit token, never a Salesforce record Id. The SHA-256 hash of the token is stored
 * in the unique Public_Invitation_Token_Hash__c so the page that receives the link can look the Registration up
 * by hash. Links are issued once and then reused; a half-written invitation is never reissued.
 *
 * getOrCreateLinks runs as the internal user who sends the invitations: sharing, object and field permissions all
 * apply. getOrCreateLinksForAutomation is for trusted automation (SummitInvitationQueueable): the invitation fields
 * are read-only for users (DEC-004), so it reads and writes in system mode without sharing. Never call it from
 * guest-facing code.
 */
public with sharing class SummitEventsInvitationService {

    public class InvitationException extends Exception {}

    private static final Integer TOKEN_HEX_LENGTH = 64;
    private static final Integer LINK_FIELD_LENGTH = 255;

    private static final List<String> INVITATION_FIELDS = new List<String>{
        'Public_Invitation_Link__c',
        'Public_Invitation_Token_Hash__c',
        'Public_Invitation_Issued_At__c'
    };

    @TestVisible
    private static String baseUrl = System.Label.Summit_Events_Public_Invitation_URL;

    public static String getOrCreateLink(Id registrationId) {

        if (registrationId == null) {
            throw new InvitationException(
                'Registration ID is required.'
            );
        }

        return getOrCreateLinks(new Set<Id>{ registrationId }).get(registrationId);
    }

    /**
     * Bulk version for a whole invitation audience: one query and one update for all Registrations.
     * All or nothing: if any Registration cannot get a link, nothing is saved and the exception names it.
     */
    public static Map<Id, String> getOrCreateLinks(Set<Id> registrationIds) {

        checkRegistrationIds(registrationIds);
        checkPermissions();
        checkBaseUrl();

        // Lock the Registrations to prevent concurrent generation.
        List<summit__Summit_Events_Registration__c> registrations = [
            SELECT Id,
                   Public_Invitation_Link__c,
                   Public_Invitation_Token_Hash__c,
                   Public_Invitation_Issued_At__c
            FROM summit__Summit_Events_Registration__c
            WHERE Id IN :registrationIds
            WITH USER_MODE
            FOR UPDATE
        ];

        return issueLinks(registrationIds, registrations, null);
    }

    /**
     * Same as getOrCreateLinks, for trusted automation that runs as a user without edit access to the invitation
     * fields. Same all-or-nothing rule.
     */
    public static Map<Id, String> getOrCreateLinksForAutomation(Set<Id> registrationIds) {

        checkRegistrationIds(registrationIds);
        checkBaseUrl();

        SystemAccess systemAccess = new SystemAccess();
        return issueLinks(registrationIds, systemAccess.lockRegistrations(registrationIds), systemAccess);
    }

    private static void checkRegistrationIds(Set<Id> registrationIds) {

        if (registrationIds == null ||
            registrationIds.isEmpty() ||
            registrationIds.contains(null)) {
            throw new InvitationException(
                'Registration ID is required.'
            );
        }
    }

    private static void checkBaseUrl() {

        // Validate the public URL from the Custom Label.
        if (String.isBlank(baseUrl) ||
            !baseUrl.startsWith('https://') ||
            baseUrl.contains('?') ||
            baseUrl.contains('#')) {
            throw new InvitationException(
                'Invalid invitation URL configuration.'
            );
        }

        // Every token has the same length, so one check covers every link.
        if ((baseUrl + '?t=').length() + TOKEN_HEX_LENGTH > LINK_FIELD_LENGTH) {
            throw new InvitationException(
                'Invitation URL exceeds field length.'
            );
        }
    }

    // systemAccess is null for the user-mode path
    private static Map<Id, String> issueLinks(
        Set<Id> registrationIds,
        List<summit__Summit_Events_Registration__c> registrations,
        SystemAccess systemAccess
    ) {

        // Missing and not shared with this user look the same, so neither is revealed.
        if (registrations.size() != registrationIds.size()) {
            throw new InvitationException(
                'Registration unavailable.'
            );
        }

        Map<Id, String> links = new Map<Id, String>();
        List<summit__Summit_Events_Registration__c> registrationsToUpdate =
            new List<summit__Summit_Events_Registration__c>();

        for (summit__Summit_Events_Registration__c registration : registrations) {

            // Reuse the existing invitation link.
            if (
                String.isNotBlank(
                    registration.Public_Invitation_Link__c
                ) &&
                String.isNotBlank(
                    registration.Public_Invitation_Token_Hash__c
                )
            ) {
                links.put(registration.Id, registration.Public_Invitation_Link__c);
                continue;
            }

            // Prevent replacement of incomplete credentials.
            if (
                String.isNotBlank(
                    registration.Public_Invitation_Link__c
                ) ||
                String.isNotBlank(
                    registration.Public_Invitation_Token_Hash__c
                )
            ) {
                throw new InvitationException(
                    'Incomplete invitation credentials: ' + registration.Id
                );
            }

            // Generate a cryptographically random 256-bit token.
            String token = EncodingUtil.convertToHex(
                Crypto.generateAesKey(256)
            );

            // Build the public URL without Salesforce record IDs.
            String invitationUrl = baseUrl + '?t=' + token;

            // Populate the custom invitation fields; only the hash is used for lookup.
            registrationsToUpdate.add(new summit__Summit_Events_Registration__c(
                Id = registration.Id,
                Public_Invitation_Link__c = invitationUrl,
                Public_Invitation_Token_Hash__c = hashToken(token),
                Public_Invitation_Issued_At__c = System.now()
            ));
            links.put(registration.Id, invitationUrl);
        }

        // Save the Registrations.
        if (!registrationsToUpdate.isEmpty()) {
            if (systemAccess == null) {
                update as user registrationsToUpdate;
            } else {
                systemAccess.save(registrationsToUpdate);
            }
        }

        return links;
    }

    // Duplicate detection in SummitInvitationQueueable adopts Registrations the running user may not see
    private without sharing class SystemAccess {

        public List<summit__Summit_Events_Registration__c> lockRegistrations(Set<Id> registrationIds) {
            return [
                SELECT Id,
                       Public_Invitation_Link__c,
                       Public_Invitation_Token_Hash__c,
                       Public_Invitation_Issued_At__c
                FROM summit__Summit_Events_Registration__c
                WHERE Id IN :registrationIds
                WITH SYSTEM_MODE
                FOR UPDATE
            ];
        }

        public void save(List<summit__Summit_Events_Registration__c> registrations) {
            Database.update(registrations, true, AccessLevel.SYSTEM_MODE);
        }
    }

    // Also needed by the page that resolves an incoming token.
    public static String hashToken(String token) {
        return EncodingUtil.convertToHex(
            Crypto.generateDigest(
                'SHA-256',
                Blob.valueOf(token)
            )
        );
    }

    // Fails early with a clear message; the user-mode query and update enforce the same rules again.
    private static void checkPermissions() {

        Schema.DescribeSObjectResult objectInfo =
            summit__Summit_Events_Registration__c.SObjectType.getDescribe();

        if (!objectInfo.isAccessible() ||
            !objectInfo.isUpdateable()) {
            throw new InvitationException(
                'Insufficient permissions.'
            );
        }

        Map<String, Schema.SObjectField> fields =
            objectInfo.fields.getMap();

        for (String fieldName : INVITATION_FIELDS) {
            Schema.SObjectField fieldToken = fields.get(fieldName);

            if (fieldToken == null ||
                !fieldToken.getDescribe().isAccessible() ||
                !fieldToken.getDescribe().isUpdateable()) {
                throw new InvitationException(
                    'Insufficient field permissions.'
                );
            }
        }
    }
}
