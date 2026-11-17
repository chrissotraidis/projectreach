/* xg_admin.h: the app's web page on the local network (xg_admin.m), where a
 * player uploads their Halo Xbox disc image from a computer or phone. */
#ifndef XG_ADMIN_H
#define XG_ADMIN_H
#import <Foundation/Foundation.h>

/* Starts the web server on port (0 picks 8080) and advertises it with Bonjour
 * as "_http._tcp". data_root is the engine's data folder (maps go in
 * data_root/maps); work_root holds uploads while they are imported.
 * maps_ready runs on the main queue each time an import installs maps.
 * pairing runs on the main queue with the six-digit code a browser must type
 * to pair, to be shown on the TV, and with nil when it should be hidden.
 * 0 on success. */
int xg_admin_start(NSString *data_root, NSString *work_root, int port, void (^maps_ready)(void),
	void (^pairing)(NSString *code));
/* nonzero when data_root/maps/ui.map exists */
int xg_admin_maps_present(NSString *data_root);
/* call when the app returns to the foreground: the listening socket is opened
 * again, since the system may have taken it while the app was suspended */
void xg_admin_reopen(void);
/* tell the page whether the game is running (new maps then need a restart) */
void xg_admin_set_game_running(int running);
/* "http://192.168.1.20:8080", or nil while the device has no network address */
NSString *xg_admin_address(void);
/* one line for the TV screen about the import in progress, or nil */
NSString *xg_admin_progress_line(void);

#endif
