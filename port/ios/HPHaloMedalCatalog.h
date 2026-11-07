#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
NSArray<NSDictionary *> *HPHaloMedalCatalog(void);
NSDictionary *HPHaloMedalForID(NSUInteger medalID);
UIImage * _Nullable HPHaloMedalBadgeImage(NSUInteger medalID, CGFloat size);
/* period: 0=current season, 1=lifetime, 2=selected past season, 3=latest match. */
NSDictionary *HPHaloMedalCollectionModel(NSDictionary *progress, NSDictionary *career,
                                        NSInteger period, NSString * _Nullable selectedSeason);
NS_ASSUME_NONNULL_END
