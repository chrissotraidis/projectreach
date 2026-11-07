#import <UIKit/UIKit.h>

/* A passive card visible only in multiplayer menus; only History takes input.
   Attach as a child of the Xbox game controller after configuring the store. */
FOUNDATION_EXPORT UIViewController *HPHaloProgressControllerMake(void (^willPresentHistory)(void));

/* Native Stats must suspend guest input through the whole sheet lifecycle,
   including Done, profile-change dismissal and interactive swipe dismissal. */
FOUNDATION_EXPORT UIViewController *HPHaloProgressControllerMakeWithDismissal(
    void (^willPresentHistory)(void), void (^didDismissHistory)(void));
