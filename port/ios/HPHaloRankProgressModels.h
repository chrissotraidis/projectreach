#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/* Uses the selected profile's current quarterly XP, never lifetime totals.
 * A missing profile or unreadable progression returns available=NO. Numeric
 * requirements that cannot be known are NSNull, rather than invented zeros.
 * Every rank row preserves the original catalog dictionary under `rank`.
 */
NSDictionary *HPHaloRankProgressModel(NSDictionary *progress,
                                     NSArray<NSDictionary *> *tiers);
NS_ASSUME_NONNULL_END
