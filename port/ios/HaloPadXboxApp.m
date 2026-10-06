/* Xbox-only entry point. Uses the same picker, importer and game controller as
 * combined builds, without linking the PC translation or opening its data. */
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "HaloPadOverlay.h"
#include "../runtime/halopad_log.h"

extern UIViewController *HPEngineChooserMake(UIViewController *(^makePC)(void));

/* The shared overlay's PC keyboard fallback is unused here: HPXboxViewController
 * supplies its own inputHandler and controllerConnected callbacks. */
void halopad_host_post_input(const hp_input *event) { (void)event; }
int halopad_app_controller_ready(void) { return 0; }

@interface HPXboxSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation HPXboxSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options
{
    NSError *error = nil;
    AVAudioSession *audio = AVAudioSession.sharedInstance;
    if (![audio setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault
                   options:AVAudioSessionCategoryOptionMixWithOthers error:&error] || ![audio setActive:YES error:&error])
        halopad_log("App: audio session: %s", error.localizedDescription.UTF8String);
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = HPEngineChooserMake(nil);
    [self.window makeKeyAndVisible];
    UIWindowSceneGeometryPreferencesIOS *land = [[UIWindowSceneGeometryPreferencesIOS alloc]
        initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscape];
    [(UIWindowScene *)scene requestGeometryUpdateWithPreferences:land errorHandler:^(NSError *e) {
        halopad_log("App: landscape request: %s", e.localizedDescription.UTF8String);
    }];
}
- (UISceneWindowingControlStyle *)preferredWindowingControlStyleForScene:(UIWindowScene *)scene API_AVAILABLE(ios(26.0))
{
    return UISceneWindowingControlStyle.minimalStyle;
}
@end

@interface HPXboxAppDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation HPXboxAppDelegate
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session
                              options:(UISceneConnectionOptions *)options
{
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:@"HaloPad" sessionRole:session.role];
    configuration.delegateClass = HPXboxSceneDelegate.class;
    return configuration;
}
@end

int main(int argc, char *argv[])
{
    @autoreleasepool {
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *logs = [documents stringByAppendingPathComponent:@"HaloPad Logs"];
        [NSFileManager.defaultManager createDirectoryAtPath:logs withIntermediateDirectories:YES attributes:nil error:nil];
        halopad_log_open([logs stringByAppendingPathComponent:@"HaloPad.log"].fileSystemRepresentation);
        halopad_log("App: Xbox-only build; PC data is untouched");
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(HPXboxAppDelegate.class));
    }
}
