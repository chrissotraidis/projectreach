#import <UIKit/UIKit.h>
#import "HPHaloTheme.h"

NS_ASSUME_NONNULL_BEGIN

/* Service Record presentation in a classic Halo-console style: steel-blue lit
 * panels, a lobby-style player nameplate, carnage-report number bands, a
 * win/loss bar and career highlight cards. Presentation only: every value shown
 * is passed in from the existing models; nothing here reads or derives stats. */

UIColor *HPH3Blue(void);
UIColor *HPH3Ice(void);
UIColor *HPH3ToneColor(id _Nullable tone);

/* Deep navy backdrop with soft diagonal light beams and fine scanlines. */
@interface HPH3Backdrop : UIView
@end

/* Rounded steel panel: vertical blue-steel gradient, lit top edge, hairline
 * border, optional left accent bar and diagonal hatching on the right end. */
@interface HPH3SteelPanel : UIView
@property(nonatomic) BOOL raised;
@property(nonatomic) BOOL striped;
@property(nonatomic) BOOL pressed;
@property(nonatomic) CGFloat shade;
@property(nonatomic, strong, nullable) UIColor *accentColor;
@end

/* Deterministic decorative emblem generated from a profile identifier. */
@interface HPH3Emblem : UIView
@property(nonatomic, copy, nullable) NSString *seed;
@end

/* Animates numeric text up from zero once, then always shows the exact text. */
@interface HPH3CountLabel : UILabel
- (void)setCountedText:(nullable NSString *)text animate:(BOOL)animate;
@end

/* Lobby-style player nameplate for the Service Record header. */
@interface HPH3NameplateView : UIView
@property(nonatomic, strong, readonly) HPH3Emblem *emblem;
@property(nonatomic, strong, readonly) UILabel *eyebrowLabel;
@property(nonatomic, strong, readonly) UILabel *nameLabel;
@property(nonatomic, strong, readonly) UILabel *rankLabel;
@property(nonatomic, strong, readonly) UILabel *standingLabel;
@property(nonatomic, strong, readonly) HPH3CountLabel *xpLabel;
@property(nonatomic, strong, readonly) UILabel *nextLabel;
@property(nonatomic, strong, readonly) HPHaloMeterView *meter;
@property(nonatomic, strong, readonly) UIImageView *badge;
@property(nonatomic, strong, readonly) HPHaloGlowView *badgeGlow;
@end

/* Carnage-report band: big centred values over small caps captions, divided by
 * hairlines. Rows: {name, value, tone}. */
@interface HPH3BandCell : UITableViewCell
- (void)configureItems:(NSArray<NSDictionary *> *)items width:(CGFloat)width compact:(BOOL)compact countUp:(BOOL)countUp;
@end

/* Match record: win percentage, a proportional win/draw/loss bar and the
 * remaining recorded counters. Rows are the model's existing named rows. */
@interface HPH3RecordCell : UITableViewCell
- (void)configureRows:(NSArray<NSDictionary *> *)rows width:(CGFloat)width countUp:(BOOL)countUp;
@end

/* Career highlight cards. Rows: {name, value, detail, page?, medal_id?, empty?}. */
@interface HPH3HighlightsCell : UITableViewCell
- (void)configureRows:(NSArray<NSDictionary *> *)rows width:(CGFloat)width
              handler:(void (^)(NSDictionary *row))handler;
@end

NS_ASSUME_NONNULL_END
