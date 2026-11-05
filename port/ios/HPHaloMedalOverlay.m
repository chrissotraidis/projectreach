#import "HPHaloMedalOverlay.h"
#import "HPHaloMedalCatalog.h"
#import "HPHaloTheme.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#include <stdio.h>
#include <stdlib.h>

static __weak UIViewController *HPBoundGameController;
static BOOL (^HPGameCanPresent)(void);

/* Presentation stays in the existing game view. It creates no window, takes no
 * focus, and never participates in mouse, touch, or controller input. */
@interface HPHaloMedalHUDView : UIView
@property(nonatomic,strong) UIStackView *stack;
@property(nonatomic,strong) HPHaloPanelView *panel;
@property(nonatomic,copy) NSArray<NSNumber *> *shownMedals;
- (void)showMedalIDs:(NSArray<NSNumber *> *)medalIDs;
@end
@implementation HPHaloMedalHUDView
- (instancetype)initWithFrame:(CGRect)frame {
    if(!(self=[super initWithFrame:frame]))return nil;
    self.userInteractionEnabled=NO;
    self.accessibilityIdentifier=@"halopad.medal.hud";
    self.backgroundColor=UIColor.clearColor;
    self.panel=[HPHaloPanelView new];
    self.panel.chamfer=14;self.panel.showsBrackets=YES;
    self.panel.fillColor=[UIColor colorWithRed:0.015 green:0.035 blue:0.06 alpha:0.86];
    self.panel.strokeColor=[HPHaloColorAccent() colorWithAlphaComponent:0.5];
    self.panel.edgeColor=HPHaloColorAccent();
    self.panel.glowColor=[HPHaloColorAccent() colorWithAlphaComponent:0.35];
    self.panel.userInteractionEnabled=NO;
    self.panel.translatesAutoresizingMaskIntoConstraints=NO;
    [self addSubview:self.panel];
    self.stack=[UIStackView new];self.stack.axis=UILayoutConstraintAxisVertical;
    self.stack.spacing=8;self.stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self addSubview:self.stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.panel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [self.panel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [self.panel.topAnchor constraintEqualToAnchor:self.topAnchor],
        [self.panel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [self.stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-10]]];
    return self;
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event { return NO; }
- (void)showMedalIDs:(NSArray<NSNumber *> *)medalIDs {
    for(UIView *v in self.stack.arrangedSubviews){[self.stack removeArrangedSubview:v];[v removeFromSuperview];}
    NSMutableArray *names=[NSMutableArray array];
    BOOL animate=!UIAccessibilityIsReduceMotionEnabled();
    for(NSNumber *number in medalIDs) {
        NSDictionary *medal=HPHaloMedalForID(number.unsignedIntegerValue);if(!medal)continue;
        BOOL spree=number.unsignedIntegerValue>9;
        UIColor *tone=spree ? HPHaloColorGold() : HPHaloColorAccent();
        BOOL fresh=![self.shownMedals containsObject:number];
        UIStackView *row=[UIStackView new];row.axis=UILayoutConstraintAxisHorizontal;
        row.spacing=12;row.alignment=UIStackViewAlignmentCenter;
        UIView *holder=[UIView new];
        HPHaloGlowView *glow=[HPHaloGlowView new];glow.glowColor=tone;
        UIImageView *badge=[[UIImageView alloc]initWithImage:HPHaloMedalBadgeImage(number.unsignedIntegerValue,64)];
        badge.contentMode=UIViewContentModeScaleAspectFit;
        for(UIView *view in @[glow,badge]){view.translatesAutoresizingMaskIntoConstraints=NO;[holder addSubview:view];}
        [NSLayoutConstraint activateConstraints:@[
            [holder.widthAnchor constraintEqualToConstant:60],[holder.heightAnchor constraintEqualToConstant:64],
            [badge.leadingAnchor constraintEqualToAnchor:holder.leadingAnchor],[badge.trailingAnchor constraintEqualToAnchor:holder.trailingAnchor],
            [badge.topAnchor constraintEqualToAnchor:holder.topAnchor],[badge.bottomAnchor constraintEqualToAnchor:holder.bottomAnchor],
            [glow.centerXAnchor constraintEqualToAnchor:holder.centerXAnchor],[glow.centerYAnchor constraintEqualToAnchor:holder.centerYAnchor],
            [glow.widthAnchor constraintEqualToConstant:104],[glow.heightAnchor constraintEqualToConstant:104]]];
        [row addArrangedSubview:holder];
        UIStackView *text=[UIStackView new];text.axis=UILayoutConstraintAxisVertical;text.spacing=1;
        UILabel *caption=HPHaloLabel(HPHaloDisplayFont(11,UIFontWeightHeavy,UIFontTextStyleCaption2,16),tone,1);
        HPHaloSetCaps(caption,spree?@"Spree medal":@"Medal earned",2.6);
        UILabel *name=HPHaloLabel(HPHaloDisplayFont(23,UIFontWeightHeavy,UIFontTextStyleTitle2,28),UIColor.whiteColor,2);
        HPHaloSetCaps(name,medal[@"name"],1.4);
        name.adjustsFontSizeToFitWidth=YES;name.minimumScaleFactor=0.7;
        name.layer.shadowColor=tone.CGColor;name.layer.shadowRadius=8;name.layer.shadowOpacity=0.55f;name.layer.shadowOffset=CGSizeZero;
        [text addArrangedSubview:caption];[text addArrangedSubview:name];[row addArrangedSubview:text];
        [self.stack addArrangedSubview:row];[names addObject:medal[@"name"]];
        if(fresh && animate) {
            /* The newest medal punches in and flares; earlier ones stay still. */
            badge.transform=CGAffineTransformMakeScale(1.9,1.9);badge.alpha=0;
            glow.transform=CGAffineTransformMakeScale(0.4,0.4);glow.alpha=1;
            text.alpha=0;text.transform=CGAffineTransformMakeTranslation(-10,0);
            [UIView animateWithDuration:0.42 delay:0 usingSpringWithDamping:0.62 initialSpringVelocity:0.4 options:0 animations:^{
                badge.transform=CGAffineTransformIdentity;badge.alpha=1;
            } completion:nil];
            [UIView animateWithDuration:0.22 delay:0.06 options:UIViewAnimationOptionCurveEaseOut animations:^{
                text.alpha=1;text.transform=CGAffineTransformIdentity;
            } completion:nil];
            [UIView animateWithDuration:0.55 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                glow.transform=CGAffineTransformMakeScale(1.25,1.25);glow.alpha=0.55;
            } completion:nil];
        }
    }
    self.shownMedals=medalIDs;
    BOOL anySpree=NO;for(NSNumber *number in medalIDs)if(number.unsignedIntegerValue>9)anySpree=YES;
    UIColor *edge=anySpree && medalIDs.count==1 ? HPHaloColorGold() : HPHaloColorAccent();
    self.panel.edgeColor=edge;self.panel.strokeColor=[edge colorWithAlphaComponent:0.5];
    self.panel.glowColor=[edge colorWithAlphaComponent:0.35];
    self.isAccessibilityElement=YES;self.accessibilityLabel=[names componentsJoinedByString:@", "];
}
@end

static UIView *HPActiveGameHost(void) {
    UIViewController *game=HPBoundGameController;
    UIView *host=game.viewIfLoaded;
    if(!game||!host||host.hidden||!host.window||host.window.hidden||host.window.alpha<=0||
       host.window.windowLevel!=UIWindowLevelNormal||
       host.window.windowScene.activationState!=UISceneActivationStateForegroundActive||
       !HPGameCanPresent||!HPGameCanPresent())return nil;
    for(UIViewController *owner=game;owner;owner=owner.parentViewController)
        if(owner.presentedViewController&&!owner.presentedViewController.isBeingDismissed)return nil;
    /* A two-badge stack cannot be presented usefully in a collapsed viewport. */
    if(CGRectGetHeight(host.safeAreaLayoutGuide.layoutFrame)<200)return nil;
    return host;
}

@interface HPHaloMedalHUDPresenter : NSObject
@property(nonatomic,strong) NSMutableOrderedSet<NSString *> *seen;
@property(nonatomic,strong) NSMutableArray<NSNumber *> *activeMedals;
@property(nonatomic,strong) HPHaloMedalHUDView *card;
@property(nonatomic,strong) NSTimer *dismissTimer;
@property(nonatomic,strong) NSTimer *visibilityTimer;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger displayedCount;
+ (instancetype)shared;
- (void)observePath:(NSString *)path event:(HPCareerStatsEventV1)event received:(CFTimeInterval)received;
@end
@implementation HPHaloMedalHUDPresenter
+ (instancetype)shared {
    static HPHaloMedalHUDPresenter *presenter;static dispatch_once_t once;
    dispatch_once(&once,^{presenter=[self new];});return presenter;
}
- (instancetype)init {
    if(!(self=[super init]))return nil;
    _seen=[NSMutableOrderedSet new];_activeMedals=[NSMutableArray new];
    for(NSString *name in @[UIApplicationWillResignActiveNotification,UIApplicationDidEnterBackgroundNotification,UISceneWillDeactivateNotification])
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(cancelPresentation) name:name object:nil];
    return self;
}
- (void)cancelPresentation {
    self.generation++;
    [self.dismissTimer invalidate];self.dismissTimer=nil;
    [self.visibilityTimer invalidate];self.visibilityTimer=nil;
    [self.card.layer removeAllAnimations];[self.card removeFromSuperview];self.card=nil;
    [self.activeMedals removeAllObjects];
}
- (void)observePath:(NSString *)path event:(HPCareerStatsEventV1)e received:(CFTimeInterval)received {
    NSAssert(NSThread.isMainThread,@"Medal presentation must be on main");
    NSString *key=[NSString stringWithFormat:@"%@/%u/%u/%u/%u/%u/%u/%u",path,e.session_seed,e.game_number,e.map_crc,e.local_player,e.event_id,e.reserved,e.flags];
    if([self.seen containsObject:key])return;
    [self.seen addObject:key];if(self.seen.count>4096)[self.seen removeObjectAtIndex:0];
    /* Storage retries never replay an animation, and a blocked/inactive UI never
     * catches up by covering gameplay with medals from several seconds ago. */
    if(CACurrentMediaTime()-received>2.0||NSDate.date.timeIntervalSince1970-e.mode_id>3.0)return;
    UIView *host=HPActiveGameHost();if(!host){[self cancelPresentation];return;}
    if(self.card&&self.card.superview!=host)[self cancelPresentation];
    NSDictionary *medal=HPHaloMedalForID(e.reserved);if(!medal)return;
    NSString *category=medal[@"category"];
    for(NSNumber *prior in [self.activeMedals copy])
        if([HPHaloMedalForID(prior.unsignedIntegerValue)[@"category"] isEqual:category])
            [self.activeMedals removeObject:prior];
    [self.activeMedals addObject:@(e.reserved)];
    BOOL newlyVisible=self.card==nil;
    if(newlyVisible) {
        self.card=[[HPHaloMedalHUDView alloc]initWithFrame:CGRectZero];
        self.card.translatesAutoresizingMaskIntoConstraints=NO;
        [host addSubview:self.card];
        UILayoutGuide *safe=host.safeAreaLayoutGuide;
        NSLayoutConstraint *width=[self.card.widthAnchor constraintEqualToConstant:300];width.priority=999;
        NSLayoutConstraint *top=[self.card.topAnchor constraintEqualToAnchor:safe.topAnchor constant:12];top.priority=999;
        [NSLayoutConstraint activateConstraints:@[
            [self.card.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
            [self.card.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:12],
            [self.card.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-12],
            [self.card.topAnchor constraintGreaterThanOrEqualToAnchor:safe.topAnchor constant:8],
            [self.card.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor constant:-8],top,width]];
        __weak typeof(self) weakSelf=self;
        self.visibilityTimer=[NSTimer scheduledTimerWithTimeInterval:0.15 repeats:YES block:^(NSTimer *timer){
            HPHaloMedalHUDPresenter *owner=weakSelf;
            if(owner&&HPActiveGameHost()!=owner.card.superview)[owner cancelPresentation];
        }];
        [NSRunLoop.mainRunLoop addTimer:self.visibilityTimer forMode:NSRunLoopCommonModes];
    }
    [self.card.layer removeAllAnimations];self.card.alpha=1;
    self.card.transform=CGAffineTransformIdentity;
    [self.card showMedalIDs:self.activeMedals];[host layoutIfNeeded];
    if(newlyVisible) {
        self.card.alpha=0;
        if(!UIAccessibilityIsReduceMotionEnabled())self.card.transform=CGAffineTransformScale(CGAffineTransformMakeTranslation(0,-14),0.94,0.94);
        [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.3 options:0 animations:^{self.card.alpha=1;self.card.transform=CGAffineTransformIdentity;} completion:nil];
    }
    self.displayedCount++;
    if(UIAccessibilityIsVoiceOverRunning())UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,medal[@"name"]);
    if(getenv("HALOPAD_MEDAL_TRACE"))fprintf(stderr,"HALOPAD_MEDAL_HUD {\"medal_id\":%u,\"shown\":true}\n",e.reserved);
    [self.dismissTimer invalidate];self.generation++;NSUInteger generation=self.generation;
    __weak typeof(self) weakSelf=self;
    self.dismissTimer=[NSTimer scheduledTimerWithTimeInterval:2.6 repeats:NO block:^(NSTimer *timer){
        HPHaloMedalHUDPresenter *owner=weakSelf;if(!owner||owner.generation!=generation)return;
        [UIView animateWithDuration:0.28 animations:^{owner.card.alpha=0;
            if(!UIAccessibilityIsReduceMotionEnabled())owner.card.transform=CGAffineTransformMakeTranslation(0,-10);} completion:^(BOOL finished){
            if(owner.generation==generation)[owner cancelPresentation];
        }];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.dismissTimer forMode:NSRunLoopCommonModes];
}
@end

void HPHaloMedalOverlayAttach(UIViewController *gameController, BOOL (^canPresent)(void)) {
    NSCAssert(NSThread.isMainThread,@"Bind the medal presenter on main");
    [[HPHaloMedalHUDPresenter shared] cancelPresentation];
    HPBoundGameController=gameController;
    HPGameCanPresent=[canPresent copy];
}

void HPHaloMedalOverlayObserve(NSString *guestPath,const HPCareerStatsEventV1 *event) {
    if(!event||event->version!=1||event->size!=sizeof(*event)||event->kind!=7||
       !event->event_id||event->event_id>event->kills||event->kills>INT32_MAX||
       event->local_player>=4||event->reserved<1||event->reserved>15||event->result||
       (event->flags&~3U)||![guestPath isKindOfClass:NSString.class]||guestPath.length>260)return;
    /* Kind7 carries the original UTC award time in mode_id. A delayed storage
     * retry may save the medal, but it must not replay an old HUD animation. */
    NSTimeInterval age=NSDate.date.timeIntervalSince1970-event->mode_id;
    if(!event->mode_id||age>3.0||age < -5.0)return;
    HPCareerStatsEventV1 copy=*event;NSString *path=[guestPath copy];CFTimeInterval received=CACurrentMediaTime();
    dispatch_async(dispatch_get_main_queue(),^{
        [[HPHaloMedalHUDPresenter shared] observePath:path event:copy received:received];
    });
}
