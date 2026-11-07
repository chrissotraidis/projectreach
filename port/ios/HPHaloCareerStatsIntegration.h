#import <Foundation/Foundation.h>
@class HPHaloProgressStore;

NS_ASSUME_NONNULL_BEGIN
/* Configure once before starting the guest, using the existing validated XP
 * store and its save root. No runtime method replacement is performed. */
FOUNDATION_EXPORT void HPHaloCareerStatsConfigure(NSURL *saveRootURL,
                                                  HPHaloProgressStore *progressStore);
NS_ASSUME_NONNULL_END
