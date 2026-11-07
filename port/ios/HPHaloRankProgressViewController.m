#import "HPHaloRankProgressViewController.h"
#import "HPHaloRankProgressModels.h"
#import "HPHaloTheme.h"
#include <math.h>

extern NSDictionary *HPHaloProgressMenuSnapshot(void);

static NSDictionary *HPRPDictionary(id value) { return [value isKindOfClass:NSDictionary.class] ? value : @{}; }
static NSString *HPRPString(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static NSString *HPRPNumber(id value) {
    if (![value isKindOfClass:NSNumber.class]) return @"—";
    return [NSNumberFormatter localizedStringFromNumber:value numberStyle:NSNumberFormatterDecimalStyle];
}
static NSString *HPRPRankTitle(NSDictionary *rank) {
    NSString *alternate=HPRPString(rank[@"alternateName"]);
    return alternate.length ? alternate : HPRPString(rank[@"name"]);
}

/* Timeline node: gold diamond for unlocked ranks, glowing ring for the current
 * rank and a hollow marker for ranks still ahead. */
@interface HPHaloRankNodeView : UIView
@property(nonatomic,copy) NSString *state;
@end
@implementation HPHaloRankNodeView
- (instancetype)initWithFrame:(CGRect)frame {
    if(!(self=[super initWithFrame:frame]))return nil;
    self.backgroundColor=UIColor.clearColor;self.opaque=NO;self.contentMode=UIViewContentModeRedraw;
    self.userInteractionEnabled=NO;self.isAccessibilityElement=NO;return self;
}
- (void)setState:(NSString *)state { _state=[state copy];[self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect {
    (void)rect;CGRect b=self.bounds;CGPoint c=CGPointMake(CGRectGetMidX(b),CGRectGetMidY(b));
    BOOL current=[self.state isEqualToString:@"current"],earned=[self.state isEqualToString:@"earned"];
    UIBezierPath *diamond=[UIBezierPath bezierPath];CGFloat r=current?8:6;
    [diamond moveToPoint:CGPointMake(c.x,c.y-r)];[diamond addLineToPoint:CGPointMake(c.x+r,c.y)];
    [diamond addLineToPoint:CGPointMake(c.x,c.y+r)];[diamond addLineToPoint:CGPointMake(c.x-r,c.y)];[diamond closePath];
    if(current){
        CGContextRef cg=UIGraphicsGetCurrentContext();
        CGContextSaveGState(cg);CGContextSetShadowWithColor(cg,CGSizeZero,8,HPHaloColorAccent().CGColor);
        [HPHaloColorAccent() setFill];[diamond fill];CGContextRestoreGState(cg);
        UIBezierPath *ring=[UIBezierPath bezierPathWithOvalInRect:CGRectInset(CGRectMake(c.x-13,c.y-13,26,26),0.5,0.5)];
        [[HPHaloColorAccent() colorWithAlphaComponent:0.55] setStroke];ring.lineWidth=1.25;[ring stroke];
    } else if(earned){
        [HPHaloColorGold() setFill];[diamond fill];
    } else {
        [HPHaloColorBackground() setFill];[diamond fill];
        [[HPHaloColorTextTertiary() colorWithAlphaComponent:0.9] setStroke];diamond.lineWidth=1.25;[diamond stroke];
    }
}
@end

@interface HPHaloRankRoadmapCell : UITableViewCell
@property(nonatomic,strong) UIImageView *badge;
@property(nonatomic,strong) UILabel *rankName;
@property(nonatomic,strong) UILabel *status;
@property(nonatomic,strong) UILabel *requirement;
@property(nonatomic,strong) UILabel *step;
@property(nonatomic,strong) HPHaloTagView *stateTag;
@property(nonatomic,strong) HPHaloPanelView *panel;
@property(nonatomic,strong) HPHaloGlowView *glow;
@property(nonatomic,strong) HPHaloRankNodeView *node;
@property(nonatomic,strong) UIView *railAbove;
@property(nonatomic,strong) UIView *railBelow;
@end

@implementation HPHaloRankRoadmapCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self=[super initWithStyle:style reuseIdentifier:identifier])) {
        self.selectionStyle=UITableViewCellSelectionStyleNone;
        self.backgroundColor=UIColor.clearColor;
        self.railAbove=[UIView new];self.railBelow=[UIView new];
        self.node=[HPHaloRankNodeView new];
        self.panel=[HPHaloPanelView new];self.panel.chamfer=12;
        self.glow=[HPHaloGlowView new];
        self.badge=[UIImageView new];self.badge.contentMode=UIViewContentModeScaleAspectFit;
        self.badge.isAccessibilityElement=NO;
        self.stateTag=[HPHaloTagView new];
        self.status=self.stateTag.label;
        self.rankName=HPHaloLabel(HPHaloDisplayFont(20,UIFontWeightHeavy,UIFontTextStyleTitle3,32),HPHaloColorText(),0);
        self.requirement=HPHaloLabel(HPHaloNumberFont(16,UIFontWeightSemibold,UIFontTextStyleSubheadline,26),HPHaloColorTextSecondary(),0);
        self.step=HPHaloLabel(HPHaloBodyFont(UIFontTextStyleFootnote,UIFontWeightRegular,22),HPHaloColorTextTertiary(),0);
        UIStackView *tagRow=[[UIStackView alloc]initWithArrangedSubviews:@[self.stateTag,[UIView new]]];
        tagRow.axis=UILayoutConstraintAxisHorizontal;
        UIStackView *text=[[UIStackView alloc]initWithArrangedSubviews:@[tagRow,self.rankName,self.requirement,self.step]];
        text.axis=UILayoutConstraintAxisVertical;text.spacing=3;[text setCustomSpacing:6 afterView:tagRow];
        for(UIView *view in @[self.railAbove,self.railBelow,self.node,self.panel,self.glow,self.badge,text]){
            view.translatesAutoresizingMaskIntoConstraints=NO;[self.contentView addSubview:view];
        }
        NSLayoutConstraint *textBottom=[text.bottomAnchor constraintEqualToAnchor:self.panel.bottomAnchor constant:-14];
        textBottom.priority=UILayoutPriorityDefaultHigh;
        [NSLayoutConstraint activateConstraints:@[
            [self.node.centerXAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:34],
            [self.node.centerYAnchor constraintEqualToAnchor:self.panel.centerYAnchor],
            [self.node.widthAnchor constraintEqualToConstant:28],[self.node.heightAnchor constraintEqualToConstant:28],
            [self.railAbove.centerXAnchor constraintEqualToAnchor:self.node.centerXAnchor],
            [self.railAbove.widthAnchor constraintEqualToConstant:2],
            [self.railAbove.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [self.railAbove.bottomAnchor constraintEqualToAnchor:self.node.centerYAnchor],
            [self.railBelow.centerXAnchor constraintEqualToAnchor:self.node.centerXAnchor],
            [self.railBelow.widthAnchor constraintEqualToConstant:2],
            [self.railBelow.topAnchor constraintEqualToAnchor:self.node.centerYAnchor],
            [self.railBelow.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor],
            [self.panel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:60],
            [self.panel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
            [self.panel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:5],
            HPCellBottom(self.panel,self.contentView,-5),
            [self.badge.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:16],
            [self.badge.centerYAnchor constraintEqualToAnchor:self.panel.centerYAnchor],
            [self.badge.widthAnchor constraintEqualToConstant:48],[self.badge.heightAnchor constraintEqualToConstant:72],
            [self.badge.topAnchor constraintGreaterThanOrEqualToAnchor:self.panel.topAnchor constant:12],
            [self.badge.bottomAnchor constraintLessThanOrEqualToAnchor:self.panel.bottomAnchor constant:-12],
            [self.glow.centerXAnchor constraintEqualToAnchor:self.badge.centerXAnchor],
            [self.glow.centerYAnchor constraintEqualToAnchor:self.badge.centerYAnchor],
            [self.glow.widthAnchor constraintEqualToConstant:110],[self.glow.heightAnchor constraintEqualToConstant:110],
            [text.leadingAnchor constraintEqualToAnchor:self.badge.trailingAnchor constant:16],
            [text.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-16],
            [text.topAnchor constraintEqualToAnchor:self.panel.topAnchor constant:14],
            [text.bottomAnchor constraintLessThanOrEqualToAnchor:self.panel.bottomAnchor constant:-14],textBottom]];
        self.isAccessibilityElement=YES;
    }
    return self;
}
- (void)configureRow:(NSDictionary *)row first:(BOOL)first last:(BOOL)last previousState:(NSString *)previous {
    NSDictionary *rank=HPRPDictionary(row[@"rank"]);
    NSString *state=HPRPString(row[@"state"]);
    BOOL current=[state isEqualToString:@"current"],earned=[state isEqualToString:@"earned"],locked=[state isEqualToString:@"locked"];
    UIColor *accent=HPHaloColorAccent(),*gold=HPHaloColorGold();
    self.badge.image=HPHaloRankBadgeImage(HPRPString(rank[@"file"]));
    self.badge.alpha=locked ? 0.42 : 1;
    self.rankName.textColor=locked ? HPHaloColorTextSecondary() : HPHaloColorText();
    HPHaloSetCaps(self.rankName,HPRPRankTitle(rank),1.0);
    NSString *tagText=current ? @"Current rank" : earned ? @"Unlocked" : locked ? @"Locked" : @"Requirement";
    [self.stateTag setText:tagText color:current ? accent : earned ? gold : HPHaloColorTextTertiary() filled:current];
    long long stepXP=[row[@"step_xp"] respondsToSelector:@selector(longLongValue)] ? [row[@"step_xp"] longLongValue] : 0;
    if (locked) self.requirement.text=[NSString stringWithFormat:@"%@ XP total · %@ to go",HPRPNumber(row[@"min_xp"]),HPRPNumber(row[@"remaining_xp"])];
    else if (current || earned) self.requirement.text=[NSString stringWithFormat:@"Unlocked at %@ XP",HPRPNumber(row[@"min_xp"])];
    else self.requirement.text=[NSString stringWithFormat:@"%@ XP total required",HPRPNumber(row[@"min_xp"])];
    self.requirement.textColor=current ? accent : HPHaloColorTextSecondary();
    self.step.text=stepXP>0 ? [NSString stringWithFormat:@"+%@ XP from the previous rank",HPRPNumber(row[@"step_xp"])] : @"Your starting rank";
    self.panel.fillColor=current ? [UIColor colorWithRed:0.06 green:0.16 blue:0.23 alpha:0.95] : locked ? [HPHaloColorPanel() colorWithAlphaComponent:0.55] : HPHaloColorPanel();
    self.panel.strokeColor=current ? [accent colorWithAlphaComponent:0.75] : earned ? [gold colorWithAlphaComponent:0.28] : HPHaloColorStroke();
    self.panel.edgeColor=current ? accent : earned ? [gold colorWithAlphaComponent:0.85] : nil;
    self.panel.glowColor=current ? [accent colorWithAlphaComponent:0.55] : nil;
    self.panel.showsBrackets=current;
    self.glow.hidden=!current;self.glow.glowColor=accent;
    self.node.state=state;
    UIColor *litRail=[gold colorWithAlphaComponent:0.75],*darkRail=[HPHaloColorTextTertiary() colorWithAlphaComponent:0.35];
    BOOL aboveLit=[previous isEqualToString:@"earned"] && (earned || current);
    self.railAbove.backgroundColor=aboveLit ? litRail : darkRail;
    self.railBelow.backgroundColor=earned ? litRail : darkRail;
    self.railAbove.hidden=first;self.railBelow.hidden=last;
    self.accessibilityLabel=[NSString stringWithFormat:@"%@. %@",HPRPRankTitle(rank),tagText];
    self.accessibilityValue=[NSString stringWithFormat:@"%@. %@",self.requirement.text,self.step.text];
}
@end

@interface HPHaloRankProgressViewController : UITableViewController
@property(nonatomic,copy) NSDictionary *progressSnapshot;
@property(nonatomic,copy) NSString *initialProfileID;
@property(nonatomic,copy) NSArray<NSDictionary *> *tiers;
@property(nonatomic,copy) NSDictionary *model;
@property(nonatomic,copy) NSArray<NSDictionary *> *visibleRanks;
@property(nonatomic,strong) UIView *header;
@property(nonatomic,strong) UIStackView *headerStack;
@property(nonatomic,strong) UIImageView *currentBadge;
@property(nonatomic,strong) HPHaloGlowView *currentGlow;
@property(nonatomic,strong) UILabel *eyebrow;
@property(nonatomic,strong) UILabel *currentName;
@property(nonatomic,strong) UILabel *currentXP;
@property(nonatomic,strong) UILabel *rankCount;
@property(nonatomic,strong) HPHaloPanelView *nextPanel;
@property(nonatomic,strong) UIImageView *nextBadge;
@property(nonatomic,strong) UILabel *nextEyebrow;
@property(nonatomic,strong) UILabel *nextName;
@property(nonatomic,strong) UILabel *remaining;
@property(nonatomic,strong) UILabel *progressCaption;
@property(nonatomic,strong) HPHaloMeterView *progressBar;
@property(nonatomic,strong) HPHaloMeterView *ladderBar;
@property(nonatomic,strong) UISegmentedControl *filter;
@property(nonatomic,strong) NSTimer *refreshTimer;
@property(nonatomic) BOOL revealed;
@property(nonatomic) CGFloat laidOutWidth;
@end

@implementation HPHaloRankProgressViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"Rank Progress";
    self.navigationItem.titleView=HPHaloNavigationTitle(@"Rank Progress");
    UIBarButtonItem *done=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeProgress)];
    HPHaloStyleDoneButton(done);self.navigationItem.rightBarButtonItem=done;
    HPHaloStyleTable(self.tableView);
    self.tableView.rowHeight=UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight=120;
    self.tableView.accessibilityIdentifier=@"halopad.rank.progress";
    [self.tableView registerClass:HPHaloRankRoadmapCell.class forCellReuseIdentifier:@"rank"];
    self.header=[[UIView alloc]initWithFrame:CGRectMake(0,0,420,460)];
    self.headerStack=[UIStackView new];self.headerStack.axis=UILayoutConstraintAxisVertical;
    self.headerStack.spacing=14;self.headerStack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.header addSubview:self.headerStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.headerStack.leadingAnchor constraintEqualToAnchor:self.header.safeAreaLayoutGuide.leadingAnchor constant:16],
        [self.headerStack.trailingAnchor constraintEqualToAnchor:self.header.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [self.headerStack.topAnchor constraintEqualToAnchor:self.header.topAnchor constant:18],
        [self.headerStack.bottomAnchor constraintEqualToAnchor:self.header.bottomAnchor constant:-16]]];

    /* Current rank hero. */
    HPHaloPanelView *hero=[HPHaloPanelView new];
    hero.chamfer=20;hero.showsBrackets=YES;hero.edgeColor=HPHaloColorGold();
    hero.fillColor=[UIColor colorWithRed:0.05 green:0.10 blue:0.15 alpha:0.92];
    self.currentGlow=[HPHaloGlowView new];self.currentGlow.glowColor=HPHaloColorGold();
    self.currentBadge=[UIImageView new];self.currentBadge.contentMode=UIViewContentModeScaleAspectFit;
    self.currentBadge.isAccessibilityElement=NO;
    self.eyebrow=HPHaloLabel(HPHaloDisplayFont(12,UIFontWeightBold,UIFontTextStyleCaption1,19),HPHaloColorAccent(),0);
    self.currentName=HPHaloLabel(HPHaloDisplayFont(34,UIFontWeightHeavy,UIFontTextStyleLargeTitle,48),HPHaloColorText(),0);
    self.currentName.layer.shadowColor=HPHaloColorGold().CGColor;self.currentName.layer.shadowRadius=12;
    self.currentName.layer.shadowOpacity=0.3f;self.currentName.layer.shadowOffset=CGSizeZero;
    self.currentXP=HPHaloLabel(HPHaloNumberFont(24,UIFontWeightBold,UIFontTextStyleTitle2,34),HPHaloColorGold(),0);
    self.rankCount=HPHaloLabel(HPHaloDisplayFont(13,UIFontWeightSemibold,UIFontTextStyleFootnote,20),HPHaloColorTextSecondary(),0);
    self.ladderBar=[HPHaloMeterView new];self.ladderBar.segments=MAX((NSUInteger)1,self.tiers.count);self.ladderBar.barHeight=6;
    self.ladderBar.meterColor=HPHaloColorGold();self.ladderBar.accessibilityLabel=@"Ranks unlocked this season";
    UIStackView *heroText=[[UIStackView alloc]initWithArrangedSubviews:@[self.eyebrow,self.currentName,self.currentXP,self.rankCount,self.ladderBar]];
    heroText.axis=UILayoutConstraintAxisVertical;heroText.spacing=4;
    [heroText setCustomSpacing:8 afterView:self.rankCount];
    for(UIView *view in @[self.currentGlow,self.currentBadge,heroText]){view.translatesAutoresizingMaskIntoConstraints=NO;[hero addSubview:view];}
    NSLayoutConstraint *heroBottom=[heroText.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor constant:-20];heroBottom.priority=UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [self.currentBadge.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor constant:22],
        [self.currentBadge.centerYAnchor constraintEqualToAnchor:hero.centerYAnchor],
        [self.currentBadge.widthAnchor constraintEqualToConstant:88],
        [self.currentBadge.heightAnchor constraintEqualToConstant:132],
        [self.currentBadge.topAnchor constraintGreaterThanOrEqualToAnchor:hero.topAnchor constant:16],
        [self.currentBadge.bottomAnchor constraintLessThanOrEqualToAnchor:hero.bottomAnchor constant:-16],
        [self.currentGlow.centerXAnchor constraintEqualToAnchor:self.currentBadge.centerXAnchor],
        [self.currentGlow.centerYAnchor constraintEqualToAnchor:self.currentBadge.centerYAnchor],
        [self.currentGlow.widthAnchor constraintEqualToConstant:200],[self.currentGlow.heightAnchor constraintEqualToConstant:200],
        [heroText.leadingAnchor constraintEqualToAnchor:self.currentBadge.trailingAnchor constant:22],
        [heroText.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-20],
        [heroText.topAnchor constraintEqualToAnchor:hero.topAnchor constant:20],
        [heroText.bottomAnchor constraintLessThanOrEqualToAnchor:hero.bottomAnchor constant:-20],heroBottom]];
    [self.headerStack addArrangedSubview:hero];

    /* Next promotion. */
    self.nextPanel=[HPHaloPanelView new];self.nextPanel.chamfer=14;self.nextPanel.edgeColor=HPHaloColorAccent();
    self.nextBadge=[UIImageView new];self.nextBadge.contentMode=UIViewContentModeScaleAspectFit;self.nextBadge.isAccessibilityElement=NO;
    self.nextEyebrow=HPHaloLabel(HPHaloDisplayFont(12,UIFontWeightBold,UIFontTextStyleCaption1,19),HPHaloColorTextSecondary(),0);
    HPHaloSetCaps(self.nextEyebrow,@"Next promotion",2.2);
    self.nextName=HPHaloLabel(HPHaloDisplayFont(22,UIFontWeightHeavy,UIFontTextStyleTitle2,32),HPHaloColorText(),0);
    self.remaining=HPHaloLabel(HPHaloNumberFont(26,UIFontWeightHeavy,UIFontTextStyleTitle1,38),HPHaloColorAccent(),0);
    self.remaining.layer.shadowColor=HPHaloColorAccent().CGColor;self.remaining.layer.shadowRadius=8;
    self.remaining.layer.shadowOpacity=0.4f;self.remaining.layer.shadowOffset=CGSizeZero;
    self.progressBar=[HPHaloMeterView new];self.progressBar.segments=10;self.progressBar.barHeight=12;
    self.progressBar.accessibilityLabel=@"Progress to next rank";
    self.progressCaption=HPHaloLabel(HPHaloDisplayFont(12,UIFontWeightSemibold,UIFontTextStyleCaption1,19),HPHaloColorTextSecondary(),0);
    UIStackView *nextText=[[UIStackView alloc]initWithArrangedSubviews:@[self.nextEyebrow,self.nextName,self.remaining]];
    nextText.axis=UILayoutConstraintAxisVertical;nextText.spacing=2;
    [NSLayoutConstraint activateConstraints:@[[self.nextBadge.widthAnchor constraintEqualToConstant:44],[self.nextBadge.heightAnchor constraintEqualToConstant:66]]];
    UIStackView *nextRow=[[UIStackView alloc]initWithArrangedSubviews:@[nextText,self.nextBadge]];
    nextRow.axis=UILayoutConstraintAxisHorizontal;nextRow.alignment=UIStackViewAlignmentCenter;nextRow.spacing=12;
    UIStackView *nextStack=[[UIStackView alloc]initWithArrangedSubviews:@[nextRow,self.progressBar,self.progressCaption]];
    nextStack.axis=UILayoutConstraintAxisVertical;nextStack.spacing=10;
    nextStack.translatesAutoresizingMaskIntoConstraints=NO;[self.nextPanel addSubview:nextStack];
    [NSLayoutConstraint activateConstraints:@[
        [nextStack.leadingAnchor constraintEqualToAnchor:self.nextPanel.leadingAnchor constant:20],
        [nextStack.trailingAnchor constraintEqualToAnchor:self.nextPanel.trailingAnchor constant:-18],
        [nextStack.topAnchor constraintEqualToAnchor:self.nextPanel.topAnchor constant:14],
        [nextStack.bottomAnchor constraintEqualToAnchor:self.nextPanel.bottomAnchor constant:-16]]];
    [self.headerStack addArrangedSubview:self.nextPanel];

    self.filter=[[UISegmentedControl alloc]initWithItems:@[@"Remaining",@"All Ranks"]];
    self.filter.selectedSegmentIndex=0;self.filter.accessibilityLabel=@"Rank list";
    HPHaloStyleSegmented(self.filter);
    [self.filter addTarget:self action:@selector(filterChanged) forControlEvents:UIControlEventValueChanged];
    [self.headerStack setCustomSpacing:18 afterView:self.nextPanel];
    [self.headerStack addArrangedSubview:self.filter];
    self.tableView.tableHeaderView=self.header;
    [self rebuild];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];[self refreshProgress];
    if(!self.revealed){
        self.revealed=YES;
        for(HPHaloMeterView *meter in @[self.progressBar,self.ladderBar]){
            CGFloat target=meter.progress;meter.progress=0;[meter layoutIfNeeded];[meter setProgress:target animated:YES];
        }
    }
    __weak typeof(self) weakSelf=self;
    self.refreshTimer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){ [weakSelf refreshProgress]; }];
}
- (void)viewDidDisappear:(BOOL)animated { [super viewDidDisappear:animated];[self.refreshTimer invalidate];self.refreshTimer=nil; }
- (void)dealloc { [_refreshTimer invalidate]; }
- (void)closeProgress { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)refreshProgress {
    NSDictionary *latest=HPHaloProgressMenuSnapshot();
    if (![latest isKindOfClass:NSDictionary.class]) return;
    NSString *newID=HPRPString(latest[@"profile_id"]);
    if (self.initialProfileID.length && newID.length && ![self.initialProfileID.uppercaseString isEqualToString:newID.uppercaseString]) {
        [self dismissViewControllerAnimated:NO completion:nil];
        return;
    } else if (!newID.length && ![latest[@"storage_error"] boolValue]) return;
    if ([self.progressSnapshot isEqualToDictionary:latest]) return;
    self.progressSnapshot=latest;[self rebuild];
}
- (void)rebuild {
    self.model=HPHaloRankProgressModel(self.progressSnapshot ?: @{},self.tiers ?: @[]);
    BOOL available=[self.model[@"available"] boolValue];
    NSArray *rows=[self.model[@"ranks"] isKindOfClass:NSArray.class] ? self.model[@"ranks"] : @[];
    NSDictionary *current=HPRPDictionary(self.model[@"current_rank"]),*next=HPRPDictionary(self.model[@"next_rank"]);
    if (available) {
        NSInteger left=[self.model[@"num_remaining"] integerValue];
        NSInteger position=(NSInteger)rows.count-MAX(0,left);
        HPHaloSetCaps(self.eyebrow,[NSString stringWithFormat:@"Local rank · %@",HPHaloSeasonDisplay(HPRPString(self.model[@"season"]))],2.2);
        HPHaloSetCaps(self.currentName,HPRPRankTitle(current),1.2);
        self.currentBadge.image=HPHaloRankBadgeImage(HPRPString(current[@"file"]));
        self.currentGlow.hidden=self.currentBadge.image==nil;
        self.currentXP.text=[NSString stringWithFormat:@"%@ XP",HPRPNumber(self.model[@"xp"])];
        HPHaloSetCaps(self.rankCount,[NSString stringWithFormat:@"Rank %ld of %ld · %ld remaining",(long)position,(long)rows.count,(long)left],1.4);
        CGFloat ladder=rows.count ? (CGFloat)position/(CGFloat)rows.count : 0;
        if(self.revealed)[self.ladderBar setProgress:ladder animated:YES];else self.ladderBar.progress=ladder;
        self.ladderBar.accessibilityValue=[NSString stringWithFormat:@"%ld of %ld",(long)position,(long)rows.count];
        self.ladderBar.hidden=NO;
        HPHaloSetCaps(self.nextName,next.count ? HPRPRankTitle(next) : @"Highest rank reached",1.0);
        self.nextBadge.image=next.count ? HPHaloRankBadgeImage(HPRPString(next[@"file"])) : HPHaloRankBadgeImage(HPRPString(current[@"file"]));
        self.nextBadge.alpha=next.count ? 0.85 : 1;
        self.remaining.textColor=next.count ? HPHaloColorAccent() : HPHaloColorGold();
        HPHaloSetCaps(self.remaining,next.count ? [NSString stringWithFormat:@"%@ XP to go",HPRPNumber(self.model[@"xp_to_next"])] : @"Every rank unlocked",0.6);
        CGFloat fraction=[self.model[@"current_progress"] floatValue];
        if(self.revealed)[self.progressBar setProgress:fraction animated:YES];else self.progressBar.progress=fraction;
        self.progressBar.meterColor=next.count ? HPHaloColorAccent() : HPHaloColorGold();
        HPHaloSetCaps(self.progressCaption,next.count ? [NSString stringWithFormat:@"%@ / %@ XP earned toward this rank",HPRPNumber(self.model[@"progress_earned"]),HPRPNumber(self.model[@"progress_span"])] : @"Your season XP keeps growing beyond the final rank",1.2);
        self.progressBar.accessibilityValue=next.count ? self.progressCaption.accessibilityLabel : @"Complete";
        self.progressBar.hidden=NO;
    } else {
        HPHaloSetCaps(self.eyebrow,@"Your local rank",2.2);
        HPHaloSetCaps(self.currentName,@"Rank unavailable",1.2);
        self.currentBadge.image=nil;self.currentGlow.hidden=YES;self.currentXP.text=@"";
        HPHaloSetCaps(self.rankCount,HPRPString(self.model[@"message"]),1.2);
        self.ladderBar.hidden=YES;
        HPHaloSetCaps(self.nextName,@"Explore every rank below",1.0);self.nextBadge.image=nil;
        HPHaloSetCaps(self.remaining,@"",0);
        HPHaloSetCaps(self.progressCaption,@"Current progress uses your named player profile’s season XP",1.2);
        self.progressBar.hidden=YES;
    }
    [self updateVisibleRanks];
}
- (void)filterChanged { [self updateVisibleRanks]; }
- (void)updateVisibleRanks {
    NSArray *all=[self.model[@"ranks"] isKindOfClass:NSArray.class] ? self.model[@"ranks"] : @[];
    if (self.filter.selectedSegmentIndex==1 || ![self.model[@"available"] boolValue]) self.visibleRanks=all;
    else {
        NSMutableArray *remaining=[NSMutableArray array];
        for(NSDictionary *row in all) if(![row[@"state"] isEqual:@"earned"]) [remaining addObject:row];
        self.visibleRanks=remaining;
    }
    [self.tableView reloadData];[self.view setNeedsLayout];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width=CGRectGetWidth(self.tableView.bounds);if(width<=0)return;
    self.header.frame=CGRectMake(0,0,width,CGRectGetHeight(self.header.frame));
    CGFloat height=[self.header systemLayoutSizeFittingSize:CGSizeMake(width,UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    if(fabs(height-CGRectGetHeight(self.header.frame))>0.5) {
        self.header.frame=CGRectMake(0,0,width,MAX(240,height));self.tableView.tableHeaderView=self.header;
    }
    if(fabs(width-self.laidOutWidth)>0.5){self.laidOutWidth=width;[self.tableView reloadData];}
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.visibleRanks.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.filter.selectedSegmentIndex==1 ? @"Every rank" : @"Your rank and the road ahead";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Local progression awards one XP per confirmed kill. XP total is the current calendar-quarter XP required for each local rank; XP to go is the remaining amount. Previous-quarter totals remain saved.";
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *trailing=[NSString stringWithFormat:@"%lu ranks",(unsigned long)self.visibleRanks.count];
    return HPHaloSectionHeaderView([self tableView:tableView titleForHeaderInSection:section],trailing);
}
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    return HPHaloSectionFooterView([self tableView:tableView titleForFooterInSection:section]);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    HPHaloRankRoadmapCell *cell=[tableView dequeueReusableCellWithIdentifier:@"rank" forIndexPath:path];
    NSDictionary *row=self.visibleRanks[path.row];
    NSString *previous=path.row>0 ? HPRPString(self.visibleRanks[path.row-1][@"state"]) : @"";
    [cell configureRow:row first:path.row==0 last:path.row+1==(NSInteger)self.visibleRanks.count previousState:previous];
    return cell;
}
@end

UIViewController *HPHaloRankProgressControllerMake(NSDictionary *progress, NSArray<NSDictionary *> *tiers) {
    HPHaloRankProgressViewController *controller=[[HPHaloRankProgressViewController alloc]initWithStyle:UITableViewStyleGrouped];
    controller.progressSnapshot=progress ?: @{};controller.tiers=tiers ?: @[];
    controller.initialProfileID=HPRPString(progress[@"profile_id"]);
    return controller;
}
