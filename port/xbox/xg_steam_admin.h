/* xg_steam_admin.h: Steam sign-in from the admin web page (xg_admin.m).
 * Implemented by xg_steam_admin.inc, which scripts/xbox/gen-host-steam.py
 * appends to its copy of upstream's steam_downloads.c, where the session is. */
#ifndef XG_STEAM_ADMIN_H
#define XG_STEAM_ADMIN_H

enum xg_steam_admin_state {
	XG_STEAM_OUT,          /* signed out */
	XG_STEAM_CONNECTING,   /* checking the name and password */
	XG_STEAM_GUARD,        /* waiting: approval in the Steam app, or a Steam Guard code */
	XG_STEAM_SIGNING_IN,   /* approved; opening the session */
	XG_STEAM_IN,           /* signed in */
	XG_STEAM_UNAVAILABLE
};

/* steam_cm.h's STEAM_GUARD_* bits, as the page needs them */
enum {
	XG_STEAM_GUARD_EMAIL_CODE = 1 << 2,
	XG_STEAM_GUARD_DEVICE_CODE = 1 << 3,
	XG_STEAM_GUARD_DEVICE_CONFIRMATION = 1 << 4,
	XG_STEAM_GUARD_EMAIL_CONFIRMATION = 1 << 5
};

struct xg_steam_admin_status {
	int state;                 /* enum xg_steam_admin_state */
	unsigned confirmations;    /* while XG_STEAM_GUARD */
	char account[64];
	char message[256];
};

/* data_root is the engine's (the game's HALO_DATA_ROOT). The first call
 * loads a saved sign-in and resumes it, as opening the game's Steam screen does. */
void xg_steam_admin_status(char const *data_root, struct xg_steam_admin_status *status);
/* 1 when a sign-in by name and password started (only while signed out) */
int xg_steam_admin_sign_in(char const *data_root, char const *account, char const *password);
/* a Steam Guard code; 1 when a sign-in was waiting for one */
int xg_steam_admin_code(char const *code);
/* stops a sign-in under way */
void xg_steam_admin_cancel(void);
/* 1 when signed in and now signing out */
int xg_steam_admin_sign_out(void);

#endif
