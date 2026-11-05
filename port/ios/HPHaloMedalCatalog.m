#import "HPHaloMedalCatalog.h"
#include <limits.h>
#include <math.h>

NSArray<NSDictionary *> *HPHaloMedalCatalog(void) {
    static NSArray *catalog;static dispatch_once_t once;
    dispatch_once(&once,^{
        NSArray *names=@[@"Double Kill",@"Triple Kill",@"Overkill",@"Killtacular",@"Killtrocity",@"Killamanjaro",@"Killtastrophe",@"Killpocalypse",@"Killionaire",@"Killing Spree",@"Killing Frenzy",@"Running Riot",@"Rampage",@"Untouchable",@"Invincible"];
        NSMutableArray *rows=[NSMutableArray array];
        for(NSUInteger i=0;i<names.count;i++) {
            NSUInteger target=i<9 ? i+2 : (i-8)*5;
            NSString *requirement=i<9 ? [NSString stringWithFormat:@"Kill %lu enemies in quick succession, within 4 seconds of each other.",(unsigned long)target] : [NSString stringWithFormat:@"Kill %lu enemies without dying.",(unsigned long)target];
            [rows addObject:@{@"id":@(i+1),@"name":names[i],@"requirement":requirement,@"category":i<9 ? @"Multikills" : @"Killing sprees",@"target":@(target)}];
        }
        catalog=[rows copy];
    });return catalog;
}
NSDictionary *HPHaloMedalForID(NSUInteger medalID) {
    return medalID>=1 && medalID<=HPHaloMedalCatalog().count ? HPHaloMedalCatalog()[medalID-1] : @{};
}
static UIBezierPath *HPMStar(CGPoint center,CGFloat outer,CGFloat inner,NSUInteger points) {
    UIBezierPath *path=[UIBezierPath bezierPath];
    for(NSUInteger i=0;i<points*2;i++) {
        CGFloat angle=(CGFloat)(-M_PI_2+M_PI*(double)i/(double)points),r=i%2 ? inner : outer;
        CGPoint p=CGPointMake(center.x+cos(angle)*r,center.y+sin(angle)*r);
        if(i)[path addLineToPoint:p];else[path moveToPoint:p];
    }
    [path closePath];return path;
}
UIImage *HPHaloMedalBadgeImage(NSUInteger medalID,CGFloat size) {
    NSDictionary *medal=HPHaloMedalForID(medalID);
    if(!medal.count || !isfinite(size) || size<1 || size>1024)return nil;
    static NSCache *cache;static dispatch_once_t once;dispatch_once(&once,^{cache=[NSCache new];cache.countLimit=128;});
    NSString *key=[NSString stringWithFormat:@"%lu-%.2f",(unsigned long)medalID,(double)size];
    UIImage *cached=[cache objectForKey:key];if(cached)return cached;
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=2;format.opaque=NO;
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(size,size) format:format];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){
        CGContextRef cg=context.CGContext;CGContextScaleCTM(cg,size/100.0,size/100.0);
        BOOL multi=medalID<=9;NSUInteger level=multi ? medalID-1 : medalID-10;
        CGFloat hue=multi ? 0.55-0.04*MIN(level,(NSUInteger)8) : 0.10-0.014*MIN(level,(NSUInteger)5);
        UIColor *accent=[UIColor colorWithHue:hue saturation:0.62 brightness:0.96 alpha:1];
        UIColor *dark=[UIColor colorWithHue:hue saturation:0.78 brightness:0.38 alpha:1];
        CGContextSaveGState(cg);CGContextSetShadowWithColor(cg,CGSizeMake(0,2),3,[UIColor colorWithWhite:0 alpha:0.65].CGColor);
        UIBezierPath *ribbon=[UIBezierPath bezierPath];
        [ribbon moveToPoint:CGPointMake(28,49)];[ribbon addLineToPoint:CGPointMake(22,94)];[ribbon addLineToPoint:CGPointMake(39,84)];[ribbon addLineToPoint:CGPointMake(48,97)];[ribbon addLineToPoint:CGPointMake(55,51)];[ribbon closePath];
        [ribbon moveToPoint:CGPointMake(45,51)];[ribbon addLineToPoint:CGPointMake(52,97)];[ribbon addLineToPoint:CGPointMake(62,84)];[ribbon addLineToPoint:CGPointMake(79,94)];[ribbon addLineToPoint:CGPointMake(72,49)];[ribbon closePath];
        [dark setFill];[ribbon fill];CGContextRestoreGState(cg);
        CGContextSaveGState(cg);CGContextSetShadowWithColor(cg,CGSizeMake(0,2),4,[UIColor colorWithWhite:0 alpha:0.7].CGColor);
        UIBezierPath *edge=HPMStar(CGPointMake(50,43),40,multi?33:29,multi?12:8);
        [[UIColor colorWithWhite:0.88 alpha:1]setFill];[edge fill];CGContextRestoreGState(cg);
        CGContextSaveGState(cg);[edge addClip];
        CGFloat colors[]={0.97,0.98,1,1, 0.36,0.40,0.46,1, 0.88,0.90,0.94,1};CGFloat locations[]={0,0.55,1};
        CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();CGGradientRef gradient=CGGradientCreateWithColorComponents(space,colors,locations,3);
        CGContextDrawLinearGradient(cg,gradient,CGPointMake(20,5),CGPointMake(75,85),0);CGGradientRelease(gradient);CGColorSpaceRelease(space);CGContextRestoreGState(cg);
        UIBezierPath *ring=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(20,13,60,60)];[dark setFill];[ring fill];
        UIBezierPath *face=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(24,17,52,52)];[accent setFill];[face fill];
        CGContextSaveGState(cg);[face addClip];
        CGContextSetFillColorWithColor(cg,[UIColor colorWithWhite:1 alpha:0.17].CGColor);CGContextFillEllipseInRect(cg,CGRectMake(12,-2,76,50));CGContextRestoreGState(cg);
        UIColor *ink=[UIColor colorWithWhite:0.07 alpha:0.94];
        if(!multi){UIBezierPath *star=HPMStar(CGPointMake(50,43),23,11,5);[[UIColor colorWithWhite:0.12 alpha:0.18]setFill];[star fill];}
        NSString *number=[medal[@"target"] stringValue];
        UIFont *font=[UIFont systemFontOfSize:multi?31:29 weight:UIFontWeightBlack];
        NSDictionary *attributes=@{NSFontAttributeName:font,NSForegroundColorAttributeName:ink};
        CGSize text=[number sizeWithAttributes:attributes];
        [number drawAtPoint:CGPointMake((100-text.width)/2,43-text.height/2) withAttributes:attributes];
        NSUInteger marks=MIN((NSUInteger)5,level+1);CGFloat start=50-(marks-1)*5;
        for(NSUInteger i=0;i<marks;i++){UIBezierPath *dot=[UIBezierPath bezierPathWithOvalInRect:CGRectMake(start+i*10-2,74,4,4)];[[UIColor colorWithWhite:0.96 alpha:1]setFill];[dot fill];}
    }];
    [cache setObject:image forKey:key];return image;
}
static NSDictionary *HPMDict(id value){return [value isKindOfClass:NSDictionary.class]?value:@{};}
static NSArray *HPMArray(id value){return [value isKindOfClass:NSArray.class]?value:@[];}
static NSString *HPMString(id value){return [value isKindOfClass:NSString.class]?value:@"";}
static long long HPMCount(id value){
    if(![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue]) || [value doubleValue]<0)return 0;
    if([value doubleValue]>=(double)LLONG_MAX)return LLONG_MAX;
    return [value longLongValue];
}
static long long HPMSum(long long a,long long b){return b>LLONG_MAX-a?LLONG_MAX:a+b;}
static BOOL HPMSeasonValid(NSString *season){
    if(season.length!=7 || [season characterAtIndex:4]!='-' || [season characterAtIndex:5]!='Q' || [season characterAtIndex:6]<'1' || [season characterAtIndex:6]>'4')return NO;
    for(NSUInteger i=0;i<4;i++)if([season characterAtIndex:i]<'0'||[season characterAtIndex:i]>'9')return NO;return YES;
}
static NSString *HPMSeasonTitle(NSString *season){return HPMSeasonValid(season)?[NSString stringWithFormat:@"Q%@ %@",[season substringFromIndex:6],[season substringToIndex:4]]:season;}
NSDictionary *HPHaloMedalCollectionModel(NSDictionary *progress,NSDictionary *career,NSInteger period,NSString *selectedSeason) {
    progress=HPMDict(progress);career=HPMDict(career);
    NSString *current=HPMString(career[@"season_id"]);if(!HPMSeasonValid(current))current=HPMString(progress[@"season"]);
    NSMutableDictionary *seasonRows=[NSMutableDictionary dictionary];
    for(id value in HPMArray(career[@"medal_seasons"])) {
        NSDictionary *row=HPMDict(value);NSString *season=HPMString(row[@"season"]);
        if(HPMSeasonValid(season) && [season compare:current]==NSOrderedAscending)seasonRows[season]=row;
    }
    for(id value in HPMArray(progress[@"history"])) {
        NSString *season=HPMString(HPMDict(value)[@"season"]);
        if(HPMSeasonValid(season) && [season compare:current]==NSOrderedAscending && !seasonRows[season])seasonRows[season]=@{@"season":season,@"medals":@{},@"total":@0,@"tracked":@NO};
    }
    NSArray *seasonIDs=[[seasonRows allKeys]sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){return [b compare:a];}];
    NSMutableArray *seasons=[NSMutableArray array];for(NSString *season in seasonIDs)[seasons addObject:seasonRows[season]];
    NSString *selected=[seasonIDs containsObject:selectedSeason?:@""]?selectedSeason:(seasonIDs.firstObject?:@"");
    NSDictionary *selection=HPMDict(seasonRows[selected]);
    NSDictionary *match=HPMDict(career[@"latest_match_medals"]);
    NSDictionary *counts=HPMDict(career[period==1?@"medals":@"season_medals"]);
    if(period==2)counts=HPMDict(selection[@"medals"]);
    if(period==3)counts=[match[@"available"]boolValue]?HPMDict(match[@"medals"]):@{};
    NSString *error=HPMString(career[@"storage_error"]);
    if([career[@"storage_error"] respondsToSelector:@selector(boolValue)] && [career[@"storage_error"]boolValue]&&!error.length)error=@"Medal statistics are temporarily unavailable.";
    if(error.length)counts=@{};
    NSMutableArray *rows=[NSMutableArray array];long long total=0;NSUInteger earned=0;
    for(NSDictionary *medal in HPHaloMedalCatalog()) {
        long long count=HPMCount(counts[[medal[@"id"] stringValue]]);total=HPMSum(total,count);if(count)earned++;
        NSMutableDictionary *row=[medal mutableCopy];row[@"count"]=@(count);[rows addObject:row];
    }
    NSString *started=HPMString(career[@"medals_tracking_started"]);
    NSString *note=@"Medals are saved for each quarterly season and lifetime. Awards earned before this update cannot be recovered.";
    if(period==2 && ![selection[@"tracked"]boolValue])note=@"Medals were not tracked in this season. Earlier awards cannot be recovered.";
    if(period==2 && !selected.length)note=@"No past seasons yet. Your medal totals will stay here when a new quarterly season begins.";
    if(period==3) {
        if(![match[@"available"]boolValue])note=@"No match recorded yet. Play a multiplayer match to see its medals here.";
        else if(![match[@"tracked"]boolValue])note=@"Medals were not tracked in this match. Earlier awards cannot be recovered.";
        else {
            NSString *map=HPMString(match[@"map"]),*mode=HPMString(match[@"mode"]);
            map=[[[map stringByReplacingOccurrencesOfString:@"\\" withString:@"/"]lastPathComponent]stringByDeletingPathExtension];
            NSDictionary *known=@{@"bloodgulch":@"Blood Gulch",@"ctf":@"Capture the Flag",@"koth":@"King of the Hill"};
            map=known[map.lowercaseString]?:[[map stringByReplacingOccurrencesOfString:@"_" withString:@" "]localizedCapitalizedString];
            mode=known[mode.lowercaseString]?:[[mode stringByReplacingOccurrencesOfString:@"_" withString:@" "]localizedCapitalizedString];
            NSInteger result=[match[@"result"]integerValue];
            NSString *outcome=![match[@"completed"]boolValue]?@"Current / unfinished match":result==1?@"Win":result==2?@"Loss":result==3?@"Draw":@"Result unknown";
            NSMutableArray *details=[NSMutableArray array];if(map.length)[details addObject:map];if(mode.length)[details addObject:mode];[details addObject:outcome];
            note=[[details componentsJoinedByString:@" · "]stringByAppendingString:@". Medals from this match only."];
        }
    }
    if(error.length)note=error;
    NSString *title=period==1?@"Lifetime":period==2?(selected.length?HPMSeasonTitle(selected):@"Past seasons"):period==3?@"Latest match":HPMSeasonTitle(current);
    BOOL tracked=period==2?[selection[@"tracked"]boolValue]:period==3?([match[@"available"]boolValue]&&[match[@"tracked"]boolValue]):YES;
    return @{@"rows":rows,@"total":@(total),@"earned_types":@(earned),@"period":@(period),@"title":title.length?title:@"This season",@"selected_season":selected,@"seasons":seasons,@"note":note,@"tracking_started":started,@"storage_error":@(error.length>0),@"tracked":@(tracked)};
}
