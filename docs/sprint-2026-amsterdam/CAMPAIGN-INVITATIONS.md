# Campaign invitations: US-01 and US-02

Built in the Sprint sandbox by Bhuvana Narayana and Jelena Vladusic on 19 October 2026, then retrieved into source.

## Metadata

| Component | API name | Purpose |
| --- | --- | --- |
| Lookup on Campaign | `Campaign.Summit_Events_Instance__c` → `summit__Summit_Events_Instance__c` | US-01: links an invitation Campaign to an Event Instance. Delete constraint: Set Null. |
| Picklist on Contact | `Contact.Donor_Type__c` | US-02: audience segment. Restricted picklist. |
| Global Value Set | `Donore_Type` (label "Donore Type") | Values for `Donor_Type__c`: Top Donor, Ambassador, VIP. |
| Permission set | `Summit_Events_Invite_Manager` | Edit access to the two fields above, for the person creating and sending invites. |
| Report | `unfiled$public/Contacts_to_add_to_Gala_Campaign_X76` ("Contacts to add to Gala Campaign") | Contacts whose Donor Type is Top Donor, Ambassador or VIP. |

## How to add the audience to a Campaign

1. Create the invitation Campaign (in the sandbox: **Annual Gala 2026 Invitations**) and set **Summit Events Instance** to the event.
2. Run the report **Contacts to add to Gala Campaign**.
3. Click **Add to Campaign**, choose the invitation Campaign, and set the member status to **Sent**.

Salesforce's standard **Add to Campaign** step skips Contacts that are already members, so running it again does not create duplicate Campaign Members (US-02 AC 3).

## Known gaps and open questions

- **Cardinality is not enforced (US-01 AC 3).** A lookup on Campaign means each Campaign can point at only one Instance, but nothing stops several Campaigns from pointing at the same Instance. The team has not yet decided whether that should be allowed.
- **Report date filter.** The report keeps the default filter *Created Date ≥ 2026-10-12*. In a real org this would leave out donors created before that date, so remove the filter or make it relative.
- **Leads (US-02 AC 2).** `Donor_Type__c` exists on Contact only, so the report does not pick up Leads.
- **Global Value Set name.** `Donore_Type` contains a typo. Renaming it later is a metadata change, so fix it before the set is packaged or used in other orgs.
- **Campaign Member status model.** "Sent" is the only status used so far. The full status list and the policy for removed members (US-02 AC 5) are still open.

## Sandbox test data (not in source)

Test data only, not part of this branch: about 880 Contacts tagged with a Donor Type (629 Top Donor, 201 Ambassador, 51 VIP), and 860 Campaign Members with status Sent on Annual Gala 2026 Invitations. That is more than the 600 in the scenario, which is useful for bulk testing.
