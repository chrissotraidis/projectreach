#import "HPHaloMedalsViewController.h"
#import "HPHaloMedalCatalog.h"
#import "HPCareerStatsStore.h"
#import "HPHaloTheme.h"
#include <math.h>
extern NSDictionary *HPHaloProgressMenuSnapshot(void);

@interface HPHaloMedalCollectionCell : UITableViewCell
@property(nonatomic,strong) UIImageView *badge;
@property(nonatomic,strong) HPHaloGlowView *glow;
@property(nonatomic,strong) HPHaloPanelView *panel;
@property(nonatomic,strong) UILabel *name;
@property(nonatomic,strong) UILabel *count;
@property(nonatomic,strong) UILabel *countCaption;
@property(nonatomic,strong) UILabel *requirement;
@property(nonatomic,strong) UIStackView *row;
@property(nonatomic,strong) UIView *countStack;
@property(nonatomic,strong) NSLayoutConstraint *countWidth;
- (void)configure:(NSDictionary *)medal unavailable:(BOOL)unavailable tracked:(BOOL)tracked;
- (void)configure:(NSDictionary *)medal unavailable:(BOOL)unavailable tracked:(BOOL)tracked compact:(BOOL)compact;
@end
@implementation HPHaloMedalCollectionCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if(!(self=[super initWithStyle:style reuseIdentifier:identifier]))return nil;
    self.selectionStyle=UITableViewCellSelectionStyleNone;self.backgroundColor=UIColor.clearColor;
    self.panel=[HPHaloPanelView new];self.panel.chamfer=12;self.panel.translatesAutoresizingMaskIntoConstraints=NO;
    [self.contentView addSubview:self.panel];
    self.glow=[HPHaloGlowView new];self.glow.translatesAutoresizingMaskIntoConstraints=NO;
    [self.contentView addSubview:self.glow];
    self.badge=[UIImageView new];self.badge.contentMode=UIViewContentModeScaleAspectFit;self.badge.isAccessibilityElement=NO;
    [NSLayoutConstraint activateConstraints:@[[self.badge.widthAnchor constraintEqualToConstant:64],[self.badge.heightAnchor constraintEqualToConstant:64]]];
    self.name=HPHaloLabel(HPHaloDisplayFont(20,UIFontWeightHeavy,UIFontTextStyleHeadline,30),HPHaloColorText(),0);
    self.requirement=HPHaloLabel(HPHaloBodyFont(UIFontTextStyleFootnote,UIFontWeightRegular,0),HPHaloColorTextSecondary(),0);
    UIStackView *text=[[UIStackView alloc]initWithArrangedSubviews:@[self.name,self.requirement]];text.axis=UILayoutConstraintAxisVertical;text.spacing=3;
    self.count=HPHaloLabel(HPHaloNumberFont(28,UIFontWeightHeavy,UIFontTextStyleTitle1,0),HPHaloColorAccent(),1);
    self.count.textAlignment=NSTextAlignmentRight;self.count.adjustsFontSizeToFitWidth=YES;self.count.minimumScaleFactor=0.5;
    self.countCaption=HPHaloLabel(HPHaloDisplayFont(11,UIFontWeightBold,UIFontTextStyleCaption2,0),HPHaloColorTextTertiary(),0);
    self.countCaption.textAlignment=NSTextAlignmentRight;
    /* Publish the measured count width before self-sizing the multiline text.
     * A soft zero-width preference leaves its wrapping width indeterminate in
     * the first narrow row while UIKit is estimating cell heights. */
    self.countStack=[UIView new];
    for(UILabel *label in @[self.count,self.countCaption]){
        label.translatesAutoresizingMaskIntoConstraints=NO;[self.countStack addSubview:label];
        [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    }
    self.countWidth=[self.countStack.widthAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[
        [self.count.topAnchor constraintEqualToAnchor:self.countStack.topAnchor],
        [self.count.trailingAnchor constraintEqualToAnchor:self.countStack.trailingAnchor],
        [self.count.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.countStack.leadingAnchor],
        [self.countCaption.topAnchor constraintEqualToAnchor:self.count.bottomAnchor],
        [self.countCaption.trailingAnchor constraintEqualToAnchor:self.countStack.trailingAnchor],
        [self.countCaption.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.countStack.leadingAnchor],
        [self.countCaption.bottomAnchor constraintEqualToAnchor:self.countStack.bottomAnchor],self.countWidth]];
    self.row=[[UIStackView alloc]initWithArrangedSubviews:@[self.badge,text,self.countStack]];
    self.row.axis=UILayoutConstraintAxisHorizontal;self.row.alignment=UIStackViewAlignmentCenter;self.row.spacing=14;
    self.row.translatesAutoresizingMaskIntoConstraints=NO;
    [self.contentView addSubview:self.row];
    [NSLayoutConstraint activateConstraints:@[
        [self.panel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.panel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.panel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
        HPCellBottom(self.panel,self.contentView,-4),
        [self.glow.centerXAnchor constraintEqualToAnchor:self.badge.centerXAnchor],
        [self.glow.centerYAnchor constraintEqualToAnchor:self.badge.centerYAnchor],
        [self.glow.widthAnchor constraintEqualToConstant:112],[self.glow.heightAnchor constraintEqualToConstant:112],
        [self.row.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:14],
        [self.row.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-18],
        [self.row.topAnchor constraintEqualToAnchor:self.panel.topAnchor constant:12],
        [self.row.bottomAnchor constraintEqualToAnchor:self.panel.bottomAnchor constant:-12]]];
    self.isAccessibilityElement=YES;return self;
}
- (void)updateCountWidth {
    CGFloat width=MAX([self.count sizeThatFits:CGSizeMake(CGFLOAT_MAX,CGFLOAT_MAX)].width,
        [self.countCaption sizeThatFits:CGSizeMake(CGFLOAT_MAX,CGFLOAT_MAX)].width);
    width=ceil(MAX((CGFloat)0,width));
    if(fabs(self.countWidth.constant-width)>0.5)self.countWidth.constant=width;
}
- (void)layoutSubviews {
    [self updateCountWidth];
    [super layoutSubviews];
}
- (void)configure:(NSDictionary *)medal unavailable:(BOOL)unavailable tracked:(BOOL)tracked {
    [self configure:medal unavailable:unavailable tracked:tracked compact:NO];
}
- (void)configure:(NSDictionary *)medal unavailable:(BOOL)unavailable tracked:(BOOL)tracked compact:(BOOL)compact {
    long long count=[medal[@"count"]longLongValue];
    BOOL spree=[medal[@"category"] isEqual:@"Killing sprees"];
    UIColor *tone=spree ? HPHaloColorGold() : HPHaloColorAccent();
    self.name.textColor=count ? HPHaloColorText() : HPHaloColorTextSecondary();
    HPHaloSetCaps(self.name,medal[@"name"],1.0);
    self.requirement.text=medal[@"requirement"];
    self.badge.image=HPHaloMedalBadgeImage([medal[@"id"]unsignedIntegerValue],76);
    self.badge.alpha=count?1:0.32;
    self.glow.hidden=count==0;self.glow.glowColor=tone;
    NSString *amount=[NSNumberFormatter localizedStringFromNumber:@(count) numberStyle:NSNumberFormatterDecimalStyle];
    NSString *status=unavailable?@"Unavailable":!tracked?@"Not tracked":count?[NSString stringWithFormat:@"%@ earned",amount]:@"Not earned yet";
    self.count.text=count&&!unavailable ? [@"×" stringByAppendingString:amount] : @"—";
    self.count.textColor=count ? tone : HPHaloColorTextTertiary();
    self.countCaption.textColor=count ? [tone colorWithAlphaComponent:0.8] : HPHaloColorTextTertiary();
    self.panel.edgeColor=count ? tone : nil;
    self.panel.strokeColor=count ? [tone colorWithAlphaComponent:0.32] : HPHaloColorStroke();
    self.panel.fillColor=count ? HPHaloColorPanel() : [HPHaloColorPanel() colorWithAlphaComponent:0.6];
    /* At accessibility sizes the count moves under the name instead of
     * squeezing the description into a narrow column. */
    self.row.axis=compact ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    self.row.alignment=compact ? UIStackViewAlignmentLeading : UIStackViewAlignmentCenter;
    HPHaloSetCaps(self.countCaption,unavailable?@"Unavailable":!tracked?@"Not tracked":count?@"Earned":@"Not yet",1.4);
    [self updateCountWidth];
    self.accessibilityLabel=medal[@"name"];self.accessibilityValue=[NSString stringWithFormat:@"%@. %@",status,self.requirement.text];
}
@end

@interface HPHaloMedalsViewController : UITableViewController
@property(nonatomic,copy) NSDictionary *progressSnapshot;
@property(nonatomic,copy) NSString *initialProfileID;
@property(nonatomic,copy) NSDictionary *careerSnapshot;
@property(nonatomic,copy) NSDictionary *model;
@property(nonatomic,copy) NSString *selectedSeason;
@property(nonatomic,strong) UIView *header;
@property(nonatomic,strong) UIStackView *headerStack;
@property(nonatomic,strong) UIStackView *showcase;
@property(nonatomic,strong) UISegmentedControl *period;
@property(nonatomic,strong) UILabel *summary;
@property(nonatomic,strong) UILabel *seasonTitle;
@property(nonatomic,strong) UILabel *eyebrow;
@property(nonatomic,strong) UILabel *note;
@property(nonatomic,strong) HPHaloMeterView *collectionMeter;
@property(nonatomic,strong) HPHaloTileButton *seasonButton;
@property(nonatomic,strong) HPHaloTileButton *latestMatchButton;
@property(nonatomic,strong) NSTimer *refreshTimer;
@property(nonatomic,assign) BOOL initialLifetime;
@property(nonatomic,assign) NSInteger activePeriod;
@property(nonatomic,assign) CGFloat laidOutWidth;
@end
@implementation HPHaloMedalsViewController
- (void)viewDidLoad {
    [super viewDidLoad];self.title=@"Medals";
    self.navigationItem.titleView=HPHaloNavigationTitle(@"Medals");
    UIBarButtonItem *done=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeMedals)];
    HPHaloStyleDoneButton(done);self.navigationItem.rightBarButtonItem=done;
    HPHaloStyleTable(self.tableView);
    self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=104;
    self.tableView.accessibilityIdentifier=@"halopad.medals.collection";
    self.header=[[UIView alloc]initWithFrame:CGRectMake(0,0,400,420)];
    self.headerStack=[UIStackView new];self.headerStack.axis=UILayoutConstraintAxisVertical;self.headerStack.spacing=14;self.headerStack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.header addSubview:self.headerStack];
    [NSLayoutConstraint activateConstraints:@[[self.headerStack.leadingAnchor constraintEqualToAnchor:self.header.safeAreaLayoutGuide.leadingAnchor constant:16],[self.headerStack.trailingAnchor constraintEqualToAnchor:self.header.safeAreaLayoutGuide.trailingAnchor constant:-16],[self.headerStack.topAnchor constraintEqualToAnchor:self.header.topAnchor constant:16],[self.headerStack.bottomAnchor constraintEqualToAnchor:self.header.bottomAnchor constant:-16]]];

    HPHaloPanelView *hero=[HPHaloPanelView new];hero.chamfer=18;hero.showsBrackets=YES;hero.edgeColor=HPHaloColorGold();
    hero.fillColor=[UIColor colorWithRed:0.05 green:0.10 blue:0.15 alpha:0.92];
    self.showcase=[UIStackView new];self.showcase.axis=UILayoutConstraintAxisHorizontal;self.showcase.alignment=UIStackViewAlignmentCenter;self.showcase.spacing=6;
    self.eyebrow=HPHaloLabel(HPHaloDisplayFont(12,UIFontWeightBold,UIFontTextStyleCaption1,19),HPHaloColorAccent(),0);
    self.seasonTitle=HPHaloLabel(HPHaloDisplayFont(32,UIFontWeightHeavy,UIFontTextStyleTitle1,44),HPHaloColorText(),0);
    self.summary=HPHaloLabel(HPHaloDisplayFont(15,UIFontWeightSemibold,UIFontTextStyleSubheadline,24),HPHaloColorTextSecondary(),0);
    self.collectionMeter=[HPHaloMeterView new];self.collectionMeter.segments=15;self.collectionMeter.barHeight=8;
    self.collectionMeter.meterColor=HPHaloColorGold();self.collectionMeter.accessibilityLabel=@"Medal types earned";
    UIStackView *heroStack=[[UIStackView alloc]initWithArrangedSubviews:@[self.showcase,self.eyebrow,self.seasonTitle,self.summary,self.collectionMeter]];
    heroStack.axis=UILayoutConstraintAxisVertical;heroStack.spacing=4;
    [heroStack setCustomSpacing:14 afterView:self.showcase];[heroStack setCustomSpacing:10 afterView:self.summary];
    heroStack.translatesAutoresizingMaskIntoConstraints=NO;[hero addSubview:heroStack];
    [NSLayoutConstraint activateConstraints:@[[heroStack.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor constant:20],[heroStack.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-20],[heroStack.topAnchor constraintEqualToAnchor:hero.topAnchor constant:18],[heroStack.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor constant:-20]]];
    [self.headerStack addArrangedSubview:hero];

    self.period=[[UISegmentedControl alloc]initWithItems:@[@"This Season",@"Lifetime",@"Past Seasons"]];self.activePeriod=self.initialLifetime?1:0;self.period.selectedSegmentIndex=self.activePeriod;self.period.accessibilityLabel=@"Medal statistics period";self.period.accessibilityIdentifier=@"halopad.medals.period";
    HPHaloStyleSegmented(self.period);
    [self.period addTarget:self action:@selector(periodChanged) forControlEvents:UIControlEventValueChanged];[self.headerStack addArrangedSubview:self.period];
    self.latestMatchButton=[HPHaloTileButton tile];
    [self.latestMatchButton setHeadline:@"Latest Match" detail:@"Your current or most recent game" icon:[UIImage systemImageNamed:@"flag.checkered"]];
    self.latestMatchButton.accessibilityIdentifier=@"halopad.medals.latest-match";self.latestMatchButton.accessibilityHint=@"Shows medals from your current or most recently recorded match.";
    [self.latestMatchButton addTarget:self action:@selector(showLatestMatch) forControlEvents:UIControlEventTouchUpInside];[self.headerStack addArrangedSubview:self.latestMatchButton];
    self.seasonButton=[HPHaloTileButton tile];
    [self.seasonButton setHeadline:@"Choose season" detail:@"Quarterly seasons saved on this device" icon:[UIImage systemImageNamed:@"calendar"]];
    self.seasonButton.showsMenuAsPrimaryAction=YES;self.seasonButton.accessibilityIdentifier=@"halopad.medals.season";[self.headerStack addArrangedSubview:self.seasonButton];
    self.note=HPHaloLabel(HPHaloBodyFont(UIFontTextStyleFootnote,UIFontWeightRegular,0),HPHaloColorTextSecondary(),0);[self.headerStack addArrangedSubview:self.note];
    self.tableView.tableHeaderView=self.header;[self refreshMedals];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];[self refreshMedals];
    __weak typeof(self) weakSelf=self;self.refreshTimer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){[weakSelf refreshMedals];}];
}
- (void)viewDidDisappear:(BOOL)animated{[super viewDidDisappear:animated];[self.refreshTimer invalidate];self.refreshTimer=nil;}
- (void)dealloc{[_refreshTimer invalidate];}
- (void)closeMedals{[self dismissViewControllerAnimated:YES completion:nil];}
- (void)periodChanged{self.activePeriod=self.period.selectedSegmentIndex;[self rebuildMedals];}
- (void)showLatestMatch{self.activePeriod=3;self.period.selectedSegmentIndex=UISegmentedControlNoSegment;[self rebuildMedals];[self.tableView setContentOffset:CGPointMake(0,-self.tableView.adjustedContentInset.top) animated:NO];}
- (void)selectSeason:(NSString *)season{self.selectedSeason=season;[self rebuildMedals];[self.tableView setContentOffset:CGPointMake(0,-self.tableView.adjustedContentInset.top) animated:NO];}
- (void)refreshMedals {
    NSDictionary *progress=HPHaloProgressMenuSnapshot();
    NSString *currentID=[progress[@"profile_id"]isKindOfClass:NSString.class]?progress[@"profile_id"]:nil;
    if(self.initialProfileID.length&&currentID.length&&![self.initialProfileID.uppercaseString isEqualToString:currentID.uppercaseString]) {
        [self dismissViewControllerAnimated:NO completion:nil];
        return;
    }
    if([progress isKindOfClass:NSDictionary.class]&&currentID.length)self.progressSnapshot=progress;
    NSDictionary *context=[self.progressSnapshot[@"menu_context"]isKindOfClass:NSDictionary.class]?self.progressSnapshot[@"menu_context"]:@{};
    NSString *path=[self.progressSnapshot[@"guest_profile_path"]isKindOfClass:NSString.class]?self.progressSnapshot[@"guest_profile_path"]:
        [context[@"path"]isKindOfClass:NSString.class]?context[@"path"]:@"";
    NSDictionary *career=path.length?HPCareerStatsSnapshot(path):@{@"storage_error":@"Select a named player profile to view saved medals."};
    if(![career isKindOfClass:NSDictionary.class])career=@{@"storage_error":@"Medal statistics are temporarily unavailable."};
    if([career[@"profile_id"]isKindOfClass:NSString.class] && ![[[NSUUID alloc]initWithUUIDString:career[@"profile_id"]]isEqual:[[NSUUID alloc]initWithUUIDString:self.progressSnapshot[@"profile_id"]]])career=@{@"storage_error":@"The player profile changed. Close and reopen Stats."};
    self.careerSnapshot=career;[self rebuildMedals];
}
- (UIView *)showcaseMedal:(NSUInteger)medalID earned:(BOOL)earned lead:(BOOL)lead {
    CGFloat size=lead ? 72 : 58;
    UIView *holder=[UIView new];holder.isAccessibilityElement=NO;
    HPHaloGlowView *glow=[HPHaloGlowView new];glow.glowColor=medalID>9 ? HPHaloColorGold() : HPHaloColorAccent();glow.hidden=!earned;
    UIImageView *image=[[UIImageView alloc]initWithImage:HPHaloMedalBadgeImage(medalID,size)];image.contentMode=UIViewContentModeScaleAspectFit;image.alpha=earned?1:0.3;
    for(UIView *view in @[glow,image]){view.translatesAutoresizingMaskIntoConstraints=NO;[holder addSubview:view];}
    [NSLayoutConstraint activateConstraints:@[
        [holder.widthAnchor constraintEqualToConstant:size],[holder.heightAnchor constraintEqualToConstant:size],
        [image.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor],[image.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor],
        [image.topAnchor constraintEqualToAnchor:holder.topAnchor],[image.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor],
        [glow.centerXAnchor constraintEqualToAnchor:holder.centerXAnchor],[glow.centerYAnchor constraintEqualToAnchor:holder.centerYAnchor],
        [glow.widthAnchor constraintEqualToConstant:size*1.7],[glow.heightAnchor constraintEqualToConstant:size*1.7]]];
    return holder;
}
- (void)rebuildShowcase:(NSDictionary *)model {
    for(UIView *view in self.showcase.arrangedSubviews){[self.showcase removeArrangedSubview:view];[view removeFromSuperview];}
    NSMutableArray *candidates=[NSMutableArray array];
    for(NSDictionary *row in model[@"rows"]) if([row[@"count"] longLongValue]>0) [candidates addObject:row];
    NSArray *earned=[candidates sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
            long long left=[a[@"count"] longLongValue],right=[b[@"count"] longLongValue];
            if(left!=right)return left>right?NSOrderedAscending:NSOrderedDescending;
            return [b[@"id"] compare:a[@"id"]];
        }];
    NSMutableArray *ids=[NSMutableArray array];
    for(NSDictionary *row in earned){ if(ids.count>=5)break; [ids addObject:row[@"id"]]; }
    BOOL any=ids.count>0;
    if(!any)[ids addObjectsFromArray:@[@1,@3,@10,@15]];
    for(NSUInteger i=0;i<ids.count;i++)[self.showcase addArrangedSubview:[self showcaseMedal:[ids[i] unsignedIntegerValue] earned:any lead:i==0&&any]];
    [self.showcase addArrangedSubview:[UIView new]];
}
- (void)rebuildMedals {
    NSDictionary *model=HPHaloMedalCollectionModel(self.progressSnapshot?:@{},self.careerSnapshot?:@{},self.activePeriod,self.selectedSeason);
    if([model isEqualToDictionary:self.model])return;self.model=model;self.selectedSeason=model[@"selected_season"];
    [self rebuildShowcase:model];
    HPHaloSetCaps(self.eyebrow,self.activePeriod==1?@"Service record · lifetime":self.activePeriod==2?@"Service record · past season":self.activePeriod==3?@"Service record · latest match":@"Service record · this season",2.2);
    HPHaloSetCaps(self.seasonTitle,model[@"title"],1.2);
    NSString *total=[NSNumberFormatter localizedStringFromNumber:model[@"total"] numberStyle:NSNumberFormatterDecimalStyle];
    NSString *summary=[model[@"storage_error"]boolValue]?@"Medal totals unavailable":![model[@"tracked"]boolValue]&&(self.activePeriod==2||self.activePeriod==3)?@"No recorded medal history":[NSString stringWithFormat:@"%@ medals · %@ of 15 types earned",total,model[@"earned_types"]];
    HPHaloSetCaps(self.summary,summary,1.4);
    self.collectionMeter.progress=(CGFloat)[model[@"earned_types"] doubleValue]/15.0;
    self.collectionMeter.accessibilityValue=[NSString stringWithFormat:@"%@ of 15",model[@"earned_types"]];
    self.note.text=model[@"note"];self.seasonButton.hidden=self.activePeriod!=2;
    self.latestMatchButton.activeLook=self.activePeriod==3;
    self.latestMatchButton.accessibilityTraits=UIAccessibilityTraitButton|(self.activePeriod==3?UIAccessibilityTraitSelected:0);
    NSMutableArray *actions=[NSMutableArray array];__weak typeof(self) weakSelf=self;
    for(NSDictionary *row in model[@"seasons"]) {
        NSString *season=row[@"season"];NSString *title=[NSString stringWithFormat:@"Q%@ %@",[season substringFromIndex:6],[season substringToIndex:4]];
        UIAction *action=[UIAction actionWithTitle:title image:nil identifier:nil handler:^(UIAction *value){[weakSelf selectSeason:season];}];
        action.state=[season isEqualToString:self.selectedSeason]?UIMenuElementStateOn:UIMenuElementStateOff;[actions addObject:action];
    }
    [self.seasonButton setHeadline:self.selectedSeason.length?HPHaloSeasonDisplay(self.selectedSeason):@"No past seasons" detail:actions.count?@"Tap to choose another quarterly season":@"Seasons appear here after they end" icon:[UIImage systemImageNamed:@"calendar"]];
    self.seasonButton.enabled=actions.count>0;self.seasonButton.menu=[UIMenu menuWithTitle:@"Quarterly seasons" children:actions];
    [self.tableView reloadData];[self.view setNeedsLayout];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];CGFloat width=CGRectGetWidth(self.tableView.bounds);if(width<=0)return;
    self.header.frame=CGRectMake(0,0,width,CGRectGetHeight(self.header.frame));
    CGFloat height=[self.header systemLayoutSizeFittingSize:CGSizeMake(width,UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    if(fabs(height-CGRectGetHeight(self.header.frame))>0.5){self.header.frame=CGRectMake(0,0,width,MAX(140,height));self.tableView.tableHeaderView=self.header;}
    /* Rows wrap differently at each width (Mac window resizing, rotation). */
    if(fabs(width-self.laidOutWidth)>0.5){self.laidOutWidth=width;[self.tableView reloadData];}
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 2;}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section{return section==0?9:6;}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section{return section==0?@"Multikills":@"Killing sprees";}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section{return section==0?@"Each new tier earns its own medal. Dying resets your multikill chain.":@"Each milestone is awarded once per life. Dying starts a new streak.";}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSArray *rows=self.model[@"rows"];NSUInteger earned=0,start=section==0?0:9,end=section==0?9:15;
    for(NSUInteger i=start;i<MIN(end,(NSUInteger)rows.count);i++)if([rows[i][@"count"] longLongValue]>0)earned++;
    return HPHaloSectionHeaderView([self tableView:tableView titleForHeaderInSection:section],[NSString stringWithFormat:@"%lu / %lu earned",(unsigned long)earned,(unsigned long)(end-start)]);
}
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return HPHaloSectionFooterView([self tableView:tableView titleForFooterInSection:section]);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    HPHaloMedalCollectionCell *cell=[tableView dequeueReusableCellWithIdentifier:@"medal"];if(!cell)cell=[[HPHaloMedalCollectionCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"medal"];
    NSDictionary *medal=self.model[@"rows"][path.section==0?path.row:path.row+9];
    BOOL compact=UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    [cell configure:medal unavailable:[self.model[@"storage_error"]boolValue] tracked:[self.model[@"tracked"]boolValue] compact:compact];return cell;
}
@end
UIViewController *HPHaloMedalsControllerMake(NSDictionary *progressSnapshot,NSDictionary *careerSnapshot,BOOL lifetime) {
    HPHaloMedalsViewController *controller=[[HPHaloMedalsViewController alloc]initWithStyle:UITableViewStyleGrouped];controller.progressSnapshot=progressSnapshot?:@{};controller.initialProfileID=[progressSnapshot[@"profile_id"]isKindOfClass:NSString.class]?progressSnapshot[@"profile_id"]:nil;controller.careerSnapshot=careerSnapshot?:@{};controller.initialLifetime=lifetime;return controller;
}
