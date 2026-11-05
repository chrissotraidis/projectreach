#import "HPHaloProgressViewController.h"
#import "HPHaloProgressStore.h"
#import "HPHaloCareerStatsViewController.h"
#import "HPHaloTheme.h"
#import "HPHaloServiceRecordRanks.h"
#import <TargetConditionals.h>

static NSArray<NSDictionary *> *HPRankCatalog(void)
{
    return HPHaloServiceRecordRankCatalog();
}

static NSDictionary *HPRank(long long xp, NSDictionary **next)
{
    NSArray *tiers = HPRankCatalog();
    NSDictionary *rank = tiers.firstObject;
    if (next) *next = nil;
    for (NSDictionary *tier in tiers) {
        if ([tier[@"minXP"] longLongValue] > xp) { if (next) *next = tier; break; }
        rank = tier;
    }
    return rank;
}

static UIImage *HPRankImage(NSDictionary *rank)
{
    return HPHaloRankBadgeImage(rank[@"file"]);
}

static NSString *HPRankTitle(NSDictionary *rank)
{
    NSString *alternate = rank[@"alternateName"];
    return [alternate isKindOfClass:NSString.class] && alternate.length ? alternate : rank[@"name"] ?: @"Recruit";
}

static NSString *HPSeasonTitle(NSString *season)
{
    if (![season isKindOfClass:NSString.class]) return @"";
    if (season.length != 7 || [season characterAtIndex:4] != '-' ||
        [season characterAtIndex:5] != 'Q') return season;
    NSInteger quarter = [[season substringFromIndex:6] integerValue];
    if (quarter < 1 || quarter > 4) return season;
    NSArray<NSString *> *ranges = @[@"Jan–Mar", @"Apr–Jun", @"Jul–Sep", @"Oct–Dec"];
    return [NSString stringWithFormat:@"Q%ld %@ · %@", (long)quarter,
        [season substringToIndex:4], ranges[quarter - 1]];
}

@interface HPHaloProgressHitView : UIView
@property(nonatomic, weak) UIView *card;
@end
@implementation HPHaloProgressHitView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    if (self.hidden || self.card.hidden) return nil;
    UIView *hit = [super hitTest:point withEvent:event];
    return [hit isKindOfClass:UIControl.class] ? hit : nil;
}
@end

/* Navigation owns one input lease for the complete modal flow. Pushing Rank
   Progress or Medals keeps the lease; any completed dismissal releases it. */
@interface HPHaloStatsNavigationController : UINavigationController <UIAdaptivePresentationControllerDelegate>
@property(nonatomic, copy) void (^didDismissStats)(void);
- (void)finishStatsPresentation;
@end
@implementation HPHaloStatsNavigationController
- (void)finishStatsPresentation
{
    void (^finished)(void) = self.didDismissStats;
    self.didDismissStats = nil;
    if (finished) finished();
}
- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    if (self.isBeingDismissed || !self.presentingViewController) [self finishStatsPresentation];
}
- (void)presentationControllerDidDismiss:(UIPresentationController *)presentationController
{
    (void)presentationController;
    [self finishStatsPresentation];
}
@end

@interface HPHaloProgressViewController : UIViewController
@property(nonatomic, copy) void (^willPresentHistory)(void);
@property(nonatomic, copy) void (^didDismissHistory)(void);
@end

@implementation HPHaloProgressViewController
{
    HPHaloPanelView *card;
    HPHaloGlowView *badgeGlow;
    UIImageView *badge;
    UILabel *seasonLabel, *rankLabel, *xpLabel;
    HPHaloMeterView *progress;
    HPHaloPanelView *historyPlate;
    UIImageView *historyChevron;
    UIButton *historyButton;
    HPHaloTagView *promotionTag;
    CADisplayLink *displayLink;
    NSDictionary *lastSnapshot;
    NSString *lastRankKey;
    NSUInteger lastRankOrder;
    NSUInteger promotionGeneration;
    __weak UINavigationController *historyNavigation;
}
static UIFont *HPCardFont(CGFloat size, UIFontWeight weight)
{
    return [UIFont systemFontOfSize:size weight:weight width:UIFontWidthCondensed];
}
- (void)loadView
{
    HPHaloProgressHitView *root = [[HPHaloProgressHitView alloc] init];
    root.backgroundColor = UIColor.clearColor;
    self.view = root;
    card = [[HPHaloPanelView alloc] init];
    card.chamfer = 14;
    card.showsBrackets = YES;
    card.fillColor = [UIColor colorWithRed:0.015 green:0.035 blue:0.058 alpha:0.9];
    card.strokeColor = [HPHaloColorAccent() colorWithAlphaComponent:0.42];
    card.edgeColor = HPHaloColorAccent();
    card.glowColor = [HPHaloColorAccent() colorWithAlphaComponent:0.22];
    card.hidden = YES;
    root.card = card;
    [root addSubview:card];
    badgeGlow = [[HPHaloGlowView alloc] init];
    badgeGlow.glowColor = HPHaloColorGold();
    [card addSubview:badgeGlow];
    badge = [[UIImageView alloc] init];
    badge.contentMode = UIViewContentModeScaleAspectFit;
    [card addSubview:badge];
    seasonLabel = [self labelWithFont:HPCardFont(10.5, UIFontWeightHeavy) color:HPHaloColorAccent()];
    rankLabel = [self labelWithFont:HPCardFont(19, UIFontWeightHeavy) color:HPHaloColorText()];
    rankLabel.adjustsFontSizeToFitWidth = YES;
    rankLabel.minimumScaleFactor = 0.6;
    rankLabel.layer.shadowColor = HPHaloColorGold().CGColor;
    rankLabel.layer.shadowRadius = 8;
    rankLabel.layer.shadowOpacity = 0.3f;
    rankLabel.layer.shadowOffset = CGSizeZero;
    xpLabel = [self labelWithFont:HPCardFont(12, UIFontWeightSemibold) color:HPHaloColorTextSecondary()];
    xpLabel.adjustsFontSizeToFitWidth = YES;
    xpLabel.minimumScaleFactor = 0.75;
    progress = [[HPHaloMeterView alloc] init];
    progress.segments = 10;
    progress.barHeight = 6;
    [card addSubview:progress];
    historyButton = [UIButton buttonWithType:UIButtonTypeCustom];
    historyPlate = [[HPHaloPanelView alloc] init];
    historyPlate.chamfer = 6;
    historyPlate.userInteractionEnabled = NO;
    historyPlate.fillColor = [HPHaloColorAccent() colorWithAlphaComponent:0.16];
    historyPlate.strokeColor = [HPHaloColorAccent() colorWithAlphaComponent:0.7];
    historyPlate.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [historyButton addSubview:historyPlate];
    [historyButton setTitle:@"Service Record" forState:UIControlStateNormal];
    [historyButton setTitleColor:HPHaloColorAccent() forState:UIControlStateNormal];
    [historyButton setTitleColor:UIColor.whiteColor forState:UIControlStateHighlighted];
    [historyButton setTitleColor:HPHaloColorTextTertiary() forState:UIControlStateDisabled];
    historyButton.titleLabel.font = HPCardFont(14, UIFontWeightBold);
    UIImageSymbolConfiguration *symbol = [UIImageSymbolConfiguration configurationWithPointSize:9 weight:UIImageSymbolWeightHeavy];
    historyChevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:symbol]];
    historyChevron.tintColor = HPHaloColorAccent();
    historyChevron.contentMode = UIViewContentModeCenter;
    historyChevron.userInteractionEnabled = NO;
    [historyButton addSubview:historyChevron];
    historyButton.accessibilityLabel = @"Service Record";
    historyButton.accessibilityIdentifier = @"halopad.service-record.open";
    historyButton.accessibilityHint = @"View your career statistics, weapon and map records, medals, and match history.";
    [historyButton addTarget:self action:@selector(showHistory) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:historyButton];
    [historyButton sendSubviewToBack:historyPlate];
    promotionTag = [[HPHaloTagView alloc] init];
    promotionTag.hidden = YES;
    promotionTag.userInteractionEnabled = NO;
    [card addSubview:promotionTag];
    card.isAccessibilityElement = NO;
}
- (UILabel *)labelWithFont:(UIFont *)font color:(UIColor *)color
{
    UILabel *label = [[UILabel alloc] init];
    label.font = font;
    label.textColor = color;
    [card addSubview:label];
    return label;
}
- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CGRect area = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
    CGFloat width = MIN((CGFloat)300, MAX((CGFloat)0, area.size.width - 24));
    card.frame = CGRectMake(CGRectGetMaxX(area) - width - 12, CGRectGetMinY(area) + 12, width, 156);
    CGFloat textX = 84, textWidth = MAX((CGFloat)0, width - textX - 14);
    badge.frame = CGRectMake(14, 16, 58, 87);
    badgeGlow.frame = CGRectInset(badge.frame, -30, -22);
    seasonLabel.frame = CGRectMake(textX, 14, textWidth, 14);
    rankLabel.frame = CGRectMake(textX, 29, textWidth, 25);
    xpLabel.frame = CGRectMake(textX, 55, textWidth, 16);
    progress.frame = CGRectMake(textX, 77, textWidth, 6);
    historyButton.frame = CGRectMake(14, 100, MAX((CGFloat)0, width - 28), 44);
    historyPlate.frame = historyButton.bounds;
    historyChevron.frame = CGRectMake(CGRectGetWidth(historyButton.bounds) - 17, 0, 10, CGRectGetHeight(historyButton.bounds));
    CGSize tag = [promotionTag systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    promotionTag.frame = CGRectMake(textX, 10, MIN(tag.width, textWidth), tag.height);
}
- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (!displayLink) {
        displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(refresh:)];
        displayLink.preferredFrameRateRange = CAFrameRateRangeMake(15, 30, 30);
        [displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}
- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    [displayLink invalidate]; displayLink = nil;
    card.hidden = YES;
}
- (void)celebratePromotionTo:(NSString *)title
{
    NSUInteger generation = ++promotionGeneration;
    [promotionTag setText:@"Promoted" color:HPHaloColorGold() filled:YES];
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
    promotionTag.hidden = NO;
    promotionTag.alpha = 0;
    seasonLabel.alpha = 0;
    card.edgeColor = HPHaloColorGold();
    card.strokeColor = [HPHaloColorGold() colorWithAlphaComponent:0.75];
    card.glowColor = [HPHaloColorGold() colorWithAlphaComponent:0.5];
    BOOL motion = !UIAccessibilityIsReduceMotionEnabled();
    if (motion) {
        badge.transform = CGAffineTransformMakeScale(1.35, 1.35);
        badgeGlow.transform = CGAffineTransformMakeScale(0.5, 0.5);
    }
    badgeGlow.alpha = 1;
    [UIView animateWithDuration:0.55 delay:0 usingSpringWithDamping:0.6 initialSpringVelocity:0.3 options:0 animations:^{
        self->badge.transform = CGAffineTransformIdentity;
        self->badgeGlow.transform = CGAffineTransformMakeScale(1.2, 1.2);
        self->promotionTag.alpha = 1;
    } completion:nil];
    if (motion) {
        [UIView animateWithDuration:0.9 delay:0.5 options:UIViewAnimationOptionAutoreverse | UIViewAnimationOptionRepeat |
            UIViewAnimationOptionAllowUserInteraction animations:^{ self->badgeGlow.alpha = 0.45; } completion:nil];
    }
    if (UIAccessibilityIsVoiceOverRunning())
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, [NSString stringWithFormat:@"Promoted to %@", title]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != self->promotionGeneration) return;
        [self->badgeGlow.layer removeAllAnimations];
        [UIView animateWithDuration:0.5 animations:^{
            self->promotionTag.alpha = 0;
            self->seasonLabel.alpha = 1;
            self->badgeGlow.alpha = 1;
            self->badgeGlow.transform = CGAffineTransformIdentity;
        } completion:^(BOOL finished) {
            (void)finished;
            if (generation != self->promotionGeneration) return;
            self->promotionTag.hidden = YES;
            self->card.edgeColor = HPHaloColorAccent();
            self->card.strokeColor = [HPHaloColorAccent() colorWithAlphaComponent:0.42];
            self->card.glowColor = [HPHaloColorAccent() colorWithAlphaComponent:0.22];
        }];
    });
}
- (void)refresh:(CADisplayLink *)sender
{
    (void)sender;
    NSDictionary *snapshot = HPHaloProgressMenuSnapshot();
    BOOL storageUnavailable = ![snapshot[@"visible"] boolValue] &&
        [snapshot[@"menu_context"] boolValue] && [snapshot[@"storage_error"] boolValue];
    BOOL visible = ([snapshot[@"visible"] boolValue] || storageUnavailable) && HPRankCatalog().count > 0;
    card.hidden = !visible;
    if (!visible || (historyNavigation && ![snapshot[@"profile_id"] isEqual:lastSnapshot[@"profile_id"]]))
        [historyNavigation dismissViewControllerAnimated:NO completion:nil];
    if (!visible || [snapshot isEqualToDictionary:lastSnapshot]) return;
    lastSnapshot = snapshot;
    historyButton.enabled = !storageUnavailable;
    historyPlate.alpha = storageUnavailable ? 0.35 : 1;
    historyChevron.alpha = historyPlate.alpha;
    if (storageUnavailable) {
        badge.image = nil;
        badgeGlow.hidden = YES;
        HPHaloSetCaps(seasonLabel, @"Season rank", 2.0);
        HPHaloSetCaps(rankLabel, @"XP storage unavailable", 0.8);
        HPHaloSetCaps(xpLabel, @"Progress will retry automatically", 0.8);
        progress.progress = 0;
        return;
    }
    long long xp = [snapshot[@"xp"] longLongValue];
    NSDictionary *next = nil;
    NSDictionary *rank = HPRank(xp, &next);
    badge.image = HPRankImage(rank);
    badgeGlow.hidden = badge.image == nil;
    badge.accessibilityLabel = HPRankTitle(rank);
    HPHaloSetCaps(seasonLabel, HPSeasonTitle(snapshot[@"season"]), 2.0);
    HPHaloSetCaps(rankLabel, HPRankTitle(rank), 1.0);
    NSString *xpText = [NSNumberFormatter localizedStringFromNumber:@(MAX(0LL, xp)) numberStyle:NSNumberFormatterDecimalStyle];
    NSString *line = [snapshot[@"storage_error"] boolValue] ? @"Saving XP… retrying" : next ? [NSString stringWithFormat:@"%@ XP · %@ to next rank", xpText,
        [NSNumberFormatter localizedStringFromNumber:@([next[@"minXP"] longLongValue] - xp) numberStyle:NSNumberFormatterDecimalStyle]]
        : [NSString stringWithFormat:@"%@ XP · Highest rank", xpText];
    HPHaloSetCaps(xpLabel, line, 0.8);
    long long base = [rank[@"minXP"] longLongValue];
    long long target = [next[@"minXP"] longLongValue];
    [progress setProgress:next && target > base ? (CGFloat)((double)(xp - base) / (double)(target - base)) : 1 animated:YES];
    progress.meterColor = next ? HPHaloColorAccent() : HPHaloColorGold();
    progress.accessibilityLabel = @"Progress to next season rank";
    progress.accessibilityValue = line;
    /* Rank-up flare when this card next appears for the same profile and
     * season at a higher rank, e.g. back in the menu after a match. */
    NSUInteger order = [HPRankCatalog() indexOfObject:rank];
    NSString *key = [NSString stringWithFormat:@"%@|%@", snapshot[@"profile_id"] ?: @"", snapshot[@"season"] ?: @""];
    if (order != NSNotFound) {
        if ([key isEqualToString:lastRankKey] && order > lastRankOrder) [self celebratePromotionTo:HPRankTitle(rank)];
        lastRankKey = key;
        lastRankOrder = order;
    }
}
- (void)showHistory
{
    NSDictionary *snapshot = HPHaloProgressMenuSnapshot();
    UIViewController *presenter = self.parentViewController;
    if (![snapshot[@"visible"] boolValue] || !presenter.viewIfLoaded.window ||
        self.presentedViewController || presenter.presentedViewController) return;
    UIViewController *history = HPHaloCareerStatsControllerMake(snapshot);
    HPHaloStatsNavigationController *navigation = [[HPHaloStatsNavigationController alloc] initWithRootViewController:history];
    HPHaloStyleNavigation(navigation);
    navigation.didDismissStats = self.didDismissHistory;
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    historyNavigation = navigation;
    if (self.willPresentHistory) self.willPresentHistory();
    [presenter presentViewController:navigation animated:YES completion:nil];
    navigation.presentationController.delegate = navigation;
    if (presenter.presentedViewController != navigation) [navigation finishStatsPresentation];
}
@end

UIViewController *HPHaloProgressControllerMake(void (^willPresentHistory)(void))
{
    return HPHaloProgressControllerMakeWithDismissal(willPresentHistory, nil);
}

UIViewController *HPHaloProgressControllerMakeWithDismissal(void (^willPresentHistory)(void),
                                                           void (^didDismissHistory)(void))
{
    HPHaloProgressViewController *controller = [[HPHaloProgressViewController alloc] init];
    controller.willPresentHistory = willPresentHistory;
    controller.didDismissHistory = didDismissHistory;
    return controller;
}
