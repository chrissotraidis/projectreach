#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/* Local display policy for the optional Service Record, independent of game or
 * network rank. One confirmed kill earns one XP. The built-in neutral six-tier
 * ladder is an example; a build may supply HaloPadServiceRecordRanks.json with
 * {"tiers":[{"name":"...","minXP":0}, ...]} to choose its own thresholds.
 * Thresholds must be increasing integers, begin at zero, and fit SQLite int64.
 * Badges are generated locally from the validated tier order, never game art. */
FOUNDATION_EXPORT NSArray<NSDictionary *> *HPHaloServiceRecordRankCatalog(void);
/* Foundation-only validation, also used by the focused tests. Invalid input
 * returns nil instead of partially applying a policy. At most 64 tiers. */
FOUNDATION_EXPORT NSArray<NSDictionary *> * _Nullable HPHaloServiceRecordValidateRankCatalog(id input);
NS_ASSUME_NONNULL_END
