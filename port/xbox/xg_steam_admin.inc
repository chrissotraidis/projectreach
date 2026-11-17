
/* ---------- HaloPad: Steam sign-in from the admin web page
 *
 * Appended by scripts/xbox/gen-host-steam.py to its copy of steam_downloads.c
 * (xg_steam_admin.h). These drive the same session thread the game's Steam
 * screen does, through the same fields its text boxes fill. The one change to
 * upstream's code is that a sign-in begun here is not cancelled because the
 * game's Steam screen is closed (xg_admin_sign_in_open). */

#include "xg_steam_admin.h"

void xg_steam_admin_status(char const *data_root, struct xg_steam_admin_status *status)
{
	static int resumed;

	threads_start(data_root);
	pthread_mutex_lock(&steam.session_lock);
	pthread_mutex_lock(&steam.state_lock);
	if (!resumed)
	{
		resumed = 1;
		if (steam.state == SESSION_OUT && steam.token[0])
		{
			steam.want_resume = 1;
			wake();
		}
	}
	status->state = (int)steam.state;
	status->confirmations = steam.confirmations;
	snprintf(status->account, sizeof(status->account), "%s",
		steam.state == SESSION_IN || steam.state == SESSION_SIGNING_IN || steam.token[0] ? steam.account : "");
	snprintf(status->message, sizeof(status->message), "%s", steam.message);
	if (steam.state == SESSION_OUT || steam.state == SESSION_IN)
		xg_admin_sign_in_open = 0;
	pthread_mutex_unlock(&steam.state_lock);
	pthread_mutex_unlock(&steam.session_lock);
}

int xg_steam_admin_sign_in(char const *data_root, char const *account, char const *password)
{
	int started = 0;

	threads_start(data_root);
	pthread_mutex_lock(&steam.state_lock);
	if (steam.state == SESSION_OUT && !steam.want_password && account[0] && password[0] &&
		strlen(account) < TEXT_SIZE && strlen(password) < TEXT_SIZE)
	{
		snprintf(steam.typed_account, sizeof(steam.typed_account), "%s", account);
		snprintf(steam.typed_password, sizeof(steam.typed_password), "%s", password);
		steam.want_password = 1;
		steam.message[0] = 0;
		xg_admin_sign_in_open = 1;
		started = 1;
		wake();
	}
	pthread_mutex_unlock(&steam.state_lock);
	return started;
}

int xg_steam_admin_code(char const *code)
{
	int taken = 0;

	pthread_mutex_lock(&steam.state_lock);
	if (steam.state == SESSION_GUARD && code[0] && strlen(code) < TEXT_SIZE)
	{
		snprintf(steam.typed_code, sizeof(steam.typed_code), "%s", code);
		steam.code_typed = 1;
		steam.message[0] = 0;
		taken = 1;
	}
	pthread_mutex_unlock(&steam.state_lock);
	return taken;
}

void xg_steam_admin_cancel(void)
{
	pthread_mutex_lock(&steam.state_lock);
	if (steam.state == SESSION_CONNECTING || steam.state == SESSION_GUARD)
		steam.cancel_sign_in = 1;
	pthread_mutex_unlock(&steam.state_lock);
}

int xg_steam_admin_sign_out(void)
{
	int taken = 0;

	pthread_mutex_lock(&steam.state_lock);
	if (steam.state == SESSION_IN)
	{
		steam.want_sign_out = 1;
		taken = 1;
		wake();
	}
	pthread_mutex_unlock(&steam.state_lock);
	return taken;
}
