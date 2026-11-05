#import "HPHaloTheme.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreText/CoreText.h>
#include <math.h>

static UIColor *HPRGB(CGFloat r, CGFloat g, CGFloat b, CGFloat a) { return [UIColor colorWithRed:r green:g blue:b alpha:a]; }

UIColor *HPHaloColorBackground(void) { return HPRGB(0.020, 0.039, 0.063, 1); }
UIColor *HPHaloColorPanel(void) { return HPRGB(0.055, 0.100, 0.145, 0.88); }
UIColor *HPHaloColorPanelRaised(void) { return HPRGB(0.085, 0.150, 0.210, 0.94); }
UIColor *HPHaloColorStroke(void) { return HPRGB(0.55, 0.78, 0.95, 0.22); }
UIColor *HPHaloColorAccent(void) { return HPRGB(0.36, 0.80, 1.00, 1); }
UIColor *HPHaloColorGold(void) { return HPRGB(0.97, 0.77, 0.34, 1); }
UIColor *HPHaloColorKills(void) { return HPRGB(0.43, 0.90, 0.56, 1); }
UIColor *HPHaloColorDeaths(void) { return HPRGB(1.00, 0.42, 0.40, 1); }
UIColor *HPHaloColorText(void) { return HPRGB(0.92, 0.96, 1.00, 1); }
UIColor *HPHaloColorTextSecondary(void) { return HPRGB(0.62, 0.72, 0.81, 1); }
UIColor *HPHaloColorTextTertiary(void) { return HPRGB(0.43, 0.51, 0.59, 1); }

UIColor *HPHaloToneColor(HPHaloTone tone)
{
    switch (tone) {
    case HPHaloToneAccent: return HPHaloColorAccent();
    case HPHaloToneGold: return HPHaloColorGold();
    case HPHaloToneKills: return HPHaloColorKills();
    case HPHaloToneDeaths: return HPHaloColorDeaths();
    case HPHaloToneNeutral: break;
    }
    return HPHaloColorText();
}

static UIFont *HPHaloScaled(UIFont *font, UIFontTextStyle style, CGFloat maximum)
{
    UIFontMetrics *metrics = [UIFontMetrics metricsForTextStyle:style];
    return maximum > 0 ? [metrics scaledFontForFont:font maximumPointSize:maximum] : [metrics scaledFontForFont:font];
}

UIFont *HPHaloDisplayFont(CGFloat size, UIFontWeight weight, UIFontTextStyle style, CGFloat maximum)
{
    return HPHaloScaled([UIFont systemFontOfSize:size weight:weight width:UIFontWidthCondensed], style, maximum);
}

UIFont *HPHaloNumberFont(CGFloat size, UIFontWeight weight, UIFontTextStyle style, CGFloat maximum)
{
    UIFont *base = [UIFont systemFontOfSize:size weight:weight width:UIFontWidthCondensed];
    UIFontDescriptor *descriptor = [base.fontDescriptor fontDescriptorByAddingAttributes:@{
        UIFontDescriptorFeatureSettingsAttribute: @[@{
            UIFontFeatureTypeIdentifierKey: @(kNumberSpacingType),
            UIFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)}]}];
    return HPHaloScaled([UIFont fontWithDescriptor:descriptor size:size], style, maximum);
}

UIFont *HPHaloBodyFont(UIFontTextStyle style, UIFontWeight weight, CGFloat maximum)
{
    UITraitCollection *standard = [UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryLarge];
    CGFloat size = [UIFontDescriptor preferredFontDescriptorWithTextStyle:style compatibleWithTraitCollection:standard].pointSize;
    return HPHaloScaled([UIFont systemFontOfSize:size weight:weight], style, maximum);
}

UILabel *HPHaloLabel(UIFont *font, UIColor *color, NSInteger lines)
{
    UILabel *label = [UILabel new];
    label.font = font;
    label.textColor = color;
    label.numberOfLines = lines;
    label.adjustsFontForContentSizeCategory = YES;
    return label;
}

void HPHaloSetCaps(UILabel *label, NSString *text, CGFloat tracking)
{
    NSString *original = [text isKindOfClass:NSString.class] ? text : @"";
    if (!original.length) { label.attributedText = nil; label.text = @""; label.accessibilityLabel = nil; return; }
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.alignment = label.textAlignment;
    paragraph.lineBreakMode = label.numberOfLines == 1 ? NSLineBreakByTruncatingTail : NSLineBreakByWordWrapping;
    UIColor *color = label.textColor ?: HPHaloColorText();
    UIFont *font = label.font ?: [UIFont systemFontOfSize:15];
    label.attributedText = [[NSAttributedString alloc] initWithString:original.localizedUppercaseString attributes:@{
        NSFontAttributeName: font, NSForegroundColorAttributeName: color,
        NSKernAttributeName: @(tracking), NSParagraphStyleAttributeName: paragraph}];
    label.accessibilityLabel = original;
}

UIBezierPath *HPHaloChamferPath(CGRect rect, CGFloat cut)
{
    cut = MAX((CGFloat)0, MIN(cut, MIN(CGRectGetWidth(rect), CGRectGetHeight(rect)) / 2));
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(CGRectGetMinX(rect) + cut, CGRectGetMinY(rect))];
    [path addLineToPoint:CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect))];
    [path addLineToPoint:CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect) - cut)];
    [path addLineToPoint:CGPointMake(CGRectGetMaxX(rect) - cut, CGRectGetMaxY(rect))];
    [path addLineToPoint:CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect))];
    [path addLineToPoint:CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect) + cut)];
    [path closePath];
    return path;
}

NSString *HPHaloSeasonDisplay(NSString *season)
{
    if (![season isKindOfClass:NSString.class] || !season.length) return @"This season";
    if (season.length == 7 && [season characterAtIndex:4] == '-' && [season characterAtIndex:5] == 'Q')
        return [NSString stringWithFormat:@"Q%@ %@", [season substringFromIndex:6], [season substringToIndex:4]];
    return season;
}

UIImage *HPHaloRankBadgeImage(NSString *file)
{
    /* Neutral local progression glyphs. The .png key is a catalog identifier,
       retained for model compatibility; no image or game artwork is loaded. */
    if (![file isKindOfClass:NSString.class] || ![file hasPrefix:@"local-"] ||
        ![file hasSuffix:@".png"]) return nil;
    NSString *digits = [file substringWithRange:NSMakeRange(6, file.length - 10)];
    NSInteger level = digits.integerValue;
    if (level < 1 || level > 64 || ![digits isEqualToString:[NSString stringWithFormat:@"%ld",(long)level]]) return nil;
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cache = [NSCache new]; cache.countLimit = 64; });
    UIImage *cached = [cache objectForKey:file];
    if (cached) return cached;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.scale = 3; format.opaque = NO;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(100,100) format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            (void)context;
            UIBezierPath *outer = HPHaloChamferPath(CGRectMake(7,7,86,86),17);
            [HPHaloColorPanelRaised() setFill]; [outer fill];
            [HPHaloColorGold() setStroke]; outer.lineWidth = 3; [outer stroke];
            UIBezierPath *inner = HPHaloChamferPath(CGRectMake(15,15,70,70),13);
            [[HPHaloColorAccent() colorWithAlphaComponent:0.5] setStroke]; inner.lineWidth = 1; [inner stroke];
            NSString *number = [NSString stringWithFormat:@"%ld",(long)level];
            NSDictionary *attributes = @{NSFontAttributeName:[UIFont monospacedDigitSystemFontOfSize:38 weight:UIFontWeightBold],
                NSForegroundColorAttributeName:HPHaloColorText()};
            CGSize size = [number sizeWithAttributes:attributes];
            [number drawAtPoint:CGPointMake((100-size.width)/2,(100-size.height)/2-2) withAttributes:attributes];
            [HPHaloColorAccent() setFill];
            for (NSUInteger i = 0; i < MIN((NSUInteger)level,(NSUInteger)6); ++i)
                UIRectFill(CGRectMake(27+i*8,77,5,3));
        }];
    [cache setObject:image forKey:file];
    return image;
}

#pragma mark - Panel

@implementation HPHaloPanelView {
    CAShapeLayer *_shape, *_sheenMask, *_edge, *_brackets;
    CAGradientLayer *_sheen;
}
- (instancetype)initWithFrame:(CGRect)frame
{
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    _chamfer = 12;
    _fillColor = HPHaloColorPanel();
    _strokeColor = HPHaloColorStroke();
    _shape = [CAShapeLayer layer];
    _shape.lineWidth = 1;
    _shape.shadowOffset = CGSizeZero;
    _shape.shadowRadius = 14;
    _sheen = [CAGradientLayer layer];
    _sheen.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.075].CGColor, (id)[UIColor colorWithWhite:1 alpha:0].CGColor];
    _sheen.startPoint = CGPointMake(0.5, 0);
    _sheen.endPoint = CGPointMake(0.5, 0.65);
    _sheenMask = [CAShapeLayer layer];
    _sheen.mask = _sheenMask;
    _edge = [CAShapeLayer layer];
    _edge.lineWidth = 3;
    _edge.fillColor = nil;
    _brackets = [CAShapeLayer layer];
    _brackets.lineWidth = 1.5;
    _brackets.fillColor = nil;
    for (CALayer *layer in @[_shape, _sheen, _edge, _brackets]) [self.layer addSublayer:layer];
    [self applyColors];
    return self;
}
- (void)applyColors
{
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _shape.fillColor = _fillColor.CGColor;
    _shape.strokeColor = _strokeColor.CGColor;
    _shape.shadowColor = _glowColor.CGColor;
    _shape.shadowOpacity = _glowColor ? 0.55f : 0;
    _edge.strokeColor = _edgeColor.CGColor;
    _edge.hidden = _edgeColor == nil;
    _brackets.strokeColor = [(_edgeColor ?: HPHaloColorAccent()) colorWithAlphaComponent:0.75].CGColor;
    _brackets.hidden = !_showsBrackets;
    [CATransaction commit];
}
- (void)setFillColor:(UIColor *)color { _fillColor = color ?: UIColor.clearColor; [self applyColors]; }
- (void)setStrokeColor:(UIColor *)color { _strokeColor = color ?: UIColor.clearColor; [self applyColors]; }
- (void)setEdgeColor:(UIColor *)color { _edgeColor = color; [self applyColors]; }
- (void)setGlowColor:(UIColor *)color { _glowColor = color; [self applyColors]; }
- (void)setShowsBrackets:(BOOL)value { _showsBrackets = value; [self applyColors]; }
- (void)setChamfer:(CGFloat)chamfer { _chamfer = chamfer; [self setNeedsLayout]; }
- (void)layoutSubviews
{
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGRect bounds = self.bounds;
    CGFloat w = CGRectGetWidth(bounds), h = CGRectGetHeight(bounds);
    UIBezierPath *path = HPHaloChamferPath(CGRectInset(bounds, 0.5, 0.5), _chamfer);
    for (CALayer *layer in @[_shape, _sheen, _edge, _brackets]) layer.frame = bounds;
    _sheenMask.frame = bounds;
    _shape.path = path.CGPath;
    _shape.shadowPath = path.CGPath;
    _sheenMask.path = path.CGPath;
    CGFloat cut = MIN(_chamfer, MIN(w, h) / 2);
    UIBezierPath *edge = [UIBezierPath bezierPath];
    [edge moveToPoint:CGPointMake(1.5, cut + 4)];
    [edge addLineToPoint:CGPointMake(1.5, MAX(cut + 4, h - 4))];
    _edge.path = edge.CGPath;
    CGFloat length = MIN((CGFloat)12, MIN(w, h) / 4);
    UIBezierPath *brackets = [UIBezierPath bezierPath];
    [brackets moveToPoint:CGPointMake(w - length - 0.75, 0.75)];
    [brackets addLineToPoint:CGPointMake(w - 0.75, 0.75)];
    [brackets addLineToPoint:CGPointMake(w - 0.75, length + 0.75)];
    [brackets moveToPoint:CGPointMake(0.75, h - length - 0.75)];
    [brackets addLineToPoint:CGPointMake(0.75, h - 0.75)];
    [brackets addLineToPoint:CGPointMake(length + 0.75, h - 0.75)];
    _brackets.path = brackets.CGPath;
    [CATransaction commit];
}
@end

#pragma mark - Backdrop and glow

@implementation HPHaloBackdropView
- (instancetype)initWithFrame:(CGRect)frame
{
    if (!(self = [super initWithFrame:frame])) return nil;
    self.contentMode = UIViewContentModeRedraw;
    self.backgroundColor = HPHaloColorBackground();
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = NO;
    return self;
}
- (void)drawRect:(CGRect)rect
{
    (void)rect;
    CGContextRef cg = UIGraphicsGetCurrentContext();
    CGRect bounds = self.bounds;
    CGFloat w = CGRectGetWidth(bounds), h = CGRectGetHeight(bounds);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat base[] = {0.050, 0.092, 0.135, 1, 0.022, 0.042, 0.066, 1, 0.010, 0.019, 0.032, 1};
    CGFloat baseStops[] = {0, 0.42, 1};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, base, baseStops, 3);
    CGContextDrawLinearGradient(cg, gradient, CGPointZero, CGPointMake(0, h), 0);
    CGGradientRelease(gradient);

    /* Faint flat-top hex lattice. */
    CGFloat radius = 17, rowHeight = (CGFloat)sqrt(3.0) * radius;
    CGMutablePathRef lattice = CGPathCreateMutable();
    NSInteger columns = (NSInteger)ceil(w / (radius * 1.5)) + 1, rows = (NSInteger)ceil(h / rowHeight) + 1;
    for (NSInteger column = 0; column <= columns; column++) {
        for (NSInteger row = -1; row <= rows; row++) {
            CGFloat cx = column * radius * 1.5, cy = row * rowHeight + (column % 2 ? rowHeight / 2 : 0);
            for (NSInteger side = 0; side <= 6; side++) {
                CGFloat angle = (CGFloat)(M_PI / 3.0 * side);
                CGPoint point = CGPointMake(cx + cos(angle) * radius, cy + sin(angle) * radius);
                if (side == 0) CGPathMoveToPoint(lattice, NULL, point.x, point.y);
                else CGPathAddLineToPoint(lattice, NULL, point.x, point.y);
            }
        }
    }
    CGContextSetStrokeColorWithColor(cg, HPRGB(0.55, 0.82, 1, 0.05).CGColor);
    CGContextSetLineWidth(cg, 0.75);
    CGContextAddPath(cg, lattice);
    CGContextStrokePath(cg);
    CGPathRelease(lattice);

    /* Cool light from above, then a fade into the dark at the bottom. */
    CGFloat glow[] = {0.36, 0.80, 1.0, 0.17, 0.36, 0.80, 1.0, 0};
    CGFloat glowStops[] = {0, 1};
    CGGradientRef light = CGGradientCreateWithColorComponents(space, glow, glowStops, 2);
    CGPoint center = CGPointMake(w * 0.5, -MIN(w, (CGFloat)900) * 0.12);
    CGContextDrawRadialGradient(cg, light, center, 0, center, MAX(w * 0.8, (CGFloat)340), 0);
    CGGradientRelease(light);
    CGFloat fade[] = {0.010, 0.019, 0.032, 0, 0.010, 0.019, 0.032, 0.85};
    CGFloat fadeStops[] = {0, 1};
    CGGradientRef bottom = CGGradientCreateWithColorComponents(space, fade, fadeStops, 2);
    CGContextDrawLinearGradient(cg, bottom, CGPointMake(0, h * 0.45), CGPointMake(0, h), 0);
    CGGradientRelease(bottom);
    CGColorSpaceRelease(space);
}
@end

@implementation HPHaloGlowView
- (instancetype)initWithFrame:(CGRect)frame
{
    if (!(self = [super initWithFrame:frame])) return nil;
    self.contentMode = UIViewContentModeRedraw;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = NO;
    _glowColor = HPHaloColorAccent();
    return self;
}
- (void)setGlowColor:(UIColor *)color { _glowColor = color ?: HPHaloColorAccent(); [self setNeedsDisplay]; }
- (void)drawRect:(CGRect)rect
{
    (void)rect;
    CGRect bounds = self.bounds;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [_glowColor getRed:&r green:&g blue:&b alpha:&a];
    CGFloat components[] = {r, g, b, 0.42, r, g, b, 0.12, r, g, b, 0};
    CGFloat stops[] = {0, 0.45, 1};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGGradientRef gradient = CGGradientCreateWithColorComponents(space, components, stops, 3);
    CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    CGContextDrawRadialGradient(UIGraphicsGetCurrentContext(), gradient, center, 0, center,
        MIN(CGRectGetWidth(bounds), CGRectGetHeight(bounds)) / 2, 0);
    CGGradientRelease(gradient);
    CGColorSpaceRelease(space);
}
@end

#pragma mark - Meter

@interface HPHaloGradientStrip : UIView
@end
@implementation HPHaloGradientStrip
+ (Class)layerClass { return CAGradientLayer.class; }
@end

@implementation HPHaloMeterView {
    CAShapeLayer *_track, *_clipMask, *_ticks;
    UIView *_clip, *_glow, *_cap;
    HPHaloGradientStrip *_fill;
}
- (instancetype)initWithFrame:(CGRect)frame
{
    if (!(self = [super initWithFrame:frame])) return nil;
    self.backgroundColor = UIColor.clearColor;
    self.userInteractionEnabled = NO;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitUpdatesFrequently;
    _barHeight = 8;
    _meterColor = HPHaloColorAccent();
    _track = [CAShapeLayer layer];
    _track.fillColor = [UIColor colorWithWhite:1 alpha:0.06].CGColor;
    _track.strokeColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    _track.lineWidth = 1;
    [self.layer addSublayer:_track];
    _glow = [UIView new];
    _glow.layer.shadowOffset = CGSizeZero;
    _glow.layer.shadowRadius = 7;
    _glow.layer.shadowOpacity = 0.85f;
    [self addSubview:_glow];
    _clip = [UIView new];
    _clipMask = [CAShapeLayer layer];
    _clip.layer.mask = _clipMask;
    [self addSubview:_clip];
    _fill = [HPHaloGradientStrip new];
    ((CAGradientLayer *)_fill.layer).startPoint = CGPointMake(0, 0.5);
    ((CAGradientLayer *)_fill.layer).endPoint = CGPointMake(1, 0.5);
    [_clip addSubview:_fill];
    _cap = [UIView new];
    _cap.backgroundColor = [UIColor colorWithWhite:1 alpha:0.92];
    [_clip addSubview:_cap];
    _ticks = [CAShapeLayer layer];
    _ticks.strokeColor = [HPHaloColorBackground() colorWithAlphaComponent:0.92].CGColor;
    _ticks.lineWidth = 2;
    [self.layer addSublayer:_ticks];
    [self applyMeterColor];
    return self;
}
- (CGSize)intrinsicContentSize { return CGSizeMake(UIViewNoIntrinsicMetric, _barHeight); }
- (void)setBarHeight:(CGFloat)height { _barHeight = MAX((CGFloat)2, height); [self invalidateIntrinsicContentSize]; [self setNeedsLayout]; }
- (void)setSegments:(NSUInteger)segments { _segments = MIN(segments, (NSUInteger)64); [self setNeedsLayout]; }
- (void)setMeterColor:(UIColor *)color { _meterColor = color ?: HPHaloColorAccent(); [self applyMeterColor]; }
- (void)applyMeterColor
{
    ((CAGradientLayer *)_fill.layer).colors = @[(id)[_meterColor colorWithAlphaComponent:0.55].CGColor, (id)_meterColor.CGColor];
    _glow.backgroundColor = [_meterColor colorWithAlphaComponent:0.5];
    _glow.layer.shadowColor = _meterColor.CGColor;
}
- (void)setProgress:(CGFloat)progress
{
    _progress = isfinite(progress) ? MAX((CGFloat)0, MIN((CGFloat)1, progress)) : 0;
    [self setNeedsLayout];
}
- (void)setProgress:(CGFloat)progress animated:(BOOL)animated
{
    if (!animated || !self.window || UIAccessibilityIsReduceMotionEnabled()) { self.progress = progress; return; }
    [self layoutIfNeeded];
    self.progress = progress;
    [UIView animateWithDuration:0.7 delay:0 usingSpringWithDamping:0.92 initialSpringVelocity:0
        options:UIViewAnimationOptionBeginFromCurrentState animations:^{ [self layoutIfNeeded]; } completion:nil];
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGFloat w = CGRectGetWidth(bounds), h = CGRectGetHeight(bounds);
    CGFloat cut = MIN((CGFloat)4, h / 2);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _track.frame = bounds;
    _track.path = HPHaloChamferPath(CGRectInset(bounds, 0.5, 0.5), cut).CGPath;
    _clip.frame = bounds;
    _clipMask.frame = bounds;
    _clipMask.path = HPHaloChamferPath(bounds, cut).CGPath;
    _ticks.frame = bounds;
    UIBezierPath *ticks = [UIBezierPath bezierPath];
    if (_segments > 1) {
        for (NSUInteger i = 1; i < _segments; i++) {
            CGFloat x = round(w * (CGFloat)i / (CGFloat)_segments);
            [ticks moveToPoint:CGPointMake(x, 0)];
            [ticks addLineToPoint:CGPointMake(x, h)];
        }
    }
    _ticks.path = ticks.CGPath;
    [CATransaction commit];
    CGFloat fillWidth = round(w * _progress);
    _fill.frame = CGRectMake(0, 0, fillWidth, h);
    _glow.frame = CGRectMake(0, 1, fillWidth, MAX((CGFloat)0, h - 2));
    _glow.layer.shadowPath = [UIBezierPath bezierPathWithRect:_glow.bounds].CGPath;
    _glow.hidden = fillWidth < 1;
    _cap.frame = CGRectMake(MAX((CGFloat)0, fillWidth - 2), 0, 2, h);
    _cap.hidden = fillWidth < 3 || _progress >= 0.999;
}
@end

#pragma mark - Tile button and tag

@implementation HPHaloTileButton {
    UIImageView *_chevron;
    UIStackView *_text;
}
+ (instancetype)tile { return [self buttonWithType:UIButtonTypeCustom]; }
- (instancetype)initWithFrame:(CGRect)frame
{
    if (!(self = [super initWithFrame:frame])) return nil;
    _panel = [HPHaloPanelView new];
    _panel.userInteractionEnabled = NO;
    _panel.chamfer = 12;
    _panel.edgeColor = HPHaloColorAccent();
    _iconView = [UIImageView new];
    _iconView.contentMode = UIViewContentModeScaleAspectFit;
    _iconView.tintColor = HPHaloColorAccent();
    _iconView.userInteractionEnabled = NO;
    _headline = HPHaloLabel(HPHaloDisplayFont(18, UIFontWeightBold, UIFontTextStyleHeadline, 28), HPHaloColorText(), 0);
    _detail = HPHaloLabel(HPHaloBodyFont(UIFontTextStyleFootnote, UIFontWeightRegular, 22), HPHaloColorTextSecondary(), 0);
    /* Equal-height horizontal tiles can have spare vertical room. Keep that
     * room in the detail instead of allowing either label to stretch equally. */
    [_headline setContentHuggingPriority:UILayoutPriorityDefaultLow+1 forAxis:UILayoutConstraintAxisVertical];
    UIImageSymbolConfiguration *symbol = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightBold];
    _chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:symbol]];
    _chevron.tintColor = HPHaloColorAccent();
    _chevron.contentMode = UIViewContentModeCenter;
    _text = [[UIStackView alloc] initWithArrangedSubviews:@[_headline, _detail]];
    _text.axis = UILayoutConstraintAxisVertical;
    _text.spacing = 2;
    _text.userInteractionEnabled = NO;
    for (UIView *view in @[_panel, _iconView, _text, _chevron]) {
        view.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:view];
    }
    [_chevron setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [_chevron setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    /* Below-required priorities let a hidden tile collapse inside a stack view. */
    NSLayoutConstraint *top = [_text.topAnchor constraintEqualToAnchor:self.topAnchor constant:13];
    NSLayoutConstraint *bottom = [_text.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-13];
    top.priority = bottom.priority = UILayoutPriorityDefaultHigh;
    NSLayoutConstraint *minimumTop = [_text.topAnchor constraintGreaterThanOrEqualToAnchor:self.topAnchor constant:13];
    NSLayoutConstraint *minimumBottom = [_text.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-13];
    NSLayoutConstraint *minimumHeight = [self.heightAnchor constraintGreaterThanOrEqualToConstant:64];
    NSLayoutConstraint *iconHeight = [_iconView.heightAnchor constraintEqualToConstant:40];
    minimumTop.priority = minimumBottom.priority = minimumHeight.priority = iconHeight.priority = 999;
    [NSLayoutConstraint activateConstraints:@[
        [_panel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_panel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_panel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_panel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_iconView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:18],
        [_iconView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_iconView.widthAnchor constraintEqualToConstant:40],
        [_text.leadingAnchor constraintEqualToAnchor:_iconView.trailingAnchor constant:14],
        [_text.centerYAnchor constraintEqualToAnchor:self.centerYAnchor], top, bottom,
        minimumTop, minimumBottom, minimumHeight, iconHeight,
        [_chevron.leadingAnchor constraintEqualToAnchor:_text.trailingAnchor constant:10],
        [_chevron.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_chevron.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_chevron.widthAnchor constraintEqualToConstant:14]]];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    [self refreshLook];
    return self;
}
- (CGSize)intrinsicContentSize { return CGSizeMake(UIViewNoIntrinsicMetric, UIViewNoIntrinsicMetric); }
- (void)setHeadline:(NSString *)headline detail:(NSString *)detail icon:(UIImage *)icon
{
    HPHaloSetCaps(_headline, headline, 1.6);
    _detail.text = detail ?: @"";
    _detail.hidden = detail.length == 0;
    _iconView.image = icon;
}
- (NSString *)accessibilityLabel { return [super accessibilityLabel] ?: _headline.accessibilityLabel; }
- (NSString *)accessibilityValue { return [super accessibilityValue] ?: (_detail.hidden ? nil : _detail.text); }
- (void)setActiveLook:(BOOL)active { _activeLook = active; [self refreshLook]; }
- (void)setHighlighted:(BOOL)highlighted { [super setHighlighted:highlighted]; [self refreshLook]; }
- (void)setEnabled:(BOOL)enabled { [super setEnabled:enabled]; [self refreshLook]; }
- (void)refreshLook
{
    UIColor *accent = HPHaloColorAccent();
    _panel.fillColor = self.highlighted ? HPHaloColorPanelRaised() :
        _activeLook ? [UIColor colorWithRed:0.07 green:0.17 blue:0.24 alpha:0.95] : HPHaloColorPanel();
    _panel.strokeColor = _activeLook || self.highlighted ? [accent colorWithAlphaComponent:0.7] : HPHaloColorStroke();
    _panel.glowColor = _activeLook ? [accent colorWithAlphaComponent:0.6] : nil;
    _panel.showsBrackets = _activeLook;
    self.alpha = self.enabled ? 1 : 0.45;
    self.transform = self.highlighted && !UIAccessibilityIsReduceMotionEnabled() ? CGAffineTransformMakeScale(0.985, 0.985) : CGAffineTransformIdentity;
}
@end

@implementation HPHaloTagView {
    HPHaloPanelView *_panel;
}
- (instancetype)initWithFrame:(CGRect)frame
{
    if (!(self = [super initWithFrame:frame])) return nil;
    _panel = [HPHaloPanelView new];
    _panel.chamfer = 5;
    _panel.translatesAutoresizingMaskIntoConstraints = NO;
    _label = HPHaloLabel(HPHaloDisplayFont(11, UIFontWeightBold, UIFontTextStyleCaption2, 17), HPHaloColorAccent(), 1);
    _label.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_panel];
    [self addSubview:_label];
    [NSLayoutConstraint activateConstraints:@[
        [_panel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_panel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [_panel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_panel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_label.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
        [_label.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [_label.topAnchor constraintEqualToAnchor:self.topAnchor constant:3],
        [_label.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-3]]];
    [self setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [self setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return self;
}
- (void)setText:(NSString *)text color:(UIColor *)color filled:(BOOL)filled
{
    _label.textColor = filled ? HPHaloColorBackground() : color;
    HPHaloSetCaps(_label, text, 1.4);
    _panel.fillColor = filled ? color : [color colorWithAlphaComponent:0.10];
    _panel.strokeColor = [color colorWithAlphaComponent:filled ? 1 : 0.55];
}
@end

#pragma mark - Table chrome

UIView *HPHaloSectionHeaderView(NSString *title, NSString *trailing)
{
    UIView *view = [UIView new];
    view.backgroundColor = UIColor.clearColor;
    UIView *marker = [UIView new];
    marker.backgroundColor = HPHaloColorAccent();
    marker.layer.shadowColor = HPHaloColorAccent().CGColor;
    marker.layer.shadowOpacity = 0.8f;
    marker.layer.shadowRadius = 4;
    marker.layer.shadowOffset = CGSizeZero;
    UILabel *label = HPHaloLabel(HPHaloDisplayFont(15, UIFontWeightBold, UIFontTextStyleSubheadline, 24), [HPHaloColorText() colorWithAlphaComponent:0.9], 0);
    HPHaloSetCaps(label, title, 2.4);
    label.accessibilityTraits = UIAccessibilityTraitHeader;
    HPHaloGradientStrip *rule = [HPHaloGradientStrip new];
    CAGradientLayer *gradient = (CAGradientLayer *)rule.layer;
    gradient.colors = @[(id)[HPHaloColorAccent() colorWithAlphaComponent:0.45].CGColor, (id)[HPHaloColorAccent() colorWithAlphaComponent:0].CGColor];
    gradient.startPoint = CGPointMake(0, 0.5);
    gradient.endPoint = CGPointMake(1, 0.5);
    UILabel *extra = HPHaloLabel(HPHaloNumberFont(14, UIFontWeightSemibold, UIFontTextStyleFootnote, 22), HPHaloColorTextSecondary(), 1);
    HPHaloSetCaps(extra, trailing, 1.2);
    extra.hidden = trailing.length == 0;
    for (UIView *child in @[marker, label, rule, extra]) {
        child.translatesAutoresizingMaskIntoConstraints = NO;
        [view addSubview:child];
    }
    [label setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [extra setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [NSLayoutConstraint activateConstraints:@[
        [marker.leadingAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.leadingAnchor constant:18],
        [marker.widthAnchor constraintEqualToConstant:3],
        [marker.heightAnchor constraintEqualToConstant:14],
        [marker.centerYAnchor constraintEqualToAnchor:label.firstBaselineAnchor constant:-5],
        [label.leadingAnchor constraintEqualToAnchor:marker.trailingAnchor constant:10],
        [label.topAnchor constraintEqualToAnchor:view.topAnchor constant:26],
        [label.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-10],
        [rule.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:12],
        [rule.heightAnchor constraintEqualToConstant:1],
        [rule.centerYAnchor constraintEqualToAnchor:marker.centerYAnchor],
        [rule.widthAnchor constraintGreaterThanOrEqualToConstant:16],
        [extra.leadingAnchor constraintEqualToAnchor:rule.trailingAnchor constant:10],
        [extra.trailingAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.trailingAnchor constant:-18],
        [extra.centerYAnchor constraintEqualToAnchor:marker.centerYAnchor]]];
    return view;
}

UIView *HPHaloSectionFooterView(NSString *text)
{
    UIView *view = [UIView new];
    UILabel *label = HPHaloLabel(HPHaloBodyFont(UIFontTextStyleFootnote, UIFontWeightRegular, 22), HPHaloColorTextTertiary(), 0);
    label.text = text;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:label];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.leadingAnchor constant:20],
        [label.trailingAnchor constraintEqualToAnchor:view.safeAreaLayoutGuide.trailingAnchor constant:-20],
        [label.topAnchor constraintEqualToAnchor:view.topAnchor constant:10],
        [label.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-4]]];
    return view;
}

UIView *HPHaloNavigationTitle(NSString *title)
{
    UILabel *label = HPHaloLabel(HPHaloDisplayFont(17, UIFontWeightHeavy, UIFontTextStyleHeadline, 22), HPHaloColorText(), 1);
    label.textAlignment = NSTextAlignmentCenter;
    HPHaloSetCaps(label, title, 3.2);
    label.accessibilityTraits = UIAccessibilityTraitHeader;
    [label sizeToFit];
    return label;
}

NSLayoutConstraint *HPCellBottom(UIView *content, UIView *contentView, CGFloat constant)
{
    NSLayoutConstraint *bottom = [content.bottomAnchor constraintEqualToAnchor:contentView.bottomAnchor constant:constant];
    bottom.priority = 999;
    return bottom;
}

void HPHaloStyleTable(UITableView *table)
{
    table.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    table.backgroundColor = HPHaloColorBackground();
    table.backgroundView = [HPHaloBackdropView new];
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.sectionHeaderTopPadding = 0;
    table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    table.sectionHeaderHeight = UITableViewAutomaticDimension;
    table.estimatedSectionHeaderHeight = 56;
    table.sectionFooterHeight = UITableViewAutomaticDimension;
    table.estimatedSectionFooterHeight = 32;
    UIEdgeInsets inset = table.contentInset;
    inset.bottom = MAX(inset.bottom, (CGFloat)28);
    table.contentInset = inset;
}

static UIImage *HPHaloSegmentImage(UIColor *fill, UIColor *stroke, UIColor *bar)
{
    CGSize size = CGSizeMake(12, 36);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format]
        imageWithActions:^(UIGraphicsImageRendererContext *context) {
            CGRect rect = CGRectMake(0, 0, size.width, size.height);
            [fill setFill];
            UIRectFill(rect);
            [stroke setStroke];
            UIBezierPath *outline = [UIBezierPath bezierPathWithRect:CGRectInset(rect, 0.5, 0.5)];
            outline.lineWidth = 1;
            [outline stroke];
            if (bar) { [bar setFill]; UIRectFill(CGRectMake(0, size.height - 2.5, size.width, 2.5)); }
            (void)context;
        }];
    return [image resizableImageWithCapInsets:UIEdgeInsetsMake(4, 5, 4, 5) resizingMode:UIImageResizingModeStretch];
}

void HPHaloStyleSegmented(UISegmentedControl *control)
{
    UIColor *accent = HPHaloColorAccent();
    control.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UIImage *normal = HPHaloSegmentImage([UIColor colorWithWhite:1 alpha:0.035], [UIColor colorWithWhite:1 alpha:0.10], nil);
    UIImage *selected = HPHaloSegmentImage([accent colorWithAlphaComponent:0.17], [accent colorWithAlphaComponent:0.5], accent);
    UIImage *pressed = HPHaloSegmentImage([UIColor colorWithWhite:1 alpha:0.08], [UIColor colorWithWhite:1 alpha:0.16], nil);
    [control setBackgroundImage:normal forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
    [control setBackgroundImage:selected forState:UIControlStateSelected barMetrics:UIBarMetricsDefault];
    [control setBackgroundImage:pressed forState:UIControlStateHighlighted barMetrics:UIBarMetricsDefault];
    [control setBackgroundImage:selected forState:UIControlStateSelected | UIControlStateHighlighted barMetrics:UIBarMetricsDefault];
    UIImage *divider = HPHaloSegmentImage([UIColor colorWithWhite:1 alpha:0.10], UIColor.clearColor, nil);
    for (NSNumber *left in @[@(UIControlStateNormal), @(UIControlStateSelected)])
        for (NSNumber *right in @[@(UIControlStateNormal), @(UIControlStateSelected)])
            [control setDividerImage:divider forLeftSegmentState:left.unsignedIntegerValue
                rightSegmentState:right.unsignedIntegerValue barMetrics:UIBarMetricsDefault];
    /* Segments cannot wrap, so the face stops growing early and tracking tightens. */
    UIFont *font = HPHaloDisplayFont(14, UIFontWeightBold, UIFontTextStyleSubheadline, 16.5);
    [control setTitleTextAttributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: HPHaloColorTextSecondary(),
        NSKernAttributeName: @1.2} forState:UIControlStateNormal];
    [control setTitleTextAttributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: HPHaloColorText(),
        NSKernAttributeName: @1.2} forState:UIControlStateSelected];
    for (NSUInteger i = 0; i < control.numberOfSegments; i++) {
        NSString *title = [control titleForSegmentAtIndex:i];
        if (title.length) {
            [control setTitle:title.localizedUppercaseString forSegmentAtIndex:i];
            /* VoiceOver keeps reading natural words rather than spelling capitals. */
        }
    }
    control.apportionsSegmentWidthsByContent = control.numberOfSegments > 2;
    [control.heightAnchor constraintGreaterThanOrEqualToConstant:38].active = YES;
}

void HPHaloStyleNavigation(UINavigationController *navigation)
{
    UIColor *accent = HPHaloColorAccent();
    navigation.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    navigation.view.backgroundColor = HPHaloColorBackground();
    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = HPRGB(0.030, 0.058, 0.088, 1);
    appearance.shadowColor = [accent colorWithAlphaComponent:0.3];
    appearance.titleTextAttributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightHeavy width:UIFontWidthCondensed],
        NSForegroundColorAttributeName: HPHaloColorText(), NSKernAttributeName: @3.0};
    UIBarButtonItemAppearance *buttons = [UIBarButtonItemAppearance new];
    buttons.normal.titleTextAttributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold width:UIFontWidthCondensed],
        NSForegroundColorAttributeName: accent, NSKernAttributeName: @1.0};
    UIBarButtonItemAppearance *done = [UIBarButtonItemAppearance new];
    done.normal.titleTextAttributes = @{
        NSFontAttributeName: [UIFont systemFontOfSize:16 weight:UIFontWeightBold width:UIFontWidthCondensed],
        NSForegroundColorAttributeName: accent, NSKernAttributeName: @1.0};
    appearance.buttonAppearance = buttons;
    appearance.backButtonAppearance = buttons;
    appearance.doneButtonAppearance = done;
    UINavigationBar *bar = navigation.navigationBar;
    bar.standardAppearance = appearance;
    bar.scrollEdgeAppearance = appearance;
    bar.compactAppearance = appearance;
    bar.compactScrollEdgeAppearance = appearance;
    bar.tintColor = accent;
}

void HPHaloStyleDoneButton(UIBarButtonItem *item)
{
    item.tintColor = HPHaloColorAccent();
}
