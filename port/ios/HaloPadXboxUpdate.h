/* Update metadata only; executable updates are built on the player's Mac. */
#import <Foundation/Foundation.h>

static BOOL HPXboxReleaseTag(id tag)
{
    return [tag isKindOfClass:NSString.class] &&
        [tag rangeOfString:@"^build-[0-9]+$" options:NSRegularExpressionSearch].location != NSNotFound;
}

static NSNumber *HPXboxNetworkVersion(NSString *header)
{
    if (!header) return nil;
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:
        @"(?m)^\\s*#define\\s+HALO_PORT_NETWORK_VERSION\\s+([0-9]+)\\b" options:0 error:nil];
    NSTextCheckingResult *match = [pattern firstMatchInString:header options:0 range:NSMakeRange(0, header.length)];
    return match ? @([[header substringWithRange:[match rangeAtIndex:1]] integerValue]) : nil;
}

static NSString *HPXboxUpdateNotice(NSDictionary *build, NSString *tag, NSNumber *network)
{
    if (!HPXboxReleaseTag(tag)) return nil;
    NSNumber *mine = build[@"network_version"];
    NSString *version = [tag stringByReplacingOccurrencesOfString:@"build-" withString:@"build "];
    if ([mine isKindOfClass:NSNumber.class] && network && mine.integerValue != network.integerValue)
        return [NSString stringWithFormat:@"OpenCE %@ uses a different multiplayer version. To join those hosts, rebuild Xbox with PadMint. Your installed game remains available.", version];
    /* A newer build on the same protocol is not an urgent player update.
       Only advertise a downloadable HaloPad update once a tested app feed exists. */
    return nil;
}
