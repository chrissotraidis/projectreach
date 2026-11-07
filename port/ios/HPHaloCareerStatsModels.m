#import "HPHaloCareerStatsModels.h"
#import "HPHaloMedalCatalog.h"
#include <limits.h>

static NSDictionary *HPDict(id value) { return [value isKindOfClass:NSDictionary.class] ? value : @{}; }
static NSArray *HPArray(id value) { return [value isKindOfClass:NSArray.class] ? value : @[]; }
static NSString *HPString(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static long long HPCount(id value) {
    if (![value respondsToSelector:@selector(longLongValue)]) return 0;
    return MAX(0LL, [value longLongValue]);
}
static long long HPSum(long long a, long long b) { return b > LLONG_MAX - a ? LLONG_MAX : a + b; }
static NSString *HPNumber(long long n) {
    return [NSNumberFormatter localizedStringFromNumber:@(n) numberStyle:NSNumberFormatterDecimalStyle];
}
static NSDictionary *HPRow(NSString *name, NSString *value) { return @{ @"name":name, @"value":value }; }
/* tone: presentation hint only (accent, gold, kills, deaths); values are unchanged. */
static NSDictionary *HPToneRow(NSString *name, NSString *value, NSString *tone) { return @{ @"name":name, @"value":value, @"tone":tone }; }
/* style: grid, medals, breakdown or notice; selects the native cell layout. */
static NSDictionary *HPStyledSection(NSString *title, NSString *footer, NSArray *rows, NSString *style) {
    return @{ @"title":title, @"footer":footer, @"rows":rows, @"style":style };
}
/* layout: presentation-only hint for the Service Record (band, band-compact, record). */
static NSDictionary *HPLaidOut(NSDictionary *section, NSString *layout) {
    NSMutableDictionary *copy=[section mutableCopy];copy[@"layout"]=layout;return [copy copy];
}
/* Kills minus deaths, signed like a post-game carnage report. */
static NSDictionary *HPSpreadRow(long long kills, long long deaths, BOOL known) {
    if (!known) return HPRow(@"K/D spread",@"—");
    long long spread=kills-deaths;
    NSString *magnitude=HPNumber(spread<0 ? -spread : spread);
    return HPToneRow(@"K/D spread",spread>0 ? [@"+" stringByAppendingString:magnitude] : spread<0 ? [@"\u2212" stringByAppendingString:magnitude] : @"0",
        spread>0 ? @"kills" : spread<0 ? @"deaths" : @"accent");
}
static NSString *HPTrackingDate(NSString *iso) {
    NSDate *date=[[NSISO8601DateFormatter new] dateFromString:iso];
    if (!date) return iso.length>=10 ? [iso substringToIndex:10] : iso;
    NSDateFormatter *format=[NSDateFormatter new];format.dateStyle=NSDateFormatterMediumStyle;format.timeStyle=NSDateFormatterNoStyle;
    return [format stringFromDate:date];
}
static NSString *HPSeasonName(NSString *season) {
    if (season.length == 7 && [season characterAtIndex:4] == '-' && [season characterAtIndex:5] == 'Q')
        return [NSString stringWithFormat:@"Q%@ %@", [season substringFromIndex:6], [season substringToIndex:4]];
    return season.length ? season : @"Current season";
}
NSDictionary *HPHaloCareerRankForXP(long long xp, NSArray<NSDictionary *> *tiers) {
    NSDictionary *rank = @{};
    for (id item in tiers) {
        NSDictionary *tier=HPDict(item);
        if (HPCount(tier[@"minXP"]) <= MAX(0LL,xp) &&
            (rank.count == 0 || HPCount(tier[@"minXP"]) >= HPCount(rank[@"minXP"]))) rank=tier;
    }
    return rank;
}
static NSDictionary *HPNextRank(long long xp, NSArray<NSDictionary *> *tiers) {
    NSDictionary *next=@{};
    for (id item in tiers) {
        NSDictionary *tier=HPDict(item); long long threshold=HPCount(tier[@"minXP"]);
        if (threshold > xp && (next.count == 0 || threshold < HPCount(next[@"minXP"]))) next=tier;
    }
    return next;
}
static NSString *HPDisplayName(NSString *name) {
    NSString *path=[name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    NSString *clean=[[path lastPathComponent] stringByDeletingPathExtension];
    NSArray<NSString *> *parts=path.pathComponents;
    if(parts.count>=3 && ([parts.firstObject.lowercaseString isEqualToString:@"weapons"] || [parts.firstObject.lowercaseString isEqualToString:@"vehicles"])) {
        NSString *family=parts[1];
        if(![family.lowercaseString isEqualToString:clean.lowercaseString]) clean=[NSString stringWithFormat:@"%@ · %@",family,clean];
    }
    NSDictionary *known=@{@"bloodgulch":@"Blood Gulch",@"hangemhigh":@"Hang ’Em High",@"battlecreek":@"Battle Creek",@"beavercreek":@"Battle Creek",
        @"boardingaction":@"Boarding Action",@"chillout":@"Chill Out",@"ratrace":@"Rat Race",@"putput":@"Chiron TL-34",@"carousel":@"Derelict",
        @"ctf":@"Capture the Flag",@"koth":@"King of the Hill",@"king":@"King of the Hill",@"slayer":@"Slayer",@"oddball":@"Oddball",
        @"race":@"Race",@"swat":@"SWAT",@"unknown":@"Unknown / unavailable"};
    NSString *mapped=known[[clean.lowercaseString stringByReplacingOccurrencesOfString:@" " withString:@""]];
    return mapped ?: [[clean stringByReplacingOccurrencesOfString:@"_" withString:@" "] localizedCapitalizedString];
}
static NSString *HPShare(long long part, long long total) {
    if (total<=0) return @"—";
    return [NSNumberFormatter localizedStringFromNumber:@((double)part/(double)total) numberStyle:NSNumberFormatterPercentStyle];
}
static NSArray *HPBreakdownRows(id value) {
    NSArray *items=HPArray(value);
    long long total=0;
    for(id item in items) total=HPSum(total,HPCount(HPDict(item)[@"kills"]));
    if (items.count == 0) return @[@{ @"name":@"No recorded kills yet", @"value":@"—", @"amount":@0, @"empty":@YES }];
    NSMutableArray *result=[NSMutableArray array];
    NSArray *sorted=[items sortedArrayUsingComparator:^NSComparisonResult(id left,id right) {
        long long a=HPCount(HPDict(left)[@"kills"]), b=HPCount(HPDict(right)[@"kills"]);
        if (a!=b) return a>b ? NSOrderedAscending : NSOrderedDescending;
        return [HPString(HPDict(left)[@"name"]) localizedCaseInsensitiveCompare:HPString(HPDict(right)[@"name"])];
    }];
    for(id item in sorted) {
        NSDictionary *row=HPDict(item); NSString *name=HPString(row[@"name"]);
        [result addObject:@{ @"name":name.length ? HPDisplayName(name) : @"Unknown", @"value":HPNumber(HPCount(row[@"kills"])), @"amount":@(HPCount(row[@"kills"])), @"source_name":name, @"share":HPShare(HPCount(row[@"kills"]),total) }];
    }
    return result;
}
NSArray<NSDictionary *> *HPHaloCareerStatSections(NSDictionary *progress, NSDictionary *career,
                                                BOOL lifetime, NSArray<NSDictionary *> *tiers) {
    NSMutableArray *sections=[NSMutableArray array];
    long long seasonXP=HPCount(progress[@"xp"]), lifetimeXP=seasonXP;
    long long seasonKills=HPCount(progress[@"kills"]), lifetimeKills=seasonKills;
    NSDictionary *best=@{ @"season":HPString(progress[@"season"]), @"xp":@(seasonXP) };
    for(id item in HPArray(progress[@"history"])) {
        NSDictionary *row=HPDict(item);
        // The legacy store's history contains past seasons; still reject an accidental current-season duplicate.
        if ([HPString(row[@"season"]) isEqualToString:HPString(progress[@"season"])]) continue;
        long long xp=HPCount(row[@"xp"]);
        lifetimeXP=HPSum(lifetimeXP,xp); lifetimeKills=HPSum(lifetimeKills,HPCount(row[@"kills"]));
        if(xp>HPCount(best[@"xp"]) || (xp==HPCount(best[@"xp"]) &&
             [HPString(row[@"season"]) compare:HPString(best[@"season"])]==NSOrderedDescending)) best=row;
    }
    NSDictionary *rank=HPHaloCareerRankForXP(seasonXP,tiers), *next=HPNextRank(seasonXP,tiers);
    NSMutableArray *progressRows=[NSMutableArray arrayWithArray:@[
        HPToneRow(lifetime ? @"Lifetime XP" : @"Season XP",HPNumber(lifetime ? lifetimeXP : seasonXP),@"accent"),
        HPToneRow(lifetime ? @"Lifetime kills" : @"Season kills",HPNumber(lifetime ? lifetimeKills : seasonKills),@"kills"),
        HPToneRow(@"Season rank",HPString(rank[@"name"]).length ? HPString(rank[@"name"]) : @"Recruit",@"gold")]];
    [progressRows addObject:HPToneRow(@"XP to next rank",next.count ? HPNumber(HPCount(next[@"minXP"])-seasonXP) : @"Max rank",@"accent")];
    if(next.count) [progressRows addObject:HPRow(@"Next rank",HPString(next[@"name"]))];
    NSString *bestText=[NSString stringWithFormat:@"%@ · %@ XP",HPSeasonName(HPString(best[@"season"])),HPNumber(HPCount(best[@"xp"]))];
    [progressRows addObject:HPRow(@"Best season",bestText)];
    if ([progress[@"storage_error"] boolValue])
        [sections addObject:HPStyledSection(@"Progression", @"Existing progression is preserved and will retry automatically.", @[HPRow(@"Progression unavailable",@"Saved XP could not be read.")],@"notice")];
    else
        [sections addObject:HPLaidOut(HPStyledSection(@"Progression", @"Local progression awards one XP per confirmed kill. Local ranks follow the current calendar quarter; saved totals from previous quarters remain available.",progressRows,@"grid"),@"band-compact")];
    NSString *error=HPString(career[@"storage_error"]);
    if([career[@"storage_error"] respondsToSelector:@selector(boolValue)] && [career[@"storage_error"] boolValue] && error.length==0) error=@"Career statistics are temporarily unavailable.";
    if(error.length) {
        [sections addObject:HPStyledSection(@"Career statistics",@"Your existing progression is preserved. Statistics will retry automatically.",@[HPRow(@"Storage unavailable",error)],@"notice")];
        return sections;
    }
    BOOL active=[career[@"tracking_active"] boolValue];
    NSString *started=HPString(career[@"tracking_started"]);
    NSString *trackingNote=started.length ? [NSString stringWithFormat:@"Tracked since %@. Earlier deaths, assists, matches and breakdowns were not recorded. K/D uses only kills and deaths from this tracking period.",HPTrackingDate(started)] : @"New career tracking begins with this update. Earlier deaths, assists, matches and breakdowns cannot be recovered. K/D uses only newly tracked kills and deaths.";
    NSDictionary *totals=HPDict(career[lifetime ? @"lifetime" : @"season"]);
    long long kills=HPCount(totals[@"kills"]), deaths=HPCount(totals[@"deaths"]);
    NSString *kd=deaths>0 ? [NSString stringWithFormat:@"%.2Lf",(long double)kills/(long double)deaths] : (kills>0 ? @"— (no deaths)" : @"—");
    NSString *killPercent=(kills>0 || deaths>0) ? [NSString stringWithFormat:@"%.1Lf%%",100.0L*(long double)kills/((long double)kills+(long double)deaths)] : @"—";
    [sections addObject:HPLaidOut(HPStyledSection(lifetime ? @"Combat · tracked lifetime" : @"Combat · this season",trackingNote,@[
        HPToneRow(@"Tracked kills",HPNumber(kills),@"kills"),HPToneRow(@"Deaths",HPNumber(deaths),@"deaths"),HPSpreadRow(kills,deaths,YES),HPToneRow(@"K/D ratio",kd,@"accent"),HPToneRow(@"Kill percentage",killPercent,@"accent"),
        HPRow(@"Assists",HPNumber(HPCount(totals[@"assists"]))),HPToneRow(@"Best observed streak",HPNumber(HPCount(totals[@"best_streak"])),@"gold")],@"grid"),@"band")];
    NSDictionary *medals=HPHaloMedalCollectionModel(progress,career,lifetime?1:0,nil);
    NSMutableArray *medalRows=[NSMutableArray arrayWithObject:HPRow(@"Medals earned",HPNumber(HPCount(medals[@"total"])))];
    for(NSDictionary *medal in medals[@"rows"]) {
        [medalRows addObject:@{@"name":medal[@"name"],@"value":HPNumber(HPCount(medal[@"count"])),@"medal_id":medal[@"id"]}];
    }
    [sections addObject:HPStyledSection(lifetime?@"Medals · tracked lifetime":@"Medals · this season",@"Open Medals above to see every badge, its requirements, past seasons, and your latest match. Medal tracking starts with this update; earlier awards cannot be recovered.",medalRows,@"medals")];
    long long wins=HPCount(totals[@"wins"]),losses=HPCount(totals[@"losses"]),draws=HPCount(totals[@"draws"]);
    long double known=(long double)wins+(long double)losses+(long double)draws;
    NSString *rate=known>0 ? [NSString stringWithFormat:@"%.1Lf%%",100.0L*(long double)wins/known] : @"—";
    NSString *matchFooter=@"Win percentage uses confirmed wins, losses and draws. Unfinished matches and unknown outcomes are excluded.";
    [sections addObject:HPLaidOut(HPStyledSection(@"Match record",matchFooter,@[
        HPRow(@"Matches played",HPNumber(HPCount(totals[@"matches_played"]))),HPToneRow(@"Wins",HPNumber(wins),@"kills"),
        HPToneRow(@"Losses",HPNumber(losses),@"deaths"),HPRow(@"Draws",HPNumber(draws)),HPToneRow(@"Win percentage",rate,@"accent"),
        HPRow(@"Results unknown",HPNumber(HPCount(totals[@"unknown_results"]))),
        HPRow(@"Unfinished matches",HPNumber(MAX(0LL,HPCount(totals[@"matches_played"])-HPCount(totals[@"completed_matches"])) ))],@"grid"),@"record")];
    NSString *prefix=lifetime ? @"" : @"season_";
    for(NSArray *pair in @[@[@"maps",@"Kills by map"],@[@"weapons",@"Kills by weapon / damage source"],@[@"modes",@"Kills by game mode"]]) {
        NSString *key=[prefix stringByAppendingString:pair[0]];
        NSString *footer=active ? @"Credited kills recorded by this update; earlier breakdowns are unavailable." : @"Play a multiplayer match to begin recording breakdowns.";
        if([pair[0] isEqualToString:@"weapons"]) footer=@"Confirmed lethal damage sources, which can differ from the held weapon. Unknown attribution is listed explicitly; earlier sources were not recorded.";
        for(id item in HPArray(career[key]))if(HPString(HPDict(item)[@"attribution_note"]).length){footer=HPString(HPDict(item)[@"attribution_note"]);break;}
        NSMutableDictionary *section=[HPStyledSection(pair[1],footer,HPBreakdownRows(career[key]),@"breakdown") mutableCopy];
        section[@"category"]=pair[0];
        [sections addObject:section];
    }
    return sections;
}

static NSString *HPRecordCategory(HPHaloServiceRecordPage page) {
    switch(page) {
        case HPHaloServiceRecordWeapons:return @"weapons";
        case HPHaloServiceRecordMaps:return @"maps";
        case HPHaloServiceRecordGameModes:return @"modes";
        default:return nil;
    }
}

static NSString *HPRecordedCount(NSDictionary *record, NSString *key) {
    return [record[key] isKindOfClass:NSNumber.class]?HPNumber(HPCount(record[key])):@"—";
}

/* Favorites from credited kills in the selected period. Unknown attribution is
 * never promoted to a favorite; categories without data say so. */
static NSDictionary *HPHighlightsSection(NSDictionary *progress, NSDictionary *career, BOOL lifetime) {
    NSString *prefix=lifetime ? @"" : @"season_";
    NSArray *specs=@[@[@"weapons",@"Favorite weapon",@"scope",@(HPHaloServiceRecordWeapons),@"accent"],
                     @[@"maps",@"Favorite map",@"map.fill",@(HPHaloServiceRecordMaps),@"kills"],
                     @[@"modes",@"Favorite game mode",@"flag.2.crossed.fill",@(HPHaloServiceRecordGameModes),@"gold"]];
    NSMutableArray *rows=[NSMutableArray array];
    for(NSArray *spec in specs) {
        NSArray *items=HPArray(career[[prefix stringByAppendingString:spec[0]]]);
        long long total=0;NSDictionary *top=nil;
        for(id item in items) {
            NSDictionary *row=HPDict(item);long long kills=HPCount(row[@"kills"]);total=HPSum(total,kills);
            NSString *name=HPString(row[@"name"]);
            if(!name.length||[name.lowercaseString isEqualToString:@"unknown"]||kills<=0)continue;
            if(!top||kills>HPCount(top[@"kills"])||(kills==HPCount(top[@"kills"])&&[name localizedCaseInsensitiveCompare:HPString(top[@"name"])]==NSOrderedAscending))top=row;
        }
        if(top) {
            long long kills=HPCount(top[@"kills"]);
            [rows addObject:@{@"name":spec[1],@"value":HPDisplayName(HPString(top[@"name"])),
                @"detail":[NSString stringWithFormat:@"%@ kills · %@ of credited kills",HPNumber(kills),HPShare(kills,total)],
                @"icon":spec[2],@"page":spec[3],@"tone":spec[4],@"source_name":HPString(top[@"name"])}];
        } else {
            [rows addObject:@{@"name":spec[1],@"value":@"—",@"detail":@"Not recorded yet",@"icon":spec[2],@"tone":spec[4],@"empty":@YES}];
        }
    }
    NSDictionary *medals=HPHaloMedalCollectionModel(progress,career,lifetime?1:0,nil);
    NSDictionary *best=nil;
    for(NSDictionary *medal in HPArray(medals[@"rows"]))
        if(HPCount(medal[@"count"])>0&&(!best||HPCount(medal[@"count"])>HPCount(best[@"count"])))best=medal;
    if(best)[rows addObject:@{@"name":@"Most earned medal",@"value":HPString(best[@"name"]),
        @"detail":[NSString stringWithFormat:@"×%@ earned",HPNumber(HPCount(best[@"count"]))],@"medal_id":best[@"id"],@"tone":@"gold",@"medals":@YES}];
    else [rows addObject:@{@"name":@"Most earned medal",@"value":@"—",@"detail":@"No medals recorded yet",@"icon":@"rosette",@"tone":@"gold",@"empty":@YES}];
    return HPStyledSection(@"Career highlights",@"Favorites use credited kills recorded for this period. Unknown damage sources are never chosen.",rows,@"highlights");
}
static NSInteger HPOverviewOrder(NSDictionary *section) {
    NSString *title=HPString(section[@"title"]),*style=HPString(section[@"style"]);
    if([style isEqualToString:@"notice"])return 0;
    if([title hasPrefix:@"Combat"])return 1;
    if([style isEqualToString:@"highlights"])return 2;
    if([title isEqualToString:@"Match record"])return 3;
    if([style isEqualToString:@"medals"])return 4;
    return 5;
}

NSArray<NSDictionary *> *HPHaloServiceRecordSections(NSDictionary *progress,
    NSDictionary *career, BOOL lifetime, NSArray<NSDictionary *> *tiers,
    HPHaloServiceRecordPage page) {
    NSArray *all=HPHaloCareerStatSections(progress,career,lifetime,tiers);
    NSString *category=HPRecordCategory(page);
    NSMutableArray *selected=[NSMutableArray array];
    for(NSDictionary *section in all) {
        BOOL breakdown=[section[@"style"] isEqual:@"breakdown"];
        if(category ? [section[@"category"] isEqual:category] : !breakdown)
            [selected addObject:section];
    }
    if(category&&!selected.count) {
        /* A career-store error must remain visible on every page. */
        for(NSDictionary *section in all)
            if([section[@"style"] isEqual:@"notice"]&&![section[@"title"] isEqual:@"Progression"])
                [selected addObject:section];
    }
    if(!category) {
        BOOL combat=NO;
        for(NSDictionary *section in selected)if([HPString(section[@"title"]) hasPrefix:@"Combat"])combat=YES;
        if(combat)[selected addObject:HPHighlightsSection(progress,HPDict(career),lifetime)];
        [selected sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
            NSInteger left=HPOverviewOrder(a),right=HPOverviewOrder(b);
            return left<right?NSOrderedAscending:left>right?NSOrderedDescending:NSOrderedSame;
        }];
    }
    return [selected copy];
}

NSDictionary *HPHaloServiceRecordBreakdownDetail(NSDictionary *progress,
    NSDictionary *career, BOOL lifetime, HPHaloServiceRecordPage page,
    NSString *sourceName) {
    (void)progress;
    career=HPDict(career);sourceName=HPString(sourceName);
    NSString *category=HPRecordCategory(page);
    NSString *title=sourceName.length?HPDisplayName(sourceName):@"Recorded statistics";
    NSString *period=lifetime?@"Tracked lifetime":@"This season";
    NSString *kind=page==HPHaloServiceRecordWeapons?@"Weapon / damage source":page==HPHaloServiceRecordMaps?@"Map":@"Game mode";
    NSString *subtitle=[NSString stringWithFormat:@"%@ · %@",period,kind];
    NSString *error=HPString(career[@"storage_error"]);
    if(!error.length&&[career[@"storage_error"] respondsToSelector:@selector(boolValue)]&&[career[@"storage_error"] boolValue])
        error=@"Saved statistics are temporarily unavailable.";
    NSDictionary *found=nil;
    NSString *key=category?[NSString stringWithFormat:@"%@%@",lifetime?@"":@"season_",category]:nil;
    for(id value in key?HPArray(career[key]):@[]) {
        NSDictionary *row=HPDict(value);
        if([HPString(row[@"name"]) isEqualToString:sourceName]){found=row;break;}
    }
    if(error.length||!found||!category) {
        NSString *message=error.length?error:@"No recorded statistics are available for this selection in this period.";
        return @{@"title":title,@"subtitle":subtitle,@"available":@NO,@"sections":@[
            HPStyledSection(@"Recorded statistics",@"Only activity recorded by this update can be shown.",@[HPRow(@"Statistics unavailable",message)],@"notice")]};
    }
    long long kills=HPCount(found[@"kills"]),deaths=HPCount(found[@"deaths"]);
    BOOL combatKnown=[found[@"kills"] isKindOfClass:NSNumber.class]&&[found[@"deaths"] isKindOfClass:NSNumber.class];
    NSString *kd=combatKnown&&deaths>0?[NSString stringWithFormat:@"%.2Lf",(long double)kills/(long double)deaths]:@"—";
    NSString *percent=combatKnown&&(kills>0||deaths>0)?[NSString stringWithFormat:@"%.1Lf%%",100.0L*(long double)kills/((long double)kills+(long double)deaths)]:@"—";
    NSMutableArray *combat=[NSMutableArray arrayWithArray:@[
        HPToneRow(@"Tracked kills",HPRecordedCount(found,@"kills"),@"kills"),HPToneRow(@"Deaths",HPRecordedCount(found,@"deaths"),@"deaths"),
        HPSpreadRow(kills,deaths,combatKnown),HPRow(@"Assists",HPRecordedCount(found,@"assists")),HPToneRow(@"K/D ratio",kd,@"accent"),
        HPToneRow(@"Kill percentage",percent,@"accent")]];
    BOOL weapon=page==HPHaloServiceRecordWeapons;
    if(!weapon)[combat addObject:HPToneRow(@"Best observed streak",HPRecordedCount(found,@"best_streak"),@"gold")];
    NSString *note=weapon?@"Attributed lethal damage sources, not the weapon held at the time. Unknown sources stay unknown. Match results, accuracy and streaks are not recorded per weapon.":@"Only tracked activity for this selection and period is included.";
    if(weapon&&HPString(found[@"attribution_note"]).length)note=HPString(found[@"attribution_note"]);
    NSMutableArray *sections=[NSMutableArray arrayWithObject:HPLaidOut(HPStyledSection(@"Combat",note,combat,@"grid"),@"band")];
    if(!weapon) {
        long long wins=HPCount(found[@"wins"]),losses=HPCount(found[@"losses"]),draws=HPCount(found[@"draws"]);
        long double known=(long double)wins+losses+draws;
        BOOL resultsKnown=[found[@"wins"] isKindOfClass:NSNumber.class]&&[found[@"losses"] isKindOfClass:NSNumber.class]&&[found[@"draws"] isKindOfClass:NSNumber.class];
        NSString *rate=resultsKnown&&known>0?[NSString stringWithFormat:@"%.1Lf%%",100.0L*wins/known]:@"—";
        NSString *unfinished=[found[@"matches_played"] isKindOfClass:NSNumber.class]&&[found[@"completed_matches"] isKindOfClass:NSNumber.class]?
            HPNumber(MAX(0LL,HPCount(found[@"matches_played"])-HPCount(found[@"completed_matches"]))):@"—";
        [sections addObject:HPLaidOut(HPStyledSection(@"Match record",@"Unknown outcomes and unfinished matches are excluded from win percentage.",@[
            HPRow(@"Matches played",HPRecordedCount(found,@"matches_played")),HPToneRow(@"Wins",HPRecordedCount(found,@"wins"),@"kills"),
            HPToneRow(@"Losses",HPRecordedCount(found,@"losses"),@"deaths"),HPRow(@"Draws",HPRecordedCount(found,@"draws")),HPToneRow(@"Win percentage",rate,@"accent"),
            HPRow(@"Results unknown",HPRecordedCount(found,@"unknown_results")),HPRow(@"Unfinished matches",unfinished)],@"grid"),@"record")];
    }
    return @{@"title":title,@"subtitle":subtitle,@"available":@YES,@"sections":[sections copy]};
}
