/* Host-owned, pre-launch choices for the explicitly adapted Xbox guest. */
#import <Foundation/Foundation.h>
#include <stdlib.h>

static NSString *const HPXboxQualityKey = @"HaloPadXboxGraphicsQuality";

static inline BOOL HPXboxSupportsQuality(NSDictionary *build)
{
    id adaptation = build[@"guest_adaptation"];
    return [adaptation isKindOfClass:NSDictionary.class] &&
        ([adaptation[@"name"] isEqual:@"render-quality-v1"] ||
         [adaptation[@"name"] isEqual:@"render-visibility-v1"] ||
         [adaptation[@"name"] isEqual:@"render-water-v1"] ||
         [adaptation[@"name"] isEqual:@"render-border-v1"] ||
         [adaptation[@"name"] isEqual:@"shared-input-v1"] ||
         [adaptation[@"name"] isEqual:@"render-present-v1"] ||
         [adaptation[@"name"] isEqual:@"render-camera-v1"] ||
         [adaptation[@"name"] isEqual:@"network-policy-v1"]);
}

static inline BOOL HPXboxSharperSelected(NSUserDefaults *settings)
{
    return [[settings objectForKey:HPXboxQualityKey] isEqual:@"sharper"];
}

static inline void HPXboxApplyQuality(NSDictionary *build, NSUserDefaults *settings)
{
    if (!HPXboxSupportsQuality(build)) return;
    BOOL sharper = HPXboxSharperSelected(settings);
    /* Explicit nonempty development overrides still support independent A/Bs. */
    const char *scale = getenv("HALO_TEST_RENDER_SCALE");
    const char *filter = getenv("HALO_TEST_ANISOTROPY");
    if (!scale || !*scale) setenv("HALO_TEST_RENDER_SCALE", sharper ? "2" : "1", 1);
    if (!filter || !*filter) setenv("HALO_TEST_ANISOTROPY", sharper ? "4" : "1", 1);
}
