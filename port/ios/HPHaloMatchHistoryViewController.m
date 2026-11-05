#import "HPHaloMatchHistoryViewController.h"
#import "HPCareerStatsStore.h"
#import "HPHaloProgressStore.h"
#import "HPHaloMedalCatalog.h"
#import "HPHaloTheme.h"
#include <math.h>

static NSString *HPMHText(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static NSString *HPMHDisplayName(id value,BOOL map) {
    NSString *name=[[[HPMHText(value) stringByReplacingOccurrencesOfString:@"\\" withString:@"/"] lastPathComponent] stringByDeletingPathExtension];
    name=[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *key=[[[name lowercaseString] componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet] componentsJoinedByString:@""];
    if(!key.length||[@[@"unknown",@"none",@"unavailable"] containsObject:key])return map?@"Unknown map":@"Unknown game mode";
    NSDictionary *known=map?@{
        @"bloodgulch":@"Blood Gulch",@"hangemhigh":@"Hang ’Em High",@"battlecreek":@"Battle Creek",@"beavercreek":@"Battle Creek",
        @"boardingaction":@"Boarding Action",@"chillout":@"Chill Out",@"ratrace":@"Rat Race",@"putput":@"Chiron TL-34",@"carousel":@"Derelict"
    }:@{
        @"ctf":@"Capture the Flag",@"capturetheflag":@"Capture the Flag",@"koth":@"King of the Hill",@"king":@"King of the Hill",
        @"kingofhill":@"King of the Hill",@"kingofthehill":@"King of the Hill",@"slayer":@"Slayer",@"oddball":@"Oddball",
        @"race":@"Race",@"gungame":@"Gun Game",@"infection":@"Infection",@"swat":@"SWAT"
    };
    if(known[key])return known[key];
    static NSRegularExpression *words;static dispatch_once_t once;
    dispatch_once(&once,^{words=[NSRegularExpression regularExpressionWithPattern:@"([a-z0-9])([A-Z])" options:0 error:NULL];});
    name=[words stringByReplacingMatchesInString:name options:0 range:NSMakeRange(0,name.length) withTemplate:@"$1 $2"];
    name=[[name stringByReplacingOccurrencesOfString:@"_" withString:@" "] stringByReplacingOccurrencesOfString:@"-" withString:@" "];
    return name.capitalizedString;
}
static NSString *HPMHNumber(id value) {
    long long count=[value isKindOfClass:NSNumber.class]?[value longLongValue]:0;
    return [NSNumberFormatter localizedStringFromNumber:@(MAX(0LL,count)) numberStyle:NSNumberFormatterDecimalStyle];
}
static NSString *HPMHOutcome(NSDictionary *match) {
    switch([match[@"result"] integerValue]) {
        case -1:return @"Unfinished";case 1:return @"Victory";case 2:return @"Defeat";case 3:return @"Draw";
        default:return @"Unknown result";
    }
}
static UIColor *HPMHOutcomeColor(NSDictionary *match) {
    switch([match[@"result"] integerValue]) {
        case 1:return HPHaloColorKills();case 2:return HPHaloColorDeaths();case 3:return HPHaloColorGold();
        case -1:return HPHaloColorAccent();default:return HPHaloColorTextSecondary();
    }
}
static NSString *HPMHDate(id value) {
    NSDate *date=[[NSISO8601DateFormatter new] dateFromString:HPMHText(value)];
    if(!date)return @"Date unavailable";
    NSDateFormatter *format=[NSDateFormatter new];format.dateStyle=NSDateFormatterMediumStyle;format.timeStyle=NSDateFormatterShortStyle;
    return [format stringFromDate:date];
}
static NSString *HPMHKDA(NSDictionary *match,NSString *prefix) {
    return [NSString stringWithFormat:@"%@ K  ·  %@ D  ·  %@ A",HPMHNumber(match[[prefix stringByAppendingString:@"kills"]]),
        HPMHNumber(match[[prefix stringByAppendingString:@"deaths"]]),HPMHNumber(match[[prefix stringByAppendingString:@"assists"]])];
}
static BOOL HPMHProfileMatches(NSString *profile) {
    NSDictionary *current=HPHaloProgressMenuSnapshot();
    return profile.length && [HPMHText(current[@"profile_id"]) isEqualToString:profile];
}

@interface HPHaloHistoryMatchCell : UITableViewCell
@property(nonatomic,strong) HPHaloPanelView *panel;
@property(nonatomic,strong) UILabel *mapLabel,*detailLabel,*combatLabel,*medalLabel;
@property(nonatomic,strong) HPHaloTagView *resultTag;
- (void)configure:(NSDictionary *)match;
@end
@implementation HPHaloHistoryMatchCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if(!(self=[super initWithStyle:style reuseIdentifier:identifier]))return nil;
    self.backgroundColor=UIColor.clearColor;
    self.panel=[HPHaloPanelView new];self.panel.chamfer=13;self.panel.translatesAutoresizingMaskIntoConstraints=NO;
    [self.contentView addSubview:self.panel];
    self.mapLabel=HPHaloLabel(HPHaloDisplayFont(23,UIFontWeightHeavy,UIFontTextStyleTitle3,34),HPHaloColorText(),0);
    UIImageView *chevron=[[UIImageView alloc]initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
    chevron.tintColor=HPHaloColorAccent();chevron.contentMode=UIViewContentModeScaleAspectFit;
    [chevron.widthAnchor constraintEqualToConstant:14].active=YES;
    UIStackView *heading=[[UIStackView alloc]initWithArrangedSubviews:@[self.mapLabel,chevron]];heading.spacing=12;heading.alignment=UIStackViewAlignmentCenter;
    self.detailLabel=HPHaloLabel(HPHaloBodyFont(UIFontTextStyleFootnote,UIFontWeightRegular,0),HPHaloColorTextSecondary(),0);
    self.combatLabel=HPHaloLabel(HPHaloNumberFont(18,UIFontWeightBold,UIFontTextStyleBody,30),HPHaloColorText(),0);
    self.resultTag=[HPHaloTagView new];
    self.medalLabel=HPHaloLabel(HPHaloBodyFont(UIFontTextStyleFootnote,UIFontWeightMedium,0),HPHaloColorGold(),0);
    UIStackView *status=[[UIStackView alloc]initWithArrangedSubviews:@[self.resultTag,self.medalLabel]];
    status.spacing=12;status.alignment=UIStackViewAlignmentLeading;status.axis=UILayoutConstraintAxisVertical;
    UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[heading,self.detailLabel,self.combatLabel,status]];
    stack.axis=UILayoutConstraintAxisVertical;stack.spacing=8;stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.panel addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.panel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.panel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.panel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],HPCellBottom(self.panel,self.contentView,-4),
        [stack.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:self.panel.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:self.panel.bottomAnchor constant:-14]]];
    self.isAccessibilityElement=YES;self.accessibilityTraits=UIAccessibilityTraitButton;
    return self;
}
- (void)configure:(NSDictionary *)match {
    NSString *map=HPMHDisplayName(match[@"map"],YES),*mode=HPMHDisplayName(match[@"mode"],NO);
    HPHaloSetCaps(self.mapLabel,map,1.0);
    self.detailLabel.text=[NSString stringWithFormat:@"%@ · %@",mode,HPMHDate(match[@"started_at"])];
    self.combatLabel.text=HPMHKDA(match,@"");
    [self.resultTag setText:HPMHOutcome(match) color:HPMHOutcomeColor(match) filled:YES];
    self.panel.edgeColor=HPMHOutcomeColor(match);
    self.medalLabel.text=[match[@"medals_tracked"] boolValue]?[NSString stringWithFormat:@"%@ medals recorded",HPMHNumber(match[@"medal_total"])]:@"Medals were not tracked for this record";
    self.accessibilityLabel=[NSString stringWithFormat:@"%@, %@",self.mapLabel.text,HPMHOutcome(match)];
    self.accessibilityValue=[NSString stringWithFormat:@"%@. %@. %@",self.detailLabel.text,self.combatLabel.text,self.medalLabel.text];
    self.accessibilityHint=@"Opens the recorded match details.";
}
@end

@interface HPHaloHistoryDetailCell : UITableViewCell
@property(nonatomic,strong) UILabel *nameLabel,*valueLabel;
@property(nonatomic,strong) HPHaloPanelView *panel;
- (void)configure:(NSDictionary *)row;
@end
@implementation HPHaloHistoryDetailCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if(!(self=[super initWithStyle:style reuseIdentifier:identifier]))return nil;
    self.backgroundColor=UIColor.clearColor;self.selectionStyle=UITableViewCellSelectionStyleNone;
    self.panel=[HPHaloPanelView new];self.panel.chamfer=10;self.panel.translatesAutoresizingMaskIntoConstraints=NO;
    [self.contentView addSubview:self.panel];
    self.nameLabel=HPHaloLabel(HPHaloDisplayFont(12,UIFontWeightBold,UIFontTextStyleCaption1,20),HPHaloColorTextSecondary(),0);
    self.valueLabel=HPHaloLabel(HPHaloNumberFont(22,UIFontWeightSemibold,UIFontTextStyleTitle3,34),HPHaloColorText(),0);
    UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[self.nameLabel,self.valueLabel]];
    stack.axis=UILayoutConstraintAxisVertical;stack.spacing=4;stack.translatesAutoresizingMaskIntoConstraints=NO;[self.panel addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.panel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.panel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.panel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:3],HPCellBottom(self.panel,self.contentView,-3),
        [stack.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:self.panel.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:self.panel.bottomAnchor constant:-12]]];self.isAccessibilityElement=YES;return self;
}
- (void)configure:(NSDictionary *)row {
    HPHaloSetCaps(self.nameLabel,HPMHText(row[@"name"]),1.4);self.valueLabel.text=HPMHText(row[@"value"]);
    UIColor *color=[row[@"color"] isKindOfClass:UIColor.class]?row[@"color"]:HPHaloColorText();
    self.valueLabel.textColor=color;self.panel.edgeColor=row[@"color"]?color:nil;
    self.accessibilityLabel=HPMHText(row[@"name"]);self.accessibilityValue=self.valueLabel.text;
}
@end

@interface HPHaloMatchDetailViewController : UITableViewController
@property(nonatomic,copy) NSDictionary *match,*progressSnapshot;
@property(nonatomic,copy) NSString *profileID;
@property(nonatomic,copy) NSArray<NSDictionary *> *sections;
@property(nonatomic,strong) NSTimer *profileTimer;
@property(nonatomic) BOOL lifetime;
@end
@implementation HPHaloMatchDetailViewController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"Match Details";self.navigationItem.titleView=HPHaloNavigationTitle(self.title);
    HPHaloStyleTable(self.tableView);self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=82;
    self.tableView.accessibilityIdentifier=@"halopad.match-history.details";[self rebuildSections];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];[self checkProfile];__weak typeof(self) weak=self;
    self.profileTimer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){HPHaloMatchDetailViewController *owner=weak;if(!owner){[timer invalidate];return;}[owner checkProfile];}];
}
- (void)viewDidDisappear:(BOOL)animated {[super viewDidDisappear:animated];[self.profileTimer invalidate];self.profileTimer=nil;}
- (void)checkProfile {
    if(!HPMHProfileMatches(self.profileID)){self.match=nil;[self rebuildSections];[self.tableView reloadData];}
}
- (void)rebuildSections {
    if(!self.match){self.sections=@[@{@"title":@"Profile changed",@"rows":@[@{@"name":@"History unavailable",@"value":@"Return to Service Record to choose the current profile."}],@"footer":@""}];return;}
    NSDictionary *m=self.match;
    NSMutableArray *sections=[NSMutableArray array];
    [sections addObject:@{@"title":@"Recorded match",@"rows":@[
        @{@"name":@"Map",@"value":HPMHDisplayName(m[@"map"],YES)},@{@"name":@"Game mode",@"value":HPMHDisplayName(m[@"mode"],NO)},
        @{@"name":@"Outcome",@"value":HPMHOutcome(m),@"color":HPMHOutcomeColor(m)},
        @{@"name":@"Tracking started",@"value":HPMHDate(m[@"started_at"])}],
        @"footer":[m[@"completed"] boolValue]?([m[@"result"] integerValue]==0?@"The match ended, but its result was not recorded.":@"The outcome comes from the saved match result."):@"No completed result was recorded. An unfinished record is never treated as a loss."}];
    double deaths=[m[@"deaths"] doubleValue];
    NSString *ratio=deaths>0?[NSString stringWithFormat:@"%.2f",[m[@"kills"] doubleValue]/deaths]:@"—";
    [sections addObject:@{@"title":@"Tracked combat",@"rows":@[
        @{@"name":@"Kills",@"value":HPMHNumber(m[@"kills"]),@"color":HPHaloColorKills()},
        @{@"name":@"Deaths",@"value":HPMHNumber(m[@"deaths"]),@"color":HPHaloColorDeaths()},
        @{@"name":@"Assists",@"value":HPMHNumber(m[@"assists"])},@{@"name":@"K/D ratio",@"value":ratio},
        @{@"name":@"Best observed spree",@"value":HPMHNumber(m[@"best_streak"]),@"color":HPHaloColorGold()}],
        @"footer":[m[@"partial"] boolValue]?@"Tracking began after scores already existed. These totals exclude the scores from before tracking began.":@"Only recorded combat is shown. Opponents, duration and missing earlier activity are unavailable."}];
    if(!self.lifetime) {
        [sections addObject:@{@"title":HPHaloSeasonDisplay(HPMHText(self.progressSnapshot[@"season"])),@"rows":@[
            @{@"name":@"Combat recorded this season",@"value":HPMHKDA(m,@"season_")}],
            @"footer":@"A match can span two seasons. The tracked combat above covers the whole recorded match; this line covers the selected quarter only."}];
    }
    NSMutableArray *medals=[NSMutableArray array];
    NSDictionary *counts=m[@"medals"];
    for(NSDictionary *medal in HPHaloMedalCatalog()) {
        NSString *key=[NSString stringWithFormat:@"%lu",(unsigned long)[medal[@"id"] unsignedIntegerValue]];
        long long amount=[counts[key] longLongValue];
        if(amount>0)[medals addObject:@{@"name":HPMHText(medal[@"name"]),@"value":[@"×" stringByAppendingString:HPMHNumber(@(amount))],@"color":HPHaloColorGold()}];
    }
    if(!medals.count)[medals addObject:@{@"name":@"Medals",@"value":[m[@"medals_tracked"] boolValue]?@"No medals recorded":@"Not tracked for this record"}];
    [sections addObject:@{@"title":@"Match medals",@"rows":medals,@"footer":@"Saved awards from this match, including activity across a season boundary. Older awards are not reconstructed."}];
    self.sections=sections;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return self.sections.count;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return [self.sections[section][@"rows"] count];}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section{return HPHaloSectionHeaderView(self.sections[section][@"title"],nil);}
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section{return HPHaloSectionFooterView(self.sections[section][@"footer"]);}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    HPHaloHistoryDetailCell *cell=[tableView dequeueReusableCellWithIdentifier:@"detail"];
    if(!cell)cell=[[HPHaloHistoryDetailCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"detail"];
    [cell configure:self.sections[path.section][@"rows"][path.row]];return cell;
}
@end

@interface HPHaloMatchHistoryViewController : UITableViewController
@property(nonatomic,copy) NSDictionary *progressSnapshot,*history;
@property(nonatomic,copy) NSString *profileID,*guestPath;
@property(nonatomic,strong) UISegmentedControl *period;
@property(nonatomic,strong) UILabel *summary;
@property(nonatomic,strong) UIView *header;
@property(nonatomic,strong) UIStackView *headerStack;
@property(nonatomic,strong) NSTimer *profileTimer;
@property(nonatomic) BOOL lifetime,loading,profileChanged;
@property(nonatomic) NSUInteger requestGeneration;
@end
@implementation HPHaloMatchHistoryViewController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"Match History";self.navigationItem.titleView=HPHaloNavigationTitle(self.title);
    HPHaloStyleTable(self.tableView);self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=180;
    self.tableView.accessibilityIdentifier=@"halopad.match-history.list";
    self.header=[[UIView alloc]initWithFrame:CGRectMake(0,0,400,170)];
    UILabel *eyebrow=HPHaloLabel(HPHaloDisplayFont(12,UIFontWeightBold,UIFontTextStyleCaption1,20),HPHaloColorAccent(),0);
    /* The minimum header height can leave spare room on a wide screen. Give
     * that room to the summary instead of an arbitrary choice of two labels. */
    [eyebrow setContentHuggingPriority:UILayoutPriorityDefaultLow+1 forAxis:UILayoutConstraintAxisVertical];
    HPHaloSetCaps(eyebrow,@"Service Record / Match History",1.5);
    self.period=[[UISegmentedControl alloc]initWithItems:@[@"This Season",@"Lifetime"]];self.period.selectedSegmentIndex=self.lifetime?1:0;
    self.period.accessibilityIdentifier=@"halopad.match-history.period";self.period.accessibilityLabel=@"Match history period";
    HPHaloStyleSegmented(self.period);[self.period addTarget:self action:@selector(periodChanged) forControlEvents:UIControlEventValueChanged];
    self.summary=HPHaloLabel(HPHaloBodyFont(UIFontTextStyleSubheadline,UIFontWeightRegular,0),HPHaloColorTextSecondary(),0);
    self.headerStack=[[UIStackView alloc]initWithArrangedSubviews:@[eyebrow,self.period,self.summary]];
    self.headerStack.axis=UILayoutConstraintAxisVertical;self.headerStack.spacing=14;self.headerStack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.header addSubview:self.headerStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.headerStack.leadingAnchor constraintEqualToAnchor:self.header.safeAreaLayoutGuide.leadingAnchor constant:16],
        [self.headerStack.trailingAnchor constraintEqualToAnchor:self.header.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [self.headerStack.topAnchor constraintEqualToAnchor:self.header.topAnchor constant:18],
        [self.headerStack.bottomAnchor constraintEqualToAnchor:self.header.bottomAnchor constant:-16]]];
    self.tableView.tableHeaderView=self.header;
    self.refreshControl=[UIRefreshControl new];self.refreshControl.tintColor=HPHaloColorAccent();
    [self.refreshControl addTarget:self action:@selector(refreshHistory) forControlEvents:UIControlEventValueChanged];
    [self refreshHistory];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];[self checkProfile];__weak typeof(self) weak=self;
    self.profileTimer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){HPHaloMatchHistoryViewController *owner=weak;if(!owner){[timer invalidate];return;}[owner checkProfile];}];
}
- (void)viewDidDisappear:(BOOL)animated {[super viewDidDisappear:animated];[self.profileTimer invalidate];self.profileTimer=nil;}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];CGFloat width=CGRectGetWidth(self.tableView.bounds);if(!isfinite(width)||width<=0)return;
    self.header.frame=CGRectMake(0,0,width,CGRectGetHeight(self.header.frame));
    CGFloat fitted=[self.header systemLayoutSizeFittingSize:CGSizeMake(width,UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    CGFloat height=isfinite(fitted)?MAX((CGFloat)130,ceil(fitted)):(CGFloat)130;
    CGFloat current=CGRectGetHeight(self.header.frame);
    if(!isfinite(current)||fabs(height-current)>0.5){self.header.frame=CGRectMake(0,0,width,height);self.tableView.tableHeaderView=self.header;}
}
- (void)checkProfile {
    if(!HPMHProfileMatches(self.profileID)&&!self.profileChanged) {
        self.profileChanged=YES;self.requestGeneration++;self.loading=NO;self.history=nil;
        [self.refreshControl endRefreshing];[self updateSummary];[self.tableView reloadData];
    }
}
- (void)periodChanged {self.lifetime=self.period.selectedSegmentIndex==1;[self refreshHistory];}
- (void)updateSummary {
    NSArray *matches=self.history[@"matches"];
    if(self.profileChanged)self.summary.text=@"The saved profile changed. Return to Service Record to continue.";
    else if(self.loading)self.summary.text=@"Loading recorded matches…";
    else if([self.history[@"storage_error"] boolValue])self.summary.text=@"Match history is unavailable. Pull to retry.";
    else self.summary.text=[NSString stringWithFormat:@"%@ recorded %@%@. Tap a match for its details.",HPMHNumber(@(matches.count)),matches.count==1?@"match":@"matches",[self.history[@"has_more"] boolValue]?@" · showing the latest 100":@""];
    [self.view setNeedsLayout];
}
- (void)refreshHistory {
    [self checkProfile];if(self.profileChanged)return;
    /* Never leave the prior period's rows selectable beneath a new filter. */
    self.loading=YES;self.history=nil;NSUInteger generation=++self.requestGeneration;BOOL lifetime=self.lifetime;
    NSString *path=[self.guestPath copy],*profile=[self.profileID copy];[self updateSummary];
    [self.tableView reloadData];
    __weak typeof(self) weak=self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSDictionary *history=HPCareerStatsMatchHistory(path,lifetime,100);
        dispatch_async(dispatch_get_main_queue(),^{
            HPHaloMatchHistoryViewController *owner=weak;if(!owner||owner.requestGeneration!=generation)return;
            [owner checkProfile];if(owner.profileChanged)return;
            owner.loading=NO;
            owner.history=![history[@"storage_error"] boolValue]&&![HPMHText(history[@"profile_id"]) isEqualToString:profile]?
                @{@"storage_error":@YES,@"matches":@[]}:history;
            [owner.refreshControl endRefreshing];[owner updateSummary];[owner.tableView reloadData];
        });
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 1;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSArray *matches=self.history[@"matches"];return self.profileChanged||[self.history[@"storage_error"] boolValue]||!matches.count?1:matches.count;
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *season=HPMHText(self.history[@"season_id"]);
    return HPHaloSectionHeaderView(self.lifetime?@"Recent recorded matches":@"This season's matches",self.lifetime?nil:HPHaloSeasonDisplay(season));
}
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return HPHaloSectionFooterView(@"Only locally recorded matches are available. This Season includes a match with any recorded activity in the current quarter. Combat totals cover the recorded part of the whole match. Unfinished records are never counted as losses.");
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSArray *matches=self.history[@"matches"];
    if(self.profileChanged||[self.history[@"storage_error"] boolValue]||!matches.count) {
        HPHaloHistoryDetailCell *cell=[[HPHaloHistoryDetailCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        NSString *title=self.profileChanged?@"Profile changed":[self.history[@"storage_error"] boolValue]?@"History unavailable":self.loading?@"Loading…":@"No matches recorded";
        NSString *value=self.profileChanged?@"Return to Service Record.":[self.history[@"storage_error"] boolValue]?@"Pull down to retry. Your saved records are kept.":self.loading?@"Reading your local records.":@"Matches will appear after this saved profile plays. Earlier games cannot be reconstructed.";
        [cell configure:@{@"name":title,@"value":value}];return cell;
    }
    HPHaloHistoryMatchCell *cell=[tableView dequeueReusableCellWithIdentifier:@"match"];
    if(!cell)cell=[[HPHaloHistoryMatchCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"match"];
    [cell configure:matches[path.row]];cell.accessibilityIdentifier=[@"halopad.match-history.match." stringByAppendingString:HPMHText(matches[path.row][@"match_id"])];return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];[self checkProfile];
    NSArray *matches=self.history[@"matches"];if(self.loading||self.profileChanged||[self.history[@"storage_error"] boolValue]||path.row<0||(NSUInteger)path.row>=matches.count)return;
    HPHaloMatchDetailViewController *detail=[[HPHaloMatchDetailViewController alloc]initWithStyle:UITableViewStyleGrouped];
    NSMutableDictionary *context=[self.progressSnapshot mutableCopy];
    context[@"season"]=HPMHText(self.history[@"season_id"]);
    detail.match=matches[path.row];detail.profileID=self.profileID;detail.progressSnapshot=context;detail.lifetime=self.lifetime;
    [self.navigationController pushViewController:detail animated:YES];
}
@end

UIViewController *HPHaloMatchHistoryControllerMake(NSDictionary *progressSnapshot,BOOL lifetime) {
    HPHaloMatchHistoryViewController *controller=[[HPHaloMatchHistoryViewController alloc]initWithStyle:UITableViewStyleGrouped];
    controller.progressSnapshot=progressSnapshot?:@{};controller.profileID=HPMHText(progressSnapshot[@"profile_id"]);
    controller.guestPath=HPMHText(progressSnapshot[@"guest_profile_path"]);controller.lifetime=lifetime;return controller;
}
