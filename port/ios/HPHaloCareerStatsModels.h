#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
NSArray<NSDictionary *> *HPHaloCareerStatSections(NSDictionary *progress, NSDictionary *career,
                                                BOOL lifetime, NSArray<NSDictionary *> *tiers);
NSDictionary *HPHaloCareerRankForXP(long long xp, NSArray<NSDictionary *> *tiers);

typedef NS_ENUM(NSInteger, HPHaloServiceRecordPage) {
    HPHaloServiceRecordOverview,
    HPHaloServiceRecordWeapons,
    HPHaloServiceRecordMaps,
    HPHaloServiceRecordGameModes,
};
/* Page selection changes presentation only; every value retains its original
 * tracking period. Breakdown rows include source_name for exact selection. */
NSArray<NSDictionary *> *HPHaloServiceRecordSections(NSDictionary *progress,
    NSDictionary *career, BOOL lifetime, NSArray<NSDictionary *> *tiers,
    HPHaloServiceRecordPage page);
/* {title, subtitle, available, sections}; weapon details intentionally omit
 * match results and streaks, which are not attributed to individual weapons. */
NSDictionary *HPHaloServiceRecordBreakdownDetail(NSDictionary *progress,
    NSDictionary *career, BOOL lifetime, HPHaloServiceRecordPage page,
    NSString *sourceName);
NS_ASSUME_NONNULL_END
