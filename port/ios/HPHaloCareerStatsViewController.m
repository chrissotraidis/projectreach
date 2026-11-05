#import "HPHaloCareerStatsViewController.h"
#import "HPHaloCareerStatsModels.h"
#import "HPCareerStatsStore.h"
#import "HPHaloServiceRecordRanks.h"
#import "HPHaloRankProgressViewController.h"
#import "HPHaloMedalsViewController.h"
#import "HPHaloMedalCatalog.h"
#import "HPHaloMatchHistoryViewController.h"
#import "HPHaloTheme.h"
#import "HPHaloServiceRecordStyle.h"
#import "HPHaloProgressStore.h"
#import <objc/runtime.h>
#include <math.h>

extern NSDictionary *HPHaloProgressMenuSnapshot(void);

static NSString *HPCSString(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static NSArray *HPCSArray(id value) { return [value isKindOfClass:NSArray.class] ? value : @[]; }
static HPHaloTone HPCSTone(id value)
{
    NSString *tone = HPCSString(value);
    if ([tone isEqualToString:@"accent"]) return HPHaloToneAccent;
    if ([tone isEqualToString:@"gold"]) return HPHaloToneGold;
    if ([tone isEqualToString:@"kills"]) return HPHaloToneKills;
    if ([tone isEqualToString:@"deaths"]) return HPHaloToneDeaths;
    return HPHaloToneNeutral;
}
static BOOL HPCSNumeric(NSString *value)
{
    NSCharacterSet *letters = NSCharacterSet.letterCharacterSet;
    return value.length > 0 && [value rangeOfCharacterFromSet:letters].location == NSNotFound;
}

#pragma mark - Tiles

/* One stat: tiny caps name above a large condensed value. */
@interface HPHaloStatTile : HPHaloPanelView
@property(nonatomic, strong) UILabel *name;
@property(nonatomic, strong) UILabel *value;
@end
@implementation HPHaloStatTile
- (instancetype)initWithRow:(NSDictionary *)row
{
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    self.chamfer = 10;
    HPHaloTone tone = HPCSTone(row[@"tone"]);
    UIColor *color = HPHaloToneColor(tone);
    if (tone != HPHaloToneNeutral) self.edgeColor = [color colorWithAlphaComponent:0.9];
    NSString *valueText = HPCSString(row[@"value"]);
    self.name = HPHaloLabel(HPHaloDisplayFont(12, UIFontWeightSemibold, UIFontTextStyleCaption1, 19), HPHaloColorTextSecondary(), 0);
    HPHaloSetCaps(self.name, HPCSString(row[@"name"]), 1.5);
    UIFont *font = HPCSNumeric(valueText) ? HPHaloNumberFont(30, UIFontWeightBold, UIFontTextStyleTitle1, 44)
                                          : HPHaloDisplayFont(20, UIFontWeightBold, UIFontTextStyleTitle3, 32);
    self.value = HPHaloLabel(font, color, 0);
    self.value.text = valueText;
    if (tone != HPHaloToneNeutral) {
        self.value.layer.shadowColor = color.CGColor;
        self.value.layer.shadowOpacity = 0.35f;
        self.value.layer.shadowRadius = 6;
        self.value.layer.shadowOffset = CGSizeZero;
    }
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[self.name, self.value]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 4;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:11],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-11]]];
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = HPCSString(row[@"name"]);
    self.accessibilityValue = valueText;
    return self;
}
@end

@interface HPHaloStatGridCell : UITableViewCell
@property(nonatomic, strong) UIStackView *grid;
- (void)configureRows:(NSArray<NSDictionary *> *)rows columns:(NSUInteger)columns;
@end
@implementation HPHaloStatGridCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    if (!(self = [super initWithStyle:style reuseIdentifier:identifier])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.grid = [UIStackView new];
    self.grid.axis = UILayoutConstraintAxisVertical;
    self.grid.spacing = 10;
    self.grid.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.grid];
    [NSLayoutConstraint activateConstraints:@[
        [self.grid.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.grid.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.grid.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
        HPCellBottom(self.grid,self.contentView,-4)]];
    return self;
}
- (void)configureRows:(NSArray<NSDictionary *> *)rows columns:(NSUInteger)columns
{
    for (UIView *view in self.grid.arrangedSubviews) { [self.grid removeArrangedSubview:view]; [view removeFromSuperview]; }
    columns = MAX((NSUInteger)1, columns);
    for (NSUInteger start = 0; start < rows.count; start += columns) {
        UIStackView *line = [UIStackView new];
        line.axis = UILayoutConstraintAxisHorizontal;
        line.spacing = 10;
        line.distribution = UIStackViewDistributionFillEqually;
        line.alignment = UIStackViewAlignmentFill;
        for (NSUInteger i = start; i < MIN(rows.count, start + columns); i++)
            [line addArrangedSubview:[[HPHaloStatTile alloc] initWithRow:rows[i]]];
        [self.grid addArrangedSubview:line];
    }
}
@end

#pragma mark - Medal strip

@interface HPHaloMedalStripCell : UITableViewCell
@property(nonatomic, strong) HPH3SteelPanel *panel;
@property(nonatomic, strong) UILabel *totalLabel;
@property(nonatomic, strong) UILabel *totalCaption;
@property(nonatomic, strong) UIStackView *grid;
- (void)configureRows:(NSArray<NSDictionary *> *)rows width:(CGFloat)width;
@end
@implementation HPHaloMedalStripCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    if (!(self = [super initWithStyle:style reuseIdentifier:identifier])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.panel = [HPH3SteelPanel new];
    self.panel.accentColor = HPHaloColorGold();
    self.panel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:self.panel];
    self.totalCaption = HPHaloLabel(HPHaloDisplayFont(12, UIFontWeightSemibold, UIFontTextStyleCaption1, 19), HPHaloColorTextSecondary(), 0);
    self.totalLabel = HPHaloLabel(HPHaloNumberFont(34, UIFontWeightHeavy, UIFontTextStyleLargeTitle, 48), HPHaloColorGold(), 1);
    self.grid = [UIStackView new];
    self.grid.axis = UILayoutConstraintAxisVertical;
    self.grid.spacing = 12;
    UIStackView *summary = [[UIStackView alloc] initWithArrangedSubviews:@[self.totalCaption, self.totalLabel]];
    summary.axis = UILayoutConstraintAxisVertical;
    summary.spacing = 0;
    summary.isAccessibilityElement = YES;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[summary, self.grid]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.panel addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.panel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.panel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.panel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
        HPCellBottom(self.panel,self.contentView,-4),
        [stack.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:self.panel.topAnchor constant:14],
        [stack.bottomAnchor constraintEqualToAnchor:self.panel.bottomAnchor constant:-16]]];
    return self;
}
- (UIView *)itemForRow:(NSDictionary *)row
{
    NSUInteger medal = [row[@"medal_id"] unsignedIntegerValue];
    NSString *value = HPCSString(row[@"value"]);
    BOOL earned = value.length && ![value isEqualToString:@"0"];
    UIView *item = [UIView new];
    UIImageView *badge = [[UIImageView alloc] initWithImage:HPHaloMedalBadgeImage(medal, 52)];
    badge.contentMode = UIViewContentModeScaleAspectFit;
    badge.alpha = earned ? 1 : 0.24;
    UILabel *count = HPHaloLabel(HPHaloNumberFont(14, UIFontWeightBold, UIFontTextStyleFootnote, 20),
        earned ? HPHaloColorText() : HPHaloColorTextTertiary(), 1);
    count.textAlignment = NSTextAlignmentCenter;
    count.text = earned ? [@"×" stringByAppendingString:value] : @"—";
    count.adjustsFontSizeToFitWidth = YES;
    count.minimumScaleFactor = 0.6;
    for (UIView *view in @[badge, count]) { view.translatesAutoresizingMaskIntoConstraints = NO; [item addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        [badge.topAnchor constraintEqualToAnchor:item.topAnchor],
        [badge.centerXAnchor constraintEqualToAnchor:item.centerXAnchor],
        [badge.widthAnchor constraintEqualToConstant:46],
        [badge.heightAnchor constraintEqualToConstant:46],
        [count.topAnchor constraintEqualToAnchor:badge.bottomAnchor constant:2],
        [count.leadingAnchor constraintEqualToAnchor:item.leadingAnchor],
        [count.trailingAnchor constraintEqualToAnchor:item.trailingAnchor],
        [count.bottomAnchor constraintEqualToAnchor:item.bottomAnchor]]];
    item.isAccessibilityElement = YES;
    item.accessibilityLabel = HPCSString(row[@"name"]);
    item.accessibilityValue = earned ? [NSString stringWithFormat:@"%@ earned", value] : @"Not earned";
    return item;
}
- (void)configureRows:(NSArray<NSDictionary *> *)rows width:(CGFloat)width
{
    for (UIView *view in self.grid.arrangedSubviews) { [self.grid removeArrangedSubview:view]; [view removeFromSuperview]; }
    NSDictionary *total = rows.firstObject ?: @{};
    HPHaloSetCaps(self.totalCaption, HPCSString(total[@"name"]).length ? HPCSString(total[@"name"]) : @"Medals earned", 1.6);
    self.totalLabel.text = HPCSString(total[@"value"]).length ? HPCSString(total[@"value"]) : @"0";
    self.totalLabel.superview.accessibilityLabel = self.totalCaption.accessibilityLabel;
    self.totalLabel.superview.accessibilityValue = self.totalLabel.text;
    NSMutableArray *medals = [NSMutableArray array];
    for (NSDictionary *row in rows) if ([row[@"medal_id"] respondsToSelector:@selector(unsignedIntegerValue)]) [medals addObject:row];
    /* Nine across puts every multikill on one line and the sprees on the next. */
    CGFloat usable = MAX((CGFloat)120, width - 32 - 34);
    NSUInteger fit = (NSUInteger)floor((usable + 8) / 56);
    NSUInteger columns = fit >= 9 ? 9 : fit >= 5 ? 5 : MAX((NSUInteger)3, fit);
    for (NSUInteger start = 0; start < medals.count; start += columns) {
        UIStackView *line = [UIStackView new];
        line.axis = UILayoutConstraintAxisHorizontal;
        line.distribution = UIStackViewDistributionFillEqually;
        line.spacing = 8;
        for (NSUInteger i = start; i < start + columns; i++)
            [line addArrangedSubview:i < medals.count ? [self itemForRow:medals[i]] : [UIView new]];
        [self.grid addArrangedSubview:line];
    }
}
@end

#pragma mark - Breakdown and notice rows

@interface HPHaloBreakdownCell : UITableViewCell
@property(nonatomic, strong) HPH3SteelPanel *panel;
@property(nonatomic, strong) UILabel *place;
@property(nonatomic, strong) UILabel *caption;
@property(nonatomic, strong) UILabel *name;
@property(nonatomic, strong) UILabel *share;
@property(nonatomic, strong) UILabel *value;
@property(nonatomic, strong) HPHaloMeterView *bar;
- (void)configureRow:(NSDictionary *)row place:(NSUInteger)place maximum:(long long)maximum;
- (void)configureRow:(NSDictionary *)row place:(NSUInteger)place maximum:(long long)maximum spotlight:(nullable NSString *)spotlight;
@end
@implementation HPHaloBreakdownCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    if (!(self = [super initWithStyle:style reuseIdentifier:identifier])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.panel = [HPH3SteelPanel new];
    self.panel.userInteractionEnabled = NO;
    self.place = HPHaloLabel(HPHaloNumberFont(18, UIFontWeightHeavy, UIFontTextStyleHeadline, 26), HPH3Blue(), 1);
    self.place.textAlignment = NSTextAlignmentCenter;
    self.caption = HPHaloLabel(HPHaloDisplayFont(12, UIFontWeightBold, UIFontTextStyleCaption1, 19), HPHaloColorGold(), 0);
    self.name = HPHaloLabel(HPHaloDisplayFont(18, UIFontWeightSemibold, UIFontTextStyleBody, 28), HPH3Ice(), 0);
    self.share = HPHaloLabel(HPHaloNumberFont(15, UIFontWeightSemibold, UIFontTextStyleSubheadline, 22), HPHaloColorTextSecondary(), 1);
    self.share.textAlignment = NSTextAlignmentRight;
    self.value = HPHaloLabel(HPHaloNumberFont(22, UIFontWeightBold, UIFontTextStyleTitle3, 32), HPH3Ice(), 1);
    self.value.textAlignment = NSTextAlignmentRight;
    for (UILabel *label in @[self.place, self.share, self.value]) {
        [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    }
    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[self.caption, self.name]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 1;
    UIStackView *line = [[UIStackView alloc] initWithArrangedSubviews:@[self.place, text, self.share, self.value]];
    line.axis = UILayoutConstraintAxisHorizontal;
    line.alignment = UIStackViewAlignmentCenter;
    line.spacing = 12;
    self.bar = [HPHaloMeterView new];
    self.bar.barHeight = 4;
    self.bar.isAccessibilityElement = NO;
    for (UIView *view in @[self.panel, line, self.bar]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:view];
    }
    [NSLayoutConstraint activateConstraints:@[
        [self.panel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.panel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.panel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:2],
        HPCellBottom(self.panel,self.contentView,-2),
        [self.place.widthAnchor constraintEqualToConstant:34],
        [line.leadingAnchor constraintEqualToAnchor:self.panel.leadingAnchor constant:10],
        [line.trailingAnchor constraintEqualToAnchor:self.panel.trailingAnchor constant:-16],
        [line.topAnchor constraintEqualToAnchor:self.panel.topAnchor constant:11],
        [self.bar.leadingAnchor constraintEqualToAnchor:text.leadingAnchor],
        [self.bar.trailingAnchor constraintEqualToAnchor:self.value.trailingAnchor],
        [self.bar.topAnchor constraintEqualToAnchor:line.bottomAnchor constant:8],
        [self.bar.bottomAnchor constraintEqualToAnchor:self.panel.bottomAnchor constant:-12]]];
    self.isAccessibilityElement = YES;
    return self;
}
- (void)configureRow:(NSDictionary *)row place:(NSUInteger)place maximum:(long long)maximum
{
    [self configureRow:row place:place maximum:maximum spotlight:nil];
}
- (void)configureRow:(NSDictionary *)row place:(NSUInteger)place maximum:(long long)maximum spotlight:(NSString *)spotlight
{
    BOOL empty = [row[@"empty"] boolValue];
    BOOL lead = spotlight.length && place == 1 && !empty;
    long long amount = [row[@"amount"] respondsToSelector:@selector(longLongValue)] ? MAX(0LL, [row[@"amount"] longLongValue]) : 0;
    self.caption.hidden = !lead;
    HPHaloSetCaps(self.caption, lead ? spotlight : @"", 1.8);
    self.name.font = lead ? HPHaloDisplayFont(28, UIFontWeightHeavy, UIFontTextStyleTitle1, 40) : HPHaloDisplayFont(18, UIFontWeightSemibold, UIFontTextStyleBody, 28);
    self.value.font = lead ? HPHaloNumberFont(34, UIFontWeightHeavy, UIFontTextStyleLargeTitle, 46) : HPHaloNumberFont(22, UIFontWeightBold, UIFontTextStyleTitle3, 32);
    self.name.textColor = empty ? HPHaloColorTextSecondary() : HPH3Ice();
    if (lead) HPHaloSetCaps(self.name, HPCSString(row[@"name"]), 0.8);
    else { self.name.attributedText = nil; self.name.text = HPCSString(row[@"name"]); }
    self.value.text = HPCSString(row[@"value"]);
    NSString *share = HPCSString(row[@"share"]);
    self.share.text = empty || !share.length ? @"" : share;
    self.share.hidden = self.share.text.length == 0;
    self.place.text = empty ? @"—" : [NSString stringWithFormat:@"%02lu", (unsigned long)place];
    UIColor *tint = place == 1 && !empty ? HPHaloColorGold() : HPH3Blue();
    self.place.textColor = empty ? HPHaloColorTextTertiary() : tint;
    self.panel.accentColor = place == 1 && !empty ? HPHaloColorGold() : nil;
    self.panel.raised = lead;
    self.panel.striped = lead;
    self.panel.shade = place % 2 ? 0 : -0.018;
    self.bar.meterColor = tint;
    self.bar.barHeight = lead ? 6 : 4;
    self.bar.progress = maximum > 0 ? (CGFloat)((double)amount / (double)maximum) : 0;
    self.bar.hidden = empty;
    self.accessibilityLabel = lead ? [NSString stringWithFormat:@"%@: %@", spotlight, HPCSString(row[@"name"])] : HPCSString(row[@"name"]);
    self.accessibilityValue = empty ? nil : [NSString stringWithFormat:@"%@ kills%@, place %lu", self.value.text,
        self.share.text.length ? [NSString stringWithFormat:@", %@ of credited kills", self.share.text] : @"", (unsigned long)place];
}
@end

@interface HPHaloNoticeCell : UITableViewCell
@property(nonatomic, strong) UILabel *title;
@property(nonatomic, strong) UILabel *message;
@end
@implementation HPHaloNoticeCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    if (!(self = [super initWithStyle:style reuseIdentifier:identifier])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    HPHaloPanelView *panel = [HPHaloPanelView new];
    panel.edgeColor = HPHaloColorGold();
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.triangle.fill"]];
    icon.tintColor = HPHaloColorGold();
    icon.contentMode = UIViewContentModeScaleAspectFit;
    self.title = HPHaloLabel(HPHaloDisplayFont(17, UIFontWeightBold, UIFontTextStyleHeadline, 28), HPHaloColorText(), 0);
    self.message = HPHaloLabel(HPHaloBodyFont(UIFontTextStyleSubheadline, UIFontWeightRegular, 26), HPHaloColorTextSecondary(), 0);
    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[self.title, self.message]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 3;
    for (UIView *view in @[panel, icon, text]) { view.translatesAutoresizingMaskIntoConstraints = NO; [self.contentView addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        [panel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [panel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [panel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
        HPCellBottom(panel,self.contentView,-4),
        [icon.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:18],
        [icon.centerYAnchor constraintEqualToAnchor:panel.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:22],
        [icon.heightAnchor constraintEqualToConstant:22],
        [text.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:14],
        [text.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16],
        [text.topAnchor constraintEqualToAnchor:panel.topAnchor constant:14],
        [text.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-14]]];
    self.isAccessibilityElement = YES;
    return self;
}
@end

#pragma mark - Stats

/* Native tabs keep a 44-point target at every text size. The containing scroll
 * view permits the complete labels on narrow windows instead of truncating. */
@interface HPHaloRecordTabButton : UIButton
@property(nonatomic,strong) HPHaloPanelView *panel;
@property(nonatomic,strong) UIView *underline;
@property(nonatomic,strong) UILabel *caption;
- (instancetype)initWithTitle:(NSString *)title;
@end
@implementation HPHaloRecordTabButton
- (instancetype)initWithTitle:(NSString *)title {
    if(!(self=[super initWithFrame:CGRectZero]))return nil;
    self.panel=[HPHaloPanelView new];self.panel.chamfer=3;self.panel.userInteractionEnabled=NO;
    self.underline=[UIView new];self.underline.backgroundColor=HPH3Ice();self.underline.userInteractionEnabled=NO;
    self.underline.layer.shadowColor=HPH3Blue().CGColor;self.underline.layer.shadowRadius=6;
    self.underline.layer.shadowOpacity=0.9f;self.underline.layer.shadowOffset=CGSizeZero;
    self.caption=HPHaloLabel(HPHaloDisplayFont(14,UIFontWeightBold,UIFontTextStyleSubheadline,23),HPHaloColorTextSecondary(),1);
    HPHaloSetCaps(self.caption,title,1.4);self.caption.textAlignment=NSTextAlignmentCenter;
    self.caption.userInteractionEnabled=NO;
    for(UIView *view in @[self.panel,self.underline,self.caption]){view.translatesAutoresizingMaskIntoConstraints=NO;[self addSubview:view];}
    [NSLayoutConstraint activateConstraints:@[
        [self.underline.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:10],
        [self.underline.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
        [self.underline.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.underline.heightAnchor constraintEqualToConstant:3],
        [self.panel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.panel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.panel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.panel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.caption.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
        [self.caption.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [self.caption.topAnchor constraintEqualToAnchor:self.topAnchor constant:12],
        [self.caption.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-12],
        [self.widthAnchor constraintGreaterThanOrEqualToConstant:108],
        [self.heightAnchor constraintGreaterThanOrEqualToConstant:44]]];
    self.isAccessibilityElement=YES;self.accessibilityLabel=title;
    self.accessibilityTraits=UIAccessibilityTraitButton;
    return self;
}
- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    self.panel.fillColor=selected?[UIColor colorWithRed:0.11 green:0.21 blue:0.29 alpha:0.92]:[UIColor colorWithWhite:1 alpha:0.035];
    self.panel.strokeColor=[UIColor colorWithWhite:1 alpha:selected?0.22:0.07];
    self.panel.edgeColor=nil;self.panel.showsBrackets=NO;
    self.underline.hidden=!selected;
    self.caption.textColor=selected?HPH3Ice():HPHaloColorTextSecondary();
    HPHaloSetCaps(self.caption,self.accessibilityLabel,1.4);
    self.accessibilityTraits=UIAccessibilityTraitButton|(selected?UIAccessibilityTraitSelected:0);
}
@end

@interface HPHaloCareerStatsViewController : UITableViewController
@property(nonatomic,copy) NSDictionary *progressSnapshot;
@property(nonatomic,copy) NSString *initialProfileID;
@property(nonatomic,copy) NSDictionary *careerSnapshot;
@property(nonatomic,copy) NSArray<NSDictionary *> *tiers;
@property(nonatomic,copy) NSArray<NSDictionary *> *sections;
@property(nonatomic,strong) UISegmentedControl *period;
@property(nonatomic,strong) UILabel *profileLabel;
@property(nonatomic,strong) UILabel *rankLabel;
@property(nonatomic,strong) UILabel *seasonLabel;
@property(nonatomic,strong) HPH3CountLabel *xpLabel;
@property(nonatomic,strong) UILabel *nextLabel;
@property(nonatomic,strong) HPHaloMeterView *rankMeter;
@property(nonatomic,strong) UIImageView *badge;
@property(nonatomic,strong) HPHaloGlowView *badgeGlow;
@property(nonatomic,strong) UIView *header;
@property(nonatomic,strong) UIStackView *headerStack;
@property(nonatomic,strong) UIStackView *tileRow;
@property(nonatomic,strong) UIView *heroPanel;
@property(nonatomic,strong) HPH3NameplateView *nameplate;
@property(nonatomic,copy) NSString *playerName;
@property(nonatomic,copy) NSString *playerNamePath;
@property(nonatomic) BOOL countUpArmed;
@property(nonatomic,strong) NSTimer *refreshTimer;
@property(nonatomic,strong) HPHaloTileButton *rankProgressButton;
@property(nonatomic,strong) HPHaloTileButton *medalsButton;
@property(nonatomic,strong) HPHaloTileButton *historyButton;
@property(nonatomic,strong) UIScrollView *pageScroll;
@property(nonatomic,copy) NSArray<HPHaloRecordTabButton *> *pageButtons;
@property(nonatomic) HPHaloServiceRecordPage recordPage;
@property(nonatomic,copy) NSString *breakdownSourceName;
@property(nonatomic,strong) UILabel *detailLabel;
@property(nonatomic) BOOL initialLifetime;
@property(nonatomic) CGFloat laidOutWidth;
@property(nonatomic) BOOL meterRevealed;
@end

@implementation HPHaloCareerStatsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"Stats";
    self.navigationItem.titleView=HPHaloNavigationTitle(@"Service Record");
    UIBarButtonItem *done=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeStats)];
    HPHaloStyleDoneButton(done);
    self.navigationItem.rightBarButtonItem=done;
    HPHaloStyleTable(self.tableView);
    self.tableView.backgroundView=[HPH3Backdrop new];
    self.tableView.rowHeight=UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight=120;
    self.tableView.accessibilityIdentifier=@"halopad.career.stats";
    /* Numbers tick up once as the record opens, like a post-game report. */
    self.countUpArmed=UIView.areAnimationsEnabled&&!UIAccessibilityIsReduceMotionEnabled();
    self.tiers=HPHaloServiceRecordRankCatalog();

    if(self.breakdownSourceName.length){[self buildDetailHeader];[self refreshStats];return;}

    self.header=[[UIView alloc]initWithFrame:CGRectMake(0,0,400,360)];
    self.headerStack=[[UIStackView alloc]init];
    self.headerStack.axis=UILayoutConstraintAxisVertical;
    self.headerStack.spacing=14;
    self.headerStack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.header addSubview:self.headerStack];
    [NSLayoutConstraint activateConstraints:@[
        [self.headerStack.leadingAnchor constraintEqualToAnchor:self.header.safeAreaLayoutGuide.leadingAnchor constant:16],
        [self.headerStack.trailingAnchor constraintEqualToAnchor:self.header.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [self.headerStack.topAnchor constraintEqualToAnchor:self.header.topAnchor constant:16],
        [self.headerStack.bottomAnchor constraintEqualToAnchor:self.header.bottomAnchor constant:-16]]];

    /* Lobby-style nameplate: emblem, saved player name, rank badge and XP. */
    self.nameplate=[HPH3NameplateView new];
    self.heroPanel=self.nameplate;
    self.badge=self.nameplate.badge;self.badgeGlow=self.nameplate.badgeGlow;
    self.profileLabel=self.nameplate.eyebrowLabel;self.rankLabel=self.nameplate.rankLabel;
    self.seasonLabel=self.nameplate.standingLabel;self.xpLabel=self.nameplate.xpLabel;
    self.nextLabel=self.nameplate.nextLabel;self.rankMeter=self.nameplate.meter;
    self.rankMeter.accessibilityLabel=@"Progress to next season rank";
    [self.headerStack addArrangedSubview:self.nameplate];

    self.rankProgressButton=[HPHaloTileButton tile];
    [self.rankProgressButton setHeadline:@"Rank Progress" detail:@"Every badge and the XP needed to reach it" icon:[UIImage systemImageNamed:@"chevron.up.2"]];
    self.rankProgressButton.accessibilityIdentifier=@"halopad.stats.rank-progress";
    self.rankProgressButton.accessibilityHint=@"Shows your current rank, your next promotion, and XP needed for every remaining rank.";
    [self.rankProgressButton addTarget:self action:@selector(showRankProgress) forControlEvents:UIControlEventTouchUpInside];
    self.medalsButton=[HPHaloTileButton tile];
    [self.medalsButton setHeadline:@"Medal Chest" detail:@"Your collection and totals for every season" icon:HPHaloMedalBadgeImage(3,40)];
    self.medalsButton.panel.edgeColor=HPHaloColorGold();
    self.medalsButton.accessibilityIdentifier=@"halopad.stats.medals";
    self.medalsButton.accessibilityHint=@"Shows multikill and killing spree badges, requirements, and saved counts by season.";
    [self.medalsButton addTarget:self action:@selector(showMedals) forControlEvents:UIControlEventTouchUpInside];
    self.historyButton=[HPHaloTileButton tile];
    [self.historyButton setHeadline:@"Match History" detail:@"Recorded games, results and match details" icon:[UIImage systemImageNamed:@"clock.arrow.circlepath"]];
    self.historyButton.accessibilityIdentifier=@"halopad.stats.match-history";
    self.historyButton.accessibilityHint=@"Opens the recorded matches for this saved player profile.";
    [self.historyButton addTarget:self action:@selector(showMatchHistory) forControlEvents:UIControlEventTouchUpInside];
    for(HPHaloTileButton *tile in @[self.rankProgressButton,self.medalsButton,self.historyButton]){
        tile.panel.chamfer=4;tile.panel.strokeColor=[UIColor colorWithWhite:1 alpha:0.13];
        tile.panel.fillColor=[UIColor colorWithRed:0.075 green:0.140 blue:0.195 alpha:0.93];
        if(tile!=self.medalsButton)tile.panel.edgeColor=HPH3Blue();
    }
    self.tileRow=[[UIStackView alloc]initWithArrangedSubviews:@[self.rankProgressButton,self.medalsButton,self.historyButton]];
    self.tileRow.spacing=12;self.tileRow.distribution=UIStackViewDistributionFill;
    self.tileRow.axis=UILayoutConstraintAxisVertical;
    [self.headerStack addArrangedSubview:self.tileRow];

    [self buildPeriodControl];
    [self.headerStack setCustomSpacing:18 afterView:self.tileRow];
    [self.headerStack addArrangedSubview:self.period];
    [self buildPageTabs];
    [self.headerStack insertArrangedSubview:self.pageScroll atIndex:0];
    self.tableView.tableHeaderView=self.header;
    [self refreshStats];
}
- (void)buildPeriodControl {
    self.period=[[UISegmentedControl alloc]initWithItems:@[@"This Season",@"Lifetime"]];
    self.period.selectedSegmentIndex=self.initialLifetime?1:0;
    self.period.accessibilityLabel=@"Statistics period";
    self.period.accessibilityIdentifier=@"halopad.service-record.period";
    HPHaloStyleSegmented(self.period);
    [self.period addTarget:self action:@selector(periodChanged) forControlEvents:UIControlEventValueChanged];
}
- (void)buildPageTabs {
    self.pageScroll=[UIScrollView new];self.pageScroll.showsHorizontalScrollIndicator=NO;
    self.pageScroll.accessibilityIdentifier=@"halopad.service-record.pages";
    UIStackView *tabs=[UIStackView new];tabs.axis=UILayoutConstraintAxisHorizontal;
    tabs.distribution=UIStackViewDistributionFillEqually;tabs.spacing=8;tabs.translatesAutoresizingMaskIntoConstraints=NO;
    [self.pageScroll addSubview:tabs];
    NSArray *names=@[@"Overview",@"Weapons",@"Maps",@"Game Modes"];
    NSArray *identifiers=@[@"overview",@"weapons",@"maps",@"modes"];
    NSMutableArray *buttons=[NSMutableArray array];
    for(NSUInteger index=0;index<names.count;index++) {
        HPHaloRecordTabButton *button=[[HPHaloRecordTabButton alloc]initWithTitle:names[index]];
        button.tag=(NSInteger)index;button.selected=index==(NSUInteger)self.recordPage;
        button.accessibilityIdentifier=[@"halopad.service-record." stringByAppendingString:identifiers[index]];
        [button addTarget:self action:@selector(recordPageChanged:) forControlEvents:UIControlEventTouchUpInside];
        [tabs addArrangedSubview:button];[buttons addObject:button];
    }
    self.pageButtons=buttons;
    [NSLayoutConstraint activateConstraints:@[
        [tabs.leadingAnchor constraintEqualToAnchor:self.pageScroll.contentLayoutGuide.leadingAnchor],
        [tabs.trailingAnchor constraintEqualToAnchor:self.pageScroll.contentLayoutGuide.trailingAnchor],
        [tabs.topAnchor constraintEqualToAnchor:self.pageScroll.contentLayoutGuide.topAnchor],
        [tabs.bottomAnchor constraintEqualToAnchor:self.pageScroll.contentLayoutGuide.bottomAnchor],
        [tabs.heightAnchor constraintEqualToAnchor:self.pageScroll.frameLayoutGuide.heightAnchor],
        [tabs.widthAnchor constraintGreaterThanOrEqualToAnchor:self.pageScroll.frameLayoutGuide.widthAnchor],
        [self.pageScroll.heightAnchor constraintGreaterThanOrEqualToConstant:44]]];
}
- (void)buildDetailHeader {
    self.header=[[UIView alloc]initWithFrame:CGRectMake(0,0,400,140)];
    self.headerStack=[UIStackView new];self.headerStack.axis=UILayoutConstraintAxisVertical;self.headerStack.spacing=16;
    self.headerStack.translatesAutoresizingMaskIntoConstraints=NO;[self.header addSubview:self.headerStack];
    self.detailLabel=HPHaloLabel(HPHaloBodyFont(UIFontTextStyleSubheadline,UIFontWeightMedium,26),HPHaloColorTextSecondary(),0);
    [self.headerStack addArrangedSubview:self.detailLabel];[self buildPeriodControl];[self.headerStack addArrangedSubview:self.period];
    [NSLayoutConstraint activateConstraints:@[
        [self.headerStack.leadingAnchor constraintEqualToAnchor:self.header.safeAreaLayoutGuide.leadingAnchor constant:16],
        [self.headerStack.trailingAnchor constraintEqualToAnchor:self.header.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [self.headerStack.topAnchor constraintEqualToAnchor:self.header.topAnchor constant:16],
        [self.headerStack.bottomAnchor constraintEqualToAnchor:self.header.bottomAnchor constant:-16]]];
    self.tableView.tableHeaderView=self.header;
    self.tableView.accessibilityIdentifier=@"halopad.service-record.breakdown-detail";
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if(self.countUpArmed){
        __weak typeof(self) weakSelf=self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{weakSelf.countUpArmed=NO;});
    }
    [self refreshStats];
    if(!self.meterRevealed){
        self.meterRevealed=YES;CGFloat target=self.rankMeter.progress;
        self.rankMeter.progress=0;[self.rankMeter layoutIfNeeded];[self.rankMeter setProgress:target animated:YES];
    }
    __weak typeof(self) weakSelf=self;
    self.refreshTimer=[NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer){ [weakSelf refreshStats]; }];
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];[self.refreshTimer invalidate];self.refreshTimer=nil;
}
- (void)dealloc { [_refreshTimer invalidate]; }
- (void)closeStats { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)showRankProgress {
    if(!self.navigationController)return;
    self.navigationItem.backButtonTitle=@"Stats";
    [self.navigationController pushViewController:HPHaloRankProgressControllerMake(self.progressSnapshot ?: @{},self.tiers ?: @[]) animated:YES];
}
- (void)showMedals {
    if(!self.navigationController)return;self.navigationItem.backButtonTitle=@"Stats";
    [self.navigationController pushViewController:HPHaloMedalsControllerMake(self.progressSnapshot?:@{},self.careerSnapshot?:@{},self.period.selectedSegmentIndex==1) animated:YES];
}
- (void)showMatchHistory {
    if(!self.navigationController)return;
    self.navigationItem.backButtonTitle=@"Service Record";
    [self.navigationController pushViewController:HPHaloMatchHistoryControllerMake(self.progressSnapshot?:@{},self.period.selectedSegmentIndex==1) animated:YES];
}
- (void)recordPageChanged:(HPHaloRecordTabButton *)sender {
    self.recordPage=(HPHaloServiceRecordPage)sender.tag;
    for(HPHaloRecordTabButton *button in self.pageButtons)button.selected=button==sender;
    [self rebuildSections];[self.view layoutIfNeeded];
    [self.tableView setContentOffset:CGPointMake(0,-self.tableView.adjustedContentInset.top) animated:NO];
    CGRect selected=[sender convertRect:sender.bounds toView:self.pageScroll];
    [self.pageScroll scrollRectToVisible:CGRectInset(selected,-4,0) animated:YES];
}
- (void)periodChanged { [self rebuildSections]; }
- (void)openHighlight:(NSDictionary *)row {
    if([row[@"medals"] boolValue]){[self showMedals];return;}
    if(![row[@"page"] isKindOfClass:NSNumber.class])return;
    NSInteger page=[row[@"page"] integerValue];
    for(HPHaloRecordTabButton *button in self.pageButtons)
        if(button.tag==page){[self recordPageChanged:button];return;}
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width=CGRectGetWidth(self.tableView.bounds);
    if(width<=0)return;
    BOOL largeText=UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    UILayoutConstraintAxis axis=width>=760 && !largeText ? UILayoutConstraintAxisHorizontal : UILayoutConstraintAxisVertical;
    if(self.tileRow.axis!=axis)self.tileRow.axis=axis;
    self.tileRow.distribution=axis==UILayoutConstraintAxisHorizontal ? UIStackViewDistributionFillEqually : UIStackViewDistributionFill;
    BOOL compact=CGRectGetHeight(self.view.bounds)>0&&CGRectGetHeight(self.view.bounds)<500&&axis==UILayoutConstraintAxisHorizontal;
    if(self.tileRow)
        for(HPHaloTileButton *button in @[self.rankProgressButton,self.medalsButton,self.historyButton])button.detail.hidden=compact;
    self.header.frame=CGRectMake(0,0,width,CGRectGetHeight(self.header.frame));
    CGFloat height=[self.header systemLayoutSizeFittingSize:CGSizeMake(width,UILayoutFittingCompressedSize.height) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    /* Compare the published height, not the smaller unconstrained fit. Otherwise
     * a compact page below this minimum republishes the same header forever. */
    height=MAX((CGFloat)140,ceil(height));
    if(fabs(height-CGRectGetHeight(self.header.frame))>0.5){
        self.header.frame=CGRectMake(0,0,width,height);self.tableView.tableHeaderView=self.header;
    }
    if(fabs(width-self.laidOutWidth)>0.5){self.laidOutWidth=width;[self.tableView reloadData];}
}
- (void)refreshStats {
    NSDictionary *current=HPHaloProgressMenuSnapshot();
    NSString *currentID=[current[@"profile_id"] isKindOfClass:NSString.class] ? current[@"profile_id"] : nil;
    if(self.initialProfileID.length && currentID.length && ![self.initialProfileID.uppercaseString isEqualToString:currentID.uppercaseString]) {
        /* The presenting game may disappear under a full-screen sheet. Keep
         * profile isolation here as well, independent of its display link. */
        [self dismissViewControllerAnimated:NO completion:nil];
        return;
    }
    if([current isKindOfClass:NSDictionary.class] && currentID.length) self.progressSnapshot=current;
    NSDictionary *context=[self.progressSnapshot[@"menu_context"] isKindOfClass:NSDictionary.class] ? self.progressSnapshot[@"menu_context"] : @{};
    NSString *path=[self.progressSnapshot[@"guest_profile_path"] isKindOfClass:NSString.class] ? self.progressSnapshot[@"guest_profile_path"] :
        [context[@"path"] isKindOfClass:NSString.class] ? context[@"path"] : @"";
    if(![path isEqualToString:self.playerNamePath?:@""]){
        self.playerNamePath=path;self.playerName=path.length?HPHaloProgressPlayerName(path):nil;
        objc_setAssociatedObject(self,@selector(refreshStats),nil,OBJC_ASSOCIATION_COPY_NONATOMIC);
    }
    NSDictionary *career=path.length ? HPCareerStatsSnapshot(path) : @{@"storage_error":@"Select a named player profile to view career statistics."};
    if(![career isKindOfClass:NSDictionary.class])career=@{@"storage_error":@"Career statistics are temporarily unavailable."};
    if([career[@"profile_id"] isKindOfClass:NSString.class] &&
       ![[[NSUUID alloc] initWithUUIDString:career[@"profile_id"]] isEqual:[[NSUUID alloc] initWithUUIDString:self.progressSnapshot[@"profile_id"]]]) career=@{@"storage_error":@"The player profile changed. Close and reopen Stats."};
    if([self.careerSnapshot isEqualToDictionary:career] && [self.sections count] && [self.progressSnapshot isEqualToDictionary:objc_getAssociatedObject(self,@selector(refreshStats))])return;
    self.careerSnapshot=career;
    objc_setAssociatedObject(self,@selector(refreshStats),self.progressSnapshot,OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self rebuildSections];
}
- (void)rebuildSections {
    NSDictionary *progress=self.progressSnapshot ?: @{};
    if(self.breakdownSourceName.length) {
        NSDictionary *detail=HPHaloServiceRecordBreakdownDetail(progress,self.careerSnapshot?:@{},self.period.selectedSegmentIndex==1,self.recordPage,self.breakdownSourceName);
        self.sections=HPCSArray(detail[@"sections"]);
        self.navigationItem.titleView=HPHaloNavigationTitle(HPCSString(detail[@"title"]));
        self.detailLabel.text=HPCSString(detail[@"subtitle"]);
        [self.tableView reloadData];[self.view setNeedsLayout];return;
    }
    self.sections=HPHaloServiceRecordSections(progress,self.careerSnapshot ?: @{},self.period.selectedSegmentIndex==1,self.tiers ?: @[],self.recordPage);
    BOOL overview=self.recordPage==HPHaloServiceRecordOverview;
    /* A removed hero keeps its own badge constraints intact; forcing its
     * arranged-view height to zero would contradict those required bounds. */
    if(overview) {
        if(self.heroPanel.superview!=self.headerStack)[self.headerStack insertArrangedSubview:self.heroPanel atIndex:1];
        if(self.tileRow.superview!=self.headerStack)[self.headerStack insertArrangedSubview:self.tileRow atIndex:2];
    } else {
        for(UIView *view in @[self.heroPanel,self.tileRow]) {
            [self.headerStack removeArrangedSubview:view];[view removeFromSuperview];
        }
    }
    long long xp=MAX(0LL,[progress[@"xp"] longLongValue]);
    NSDictionary *rank=HPHaloCareerRankForXP(xp,self.tiers ?: @[]),*next=nil;
    for(NSDictionary *tier in self.tiers){
        if(![tier isKindOfClass:NSDictionary.class])continue;
        long long minimum=[tier[@"minXP"] longLongValue];
        if(minimum>xp && (!next || minimum<[next[@"minXP"] longLongValue]))next=tier;
    }
    NSString *season=HPHaloSeasonDisplay(HPCSString(progress[@"season"]));
    HPHaloSetCaps(self.profileLabel,[NSString stringWithFormat:@"Service record · %@",season],2.2);
    HPHaloSetCaps(self.nameplate.nameLabel,self.playerName.length?self.playerName:@"Saved player",1.6);
    self.nameplate.nameLabel.accessibilityLabel=self.playerName.length?[NSString stringWithFormat:@"Player %@",self.playerName]:@"Saved player";
    self.nameplate.emblem.seed=HPCSString(progress[@"profile_id"]);
    NSString *rankName=HPCSString(rank[@"alternateName"]).length ? HPCSString(rank[@"alternateName"]) : HPCSString(rank[@"name"]);
    HPHaloSetCaps(self.rankLabel,rankName.length ? rankName : @"Recruit",1.2);
    NSUInteger order=[self.tiers indexOfObject:rank];
    NSString *standing=order!=NSNotFound && self.tiers.count ? [NSString stringWithFormat:@"Local rank %lu of %lu",(unsigned long)order+1,(unsigned long)self.tiers.count] : @"Local rank";
    if(HPCSString(rank[@"alternateName"]).length) standing=[standing stringByAppendingFormat:@" · %@",HPCSString(rank[@"name"])];
    HPHaloSetCaps(self.seasonLabel,standing,1.4);
    [self.xpLabel setCountedText:[NSString stringWithFormat:@"%@ XP",[NSNumberFormatter localizedStringFromNumber:@(xp) numberStyle:NSNumberFormatterDecimalStyle]] animate:self.countUpArmed];
    long long base=[rank[@"minXP"] longLongValue],target=[next[@"minXP"] longLongValue];
    CGFloat fraction=next && target>base ? (CGFloat)((double)(xp-base)/(double)(target-base)) : 1;
    if(self.meterRevealed)[self.rankMeter setProgress:fraction animated:YES];else self.rankMeter.progress=fraction;
    self.rankMeter.meterColor=next ? HPH3Blue() : HPHaloColorGold();
    NSString *nextText=next ? [NSString stringWithFormat:@"%@ XP to %@",[NSNumberFormatter localizedStringFromNumber:@(target-xp) numberStyle:NSNumberFormatterDecimalStyle],HPCSString(next[@"name"])] : @"Highest rank reached";
    HPHaloSetCaps(self.nextLabel,nextText,1.3);
    self.rankMeter.accessibilityValue=self.nextLabel.accessibilityLabel;
    UIImage *nextBadge=next ? HPHaloRankBadgeImage(HPCSString(next[@"file"])) : nil;
    self.rankProgressButton.iconView.image=nextBadge ?: [UIImage systemImageNamed:@"chevron.up.2"];
    NSString *file=HPCSString(rank[@"file"]);
    self.badge.image=file.length ? HPHaloRankBadgeImage(file) : nil;
    self.badgeGlow.hidden=self.badge.image==nil;
    if ([progress[@"storage_error"] boolValue]) {
        HPHaloSetCaps(self.rankLabel,@"Progression unavailable",1.2);
        HPHaloSetCaps(self.seasonLabel,@"Saved rank will retry automatically",1.4);
        self.badge.image=nil;self.badgeGlow.hidden=YES;[self.xpLabel setCountedText:@"—" animate:NO];self.rankMeter.progress=0;
        HPHaloSetCaps(self.nextLabel,@"",1);
    }
    [self.tableView reloadData];[self.view setNeedsLayout];
}
- (NSString *)styleForSection:(NSInteger)section { return HPCSString(self.sections[section][@"style"]); }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSString *style=[self styleForSection:section];
    if([style isEqualToString:@"grid"] || [style isEqualToString:@"medals"] || [style isEqualToString:@"highlights"]) return HPCSArray(self.sections[section][@"rows"]).count ? 1 : 0;
    return HPCSArray(self.sections[section][@"rows"]).count;
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSDictionary *info=self.sections[section];NSString *trailing=nil;
    if([[self styleForSection:section] isEqualToString:@"breakdown"]){
        NSArray *rows=HPCSArray(info[@"rows"]);
        if(rows.count && ![rows.firstObject[@"empty"] boolValue])trailing=[NSString stringWithFormat:@"%lu tracked",(unsigned long)rows.count];
    }
    return HPHaloSectionHeaderView(HPCSString(info[@"title"]),trailing);
}
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    NSString *footer=HPCSString(self.sections[section][@"footer"]);
    return footer.length ? HPHaloSectionFooterView(footer) : [UIView new];
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.sections[section][@"title"]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section { return self.sections[section][@"footer"]; }
- (NSUInteger)gridColumns {
    CGFloat width=CGRectGetWidth(self.tableView.bounds)-32;
    if(UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory)) return width>=640 ? 2 : 1;
    return width>=760 ? 4 : width>=430 ? 3 : 2;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *info=self.sections[path.section];NSArray *rows=HPCSArray(info[@"rows"]);
    NSString *style=[self styleForSection:path.section];
    NSString *layout=HPCSString(info[@"layout"]);
    CGFloat tableWidth=CGRectGetWidth(tableView.bounds);
    if([style isEqualToString:@"grid"]&&[layout hasPrefix:@"band"]) {
        HPH3BandCell *cell=[tableView dequeueReusableCellWithIdentifier:@"band"];
        if(!cell)cell=[[HPH3BandCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"band"];
        [cell configureItems:rows width:tableWidth compact:[layout isEqualToString:@"band-compact"] countUp:self.countUpArmed];
        return cell;
    }
    if([style isEqualToString:@"grid"]&&[layout isEqualToString:@"record"]) {
        HPH3RecordCell *cell=[tableView dequeueReusableCellWithIdentifier:@"record"];
        if(!cell)cell=[[HPH3RecordCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"record"];
        [cell configureRows:rows width:tableWidth countUp:self.countUpArmed];
        return cell;
    }
    if([style isEqualToString:@"highlights"]) {
        HPH3HighlightsCell *cell=[tableView dequeueReusableCellWithIdentifier:@"highlights"];
        if(!cell)cell=[[HPH3HighlightsCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"highlights"];
        __weak typeof(self) weakSelf=self;
        [cell configureRows:rows width:tableWidth handler:^(NSDictionary *row){[weakSelf openHighlight:row];}];
        return cell;
    }
    if([style isEqualToString:@"grid"]) {
        HPHaloStatGridCell *cell=[tableView dequeueReusableCellWithIdentifier:@"grid"];
        if(!cell)cell=[[HPHaloStatGridCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"grid"];
        [cell configureRows:rows columns:[self gridColumns]];
        return cell;
    }
    if([style isEqualToString:@"medals"]) {
        HPHaloMedalStripCell *cell=[tableView dequeueReusableCellWithIdentifier:@"medals"];
        if(!cell)cell=[[HPHaloMedalStripCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"medals"];
        [cell configureRows:rows width:CGRectGetWidth(tableView.bounds)];
        cell.accessibilityTraits=UIAccessibilityTraitButton;
        cell.accessibilityLabel=@"Medal Chest";
        cell.accessibilityHint=@"Open your medals, requirements and saved counts.";
        cell.accessibilityIdentifier=@"halopad.service-record.medal-chest";
        cell.isAccessibilityElement=YES;
        return cell;
    }
    NSDictionary *row=rows[path.row];
    if([style isEqualToString:@"breakdown"]) {
        HPHaloBreakdownCell *cell=[tableView dequeueReusableCellWithIdentifier:@"breakdown"];
        if(!cell)cell=[[HPHaloBreakdownCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"breakdown"];
        long long maximum=0;
        for(NSDictionary *item in rows) if([item[@"amount"] respondsToSelector:@selector(longLongValue)]) maximum=MAX(maximum,[item[@"amount"] longLongValue]);
        NSString *category=HPCSString(info[@"category"]);
        NSString *spotlight=[category isEqualToString:@"weapons"]?@"Favorite weapon":[category isEqualToString:@"maps"]?@"Favorite map":[category isEqualToString:@"modes"]?@"Favorite game mode":nil;
        /* Unknown attribution is listed but never spotlighted as a favorite. */
        if([HPCSString(row[@"source_name"]).lowercaseString isEqualToString:@"unknown"])spotlight=nil;
        [cell configureRow:row place:(NSUInteger)path.row+1 maximum:maximum spotlight:spotlight];
        BOOL selectable=![row[@"empty"] boolValue]&&[row[@"source_name"] isKindOfClass:NSString.class]&&[row[@"source_name"] length]>0;
        cell.selectionStyle=selectable?UITableViewCellSelectionStyleDefault:UITableViewCellSelectionStyleNone;
        cell.accessibilityTraits=selectable?UIAccessibilityTraitButton:UIAccessibilityTraitStaticText;
        cell.accessibilityHint=selectable?@"Open recorded statistics for this selection.":nil;
        cell.accessibilityIdentifier=[NSString stringWithFormat:@"halopad.service-record.breakdown.%ld.%ld",(long)path.section,(long)path.row];
        return cell;
    }
    HPHaloNoticeCell *cell=[tableView dequeueReusableCellWithIdentifier:@"notice"];
    if(!cell)cell=[[HPHaloNoticeCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"notice"];
    HPHaloSetCaps(cell.title,HPCSString(row[@"name"]),1.2);cell.message.text=HPCSString(row[@"value"]);
    cell.accessibilityLabel=HPCSString(row[@"name"]);cell.accessibilityValue=HPCSString(row[@"value"]);
    return cell;
}
- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)path {
    (void)tableView;
    if(self.breakdownSourceName.length)return nil;
    NSString *style=[self styleForSection:path.section];
    if([style isEqualToString:@"medals"])return path;
    NSArray *rows=HPCSArray(self.sections[path.section][@"rows"]);
    if([style isEqualToString:@"breakdown"]&&path.row<(NSInteger)rows.count&&![rows[path.row][@"empty"] boolValue]&&[HPCSString(rows[path.row][@"source_name"]) length])return path;
    return nil;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if(!self.navigationController||self.breakdownSourceName.length||path.section>=(NSInteger)self.sections.count)return;
    NSString *style=[self styleForSection:path.section];
    if([style isEqualToString:@"medals"]){[self showMedals];return;}
    NSArray *rows=HPCSArray(self.sections[path.section][@"rows"]);
    if(![style isEqualToString:@"breakdown"]||path.row>=(NSInteger)rows.count)return;
    NSDictionary *row=rows[path.row];NSString *source=HPCSString(row[@"source_name"]);
    if([row[@"empty"] boolValue]||!source.length)return;
    HPHaloCareerStatsViewController *detail=[[HPHaloCareerStatsViewController alloc]initWithStyle:UITableViewStyleGrouped];
    detail.progressSnapshot=self.progressSnapshot;detail.careerSnapshot=self.careerSnapshot;
    detail.initialProfileID=self.initialProfileID;detail.breakdownSourceName=source;
    detail.recordPage=self.recordPage;detail.initialLifetime=self.period.selectedSegmentIndex==1;
    self.navigationItem.backButtonTitle=@"Service Record";
    [self.navigationController pushViewController:detail animated:YES];
}
@end
UIViewController *HPHaloCareerStatsControllerMake(NSDictionary *snapshot) {
    HPHaloCareerStatsViewController *controller=[[HPHaloCareerStatsViewController alloc]initWithStyle:UITableViewStyleGrouped];
    controller.progressSnapshot=snapshot ?: @{};
    controller.initialProfileID=[snapshot[@"profile_id"] isKindOfClass:NSString.class] ? snapshot[@"profile_id"] : nil;
    return controller;
}
