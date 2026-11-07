#import "HPHaloCareerStatsIntegration.h"
#import "HPCareerStatsStore.h"
#import "HPHaloProgressStore.h"

void HPHaloCareerStatsConfigure(NSURL *saveRootURL, HPHaloProgressStore *progressStore)
{
    __weak HPHaloProgressStore *weakStore = progressStore;
    HPCareerStatsSetProfileResolver(^NSString *(NSString *guestPath) {
        HPHaloProgressStore *store = weakStore;
        if (!store) return nil;
        /* Resolve against the progression store's actual save-root/path/UUID
         * validation before taking a career-store lock. */
        NSDictionary *snapshot = [store snapshotForProfilePath:guestPath date:NSDate.date];
        id profile = snapshot[@"profile_id"];
        return [profile isKindOfClass:NSString.class] && [profile length] ? profile : nil;
    });
    HPCareerStatsConfigure(saveRootURL);
}
