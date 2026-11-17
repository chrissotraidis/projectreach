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

/* On tvOS a controller's B button is also the system's Menu press, which
 * leaves the app when nothing handles it. A GCEventViewController with
 * controller user interaction off keeps controllers' input for the game
 * (GameController, xg_ios.m) and away from UIKit. */
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
	self.controllerUserInteractionEnabled = NO;
#endif
}
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; xg_ios_view_resized(); }
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
