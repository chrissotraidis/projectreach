#import "HPHaloRankProgressModels.h"
#include <limits.h>
#include <math.h>
#include <string.h>

/* SQLite progression uses signed 64-bit integers. Accept only real integer
 * NSNumber values, clamping negative saved XP and saturating positive XP at
 * that storage limit. Catalog thresholds themselves must fit without clamping.
 */
static BOOL HPRoadmapInteger(id value, BOOL savedXP, long long *result) {
    if (![value isKindOfClass:NSNumber.class] ||
        CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
    const char *type=[value objCType];
    if (!type || !type[0]) return NO;
    if (strchr("fdD",type[0])) {
        double number=[value doubleValue];
        if (!isfinite(number) || trunc(number)!=number) return NO;
        if (number<0) { if (!savedXP) return NO; *result=0; return YES; }
        // (double)LLONG_MAX rounds to 2^63, so this comparison also rejects
        // unrepresentable catalog thresholds before any integer conversion.
        if (number>=(double)LLONG_MAX) {
            if (!savedXP) return NO;
            *result=LLONG_MAX; return YES;
        }
        *result=(long long)number; return YES;
    }
    if (strchr("CSILQ",type[0])) {
        unsigned long long number=[value unsignedLongLongValue];
        if (number>(unsigned long long)LLONG_MAX) {
            if (!savedXP) return NO;
            *result=LLONG_MAX; return YES;
        }
        *result=(long long)number; return YES;
    }
    if (!strchr("csilq",type[0])) return NO;
    long long number=[value longLongValue];
    if (number<0) { if (!savedXP) return NO; number=0; }
    *result=number; return YES;
}

static BOOL HPRoadmapText(id value) {
    return [value isKindOfClass:NSString.class] &&
        [[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] length]>0;
}

static NSArray<NSDictionary *> *HPRoadmapCatalog(id input) {
    if (![input isKindOfClass:NSArray.class] || [input count]==0) return nil;
    NSMutableArray<NSDictionary *> *rows=[NSMutableArray array];
    NSMutableSet *thresholds=[NSMutableSet set], *orders=[NSMutableSet set], *identifiers=[NSMutableSet set];
    for (id item in input) {
        if (![item isKindOfClass:NSDictionary.class]) return nil;
        NSDictionary *tier=item;
        long long threshold=0, order=0;
        if (!HPRoadmapInteger(tier[@"minXP"],NO,&threshold) ||
            !HPRoadmapText(tier[@"name"]) || !HPRoadmapText(tier[@"file"])) return nil;
        NSString *file=tier[@"file"];
        if (![file.pathExtension.lowercaseString isEqualToString:@"png"] ||
            [file containsString:@"/"] || [file containsString:@"\\"] || [file hasPrefix:@"."]) return nil;
        if ([thresholds containsObject:@(threshold)]) return nil;
        [thresholds addObject:@(threshold)];
        if (tier[@"order"]) {
            if (!HPRoadmapInteger(tier[@"order"],NO,&order) || order<=0 || [orders containsObject:@(order)]) return nil;
            [orders addObject:@(order)];
        }
        if (tier[@"rankId"]) {
            if (!HPRoadmapText(tier[@"rankId"]) || [identifiers containsObject:tier[@"rankId"]]) return nil;
            [identifiers addObject:tier[@"rankId"]];
        }
        [rows addObject:tier];
    }
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b) {
        long long left=0,right=0;
        HPRoadmapInteger(a[@"minXP"],NO,&left); HPRoadmapInteger(b[@"minXP"],NO,&right);
        return left<right ? NSOrderedAscending : left>right ? NSOrderedDescending : NSOrderedSame;
    }];
    long long first=0;
    if (!HPRoadmapInteger(rows.firstObject[@"minXP"],NO,&first) || first!=0) return nil;
    return rows;
}

static BOOL HPRoadmapSeason(id value) {
    if (![value isKindOfClass:NSString.class] || [value length]!=7) return NO;
    NSString *season=value;
    if ([season characterAtIndex:4]!='-' || [season characterAtIndex:5]!='Q' ||
        [season characterAtIndex:6]<'1' || [season characterAtIndex:6]>'4') return NO;
    for (NSUInteger i=0;i<4;i++) {
        unichar c=[season characterAtIndex:i];
        if (c<'0' || c>'9') return NO;
    }
    return [[season substringToIndex:4] integerValue]>0;
}

NSDictionary *HPHaloRankProgressModel(NSDictionary *progress,
                                     NSArray<NSDictionary *> *tiers) {
    NSDictionary *saved=[progress isKindOfClass:NSDictionary.class] ? progress : @{};
    NSArray<NSDictionary *> *catalog=HPRoadmapCatalog(tiers);
    NSString *message=@"";
    long long xp=0;
    id error=saved[@"storage_error"];
    BOOL storageError=([error isKindOfClass:NSString.class] && [error length]>0) ||
        ([error isKindOfClass:NSNumber.class] && [error boolValue]);
    NSString *profile=[saved[@"profile_id"] isKindOfClass:NSString.class] ? saved[@"profile_id"] : nil;
    if (!catalog) message=@"Rank information is unavailable.";
    else if (storageError) message=@"Saved rank is temporarily unavailable.";
    else if (!profile || ![[NSUUID alloc] initWithUUIDString:profile]) message=@"Select a named player profile to see rank progress.";
    else if (!HPRoadmapSeason(saved[@"season"])) message=@"Current season is unavailable.";
    else if (!HPRoadmapInteger(saved[@"xp"],YES,&xp)) message=@"Saved XP is unavailable.";
    BOOL available=message.length==0;
    NSUInteger currentIndex=NSNotFound;
    if (available) {
        for (NSUInteger i=0;i<catalog.count;i++) {
            long long threshold=0; HPRoadmapInteger(catalog[i][@"minXP"],NO,&threshold);
            if (threshold<=xp) currentIndex=i;
            else break;
        }
    }
    NSMutableArray *rankRows=[NSMutableArray array];
    long long previous=0;
    for (NSUInteger i=0;i<catalog.count;i++) {
        NSDictionary *tier=catalog[i];
        long long threshold=0; HPRoadmapInteger(tier[@"minXP"],NO,&threshold);
        NSString *state=!available ? @"unavailable" : i<currentIndex ? @"earned" : i==currentIndex ? @"current" : @"locked";
        [rankRows addObject:@{ @"rank":tier, @"state":state, @"min_xp":@(threshold),
            @"remaining_xp":available ? @(threshold>xp ? threshold-xp : 0) : (id)NSNull.null,
            @"step_xp":@(i==0 ? 0 : threshold-previous) }];
        previous=threshold;
    }
    id current=NSNull.null, next=NSNull.null, xpToNext=NSNull.null;
    NSUInteger remaining=0;
    long long earned=0, span=0;
    double fraction=0;
    if (available) {
        current=catalog[currentIndex];
        remaining=catalog.count-currentIndex-1;
        if (remaining>0) {
            next=catalog[currentIndex+1];
            long long base=0, threshold=0;
            HPRoadmapInteger(current[@"minXP"],NO,&base); HPRoadmapInteger(next[@"minXP"],NO,&threshold);
            earned=xp-base; span=threshold-base; xpToNext=@(threshold-xp);
            fraction=MIN(1.0,MAX(0.0,(double)earned/(double)span));
        } else fraction=1;
    }
    return @{ @"available":@(available), @"message":message,
        @"season":HPRoadmapSeason(saved[@"season"]) ? saved[@"season"] : (id)NSNull.null,
        @"xp":available ? @(xp) : (id)NSNull.null,
        @"current_rank":current, @"next_rank":next, @"xp_to_next":xpToNext,
        @"num_remaining":@(remaining), @"current_progress":@(fraction),
        @"progress_earned":@(earned), @"progress_span":@(span), @"ranks":rankRows };
}
