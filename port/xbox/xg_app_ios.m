/*
 * xg_app_ios.m: a stand-alone iOS test app for the Xbox engine (development
 * only; HaloPad's own app will offer the engine from its launch picker).
 * Data: XG_DATA and XG_SAVE from the environment (simctl), else Documents.
 * tvOS apps may write only Caches and tmp, so there the defaults are
 * Caches/data and Caches/data/save.
 */
#import <UIKit/UIKit.h>
#include "xg_ios.h"
#if TARGET_OS_TV
#import <GameController/GameController.h>

/* On tvOS a controller's B button and the Siri Remote's Back are the system
 * Menu press, which quits an app when nothing handles it. This controller
 * handles every press itself (pressesBegan below) and passes none on.
 * Controller UI interaction stays on: with it off, tvOS 27 kept the Siri
 * Remote's presses from both UIKit and GameController. */
@interface XGViewController : GCEventViewController
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
	/* tvOS hands the Siri Remote's presses to the app through UIKit
	 * (pressesBegan below), and controllers' too */
	self.controllerUserInteractionEnabled = YES;
#endif
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; xg_ios_view_resized(); }
#if TARGET_OS_TV
/* The Siri Remote's arrows, click, Back and Play/Pause as UIKit delivers them:
 * player 1's menu buttons (xg_ios.m). Not passed on, so Back does not leave
 * the app. */
- (void)remotePresses:(NSSet<UIPress *> *)presses down:(int)down
{
	for (UIPress *press in presses)
		xg_ios_remote_press((int)press.type, press.key ? (long)press.key.keyCode : 0, down);
}
- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event { [self remotePresses:presses down:1]; }
- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event { [self remotePresses:presses down:0]; }
- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event { [self remotePresses:presses down:0]; }
#endif
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (void)viewDidAppear:(BOOL)animated
{
	static int started;
#if TARGET_OS_TV
	NSString *documents = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
		stringByAppendingPathComponent:@"data"];
#else
	NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
#endif
	NSDictionary *environment = NSProcessInfo.processInfo.environment;
	NSString *data = environment[@"XG_DATA"] ?: documents;
	NSString *save = environment[@"XG_SAVE"] ?: [documents stringByAppendingPathComponent:@"save"];
	NSString *image = [NSBundle.mainBundle pathForResource:@"halo_guest" ofType:@"elf"];
	[super viewDidAppear:animated];
	if (started++)
		return;
	if (!image || xg_ios_start(image.fileSystemRepresentation, data.fileSystemRepresentation, save.fileSystemRepresentation))
		NSLog(@"HaloPad Xbox engine did not start");
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
