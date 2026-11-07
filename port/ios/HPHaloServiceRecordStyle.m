#import "HPHaloServiceRecordStyle.h"
#import "HPHaloMedalCatalog.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

static UIColor *HPH3RGB(CGFloat r, CGFloat g, CGFloat b, CGFloat a) { return [UIColor colorWithRed:r green:g blue:b alpha:a]; }
UIColor *HPH3Blue(void) { return HPH3RGB(0.47, 0.74, 0.93, 1); }
UIColor *HPH3Ice(void) { return HPH3RGB(0.86, 0.94, 1.00, 1); }
UIColor *HPH3ToneColor(id tone)
{
    NSString *name = [tone isKindOfClass:NSString.class] ? tone : @"";
    if ([name isEqualToString:@"accent"]) return HPH3Blue();
    if ([name isEqualToString:@"gold"]) return HPHaloColorGold();
    if ([name isEqualToString:@"kills"]) return HPHaloColorKills();
    if ([name isEqualToString:@"deaths"]) return HPHaloColorDeaths();
    return HPH3Ice();
}
static BOOL HPH3Numeric(NSString *value)
{
    return value.length > 0 && [value rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location == NSNotFound;
}
static long long HPH3Amount(NSString *value)
{
    static NSNumberFormatter *format;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ format = [NSNumberFormatter new]; format.numberStyle = NSNumberFormatterDecimalStyle; });
    if (![value isKindOfClass:NSString.class]) return 0;
    NSNumber *number = [format numberFromString:value];
    return number ? MAX(0LL, number.longLongValue) : 0;
}

#pragma mark - Backdrop

@implementation HPH3Backdrop
- (instancetype)initWithFrame:(CGRect)frame
{
    if (!(self = [super initWithFrame:frame])) return nil;
    self.contentMode = UIViewContentModeRedraw;
    self.backgroundColor = HPH3RGB(0.016, 0.031, 0.050, 1);
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = NO;
    return self;
}
- (void)drawRect:(CGRect)rect
{
    (void)rect;
    CGContextRef cg = UIGraphicsGetCurrentContext();
    CGFloat w = CGRectGetWidth(self.bounds), h = CGRectGetHeight(self.bounds);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat base[] = {0.050, 0.095, 0.140, 1, 0.022, 0.044, 0.068, 1, 0.010, 0.020, 0.033, 1};
    CGFloat baseStops[] = {0, 0.38, 1};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, base, baseStops, 3);
    CGContextDrawLinearGradient(cg, gradient, CGPointZero, CGPointMake(0, h), 0);
    CGGradientRelease(gradient);

    /* Soft diagonal beams of light falling from the upper left. */
    CGFloat beam[] = {0.55, 0.78, 1.0, 0.075, 0.55, 0.78, 1.0, 0};
    CGFloat beamStops[] = {0, 1};
    CGGradientRef light = CGGradientCreateWithColorComponents(space, beam, beamStops, 2);
    CGFloat starts[] = {0.08, 0.30, 0.55};
    CGFloat widths[] = {0.10, 0.05, 0.16};
    CGFloat reach = MIN(h, MAX(w, (CGFloat)600) * 1.1);
    for (int i = 0; i < 3; i++) {
        CGFloat x = w * starts[i], width = MAX((CGFloat)40, w * widths[i]);
        CGContextSaveGState(cg);
        CGMutablePathRef path = CGPathCreateMutable();
        CGPathMoveToPoint(path, NULL, x, 0);
        CGPathAddLineToPoint(path, NULL, x + width, 0);
        CGPathAddLineToPoint(path, NULL, x + width + reach * 0.55, reach);
        CGPathAddLineToPoint(path, NULL, x + reach * 0.55, reach);
        CGPathCloseSubpath(path);
        CGContextAddPath(cg, path);
        CGContextClip(cg);
        CGContextDrawLinearGradient(cg, light, CGPointZero, CGPointMake(0, reach), 0);
        CGPathRelease(path);
        CGContextRestoreGState(cg);
    }
    CGGradientRelease(light);

    /* Top glow and fine scanlines. */
    CGFloat glow[] = {0.47, 0.74, 0.93, 0.16, 0.47, 0.74, 0.93, 0};
    CGGradientRef top = CGGradientCreateWithColorComponents(space, glow, beamStops, 2);
    CGPoint center = CGPointMake(w * 0.5, -MIN(w, (CGFloat)900) * 0.18);
    CGContextDrawRadialGradient(cg, top, center, 0, center, MAX(w * 0.75, (CGFloat)320), 0);
    CGGradientRelease(top);
    CGContextSetFillColorWithColor(cg, [UIColor colorWithWhite:1 alpha:0.018].CGColor);
    for (CGFloat y = 0; y < h; y += 4) CGContextFillRect(cg, CGRectMake(0, y, w, 1));
    CGFloat fade[] = {0.010, 0.020, 0.033, 0, 0.010, 0.020, 0.033, 0.85};
    CGGradientRef bottom = CGGradientCreateWithColorComponents(space, fade, beamStops, 2);
    CGContextDrawLinearGradient(cg, bottom, CGPointMake(0, h * 0.5), CGPointMake(0, h), 0);
    CGGradientRelease(bottom);
    CGColorSpaceRelease(space);
}
@end

#pragma mark - Steel panel

@implementation HPH3SteelPanel
- (instancetype)initWithFrame:(CGRect)frame
{
    if (!(self = [super initWithFrame:frame])) return nil;
    self.opaque = NO;
    self.backgroundColor = UIColor.clearColor;
    self.contentMode = UIViewContentModeRedraw;
    return self;
}
- (void)setRaised:(BOOL)raised { _raised = raised; [self setNeedsDisplay]; }
- (void)setStriped:(BOOL)striped { _striped = striped; [self setNeedsDisplay]; }
- (void)setPressed:(BOOL)pressed { _pressed = pressed; [self setNeedsDisplay]; }
- (void)setShade:(CGFloat)shade { _shade = shade; [self setNeedsDisplay]; }
- (void)setAccentColor:(UIColor *)color { _accentColor = color; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect
{
    (void)rect;
    CGContextRef cg = UIGraphicsGetCurrentContext();
    CGRect bounds = CGRectInset(self.bounds, 0.5, 0.5);
    CGFloat w = CGRectGetWidth(self.bounds), h = CGRectGetHeight(self.bounds);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:4];
    CGFloat lift = (_raised ? 0.045 : 0) + (_pressed ? 0.06 : 0) + _shade;
    CGFloat colors[] = {
        0.150 + lift, 0.255 + lift * 1.3, 0.345 + lift * 1.5, 0.93,
        0.085 + lift * 0.6, 0.155 + lift * 0.8, 0.220 + lift, 0.93,
        0.050 + lift * 0.4, 0.095 + lift * 0.5, 0.140 + lift * 0.6, 0.95};
    CGFloat stops[] = {0, 0.45, 1};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, colors, stops, 3);
    CGContextSaveGState(cg);
    [path addClip];
    CGContextDrawLinearGradient(cg, gradient, CGPointZero, CGPointMake(0, h), 0);
    if (_striped) {
        /* Hatching fades in toward the right end, like a lobby nameplate. */
        CGFloat start = w * 0.58;
        CGContextSetLineWidth(cg, 2.5);
        for (CGFloat x = start; x < w + h; x += 8) {
            CGFloat strength = MIN((CGFloat)1, MAX((CGFloat)0, (x - start) / MAX((CGFloat)1, w - start)));
            CGContextSetStrokeColorWithColor(cg, [UIColor colorWithWhite:1 alpha:0.012 + 0.05 * strength].CGColor);
            CGContextMoveToPoint(cg, x, 0);
            CGContextAddLineToPoint(cg, x - h, h);
            CGContextStrokePath(cg);
        }
    }
    CGFloat sheen[] = {1, 1, 1, 0.07, 1, 1, 1, 0};
    CGFloat sheenStops[] = {0, 1};
    CGGradientRef top = CGGradientCreateWithColorComponents(space, sheen, sheenStops, 2);
    CGContextDrawLinearGradient(cg, top, CGPointZero, CGPointMake(0, MIN(h * 0.45, (CGFloat)40)), 0);
    CGGradientRelease(top);
    CGContextSetFillColorWithColor(cg, HPH3RGB(0.80, 0.91, 1.0, _pressed ? 0.6 : 0.38).CGColor);
    CGContextFillRect(cg, CGRectMake(4, 1, MAX((CGFloat)0, w - 8), 1));
    if (_accentColor) {
        CGContextSetFillColorWithColor(cg, _accentColor.CGColor);
        CGContextFillRect(cg, CGRectMake(0, 0, 3, h));
    }
    CGContextRestoreGState(cg);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
    [[UIColor colorWithWhite:1 alpha:_pressed ? 0.28 : 0.13] setStroke];
    path.lineWidth = 1;
    [path stroke];
}
@end

#pragma mark - Emblem

static uint64_t HPH3Hash(NSString *seed)
{
    uint64_t hash = 1469598103934665603ULL;
    for (const char *c = seed.UTF8String ?: ""; *c; c++) { hash ^= (uint8_t)*c; hash *= 1099511628211ULL; }
    return hash;
}
static UIBezierPath *HPH3Star(CGPoint c, CGFloat outer, CGFloat inner, int points)
{
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (int i = 0; i < points * 2; i++) {
        CGFloat angle = (CGFloat)(-M_PI_2 + M_PI * i / points), r = i % 2 ? inner : outer;
        CGPoint p = CGPointMake(c.x + cos(angle) * r, c.y + sin(angle) * r);
        if (i) [path addLineToPoint:p]; else [path moveToPoint:p];
    }
    [path closePath];
    return path;
}
static UIBezierPath *HPH3Polygon(CGPoint c, CGFloat r, int sides, CGFloat rotation)
{
    UIBezierPath *path = [UIBezierPath bezierPath];
    for (int i = 0; i < sides; i++) {
        CGFloat angle = rotation + (CGFloat)(2 * M_PI * i / sides);
        CGPoint p = CGPointMake(c.x + cos(angle) * r, c.y + sin(angle) * r);
        if (i) [path addLineToPoint:p]; else [path moveToPoint:p];
    }
    [path closePath];
    return path;
}

@implementation HPH3Emblem
- (instancetype)initWithFrame:(CGRect)frame
{
    if (!(self = [super initWithFrame:frame])) return nil;
    self.opaque = NO;
    self.backgroundColor = UIColor.clearColor;
    self.contentMode = UIViewContentModeRedraw;
    self.isAccessibilityElement = NO;
    return self;
}
- (void)setSeed:(NSString *)seed { _seed = [seed copy]; [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect
{
    (void)rect;
    CGRect b = self.bounds;
    CGFloat s = MIN(CGRectGetWidth(b), CGRectGetHeight(b));
    CGPoint c = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b));
    uint64_t hash = HPH3Hash(self.seed ?: @"");
    NSArray<UIColor *> *backs = @[HPH3RGB(0.16, 0.32, 0.52, 1), HPH3RGB(0.48, 0.12, 0.12, 1), HPH3RGB(0.14, 0.38, 0.22, 1),
        HPH3RGB(0.40, 0.30, 0.10, 1), HPH3RGB(0.28, 0.17, 0.42, 1), HPH3RGB(0.46, 0.21, 0.08, 1), HPH3RGB(0.10, 0.36, 0.40, 1)];
    NSArray<UIColor *> *fronts = @[HPH3RGB(0.95, 0.96, 0.98, 1), HPH3RGB(0.98, 0.80, 0.32, 1), HPH3RGB(0.60, 0.88, 1.0, 1),
        HPH3RGB(1.0, 0.55, 0.30, 1), HPH3RGB(0.62, 0.95, 0.60, 1)];
    UIColor *back = backs[hash % backs.count], *front = fronts[(hash >> 8) % fronts.count];
    /* Tile */
    UIBezierPath *tile = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(b, 0.5, 0.5) cornerRadius:4];
    [HPH3RGB(0.03, 0.06, 0.09, 0.9) setFill]; [tile fill];
    [[UIColor colorWithWhite:1 alpha:0.18] setStroke]; tile.lineWidth = 1; [tile stroke];
    /* Background shape */
    CGFloat r = s * 0.40;
    UIBezierPath *shape;
    switch ((hash >> 16) % 5) {
    case 0: shape = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(c.x - r, c.y - r, r * 2, r * 2)]; break;
    case 1: {
        shape = [UIBezierPath bezierPath];
        [shape moveToPoint:CGPointMake(c.x - r * 0.85, c.y - r * 0.85)];
        [shape addLineToPoint:CGPointMake(c.x + r * 0.85, c.y - r * 0.85)];
        [shape addLineToPoint:CGPointMake(c.x + r * 0.85, c.y + r * 0.10)];
        [shape addQuadCurveToPoint:CGPointMake(c.x, c.y + r) controlPoint:CGPointMake(c.x + r * 0.80, c.y + r * 0.75)];
        [shape addQuadCurveToPoint:CGPointMake(c.x - r * 0.85, c.y + r * 0.10) controlPoint:CGPointMake(c.x - r * 0.80, c.y + r * 0.75)];
        [shape closePath];
        break;
    }
    case 2: shape = HPH3Polygon(c, r, 6, 0); break;
    case 3: shape = HPH3Polygon(c, r * 1.05, 4, (CGFloat)-M_PI_2); break;
    default: shape = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(c.x - r * 0.85, c.y - r * 0.85, r * 1.7, r * 1.7) cornerRadius:r * 0.3]; break;
    }
    [back setFill]; [shape fill];
    CGContextRef shading = UIGraphicsGetCurrentContext();
    CGContextSaveGState(shading);
    [shape addClip];
    CGFloat lit[] = {1, 1, 1, 0.20, 1, 1, 1, 0};
    CGFloat litStops[] = {0, 1};
    CGColorSpaceRef litSpace = CGColorSpaceCreateDeviceRGB();
    CGGradientRef litGradient = CGGradientCreateWithColorComponents(litSpace, lit, litStops, 2);
    CGContextDrawLinearGradient(shading, litGradient, CGPointMake(0, c.y - r), CGPointMake(0, c.y + r * 0.2), 0);
    CGGradientRelease(litGradient);
    CGColorSpaceRelease(litSpace);
    CGContextRestoreGState(shading);
    [[front colorWithAlphaComponent:0.55] setStroke]; shape.lineWidth = MAX((CGFloat)1.5, s * 0.025); [shape stroke];
    /* Foreground glyph */
    CGFloat g = s * 0.22;
    UIBezierPath *glyph = [UIBezierPath bezierPath];
    switch ((hash >> 24) % 6) {
    case 0: glyph = HPH3Star(c, g, g * 0.42, 5); break;
    case 1:
        for (int i = 0; i < 2; i++) {
            CGFloat y = c.y - g * 0.15 + i * g * 0.7;
            [glyph moveToPoint:CGPointMake(c.x - g, y + g * 0.35)];
            [glyph addLineToPoint:CGPointMake(c.x, y - g * 0.45)];
            [glyph addLineToPoint:CGPointMake(c.x + g, y + g * 0.35)];
            [glyph addLineToPoint:CGPointMake(c.x + g * 0.62, y + g * 0.55)];
            [glyph addLineToPoint:CGPointMake(c.x, y - g * 0.05)];
            [glyph addLineToPoint:CGPointMake(c.x - g * 0.62, y + g * 0.55)];
            [glyph closePath];
        }
        break;
    case 2:
        [glyph moveToPoint:CGPointMake(c.x + g * 0.25, c.y - g * 1.05)];
        [glyph addLineToPoint:CGPointMake(c.x - g * 0.60, c.y + g * 0.15)];
        [glyph addLineToPoint:CGPointMake(c.x - g * 0.02, c.y + g * 0.15)];
        [glyph addLineToPoint:CGPointMake(c.x - g * 0.25, c.y + g * 1.05)];
        [glyph addLineToPoint:CGPointMake(c.x + g * 0.60, c.y - g * 0.15)];
        [glyph addLineToPoint:CGPointMake(c.x + g * 0.02, c.y - g * 0.15)];
        [glyph closePath];
        break;
    case 3: glyph = HPH3Polygon(c, g * 1.05, 3, (CGFloat)-M_PI_2); break;
    case 4: /* winged insignia */
        for (int side = -1; side <= 1; side += 2) {
            [glyph moveToPoint:CGPointMake(c.x + side * g * 0.18, c.y + g * 0.40)];
            [glyph addLineToPoint:CGPointMake(c.x + side * g * 1.18, c.y - g * 0.62)];
            [glyph addLineToPoint:CGPointMake(c.x + side * g * 0.92, c.y + g * 0.05)];
            [glyph addLineToPoint:CGPointMake(c.x + side * g * 0.62, c.y + g * 0.78)];
            [glyph closePath];
        }
        [glyph appendPath:HPH3Polygon(CGPointMake(c.x, c.y - g * 0.05), g * 0.42, 4, (CGFloat)-M_PI_2)];
        break;
    default: {
        glyph = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(c.x - g, c.y - g, g * 2, g * 2)];
        [glyph appendPath:[[UIBezierPath bezierPathWithOvalInRect:CGRectMake(c.x - g * 0.45, c.y - g * 0.95, g * 1.7, g * 1.7)] bezierPathByReversingPath]];
        break;
    }
    }
    CGContextRef cg = UIGraphicsGetCurrentContext();
    CGContextSaveGState(cg);
    CGContextSetShadowWithColor(cg, CGSizeMake(0, 1), 3, [UIColor colorWithWhite:0 alpha:0.6].CGColor);
    [front setFill]; [glyph fill];
    CGContextRestoreGState(cg);
}
@end

#pragma mark - Counting label

@interface HPH3CountTarget : NSObject
@property(nonatomic, weak) HPH3CountLabel *label;
@end
@interface HPH3CountLabel ()
- (void)tick:(CADisplayLink *)link;
@end
@implementation HPH3CountTarget
- (void)tick:(CADisplayLink *)link { [self.label tick:link]; }
@end

@implementation HPH3CountLabel {
    CADisplayLink *_link;
    CFTimeInterval _start;
    NSString *_final, *_prefix, *_suffix;
    double _target;
    NSNumberFormatter *_format;
    BOOL _pending, _played;
}
- (BOOL)prepareCount:(NSString *)text
{
    static NSRegularExpression *pattern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pattern = [NSRegularExpression regularExpressionWithPattern:@"^([+\\-\\x{2212}]?)([0-9][0-9.,\\x{00a0}\\x{202f}\\x{2019}']*)([^0-9]*)$" options:0 error:NULL];
    });
    NSTextCheckingResult *match = [pattern firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match) return NO;
    NSString *core = [text substringWithRange:[match rangeAtIndex:2]];
    NSNumberFormatter *format = [NSNumberFormatter new];
    format.numberStyle = NSNumberFormatterDecimalStyle;
    NSNumber *number = [format numberFromString:core];
    if (!number || number.doubleValue <= 0 || !isfinite(number.doubleValue)) return NO;
    NSRange separator = [core rangeOfString:format.decimalSeparator options:NSBackwardsSearch];
    NSUInteger decimals = separator.location == NSNotFound ? 0 : core.length - NSMaxRange(separator);
    format.minimumFractionDigits = decimals;
    format.maximumFractionDigits = decimals;
    format.usesGroupingSeparator = [core rangeOfString:format.groupingSeparator].location != NSNotFound;
    /* Only animate text this formatter reproduces exactly. */
    if (![[format stringFromNumber:number] isEqualToString:core]) return NO;
    _format = format;
    _target = number.doubleValue;
    _prefix = [text substringWithRange:[match rangeAtIndex:1]];
    _suffix = [text substringWithRange:[match rangeAtIndex:3]];
    return YES;
}
- (NSString *)textForValue:(double)value
{
    if (_format.maximumFractionDigits == 0) value = floor(value);
    return [NSString stringWithFormat:@"%@%@%@", _prefix, [_format stringFromNumber:@(value)], _suffix];
}
- (void)setCountedText:(NSString *)text animate:(BOOL)animate
{
    text = text ?: @"";
    if ([text isEqualToString:_final] && (_link || _pending || [self.text isEqualToString:text])) return;
    [self stopCounting];
    _final = [text copy];
    self.accessibilityLabel = _final;
    if (animate && !_played && !UIAccessibilityIsReduceMotionEnabled() && [self prepareCount:text]) {
        _pending = YES;
        self.text = [self textForValue:0];
        if (self.window) [self startCounting];
    } else {
        self.text = text;
    }
}
- (void)didMoveToWindow
{
    [super didMoveToWindow];
    if (self.window && _pending && !_link) [self startCounting];
    else if (!self.window && (_link || _pending)) { [self stopCounting]; self.text = _final; }
}
- (void)startCounting
{
    _pending = NO;
    _played = YES;
    _start = CACurrentMediaTime();
    HPH3CountTarget *target = [HPH3CountTarget new];
    target.label = self;
    _link = [CADisplayLink displayLinkWithTarget:target selector:@selector(tick:)];
    [_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)stopCounting
{
    [_link invalidate];
    _link = nil;
    _pending = NO;
}
- (void)tick:(CADisplayLink *)link
{
    (void)link;
    double t = (CACurrentMediaTime() - _start) / 0.9;
    if (t >= 1) { [self stopCounting]; self.text = _final; return; }
    double eased = 1 - pow(1 - t, 3);
    self.text = [self textForValue:_target * eased];
}
- (void)dealloc { [_link invalidate]; }
@end

#pragma mark - Nameplate

@implementation HPH3NameplateView
- (instancetype)initWithFrame:(CGRect)frame
{
    if (!(self = [super initWithFrame:frame])) return nil;
    HPH3SteelPanel *panel = [HPH3SteelPanel new];
    panel.raised = YES;
    panel.striped = YES;
    panel.accentColor = HPH3Blue();
    panel.userInteractionEnabled = NO;
    _emblem = [HPH3Emblem new];
    _eyebrowLabel = HPHaloLabel(HPHaloDisplayFont(12, UIFontWeightBold, UIFontTextStyleCaption1, 19), HPH3Blue(), 0);
    _nameLabel = HPHaloLabel(HPHaloDisplayFont(38, UIFontWeightHeavy, UIFontTextStyleLargeTitle, 52), HPH3Ice(), 1);
    _nameLabel.adjustsFontSizeToFitWidth = YES;
    _nameLabel.minimumScaleFactor = 0.5;
    _nameLabel.layer.shadowColor = HPH3Blue().CGColor;
    _nameLabel.layer.shadowRadius = 10;
    _nameLabel.layer.shadowOpacity = 0.45f;
    _nameLabel.layer.shadowOffset = CGSizeZero;
    _rankLabel = HPHaloLabel(HPHaloDisplayFont(20, UIFontWeightHeavy, UIFontTextStyleTitle3, 30), HPHaloColorGold(), 0);
    _standingLabel = HPHaloLabel(HPHaloDisplayFont(12.5, UIFontWeightSemibold, UIFontTextStyleCaption1, 19), HPHaloColorTextSecondary(), 0);
    _xpLabel = [HPH3CountLabel new];
    _xpLabel.font = HPHaloNumberFont(26, UIFontWeightHeavy, UIFontTextStyleTitle2, 36);
    _xpLabel.textColor = HPH3Ice();
    _xpLabel.adjustsFontForContentSizeCategory = YES;
    _nextLabel = HPHaloLabel(HPHaloDisplayFont(12, UIFontWeightSemibold, UIFontTextStyleCaption1, 19), HPHaloColorTextSecondary(), 0);
    _nextLabel.textAlignment = NSTextAlignmentRight;
    _meter = [HPHaloMeterView new];
    _meter.segments = 10;
    _meter.barHeight = 9;
    _meter.meterColor = HPH3Blue();
    _badgeGlow = [HPHaloGlowView new];
    _badgeGlow.glowColor = HPHaloColorGold();
    _badge = [UIImageView new];
    _badge.contentMode = UIViewContentModeScaleAspectFit;
    _badge.isAccessibilityElement = NO;

    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[_eyebrowLabel, _nameLabel, _rankLabel, _standingLabel]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 2;
    [text setCustomSpacing:4 afterView:_nameLabel];
    UIView *badgeHolder = [UIView new];
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[_emblem, text, badgeHolder]];
    top.axis = UILayoutConstraintAxisHorizontal;
    top.alignment = UIStackViewAlignmentCenter;
    top.spacing = 16;
    [_xpLabel setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_xpLabel setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_nextLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *xpRow = [[UIStackView alloc] initWithArrangedSubviews:@[_xpLabel, _nextLabel]];
    xpRow.axis = UILayoutConstraintAxisHorizontal;
    xpRow.alignment = UIStackViewAlignmentLastBaseline;
    xpRow.spacing = 12;
    UIStackView *main = [[UIStackView alloc] initWithArrangedSubviews:@[top, xpRow, _meter]];
    main.axis = UILayoutConstraintAxisVertical;
    main.spacing = 12;
    [main setCustomSpacing:6 afterView:xpRow];
    for (UIView *view in @[panel, _badgeGlow, main]) { view.translatesAutoresizingMaskIntoConstraints = NO; [self addSubview:view]; }
    _badge.translatesAutoresizingMaskIntoConstraints = NO;
    [badgeHolder addSubview:_badge];
    NSLayoutConstraint *bottom = [main.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-16];
    bottom.priority = UILayoutPriorityDefaultLow - 1;
    [NSLayoutConstraint activateConstraints:@[
        [panel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [panel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [panel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [panel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_emblem.widthAnchor constraintEqualToConstant:76],
        [_emblem.heightAnchor constraintEqualToConstant:76],
        [badgeHolder.widthAnchor constraintEqualToConstant:62],
        [badgeHolder.heightAnchor constraintEqualToConstant:93],
        [_badge.leadingAnchor constraintEqualToAnchor:badgeHolder.leadingAnchor],
        [_badge.trailingAnchor constraintEqualToAnchor:badgeHolder.trailingAnchor],
        [_badge.topAnchor constraintEqualToAnchor:badgeHolder.topAnchor],
        [_badge.bottomAnchor constraintEqualToAnchor:badgeHolder.bottomAnchor],
        [_badgeGlow.centerXAnchor constraintEqualToAnchor:_badge.centerXAnchor],
        [_badgeGlow.centerYAnchor constraintEqualToAnchor:_badge.centerYAnchor],
        [_badgeGlow.widthAnchor constraintEqualToConstant:150],
        [_badgeGlow.heightAnchor constraintEqualToConstant:150],
        [main.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18],
        [main.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-18],
        [main.topAnchor constraintEqualToAnchor:self.topAnchor constant:16],
        [main.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-16], bottom]];
    self.clipsToBounds = NO;
    return self;
}
@end

#pragma mark - Carnage band

static UIView *HPH3Rule(BOOL vertical)
{
    UIView *rule = [UIView new];
    rule.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    rule.translatesAutoresizingMaskIntoConstraints = NO;
    [(vertical ? rule.widthAnchor : rule.heightAnchor) constraintEqualToConstant:1].active = YES;
    rule.isAccessibilityElement = NO;
    return rule;
}

@implementation HPH3BandCell {
    HPH3SteelPanel *_panel;
    UIStackView *_rows;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    if (!(self = [super initWithStyle:style reuseIdentifier:identifier])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    _panel = [HPH3SteelPanel new];
    _rows = [UIStackView new];
    _rows.axis = UILayoutConstraintAxisVertical;
    for (UIView *view in @[_panel, _rows]) { view.translatesAutoresizingMaskIntoConstraints = NO; [self.contentView addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        [_panel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [_panel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [_panel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
        HPCellBottom(_panel, self.contentView, -4),
        [_rows.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:4],
        [_rows.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor constant:-4],
        [_rows.topAnchor constraintEqualToAnchor:_panel.topAnchor constant:4],
        [_rows.bottomAnchor constraintEqualToAnchor:_panel.bottomAnchor constant:-4]]];
    return self;
}
- (UIView *)itemForRow:(NSDictionary *)row compact:(BOOL)compact divider:(BOOL)divider countUp:(BOOL)countUp
{
    NSString *name = [row[@"name"] isKindOfClass:NSString.class] ? row[@"name"] : @"";
    NSString *value = [row[@"value"] isKindOfClass:NSString.class] ? row[@"value"] : @"—";
    BOOL numeric = HPH3Numeric(value);
    UIView *item = [UIView new];
    HPH3CountLabel *label = [HPH3CountLabel new];
    label.font = numeric ? HPHaloNumberFont(compact ? 24 : 34, UIFontWeightHeavy, compact ? UIFontTextStyleTitle2 : UIFontTextStyleTitle1, compact ? 34 : 46)
                         : HPHaloDisplayFont(compact ? 17 : 20, UIFontWeightBold, UIFontTextStyleTitle3, compact ? 26 : 30);
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = HPH3ToneColor(row[@"tone"]);
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = numeric ? 1 : 0;
    label.adjustsFontSizeToFitWidth = numeric;
    label.minimumScaleFactor = 0.55;
    if (row[@"tone"]) {
        label.layer.shadowColor = label.textColor.CGColor;
        label.layer.shadowRadius = 8;
        label.layer.shadowOpacity = 0.35f;
        label.layer.shadowOffset = CGSizeZero;
    }
    [label setCountedText:value animate:countUp && numeric];
    UILabel *caption = HPHaloLabel(HPHaloDisplayFont(11.5, UIFontWeightSemibold, UIFontTextStyleCaption1, 18), HPHaloColorTextSecondary(), 0);
    caption.textAlignment = NSTextAlignmentCenter;
    HPHaloSetCaps(caption, name, 1.4);
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[label, caption]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 2;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [item addSubview:stack];
    NSLayoutConstraint *bottom = [stack.bottomAnchor constraintEqualToAnchor:item.bottomAnchor constant:compact ? -10 : -13];
    bottom.priority = UILayoutPriorityDefaultLow - 1;
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:item.leadingAnchor constant:8],
        [stack.trailingAnchor constraintEqualToAnchor:item.trailingAnchor constant:-8],
        [stack.topAnchor constraintEqualToAnchor:item.topAnchor constant:compact ? 10 : 13],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:item.bottomAnchor constant:compact ? -10 : -13], bottom]];
    if (divider) {
        UIView *rule = HPH3Rule(YES);
        [item addSubview:rule];
        [NSLayoutConstraint activateConstraints:@[
            [rule.leadingAnchor constraintEqualToAnchor:item.leadingAnchor],
            [rule.topAnchor constraintEqualToAnchor:item.topAnchor constant:12],
            [rule.bottomAnchor constraintEqualToAnchor:item.bottomAnchor constant:-12]]];
    }
    item.isAccessibilityElement = YES;
    item.accessibilityLabel = name;
    item.accessibilityValue = value;
    return item;
}
- (void)configureItems:(NSArray<NSDictionary *> *)items width:(CGFloat)width compact:(BOOL)compact countUp:(BOOL)countUp
{
    for (UIView *view in _rows.arrangedSubviews) { [_rows removeArrangedSubview:view]; [view removeFromSuperview]; }
    if (!items.count) return;
    BOOL large = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    CGFloat available = MAX((CGFloat)120, width - 40);
    CGFloat minimum = large ? 210 : compact ? 128 : 116;
    NSUInteger columns = MAX((NSUInteger)1, MIN(items.count, (NSUInteger)floor(available / minimum)));
    NSUInteger lines = (items.count + columns - 1) / columns;
    columns = (items.count + lines - 1) / lines;
    for (NSUInteger start = 0; start < items.count; start += columns) {
        if (start) [_rows addArrangedSubview:HPH3Rule(NO)];
        UIStackView *line = [UIStackView new];
        line.axis = UILayoutConstraintAxisHorizontal;
        line.distribution = UIStackViewDistributionFillEqually;
        for (NSUInteger i = start; i < MIN(items.count, start + columns); i++)
            [line addArrangedSubview:[self itemForRow:items[i] compact:compact divider:i > start countUp:countUp]];
        [_rows addArrangedSubview:line];
    }
}
@end

#pragma mark - Match record

@interface HPH3OutcomeBar : UIView
@property(nonatomic) long long wins, draws, losses;
@end
@implementation HPH3OutcomeBar
- (instancetype)initWithFrame:(CGRect)frame
{
    if (!(self = [super initWithFrame:frame])) return nil;
    self.opaque = NO;
    self.backgroundColor = UIColor.clearColor;
    self.contentMode = UIViewContentModeRedraw;
    self.isAccessibilityElement = NO;
    return self;
}
- (CGSize)intrinsicContentSize { return CGSizeMake(UIViewNoIntrinsicMetric, 12); }
- (void)drawRect:(CGRect)rect
{
    (void)rect;
    CGRect b = self.bounds;
    UIBezierPath *track = [UIBezierPath bezierPathWithRoundedRect:b cornerRadius:CGRectGetHeight(b) / 2];
    [[UIColor colorWithWhite:1 alpha:0.07] setFill];
    [track fill];
    long double total = (long double)_wins + _draws + _losses;
    if (total <= 0) return;
    CGContextRef cg = UIGraphicsGetCurrentContext();
    CGContextSaveGState(cg);
    [track addClip];
    CGFloat x = 0, w = CGRectGetWidth(b);
    long long values[] = {_wins, _draws, _losses};
    UIColor *colors[] = {HPHaloColorKills(), HPHaloColorGold(), HPHaloColorDeaths()};
    for (int i = 0; i < 3; i++) {
        if (values[i] <= 0) continue;
        CGFloat width = (CGFloat)((long double)w * values[i] / total);
        [colors[i] setFill];
        UIRectFill(CGRectMake(x, 0, width, CGRectGetHeight(b)));
        [[UIColor colorWithWhite:1 alpha:0.22] setFill];
        UIRectFill(CGRectMake(x, 0, width, CGRectGetHeight(b) * 0.4));
        x += width;
        if (x < w - 1) { [[UIColor colorWithRed:0.02 green:0.04 blue:0.06 alpha:1] setFill]; UIRectFill(CGRectMake(x - 1, 0, 2, CGRectGetHeight(b))); }
    }
    CGContextRestoreGState(cg);
}
@end

@implementation HPH3RecordCell {
    HPH3SteelPanel *_panel;
    UIStackView *_stack;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    if (!(self = [super initWithStyle:style reuseIdentifier:identifier])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    _panel = [HPH3SteelPanel new];
    _stack = [UIStackView new];
    _stack.axis = UILayoutConstraintAxisVertical;
    _stack.spacing = 12;
    for (UIView *view in @[_panel, _stack]) { view.translatesAutoresizingMaskIntoConstraints = NO; [self.contentView addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        [_panel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [_panel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [_panel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
        HPCellBottom(_panel, self.contentView, -4),
        [_stack.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:20],
        [_stack.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor constant:-18],
        [_stack.topAnchor constraintEqualToAnchor:_panel.topAnchor constant:16],
        [_stack.bottomAnchor constraintEqualToAnchor:_panel.bottomAnchor constant:-16]]];
    return self;
}
- (void)configureRows:(NSArray<NSDictionary *> *)rows width:(CGFloat)width countUp:(BOOL)countUp
{
    for (UIView *view in _stack.arrangedSubviews) { [_stack removeArrangedSubview:view]; [view removeFromSuperview]; }
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSDictionary *row in rows) if ([row[@"name"] isKindOfClass:NSString.class] && [row[@"value"] isKindOfClass:NSString.class]) values[row[@"name"]] = row[@"value"];
    BOOL large = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);

    HPH3CountLabel *rate = [HPH3CountLabel new];
    rate.font = HPHaloNumberFont(44, UIFontWeightHeavy, UIFontTextStyleLargeTitle, 56);
    rate.adjustsFontForContentSizeCategory = YES;
    rate.textColor = HPH3Ice();
    rate.layer.shadowColor = HPH3Blue().CGColor;
    rate.layer.shadowRadius = 10;
    rate.layer.shadowOpacity = 0.4f;
    rate.layer.shadowOffset = CGSizeZero;
    [rate setCountedText:values[@"Win percentage"] ?: @"—" animate:countUp];
    UILabel *rateCaption = HPHaloLabel(HPHaloDisplayFont(12, UIFontWeightBold, UIFontTextStyleCaption1, 19), HPH3Blue(), 0);
    HPHaloSetCaps(rateCaption, @"Win percentage", 1.8);
    UIStackView *left = [[UIStackView alloc] initWithArrangedSubviews:@[rate, rateCaption]];
    left.axis = UILayoutConstraintAxisVertical;
    left.spacing = 0;
    left.isAccessibilityElement = YES;
    left.accessibilityLabel = @"Win percentage";
    left.accessibilityValue = values[@"Win percentage"] ?: @"—";

    UIStackView *right = [UIStackView new];
    right.axis = UILayoutConstraintAxisVertical;
    right.spacing = 6;
    for (NSString *name in @[@"Matches played", @"Unfinished matches", @"Results unknown"]) {
        UILabel *caption = HPHaloLabel(HPHaloDisplayFont(12.5, UIFontWeightSemibold, UIFontTextStyleCaption1, 19), HPHaloColorTextSecondary(), 0);
        HPHaloSetCaps(caption, name, 1.3);
        UILabel *value = HPHaloLabel(HPHaloNumberFont(19, UIFontWeightBold, UIFontTextStyleHeadline, 28), HPH3Ice(), 1);
        value.text = values[name] ?: @"—";
        value.textAlignment = NSTextAlignmentRight;
        [value setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        [value setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
        UIStackView *line = [[UIStackView alloc] initWithArrangedSubviews:@[caption, value]];
        line.spacing = 12;
        line.alignment = UIStackViewAlignmentFirstBaseline;
        line.isAccessibilityElement = YES;
        line.accessibilityLabel = name;
        line.accessibilityValue = value.text;
        [right addArrangedSubview:line];
    }
    UIStackView *top = [[UIStackView alloc] initWithArrangedSubviews:@[left, right]];
    top.spacing = 24;
    BOOL stacked = large || width < 480;
    top.axis = stacked ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    top.alignment = stacked ? UIStackViewAlignmentFill : UIStackViewAlignmentCenter;
    top.distribution = stacked ? UIStackViewDistributionFill : UIStackViewDistributionFillEqually;
    [_stack addArrangedSubview:top];

    HPH3OutcomeBar *bar = [HPH3OutcomeBar new];
    bar.wins = HPH3Amount(values[@"Wins"]);
    bar.draws = HPH3Amount(values[@"Draws"]);
    bar.losses = HPH3Amount(values[@"Losses"]);
    [_stack addArrangedSubview:bar];

    UIStackView *legend = [UIStackView new];
    legend.distribution = UIStackViewDistributionFillEqually;
    legend.axis = large ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
    legend.spacing = 8;
    NSArray *keys = @[@"Wins", @"Draws", @"Losses"];
    NSArray *colors = @[HPHaloColorKills(), HPHaloColorGold(), HPHaloColorDeaths()];
    for (NSUInteger i = 0; i < keys.count; i++) {
        UILabel *label = HPHaloLabel(HPHaloDisplayFont(15, UIFontWeightHeavy, UIFontTextStyleSubheadline, 24), colors[i], 0);
        label.textAlignment = large ? NSTextAlignmentNatural : i == 0 ? NSTextAlignmentLeft : i == 1 ? NSTextAlignmentCenter : NSTextAlignmentRight;
        HPHaloSetCaps(label, [NSString stringWithFormat:@"%@ %@", values[keys[i]] ?: @"—", keys[i]], 1.4);
        [legend addArrangedSubview:label];
    }
    [_stack addArrangedSubview:legend];
}
@end

#pragma mark - Career highlights

@interface HPH3HighlightCard : UIControl
@property(nonatomic, strong) HPH3SteelPanel *panel;
@property(nonatomic, copy) NSDictionary *row;
@property(nonatomic, copy) void (^handler)(NSDictionary *row);
@end
@implementation HPH3HighlightCard
- (instancetype)initWithRow:(NSDictionary *)row
{
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _row = [row copy];
    BOOL empty = [row[@"empty"] boolValue];
    UIColor *tone = HPH3ToneColor(row[@"tone"]);
    _panel = [HPH3SteelPanel new];
    _panel.raised = !empty;
    _panel.accentColor = empty ? nil : tone;
    _panel.userInteractionEnabled = NO;
    UIImageView *icon = [UIImageView new];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = tone;
    if ([row[@"medal_id"] respondsToSelector:@selector(unsignedIntegerValue)])
        icon.image = HPHaloMedalBadgeImage([row[@"medal_id"] unsignedIntegerValue], 34);
    else if ([row[@"icon"] isKindOfClass:NSString.class])
        icon.image = [UIImage systemImageNamed:row[@"icon"] withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightBold]];
    icon.alpha = empty ? 0.4 : 1;
    [icon.widthAnchor constraintEqualToConstant:30].active = YES;
    [icon.heightAnchor constraintEqualToConstant:30].active = YES;
    UILabel *caption = HPHaloLabel(HPHaloDisplayFont(12, UIFontWeightBold, UIFontTextStyleCaption1, 19), HPHaloColorTextSecondary(), 0);
    HPHaloSetCaps(caption, row[@"name"], 1.6);
    UIStackView *heading = [[UIStackView alloc] initWithArrangedSubviews:@[icon, caption]];
    heading.spacing = 10;
    heading.alignment = UIStackViewAlignmentCenter;
    UILabel *value = HPHaloLabel(HPHaloDisplayFont(22, UIFontWeightHeavy, UIFontTextStyleTitle2, 32), empty ? HPHaloColorTextSecondary() : HPH3Ice(), 0);
    HPHaloSetCaps(value, row[@"value"], 0.8);
    UILabel *detail = HPHaloLabel(HPHaloBodyFont(UIFontTextStyleFootnote, UIFontWeightMedium, 22), empty ? HPHaloColorTextTertiary() : tone, 0);
    detail.text = [row[@"detail"] isKindOfClass:NSString.class] ? row[@"detail"] : @"";
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[heading, value, detail]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 4;
    [stack setCustomSpacing:8 afterView:heading];
    stack.userInteractionEnabled = NO;
    for (UIView *view in @[_panel, stack]) { view.translatesAutoresizingMaskIntoConstraints = NO; [self addSubview:view]; }
    NSLayoutConstraint *bottom = [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-14];
    bottom.priority = UILayoutPriorityDefaultLow - 1;
    [NSLayoutConstraint activateConstraints:@[
        [_panel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_panel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_panel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_panel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-14], bottom]];
    self.enabled = !empty;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = [NSString stringWithFormat:@"%@: %@", row[@"name"] ?: @"", row[@"value"] ?: @""];
    self.accessibilityValue = detail.text;
    self.accessibilityTraits = empty ? UIAccessibilityTraitStaticText : UIAccessibilityTraitButton;
    [self addTarget:self action:@selector(activate) forControlEvents:UIControlEventTouchUpInside];
    return self;
}
- (void)setHighlighted:(BOOL)highlighted { [super setHighlighted:highlighted]; self.panel.pressed = highlighted; }
- (void)activate { if (self.handler && self.enabled) self.handler(self.row); }
@end

@implementation HPH3HighlightsCell {
    UIStackView *_grid;
}
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier
{
    if (!(self = [super initWithStyle:style reuseIdentifier:identifier])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    _grid = [UIStackView new];
    _grid.axis = UILayoutConstraintAxisVertical;
    _grid.spacing = 10;
    _grid.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:_grid];
    [NSLayoutConstraint activateConstraints:@[
        [_grid.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [_grid.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [_grid.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:4],
        HPCellBottom(_grid, self.contentView, -4)]];
    return self;
}
- (void)configureRows:(NSArray<NSDictionary *> *)rows width:(CGFloat)width handler:(void (^)(NSDictionary *))handler
{
    for (UIView *view in _grid.arrangedSubviews) { [_grid removeArrangedSubview:view]; [view removeFromSuperview]; }
    BOOL large = UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
    CGFloat available = width - 32;
    NSUInteger columns = large ? 1 : available >= 760 ? 4 : available >= 420 ? 2 : 1;
    columns = MAX((NSUInteger)1, MIN(columns, rows.count));
    for (NSUInteger start = 0; start < rows.count; start += columns) {
        UIStackView *line = [UIStackView new];
        line.axis = UILayoutConstraintAxisHorizontal;
        line.distribution = UIStackViewDistributionFillEqually;
        line.alignment = UIStackViewAlignmentFill;
        line.spacing = 10;
        for (NSUInteger i = start; i < start + columns; i++) {
            if (i >= rows.count) { [line addArrangedSubview:[UIView new]]; continue; }
            HPH3HighlightCard *card = [[HPH3HighlightCard alloc] initWithRow:rows[i]];
            card.handler = handler;
            card.accessibilityIdentifier = [NSString stringWithFormat:@"halopad.service-record.highlight.%lu", (unsigned long)i];
            [line addArrangedSubview:card];
        }
        [_grid addArrangedSubview:line];
    }
}
@end
