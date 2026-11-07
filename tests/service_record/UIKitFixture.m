/* Isolated host-UI verification. Every profile, statistic and save path here
 * is synthetic. No engine, game assets, cloud folder or installed save opens. */
#import <UIKit/UIKit.h>
#import "HPHaloCareerStatsViewController.h"
#import "HPHaloMatchHistoryViewController.h"
#import "HPHaloProgressViewController.h"
#import "HPHaloRankProgressViewController.h"
#import "HPHaloMedalsViewController.h"
#import "HPHaloMedalCatalog.h"
#import "HPHaloTheme.h"
#import "HPHaloServiceRecordRanks.h"
#import "ServiceRecordModelsTests.h"

static NSDictionary *Progress,*Career,*History,*LifetimeHistory;
static NSMutableArray<NSString *> *Failures;
static NSMutableArray<NSDictionary *> *Renders;
static NSString *Output;
static NSUInteger Checks;
static BOOL HoldSeason;
static dispatch_semaphore_t SeasonGate,SeasonStarted;

NSString *HPHaloProgressPlayerName(NSString *path) { return path.length?@"Test Player":nil; }
NSDictionary *HPHaloProgressMenuSnapshot(void) { return Progress?:@{}; }
NSDictionary *HPCareerStatsSnapshot(NSString *path) { return Career?:@{}; }
NSDictionary *HPCareerStatsMatchHistory(NSString *path,BOOL lifetime,NSUInteger limit) {
    NSDictionary *answer=lifetime&&LifetimeHistory?LifetimeHistory:History;
    if(!lifetime&&HoldSeason) {
        dispatch_semaphore_signal(SeasonStarted);
        dispatch_semaphore_wait(SeasonGate,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC));
    }
    return answer?:@{@"matches":@[],@"limit":@(limit),@"has_more":@NO};
}
static void Check(BOOL pass,NSString *label) { Checks++;if(!pass)[Failures addObject:label]; }
static NSArray<UIView *> *Views(UIView *root,Class type) {
    NSMutableArray *result=[NSMutableArray array];
    if([root isKindOfClass:type])[result addObject:root];
    for(UIView *child in root.subviews)[result addObjectsFromArray:Views(child,type)];
    return result;
}
static UIButton *Button(UIView *root,NSString *identifier) {
    for(UIButton *button in Views(root,UIButton.class))if([button.accessibilityIdentifier isEqual:identifier])return button;
    return nil;
}
static void Later(NSTimeInterval seconds,void (^block)(void)) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(seconds*NSEC_PER_SEC)),dispatch_get_main_queue(),block);
}
@interface NSObject (FixtureTesting)
- (void)refreshStats;
- (void)refreshProgress;
- (void)refreshMedals;
- (void)refresh:(id)sender;
- (void)refreshHistory;
- (void)checkProfile;
- (void)closeStats;
- (void)selectSeason:(NSString *)season;
@end
@interface FixtureDelegate : UIResponder <UIApplicationDelegate,UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@property(nonatomic,strong) UIViewController *container;
@end

@implementation FixtureDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    Failures=[NSMutableArray array];Renders=[NSMutableArray array];
    Output=[NSTemporaryDirectory()stringByAppendingPathComponent:@"ServiceRecordFixture"];
    [NSFileManager.defaultManager createDirectoryAtPath:Output withIntermediateDirectories:YES attributes:nil error:NULL];
    return YES;
}
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration=[[UISceneConfiguration alloc]initWithName:@"Fixture" sessionRole:session.role];
    configuration.delegateClass=FixtureDelegate.class;return configuration;
}
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    if(![scene isKindOfClass:UIWindowScene.class])return;
    self.window=[[UIWindow alloc]initWithWindowScene:(UIWindowScene *)scene];
    self.container=[UIViewController new];self.window.rootViewController=self.container;
    [self.window makeKeyAndVisible];Later(0.6,^{[self runChecks];});
}
- (void)attach:(UIViewController *)controller width:(CGFloat)width {
    for(UIViewController *old in self.container.childViewControllers) {
        [old willMoveToParentViewController:nil];[old.view removeFromSuperview];[old removeFromParentViewController];
    }
    [self.container addChildViewController:controller];
    controller.view.frame=CGRectMake(0,0,MIN(width,CGRectGetWidth(self.container.view.bounds)),CGRectGetHeight(self.container.view.bounds));
    controller.view.autoresizingMask=UIViewAutoresizingNone;[self.container.view addSubview:controller.view];
    [controller didMoveToParentViewController:self.container];
    [controller.view setNeedsLayout];[controller.view layoutIfNeeded];
}
- (void)validate:(UITableViewController *)controller label:(NSString *)label {
    UITableView *table=controller.tableView;[table setNeedsLayout];[table layoutIfNeeded];
    Check(table.contentSize.width<=CGRectGetWidth(table.bounds)+1,[label stringByAppendingString:@": no horizontal table overflow"]);
    Check(CGRectGetHeight(table.tableHeaderView.frame)>0,[label stringByAppendingString:@": fitted header"]);
    for(UILabel *text in Views(table.tableHeaderView,UILabel.class)) {
        if(text.hidden||text.superview.hidden)continue;
        if(text.hasAmbiguousLayout)fprintf(stderr,"AMBIGUOUS_HEADER %s\nH %s\nV %s\n",text.text.UTF8String,[text constraintsAffectingLayoutForAxis:UILayoutConstraintAxisHorizontal].description.UTF8String,[text constraintsAffectingLayoutForAxis:UILayoutConstraintAxisVertical].description.UTF8String);
        Check(!text.hasAmbiguousLayout,[NSString stringWithFormat:@"%@: determined header layout (%@)",label,text.text]);
        Check(CGRectGetWidth(text.bounds)>0,[label stringByAppendingString:@": header text has width"]);
    }
    for(UITableViewCell *cell in table.visibleCells) {
        [cell layoutIfNeeded];
        for(UILabel *text in Views(cell.contentView,UILabel.class)) {
            if(text.hidden||text.superview.hidden)continue;
            Check(!text.hasAmbiguousLayout,[label stringByAppendingString:@": determined cell layout"]);
            CGRect box=[text convertRect:text.bounds toView:cell.contentView];
            Check(CGRectGetMinX(box)>=-1&&CGRectGetMaxX(box)<=CGRectGetWidth(cell.contentView.bounds)+1,[label stringByAppendingString:@": cell text fits horizontally"]);
            Check(CGRectGetMaxY(box)<=CGRectGetHeight(cell.contentView.bounds)+1,[label stringByAppendingString:@": cell text fits vertically"]);
        }
    }
}
- (void)render:(UIViewController *)controller label:(NSString *)label {
    UIGraphicsImageRendererFormat *format=UIGraphicsImageRendererFormat.defaultFormat;format.scale=1;
    UIImage *image=[[[UIGraphicsImageRenderer alloc]initWithSize:controller.view.bounds.size format:format]imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [controller.view drawViewHierarchyInRect:controller.view.bounds afterScreenUpdates:YES];
    }];
    NSString *path=[Output stringByAppendingPathComponent:[label stringByAppendingPathExtension:@"png"]];
    Check([UIImagePNGRepresentation(image)writeToFile:path atomically:YES],[@"Render "stringByAppendingString:label]);
    [Renders addObject:@{@"case":label,@"image":path}];
}
- (void)fixtures {
    Progress=@{@"visible":@YES,@"menu_context":@YES,@"menu_kind":@1,@"local_player":@0,
        @"guest_profile_path":@"U:\\UDATA\\123456789ABC",@"profile_id":@"12345678-1234-1234-1234-123456789ABC",
        @"xp":@110,@"kills":@110,@"season":@"2026-Q4",@"history":@[@{@"season":@"2026-Q3",@"xp":@900,@"kills":@900}]};
    NSDictionary *totals=SRBreakdown(@"totals",@24,@12,@5,@8,@8,@6,@2,@1,@1,@2);
    NSDictionary *all=SRBreakdown(@"totals",@84,@42,@20,@10,@24,@20,@10,@4,@2,@4);
    Career=@{@"profile_id":Progress[@"profile_id"],@"tracking_active":@YES,@"storage_error":@NO,
        @"tracking_started":@"2026-08-01T12:00:00Z",@"season_id":@"2026-Q4",@"season":totals,@"lifetime":all,
        @"season_weapons":@[SRBreakdown(@"weapons\\pistol\\pistol",@20,@7,@3,@0,@0,@0,@0,@0,@0,@0),SRBreakdown(@"unknown",@4,@5,@2,@0,@0,@0,@0,@0,@0,@0)],
        @"weapons":@[SRBreakdown(@"weapons\\pistol\\pistol",@84,@42,@20,@0,@0,@0,@0,@0,@0,@0)],
        @"season_maps":@[SRBreakdown(@"bloodgulch",@24,@12,@5,@8,@8,@6,@2,@1,@1,@2)],
        @"maps":@[SRBreakdown(@"bloodgulch",@84,@42,@20,@10,@24,@20,@10,@4,@2,@4)],
        @"season_modes":@[SRBreakdown(@"slayer",@24,@12,@5,@8,@8,@6,@2,@1,@1,@2)],
        @"modes":@[SRBreakdown(@"slayer",@84,@42,@20,@10,@24,@20,@10,@4,@2,@4)],
        @"medals_tracking_started":@"2026-08-01T12:00:00Z",@"medals":@{@"1":@7,@"2":@2,@"10":@3},
        @"season_medals":@{@"1":@2,@"10":@1},
        @"medal_seasons":@[@{@"season":@"2026-Q3",@"medals":@{@"1":@5,@"2":@2,@"10":@2},@"total":@9,@"tracked":@YES},
                           @{@"season":@"2026-Q2",@"medals":@{},@"total":@0,@"tracked":@NO}],
        @"latest_match_medals":@{@"available":@YES,@"tracked":@YES,@"medals":@{@"1":@1},@"total":@1,@"map":@"bloodgulch",@"mode":@"slayer",@"result":@2,@"completed":@YES,@"kills":@8,@"deaths":@3}};
    NSDictionary *match=@{@"match_id":@"1:2:3",@"seed":@1,@"game":@2,@"crc":@3,
        @"map":@"bloodgulch",@"mode":@"slayer",@"started_at":@"2026-11-03T12:00:00Z",@"season_id":@"2026-Q4",
        @"kills":@18,@"deaths":@9,@"assists":@6,@"best_streak":@7,@"result":@2,@"completed":@YES,
        @"replicated":@NO,@"partial":@NO,@"season_kills":@18,@"season_deaths":@9,@"season_assists":@6,
        @"season_best_streak":@7,@"medals":@{@"1":@1},@"season_medals":@{@"1":@1},
        @"medal_total":@1,@"season_medal_total":@1,@"medals_tracked":@YES};
    NSMutableDictionary *unfinished=[match mutableCopy];unfinished[@"match_id"]=@"1:3:3";
    unfinished[@"result"]=@(-1);unfinished[@"completed"]=@NO;unfinished[@"partial"]=@YES;
    unfinished[@"kills"]=@9;unfinished[@"deaths"]=@18;
    NSMutableDictionary *unknown=[match mutableCopy];unknown[@"match_id"]=@"1:4:3";unknown[@"result"]=@0;
    History=@{@"profile_id":Progress[@"profile_id"],@"season_id":@"2026-Q4",@"lifetime":@NO,
        @"matches":@[match,unfinished,unknown],@"limit":@100,@"has_more":@NO,
        @"tracking_started":@"2026-08-01T12:00:00Z",@"storage_error":@NO};
}
- (void)runChecks {
    @try {
        [UIView setAnimationsEnabled:NO];[self fixtures];
        RunServiceRecordModelTests(^(BOOL pass,NSString *label){Check(pass,label);});
        for(NSUInteger medal=1;medal<=15;medal++)Check(HPHaloMedalBadgeImage(medal,64)!=nil,@"Every locally drawn medal renders");
        Check(HPHaloMedalBadgeImage(0,64)==nil&&HPHaloMedalBadgeImage(16,64)==nil,@"Invalid medal IDs have no badge");
        for(NSDictionary *tier in HPHaloServiceRecordRankCatalog())Check(HPHaloRankBadgeImage(tier[@"file"])!=nil,@"Every generic rank badge renders without resources");
        Check(HPHaloRankBadgeImage(@"../../external.png")==nil,@"Rank renderer rejects external artwork path");
        for(NSNumber *width in @[@360,@600,@1000]) {
            UITableViewController *stats=(id)HPHaloCareerStatsControllerMake(Progress);
            UINavigationController *navigation=[[UINavigationController alloc]initWithRootViewController:stats];HPHaloStyleNavigation(navigation);
            [self attach:navigation width:width.doubleValue];[self validate:stats label:@"Overview"];
            Check([SRValue([stats valueForKey:@"sections"],@"Tracked kills")isEqual:@"24"],@"Season shows newly tracked combat");
            [self render:navigation label:[NSString stringWithFormat:@"overview-%@",width]];
            UISegmentedControl *period=[stats valueForKey:@"period"];period.selectedSegmentIndex=1;
            [period sendActionsForControlEvents:UIControlEventValueChanged];
            Check([SRValue([stats valueForKey:@"sections"],@"Tracked kills")isEqual:@"84"],@"Lifetime uses lifetime combat");
            period.selectedSegmentIndex=0;[period sendActionsForControlEvents:UIControlEventValueChanged];
            for(NSString *page in @[@"weapons",@"maps",@"modes",@"overview"]) {
                UIButton *tab=Button(stats.view,[@"halopad.service-record."stringByAppendingString:page]);
                Check(tab!=nil&&CGRectGetHeight(tab.bounds)>=44,@"Tabs expose 44-point touch targets");
                [tab sendActionsForControlEvents:UIControlEventTouchUpInside];[stats.view layoutIfNeeded];
                Check((tab.accessibilityTraits&UIAccessibilityTraitSelected)!=0,@"Selected tab announces selection");
                [self validate:stats label:page];
                [self render:navigation label:[NSString stringWithFormat:@"%@-%@",page,width]];
            }
        }
        UITableViewController *large=(id)HPHaloCareerStatsControllerMake(Progress);
        large.traitOverrides.preferredContentSizeCategory=UIContentSizeCategoryAccessibilityExtraExtraExtraLarge;
        UINavigationController *largeNavigation=[[UINavigationController alloc]initWithRootViewController:large];
        [self attach:largeNavigation width:360];[self validate:large label:@"Largest Dynamic Type"];
        [self render:largeNavigation label:@"overview-largest-type-360"];
        [self medalChecks];[self navigationChecks];
    } @catch(NSException *error) { [Failures addObject:[NSString stringWithFormat:@"Exception %@: %@",error.name,error.reason]];[self finish]; }
}
- (void)medalChecks {
    Check([HPHaloMedalCollectionModel(Progress,Career,0,nil)[@"total"]integerValue]==3,@"Current-season medal model");
    Check([HPHaloMedalCollectionModel(Progress,Career,1,nil)[@"total"]integerValue]==12,@"Lifetime medal model");
    Check([HPHaloMedalCollectionModel(Progress,Career,2,nil)[@"total"]integerValue]==9,@"Past-season medal model");
    Check(![HPHaloMedalCollectionModel(Progress,Career,2,@"2026-Q2")[@"tracked"]boolValue],@"Pre-update season does not invent medals");
    NSDictionary *latest=HPHaloMedalCollectionModel(Progress,Career,3,nil);
    Check([latest[@"note"]containsString:@"Defeat"]||[latest[@"note"]containsString:@"Loss"],@"Medal match result preserves server defeat despite positive K/D");
    UITableViewController *medals=(id)HPHaloMedalsControllerMake(Progress,Career,NO);
    [self attach:medals width:360];[self validate:medals label:@"Medals"];
    Check([medals.tableView numberOfRowsInSection:0]==9&&[medals.tableView numberOfRowsInSection:1]==6,@"All 15 medal types remain available");
    UISegmentedControl *period=[medals valueForKey:@"period"];period.selectedSegmentIndex=1;
    [period sendActionsForControlEvents:UIControlEventValueChanged];
    Check([[[medals valueForKey:@"model"]objectForKey:@"total"]integerValue]==12,@"Medal lifetime control");
    period.selectedSegmentIndex=2;[period sendActionsForControlEvents:UIControlEventValueChanged];
    Check([[[medals valueForKey:@"model"]objectForKey:@"total"]integerValue]==9,@"Medal history control");
    [medals selectSeason:@"2026-Q2"];[medals.view layoutIfNeeded];
    Check([[[medals valueForKey:@"note"]text]containsString:@"not tracked"],@"Untracked season UI is explicit");
    [self render:medals label:@"medals-untracked-360"];
}
- (void)navigationChecks {
    UITableViewController *stats=(id)HPHaloCareerStatsControllerMake(Progress);
    UINavigationController *navigation=[[UINavigationController alloc]initWithRootViewController:stats];
    HPHaloStyleNavigation(navigation);[self attach:navigation width:1000];
    [Button(stats.view,@"halopad.service-record.weapons")sendActionsForControlEvents:UIControlEventTouchUpInside];
    [stats.tableView.delegate tableView:stats.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    Later(0.15,^{
        Check(navigation.topViewController!=stats,@"Recorded weapon opens its detail screen");
        if(navigation.topViewController!=stats) {
            UITableViewController *detail=(id)navigation.topViewController;
            Check([SRValue([detail valueForKey:@"sections"],@"Tracked kills")isEqual:@"20"],@"Detail uses exactly the selected weapon");
            [self validate:detail label:@"Weapon detail"];[self render:navigation label:@"weapon-detail"];
        }
        [navigation popToRootViewControllerAnimated:NO];
        Later(0.15,^{
        [Button(stats.view,@"halopad.service-record.overview")sendActionsForControlEvents:UIControlEventTouchUpInside];
        UIButton *entry=Button(stats.view,@"halopad.stats.match-history");
        Check(entry!=nil,@"Overview retains Match History entry after returning from a weapon");
        [entry sendActionsForControlEvents:UIControlEventTouchUpInside];
        Later(0.3,^{
            UITableViewController *history=(id)navigation.topViewController;
            Check([NSStringFromClass(history.class)isEqual:@"HPHaloMatchHistoryViewController"],@"History tile opens production controller");
            if(![NSStringFromClass(history.class)isEqual:@"HPHaloMatchHistoryViewController"]){[self finish];return;}
            Check(![[history valueForKey:@"loading"]boolValue]&&[history.tableView numberOfRowsInSection:0]==3,@"Background history reads display the synthetic match set");
            for(NSUInteger index=0;index<3;index++) {
                UITableViewCell *cell=[history.tableView.dataSource tableView:history.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:index inSection:0]];
                Check([cell.accessibilityLabel containsString:@[@"Defeat",@"Unfinished",@"Unknown result"][index]],@"Results preserve defeat, unfinished and unknown without K/D reclassification");
            }
            [self validate:history label:@"Match history"];[self render:navigation label:@"match-history"];
            [history.tableView.delegate tableView:history.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
            Later(0.15,^{
                Check([NSStringFromClass(navigation.topViewController.class)isEqual:@"HPHaloMatchDetailViewController"],@"Match row opens production details");
                if([NSStringFromClass(navigation.topViewController.class)isEqual:@"HPHaloMatchDetailViewController"]) {
                    UITableViewController *detail=(id)navigation.topViewController;
                    Check([SRValue([detail valueForKey:@"sections"],@"Outcome")isEqual:@"Unfinished"],@"Unfinished match details do not invent a loss");
                    [self render:navigation label:@"match-detail"];
                }
                [self historyRaceChecks:^{[self progressionChecks];}];
            });
        });
        });
    });
}
- (void)historyRaceChecks:(void (^)(void))done {
    SeasonGate=dispatch_semaphore_create(0);SeasonStarted=dispatch_semaphore_create(0);HoldSeason=YES;
    NSMutableDictionary *lifetime=[History mutableCopy];lifetime[@"matches"]=@[History[@"matches"][0]];lifetime[@"lifetime"]=@YES;LifetimeHistory=lifetime;
    UITableViewController *history=(id)HPHaloMatchHistoryControllerMake(Progress,NO);
    UINavigationController *navigation=[[UINavigationController alloc]initWithRootViewController:history];[self attach:navigation width:600];
    Later(0.15,^{
        Check(dispatch_semaphore_wait(SeasonStarted,DISPATCH_TIME_NOW)==0,@"Hold the first background season query");
        UISegmentedControl *period=[history valueForKey:@"period"];period.selectedSegmentIndex=1;
        [period sendActionsForControlEvents:UIControlEventValueChanged];
        Check([[history valueForKey:@"loading"]boolValue]&&[history valueForKey:@"history"]==nil,@"Period change clears previous rows while loading");
        [history.tableView.delegate tableView:history.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        Check(navigation.topViewController==history,@"Loading rows cannot select stale matches");
        Later(0.2,^{
            Check(![[history valueForKey:@"loading"]boolValue]&&[[[history valueForKey:@"history"]objectForKey:@"matches"]count]==1,@"New lifetime query completes independently");
            HoldSeason=NO;dispatch_semaphore_signal(SeasonGate);
            Later(0.2,^{
                Check([[[history valueForKey:@"history"]objectForKey:@"lifetime"]boolValue]&&[[[history valueForKey:@"history"]objectForKey:@"matches"]count]==1,@"Late season response cannot replace selected lifetime history");
                NSDictionary *saved=Progress;NSMutableDictionary *changed=[saved mutableCopy];changed[@"profile_id"]=@"ABCD1234-1234-1234-1234-123456789ABC";
                Progress=changed;[history checkProfile];
                Check([[history valueForKey:@"profileChanged"]boolValue]&&[history valueForKey:@"history"]==nil,@"Profile change clears previously displayed history");
                Progress=saved;LifetimeHistory=nil;done();
            });
        });
    });
}
- (void)progressionChecks {
    __block NSUInteger captured=0,restored=0;
    UIViewController *card=HPHaloProgressControllerMakeWithDismissal(^{captured++;},^{restored++;});
    [self attach:card width:600];[card refresh:nil];[card.view layoutIfNeeded];
    UIButton *entry=[card valueForKey:@"historyButton"];
    Check([entry.titleLabel.text isEqual:@"Service Record"]&&[entry.accessibilityIdentifier isEqual:@"halopad.service-record.open"],@"Production menu card exposes Service Record");
    [entry sendActionsForControlEvents:UIControlEventTouchUpInside];
    Later(0.3,^{
        UINavigationController *navigation=(id)self.container.presentedViewController;
        Check(captured==1&&restored==0,@"Opening Service Record owns one input-capture lease");
        Check([navigation isKindOfClass:UINavigationController.class]&&[NSStringFromClass(navigation.topViewController.class)isEqual:@"HPHaloCareerStatsViewController"],@"Menu opens the new production Service Record directly");
        if(![navigation isKindOfClass:UINavigationController.class]){[self finish];return;}
        [navigation.topViewController closeStats];
        Later(0.2,^{
            Check(self.container.presentedViewController==nil&&restored==1,@"Done restores input once");
            [(id<UIAdaptivePresentationControllerDelegate>)navigation presentationControllerDidDismiss:navigation.presentationController];
            Check(restored==1,@"Duplicate adaptive callback cannot restore input twice");
            [self finish];
        });
    });
}
- (void)finish {
    NSDictionary *report=@{@"passed":@(Failures.count==0),@"checks":@(Checks),@"failures":Failures,@"renders":Renders,
        @"window_width":@(CGRectGetWidth(self.window.bounds)),@"window_height":@(CGRectGetHeight(self.window.bounds)),
        @"scope":@"Synthetic host UIKit models, native controllers, layout, period/detail/history navigation, stale query suppression, profile isolation and dismissal input lease. No engine or physical device acceptance."};
    NSData *data=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:NULL];
    [data writeToFile:[Output stringByAppendingPathComponent:@"verification.json"]atomically:YES];
    fprintf(stderr,"SERVICE_RECORD_UI: %s\n",[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
    exit(Failures.count?1:0);
}
@end
int main(int argc,char **argv) { @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(FixtureDelegate.class)); } }
