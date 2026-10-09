/* Announce downloadable HaloPad releases, never a moving upstream engine. */
#import <Foundation/Foundation.h>

static BOOL HPHaloPadVersion(id value)
{
    return [value isKindOfClass:NSString.class] &&
        [value rangeOfString:@"^[0-9]+(\\.[0-9]+){0,2}\\z" options:NSRegularExpressionSearch].location != NSNotFound;
}

static BOOL HPHaloPadDownloadURL(id value)
{
    if (![value isKindOfClass:NSString.class]) return NO;
    NSURLComponents *url = [NSURLComponents componentsWithString:value];
    return [url.scheme isEqualToString:@"https"] && [url.host isEqualToString:@"github.com"] &&
        !url.user && !url.password && !url.port && !url.query && !url.fragment &&
        [url.path hasPrefix:@"/chrissotraidis/projectreach/releases/download/"] &&
        ![url.path containsString:@"/../"];
}

static NSString *const HPHaloPadUpdateFeedURL = @"https://raw.githubusercontent.com/chrissotraidis/projectreach/halopad-updates/halopad-update.json";

static NSString *HPHaloPadUpdateNotice(NSDictionary *manifest, NSString *version, NSString *build,
                                      NSString *platform, NSString *osVersion)
{
    if (![manifest isKindOfClass:NSDictionary.class] || ![manifest[@"schema"] isEqual:@1] ||
        ![manifest[@"bundle_id"] isEqual:@"dev.halopad.HaloPad"] ||
        !HPHaloPadVersion(version) || !HPHaloPadVersion(build) ||
        !HPHaloPadVersion(manifest[@"version"]) || !HPHaloPadVersion(manifest[@"build"]) ||
        ![manifest[@"artifacts"] isKindOfClass:NSDictionary.class]) return nil;
    NSDictionary *artifact = manifest[@"artifacts"][platform];
    if (![artifact isKindOfClass:NSDictionary.class] || !HPHaloPadDownloadURL(artifact[@"url"]) ||
        ![artifact[@"size"] isKindOfClass:NSNumber.class] || [artifact[@"size"] longLongValue] <= 0 ||
        !HPHaloPadVersion(artifact[@"minimum_os"]) || !HPHaloPadVersion(osVersion) ||
        [artifact[@"minimum_os"] compare:osVersion options:NSNumericSearch] == NSOrderedDescending) return nil;
    NSComparisonResult order = [manifest[@"version"] compare:version options:NSNumericSearch];
    if (order == NSOrderedAscending || (order == NSOrderedSame &&
        [manifest[@"build"] compare:build options:NSNumericSearch] != NSOrderedDescending)) return nil;
    return [NSString stringWithFormat:@"HaloPad %@ is available. Open Updates to get the app. Your installed game remains available.", manifest[@"version"]];
}
