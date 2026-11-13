/* UIKit overlay input boundary tests. Uses the real timer/handlers, capturing the events
   sent to the host; it does not claim actual multi-touch routing or game acceptance. */
#import "../port/ios/HaloPadOverlay.h"
#include "../port/runtime/halopad_input.h"
#include "../port/xbox/xg_overlay_input.h"
#include <stdio.h>

static hp_input events[512];
static int count, failures, cancellations, countAtCancel;
static BOOL held[256], actions[29];
static void check(const char *name, BOOL ok);
static void run_for(double seconds);
static BOOL all_released(void);

static void check_xbox_adapter(void)
{
    __block struct xg_overlay_input adapter = {0};
    __block struct xg_touch_input buffer = {0};
    __block int lookX = 0, lookY = 0;
    int pcCount = count;
    HPOverlay *view = [[HPOverlay alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)
        inputHandler:^(const hp_input *event) {
            xg_overlay_event(&adapter, event);
            if (event->kind == HPI_CANCEL_TOUCH) { xg_touch_clear(&buffer); lookX = lookY = 0; }
            else if (event->kind == HPI_MOUSEMOVE) { lookX += event->dx; lookY += event->dy; }
            else xg_touch_publish(&buffer, &adapter.pad);
        }];
    view.inGame = YES; view.analogMoveReady = YES;
    [view setControllerLabel:@"A" hint:@"Xbox A. Select in menus." forControl:@"jump"];
    [view setControllerLabel:@"B" hint:@"Xbox B. Back in menus." forControl:@"melee"];
    [view setControllerLabel:@"X" hint:@"Xbox X" forControl:@"action"];
    [view setControllerLabel:@"X" hint:@"Xbox X" forControl:@"reload"];
    [view setControllerLabel:@"Y" hint:@"Xbox Y" forControl:@"switch"];
    [view layoutIfNeeded];
    UIView *jump = nil;
    for (UIView *button in view.subviews)
        if ([button.accessibilityIdentifier isEqualToString:@"jump"]) jump = button;
    UILabel *badge = [jump valueForKey:@"controllerLabel"];
    check("Xbox A badge explains Select without changing Jump's action label",
          [badge.text isEqualToString:@"A"] && !badge.hidden &&
          [jump.accessibilityLabel isEqualToString:@"Jump"] &&
          [jump.accessibilityHint isEqualToString:@"Xbox A. Select in menus."]);
    BOOL captions = HPSettings.shared.showCaptions;
    HPSettings.shared.showCaptions = NO;
    [jump setNeedsLayout]; [jump layoutIfNeeded];
    check("Xbox letter remains visible with captions off and inside the original target",
          !badge.hidden && [(UILabel *)[jump valueForKey:@"label"] isHidden] && CGRectContainsRect(jump.bounds, badge.frame));
    HPSettings.shared.showCaptions = captions;
    [jump setNeedsLayout]; [jump layoutIfNeeded];
    const char *renderPath = getenv("HALOPAD_OVERLAY_RENDER_DIR");
    if (renderPath) {
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size];
        UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [UIColor.blackColor setFill]; UIRectFill(view.bounds);
            [view.layer renderInContext:context.CGContext];
        }];
        check("shared Xbox label preview written", [UIImagePNGRepresentation(image) writeToFile:
            [@(renderPath) stringByAppendingPathComponent:@"xbox-labels.png"] atomically:YES]);
    }
    [view driveMoveX:.5 y:1];
    [view driveControl:@"fire" down:YES];
    [view driveLookX:20 y:-10];
    check("shared Xbox controls hold movement/fire and accumulate independent look",
          buffer.current.axes[0] == .5f && buffer.current.axes[1] == -1 &&
          buffer.current.axes[5] == 1 && lookX > 0 && lookY < 0);
    [view driveControl:@"action" down:YES]; [view driveControl:@"reload" down:YES];
    (void)xg_touch_button(&buffer, SDL_GAMEPAD_BUTTON_WEST);
    [view driveControl:@"action" down:NO];
    check("Xbox USE/RELOAD alias preserves X until both controls release",
          xg_touch_button(&buffer, SDL_GAMEPAD_BUTTON_WEST) && xg_touch_button(&buffer, SDL_GAMEPAD_BUTTON_WEST));
    [view driveControl:@"reload" down:NO];
    check("last Xbox X owner releases", !xg_touch_button(&buffer, SDL_GAMEPAD_BUTTON_WEST));
    [view driveControl:@"jump" down:YES]; [view driveControl:@"jump" down:NO];
    check("shared Jump reaches Xbox A for one poll after a short tap",
          xg_touch_button(&buffer, SDL_GAMEPAD_BUTTON_SOUTH) && !xg_touch_button(&buffer, SDL_GAMEPAD_BUTTON_SOUTH));
    [view driveControl:@"menu" down:YES]; [view driveControl:@"menu" down:NO];
    check("shared pause reaches Xbox Start", xg_touch_button(&buffer, SDL_GAMEPAD_BUTTON_START));
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    struct xg_touch_input zero = {0};
    check("shared Xbox focus loss clears held/unread controls and look",
          !memcmp(&buffer, &zero, sizeof(zero)) && !lookX && !lookY);
    [view driveControl:@"fire" down:YES]; [view driveMoveX:1 y:1]; [view driveLookX:20 y:30];
    check("inactive engine adapter refuses input", !memcmp(&buffer, &zero, sizeof(zero)) && !lookX);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    [view driveControl:@"fire" down:YES];
    check("fresh Xbox fire works after activation", xg_touch_axis(&buffer, 5) == 1);
    [view clearTouchInput];
    check("Xbox routing never posts into PC input", count == pcCount);
    UIButton *menu = [view valueForKey:@"menuButton"];
    check("Xbox menu contains shared settings and excludes PC join/chat commands", menu.menu.children.count == 2);
    HPOverlay *pc = [[HPOverlay alloc] initWithFrame:view.frame]; pc.inGame = YES;
    [pc layoutIfNeeded];
    BOOL same = YES;
    for (UIView *a in view.subviews) for (UIView *b in pc.subviews)
        if (a.accessibilityIdentifier.length && [a.accessibilityIdentifier isEqualToString:b.accessibilityIdentifier])
            same &= CGRectEqualToRect(a.frame, b.frame);
    check("PC and Xbox share identical layout geometry and preference keys", same);
    BOOL pcUnchanged = YES;
    for (UIView *button in [pc valueForKey:@"buttons"])
        pcUnchanged &= [(UILabel *)[button valueForKey:@"controllerLabel"] isHidden];
    check("PC controls do not acquire Xbox badges", pcUnchanged);
    int beforeLabelChange = count;
    [view setControllerLabel:nil hint:nil forControl:@"jump"];
    [view setControllerLabel:@"?" hint:@"Unused" forControl:@"unknown"];
    check("clearing or unknown presentation labels never deliver input",
          badge.hidden && jump.accessibilityHint == nil && count == beforeLabelChange);
}

@interface HPTestOverlay : HPOverlay
@property(nonatomic) BOOL simulatedPhone;
@property(nonatomic) UIEdgeInsets simulatedInsets;
@end
@implementation HPTestOverlay
- (BOOL)phone { return self.simulatedPhone; }
- (UIEdgeInsets)safeAreaInsets { return self.simulatedInsets; }
@end

@interface HPOverlay (LayoutTesting)
- (CGPoint)alignedCenter:(CGPoint)center forView:(UIView *)view;
- (void)place:(UIView *)view frame:(CGRect)frame;
- (NSString *)key:(NSString *)what;
- (void)beginEditing;
- (void)endEditing;
- (void)select:(UIView *)view;
- (void)togglePanel;
- (void)leftChanged:(UISwitch *)sender;
- (void)lookChanged:(UISlider *)sender;
- (void)selectedSizeChanged:(UISlider *)sender;
@end

static BOOL menu_has_title(UIMenu *menu, NSString *title)
{
    for (UIMenuElement *element in menu.children) {
        if ([element.title isEqualToString:title]) return YES;
        if ([element isKindOfClass:UIMenu.class] && menu_has_title((UIMenu *)element, title)) return YES;
    }
    return NO;
}
/* Show Touch Controls overrides both the manual hide and controller suppression, in both
   editions (the Xbox host passes controllerConnected; the PC host uses the same overlay). */
static void check_show_precedence(void)
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    id savedAuto = [defaults objectForKey:@"HaloPad.hideWithController"];
    id savedManual = [defaults objectForKey:@"HaloPad.hideTouchControls"];
    [defaults removeObjectForKey:@"HaloPad.hideWithController"];
    [defaults removeObjectForKey:@"HaloPad.hideTouchControls"];
    check("auto-hide defaults on when no choice is saved", HPSettings.shared.hideWithController);
    [defaults setObject:@NO forKey:@"HaloPad.hideWithController"];
    check("a saved auto-hide choice is kept", !HPSettings.shared.hideWithController);
    [defaults removeObjectForKey:@"HaloPad.hideWithController"];

    __block BOOL connected = YES;
    for (int edition = 0; edition < 2; edition++) {
        HPOverlay *view = edition ? [[HPOverlay alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)
                                                        inputHandler:^(const hp_input *event) { (void)event; }]
                                  : [[HPOverlay alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)];
        const char *name = edition ? "Xbox" : "PC";
        view.inGame = YES;
        view.controllerConnected = ^BOOL { return connected; };
        UIButton *menu = [view valueForKey:@"menuButton"];
        connected = YES; HPSettings.shared.hideWithController = YES; HPSettings.shared.hideTouchControls = YES;
        [view refreshControllerVisibility];
        BOOL hidden = [[view valueForKey:@"controlsHidden"] boolValue];
        BOOL offered = menu_has_title(menu.menu, @"Show Touch Controls");
        [view showTouchControls];
        BOOL shown = ![[view valueForKey:@"controlsHidden"] boolValue];
        BOOL prefs = !HPSettings.shared.hideTouchControls && !HPSettings.shared.hideWithController;
        BOOL withdrawn = !menu_has_title(menu.menu, @"Show Touch Controls");
        [view refreshControllerVisibility];   /* the controller reconnects or is polled again */
        BOOL stays = ![[view valueForKey:@"controlsHidden"] boolValue];
        HPSettings.shared.hideWithController = YES;
        [view refreshControllerVisibility];
        BOOL rehidden = [[view valueForKey:@"controlsHidden"] boolValue];
        connected = NO; [view refreshControllerVisibility];
        BOOL returns = ![[view valueForKey:@"controlsHidden"] boolValue];
        view.softwareKeyboardVisible = YES;
        BOOL keyboardHides = [[view valueForKey:@"controlsHidden"] boolValue];
        view.softwareKeyboardVisible = NO;
        fprintf(stderr, "OVERLAY SHOW %s: hidden=%d offered=%d shown=%d prefs=%d withdrawn=%d stays=%d rehidden=%d returns=%d keyboard=%d\n",
                name, hidden, offered, shown, prefs, withdrawn, stays, rehidden, returns, keyboardHides);
        check(edition ? "Xbox: Show overrides controller suppression and turns auto-hide off"
                      : "PC: Show overrides controller suppression and turns auto-hide off",
              hidden && offered && shown && prefs && withdrawn && stays);
        check(edition ? "Xbox: re-enabled auto-hide applies at once; the keyboard still hides controls"
                      : "PC: re-enabled auto-hide applies at once; the keyboard still hides controls",
              rehidden && returns && keyboardHides);
    }
    if (savedAuto) [defaults setObject:savedAuto forKey:@"HaloPad.hideWithController"];
    else [defaults removeObjectForKey:@"HaloPad.hideWithController"];
    if (savedManual) [defaults setObject:savedManual forKey:@"HaloPad.hideTouchControls"];
    else [defaults removeObjectForKey:@"HaloPad.hideTouchControls"];
}
static void check_editor_alignment(void)
{
    HPTestOverlay *view = [[HPTestOverlay alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)];
    view.inGame = YES;
    [view layoutIfNeeded];
    UIView *move = [view valueForKey:@"move"], *aim = [view valueForKey:@"aim"];
    for (UIView *other in view.subviews) other.hidden = other != move && other != aim;
    move.frame = CGRectMake(40, 400, 144, 144);
    aim.frame = CGRectMake(840, 400, 144, 144);
    CGPoint near = CGPointMake(move.center.x, move.center.y + 6);
    check("editor aligns the two sticks after a near-baseline drop",
          CGPointEqualToPoint([view alignedCenter:near forView:move], move.center));
    CGPoint far = CGPointMake(move.center.x, move.center.y + 20);
    check("editor preserves deliberate offsets outside snap distance",
          CGPointEqualToPoint([view alignedCenter:far forView:move], far));
    aim.frame = CGRectMake(194, 406, 144, 144);
    near = CGPointMake(move.center.x + 6, move.center.y);
    check("editor refuses alignment that crowds another control",
          CGPointEqualToPoint([view alignedCenter:near forView:move], near));
    NSString *key = [view key:@"scales"];
    NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:key];
    [NSUserDefaults.standardUserDefaults setObject:@{@"move": @0.6} forKey:key];
    [view place:move frame:CGRectMake(0, 0, 52, 52)];
    check("saved small scales retain a 44-point tappable target",
          move.bounds.size.width == 44 && move.bounds.size.height == 44);
    if (saved) [NSUserDefaults.standardUserDefaults setObject:saved forKey:key];
    else [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
}

/* Real settings/editor handlers, with separate PC/Xbox destinations. This checks
   persisted presentation and cancellation contracts, not physical multitouch. */
static void check_shared_settings(void)
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSArray *keys = @[@"HaloPad.lookSensitivity", @"HaloPad.leftHanded",
                      @"HaloPad.tablet.v3.origins", @"HaloPad.tablet.v3.scales",
                      @"HaloPad.phone.v3.origins", @"HaloPad.phone.v3.scales"];
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    for (NSString *key in keys) {
        id value = [defaults objectForKey:key];
        if (value) saved[key] = value;
    }
    __block struct xg_overlay_input adapter = {0};
    __block int xboxLook = 0;
    HPTestOverlay *xbox = [[HPTestOverlay alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)
        inputHandler:^(const hp_input *event) {
            xg_overlay_event(&adapter, event);
            if (event->kind == HPI_MOUSEMOVE) xboxLook += event->dx;
        }];
    xbox.inGame = YES; xbox.analogMoveReady = YES;
    [defaults removeObjectForKey:[xbox key:@"origins"]];
    [defaults removeObjectForKey:[xbox key:@"scales"]];
    HPSettings.shared.leftHanded = NO;
    [xbox layoutIfNeeded];
    UIView *move = [xbox valueForKey:@"move"], *aim = [xbox valueForKey:@"aim"];
    CGPoint moveBefore = move.center, aimBefore = aim.center;
    [xbox driveMoveX:1 y:1]; [xbox driveControl:@"fire" down:YES];
    [xbox togglePanel];
    check("opening shared settings cancels Xbox movement and fire", !adapter.actions &&
          adapter.pad.axes[0] == 0 && adapter.pad.axes[1] == 0 && adapter.pad.axes[5] == 0);
    UISwitch *hand = [xbox valueForKey:@"leftSwitch"];
    check("shared settings retain the registered value-change targets",
          [[hand actionsForTarget:xbox forControlEvent:UIControlEventValueChanged] containsObject:@"leftChanged:"]);
    /* This helper has no UIApplication event loop. Invoke the registered handler
       directly; real UI dispatch is covered separately on the installed app. */
    hand.on = YES; [xbox leftChanged:hand];
    [xbox layoutIfNeeded];
    check("left-handed handler mirrors both sticks without changing their identities",
          hypot(move.center.x - aimBefore.x, move.center.y - aimBefore.y) < .01 &&
          hypot(aim.center.x - moveBefore.x, aim.center.y - moveBefore.y) < .01);
    UISlider *look = [xbox valueForKey:@"look"];
    check("Look Speed slider keeps its handler", [[look actionsForTarget:xbox
          forControlEvent:UIControlEventValueChanged] containsObject:@"lookChanged:"]);
    look.value = 2; [xbox lookChanged:look];
    [xbox driveLookX:10 y:0];
    /* UISlider returns a float near 2, not necessarily exactly 2. The overlay
       intentionally retains sub-count fractions for the next drag segment. */
    check("shared Look Speed handler changes Xbox mouse counts",
          fabs(HPSettings.shared.lookSensitivity - 2) < .00001 &&
          xboxLook == (int)(10 * 2.2 * HPSettings.shared.lookSensitivity));
    [xbox togglePanel];
    [xbox driveControl:@"fire" down:YES];
    [xbox beginEditing];
    check("entering editor releases gameplay input", !adapter.actions && adapter.pad.axes[5] == 0);
    [xbox driveMoveX:1 y:1];
    [xbox select:move];
    CGFloat baseWidth = move.bounds.size.width;
    UISlider *resize = [xbox valueForKey:@"selectedSize"];
    check("editor resize slider keeps its handler", [[resize actionsForTarget:xbox
          forControlEvent:UIControlEventValueChanged] containsObject:@"selectedSizeChanged:"]);
    resize.value = 1.2; [xbox selectedSizeChanged:resize];
    check("editor selection and resizing do not fire or move the player", !adapter.actions &&
          adapter.pad.axes[0] == 0 && adapter.pad.axes[1] == 0 && adapter.pad.axes[5] == 0);
    /* The saved normalized position is the editor's persistence contract. Actual
       drag delivery is a separate UI test; do not synthesize it here. */
    [defaults setObject:@{@"move": NSStringFromCGPoint(CGPointMake(.7, .65))}
                forKey:[xbox key:@"origins"]];
    [xbox endEditing]; [xbox layoutIfNeeded];
    HPTestOverlay *pc = [[HPTestOverlay alloc] initWithFrame:xbox.frame];
    pc.inGame = YES; [pc layoutIfNeeded];
    UIView *pcMove = [pc valueForKey:@"move"];
    check("fresh PC overlay restores Xbox-edited position and size",
          CGRectEqualToRect(move.frame, pcMove.frame) && fabs(move.center.x - 716.8) < .01 &&
          fabs(move.center.y - 499.2) < .01 && fabs(move.bounds.size.width - baseWidth * 1.2) < .01);
    int before = count;
    [pc driveLookX:10 y:0];
    check("fresh PC overlay uses the same saved Look Speed", count == before + 1 &&
          events[before].kind == HPI_MOUSEMOVE && events[before].dx == xboxLook);
    HPTestOverlay *phone = [[HPTestOverlay alloc] initWithFrame:CGRectMake(0, 0, 844, 390)];
    phone.simulatedPhone = YES;
    [defaults setObject:@{@"move": NSStringFromCGPoint(CGPointMake(.2, .6))}
                forKey:[phone key:@"origins"]];
    [phone setNeedsLayout]; [phone layoutIfNeeded];
    [xbox setNeedsLayout]; [xbox layoutIfNeeded];
    check("phone layout changes do not overwrite shared tablet layout",
          ![[phone key:@"origins"] isEqualToString:[xbox key:@"origins"]] &&
          CGRectEqualToRect(move.frame, pcMove.frame));
    [xbox driveControl:@"fire" down:YES];
    check("fresh fire works after leaving editor", adapter.pad.axes[5] == 1);
    [xbox clearTouchInput]; [pc clearTouchInput]; [phone clearTouchInput];
    for (NSString *key in keys) {
        if (saved[key]) [defaults setObject:saved[key] forKey:key];
        else [defaults removeObjectForKey:key];
    }
}

@interface HPLookDrag : NSObject
@property(nonatomic, copy) void (^delta)(CGFloat dx, CGFloat dy);
- (void)begin:(id)token at:(CGPoint)point;
- (void)move:(id)token to:(CGPoint)point;
- (void)end:(id)token at:(CGPoint)point cancelled:(BOOL)cancelled;
- (void)clear;
@end

static void check_drag_tracking(void)
{
    HPLookDrag *drag = [HPLookDrag new];
    NSObject *a = [NSObject new], *b = [NSObject new];
    __block CGFloat x = 0, y = 0;
    __block int deltas = 0;
    drag.delta = ^(CGFloat dx, CGFloat dy) { x += dx; y += dy; deltas++; };
    [drag begin:a at:CGPointMake(10, 20)];
    [drag end:a at:CGPointMake(110, 15) cancelled:NO];
    check("short swipe with no move callback preserves final displacement", x == 100 && y == -5 && deltas == 1);
    x = y = 0; deltas = 0;
    [drag begin:a at:CGPointZero];
    [drag move:a to:CGPointMake(20, 0)];
    [drag move:a to:CGPointMake(50, 5)];
    [drag end:a at:CGPointMake(80, 7) cancelled:NO];
    [drag end:a at:CGPointMake(90, 9) cancelled:NO];
    check("normal swipe consumes each segment and final endpoint exactly once", x == 80 && y == 7 && deltas == 3);
    x = y = 0; deltas = 0;
    [drag begin:a at:CGPointZero];
    [drag move:a to:CGPointMake(20, 0)];
    [drag end:a at:CGPointMake(20, 0) cancelled:NO];
    check("unchanged end point adds no duplicate aim", x == 20 && y == 0 && deltas == 1);
    x = y = 0; deltas = 0;
    [drag begin:a at:CGPointZero]; [drag begin:b at:CGPointMake(100, 100)];
    [drag move:a to:CGPointMake(5, 3)]; [drag move:b to:CGPointMake(96, 104)];
    [drag end:b at:CGPointMake(500, 500) cancelled:YES];
    [drag end:a at:CGPointMake(7, 8) cancelled:NO];
    check("interleaved fingers keep independent positions and cancellation drops its endpoint", x == 3 && y == 12 && deltas == 3);
    [drag begin:a at:CGPointZero]; [drag clear];
    [drag move:a to:CGPointMake(50, 50)]; [drag end:a at:CGPointMake(80, 80) cancelled:NO];
    check("cleared drag ignores late move and end callbacks", x == 3 && y == 12 && deltas == 3);

    HPOverlay *overlay = [[HPOverlay alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)
        inputHandler:^(const hp_input *event) { halopad_host_post_input(event); }];
    HPLookDrag *surface = [overlay valueForKey:@"lookDrag"];
    count = 0;
    [surface begin:a at:CGPointZero]; [surface end:a at:CGPointMake(20, 0) cancelled:NO];
    check("real overlay forwards short swipe to host mouse motion", count == 1 && events[0].kind == HPI_MOUSEMOVE && events[0].dx > 0);
    UIView *fire = nil;
    for (UIView *v in overlay.subviews) if ([v.accessibilityIdentifier isEqualToString:@"fire"]) fire = v;
    HPLookDrag *fireDrag = [fire valueForKey:@"drag"];
    count = 0;
    [fireDrag begin:a at:CGPointZero]; [fireDrag end:a at:CGPointMake(0, 20) cancelled:NO];
    check("FIRE drag forwards its final displacement to aiming", count == 1 && events[0].kind == HPI_MOUSEMOVE && events[0].dy > 0);
    count = 0;
    [surface begin:a at:CGPointZero]; [fireDrag begin:b at:CGPointZero];
    [overlay clearTouchInput];
    [surface end:a at:CGPointMake(20, 0) cancelled:NO]; [fireDrag end:b at:CGPointMake(0, 20) cancelled:NO];
    check("overlay interruption clears both surface and FIRE drag endpoints", count == 0);

    UIView *scores = nil;
    for (UIView *v in overlay.subviews) if ([v.accessibilityIdentifier isEqualToString:@"scores"]) scores = v;
    HPLookDrag *scoreDrag = [scores valueForKey:@"drag"];
    check("PC scoreboard defaults to hold only", ![[scores valueForKey:@"looks"] boolValue]);
    __block CGFloat scroll = 0;
    overlay.scoreboardScroll = ^(CGFloat dy) { scroll += dy; };
    check("optional roster scrolling enables only the scoreboard drag", [[scores valueForKey:@"looks"] boolValue]);
    count = 0;
    [overlay driveControl:@"scores" down:YES];
    [scoreDrag begin:a at:CGPointZero];
    [scoreDrag move:a to:CGPointMake(100, 80)];
    check("scoreboard drag preserves held action and does not aim", scroll == 80 && count == 1 &&
          events[0].kind == HPI_ACTION && events[0].action == 12 && events[0].down);
    [scoreDrag end:a at:CGPointMake(100, 100) cancelled:NO];
    [overlay driveControl:@"scores" down:NO];
    check("final roster displacement and release delivered once", scroll == 100 && count == 2 && !events[1].down);
    [scoreDrag begin:a at:CGPointZero];
    [overlay clearTouchInput];
    [scoreDrag end:a at:CGPointMake(0, 80) cancelled:NO];
    check("cancel drops unread scoreboard drag endpoint", scroll == 100);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    [scoreDrag begin:a at:CGPointZero]; [scoreDrag move:a to:CGPointMake(0, 80)];
    check("inactive overlay refuses roster scrolling", scroll == 100);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    overlay.scoreboardScroll = nil;
    [scoreDrag begin:a at:CGPointZero]; [scoreDrag end:a at:CGPointMake(0, 80) cancelled:NO];
    check("removing roster adapter restores hold-only and no aim", ![[scores valueForKey:@"looks"] boolValue] && scroll == 100);
}

/* Exercise the real stick geometry without fabricating UIKit touch objects. */
@interface HPStickView : UIView
@property(nonatomic, copy) void (^valueChanged)(float x, float y);
- (void)trackPoint:(CGPoint)p;
- (void)reset;
@end

/* Handler-boundary tokens, not synthesized UIKit events or proof of OS routing. */
@interface HPTestTouch : NSObject
@property(nonatomic) CGPoint point;
- (CGPoint)locationInView:(UIView *)view;
@end
@implementation HPTestTouch
- (CGPoint)locationInView:(UIView *)view { return self.point; }
- (UITouchType)type { return UITouchTypeDirect; }
- (NSTimeInterval)timestamp { return 0; }
@end
static NSSet<UITouch *> *touch_set(HPTestTouch *touch) { return (id)[NSSet setWithObject:touch]; }

static void check_stick_ownership(void)
{
    HPOverlay *overlay = [[HPOverlay alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)];
    overlay.inGame = YES;
    [overlay layoutIfNeeded];
    HPStickView *move = [overlay valueForKey:@"move"], *aim = [overlay valueForKey:@"aim"];
    HPTestTouch *left = [HPTestTouch new], *right = [HPTestTouch new], *stray = [HPTestTouch new];
    left.point = CGPointMake(CGRectGetMidX(move.bounds), 0);
    right.point = CGPointMake(CGRectGetMaxX(aim.bounds), CGRectGetMidY(aim.bounds));
    stray.point = CGPointZero;
    count = 0;
    [move touchesBegan:touch_set(left) withEvent:nil];
    [aim touchesBegan:touch_set(right) withEvent:nil];
    run_for(0.08);
    check("independent MOVE and LOOK handlers can remain held together", actions[19] && count > 1);
    [move touchesEnded:touch_set(left) withEvent:nil];
    int afterMoveRelease = count;
    run_for(0.08);
    check("releasing MOVE keeps the other finger aiming", all_released() && count > afterMoveRelease);
    [move touchesBegan:touch_set(left) withEvent:nil];
    [aim touchesEnded:touch_set(right) withEvent:nil];
    int afterAimRelease = count;
    run_for(0.08);
    check("releasing LOOK keeps movement held without further aim", actions[19] && count == afterAimRelease);
    [aim touchesBegan:touch_set(right) withEvent:nil];
    [overlay clearTouchInput];
    int afterClear = count;
    [move touchesMoved:touch_set(left) withEvent:nil];
    [aim touchesMoved:touch_set(right) withEvent:nil];
    run_for(0.08);
    check("late stick moves after interruption cannot restore movement or aim", all_released() && count == afterClear);
    [move touchesEnded:touch_set(left) withEvent:nil];
    [aim touchesEnded:touch_set(right) withEvent:nil];
    [overlay clearTouchInput];

    [move touchesBegan:touch_set(left) withEvent:nil];
    int afterBegin = count;
    [move touchesBegan:touch_set(stray) withEvent:nil];
    [move touchesMoved:touch_set(stray) withEvent:nil];
    [move touchesEnded:touch_set(stray) withEvent:nil];
    check("another touch cannot steal or release an owned stick", actions[19] && count == afterBegin);
    [move touchesCancelled:touch_set(left) withEvent:nil];
    check("owner cancellation releases movement", all_released());
    afterClear = count;
    [move touchesMoved:touch_set(left) withEvent:nil];
    check("cancelled owner cannot restart movement with a late move", all_released() && count == afterClear);
    [overlay clearTouchInput];

    [move touchesBegan:touch_set(left) withEvent:nil];
    [move reset];
    [move touchesBegan:touch_set(right) withEvent:nil];
    afterBegin = count;
    [move touchesEnded:touch_set(left) withEvent:nil];
    check("old owner ending cannot release a newly started touch", count == afterBegin);
    [move touchesEnded:touch_set(right) withEvent:nil];
    check("new owner ends normally", all_released());
    [overlay clearTouchInput];
}

static void check_stick_tracking(void)
{
    HPStickView *stick = [[HPStickView alloc] initWithFrame:CGRectMake(0, 0, 128, 128)];
    [stick layoutIfNeeded];
    __block float x = 0, y = 0;
    stick.valueChanged = ^(float a, float b) { x = a; y = b; };
    UIView *thumb = stick.subviews.firstObject;
    check("stick corners leave open-screen swipes available", ![stick pointInside:CGPointMake(1, 1) withEvent:nil]);
    check("stick centre and visible rim remain touch targets", [stick pointInside:CGPointMake(64, 64) withEvent:nil] && [stick pointInside:CGPointMake(127, 64) withEvent:nil]);
    [stick trackPoint:CGPointMake(76, 54)];
    check("stick thumb follows the finger inside its travel",
          fabs(thumb.center.x - 76) < 0.01 && fabs(thumb.center.y - 54) < 0.01 && x > 0 && y > 0);
    CGFloat travel = 64 - thumb.bounds.size.width / 2 - 3;
    [stick trackPoint:CGPointMake(64 + travel, 64)];
    check("visible stick rim reaches full input without dragging past the thumb",
          fabs(x - 1) < 0.001 && fabs(y) < 0.001);
    [stick trackPoint:CGPointMake(200, -100)];
    check("drag outside the stick clamps radially and preserves direction",
          fabs(hypot(x, y) - 1) < 0.001 && x > 0 && y > 0 &&
          fabs(hypot(thumb.center.x - 64, thumb.center.y - 64) - travel) < 0.01);
    [stick reset];
    check("stick release returns input and thumb to centre", x == 0 && y == 0 && CGPointEqualToPoint(thumb.center, CGPointMake(64, 64)));
}

static void check_layouts(void)
{
    HPSettings *settings = HPSettings.shared;
    CGFloat savedSize = settings.controlSize;
    BOOL savedHand = settings.leftHanded;
    NSInteger savedSpacing = settings.ringSpacing;
    CGSize screens[] = {{667, 375}, {760, 354}, {844, 390}, {1024, 768}, {1376, 1032}};
    CGFloat sizes[] = {0.7, 1, 1.35};
    int cases = 0, bad = 0, badReach = 0, badGrid = 0, badBadge = 0;
    for (int form = 0; form < 5; form++) for (int hand = 0; hand < 2; hand++)
    for (int size = 0; size < 3; size++) for (int gap = 0; gap < 3; gap++) {
        settings.controlSize = sizes[size]; settings.leftHanded = hand; settings.ringSpacing = gap;
        HPTestOverlay *view = [[HPTestOverlay alloc] initWithFrame:(CGRect){CGPointZero, screens[form]}];
        view.simulatedPhone = form < 3;
        view.simulatedInsets = form < 3 ? UIEdgeInsetsMake(0, 44, 21, 44) : UIEdgeInsetsMake(0, 0, 20, 0);
        view.inGame = YES;
        [view setNeedsLayout]; [view layoutIfNeeded];
        /* Render the actual UIKit controls without presenting a window or loading Halo. */
        const char *renderPath = getenv("HALOPAD_OVERLAY_RENDER_DIR");
        if (renderPath && hand == 0 && size == 1 && gap == 1) {
            UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
            format.scale = 1;
            UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size format:format];
            UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                [[UIColor colorWithRed:0.12 green:0.18 blue:0.21 alpha:1] setFill];
                UIRectFill(view.bounds);
                [view.layer renderInContext:context.CGContext];
            }];
            NSString *path = [@(renderPath) stringByAppendingPathComponent:[NSString stringWithFormat:@"layout-%.0fx%.0f.png", screens[form].width, screens[form].height]];
            check("native overlay preview written", [UIImagePNGRepresentation(image) writeToFile:path atomically:YES]);
        }
        if (hand == 0 && size == 1 && gap == 1) {
            view.availableActions &= ~1u;
            [view driveControl:@"jump" down:YES]; [view driveControl:@"jump" down:NO];
            [view layoutIfNeeded];
            UILabel *hint = [view valueForKey:@"bindingHint"];
            check("binding hint stays inside the safe area and allows touch through",
                  CGRectContainsRect(UIEdgeInsetsInsetRect(view.bounds, view.safeAreaInsets), hint.frame) &&
                  !hint.userInteractionEnabled);
            if (renderPath) {
                UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat]; format.scale = 1;
                UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size format:format];
                UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                    [[UIColor colorWithRed:0.12 green:0.18 blue:0.21 alpha:1] setFill]; UIRectFill(view.bounds);
                    [view.layer renderInContext:context.CGContext];
                }];
                NSString *path = [@(renderPath) stringByAppendingPathComponent:[NSString stringWithFormat:@"binding-%.0fx%.0f.png", screens[form].width, screens[form].height]];
                check("unavailable binding preview written", [UIImagePNGRepresentation(image) writeToFile:path atomically:YES]);
            }
            view.availableActions |= 1;
        }
        NSMutableArray<UIView *> *controls = [NSMutableArray array];
        for (UIView *v in view.subviews)
            if (v.accessibilityIdentifier && !v.hidden) [controls addObject:v];
        BOOL valid = controls.count == 16; /* 13 actions, two sticks, native menu */
        UIView *move = nil, *aim = nil, *fire = nil, *crouch = nil;
        for (UIView *v in controls) {
            if ([v.accessibilityIdentifier isEqualToString:@"move"]) move = v;
            if ([v.accessibilityIdentifier isEqualToString:@"aim"]) aim = v;
            if ([v.accessibilityIdentifier isEqualToString:@"fire"]) fire = v;
            if ([v.accessibilityIdentifier isEqualToString:@"crouch"]) crouch = v;
            valid &= CGRectContainsRect(UIEdgeInsetsInsetRect(view.bounds, view.safeAreaInsets), v.frame) && v.bounds.size.width >= 44 && v.bounds.size.height >= 44;
            for (UIView *other in controls) if (v != other) {
                CGFloat dx = MAX(0, MAX(CGRectGetMinX(v.frame) - CGRectGetMaxX(other.frame), CGRectGetMinX(other.frame) - CGRectGetMaxX(v.frame)));
                CGFloat dy = MAX(0, MAX(CGRectGetMinY(v.frame) - CGRectGetMaxY(other.frame), CGRectGetMinY(other.frame) - CGRectGetMaxY(v.frame)));
                valid &= hypot(dx, dy) >= 7.99; /* an actual gap, not just non-overlap */
            }
            if ([v.accessibilityIdentifier isEqualToString:@"move"] || [v.accessibilityIdentifier isEqualToString:@"aim"])
                valid &= [view hitTest:v.center withEvent:nil] == v;
        }
        CGRect safe = UIEdgeInsetsInsetRect(view.bounds, view.safeAreaInsets);
        NSMutableDictionary<NSString *, UIView *> *byID = [NSMutableDictionary dictionary];
        for (UIView *v in controls) byID[v.accessibilityIdentifier] = v;
        UIView *reload = byID[@"reload"], *melee = byID[@"melee"], *jump = byID[@"jump"];
        UIView *zoom = byID[@"zoom"], *use = byID[@"action"], *swap = byID[@"switch"];
        CGFloat pitch = jump.center.y - melee.center.y;
        BOOL grid = fabs(reload.center.x - melee.center.x) < 0.01 && fabs(melee.center.x - jump.center.x) < 0.01 &&
            fabs(zoom.center.x - use.center.x) < 0.01 && fabs(use.center.x - swap.center.x) < 0.01 &&
            fabs(zoom.center.y - reload.center.y) < 0.01 && fabs(use.center.y - melee.center.y) < 0.01 &&
            fabs(swap.center.y - jump.center.y) < 0.01 && fabs(melee.center.y - reload.center.y - pitch) < 0.01 &&
            fabs(fabs(use.center.x - melee.center.x) - pitch) < 0.01 &&
            fabs(melee.center.y - aim.center.y) < 0.01 &&
            fabs(byID[@"flash"].center.y - move.center.y) < 0.01 &&
            fabs(byID[@"grenade"].center.y - fire.center.y) < 0.01;
        if (!grid) badGrid++;
        BOOL reachable = move && aim && fire && crouch && fabs(move.center.y - aim.center.y) < 0.01 &&
            fabs(move.center.x + aim.center.x - CGRectGetMinX(safe) - CGRectGetMaxX(safe)) < 0.01 &&
            MIN(move.center.x, aim.center.x) - CGRectGetMinX(safe) <= 160 &&
            fabs(fire.center.x - aim.center.x) < 0.01 &&
            fabs(crouch.center.x - move.center.x) < fabs(crouch.center.x - aim.center.x);
        if (form >= 3) {
            /* Conservative bottom-left HUD box for the stock 4:3 tablet viewport. */
            CGRect radar = CGRectMake(0, screens[form].height * 0.83, screens[form].width * 0.15, screens[form].height * 0.17);
            for (UIView *v in controls) reachable &= !CGRectIntersectsRect(v.frame, radar);
        }
        if (!reachable) badReach++;
        CGRect targetBeforeBadge = jump.frame;
        [view setControllerLabel:@"A" hint:@"Select" forControl:@"jump"];
        [jump layoutIfNeeded];
        UILabel *badge = [jump valueForKey:@"controllerLabel"];
        CGPoint badgePoint = [jump convertPoint:badge.center toView:view];
        if (badge.hidden || !CGRectContainsRect(jump.bounds, badge.frame) ||
            !CGRectEqualToRect(jump.frame, targetBeforeBadge) || [view hitTest:badgePoint withEvent:nil] != jump)
            badBadge++;
        cases++;
        if (!valid) { bad++; fprintf(stderr, "layout failed: %.0fx%.0f hand %d size %.2f gap %d controls %lu\n",
                                    screens[form].width, screens[form].height, hand, sizes[size], gap, (unsigned long)controls.count); }
    }
    settings.controlSize = savedSize; settings.leftHanded = savedHand; settings.ringSpacing = savedSpacing;
    fprintf(stderr, "LAYOUT: %d combinations, %d failures\n", cases, bad);
    check("phone/tablet defaults have separate targets, safe bounds and two reachable sticks", bad == 0);
    check("sticks have equal reach, aligned fire, movement-side crouch and tablet radar clearance", badReach == 0);
    check("action columns retain equal spacing and align around the aiming thumb", badGrid == 0);
    check("Xbox label stays in its original tappable target across all phone/tablet layouts", badBadge == 0);
}

void halopad_host_post_input(const hp_input *e)
{
    if (e->kind == HPI_CANCEL_TOUCH) { cancellations++; countAtCancel = count; return; }
    if (count >= 512) abort();
    events[count++] = *e;
    if (e->kind == HPI_ACTION && e->action < 29) actions[e->action] = e->down;
    if (e->kind == HPI_KEY && e->side_vk < 256) held[e->side_vk] = e->down;
}

static void check(const char *name, BOOL ok)
{
    fprintf(stderr, "%s: %s\n", ok ? "PASS" : "FAIL", name);
    failures += !ok;
}

static void run_for(double seconds)
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (end.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:end];
}

static void await_events(int wanted)
{
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:2];
    while (count < wanted && end.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    check("timer delivers expected events before deadline", count == wanted);
}

static BOOL all_released(void)
{
    for (int i = 0; i < 29; i++) if (actions[i]) return NO;
    for (int i = 0; i < 256; i++) if (held[i]) return NO;
    return YES;
}

int main(void)
{
    @autoreleasepool {
        [HPOverlay setTextInputActive:YES];
        [HPOverlay typeText:@"A\n"];
        await_events(6);
        check("normal uppercase text preserves Shift, character and Enter order",
              count == 6 && events[0].side_vk == 0xA0 && events[0].down &&
              events[1].vk == 'A' && events[1].chars[0] == 'A' && events[1].down &&
              events[2].vk == 'A' && !events[2].down &&
              events[3].side_vk == 0xA0 && !events[3].down &&
              events[4].vk == 13 && events[4].chars[0] == '\r' && events[4].down &&
              events[5].vk == 13 && !events[5].down && all_released());

        count = 0;
        [HPOverlay typeText:@"BBBB\n"];
        await_events(2);  /* Shift and B held; all remaining text, including Enter, is pending. */
        check("interruption fixture holds letter and Shift", held['B'] && held[0xA0]);
        [HPOverlay setTextInputActive:NO];
        check("losing focus immediately releases the delivered keys", count == 4 && all_released());
        check("cancellation releases contain no characters",
              !events[2].down && !events[3].down && !events[2].nchars && !events[3].nchars);
        [HPOverlay setTextInputActive:NO];
        check("repeated interruption does not duplicate releases", count == 4);
        [HPOverlay typeText:@"stale\n"];
        [HPOverlay tapKey:0xC0 scan:0x29];
        run_for(0.3);
        check("inactive scene emits no queued text or console key", count == 4);
        [HPOverlay setTextInputActive:YES];
        run_for(0.3);
        check("resuming never replays the partial text or Enter", count == 4);
        [HPOverlay typeText:@"c"];
        await_events(6);
        check("fresh input works after resume without stale Shift",
              events[4].vk == 'C' && events[4].chars[0] == 'c' && events[4].down &&
              events[5].vk == 'C' && !events[5].down && all_released());

        count = 0;
        [HPOverlay typeText:@"never sent\n"];
        [HPOverlay setTextInputActive:NO];
        [HPOverlay setTextInputActive:YES];
        run_for(0.3);
        check("cancel before the first timer tick emits nothing", count == 0);

        HPOverlay *overlay = [[HPOverlay alloc] initWithFrame:CGRectMake(0, 0, 1024, 768)];
        [overlay driveMoveX:0 y:1];
        check("move fixture holds forward", actions[19]);
        check("movement identifies its cancelable touch source", events[count - 1].flags & HPI_TOUCH);
        check("fire fixture finds the actual control", [overlay driveControl:@"fire" down:YES]);
        int cancelsBefore = cancellations;
        [overlay clearTouchInput];
        check("clearing touch input explicitly cancels unread virtual button edges", cancellations == cancelsBefore + 1);
        check("virtual FIRE identifies its touch source", events[count - 2].flags & HPI_TOUCH);
        check("cancel follows all gameplay releases", countAtCancel == count);
        check("movement release keeps its touch source", events[count - 1].flags & HPI_TOUCH);
        check("clearing touch input releases movement and fire",
              all_released() && count >= 4 && events[count - 2].kind == HPI_ACTION && events[count - 2].action == 7 &&
              !events[count - 2].down && events[count - 1].action == 19 && !events[count - 1].down);
        [overlay driveMoveX:0 y:1];
        overlay.analogMoveReady = YES;
        check("switching MOVE sources releases the old keyboard hold", all_released());
        count = 0;
        [overlay driveMoveX:.25f y:.5f];
        check("analog MOVE preserves both partial axes without keyboard events", count == 1 &&
              events[0].kind == HPI_TOUCH_MOVE && events[0].flags == HPI_TOUCH &&
              events[0].move_x == .25f && events[0].move_y == .5f && all_released());
        [overlay clearTouchInput];
        check("clearing analog MOVE sends neutral before cancel", events[count - 1].kind == HPI_TOUCH_MOVE &&
              events[count - 1].move_x == 0 && events[count - 1].move_y == 0 && countAtCancel == count);
        overlay.analogMoveReady = NO;
        [overlay driveMoveX:0 y:1];
        check("unconfigured MOVE retains the existing keyboard route", actions[19]);
        [overlay clearTouchInput];
        count = 0;
        CGFloat scale = 2.2 * HPSettings.shared.lookSensitivity;
        [overlay driveLookX:0.4 / scale y:0];
        [overlay clearTouchInput];
        [overlay driveLookX:0.7 / scale y:0];
        check("canceled look fractions do not spill into the next drag", count == 0);

        [overlay driveAimX:1 y:0];
        run_for(0.15);
        check("held LOOK stick produces continued rightward mouse motion",
              count > 1 && events[0].kind == HPI_MOUSEMOVE && events[0].dx > 0 && events[0].dy == 0);
        check("LOOK identifies its cancelable touch source", events[0].flags & HPI_TOUCH);
        [overlay clearTouchInput];
        int afterRelease = count;
        run_for(0.15);
        check("clearing the LOOK stick stops its continuous motion", count == afterRelease);
        [overlay driveAimX:0.05 y:0.05];
        run_for(0.15);
        check("LOOK dead zone causes no drift", count == afterRelease);
        [overlay clearTouchInput];
        overlay.inGame = YES;
        [overlay driveMoveX:0 y:1];
        [overlay driveControl:@"fire" down:YES];
        [overlay driveAimX:1 y:0];
        UIButton *nativeMenu = [overlay valueForKey:@"menuButton"];
        cancelsBefore = cancellations;
        /* This headless harness has no UIApplication to dispatch sendActions. Check
           the real registration and invoke that registered handler directly. */
        NSArray<NSString *> *menuActions = [nativeMenu actionsForTarget:overlay forControlEvent:UIControlEventMenuActionTriggered];
        check("three-dot menu registers input cancellation before presentation",
              [menuActions containsObject:NSStringFromSelector(@selector(clearTouchInput))]);
        for (NSString *action in menuActions) [overlay performSelector:NSSelectorFromString(action)];
        int afterNativeMenu = count;
        run_for(0.15);
        check("three-dot menu opening releases holds and cancels unread mouse edges",
              all_released() && cancellations == cancelsBefore + 1 && count == afterNativeMenu);
        [overlay setNeedsLayout]; [overlay layoutIfNeeded];
        [overlay driveMoveX:0 y:1];
        [overlay driveControl:@"fire" down:YES];
        [overlay driveAimX:1 y:0];
        NSMutableArray<UIView *> *typingTargets = [NSMutableArray array];
        for (UIView *v in overlay.subviews)
            if (v.accessibilityIdentifier && !v.hidden && ![v.accessibilityIdentifier isEqualToString:@"HaloPadMenu"])
                [typingTargets addObject:v];
        int beforeKeyboard = count;
        overlay.softwareKeyboardVisible = YES;
        int afterKeyboard = count;
        BOOL fireReleased = NO;
        for (int i = beforeKeyboard; i < afterKeyboard; i++)
            fireReleased |= events[i].kind == HPI_ACTION && events[i].action == 7 && !events[i].down;
        run_for(0.15);
        check("opening software keyboard releases held movement, fire and aim",
              fireReleased && all_released() && count == afterKeyboard);
        BOOL hidden = typingTargets.count == 15, restored = YES;
        for (UIView *v in typingTargets) hidden &= v.hidden;
        check("typing hides gameplay targets and disables open-space swipe capture",
              hidden && [overlay hitTest:CGPointMake(512, 384) withEvent:nil] == nil);
        overlay.softwareKeyboardVisible = NO;
        for (UIView *v in typingTargets) restored &= !v.hidden;
        check("keyboard dismissal restores gameplay targets without replaying holds",
              restored && all_released() && count == afterKeyboard);
        UIView *back = nil;
        for (UIView *v in typingTargets)
            if ([v.accessibilityIdentifier isEqualToString:@"menu"]) back = v;
        [overlay driveMoveX:0 y:1];
        [overlay driveControl:@"fire" down:YES];
        [overlay driveAimX:1 y:0];
        int beforeMenu = count;
        overlay.haloMenuVisible = YES;
        int afterMenu = count;
        fireReleased = NO;
        for (int i = beforeMenu; i < afterMenu; i++)
            fireReleased |= events[i].kind == HPI_ACTION && events[i].action == 7 && !events[i].down;
        run_for(0.15);
        check("Halo menu releases movement, fire and continuous LOOK",
              fireReleased && all_released() && count == afterMenu);
        hidden = YES;
        for (UIView *v in typingTargets) if (v != back) {
            hidden &= v.hidden && [overlay hitTest:v.center withEvent:nil] == nil;
        }
        check("Halo menu passes through former gameplay targets and the blank surface",
              hidden && [overlay hitTest:CGPointMake(512, 384) withEvent:nil] == nil);
        check("Halo menu retains a reachable Back control",
              back && !back.hidden && [overlay hitTest:back.center withEvent:nil] == back &&
              [back.accessibilityLabel isEqualToString:@"Back to game or previous menu"]);
        overlay.haloMenuVisible = YES; /* changing to a child widget keeps menu ownership */
        check("child menus do not replay releases", count == afterMenu);
        overlay.softwareKeyboardVisible = YES;
        check("keyboard also hides the menu Back target", back.hidden);
        overlay.softwareKeyboardVisible = NO;
        overlay.haloMenuVisible = NO;
        restored = YES;
        for (UIView *v in typingTargets) restored &= !v.hidden;
        check("resume restores both sticks and actions without replaying input",
              restored && count == afterMenu && [back.accessibilityLabel isEqualToString:@"Pause"]);
        overlay.haloMenuVisible = YES;
        overlay.inGame = NO;
        check("main menu hides the in-game Back target", back.hidden);
        /* Availability is presentation only; the runtime owns press-time releases. */
        overlay.inGame = YES;
        overlay.haloMenuVisible = NO;
        UIView *jumpButton = nil;
        for (UIView *v in overlay.subviews)
            if ([v.accessibilityIdentifier isEqualToString:@"jump"]) jumpButton = v;
        UILabel *hint = [overlay valueForKey:@"bindingHint"];
        count = 0;
        [overlay driveControl:@"jump" down:YES];
        overlay.availableActions &= ~1u;
        [overlay driveControl:@"jump" down:NO];
        check("availability changing during a hold preserves release delivery",
              count == 2 && events[0].action == 0 && events[0].down && !events[1].down && all_released());
        check("unavailable button exposes binding recovery to accessibility",
              [jumpButton.accessibilityValue containsString:@"binding"] &&
              [jumpButton.accessibilityHint containsString:@"Controls Setup"]);
        [overlay driveControl:@"jump" down:YES];
        check("unavailable press names the action and the original settings route",
              !hint.hidden && [hint.text containsString:@"Jump needs"] && [hint.text containsString:@"Pause → Change Settings → Controls Setup"]);
        [overlay driveControl:@"jump" down:NO];
        overlay.availableActions |= 1;
        check("binding recovery removes stale warning without relaunch",
              hint.hidden && jumpButton.accessibilityValue == nil);
        [overlay driveControl:@"jump" down:YES];
        [overlay driveControl:@"jump" down:NO];
        check("recovered binding no longer displays a warning", hint.hidden);
        overlay.availableActions &= ~(1u << 19);
        [overlay driveMoveX:0 y:1];
        check("digital MOVE reports its unavailable direction",
              !hint.hidden && [hint.text containsString:@"Forward needs"]);
        [overlay clearTouchInput];
        check("native menu or focus cancellation clears binding help", hint.hidden);
        overlay.analogMoveReady = YES;
        [overlay driveMoveX:0 y:1];
        check("independent analog MOVE needs no keyboard mapping warning", hint.hidden);
        [overlay clearTouchInput];
        overlay.analogMoveReady = NO;
        overlay.availableActions = (1u << 29) - 1;
        check_drag_tracking();
        check_stick_tracking();
        /* Three-dot menu: complete for a phone player, and a round system button. */
        {
            HPOverlay *m = [[HPOverlay alloc] initWithFrame:CGRectMake(0, 0, 844, 390)];
            UIButton *menu = [m valueForKey:@"menuButton"];
            NSMutableArray<NSString *> *titles = [NSMutableArray array];
            __block __weak void (^weakWalk)(UIMenu *);
            void (^walk)(UIMenu *) = ^(UIMenu *u) {
                for (UIMenuElement *e in u.children) {
                    if (e.title.length) [titles addObject:e.title];
                    if ([e isKindOfClass:UIMenu.class]) weakWalk((UIMenu *)e);
                }
            };
            weakWalk = walk;
            walk(menu.menu);
            check("menu button is drawn by a system configuration (round, keeps its dots after dismissal)",
                  menu.configuration != nil && menu.configuration.image != nil &&
                  menu.configuration.cornerStyle == UIButtonConfigurationCornerStyleCapsule && menu.showsMenuAsPrimaryAction);
            check("menu button never takes a square keyboard-focus ring", !menu.canBecomeFocused);
            for (NSString *need in @[@"Join Server by Address…", @"Recent Servers", @"Controls", @"Look Speed & Touch Settings…",
                                     @"Edit Touch Layout", @"Hide Touch Controls", @"Hide Touch Controls with a Controller",
                                     @"Controller Guide", @"Keyboard & Chat", @"All Chat", @"Team Chat", @"Show Keyboard",
                                     @"Halo Console", @"Display", @"Help", @"Report a Problem…", @"HaloPad on GitHub", @"About HaloPad"])
                check([NSString stringWithFormat:@"menu has %@", need].UTF8String, [titles containsObject:need]);
            check("leave menu is hidden outside a game", ![titles containsObject:@"Open Leave Game Menu…"]);
            m.inGame = YES;
            [titles removeAllObjects];
            walk(menu.menu);
            check("leave menu appears in a game", [titles containsObject:@"Open Leave Game Menu…"]);
            check("the top level stays short: three grouped sections", menu.menu.children.count == 3);
        }
        check_stick_ownership();
        check_layouts();
        check_editor_alignment();
        check_xbox_adapter();
        check_shared_settings();
        check_show_precedence();

        fprintf(stderr, "OVERLAY INPUT: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
        return failures ? 1 : 0;
    }
}
