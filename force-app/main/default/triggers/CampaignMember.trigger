
trigger CampaignMember on CampaignMember (after insert, after update) {
    Set<Id> memberIdsToProcess = new Set<Id>();

    for (CampaignMember member : Trigger.new) {
        System.debug(LoggingLevel.ERROR,'TRIGGER CHECK' + ' | isInsert=' + Trigger.isInsert + ' | Id=' + member.Id + ' | Status=[' + member.Status + ']');
        Boolean isInvited = member.Status == 'Invited';
        System.debug(LoggingLevel.ERROR,'TRIGGER isInvited=' + isInvited);

        if (Trigger.isInsert && isInvited) {
            memberIdsToProcess.add(member.Id);
        } else if (Trigger.isUpdate && isInvited && Trigger.oldMap.get(member.Id).Status != 'Invited') {
            memberIdsToProcess.add(member.Id);
        }
    }

    if (!memberIdsToProcess.isEmpty()) {
        System.enqueueJob(new SummitInvitationQueueable(memberIdsToProcess));
    }
    System.debug(LoggingLevel.ERROR,'TRIGGER MEMBER IDS TO PROCESS=' + memberIdsToProcess);

    if (!memberIdsToProcess.isEmpty()) {
        System.debug(LoggingLevel.ERROR,'ENQUEUEING SUMMIT QUEUEABLE');
        System.enqueueJob(new SummitInvitationQueueable(memberIdsToProcess));
    }
}
