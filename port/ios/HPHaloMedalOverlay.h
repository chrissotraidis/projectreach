#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "HPCareerStatsEvent.h"

/* Bind to the actual game's controller and menu/input state on the main queue.
 * The controller is weakly held; the eligibility block must also capture weakly.
 * Medals use its existing view and never create a window or capture input. */
void HPHaloMedalOverlayAttach(UIViewController *gameController, BOOL (^canPresent)(void));

/* Called from the private local event bridge. Never waits for the UI thread. */
void HPHaloMedalOverlayObserve(NSString *guestPath, const HPCareerStatsEventV1 *event);
