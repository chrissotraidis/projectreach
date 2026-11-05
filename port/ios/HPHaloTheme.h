#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/* Shared visual language for the native Stats, Rank Progress, Medals, menu rank
 * card and in-match medal popups on iPhone, iPad and Mac Catalyst: dark tactical
 * glass, angled panels, condensed caps and glowing meters. Presentation only; no
 * screen reads or writes progression data through this file. */

typedef NS_ENUM(NSInteger, HPHaloTone) {
    HPHaloToneNeutral = 0,
    HPHaloToneAccent,
    HPHaloToneGold,
    HPHaloToneKills,
    HPHaloToneDeaths,
};

UIColor *HPHaloColorBackground(void);
UIColor *HPHaloColorPanel(void);
UIColor *HPHaloColorPanelRaised(void);
UIColor *HPHaloColorStroke(void);
UIColor *HPHaloColorAccent(void);
UIColor *HPHaloColorGold(void);
UIColor *HPHaloColorKills(void);
UIColor *HPHaloColorDeaths(void);
UIColor *HPHaloColorText(void);
UIColor *HPHaloColorTextSecondary(void);
UIColor *HPHaloColorTextTertiary(void);
UIColor *HPHaloToneColor(HPHaloTone tone);

/* Condensed system faces that follow Dynamic Type up to `maximum` points. */
UIFont *HPHaloDisplayFont(CGFloat size, UIFontWeight weight, UIFontTextStyle style, CGFloat maximum);
UIFont *HPHaloNumberFont(CGFloat size, UIFontWeight weight, UIFontTextStyle style, CGFloat maximum);
UIFont *HPHaloBodyFont(UIFontTextStyle style, UIFontWeight weight, CGFloat maximum);

UILabel *HPHaloLabel(UIFont *font, UIColor *color, NSInteger lines);
/* Upper-cases and letter-spaces the label's text using its current font/color. */
void HPHaloSetCaps(UILabel *label, NSString *_Nullable text, CGFloat tracking);

UIBezierPath *HPHaloChamferPath(CGRect rect, CGFloat cut);
NSString *HPHaloSeasonDisplay(NSString *_Nullable season);
UIImage *_Nullable HPHaloRankBadgeImage(NSString *_Nullable file);

/* Angled panel: top-left and bottom-right corners cut, hairline stroke, faint
 * sheen, optional left edge rail, corner brackets and outer glow. */
@interface HPHaloPanelView : UIView
@property(nonatomic) CGFloat chamfer;
@property(nonatomic, strong) UIColor *fillColor;
@property(nonatomic, strong) UIColor *strokeColor;
@property(nonatomic, strong, nullable) UIColor *edgeColor;
@property(nonatomic, strong, nullable) UIColor *glowColor;
@property(nonatomic) BOOL showsBrackets;
@end

/* Full-bleed deep-space backdrop with a faint hex lattice and top glow. */
@interface HPHaloBackdropView : UIView
@end

/* Soft radial light placed behind a rank badge or medal. */
@interface HPHaloGlowView : UIView
@property(nonatomic, strong) UIColor *glowColor;
@end

/* Segmented, glowing progress meter. */
@interface HPHaloMeterView : UIView
@property(nonatomic) CGFloat progress;
@property(nonatomic) NSUInteger segments;
@property(nonatomic) CGFloat barHeight;
@property(nonatomic, strong) UIColor *meterColor;
- (void)setProgress:(CGFloat)progress animated:(BOOL)animated;
@end

/* Full-width navigation tile: icon, caps headline, detail and chevron on an
 * angled panel. Remains a UIButton so actions, menus and identifiers work. */
@interface HPHaloTileButton : UIButton
@property(nonatomic, strong, readonly) UIImageView *iconView;
@property(nonatomic, strong, readonly) UILabel *headline;
@property(nonatomic, strong, readonly) UILabel *detail;
@property(nonatomic, strong, readonly) HPHaloPanelView *panel;
@property(nonatomic) BOOL activeLook;
+ (instancetype)tile;
- (void)setHeadline:(NSString *)headline detail:(nullable NSString *)detail icon:(nullable UIImage *)icon;
@end

/* Small caps tag such as CURRENT / UNLOCKED / LOCKED. */
@interface HPHaloTagView : UIView
@property(nonatomic, strong, readonly) UILabel *label;
- (void)setText:(NSString *)text color:(UIColor *)color filled:(BOOL)filled;
@end

UIView *HPHaloSectionHeaderView(NSString *title, NSString *_Nullable trailing);
UIView *HPHaloSectionFooterView(NSString *text);
UIView *HPHaloNavigationTitle(NSString *title);
void HPHaloStyleTable(UITableView *table);
/* Bottom edge for self-sizing cell content at priority 999, so a row briefly
 * laid out at its estimated height never forces an arbitrary constraint break. */
NSLayoutConstraint *HPCellBottom(UIView *content, UIView *contentView, CGFloat constant);
void HPHaloStyleSegmented(UISegmentedControl *control);
void HPHaloStyleNavigation(UINavigationController *navigation);
void HPHaloStyleDoneButton(UIBarButtonItem *item);

NS_ASSUME_NONNULL_END
