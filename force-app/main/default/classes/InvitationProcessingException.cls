/**
 * Raised for non-recoverable invitation processing errors (invalid input or configuration).
 * Duplicate registrations are an expected outcome and are reported through
 * InvitationRegistrationDedupe.Result instead of this exception.
 */
public with sharing class InvitationProcessingException extends Exception {
}
