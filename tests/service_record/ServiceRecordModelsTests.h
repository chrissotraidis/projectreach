/* Include in the isolated UIKit probe so these checks execute the real career
 * and medal models. Fixtures are synthetic and never read installed profiles. */
#import "HPHaloCareerStatsModels.h"

static NSDictionary *SRSection(NSArray *sections,NSString *title) {
    for(NSDictionary *section in sections)if([section[@"title"]isEqual:title])return section;
    return nil;
}
static NSString *SRValue(NSArray *sections,NSString *name) {
    for(NSDictionary *section in sections)for(NSDictionary *row in section[@"rows"])
        if([row[@"name"]isEqual:name])return row[@"value"];
    return nil;
}
static NSDictionary *SRBreakdown(NSString *name,NSNumber *kills,NSNumber *deaths,
    NSNumber *assists,NSNumber *best,NSNumber *played,NSNumber *completed,
    NSNumber *wins,NSNumber *losses,NSNumber *draws,NSNumber *unknown) {
    return @{ @"name":name,@"kills":kills,@"deaths":deaths,@"assists":assists,
              @"best_streak":best,@"matches_played":played,@"completed_matches":completed,
              @"wins":wins,@"losses":losses,@"draws":draws,@"unknown_results":unknown };
}
static void RunServiceRecordModelTests(void (^check)(BOOL,NSString *)) {
    void (^expect)(BOOL,NSString *)=^(BOOL pass,NSString *label){check(pass,[@"Service Record model: "stringByAppendingString:label]);};
    NSString *pistol=@"weapons\\pistol\\pistol",*sameDisplay=@"weapons/pistol/pistol";
    NSString *gulch=@"levels\\test\\bloodgulch\\bloodgulch";
    NSDictionary *progress=@{ @"profile_id":@"12345678-1234-1234-1234-123456789ABC",
        @"season":@"2026-Q4",@"xp":@10,@"kills":@10,
        @"history":@[@{@"season":@"2026-Q3",@"xp":@9000,@"kills":@9000}] };
    NSArray *tiers=@[@{@"name":@"Recruit",@"minXP":@0},@{@"name":@"Private",@"minXP":@10},@{@"name":@"Next",@"minXP":@20}];
    NSDictionary *season=SRBreakdown(@"totals",@5,@2,@1,@3,@8,@6,@2,@1,@1,@2);
    NSDictionary *lifetime=SRBreakdown(@"totals",@90,@30,@8,@10,@50,@41,@20,@10,@20,@6);
    NSDictionary *map=SRBreakdown(gulch,@5,@2,@1,@3,@8,@6,@2,@1,@1,@2);
    NSDictionary *oldMap=SRBreakdown(gulch,@90,@30,@8,@10,@50,@41,@20,@10,@20,@6);
    NSMutableDictionary *career=[@{ @"profile_id":progress[@"profile_id"],@"storage_error":@NO,
        @"tracking_active":@YES,@"tracking_started":@"2026-10-01T12:00:00Z",@"season_id":@"2026-Q4",
        @"season":season,@"lifetime":lifetime,@"season_maps":@[map],@"maps":@[oldMap],
        @"season_modes":@[SRBreakdown(@"ctf",@5,@2,@1,@3,@8,@6,@2,@1,@1,@2)],
        @"modes":@[SRBreakdown(@"ctf",@90,@30,@8,@10,@50,@41,@20,@10,@20,@6)],
        @"season_weapons":@[
            SRBreakdown(pistol,@5,@2,@1,@99,@99,@99,@99,@0,@0,@0),
            SRBreakdown(sameDisplay,@1,@0,@0,@99,@99,@99,@99,@0,@0,@0),
            SRBreakdown(@"unknown",@3,@0,@0,@99,@99,@99,@99,@0,@0,@0)],
        @"weapons":@[SRBreakdown(pistol,@90,@30,@8,@999,@999,@999,@999,@0,@0,@0),
            SRBreakdown(@"lifetime_only",@40,@20,@0,@0,@0,@0,@0,@0,@0,@0)],
        @"medals":@{},@"season_medals":@{},@"medal_seasons":@[],@"medals_tracking_started":NSNull.null }mutableCopy];
    NSDictionary *unmodified=[career copy];

    NSArray *overview=HPHaloServiceRecordSections(progress,career,NO,tiers,HPHaloServiceRecordOverview);
    expect(SRSection(overview,@"Progression")!=nil&&SRSection(overview,@"Match record")!=nil,@"overview retains progression and recorded results");
    expect([SRValue(overview,@"Tracked kills")isEqual:@"5"]&&[SRValue(overview,@"Season XP")isEqual:@"10"],@"overview never substitutes old XP kills for newly tracked combat");
    expect([SRValue(overview,@"Season rank")isEqual:@"Private"],@"rank remains current-quarter rank");
    expect([SRValue(overview,@"Win percentage")isEqual:@"50.0%"],@"win percentage uses all recorded known final results");
    expect(![SRSection(overview,@"Match record")[@"footer"]containsString:@"win; more deaths"],@"match record does not invent game results from K/D");
    expect([SRValue(overview,@"Results unknown")isEqual:@"2"]&&[SRValue(overview,@"Unfinished matches")isEqual:@"2"],@"unknown completion stays distinct from unfinished");
    for(NSDictionary *section in overview)expect(![section[@"style"]isEqual:@"breakdown"],@"overview excludes category lists");
    NSArray *allTime=HPHaloServiceRecordSections(progress,career,YES,tiers,HPHaloServiceRecordOverview);
    expect([SRValue(allTime,@"Tracked kills")isEqual:@"90"]&&[SRValue(allTime,@"Season rank")isEqual:@"Private"],@"lifetime switches combat without promoting seasonal rank");

    NSArray *categories=@[@"weapons",@"maps",@"modes"];
    NSArray *pages=@[@(HPHaloServiceRecordWeapons),@(HPHaloServiceRecordMaps),@(HPHaloServiceRecordGameModes)];
    for(NSUInteger index=0;index<pages.count;index++) {
        NSArray *sections=HPHaloServiceRecordSections(progress,career,NO,tiers,[pages[index]integerValue]);
        expect(sections.count==1&&[sections.firstObject[@"category"]isEqual:categories[index]],@"each page contains only its own recorded category");
        expect([sections.firstObject[@"style"]isEqual:@"breakdown"],@"category retains real breakdown presentation");
        expect([NSJSONSerialization dataWithJSONObject:sections options:0 error:NULL]!=nil,@"page output is plain serializable data");
    }
    NSDictionary *weaponPage=HPHaloServiceRecordSections(progress,career,NO,tiers,HPHaloServiceRecordWeapons).firstObject;
    NSArray *weaponRows=weaponPage[@"rows"];
    expect([weaponRows[0][@"source_name"]isEqual:pistol]&&[weaponRows[1][@"source_name"]isEqual:@"unknown"]&&[weaponRows[2][@"source_name"]isEqual:sameDisplay],@"kill ordering retains exact raw source identities");
    expect([weaponRows[0][@"name"]isEqual:weaponRows[2][@"name"]],@"fixture exercises a display-name collision");

    NSDictionary *detail=HPHaloServiceRecordBreakdownDetail(progress,career,NO,HPHaloServiceRecordWeapons,pistol);
    expect([detail[@"available"]boolValue]&&[SRValue(detail[@"sections"],@"Tracked kills")isEqual:@"5"],@"weapon detail uses selected source in selected season");
    expect([SRValue(detail[@"sections"],@"Deaths")isEqual:@"2"]&&[SRValue(detail[@"sections"],@"Assists")isEqual:@"1"],@"weapon detail preserves actual lethal-source counters");
    expect([SRValue(detail[@"sections"],@"K/D ratio")isEqual:@"2.50"],@"weapon K/D uses selected source counters");
    for(NSString *unrecorded in @[@"Matches played",@"Wins",@"Best observed streak",@"Accuracy",@"Headshots"])
        expect(SRValue(detail[@"sections"],unrecorded)==nil,@"weapons omit measurements not attributed to weapons");
    NSDictionary *collision=HPHaloServiceRecordBreakdownDetail(progress,career,NO,HPHaloServiceRecordWeapons,sameDisplay);
    expect([SRValue(collision[@"sections"],@"Tracked kills")isEqual:@"1"],@"equal displayed names do not select each other's raw source");
    expect([SRValue(collision[@"sections"],@"K/D ratio")containsString:@"—"],@"zero deaths never becomes infinity");
    detail=HPHaloServiceRecordBreakdownDetail(progress,career,YES,HPHaloServiceRecordWeapons,pistol);
    expect([SRValue(detail[@"sections"],@"Tracked kills")isEqual:@"90"],@"lifetime detail uses lifetime source data");
    detail=HPHaloServiceRecordBreakdownDetail(progress,career,NO,HPHaloServiceRecordWeapons,@"lifetime_only");
    expect(![detail[@"available"]boolValue]&&SRValue(detail[@"sections"],@"Tracked kills")==nil,@"a lifetime-only source cannot leak into a seasonal detail");
    detail=HPHaloServiceRecordBreakdownDetail(progress,career,NO,HPHaloServiceRecordWeapons,@"unknown");
    expect([detail[@"title"]containsString:@"Unknown"]&&[SRValue(detail[@"sections"],@"Tracked kills")isEqual:@"3"],@"unknown attribution remains explicitly unknown");

    for(NSNumber *page in @[@(HPHaloServiceRecordMaps),@(HPHaloServiceRecordGameModes)]) {
        NSString *source=page.integerValue==HPHaloServiceRecordMaps?gulch:@"ctf";
        detail=HPHaloServiceRecordBreakdownDetail(progress,career,NO,page.integerValue,source);
        expect([detail[@"available"]boolValue]&&[SRValue(detail[@"sections"],@"Matches played")isEqual:@"8"],@"map and mode detail expose their own aggregate match counts");
        expect([SRValue(detail[@"sections"],@"Best observed streak")isEqual:@"3"]&&[SRValue(detail[@"sections"],@"Win percentage")isEqual:@"50.0%"],@"map and mode results use known final results and observed streaks");
        expect([SRValue(detail[@"sections"],@"Results unknown")isEqual:@"2"]&&[SRValue(detail[@"sections"],@"Unfinished matches")isEqual:@"2"],@"map and mode retain incomplete-outcome semantics");
        detail=HPHaloServiceRecordBreakdownDetail(progress,career,YES,page.integerValue,source);
        expect([SRValue(detail[@"sections"],@"Tracked kills")isEqual:@"90"]&&[SRValue(detail[@"sections"],@"Matches played")isEqual:@"50"],@"map and mode lifetime selection never reuses seasonal metrics");
    }
    expect([career isEqual:unmodified],@"page and detail construction do not modify saved snapshots");

    NSMutableDictionary *empty=[career mutableCopy];empty[@"season_maps"]=@[];
    NSArray *emptySections=HPHaloServiceRecordSections(progress,empty,NO,tiers,HPHaloServiceRecordMaps);
    NSDictionary *emptyRow=emptySections.firstObject[@"rows"][0];
    expect([emptyRow[@"empty"]boolValue]&&emptyRow[@"source_name"]==nil,@"empty list has no fabricated selectable source");
    detail=HPHaloServiceRecordBreakdownDetail(progress,empty,NO,HPHaloServiceRecordMaps,gulch);
    expect(![detail[@"available"]boolValue],@"missing source is unavailable rather than zero-filled");
    empty[@"season_maps"]=@[@{@"name":gulch,@"kills":@5}];
    detail=HPHaloServiceRecordBreakdownDetail(progress,empty,NO,HPHaloServiceRecordMaps,gulch);
    expect([SRValue(detail[@"sections"],@"Tracked kills")isEqual:@"5"],@"partial snapshot keeps the counter it actually contains");
    for(NSString *missing in @[@"Deaths",@"Assists",@"Best observed streak",@"Matches played",@"Wins",@"Unfinished matches"])
        expect([SRValue(detail[@"sections"],missing)containsString:@"—"],@"missing measurements stay unavailable rather than invented zero");

    for(id failure in @[@YES,@"Database unavailable"]) {
        NSMutableDictionary *failed=[career mutableCopy];failed[@"storage_error"]=failure;
        for(NSNumber *page in @[@(HPHaloServiceRecordOverview),@(HPHaloServiceRecordWeapons),@(HPHaloServiceRecordMaps),@(HPHaloServiceRecordGameModes)]) {
            NSArray *sections=HPHaloServiceRecordSections(progress,failed,NO,tiers,page.integerValue);
            expect(SRValue(sections,@"Storage unavailable")!=nil,@"storage failure remains visible on every page");
            for(NSDictionary *section in sections)expect(![section[@"style"]isEqual:@"breakdown"],@"unavailable storage never presents stale breakdown rows");
        }
        detail=HPHaloServiceRecordBreakdownDetail(progress,failed,NO,HPHaloServiceRecordMaps,gulch);
        expect(![detail[@"available"]boolValue]&&SRValue(detail[@"sections"],@"Tracked kills")==nil,@"storage errors suppress stale selected-source metrics");
    }
}
