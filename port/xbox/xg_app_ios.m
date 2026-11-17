/*
 * xg_app_ios.m: a stand-alone iOS test app for the Xbox engine (development
 * only; HaloPad's own app will offer the engine from its launch picker).
 * Data: XG_DATA and XG_SAVE from the environment (simctl), else Documents.
 * tvOS apps may write only Caches and tmp, so there the defaults are
 * Caches/data and Caches/data/save. On tvOS the app also serves a web page
 * (xg_admin.m) where the player adds their disc's maps; without maps it shows
 * that page's address instead of starting the game.
 */
#import <UIKit/UIKit.h>
#include "xg_ios.h"
#if TARGET_OS_TV
#import <GameController/GameController.h>
#include "xg_admin.h"

/* On tvOS a controller's B button is also the system's Menu press, which
 * leaves the app when nothing handles it. A GCEventViewController with
 * controller user interaction off keeps controllers' input for the game
 * (GameController, xg_ios.m) and away from UIKit. */
@interface XGViewController : GCEventViewController
@property(nonatomic, strong) UILabel *setupLabel;
@property(nonatomic, strong) NSTimer *setupTimer;
@property(nonatomic, strong) UILabel *pairingLabel;
@end
#else
@interface XGViewController : UIViewController
@end
#endif

@implementation XGViewController
- (void)loadView
{
	self.view = xg_ios_make_view(UIScreen.mainScreen.bounds);
#if TARGET_OS_TV
	self.controllerUserInteractionEnabled = NO;
#endif
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; xg_ios_view_resized(); }
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
#if TARGET_OS_TV
/* Without maps the game cannot start: the screen shows where the web page
 * (xg_admin.m) is, and the game starts once an upload has installed them. */
- (void)showSetup
{
	UILabel *label = [UILabel new];
	label.numberOfLines = 0;
	label.textAlignment = NSTextAlignmentCenter;
	label.textColor = UIColor.whiteColor;
	label.backgroundColor = UIColor.blackColor;
	label.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:label];
	[NSLayoutConstraint activateConstraints:@[
		[label.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
		[label.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
		[label.topAnchor constraintEqualToAnchor:self.view.topAnchor],
		[label.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor] ]];
	self.setupLabel = label;
	[self updateSetup];
	self.setupTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
		(void)timer;
		[self updateSetup];
	}];
}
- (void)updateSetup
{
	NSString *address = xg_admin_address();
	NSString *progress = xg_admin_progress_line();
	NSMutableAttributedString *text = [NSMutableAttributedString new];
	NSDictionary *title = @{ NSFontAttributeName: [UIFont systemFontOfSize:64 weight:UIFontWeightBold], NSForegroundColorAttributeName: UIColor.whiteColor };
	NSDictionary *body = @{ NSFontAttributeName: [UIFont systemFontOfSize:36], NSForegroundColorAttributeName: [UIColor colorWithWhite:0.75 alpha:1] };
	NSDictionary *link = @{ NSFontAttributeName: [UIFont monospacedSystemFontOfSize:52 weight:UIFontWeightSemibold], NSForegroundColorAttributeName: UIColor.whiteColor };
	[text appendAttributedString:[[NSAttributedString alloc] initWithString:@"Add your Halo game data\n\n" attributes:title]];
	if (address) {
		[text appendAttributedString:[[NSAttributedString alloc] initWithString:
			@"On a computer or phone on the same network, open\n\n" attributes:body]];
		[text appendAttributedString:[[NSAttributedString alloc] initWithString:[address stringByAppendingString:@"\n\n"] attributes:link]];
		[text appendAttributedString:[[NSAttributedString alloc] initWithString:
			@"and choose your Halo: Combat Evolved Xbox disc image." attributes:body]];
	} else
		[text appendAttributedString:[[NSAttributedString alloc] initWithString:
			@"Connect the Apple TV to your network to continue." attributes:body]];
	if (progress)
		[text appendAttributedString:[[NSAttributedString alloc] initWithString:[@"\n\n" stringByAppendingString:progress] attributes:body]];
	self.setupLabel.attributedText = text;
}
/* the pairing code a browser asked for (xg_admin.m), over the game; nil hides it */
- (void)showPairingCode:(NSString *)code
{
	[self.pairingLabel removeFromSuperview];
	self.pairingLabel = nil;
	if (!code)
		return;
	UILabel *label = [UILabel new];
	NSMutableAttributedString *text = [NSMutableAttributedString new];
	[text appendAttributedString:[[NSAttributedString alloc] initWithString:@"Homecoming pairing code\n" attributes:@{
		NSFontAttributeName: [UIFont systemFontOfSize:30 weight:UIFontWeightMedium],
		NSForegroundColorAttributeName: [UIColor colorWithWhite:0.8 alpha:1] }]];
	[text appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@ %@",
		[code substringToIndex:3], [code substringFromIndex:3]] attributes:@{
		NSFontAttributeName: [UIFont monospacedDigitSystemFontOfSize:96 weight:UIFontWeightBold],
		NSForegroundColorAttributeName: UIColor.whiteColor, NSKernAttributeName: @6 }]];
	label.attributedText = text;
	label.numberOfLines = 0;
	label.textAlignment = NSTextAlignmentCenter;
	label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.82];
	label.layer.cornerRadius = 28;
	label.layer.masksToBounds = YES;
	label.translatesAutoresizingMaskIntoConstraints = NO;
	[self.view addSubview:label];
	[NSLayoutConstraint activateConstraints:@[
		[label.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:80],
		[label.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-100],
		[label.widthAnchor constraintEqualToConstant:520],
		[label.heightAnchor constraintEqualToConstant:230] ]];
	self.pairingLabel = label;
}
#endif
- (void)startGameWithData:(NSString *)data save:(NSString *)save
{
	NSString *image = [NSBundle.mainBundle pathForResource:@"halo_guest" ofType:@"elf"];
	if (!image || xg_ios_start(image.fileSystemRepresentation, data.fileSystemRepresentation, save.fileSystemRepresentation))
		NSLog(@"HaloPad Xbox engine did not start");
#if TARGET_OS_TV
	else
		xg_admin_set_game_running(1);
#endif
}
- (void)viewDidAppear:(BOOL)animated
{
	static int started;
#if TARGET_OS_TV
	NSString *caches = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
	NSString *documents = [caches stringByAppendingPathComponent:@"data"];
#else
	NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
#endif
	NSDictionary *environment = NSProcessInfo.processInfo.environment;
	NSString *data = environment[@"XG_DATA"] ?: documents;
	NSString *save = environment[@"XG_SAVE"] ?: [documents stringByAppendingPathComponent:@"save"];
	[super viewDidAppear:animated];
	if (started++)
		return;
#if TARGET_OS_TV
	{
		__weak XGViewController *weakSelf = self;
		xg_admin_start(data, caches, 8080, ^{
			XGViewController *controller = weakSelf;
			if (!controller || !controller.setupLabel)
				return;     /* already playing: the page asks for a restart */
			[controller.setupTimer invalidate];
			[controller.setupLabel removeFromSuperview];
			controller.setupLabel = nil;
			[controller startGameWithData:data save:save];
		}, ^(NSString *code) {
			[weakSelf showPairingCode:code];
		});
		[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillEnterForegroundNotification object:nil
			queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
				(void)note;
				xg_admin_reopen();
			}];
		if (!xg_admin_maps_present(data)) {
			[self showSetup];
			return;
		}
	}
#endif
	[self startGameWithData:data save:save];
}
@end

/* Apps built with the iOS and tvOS 27 SDKs must use the scene lifecycle:
 * UIKit stops an app that makes its window from the application delegate. */
@interface XGSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation XGSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options
{
	self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
	self.window.rootViewController = [XGViewController new];
	[self.window makeKeyAndVisible];
}
@end

@interface XGAppDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation XGAppDelegate
- (UISceneConfiguration *)application:(UIApplication *)application
	configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options
{
	UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];
	configuration.delegateClass = XGSceneDelegate.class;
	return configuration;
}
@end

int main(int argc, char *argv[])
{
	@autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass([XGAppDelegate class])); }
}
