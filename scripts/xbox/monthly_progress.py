"""Pinned OpenCE337 confirmed-kill XP and passive multiplayer-menu bridge.

The native host owns durable deduplication, calendar months, history and ranks.
This module changes neither network messages nor the game's statistics/input.
"""
import hashlib
from pathlib import Path

NAME = 'kill-xp-monthly-v1'
GAME = Path('source/game/game_engine.c')
MENU = Path('port/linux/game/menu_functions.c')
WIDGET = Path('source/interface/ui_widget.c')
SAVES = Path('source/saved games/saved_game_files.c')
IMPORTS = Path('port/android/host_imports.list')
SHA256 = {
    GAME: '9432acd8f39c9f80f476919e9fe4da7aac968193db98d3fca27229a0144bd6e9',
    MENU: 'cb21eec2264befbfba966da69a322130d74bc1bf20e1290dc9ebe263d7035d16',
    WIDGET: '5b51dc768edbbbba07a2550bea90718cd35a9f01494a96211c44afff49af4e1f',
    SAVES: '89e44b3e3e5831895e8dc24c832d8704dfb035048541dee16d794f9a5e07bf60',
    IMPORTS: 'f373b1ba6fc340334bb423f539135cf4e86840d14848786ae3208bdeb6ff1db2',
}
IMPORT_NAMES = (b'host_halopad_progress_kill_v1', b'host_halopad_progress_menu_v1')
IMPORT_APPEND = (b'\n# Native monthly progression; no network protocol changes.\n' +
                 b'\n'.join(IMPORT_NAMES) + b'\n')
GAME_INCLUDE = b'#include "networking/network_game_globals.h"\n'
GAME_INCLUDES = GAME_INCLUDE + (
    b'#include "networking/network_client_manager.h" /* port: session identity */\n'
    b'#include "cache/cache_files.h" /* port: current map checksum */\n')
UPDATE = b'void game_engine_update(\n\tvoid)\n{\n'
QUALIFIED = b'\tplayer_kill = !friendly_fire && valid_players && !same_player;\n'
QUALIFIED_WITH_AWARD = QUALIFIED + (
    b'\thalopad_progress_note_kill(player_kill, killing_player_index, dead_player_index, dead_player);\n')

CORE = br'''/* port: confirmed events, not a score/statistics snapshot. The native
host commits/deduplicates these six little-endian 32-bit words durably.
Only simulation/UI thread code accesses this queue. Paths and keys remain
frozen on retries, even across map changes; the host tracks profile UUIDs. */
extern unsigned int host_halopad_progress_kill_v1(char const *path, unsigned int path_length,
	void const *event, unsigned int event_length);
void platform_log(char const *format, ...);

struct halopad_progress_event
{
	unsigned int version, size;
	unsigned int session_seed, game_number, map_crc, victim_full_datum;
};
typedef char halopad_progress_word_size[sizeof(unsigned int) == 4 ? 1 : -1];
typedef char halopad_progress_event_size[sizeof(struct halopad_progress_event) == 24 ? 1 : -1];

#define HALOPAD_PROGRESS_PENDING 256
#define HALOPAD_PROGRESS_PATH 261
struct halopad_progress_pending
{
	struct halopad_progress_event event;
	unsigned int path_length;
	char path[HALOPAD_PROGRESS_PATH];
};
static struct halopad_progress_pending halopad_progress_pending[HALOPAD_PROGRESS_PENDING];
static unsigned int halopad_progress_head, halopad_progress_count;
static unsigned int halopad_progress_dropped;
static unsigned long halopad_progress_retry_time;

void halopad_progress_retry(
	void)
{
	unsigned int remaining = 16;
	unsigned long now;
	unsigned int result;
	struct halopad_progress_pending *pending;

	if (!halopad_progress_count)
		return;
	now = system_milliseconds();
	if (now - halopad_progress_retry_time < 100)
		return;
	halopad_progress_retry_time = now;
	while (halopad_progress_count && remaining--)
	{
		pending = &halopad_progress_pending[halopad_progress_head];
		result = host_halopad_progress_kill_v1(pending->path, pending->path_length,
			&pending->event, sizeof(pending->event));
		if (result != 1 && result != 2)
			break;
		if (result == 2)
			platform_log("progress: native host rejected a queued kill event");
		halopad_progress_head = (halopad_progress_head + 1) % HALOPAD_PROGRESS_PENDING;
		halopad_progress_count--;
	}
}

static void halopad_progress_submit(
	char const *path,
	struct halopad_progress_event const *event)
{
	unsigned int index;
	unsigned int result;
	unsigned int path_length = (unsigned int)strlen(path);
	struct halopad_progress_pending *pending;

	if (!path_length || path_length >= HALOPAD_PROGRESS_PATH)
		return;
	/* (a retransmitted callback must not fill the transient retry queue) */
	for (index = 0; index < halopad_progress_count; index++)
	{
		pending = &halopad_progress_pending[(halopad_progress_head + index) % HALOPAD_PROGRESS_PENDING];
		if (!strcmp(pending->path, path) && !memcmp(&pending->event, event, sizeof(*event)))
			return;
	}
	result = host_halopad_progress_kill_v1(path, path_length, event, sizeof(*event));
	if (result == 1)
		return;
	if (result == 2)
	{
		platform_log("progress: native host rejected a kill event");
		return;
	}
	/* (exceptional persistent storage failure: never hang gameplay, overwrite
	an older uncommitted event, or invent XP from a later statistics delta.
	The newest event beyond this explicit 256-event limit is not retained.) */
	if (halopad_progress_count == HALOPAD_PROGRESS_PENDING)
	{
		halopad_progress_dropped++;
		if (halopad_progress_dropped == 1 || halopad_progress_dropped % 64 == 0)
			platform_log("progress: storage retry queue full; %u newest kill events not retained",
				halopad_progress_dropped);
		return;
	}
	pending = &halopad_progress_pending[(halopad_progress_head + halopad_progress_count) % HALOPAD_PROGRESS_PENDING];
	pending->event = *event;
	pending->path_length = path_length;
	memcpy(pending->path, path, path_length + 1);
	halopad_progress_count++;
}

static void halopad_progress_note_kill(
	boolean player_kill,
	long killing_player_index,
	long dead_player_index,
	struct player_datum const *dead_player)
{
	struct player_datum *killer;
	struct network_game_server *server;
	struct network_game_client *client;
	struct network_game const *game;
	struct halopad_progress_event event;
	char path[HALOPAD_PROGRESS_PATH];

	if (!player_kill || !game_engine_running() || !game_engine_in_play() ||
		network_coop_active() || game_connection() == _game_connection_film_playback ||
		killing_player_index == NONE || killing_player_index == dead_player_index ||
		dead_player == NULL || dead_player->quit_out_of_game || dead_player->unit_index == NONE)
		return;
	killer = player_try_and_get(killing_player_index);
	if (killer == NULL || killer->quit_out_of_game ||
		killer->local_player_index < 0 || killer->local_player_index >= MAXIMUM_LOCAL_PLAYERS)
		return;
	server = global_network_game_server_get();
	client = global_network_game_client_get();
	game = server ? network_game_server_get_game(server) : NULL;
	if (game == NULL && client != NULL)
		game = network_game_client_get_game(client);
	/* (the same session identity on reconnect; do not substitute a local
	clock/seed or merge unrelated matches when there is no session) */
	if (game == NULL)
		return;
	path[0] = 0;
	path[HALOPAD_PROGRESS_PATH - 1] = 0;
	if (!player_ui_get_path_to_local_player_profile_directory(killer->local_player_index, path))
		return;
	path[HALOPAD_PROGRESS_PATH - 1] = 0;
	event.version = 1;
	event.size = sizeof(event);
	event.session_seed = (unsigned int)game->random_seed;
	event.game_number = (unsigned int)game->number_of_games_played;
	event.map_crc = (unsigned int)cache_files_get_checksum();
	event.victim_full_datum = (unsigned int)dead_player->unit_index;
	halopad_progress_submit(path, &event);
}

'''

COOPERATIVE = br'''static boolean game_cooperative(struct network_game const *game)
{
	return game && !game->variant.game_engine_index &&
		(custom_edition_maps_level_campaign(game->map.name) ||
		(custom_edition_level_name(game->map.name) && custom_edition_maps_display_index(game->map.name) == NONE));
}
'''
MENU_HELPER = br'''
/* port: passive native rank card; no remote lobby row or input target.
The native presenter consumes this frame's context and defaults the next
frame to hidden, including movie frames that do not render any widgets. */
extern unsigned int host_halopad_progress_menu_v1(char const *path, unsigned int path_length,
	unsigned int kind, unsigned int local_player);
void halopad_progress_retry(void);

void halopad_progress_menu_context(
	unsigned int kind,
	unsigned int local_player)
{
	void *client;
	void *server;
	struct network_game const *game;
	long profile;
	char path[261];

	if (kind == 0)
	{
		host_halopad_progress_menu_v1(NULL, 0, 0, local_player);
		return;
	}
	if ((kind != 1 && kind != 2) || local_player >= MAXIMUM_LOCAL_PLAYERS)
		return;
	if (kind == 2)
	{
		server = global_network_game_server_get();
		client = global_network_game_client_get();
		game = server ? network_game_server_get_game(server) : NULL;
		if (game == NULL && client != NULL)
			game = network_game_client_get_game(client);
		/* (the same lobby serves campaign co-op; unknown context stays hidden) */
		if (game == NULL || game_cooperative(game) || !game->variant.game_engine_index)
			return;
	}
	profile = player_ui_get_active_player_profile_index((short)local_player);
	if (profile == NONE && local_player == 0)
		profile = player_ui_get_player1_last_used_profile_index();
	if (profile == NONE)
		return;
	path[0] = 0;
	path[NUMBEROF(path) - 1] = 0;
	if (!player_profile_get_enclosing_directory_path(profile, path))
		return;
	path[NUMBEROF(path) - 1] = 0;
	if (path[0])
		host_halopad_progress_menu_v1(path, (unsigned int)strlen(path), kind, local_player);
}
'''

RENDER = b'void render_ui_widgets(\n\tshort local_player_index,\n\trectangle2d const *window_bounds)\n{\n'
WIDGET_HELPER = br'''/* port: the exact top-level multiplayer screens, never a path prefix
that also admits campaign, previews, settings or a gameplay pause menu. */
void halopad_progress_menu_context(unsigned int kind, unsigned int local_player);
void halopad_progress_retry(void);

static unsigned int halopad_progress_widget_kind(
	struct widget_instance const *widget)
{
	char const *name;

	if (widget == NULL || !widget->visible || widget->widget_is_error_dialog ||
		widget->definition_tag_index == NONE)
		return 0;
	name = tag_get_name(widget->definition_tag_index);
	if (name == NULL)
		return 0;
	if (!strcmp(name, "pc\\main_menu\\multiplayer_type_select\\multiplayer_type_select_screen"))
		return 1;
	if (!strcmp(name, "pc\\main_menu\\multiplayer_type_select\\lobby\\lobby_screen"))
		return 2;
	return 0;
}

'''
BEFORE_BINK = br'''	local_player_index_for_draw_string_and_hack_in_icons =
		local_player_index == NONE ? 0 : local_player_index;
	if (bink_playback_ui_rendering_inhibited())
'''
CLEAR_BEFORE_BINK = br'''	local_player_index_for_draw_string_and_hack_in_icons =
		local_player_index == NONE ? 0 : local_player_index;
	/* port: explicit hidden context even with no widgets or an early return. */
	if (first_players_render)
	{
		halopad_progress_retry();
		halopad_progress_menu_context(0, 0);
	}
	if (bink_playback_ui_rendering_inhibited())
'''
AFTER_ROOT = b'\t\t\t\tui_mouse_noting_targets = FALSE;\n\t\t\t\tif (widget_globals.debug_show_path)\n'
PUBLISH_ROOT = br'''				ui_mouse_noting_targets = FALSE;
				if (first_players_render)
					halopad_progress_menu_context(halopad_progress_widget_kind(widget), 0);
				if (widget_globals.debug_show_path)
'''

RENAME = b'boolean synchronize_metadata_display_name_with_profile_name(\n'
RENAME_HELPER = br'''/* port: a profile rename moves the profile directory. Preserve its
native UUID sidecar as well as blam.sav and the campaign snapshot. Missing
sidecars are ordinary legacy profiles; an actual copy failure follows the
existing rename rollback and leaves the old profile and identity intact. */
static boolean halopad_progress_copy_profile_identity(
	char const *old_profile_path,
	char const *new_directory)
{
	char old_identity[MAXIMUM_FILENAME_LENGTH + 1];
	char new_identity[MAXIMUM_FILENAME_LENGTH + 1];
	char *filename;
	DWORD attributes;
	DWORD failure;
	int length;

	csstrncpy(old_identity, old_profile_path, MAXIMUM_FILENAME_LENGTH);
	old_identity[MAXIMUM_FILENAME_LENGTH] = 0;
	filename = strstr(old_identity, "blam.sav");
	if (filename == NULL)
		return FALSE;
	*filename = 0;
	if (strlen(old_identity) + sizeof(".halopad-profile-id") > sizeof(old_identity))
		return FALSE;
	strcat(old_identity, ".halopad-profile-id");
	attributes = GetFileAttributesA(old_identity);
	if (attributes == (DWORD)-1)
	{
		failure = GetLastError();
		if (failure == ERROR_FILE_NOT_FOUND || failure == ERROR_PATH_NOT_FOUND)
			return TRUE;
		error(_error_silent, "progress: could not read profile identity during rename");
		return FALSE;
	}
	length = _snprintf(new_identity, sizeof(new_identity), "%s%s", new_directory, ".halopad-profile-id");
	if (length < 0 || (unsigned int)length >= sizeof(new_identity) ||
		(attributes & FILE_ATTRIBUTE_DIRECTORY) || !CopyFileA(old_identity, new_identity, TRUE))
	{
		error(_error_silent, "progress: could not preserve profile identity during rename");
		return FALSE;
	}
	return TRUE;
}

'''
RENAME_COPY = br'''							else
								{
									success = FALSE;
								}
							}
							break;
						}

						case _saved_game_file_type_game_variant:
'''
RENAME_COPY_IDENTITY = RENAME_COPY.replace(
    b'\t\t\t\t\t\t\tbreak;\n',
    b'\t\t\t\t\t\t\tif (success)\n'
    b'\t\t\t\t\t\t\t\tsuccess = halopad_progress_copy_profile_identity(file.path, save_game_directory);\n'
    b'\t\t\t\t\t\t\tbreak;\n')

PATCHES = {
    GAME: ((GAME_INCLUDE, GAME_INCLUDES), (UPDATE, CORE + UPDATE + b'\thalopad_progress_retry();\n'),
           (QUALIFIED, QUALIFIED_WITH_AWARD)),
    MENU: ((COOPERATIVE, COOPERATIVE + MENU_HELPER),),
    WIDGET: ((RENDER, WIDGET_HELPER + RENDER), (BEFORE_BINK, CLEAR_BEFORE_BINK),
             (AFTER_ROOT, PUBLISH_ROOT)),
    SAVES: ((RENAME, RENAME_HELPER + RENAME), (RENAME_COPY, RENAME_COPY_IDENTITY)),
}


def recipe():
    result = NAME.encode() + b'\0'
    for path, digest in SHA256.items():
        result += path.as_posix().encode() + b'\0' + digest.encode() + b'\0'
        for before, after in PATCHES.get(path, ()):
            result += before + b'\0' + after + b'\0'
    return result + IMPORT_APPEND


def adapt(path, original, adapted=None):
    path = Path(path)
    if path not in SHA256 or hashlib.sha256(original).hexdigest() != SHA256[path]:
        raise ValueError('Monthly progression source changed; review upstream: ' + str(path))
    modified = original if adapted is None else adapted
    if path == IMPORTS:
        if modified.count(b'host_errno\n') != 1 or any(name in modified for name in IMPORT_NAMES):
            raise ValueError('Monthly progression import anchors changed')
        return modified.rstrip(b'\n') + b'\n' + IMPORT_APPEND
    for before, after in PATCHES[path]:
        if original.count(before) != 1 or modified.count(before) != 1:
            raise ValueError('Monthly progression anchors changed: ' + str(path))
        if after in modified:
            raise ValueError('Monthly progression was already applied: ' + str(path))
        modified = modified.replace(before, after)
    return modified


def compose_changes(engine, planned):
    """Stack edits on existing input/network plans, retaining pristine originals."""
    result = list(planned)
    indices = {path: index for index, (path, _, _) in enumerate(result)}
    if len(indices) != len(result):
        raise ValueError('Existing adaptation plan contains duplicate paths')
    for relative in SHA256:
        path = engine / relative
        if path in indices:
            index = indices[path]
            prior_path, original, modified = result[index]
            result[index] = (prior_path, original, adapt(relative, original, modified))
        else:
            original = path.read_bytes()
            result.append((path, original, adapt(relative, original)))
    return result


def changes(engine):
    return compose_changes(engine, [])
