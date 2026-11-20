/*
 * xg_app_ios.m: a stand-alone iOS test app for the Xbox engine (development
 * only; HaloPad's own app will offer the engine from its launch picker).
 * Data: XG_DATA and XG_SAVE from the environment (simctl), else Documents.
 */
#import <UIKit/UIKit.h>
#include "xg_ios.h"

@interface XGViewController : UIViewController
@end

@implementation XGViewController
- (void)loadView { self.view = xg_ios_make_view(UIScreen.mainScreen.bounds); }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; xg_ios_view_resized(); }
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? UIInterfaceOrientationMaskAll : UIInterfaceOrientationMaskLandscape; }
- (void)viewDidAppear:(BOOL)animated
{
	static int started;
	NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
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

@interface XGAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation XGAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
	self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
	self.window.rootViewController = [XGViewController new];
	[self.window makeKeyAndVisible];
	return YES;
}
@end

int main(int argc, char *argv[])
{
	@autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass([XGAppDelegate class])); }
}
