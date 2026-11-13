/* HaloPad touch controls and the three-dot menu: see HaloPadOverlay.h. Structure, colours, sizes
 * and the layout editor follow SunPad's SunPadGameOverlay.mm (ref/sunpad at e43f0ea, GPL-3.0). */
#import "HaloPadOverlay.h"
#import <GameController/GameController.h>
#include <math.h>
#include <unistd.h>

#include "../runtime/halopad_input.h"
#include "../runtime/halopad_log.h"

/* ---- settings (NSUserDefaults, HaloPad-owned keys) ---- */

@implementation HPSettings
+ (instancetype)shared
{
    static HPSettings *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [HPSettings new];
        [NSUserDefaults.standardUserDefaults registerDefaults:@{
            @"HaloPad.controlOpacity": @0.8, @"HaloPad.controlSize": @1.0, @"HaloPad.lookSensitivity": @1.5,
            @"HaloPad.hideWithController": @YES, @"HaloPad.hideTouchControls": @NO, @"HaloPad.showFPS": @NO,
            @"HaloPad.aspect": @0, @"HaloPad.recentServers": @[], @"HaloPad.leftHanded": @NO, @"HaloPad.showCaptions": @YES,
            @"HaloPad.ringSpacing": @1, @"HaloPad.mouseSpeed": @1.0}];
    });
    return s;
}
#define HP_SETTING(type, get, set, key, box, unbox) \
    - (type)get { return (type)[(NSNumber *)[NSUserDefaults.standardUserDefaults objectForKey:key] unbox]; } \
    - (void)set:(type)v { [NSUserDefaults.standardUserDefaults setObject:box forKey:key]; }
HP_SETTING(CGFloat, controlOpacity, setControlOpacity, @"HaloPad.controlOpacity", @(fmin(1, fmax(0.25, v))), doubleValue)
HP_SETTING(CGFloat, controlSize, setControlSize, @"HaloPad.controlSize", @(fmin(1.35, fmax(0.7, v))), doubleValue)
HP_SETTING(CGFloat, lookSensitivity, setLookSensitivity, @"HaloPad.lookSensitivity", @(fmin(6, fmax(0.25, v))), doubleValue)
HP_SETTING(CGFloat, mouseSpeed, setMouseSpeed, @"HaloPad.mouseSpeed", @(fmin(4, fmax(0.25, v))), doubleValue)
HP_SETTING(BOOL, hideWithController, setHideWithController, @"HaloPad.hideWithController", @(v), boolValue)
HP_SETTING(BOOL, hideTouchControls, setHideTouchControls, @"HaloPad.hideTouchControls", @(v), boolValue)
HP_SETTING(BOOL, showFPS, setShowFPS, @"HaloPad.showFPS", @(v), boolValue)
HP_SETTING(HPAspectMode, aspect, setAspect, @"HaloPad.aspect", @(v), integerValue)
HP_SETTING(BOOL, leftHanded, setLeftHanded, @"HaloPad.leftHanded", @(v), boolValue)
HP_SETTING(BOOL, showCaptions, setShowCaptions, @"HaloPad.showCaptions", @(v), boolValue)
HP_SETTING(NSInteger, ringSpacing, setRingSpacing, @"HaloPad.ringSpacing", @(MIN(2, MAX(0, v))), integerValue)
- (NSArray<NSString *> *)recentServers { return [NSUserDefaults.standardUserDefaults stringArrayForKey:@"HaloPad.recentServers"] ?: @[]; }
- (void)setRecentServers:(NSArray<NSString *> *)v { [NSUserDefaults.standardUserDefaults setObject:v forKey:@"HaloPad.recentServers"]; }
@end

/* ---- Windows input ---- */

/* Typed keys (text, the console key, chat keys) wait in a queue and go to Halo one event every
   50 ms, a little over one of Halo's frames: its keyboard is read once a frame, and a key that
   goes down and up between two reads is never seen. Held controls post at once. */
static NSMutableArray<NSValue *> *typed_queue;
static NSMutableDictionary<NSNumber *, NSValue *> *typed_held;
static BOOL typed_active = YES;
static void queue_key(uint32_t vk, uint32_t side, uint32_t scan, int down, unichar ch)
{
    if (!typed_active) return;
    hp_input e = {.kind = HPI_KEY, .vk = vk, .side_vk = side ? side : vk, .scan = scan, .down = down};
    if (down && ch) { e.chars[0] = ch; e.nchars = 1; }
    if (!typed_queue) {
        typed_queue = [NSMutableArray array];
        typed_held = [NSMutableDictionary dictionary];
        [NSTimer scheduledTimerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *t) {
            if (!typed_active || !typed_queue.count) return;
            hp_input next;
            [typed_queue.firstObject getValue:&next size:sizeof next];
            [typed_queue removeObjectAtIndex:0];
            NSNumber *key = @(next.side_vk);
            if (next.down) typed_held[key] = [NSValue valueWithBytes:&next objCType:@encode(hp_input)];
            else [typed_held removeObjectForKey:key];
            halopad_host_post_input(&next);
        }];
    }
    [typed_queue addObject:[NSValue valueWithBytes:&e objCType:@encode(hp_input)]];
}

/* A character on a US keyboard: virtual key, scan code, whether Shift is held. */
static int us_key(unichar c, uint32_t *vk, uint32_t *scan, int *shift)
{
    static const char row1[] = "1234567890", qrow[] = "qwertyuiop", arow[] = "asdfghjkl", zrow[] = "zxcvbnm";
    static const char shifted1[] = "!@#$%^&*()";
    *shift = 0;
    if (c >= 'A' && c <= 'Z') { *shift = 1; c = c - 'A' + 'a'; }
    const char *p;
    if (c < 128 && (p = strchr(shifted1, (char)c)) && c) { *shift = 1; c = row1[p - shifted1]; }
    if (c < 128 && c && (p = strchr(row1, (char)c))) { *vk = (uint32_t)c; *scan = 0x02 + (uint32_t)(p - row1); return 1; }
    if (c < 128 && c && (p = strchr(qrow, (char)c))) { *vk = (uint32_t)(c - 32); *scan = 0x10 + (uint32_t)(p - qrow); return 1; }
    if (c < 128 && c && (p = strchr(arow, (char)c))) { *vk = (uint32_t)(c - 32); *scan = 0x1e + (uint32_t)(p - arow); return 1; }
    if (c < 128 && c && (p = strchr(zrow, (char)c))) { *vk = (uint32_t)(c - 32); *scan = 0x2c + (uint32_t)(p - zrow); return 1; }
    static const struct { unichar c; uint32_t vk, scan; int shift; } other[] = {
        {' ', 0x20, 0x39, 0}, {'.', 0xBE, 0x34, 0}, {',', 0xBC, 0x33, 0}, {';', 0xBA, 0x27, 0}, {':', 0xBA, 0x27, 1},
        {'-', 0xBD, 0x0c, 0}, {'_', 0xBD, 0x0c, 1}, {'=', 0xBB, 0x0d, 0}, {'+', 0xBB, 0x0d, 1}, {'/', 0xBF, 0x35, 0},
        {'?', 0xBF, 0x35, 1}, {'\'', 0xDE, 0x28, 0}, {'"', 0xDE, 0x28, 1}, {'[', 0xDB, 0x1a, 0}, {']', 0xDD, 0x1b, 0},
        {'\\', 0xDC, 0x2b, 0}, {'<', 0xBC, 0x33, 1}, {'>', 0xBE, 0x34, 1}, {'\n', 0x0D, 0x1c, 0}, {'\b', 0x08, 0x0e, 0}};
    for (unsigned i = 0; i < sizeof other / sizeof other[0]; i++)
        if (other[i].c == c) { *vk = other[i].vk; *scan = other[i].scan; *shift |= other[i].shift; return 1; }
    return 0;
}

/* ---- controls ---- */

/* Opt-in development trace: distinguish missing UIKit drags from lost host input.
   Logs geometry and phases only, never typed text or player data. */
static void trace_touches(UIView *view, NSSet<UITouch *> *touches, const char *phase)
{
    if (!getenv("HALOPAD_TRACE_TOUCH")) return;
    for (UITouch *touch in touches) {
        CGPoint p = [touch locationInView:view];
        fprintf(stderr, "HALOPAD TOUCH: %.3f %s %s type %ld point %.1f %.1f\n",
                touch.timestamp, (view.accessibilityIdentifier ?: @"surface").UTF8String,
                phase, (long)touch.type, p.x, p.y);
    }
}

/* UIKit can deliver a last displacement with touchesEnded, including a short
   swipe with no touchesMoved. Remember the last consumed point independently
   for each finger; never consume a cancelled or previously cleared gesture. */
@interface HPLookDrag : NSObject
@property(nonatomic, copy) void (^delta)(CGFloat dx, CGFloat dy);
- (void)begin:(id)token at:(CGPoint)point;
- (void)move:(id)token to:(CGPoint)point;
- (void)end:(id)token at:(CGPoint)point cancelled:(BOOL)cancelled;
- (void)clear;
@end
@implementation HPLookDrag {
    NSMapTable<id, NSValue *> *_points;
}
- (instancetype)init
{
    if ((self = [super init])) _points = [NSMapTable strongToStrongObjectsMapTable];
    return self;
}
- (void)begin:(id)token at:(CGPoint)point { [_points setObject:[NSValue valueWithCGPoint:point] forKey:token]; }
- (void)move:(id)token to:(CGPoint)point
{
    NSValue *last = [_points objectForKey:token];
    if (!last) return;
    [_points setObject:[NSValue valueWithCGPoint:point] forKey:token];
    CGPoint previous = last.CGPointValue;
    if (self.delta && !CGPointEqualToPoint(previous, point)) self.delta(point.x - previous.x, point.y - previous.y);
}
- (void)end:(id)token at:(CGPoint)point cancelled:(BOOL)cancelled
{
    if (!cancelled) [self move:token to:point];
    [_points removeObjectForKey:token];
}
- (void)clear { [_points removeAllObjects]; }
@end

@interface HPStickView : UIView
@property(nonatomic, copy) void (^valueChanged)(float x, float y);
@property(nonatomic) BOOL editing;
@property(nonatomic, strong) UILabel *caption;
- (void)reset;
- (void)track:(UITouch *)t;
- (void)trackPoint:(CGPoint)p;
@end

@implementation HPStickView {
    UIView *_thumb;
    UITouch *_activeTouch;
    float _x, _y;
}
- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = NO;
        self.clipsToBounds = YES;
        self.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.30];
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.30].CGColor;
        self.layer.borderWidth = 1.5;
        _thumb = [UIView new];
        _thumb.backgroundColor = [UIColor colorWithWhite:1 alpha:0.55];
        _thumb.userInteractionEnabled = NO;
        [self addSubview:_thumb];
        _caption = [UILabel new];
        _caption.textAlignment = NSTextAlignmentCenter;
        _caption.textColor = [UIColor colorWithWhite:1 alpha:0.65];
        _caption.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
        _caption.userInteractionEnabled = NO;
        [self addSubview:_caption];
    }
    return self;
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat side = fmin(self.bounds.size.width, self.bounds.size.height), t = side * 0.42;
    self.layer.cornerRadius = side / 2;
    _thumb.bounds = CGRectMake(0, 0, t, t);
    _thumb.layer.cornerRadius = t / 2;
    _caption.frame = CGRectMake(0, side - 23, side, 14);
    _caption.hidden = !HPSettings.shared.showCaptions;
    [self place];
}
- (void)place
{
    CGFloat half = self.bounds.size.width / 2, travel = half - _thumb.bounds.size.width / 2 - 3;
    _thumb.center = CGPointMake(half + _x * travel, half - _y * travel);
    BOOL held = _activeTouch != nil;
    _thumb.backgroundColor = held ? [UIColor colorWithRed:0.60 green:0.85 blue:1 alpha:0.9] : [UIColor colorWithWhite:1 alpha:0.45];
    if (!self.editing) {
        self.layer.borderColor = held ? [UIColor colorWithRed:0.60 green:0.85 blue:1 alpha:0.8].CGColor : [UIColor colorWithWhite:1 alpha:0.3].CGColor;
        self.layer.borderWidth = held ? 2 : 1.5;
    }
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
    if (self.editing) return [super pointInside:point withEvent:event];
    /* The invisible corners of a square stick view must not steal an adjacent
       look swipe. Once a finger owns a stick, UIKit keeps its outside drags. */
    CGFloat radius = fmin(self.bounds.size.width, self.bounds.size.height) / 2;
    return hypot(point.x - CGRectGetMidX(self.bounds), point.y - CGRectGetMidY(self.bounds)) <= radius;
}
- (void)reset { _activeTouch = nil; _x = _y = 0; [self place]; if (self.valueChanged) self.valueChanged(0, 0); }
- (void)track:(UITouch *)t
{
    [self trackPoint:[t locationInView:self]];
}
- (void)trackPoint:(CGPoint)p
{
    /* Match input travel to the visible thumb, so it stays under the finger until
       reaching the rim. Normalizing by the entire base radius made it lag behind. */
    CGFloat side = fmin(self.bounds.size.width, self.bounds.size.height);
    CGFloat r = fmax(1, side * (1 - 0.42) / 2 - 3);
    CGFloat dx = (p.x - CGRectGetMidX(self.bounds)) / r, dy = (p.y - CGRectGetMidY(self.bounds)) / r, l = hypot(dx, dy);
    if (l > 1) { dx /= l; dy /= l; }
    _x = (float)dx; _y = (float)-dy;                    /* +y up, as SunPad */
    [self place];
    if (self.valueChanged) self.valueChanged(_x, _y);
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    trace_touches(self, touches, "began");
    if (self.editing || _activeTouch) return;
    _activeTouch = touches.anyObject;
    if (_activeTouch) [self track:_activeTouch];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    trace_touches(self, touches, "moved");
    /* A menu/lifecycle reset revokes ownership. Late callbacks from that finger
       must not restart movement or disturb a new finger's hold. */
    if (!self.editing && _activeTouch && [touches containsObject:_activeTouch]) [self track:_activeTouch];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    trace_touches(self, touches, "ended");
    if (_activeTouch && [touches containsObject:_activeTouch]) [self reset];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    trace_touches(self, touches, "cancelled");
    if (_activeTouch && [touches containsObject:_activeTouch]) [self reset];
}
@end

/* A Halo action, resolved against current bindings and held while touched; a translucent glass circle with an
   SF Symbol and a small caption. Fire and grenade also look while the finger moves, as a mobile
   shooter's fire button does. */
@interface HPControlButton : UIView
@property(nonatomic) int action; /* original CE action, -1 for Escape/Back */
@property(nonatomic) BOOL looks, held, primary;
@property(nonatomic) BOOL bindingAvailable;
@property(nonatomic, copy) void (^bindingHelp)(void);
@property(nonatomic, strong) UILabel *label;
@property(nonatomic, strong) UILabel *controllerLabel;
@property(nonatomic, copy) NSString *controllerHint;
@property(nonatomic, strong) UIImageView *icon;
@property(nonatomic, copy) void (^lookBy)(CGFloat dx, CGFloat dy);
@property(nonatomic, copy) void (^actionChanged)(int action, int down);
@property(nonatomic) BOOL editing;
- (void)release_;
- (void)press:(int)down;
- (void)setSymbol:(NSString *)name;
@end

@implementation HPControlButton {
    HPLookDrag *_drag;
    UIImageView *_bindingBadge;
}
- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = NO;
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        _bindingAvailable = YES;
        self.clipsToBounds = YES;
        self.layer.borderWidth = 1.5;
        _drag = [HPLookDrag new];
        __weak HPControlButton *weak = self;
        _drag.delta = ^(CGFloat dx, CGFloat dy) { if (weak.lookBy) weak.lookBy(dx, dy); };
        _icon = [UIImageView new];
        _icon.contentMode = UIViewContentModeScaleAspectFit;
        _icon.tintColor = [UIColor colorWithWhite:1 alpha:0.95];
        _icon.layer.shadowColor = UIColor.blackColor.CGColor;
        _icon.layer.shadowOpacity = 0.55; _icon.layer.shadowRadius = 1.5; _icon.layer.shadowOffset = CGSizeMake(0, 1);
        [self addSubview:_icon];
        _label = [UILabel new];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.textColor = [UIColor colorWithWhite:1 alpha:0.86];
        _label.layer.shadowColor = UIColor.blackColor.CGColor;
        _label.layer.shadowOpacity = 0.7; _label.layer.shadowRadius = 1; _label.layer.shadowOffset = CGSizeMake(0, 1);
        _label.adjustsFontSizeToFitWidth = YES;
        _label.minimumScaleFactor = 0.6;
        [self addSubview:_label];
        _controllerLabel = [UILabel new];
        _controllerLabel.textAlignment = NSTextAlignmentCenter;
        _controllerLabel.textColor = UIColor.whiteColor;
        _controllerLabel.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.9];
        _controllerLabel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.6].CGColor;
        _controllerLabel.layer.borderWidth = 1;
        _controllerLabel.clipsToBounds = YES;
        _controllerLabel.hidden = YES;
        [self addSubview:_controllerLabel];
        _bindingBadge = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.circle.fill"]];
        _bindingBadge.tintColor = UIColor.systemYellowColor;
        _bindingBadge.backgroundColor = UIColor.blackColor;
        _bindingBadge.layer.cornerRadius = 7;
        _bindingBadge.hidden = YES;
        [self addSubview:_bindingBadge];
        [self paint];
    }
    return self;
}
- (void)setSymbol:(NSString *)name { _icon.image = [UIImage systemImageNamed:name]; [self setNeedsLayout]; }
- (void)setBindingAvailable:(BOOL)available
{
    _bindingAvailable = available;
    _bindingBadge.hidden = available;
    self.accessibilityValue = available ? nil : @"Needs a keyboard or mouse binding";
    self.accessibilityHint = available ? self.controllerHint : @"Pause, Change Settings, Controls Setup";
}
- (void)setPrimary:(BOOL)primary { _primary = primary; [self paint]; }
/* Quiet at rest; the larger FIRE target uses Halo's cool HUD palette. */
- (void)paint
{
    UIColor *rest = self.primary ? [UIColor colorWithRed:0.12 green:0.32 blue:0.43 alpha:0.55] : [UIColor colorWithWhite:0.05 alpha:0.42];
    UIColor *held = self.primary ? [UIColor colorWithRed:0.38 green:0.72 blue:0.88 alpha:0.75] : [UIColor colorWithWhite:1 alpha:0.30];
    self.backgroundColor = self.held ? held : rest;
    if (!self.editing) self.layer.borderColor = [UIColor colorWithWhite:1 alpha:self.held ? 0.8 : 0.32].CGColor;
}
- (void)layoutSubviews
{
    [super layoutSubviews];
    CGFloat d = fmin(self.bounds.size.width, self.bounds.size.height);
    self.layer.cornerRadius = d / 2;
    BOOL caption = self.label.text.length && d >= 44 && HPSettings.shared.showCaptions;
    CGFloat iconSide = d * (caption ? 0.40 : 0.50);
    _icon.frame = CGRectMake((self.bounds.size.width - iconSide) / 2, self.bounds.size.height / 2 - iconSide / 2 - (caption ? d * 0.08 : 0), iconSide, iconSide);
    _icon.preferredSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:iconSide * 0.8 weight:UIImageSymbolWeightSemibold];
    _bindingBadge.frame = CGRectMake(d * 0.68 - 7, d * 0.22 - 7, 14, 14);
    CGFloat badgeSide = fmax(14, d * 0.26);
    _controllerLabel.frame = CGRectMake(d * 0.28 - badgeSide / 2, d * 0.23 - badgeSide / 2, badgeSide, badgeSide);
    _controllerLabel.font = [UIFont systemFontOfSize:badgeSide * 0.72 weight:UIFontWeightBold];
    _controllerLabel.layer.cornerRadius = badgeSide / 2;
    _label.hidden = !caption;
    _label.font = [UIFont systemFontOfSize:fmax(10, d * 0.15) weight:UIFontWeightSemibold];
    _label.frame = CGRectMake(d * 0.12, CGRectGetMaxY(_icon.frame) + d * 0.02, self.bounds.size.width - d * 0.24, d * 0.2);
}
- (void)press:(int)down
{
    if (down == self.held) return;
    self.held = down;
    if (down && !self.bindingAvailable && self.bindingHelp) self.bindingHelp();
    /* Still deliver both edges: this snapshot may lag a remap, and release
       must reach the runtime's press-time owner even if availability changed. */
    if (self.actionChanged) self.actionChanged(self.action, down);
    self.transform = down ? CGAffineTransformMakeScale(0.92, 0.92) : CGAffineTransformIdentity;
    [self paint];
}
- (void)release_ { [_drag clear]; [self press:0]; }
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    trace_touches(self, touches, "began");
    if (self.editing) return;
    [self press:1];
    UITouch *t = touches.anyObject;
    if (self.looks) [_drag begin:t at:[t locationInView:self.superview]];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    if (self.editing || !self.looks || !self.lookBy) return;
    trace_touches(self, touches, "moved");
    UITouch *t = touches.anyObject;
    [_drag move:t to:[t locationInView:self.superview]];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    trace_touches(self, touches, "ended");
    UITouch *t = touches.anyObject;
    [_drag end:t at:[t locationInView:self.superview] cancelled:self.editing];
    [self release_];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { trace_touches(self, touches, "cancelled"); [self release_]; }
@end

/* Halo's PC bindings. Layout gives the sticks their own space and places actions in
   rows above/beside them. Size 0 is a utility, 1 an action, 2 the fire target. */
typedef struct {
    const char *ident, *caption, *symbol;
    int action;
    int looks, size;
} hp_control_def;

static const hp_control_def CONTROLS[] = {
    {"fire",      "FIRE",    "scope",                           7, 1, 2},
    {"action",    "USE",     "hand.tap.fill",                   2, 0, 1},
    {"switch",    "SWAP",    "arrow.left.arrow.right",          3, 0, 1},
    {"zoom",      "ZOOM",    "plus.magnifyingglass",           11, 0, 1},
    {"grenade",   "THROW",   "flame.fill",                      6, 1, 1},
    {"melee",     "MELEE",   "hand.raised.fill",                4, 0, 1},
    {"reload",    "RELOAD",  "arrow.clockwise",                13, 0, 1},
    {"crouch",    "CROUCH",  "arrow.down.to.line",             10, 0, 1},
    {"jump",      "JUMP",    "arrow.up",                        0, 0, 1},
    {"flash",     "LIGHT",   "flashlight.on.fill",              5, 0, 1},
    {"nadetype",  "NADE",    "arrow.triangle.2.circlepath",     1, 0, 1},
    {"scores",    "",        "list.number",                    12, 0, 0},
    {"menu",      "",        "pause.fill",                     -1, 0, 0},
};
#define NCONTROLS (int)(sizeof CONTROLS / sizeof CONTROLS[0])

/* The three-dot button. On iOS 26 a button's menu grows out of the button and
   shrinks back into it. A custom button styled through its layer (background,
   cornerRadius, border) gives that animation no shape to return to: after
   tapping elsewhere it showed an empty square outline and the dots vanished
   for seconds (the same bug SunPad has). A UIButtonConfiguration describes
   the round shape, icon and colors to UIKit itself, so the menu animates back
   into the same circle. Keyboard focus, whose ring was another square, is off;
   the pointer highlight is round. */
@interface HPMenuButton : UIButton
@end
@implementation HPMenuButton
+ (instancetype)menuButton
{
    UIButtonConfiguration *c = [UIButtonConfiguration filledButtonConfiguration];
    c.image = [UIImage systemImageNamed:@"ellipsis" withConfiguration:
        [UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightBold]];
    c.baseForegroundColor = UIColor.whiteColor;
    c.baseBackgroundColor = [UIColor colorWithWhite:0.06 alpha:0.72];
    c.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    c.background.strokeColor = [UIColor colorWithWhite:1 alpha:0.3];
    c.background.strokeWidth = 1;
    c.contentInsets = NSDirectionalEdgeInsetsZero;
    HPMenuButton *b = [self buttonWithConfiguration:c primaryAction:nil];
    b.showsMenuAsPrimaryAction = YES;
    b.changesSelectionAsPrimaryAction = NO;
    b.focusEffect = nil;
    b.pointerInteractionEnabled = YES;
    b.pointerStyleProvider = ^UIPointerStyle *(UIButton *button, UIPointerEffect *effect, UIPointerShape *shape) {
        return [UIPointerStyle styleWithEffect:[UIPointerLiftEffect effectWithPreview:[[UITargetedPreview alloc] initWithView:button]]
                                         shape:[UIPointerShape shapeWithPath:[UIBezierPath bezierPathWithOvalInRect:button.bounds]]];
    };
    return b;
}
- (BOOL)canBecomeFocused { return NO; }
@end

@interface HPOverlay () <UIGestureRecognizerDelegate>
- (void)postInput:(const hp_input *)event;
@end

@implementation HPOverlay {
    UIButton *_menuButton;
    HPStickView *_move, *_aim;
    CADisplayLink *_aimClock;
    float _aimX, _aimY;
    NSMutableArray<HPControlButton *> *_buttons;
    NSMutableArray<UIGestureRecognizer *> *_editGestures;
    UILabel *_fps, *_bindingHint;
    NSUInteger _bindingHintGeneration;
    UIView *_panel, *_editorBar;
    UISlider *_opacity, *_size, *_look, *_selectedSize;
    UISwitch *_hideSwitch, *_editSwitch, *_leftSwitch, *_captionSwitch;
    UISegmentedControl *_spacingControl;
    UILabel *_editorHint;
    __weak UIView *_selected;
    BOOL _editing, _controllerHidden;
    int _wasd[4];                                   /* W A S D held */
    double _lookRestX, _lookRestY;
    HPLookDrag *_lookDrag;
    void (^_inputHandler)(const hp_input *event);
    BOOL _inputInactive;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    return [self initWithFrame:frame inputHandler:nil];
}
- (instancetype)initWithFrame:(CGRect)frame inputHandler:(void (^)(const hp_input *event))handler
{
    if ((self = [super initWithFrame:frame])) {
        _inputHandler = [handler copy];
        _engineMenuItems = @[];
        self.multipleTouchEnabled = YES;
        _availableActions = (1u << 29) - 1;
        _lookDrag = [HPLookDrag new];
        __weak HPOverlay *weak = self;
        _lookDrag.delta = ^(CGFloat dx, CGFloat dy) { [weak lookX:dx y:dy]; };
        [self buildControls];
        [self buildMenuButton];
        [self buildPanel];
        [self buildEditorBar];
        _fps = [UILabel new];
        _fps.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
        _fps.textColor = UIColor.greenColor;
        _fps.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        _fps.textAlignment = NSTextAlignmentCenter;
        _fps.hidden = YES;
        _fps.userInteractionEnabled = NO;
        [self addSubview:_fps];
        _bindingHint = [UILabel new];
        _bindingHint.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        _bindingHint.textColor = UIColor.whiteColor;
        _bindingHint.backgroundColor = [UIColor colorWithWhite:0.04 alpha:0.92];
        _bindingHint.numberOfLines = 0;
        _bindingHint.textAlignment = NSTextAlignmentCenter;
        _bindingHint.layer.cornerRadius = 10;
        _bindingHint.clipsToBounds = YES;
        _bindingHint.userInteractionEnabled = NO;
        _bindingHint.hidden = YES;
        [self addSubview:_bindingHint];
        for (NSString *n in @[GCControllerDidConnectNotification, GCControllerDidDisconnectNotification])
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refreshControllerVisibility) name:n object:nil];
        if (_inputHandler) {
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(inputWillResign:)
                name:UIApplicationWillResignActiveNotification object:nil];
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(inputDidBecomeActive:)
                name:UIApplicationDidBecomeActiveNotification object:nil];
        }
        [self refreshControllerVisibility];
    }
    return self;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)postInput:(const hp_input *)event
{
    if (_inputInactive && event->kind != HPI_CANCEL_TOUCH) return;
    if (_inputHandler) _inputHandler(event);
    else halopad_host_post_input(event);
}
- (void)inputWillResign:(NSNotification *)note { [self clearTouchInput]; _inputInactive = YES; }
- (void)inputDidBecomeActive:(NSNotification *)note { [self clearTouchInput]; _inputInactive = NO; }
- (void)setEngineMenuItems:(NSArray<UIMenuElement *> *)items
{
    _engineMenuItems = [items copy];
    [self rebuildMenu];
}

/* Delegate-provided items (custom maps, Switch Edition) appear as soon as it is set. */
- (void)setDelegate:(id<HPOverlayDelegate>)delegate
{
    _delegate = delegate;
    if (_menuButton) [self rebuildMenu];
}
- (void)setControllerLabel:(NSString *)label hint:(NSString *)hint forControl:(NSString *)identifier
{
    for (HPControlButton *button in _buttons) {
        if (![button.accessibilityIdentifier isEqualToString:identifier]) continue;
        button.controllerLabel.text = label;
        button.controllerLabel.hidden = !label.length;
        button.controllerHint = hint;
        if (button.bindingAvailable) button.accessibilityHint = hint;
        [button setNeedsLayout];
        break;
    }
}

- (void)setScoreboardScroll:(void (^)(CGFloat))handler
{
    [self clearTouchInput];
    _scoreboardScroll = [handler copy];
    for (HPControlButton *button in _buttons)
        if (button.action == 12) button.looks = handler != nil;
}

/* ---- the controls ---- */

- (void)buildControls
{
    _buttons = [NSMutableArray array];
    _editGestures = [NSMutableArray array];
    _move = [HPStickView new];
    _move.accessibilityIdentifier = @"move";
    _move.accessibilityLabel = @"Move";
    __weak HPOverlay *weak = self;
    _move.valueChanged = ^(float x, float y) { [weak moveX:x y:y]; };
    [self addSubview:_move];
    [self addEditGestures:_move];
    _move.caption.text = @"MOVE";
    _aim = [HPStickView new];
    _aim.accessibilityIdentifier = @"aim";
    _aim.accessibilityLabel = @"Look";
    _aim.caption.text = @"LOOK";
    _aim.valueChanged = ^(float x, float y) { [weak aimX:x y:y]; };
    [self addSubview:_aim];
    [self addEditGestures:_aim];
    for (int i = 0; i < NCONTROLS; i++) {
        const hp_control_def *d = &CONTROLS[i];
        HPControlButton *b = [HPControlButton new];
        b.action = d->action; b.looks = d->looks;
        b.label.text = @(d->caption);
        [b setSymbol:@(d->symbol)];
        b.primary = d->size == 2;
        b.accessibilityIdentifier = @(d->ident);
        b.accessibilityLabel = strlen(d->caption) ? @(d->caption).capitalizedString :
            (strcmp(d->ident, "menu") == 0 ? @"Pause" : @"Scoreboard");
        NSString *name = b.accessibilityLabel;
        b.bindingHelp = ^{ [weak showBindingHelp:name]; };
        if (d->action == 12) {
            b.lookBy = ^(CGFloat dx, CGFloat dy) {
                HPOverlay *owner = weak;
                if (owner && !owner->_inputInactive && owner.scoreboardScroll && isfinite(dy))
                    owner.scoreboardScroll(dy);
            };
        } else b.lookBy = ^(CGFloat dx, CGFloat dy) { [weak lookX:dx y:dy]; };
        b.actionChanged = ^(int action, int down) {
            hp_input event = {.kind = action < 0 ? HPI_KEY : HPI_ACTION, .flags = HPI_TOUCH,
                .action = (uint32_t)action, .down = down, .vk = 0x1b, .side_vk = 0x1b, .scan = 0x01};
            [weak postInput:&event];
        };
        [_buttons addObject:b];
        [self addSubview:b];
        [self addEditGestures:b];
    }
}

- (void)showBindingHelp:(NSString *)name
{
    _bindingHint.text = [NSString stringWithFormat:@"%@ needs a keyboard or mouse binding.\nPause → Change Settings → Controls Setup", name];
    _bindingHint.hidden = NO;
    [self setNeedsLayout];
    NSUInteger generation = ++_bindingHintGeneration;
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, _bindingHint.text);
    __weak HPOverlay *weak = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        HPOverlay *strong = weak;
        if (strong && strong->_bindingHintGeneration == generation) strong->_bindingHint.hidden = YES;
    });
}
- (void)setAvailableActions:(uint32_t)mask
{
    if (_availableActions == mask) return;
    _availableActions = mask;
    _bindingHint.hidden = YES; ++_bindingHintGeneration;
    for (HPControlButton *b in _buttons)
        b.bindingAvailable = b.action < 0 || (mask & (1u << b.action));
    [self updateMoveBindingHint];
}
- (void)updateMoveBindingHint
{
    uint32_t movement = 15u << 19;
    BOOL available = self.analogMoveReady || (self.availableActions & movement) == movement;
    _move.caption.text = available ? @"MOVE" : @"MOVE !";
    _move.accessibilityValue = available ? nil : @"One or more directions need a keyboard or mouse binding";
}

/* Digital fallback follows the player's movement bindings, with hysteresis. */
- (void)moveX:(float)x y:(float)y
{
    if (_editing) return;
    if (self.analogMoveReady) {
        hp_input event = {.kind = HPI_TOUCH_MOVE, .flags = HPI_TOUCH, .move_x = x, .move_y = y};
        [self postInput:&event];
        return;
    }
    static const uint32_t actions[4] = {19, 21, 20, 22};
    float v[4] = {y, -x, -y, x};
    for (int i = 0; i < 4; i++) {
        int want = _wasd[i] ? v[i] > 0.25f : v[i] > 0.38f;
        if (want != _wasd[i]) {
            _wasd[i] = want;
            if (want && !(self.availableActions & (1u << actions[i]))) {
                static NSString * const names[] = {@"Forward", @"Left", @"Backward", @"Right"};
                [self showBindingHelp:names[i]];
            }
            hp_input event = {.kind = HPI_ACTION, .flags = HPI_TOUCH, .action = actions[i], .down = want};
            [self postInput:&event];
        }
    }
}
- (void)setAnalogMoveReady:(BOOL)ready
{
    if (_analogMoveReady == ready) return;
    [self clearTouchInput]; /* release the old source before switching ownership */
    _analogMoveReady = ready;
    [self updateMoveBindingHint];
}
/* looking: points dragged as mouse counts (DirectInput), fractions kept */
- (void)lookX:(CGFloat)dx y:(CGFloat)dy
{
    double s = 2.2 * HPSettings.shared.lookSensitivity;
    _lookRestX += dx * s; _lookRestY += dy * s;
    int32_t ix = (int32_t)_lookRestX, iy = (int32_t)_lookRestY;
    _lookRestX -= ix; _lookRestY -= iy;
    if (ix || iy) {
        hp_input event = {.kind = HPI_MOUSEMOVE, .flags = HPI_TOUCH, .x = 400, .y = 300, .dx = ix, .dy = iy};
        [self postInput:&event];
    }
}
- (void)clearTouchInput
{
    if (getenv("HALOPAD_TRACE_TOUCH")) fprintf(stderr, "HALOPAD TOUCH: clear input\n");
    _bindingHint.hidden = YES; ++_bindingHintGeneration;
    for (HPControlButton *b in _buttons) [b release_];
    [_move reset];
    [_aim reset];
    [_lookDrag clear];
    _lookRestX = _lookRestY = 0;
    hp_input cancel = {.kind = HPI_CANCEL_TOUCH};
    [self postInput:&cancel];
}

- (BOOL)driveControl:(NSString *)identifier down:(BOOL)down
{
    for (HPControlButton *b in _buttons)
        if ([b.accessibilityIdentifier isEqualToString:identifier]) { [b press:down]; return YES; }
    return NO;
}
- (void)driveMoveX:(float)x y:(float)y { if (_move.valueChanged) _move.valueChanged(x, y); }
- (void)driveLookX:(CGFloat)dx y:(CGFloat)dy { [self lookX:dx y:dy]; }

/* The fixed sticks own their touches independently. Swiping open screen or dragging
   FIRE can still aim, so the right thumb can shoot and turn without leaving FIRE. */
- (void)aimX:(float)x y:(float)y
{
    if (_editing) return;
    _aimX = x; _aimY = y;
    if (hypotf(x, y) <= 0.12f) {
        [_aimClock invalidate]; _aimClock = nil;
    } else if (!_aimClock) {
        _aimClock = [CADisplayLink displayLinkWithTarget:self selector:@selector(aimTick:)];
        [_aimClock addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}
- (void)aimTick:(CADisplayLink *)clock
{
    float magnitude = hypotf(_aimX, _aimY);
    if (magnitude <= 0.12f) return;
    /* Radial dead zone, gentle near-centre aim, speed independent of refresh rate. */
    double response = pow(fmin(1, (magnitude - 0.12) / 0.88), 1.5);
    /* Keep turning speed proportional to real time when the phone falls below 20 FPS.
       Bound long app stalls so one resumed frame cannot swing the view wildly. */
    double dt = fmin(0.2, fmax(0, clock.targetTimestamp - clock.timestamp));
    double speed = 250 * response * dt / magnitude;
    [self lookX:_aimX * speed y:-_aimY * speed];
}
- (void)driveAimX:(float)x y:(float)y { if (_aim.valueChanged) _aim.valueChanged(x, y); }

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *hit = [super hitTest:point withEvent:event];
    if (!_panel.hidden && hit && hit != _menuButton && ![hit isDescendantOfView:_menuButton] &&
        hit != _panel && ![hit isDescendantOfView:_panel]) return self;
    if (hit != self) return hit;
    return self.inGame && !self.controlsHidden && !_editing ? self : nil;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    if (!_panel.hidden) return;
    trace_touches(self, touches, "began");
    for (UITouch *t in touches) [_lookDrag begin:t at:[t locationInView:self]];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    trace_touches(self, touches, "moved");
    for (UITouch *t in touches) {
        [_lookDrag move:t to:[t locationInView:self]];
    }
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    trace_touches(self, touches, "ended");
    for (UITouch *t in touches) [_lookDrag end:t at:[t locationInView:self] cancelled:NO];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    trace_touches(self, touches, "cancelled");
    for (UITouch *t in touches) [_lookDrag end:t at:CGPointZero cancelled:YES];
}

- (BOOL)controlsHidden { return TARGET_OS_MACCATALYST || HPSettings.shared.hideTouchControls || _controllerHidden || _softwareKeyboardVisible || _haloMenuVisible; }
- (void)setSoftwareKeyboardVisible:(BOOL)visible
{
    if (_softwareKeyboardVisible == visible) return;
    _softwareKeyboardVisible = visible;
    if (visible) [self clearTouchInput];
    [self updateAppearance];
}
- (void)setHaloMenuVisible:(BOOL)visible
{
    if (_haloMenuVisible == visible) return;
    _haloMenuVisible = visible;
    if (visible) [self clearTouchInput];
    [self updateAppearance];
}
- (void)setInGame:(BOOL)inGame
{
    if (_inGame == inGame) return;
    _inGame = inGame;
    if (!inGame) [self clearTouchInput];
    [self rebuildMenu];
    [self updateAppearance];
}

- (void)refreshControllerVisibility
{
    extern int halopad_app_controller_ready(void);
    BOOL connected = NO;
    if (self.controllerConnected) connected = self.controllerConnected();
#if !TARGET_OS_SIMULATOR
    else if (halopad_app_controller_ready())
        for (GCController *c in GCController.controllers) if (c.extendedGamepad) connected = YES;
#endif
    BOOL hidden = connected && HPSettings.shared.hideWithController;
    BOOL changed = hidden != _controllerHidden;
    _controllerHidden = hidden;
    if (connected) [self clearTouchInput];
    [self updateAppearance];
    if (changed) [self rebuildMenu];    /* Show Touch Controls appears only while needed */
}

/* The reliable recovery from both kinds of hiding. A connected controller would otherwise keep
   suppressing the controls the player just asked for, so auto-hide stays off until the player
   turns it back on. The keyboard and Halo's menus still hide them temporarily. */
- (void)showTouchControls
{
    HPSettings.shared.hideTouchControls = NO;
    HPSettings.shared.hideWithController = NO;
    _controllerHidden = NO;
    [self updateAppearance];
    [self rebuildMenu];
}

- (void)setFramesPerSecond:(int)fps
{
    _fps.hidden = fps < 0 || !HPSettings.shared.showFPS;
    _fps.text = [NSString stringWithFormat:@"%d FPS", fps];
}

/* ---- layout: point-sized targets constrained together to the safe area, with
   separate saved phone/tablet positions and sizes ---- */

- (BOOL)phone { return self.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPhone; }
- (NSString *)key:(NSString *)what { return [NSString stringWithFormat:@"HaloPad.%@.v3.%@", self.phone ? @"phone" : @"tablet", what]; }
- (CGRect)safe { return UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets); }

- (void)place:(UIView *)v frame:(CGRect)f
{
    NSString *ident = v.accessibilityIdentifier;
    NSNumber *scale = [NSUserDefaults.standardUserDefaults dictionaryForKey:[self key:@"scales"]][ident];
    CGFloat s = scale ? scale.doubleValue : 1;
    v.bounds = CGRectMake(0, 0, fmax(44, f.size.width * s), fmax(44, f.size.height * s));
    NSString *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:[self key:@"origins"]][ident];
    CGRect safe = self.safe;
    CGPoint c = CGPointMake(CGRectGetMidX(f), CGRectGetMidY(f));
    if (saved) {
        CGPoint n = CGPointFromString(saved);
        c = CGPointMake(CGRectGetMinX(safe) + fmin(1, fmax(0, n.x)) * safe.size.width, CGRectGetMinY(safe) + fmin(1, fmax(0, n.y)) * safe.size.height);
    }
    CGFloat hw = v.bounds.size.width / 2, hh = v.bounds.size.height / 2;
    c.x = fmin(fmax(c.x, CGRectGetMinX(safe) + hw), CGRectGetMaxX(safe) - hw);
    c.y = fmin(fmax(c.y, CGRectGetMinY(safe) + hh), CGRectGetMaxY(safe) - hh);
    v.center = c;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    CGRect safe = self.safe;
    BOOL pad = !self.phone && safe.size.width >= 1000;
    /* Bound the whole arrangement before placing individual controls. Clamping each
       circle against an edge was what collapsed the old ring at larger sizes. */
    CGFloat k = fmin((pad ? 1.10 : 1) * HPSettings.shared.controlSize,
                     fmin(safe.size.width / 760, (safe.size.height - 68) / 260));
    k = fmax(0.65, k);
    CGFloat stick = fmax(100, 144 * k), action = fmax(44, 52 * k);
    CGFloat utility = fmax(44, 44 * k), fire = fmax(60, 72 * k);
    CGFloat gaps[] = {8, 12, 18};
    CGFloat gap = fmax(8, gaps[HPSettings.shared.ringSpacing] * k);
    /* Thumb reach is measured in points, not a fraction of the display width.
       Keep both sticks on one baseline and leave identical space around them. */
    CGFloat inset = fmin(160 - stick / 2, fmax(16, (self.phone ? 20 : 36) * k));
    CGFloat left = CGRectGetMinX(safe) + inset;
    CGFloat right = CGRectGetMaxX(safe) - inset;
    /* Tablet thumbs rest along the sides, above the bottom-left motion tracker.
       A phone's shorter display needs the lower grip instead. */
    CGFloat pitch = action + gap;
    CGFloat rowOverhang = fmax(0, pitch + action / 2 - stick / 2);
    CGFloat bottom = CGRectGetMaxY(safe) - (self.phone ? fmax(20, 32 * k) : fmax(160, 128 * k)) - rowOverhang;
    /* Small actions share one compact pitch. FIRE has its own clearance above
       LOOK, so its larger diameter does not inflate every small-button gap. */
    /* Center each action column on its thumb. The old half-row offset put the
       middle actions above the thumb and left uneven space below both clusters. */
    CGFloat midY = bottom - stick / 2;
    CGFloat lowY = midY + pitch, rowY = midY - pitch;
    CGFloat nearX = right - stick - gap - action / 2;
    CGFloat farX = nearX - pitch;
    CGFloat fireX = right - stick / 2;
    CGFloat fireY = bottom - stick - gap - fire / 2;
    CGFloat throwY = fireY;
    CGFloat leftInnerX = left + stick + gap + action / 2;
    BOOL mirror = HPSettings.shared.leftHanded;
    CGFloat (^mx)(CGFloat) = ^CGFloat(CGFloat x) { return mirror ? CGRectGetMinX(safe) + CGRectGetMaxX(safe) - x : x; };
    [self place:_move frame:CGRectMake(mx(left + stick / 2) - stick / 2, bottom - stick, stick, stick)];
    [self place:_aim frame:CGRectMake(mx(right - stick / 2) - stick / 2, bottom - stick, stick, stick)];
    CGPoint points[NCONTROLS] = {
        {fireX, fireY}, {farX, midY}, {farX, lowY}, {farX, rowY},
        {left + stick / 2, throwY}, {nearX, midY}, {nearX, rowY},
        {leftInnerX, lowY}, {nearX, lowY},
        {leftInnerX, midY},
        {leftInnerX, rowY},
        {CGRectGetMidX(safe) - utility / 2 - 6, CGRectGetMinY(safe) + utility / 2 + 12},
        {CGRectGetMidX(safe) + utility / 2 + 6, CGRectGetMinY(safe) + utility / 2 + 12},
    };
    for (int i = 0; i < NCONTROLS; i++) {
        CGFloat dia = CONTROLS[i].size == 2 ? fire : CONTROLS[i].size == 1 ? action : utility;
        CGPoint c = points[i];
        if (i < NCONTROLS - 2) c.x = mx(c.x);
        [self place:_buttons[i] frame:CGRectMake(c.x - dia / 2, c.y - dia / 2, dia, dia)];
        [_buttons[i] setNeedsLayout];
    }
    CGFloat side = 44; inset = 12;
    _menuButton.frame = CGRectMake(CGRectGetMaxX(safe) - side - inset, CGRectGetMinY(safe) + inset, side, side);
    _fps.frame = CGRectMake(CGRectGetMaxX(safe) - side - inset - 86, CGRectGetMinY(safe) + inset + 8, 76, 24);
    CGFloat hintWidth = fmin(440, safe.size.width - 32);
    CGSize hintSize = [_bindingHint sizeThatFits:CGSizeMake(hintWidth - 24, CGFLOAT_MAX)];
    _bindingHint.frame = CGRectMake(CGRectGetMidX(safe) - hintWidth / 2,
                                   CGRectGetMinY(safe) + 72, hintWidth, fmax(64, hintSize.height + 20));
    _fps.layer.cornerRadius = 6; _fps.layer.masksToBounds = YES;
    CGFloat pw = fmin(360, safe.size.width - 32), ph = fmin(560, fmax(0, safe.size.height - 72));
    _panel.frame = CGRectMake(CGRectGetMaxX(safe) - pw - 12, CGRectGetMinY(safe) + 60, pw, ph);
    CGFloat ew = fmin(560, safe.size.width - 24);
    _editorBar.frame = CGRectMake(CGRectGetMidX(safe) - ew / 2, CGRectGetMaxY(safe) - 72, ew, 60);
    [self updateAppearance];
    [self bringSubviewToFront:_panel];
    [self bringSubviewToFront:_editorBar];
    [self bringSubviewToFront:_menuButton];
}

- (void)updateAppearance
{
    BOOL show = !_softwareKeyboardVisible && (_editing || (self.inGame && !self.controlsHidden));
    CGFloat alpha = HPSettings.shared.controlOpacity;
    NSMutableArray<UIView *> *all = [NSMutableArray arrayWithArray:_buttons];
    [all addObjectsFromArray:@[_move, _aim]];
    for (UIView *v in all) {
        v.hidden = !show;
        BOOL picked = _editing && v == _selected;
        v.alpha = [v isKindOfClass:HPStickView.class] && !_editing ? alpha * 0.75 : alpha;
        if ([v isKindOfClass:HPStickView.class]) ((HPStickView *)v).editing = _editing;
        [v setNeedsLayout];
        v.layer.borderWidth = picked ? 3 : 1.5;
        v.layer.borderColor = (picked ? UIColor.systemYellowColor : [UIColor colorWithWhite:1 alpha:0.32]).CGColor;
        if ([v isKindOfClass:HPControlButton.class]) {
            HPControlButton *button = (HPControlButton *)v;
            button.editing = _editing;
            if ([button.accessibilityIdentifier isEqualToString:@"menu"]) {
                /* Keep a touch route back/resume while gameplay touches pass to Halo. */
                button.hidden = !(show || (_haloMenuVisible && self.inGame && !_softwareKeyboardVisible));
                [button setSymbol:_haloMenuVisible ? @"chevron.backward" : @"pause.fill"];
                button.accessibilityLabel = _haloMenuVisible ? @"Back to game or previous menu" : @"Pause";
            }
        }
    }
}

/* ---- the three-dot menu ---- */

- (void)buildMenuButton
{
    _menuButton = [HPMenuButton menuButton];
    _menuButton.accessibilityLabel = @"Menu";
    _menuButton.accessibilityIdentifier = @"HaloPadMenu";
    [_menuButton addTarget:self action:@selector(clearTouchInput) forControlEvents:UIControlEventMenuActionTriggered];
    [self addSubview:_menuButton];
    [self rebuildMenu];
}

- (UIAction *)check:(NSString *)title on:(BOOL)on handler:(void (^)(void))h
{
    UIAction *a = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(__kindof UIAction *x) { h(); }];
    a.state = on ? UIMenuElementStateOn : UIMenuElementStateOff;
    return a;
}

static NSString * const HPRepositoryURL = @"https://github.com/chrissotraidis/projectreach";

/* The three-dot menu, grouped the way a player looks for things: play, controls,
   chat, display, maps, help. Everything Halo's own menus already do stays there.
   Both editions share this menu. Only what an edition cannot do differs: the Xbox
   game has no server browser, chat keyboard, console or 4:3 choice, and adds its
   own play items (System Link) through engineMenuItems. */
- (void)rebuildMenu
{
    __weak HPOverlay *weak = self;
    HPSettings *s = HPSettings.shared;
    UIImage *(^icon)(NSString *) = ^UIImage *(NSString *name) { return [UIImage systemImageNamed:name]; };
    BOOL pc = !_inputHandler;

    NSMutableArray<UIMenuElement *> *play = [NSMutableArray array];
    if (pc) {
        NSMutableArray<UIMenuElement *> *recent = [NSMutableArray array];
        for (NSString *addr in s.recentServers)
            [recent addObject:[UIAction actionWithTitle:addr image:nil identifier:nil handler:^(__kindof UIAction *a) { [weak joinServer:addr password:@""]; }]];
        if (!recent.count) {
            UIAction *none = [UIAction actionWithTitle:@"No Recent Servers" image:nil identifier:nil handler:^(__kindof UIAction *a) {}];
            none.attributes = UIMenuElementAttributesDisabled;
            [recent addObject:none];
        }
        [play addObject:[UIAction actionWithTitle:@"Join Server by Address…" image:icon(@"network") identifier:nil handler:^(__kindof UIAction *a) { [weak promptJoin]; }]];
        [play addObject:[UIMenu menuWithTitle:@"Recent Servers" image:icon(@"clock.arrow.circlepath") identifier:nil options:0 children:recent]];
    }
    [play addObjectsFromArray:self.engineMenuItems ?: @[]];
    if (pc && self.inGame) {
        UIAction *leave = [UIAction actionWithTitle:@"Open Leave Game Menu…" image:icon(@"rectangle.portrait.and.arrow.right") identifier:nil
                                            handler:^(__kindof UIAction *a) { [weak leaveGame]; }];
        [play addObject:leave];
    }

#if TARGET_OS_MACCATALYST
    /* a Mac has no touch controls: the mouse's speed (both editions) and the controller guide */
    NSMutableArray<UIMenuElement *> *speeds = [NSMutableArray array];
    for (NSNumber *speed in @[@0.5, @0.75, @1.0, @1.5, @2.0, @3.0]) {
        NSString *title = [NSString stringWithFormat:@"%g×%@", speed.doubleValue, speed.doubleValue == 1.0 ? @" (default)" : @""];
        [speeds addObject:[self check:title on:fabs(s.mouseSpeed - speed.doubleValue) < 0.01 handler:^{
            HPSettings.shared.mouseSpeed = speed.doubleValue; [weak rebuildMenu]; }]];
    }
    UIMenu *controls = [UIMenu menuWithTitle:@"Controls" image:icon(@"gamecontroller") identifier:nil options:0 children:@[
        [UIMenu menuWithTitle:@"Mouse Speed" image:icon(@"computermouse") identifier:nil options:0 children:speeds],
        [UIAction actionWithTitle:@"Controller Guide" image:icon(@"gamecontroller.fill") identifier:nil handler:^(__kindof UIAction *a) { [weak showControllerLayout]; }]]];
#else
    UIMenu *controls = [UIMenu menuWithTitle:@"Controls" image:icon(@"gamecontroller") identifier:nil options:0 children:@[
        [UIAction actionWithTitle:@"Look Speed & Touch Settings…" image:icon(@"slider.horizontal.3") identifier:nil handler:^(__kindof UIAction *a) { [weak togglePanel]; }],
        [UIAction actionWithTitle:@"Edit Touch Layout" image:icon(@"hand.draw") identifier:nil handler:^(__kindof UIAction *a) { [weak beginEditing]; }],
        [self check:@"Hide Touch Controls" on:s.hideTouchControls handler:^{
            /* Unhiding while a controller suppresses the controls must still show them. */
            HPOverlay *strong = weak;
            if (strong && HPSettings.shared.hideTouchControls && strong->_controllerHidden) { [strong showTouchControls]; return; }
            HPSettings.shared.hideTouchControls = !HPSettings.shared.hideTouchControls; [weak clearTouchInput]; [weak updateAppearance]; [weak rebuildMenu]; }],
        [self check:@"Hide Touch Controls with a Controller" on:s.hideWithController handler:^{
            HPSettings.shared.hideWithController = !HPSettings.shared.hideWithController; [weak refreshControllerVisibility]; [weak rebuildMenu]; }],
        [UIAction actionWithTitle:@"Controller Guide" image:icon(@"gamecontroller.fill") identifier:nil handler:^(__kindof UIAction *a) { [weak showControllerLayout]; }]]];
#endif

    UIMenu *chat = !pc ? nil : [UIMenu menuWithTitle:@"Keyboard & Chat" image:icon(@"keyboard") identifier:nil options:0 children:@[
        [UIAction actionWithTitle:@"All Chat" image:icon(@"bubble.left.and.bubble.right") identifier:nil
                          handler:^(__kindof UIAction *a) { [HPOverlay tapKey:'T' scan:0x14]; [weak.delegate overlayRequestsKeyboard:weak]; }],
        [UIAction actionWithTitle:@"Team Chat" image:icon(@"bubble.left") identifier:nil
                          handler:^(__kindof UIAction *a) { [HPOverlay tapKey:'Y' scan:0x15]; [weak.delegate overlayRequestsKeyboard:weak]; }],
        [UIAction actionWithTitle:@"Show Keyboard" image:icon(@"keyboard.chevron.compact.down") identifier:nil
                          handler:^(__kindof UIAction *a) { [weak.delegate overlayRequestsKeyboard:weak]; }],
        [UIAction actionWithTitle:@"Halo Console" image:icon(@"terminal") identifier:nil
                          handler:^(__kindof UIAction *a) { [HPOverlay tapKey:0xC0 scan:0x29]; [weak.delegate overlayRequestsKeyboard:weak]; }]]];

    NSMutableArray<UIMenuElement *> *displayItems = [NSMutableArray array];
    if (pc)
        [displayItems addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
            [self check:@"Original 4:3" on:s.aspect == HPAspectOriginal handler:^{ HPSettings.shared.aspect = HPAspectOriginal; [weak displayChanged]; }],
            [self check:@"Stretch to Fill" on:s.aspect == HPAspectFill handler:^{ HPSettings.shared.aspect = HPAspectFill; [weak displayChanged]; }]]]];
    [displayItems addObject:[self check:@"Show FPS Counter" on:s.showFPS handler:^{ HPSettings.shared.showFPS = !HPSettings.shared.showFPS; [weak displayChanged]; }]];
    UIMenu *display = [UIMenu menuWithTitle:@"Display" image:icon(@"display") identifier:nil options:0 children:displayItems];

    NSMutableArray<UIMenuElement *> *setup = [NSMutableArray arrayWithObject:controls];
    if (chat) [setup addObject:chat];
    [setup addObject:display];
    if ([self.delegate respondsToSelector:@selector(overlayRequestsCustomMaps:)])
        [setup addObject:[UIAction actionWithTitle:@"Add Custom Maps…" image:icon(@"map") identifier:nil
                                           handler:^(__kindof UIAction *a) { [weak.delegate overlayRequestsCustomMaps:weak]; }]];

    UIMenu *help = [UIMenu menuWithTitle:@"Help" image:icon(@"questionmark.circle") identifier:nil options:0 children:@[
        [UIAction actionWithTitle:@"Report a Problem…" image:icon(@"exclamationmark.bubble") identifier:nil handler:^(__kindof UIAction *a) { [weak report]; }],
        [UIAction actionWithTitle:@"Share Diagnostic Log…" image:icon(@"doc.text") identifier:nil handler:^(__kindof UIAction *a) { [weak shareLog]; }],
        [UIAction actionWithTitle:@"HaloPad on GitHub" image:icon(@"safari") identifier:nil handler:^(__kindof UIAction *a) {
            [UIApplication.sharedApplication openURL:[NSURL URLWithString:HPRepositoryURL] options:@{} completionHandler:nil]; }],
        [UIAction actionWithTitle:@"About HaloPad" image:icon(@"info.circle") identifier:nil handler:^(__kindof UIAction *a) { [weak showAbout]; }]]];
    NSMutableArray<UIMenuElement *> *last = [NSMutableArray arrayWithObject:help];
    if ([self.delegate respondsToSelector:@selector(overlayEditionSwitchNote:)] && [self.delegate overlayEditionSwitchNote:self])
        [last addObject:[UIAction actionWithTitle:@"Switch Edition…" image:icon(@"arrow.left.arrow.right") identifier:nil
                                          handler:^(__kindof UIAction *a) { [weak confirmEditionSwitch]; }]];

    NSMutableArray<UIMenuElement *> *groups = [NSMutableArray array];
#if !TARGET_OS_MACCATALYST
    if (s.hideTouchControls || _controllerHidden)
        [groups addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[
            [UIAction actionWithTitle:@"Show Touch Controls" image:icon(@"hand.tap") identifier:nil
                              handler:^(__kindof UIAction *a) { [weak showTouchControls]; }]]]];
#endif
    for (NSArray<UIMenuElement *> *group in @[play, setup, last])
        if (group.count)
            [groups addObject:[UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:group]];
    _menuButton.menu = [UIMenu menuWithTitle:@"HaloPad" children:groups];
}

/* iOS apps cannot relaunch themselves, and one engine owns the process's guest memory
   per launch. Settings are already stored; HaloPad closes and shows the edition picker
   when the player opens it again. */
- (void)confirmEditionSwitch
{
    [self clearTouchInput];
    NSString *note = [self.delegate overlayEditionSwitchNote:self] ?: @"";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Switch Edition"
        message:[note stringByAppendingString:@"\n\nHaloPad will close. Open it again to choose Windows or Xbox."]
        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Close HaloPad" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [HPOverlay closeForEditionSwitch];
    }]];
    [self.presenter presentViewController:a animated:YES completion:nil];
}

+ (void)closeForEditionSwitch
{
    HP_LOG("App: closing to switch edition (player request)");
    fflush(NULL);
    _exit(0);                                           /* no atexit teardown under a running engine */
}

- (void)displayChanged
{
    [self.delegate overlayDisplayChanged:self];
    [self rebuildMenu];
    [self setNeedsLayout];
}

/* The diagnostic log (Documents/HaloPad Logs, also in Files): controller, state,
   video and stall events only, for a bug report. */
- (void)shareLog
{
    if (![self.delegate respondsToSelector:@selector(overlayDiagnosticLog:)]) return;
    NSURL *log = [self.delegate overlayDiagnosticLog:self];
    if (!log) return;
    UIActivityViewController *share = [[UIActivityViewController alloc]
        initWithActivityItems:@[log] applicationActivities:nil];
    share.popoverPresentationController.sourceView = _menuButton;
    share.popoverPresentationController.sourceRect = _menuButton.bounds;
    [self.presenter presentViewController:share animated:YES completion:nil];
}

- (UIViewController *)presenter
{
    UIViewController *vc = self.window.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

/* Halo's own console command: connect <address> [password] (the same as the -connect switch) */
- (void)promptJoin
{
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Join Server"
                                                               message:nil
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder = @"address:port";
        f.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
        f.autocorrectionType = UITextAutocorrectionTypeNo;
        f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        f.text = HPSettings.shared.recentServers.firstObject;
    }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"password (optional)"; f.secureTextEntry = YES; }];
    __weak HPOverlay *weak = self;
    __weak UIAlertController *wa = a;
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Join" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *addr = [wa.textFields[0].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (addr.length) [weak joinServer:addr password:wa.textFields[1].text ?: @""];
    }]];
    [self.presenter presentViewController:a animated:YES completion:nil];
}

/* Halo's console: connect <address> <password> (both arguments are required; an empty password is "") */
- (void)joinServer:(NSString *)addr password:(NSString *)pw
{
    NSMutableArray *recent = [HPSettings.shared.recentServers mutableCopy];
    [recent removeObject:addr];
    [recent insertObject:addr atIndex:0];
    while (recent.count > 6) [recent removeLastObject];
    HPSettings.shared.recentServers = recent;
    [self rebuildMenu];
    [HPOverlay tapKey:0xC0 scan:0x29];                              /* open Halo's console */
    NSString *quoted = [pw stringByReplacingOccurrencesOfString:@"\"" withString:@""];
    [HPOverlay typeText:[NSString stringWithFormat:@"connect %@ \"%@\"\n", addr, quoted]];
    [HPOverlay tapKey:0xC0 scan:0x29];                              /* and close it: in a game its keys would type there */
}

/* The original pause menu handles both a local host and a remote client.
   The console's disconnect command leaves a local host stuck in its match. */
- (void)leaveGame
{
    [self clearTouchInput];
    [HPOverlay tapKey:0x1b scan:0x01];
}
- (void)showAbout
{
    NSString *text = [self.delegate respondsToSelector:@selector(overlayAbout:)] ? [self.delegate overlayAbout:self] : @"";
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"About HaloPad" message:text preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self.presenter presentViewController:a animated:YES completion:nil];
}
/* Report a Problem: a short description, then a prefilled GitHub issue (the device,
   OS, app build and Halo's state are filled in; nothing is sent without the player
   submitting it) or a plain-text report for anywhere else. */
- (void)report
{
    [self clearTouchInput];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Report a Problem"
        message:@"Describe what happened. HaloPad adds the app version, device and game state; no game files or personal data."
        preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"What went wrong?"; f.autocapitalizationType = UITextAutocapitalizationTypeSentences; }];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = @"What were you doing? (map, server, controls)"; f.autocapitalizationType = UITextAutocapitalizationTypeSentences; }];
    __weak HPOverlay *weak = self;
    __weak UIAlertController *wa = a;
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Share as Text…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [weak shareReport:wa.textFields[0].text context:wa.textFields[1].text]; }]];
    UIAlertAction *github = [UIAlertAction actionWithTitle:@"Open GitHub Issue" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        [weak openIssue:wa.textFields[0].text context:wa.textFields[1].text]; }];
    [a addAction:github];
    a.preferredAction = github;
    [self.presenter presentViewController:a animated:YES completion:nil];
}
- (NSString *)reportBody:(NSString *)problem context:(NSString *)context
{
    return [NSString stringWithFormat:@"### What happened\n%@\n\n### What I was doing\n%@\n\n### Details\n```\n%@\n```\n\n"
                                       "Please attach the diagnostic log: ⋯ › Help › Share Diagnostic Log… (no typed text, names, chat or addresses).\n",
            problem.length ? problem : @"(not given)", context.length ? context : @"(not given)", [self.delegate overlayDiagnostics:self]];
}
- (void)openIssue:(NSString *)problem context:(NSString *)context
{
    NSString *title = problem.length ? problem : @"Problem report";
    if (title.length > 80) title = [[title substringToIndex:80] stringByAppendingString:@"…"];
    NSURLComponents *c = [NSURLComponents componentsWithString:[HPRepositoryURL stringByAppendingString:@"/issues/new"]];
    c.queryItems = @[[NSURLQueryItem queryItemWithName:@"title" value:[@"[Bug] " stringByAppendingString:title]],
                     [NSURLQueryItem queryItemWithName:@"labels" value:@"bug"],
                     [NSURLQueryItem queryItemWithName:@"body" value:[self reportBody:problem context:context]]];
    [UIApplication.sharedApplication openURL:c.URL options:@{} completionHandler:nil];
}
- (void)shareReport:(NSString *)problem context:(NSString *)context
{
    NSString *body = [@"HaloPad problem report\n\n" stringByAppendingString:[self reportBody:problem context:context]];
    NSMutableArray *items = [NSMutableArray arrayWithObject:body];
    NSURL *log = [self.delegate respondsToSelector:@selector(overlayDiagnosticLog:)] ? [self.delegate overlayDiagnosticLog:self] : nil;
    if (log) [items addObject:log];
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    share.popoverPresentationController.sourceView = _menuButton;
    share.popoverPresentationController.sourceRect = _menuButton.bounds;
    [self.presenter presentViewController:share animated:YES completion:nil];
}
- (void)showControllerLayout
{
    UIViewController *guide = [UIViewController new];
    guide.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];
    guide.preferredContentSize = CGSizeMake(520, 580);
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *title = [UILabel new];
    title.text = @"Controller Guide";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    [stack addArrangedSubview:title];
    UILabel *setup = [UILabel new];
    setup.text = self.controllerGuideIntro ?: @"Connect the controller before opening HaloPad. If you connect during play, close and reopen the app.";
    setup.textColor = UIColor.lightGrayColor;
    setup.font = [UIFont systemFontOfSize:14];
    setup.numberOfLines = 0;
    [stack addArrangedSubview:setup];
    NSArray<NSArray *> *sections = self.controllerGuideSections ?: @[
        @[@"Movement & View", @[@"Left stick", @"Move"], @[@"Right stick", @"Look"],
          @[@"Left stick click", @"Crouch"], @[@"Right stick click", @"Zoom"]],
        @[@"Combat & Actions", @[@"RT", @"Fire"], @[@"LT", @"Throw grenade"],
          @[@"A", @"Jump"], @[@"B", @"Melee"], @[@"X", @"Reload"],
          @[@"Y", @"Switch weapon"], @[@"RB (Button 6)", @"Use / pick up / enter vehicle"],
          @[@"LB", @"Switch grenade"], @[@"D-pad up", @"Flashlight"]],
        @[@"Menus", @[@"D-pad", @"Move selection"], @[@"A", @"Select"],
          @[@"B", @"Back"], @[@"View", @"Scoreboard"], @[@"Menu", @"Pause"]]
    ];
    for (NSArray *section in sections) {
        UILabel *heading = [UILabel new];
        heading.text = section[0];
        heading.textColor = UIColor.systemTealColor;
        heading.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
        [stack addArrangedSubview:heading];
        for (NSUInteger i = 1; i < section.count; i++) {
            NSArray<NSString *> *pair = section[i];
            UILabel *button = [UILabel new];
            button.text = pair[0]; button.textColor = UIColor.whiteColor;
            button.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
            [button.widthAnchor constraintEqualToConstant:132].active = YES;
            UILabel *action = [UILabel new];
            action.text = pair[1]; action.textColor = UIColor.lightGrayColor;
            action.font = [UIFont systemFontOfSize:15];
            action.numberOfLines = 0;
            UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[button, action]];
            row.spacing = 12;
            row.alignment = UIStackViewAlignmentTop;
            row.isAccessibilityElement = YES;
            row.accessibilityLabel = [NSString stringWithFormat:@"%@, %@", pair[0], pair[1]];
            [stack addArrangedSubview:row];
        }
    }
    UILabel *note = [UILabel new];
    note.text = self.controllerGuideFootnote ?: @"Change bindings in Halo → Settings → Controls Setup.";
    note.textColor = UIColor.lightGrayColor;
    note.font = [UIFont systemFontOfSize:13];
    note.numberOfLines = 0;
    [stack addArrangedSubview:note];
    [guide.view addSubview:scroll];
    [scroll addSubview:stack];
    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"Done" forState:UIControlStateNormal];
    done.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    done.translatesAutoresizingMaskIntoConstraints = NO;
    [done addTarget:self action:@selector(dismissControllerGuide) forControlEvents:UIControlEventPrimaryActionTriggered];
    [guide.view addSubview:done];
    UILayoutGuide *safe = guide.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16],
        [scroll.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [scroll.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [scroll.bottomAnchor constraintEqualToAnchor:done.topAnchor constant:-8],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
        [done.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [done.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [done.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
        [done.heightAnchor constraintEqualToConstant:44]
    ]];
    [self.presenter presentViewController:guide animated:YES completion:nil];
}
- (void)dismissControllerGuide { [self.presenter dismissViewControllerAnimated:YES completion:nil]; }

+ (void)setTextInputActive:(BOOL)active
{
    NSAssert(NSThread.isMainThread, @"Text input belongs to UIKit's main thread");
    typed_active = active;
    if (active) return;
    [typed_queue removeAllObjects];
    /* A canceled Shift-up (or ordinary key-up) must not leave that key held. These
       releases precede the scene's deactivation event in the host queue. */
    for (NSValue *value in typed_held.allValues) {
        hp_input up;
        [value getValue:&up size:sizeof up];
        up.down = 0;
        up.nchars = 0;
        memset(up.chars, 0, sizeof up.chars);
        halopad_host_post_input(&up);
    }
    [typed_held removeAllObjects];
}

+ (void)tapKey:(uint32_t)vk scan:(uint32_t)scan
{
    queue_key(vk, 0, scan, 1, 0);
    queue_key(vk, 0, scan, 0, 0);
}

+ (void)typeText:(NSString *)text
{
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        uint32_t vk, scan; int shift;
        if (!us_key(c, &vk, &scan, &shift)) continue;
        if (c == '\n') c = '\r';
        if (shift) queue_key(0x10, 0xA0, 0x2a, 1, 0);
        queue_key(vk, 0, scan, 1, c == '\b' ? 0x08 : c);
        queue_key(vk, 0, scan, 0, 0);
        if (shift) queue_key(0x10, 0xA0, 0x2a, 0, 0);
    }
}

/* ---- the settings panel (SunPad's: opacity, size, hide with a controller, edit, reset) ---- */

- (UIView *)row:(NSString *)title control:(UIView *)c
{
    UILabel *l = [UILabel new];
    l.text = title;
    l.textColor = UIColor.whiteColor;
    l.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    [l setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisHorizontal];
    [c setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *r = [[UIStackView alloc] initWithArrangedSubviews:@[l, c]];
    r.spacing = 12;
    r.alignment = UIStackViewAlignmentCenter;
    return r;
}
- (UISlider *)slider:(float)lo max:(float)hi action:(SEL)sel
{
    UISlider *s = [UISlider new];
    s.minimumValue = lo; s.maximumValue = hi;
    [s addTarget:self action:sel forControlEvents:UIControlEventValueChanged];
    return s;
}
- (void)buildPanel
{
    _panel = [UIView new];
    _panel.backgroundColor = [UIColor colorWithWhite:0.035 alpha:0.94];
    _panel.layer.cornerRadius = 16;
    _panel.clipsToBounds = YES;
    _panel.layer.borderWidth = 1;
    _panel.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
    _panel.hidden = YES;
    _panel.accessibilityIdentifier = @"TouchControlSettings";
    UILabel *title = [UILabel new];
    title.text = @"Touch Controls";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    _opacity = [self slider:0.25 max:1 action:@selector(opacityChanged:)];
    _size = [self slider:0.7 max:1.35 action:@selector(sizeChanged:)];
    _look = [self slider:0.25 max:6 action:@selector(lookChanged:)];
    _hideSwitch = [UISwitch new];
    [_hideSwitch addTarget:self action:@selector(hideChanged:) forControlEvents:UIControlEventValueChanged];
    _editSwitch = [UISwitch new];
    [_editSwitch addTarget:self action:@selector(editChanged:) forControlEvents:UIControlEventValueChanged];
    _leftSwitch = [UISwitch new];
    [_leftSwitch addTarget:self action:@selector(leftChanged:) forControlEvents:UIControlEventValueChanged];
    _captionSwitch = [UISwitch new];
    [_captionSwitch addTarget:self action:@selector(captionChanged:) forControlEvents:UIControlEventValueChanged];
    _spacingControl = [[UISegmentedControl alloc] initWithItems:@[@"Compact", @"Normal", @"Spread"]];
    [_spacingControl addTarget:self action:@selector(spacingChanged:) forControlEvents:UIControlEventValueChanged];
    _spacingControl.selectedSegmentTintColor = [UIColor colorWithWhite:1 alpha:0.9];
    _spacingControl.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    [_spacingControl setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor} forState:UIControlStateNormal];
    [_spacingControl setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.blackColor} forState:UIControlStateSelected];
    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [reset setTitle:@"Reset This Device Layout" forState:UIControlStateNormal];
    [reset setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    [reset addTarget:self action:@selector(confirmReset) forControlEvents:UIControlEventPrimaryActionTriggered];
    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"Done" forState:UIControlStateNormal];
    done.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [done addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventPrimaryActionTriggered];
    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[title, done]];
    header.alignment = UIStackViewAlignmentCenter;
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [done setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [done.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [_panel addSubview:header];
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    scroll.accessibilityIdentifier = @"TouchControlSettingsScroll";
    [_panel addSubview:scroll];
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        [self row:@"Opacity" control:_opacity], [self row:@"Size" control:_size], [self row:@"Look Speed" control:_look],
        [self row:@"Left-handed" control:_leftSwitch], [self row:@"Button Labels" control:_captionSwitch],
        [self row:@"Spacing" control:_spacingControl],
        [self row:@"Hide with a Controller" control:_hideSwitch], [self row:@"Move Controls" control:_editSwitch], reset]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    for (UIView *row in stack.arrangedSubviews)
        [row.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:18],
        [header.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor constant:-18],
        [header.topAnchor constraintEqualToAnchor:_panel.topAnchor constant:8],
        [scroll.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:8],
        [scroll.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:_panel.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-18],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-16],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-36]]];
    [self addSubview:_panel];
}
- (void)togglePanel
{
    if (_editing) [self endEditing];
    _panel.hidden = !_panel.hidden;
    if (!_panel.hidden) [self clearTouchInput];
    HPSettings *s = HPSettings.shared;
    _opacity.value = s.controlOpacity; _size.value = s.controlSize; _look.value = s.lookSensitivity;
    _hideSwitch.on = s.hideWithController; _editSwitch.on = NO;
    _leftSwitch.on = s.leftHanded; _captionSwitch.on = s.showCaptions; _spacingControl.selectedSegmentIndex = s.ringSpacing;
    [self bringSubviewToFront:_panel];
}
- (void)opacityChanged:(UISlider *)s { HPSettings.shared.controlOpacity = s.value; [self updateAppearance]; }
- (void)sizeChanged:(UISlider *)s { HPSettings.shared.controlSize = s.value; [self setNeedsLayout]; }
- (void)lookChanged:(UISlider *)s { HPSettings.shared.lookSensitivity = s.value; }
- (void)hideChanged:(UISwitch *)s { HPSettings.shared.hideWithController = s.on; [self refreshControllerVisibility]; }
- (void)editChanged:(UISwitch *)s { if (s.on) [self beginEditing]; else [self endEditing]; }
- (void)leftChanged:(UISwitch *)s { HPSettings.shared.leftHanded = s.on; [self clearTouchInput]; [self setNeedsLayout]; }
- (void)captionChanged:(UISwitch *)s { HPSettings.shared.showCaptions = s.on; [self setNeedsLayout]; }
- (void)spacingChanged:(UISegmentedControl *)c { HPSettings.shared.ringSpacing = c.selectedSegmentIndex; [self setNeedsLayout]; }
- (void)confirmReset
{
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Reset Touch Control Layout?"
                                                               message:@"All control positions and sizes on this kind of device return to their defaults."
                                                        preferredStyle:UIAlertControllerStyleAlert];
    __weak HPOverlay *weak = self;
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [NSUserDefaults.standardUserDefaults removeObjectForKey:[weak key:@"origins"]];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:[weak key:@"scales"]];
        [weak setNeedsLayout];
    }]];
    [self.presenter presentViewController:a animated:YES completion:nil];
}

/* ---- the layout editor: drag to move, tap to select, a size slider, Done ---- */

- (void)buildEditorBar
{
    _editorBar = [UIView new];
    _editorBar.backgroundColor = [UIColor colorWithWhite:0.035 alpha:0.94];
    _editorBar.layer.cornerRadius = 14;
    _editorBar.hidden = YES;
    _editorHint = [UILabel new];
    _editorHint.textColor = UIColor.whiteColor;
    _editorHint.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    _editorHint.text = @"Drag to align • tap to resize";
    _selectedSize = [self slider:0.6 max:1.75 action:@selector(selectedSizeChanged:)];
    _selectedSize.enabled = NO;
    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"Done" forState:UIControlStateNormal];
    done.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [done addTarget:self action:@selector(endEditing) forControlEvents:UIControlEventPrimaryActionTriggered];
    UIStackView *r = [[UIStackView alloc] initWithArrangedSubviews:@[_editorHint, _selectedSize, done]];
    r.spacing = 14;
    r.alignment = UIStackViewAlignmentCenter;
    r.translatesAutoresizingMaskIntoConstraints = NO;
    [_editorBar addSubview:r];
    [NSLayoutConstraint activateConstraints:@[
        [r.leadingAnchor constraintEqualToAnchor:_editorBar.leadingAnchor constant:16],
        [r.trailingAnchor constraintEqualToAnchor:_editorBar.trailingAnchor constant:-16],
        [r.centerYAnchor constraintEqualToAnchor:_editorBar.centerYAnchor],
        [_selectedSize.widthAnchor constraintGreaterThanOrEqualToConstant:140]]];
    [self addSubview:_editorBar];
}
- (void)addEditGestures:(UIView *)v
{
    UIPanGestureRecognizer *drag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragged:)];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)];
    drag.enabled = tap.enabled = NO;
    [v addGestureRecognizer:drag];
    [v addGestureRecognizer:tap];
    [_editGestures addObjectsFromArray:@[drag, tap]];
}
- (void)beginEditing
{
    [self clearTouchInput];
    _editing = YES;
    _panel.hidden = YES;
    _editorBar.hidden = NO;
    _selected = nil;
    _selectedSize.enabled = NO;
    _editorHint.text = @"Drag to align • tap to resize";
    for (UIGestureRecognizer *g in _editGestures) g.enabled = YES;
    [self updateAppearance];
}
- (void)endEditing
{
    _editing = NO;
    _editorBar.hidden = YES;
    _editSwitch.on = NO;
    for (UIGestureRecognizer *g in _editGestures) g.enabled = NO;
    _selected = nil;
    [self setNeedsLayout];
    [self clearTouchInput];
    [self updateAppearance];
}
- (void)select:(UIView *)v
{
    _selected = v;
    NSNumber *s = [NSUserDefaults.standardUserDefaults dictionaryForKey:[self key:@"scales"]][v.accessibilityIdentifier];
    _selectedSize.value = s ? s.floatValue : 1;
    _selectedSize.enabled = YES;
    _editorHint.text = [NSString stringWithFormat:@"%@ size", v.accessibilityLabel];
    [self updateAppearance];
}
- (void)tapped:(UITapGestureRecognizer *)t { if (t.state == UIGestureRecognizerStateEnded) [self select:t.view]; }
/* Snap only on release so the control follows the finger throughout the drag.
   Nearby centres line up rows/columns, including the two sticks. Reject a snap
   that would reduce clearance below eight points or cross the safe area. */
- (CGPoint)alignedCenter:(CGPoint)center forView:(UIView *)view
{
    NSMutableArray<UIView *> *targets = [NSMutableArray arrayWithArray:_buttons];
    [targets addObjectsFromArray:@[_move, _aim]];
    CGPoint aligned = center;
    CGFloat closestX = 8.01, closestY = 8.01;
    for (UIView *other in targets) {
        if (other == view || other.hidden) continue;
        CGFloat dx = fabs(other.center.x - center.x), dy = fabs(other.center.y - center.y);
        if (dx < closestX) { closestX = dx; aligned.x = other.center.x; }
        if (dy < closestY) { closestY = dy; aligned.y = other.center.y; }
    }
    /* Try both axes, then each separately if the combined snap is obstructed. */
    CGPoint candidates[] = {aligned, {aligned.x, center.y}, {center.x, aligned.y}};
    for (int i = 0; i < 3; i++) {
        CGRect frame = CGRectMake(candidates[i].x - view.bounds.size.width / 2,
                                  candidates[i].y - view.bounds.size.height / 2,
                                  view.bounds.size.width, view.bounds.size.height);
        BOOL clear = CGRectContainsRect(self.safe, frame);
        for (UIView *other in targets) {
            if (other == view || other.hidden) continue;
            CGFloat dx = MAX(0, MAX(CGRectGetMinX(frame) - CGRectGetMaxX(other.frame),
                                    CGRectGetMinX(other.frame) - CGRectGetMaxX(frame)));
            CGFloat dy = MAX(0, MAX(CGRectGetMinY(frame) - CGRectGetMaxY(other.frame),
                                    CGRectGetMinY(other.frame) - CGRectGetMaxY(frame)));
            if (hypot(dx, dy) < 7.99) { clear = NO; break; }
        }
        if (clear) return candidates[i];
    }
    return center;
}
- (void)dragged:(UIPanGestureRecognizer *)g
{
    UIView *v = g.view;
    if (g.state == UIGestureRecognizerStateBegan) [self select:v];
    CGPoint d = [g translationInView:self];
    [g setTranslation:CGPointZero inView:self];
    CGRect safe = self.safe;
    CGFloat hw = v.bounds.size.width / 2, hh = v.bounds.size.height / 2;
    v.center = CGPointMake(fmin(fmax(v.center.x + d.x, CGRectGetMinX(safe) + hw), CGRectGetMaxX(safe) - hw),
                           fmin(fmax(v.center.y + d.y, CGRectGetMinY(safe) + hh), CGRectGetMaxY(safe) - hh));
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        if (g.state == UIGestureRecognizerStateEnded) v.center = [self alignedCenter:v.center forView:v];
        NSMutableDictionary *o = [[NSUserDefaults.standardUserDefaults dictionaryForKey:[self key:@"origins"]] mutableCopy] ?: [NSMutableDictionary dictionary];
        o[v.accessibilityIdentifier] = NSStringFromCGPoint(CGPointMake((v.center.x - CGRectGetMinX(safe)) / safe.size.width,
                                                                       (v.center.y - CGRectGetMinY(safe)) / safe.size.height));
        [NSUserDefaults.standardUserDefaults setObject:o forKey:[self key:@"origins"]];
    }
}
- (void)selectedSizeChanged:(UISlider *)s
{
    if (!_selected) return;
    NSMutableDictionary *o = [[NSUserDefaults.standardUserDefaults dictionaryForKey:[self key:@"scales"]] mutableCopy] ?: [NSMutableDictionary dictionary];
    o[_selected.accessibilityIdentifier] = @(s.value);
    [NSUserDefaults.standardUserDefaults setObject:o forKey:[self key:@"scales"]];
    [self setNeedsLayout];
}

/* development: the three-dot menu as text, for comparing the editions' menus */
- (void)printMenu:(UIMenu *)menu depth:(int)depth
{
    for (UIMenuElement *element in menu.children) {
        BOOL group = [element isKindOfClass:UIMenu.class];
        if (!(group && !element.title.length))
            fprintf(stderr, "HALOPAD MENU: %*s%s%s\n", depth * 2, "", element.title.UTF8String, group ? " ›" : "");
        if (group) [self printMenu:(UIMenu *)element depth:element.title.length ? depth + 1 : depth];
    }
}

/* development: open a part of the overlay for an unattended screenshot (HALOPAD_OVERLAY_DEMO) */
- (void)didMoveToWindow
{
    [super didMoveToWindow];
    const char *demo = getenv("HALOPAD_OVERLAY_DEMO");
    if (!self.window || !demo) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (!strcmp(demo, "settings")) [self togglePanel];
        if (!strcmp(demo, "layout")) { [self beginEditing]; }
        if (!strcmp(demo, "lefthanded")) { HPSettings.shared.leftHanded = YES; [self setNeedsLayout]; }
        if (!strcmp(demo, "spread")) { HPSettings.shared.ringSpacing = 2; HPSettings.shared.showCaptions = NO; [self setNeedsLayout]; }
        if (!strcmp(demo, "menu")) [self printMenu:self->_menuButton.menu depth:0];
        if (!strcmp(demo, "guide")) [self showControllerLayout];
        if (!strcmp(demo, "switch")) [self confirmEditionSwitch];
        if (!strcmp(demo, "switch-close")) [HPOverlay closeForEditionSwitch];
        fprintf(stderr, "HALOPAD OVERLAY: demo \"%s\" open\n", demo);
    });
    /* join:ADDRESS: the menu's Join Server, once Halo's menu is up */
    if (!strcmp(demo, "console") || !strcmp(demo, "console-keyboard")) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            fprintf(stderr, "HALOPAD OVERLAY: demo opens console through the menu's key handler\n");
            [HPOverlay tapKey:0xC0 scan:0x29];
            if (!strcmp(demo, "console-keyboard")) [self.delegate overlayRequestsKeyboard:self];
        });
    }
    if (!strncmp(demo, "join:", 5)) {
        NSString *addr = @(demo + 5);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            fprintf(stderr, "HALOPAD OVERLAY: demo joins %s through Halo's console\n", addr.UTF8String);
            [self joinServer:addr password:@""];
        });
    }
}
@end
