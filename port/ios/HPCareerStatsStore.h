#import <Foundation/Foundation.h>
#import "HPCareerStatsEvent.h"
NS_ASSUME_NONNULL_BEGIN
/* Posted on the main queue after a newly committed medal. Retries are silent.
 * userInfo: profile_id, medal_id, season, event_id, awarded_at/earned_at (ISO date). */
FOUNDATION_EXPORT NSNotificationName const HPCareerMedalEarnedNotification;
/* 1: committed or already committed, 2: invalid event, 0: retryable storage failure. */
@interface HPCareerStatsStore : NSObject
- (nullable instancetype)initWithSaveRootURL:(NSURL *)root calendar:(nullable NSCalendar *)calendar error:(NSError **)error;
- (uint32_t)recordEvent:(const HPCareerStatsEventV1 *)event profileID:(NSString *)profileID date:(NSDate *)date error:(NSError **)error;
- (nullable NSDictionary *)snapshotForProfileID:(NSString *)profileID date:(NSDate *)date error:(NSError **)error;
/* Read-only newest-first match snapshots. limit 0 uses 50; all requests cap at
 * 100. has_more means older records exist beyond this bounded window. Season
 * filtering includes any match with career or medal activity in that quarter,
 * once per match. kills/deaths/assists cover the recorded part of the whole
 * match (authoritative join baselines excluded); season_* values use the chosen
 * quarter. result -1 is unfinished, 0 completed/unknown, 1 win, 2 loss, 3 draw.
 * No missing older matches, scores, opponents or durations are reconstructed. */
- (nullable NSDictionary *)matchHistoryForProfileID:(NSString *)profileID
                                             date:(NSDate *)date
                                         lifetime:(BOOL)lifetime
                                            limit:(NSUInteger)limit
                                            error:(NSError **)error;
/* Snapshot medal keys: medals, season_medals (decimal ID -> count),
 * medal_seasons [{season, medals, total, tracked}], medals_tracking_started,
 * latest_match_medals {available, tracked, medals, total, map, mode, result,
 * completed, started_at}. Latest-match totals cover the whole match across
 * quarter boundaries; result is -1 unfinished, 0 unknown, 1 win, 2 loss, 3 draw. */
- (void)close;
@end
/* Integration supplies the existing progression store's validated profile UUID resolver.
 * The resolver is invoked before acquiring any career-store lock. */
void HPCareerStatsConfigure(NSURL *saveRootURL);
void HPCareerStatsSetProfileResolver(NSString * _Nullable (^ _Nullable resolver)(NSString *guestProfilePath));
NSDictionary *HPCareerStatsSnapshot(NSString *guestProfilePath);
NSDictionary *HPCareerStatsMatchHistory(NSString *guestProfilePath, BOOL lifetime, NSUInteger limit);
uint32_t xh_host_halopad_career_event_v1(uint32_t path,uint32_t pathLength,uint32_t event,uint32_t eventLength);
NS_ASSUME_NONNULL_END
