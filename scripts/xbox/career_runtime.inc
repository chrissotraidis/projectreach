/* Native career bridge: native events only; no network format changes. */
struct halopad_career_event_v1
{
	unsigned int version, size, kind, session_seed, game_number, map_crc;
	unsigned int event_id, local_player, streak, result, mode_id, flags;
	unsigned int kills, deaths, assists, reserved;
	char map[64], mode[64], weapon[128];
};
typedef char halopad_career_word_size[sizeof(unsigned int) == 4 ? 1 : -1];
typedef char halopad_career_payload_size[sizeof(struct halopad_career_event_v1) == 320 ? 1 : -1];
extern unsigned int host_halopad_career_event_v1(char const *, unsigned int, void const *, unsigned int);
void platform_log(char const *, ...);
boolean tag_index_is_group(long tag_index, long group_tag);

#define HALOPAD_CAREER_PENDING 256
struct halopad_career_pending
{
	struct halopad_career_event_v1 event;
	char path[261];
};
static struct halopad_career_pending halopad_career_pending[HALOPAD_CAREER_PENDING];
static unsigned int halopad_career_head, halopad_career_count, halopad_career_dropped;
static unsigned long halopad_career_retry_time;
struct halopad_career_match
{
	boolean entered, ended;
	boolean outcome_seen;
	unsigned int outcome;
	unsigned int seed, game_number, map_crc;
	boolean snapshot_valid;
	unsigned int snapshot_kills, snapshot_deaths, snapshot_assists, snapshot_streak;
	/* Medals use confirmed credited kills, never speculative client tallies. */
	boolean medal_host_valid, medal_client_valid, medal_last_kill_valid;
	unsigned int medal_kills, medal_deaths, medal_tick, medal_chain;
	unsigned int medal_last_kill_tick, medal_highwater;
	char path[261];
};
static struct halopad_career_match halopad_career_matches[MAXIMUM_LOCAL_PLAYERS];
static long halopad_career_damage_unit = NONE, halopad_career_damage_effect = NONE;

static void halopad_career_copy(char *out, unsigned int capacity, char const *source)
{
	unsigned int index = 0;
	if (source)
		while (index + 1 < capacity && source[index])
		{
			out[index] = source[index];
			index++;
		}
	out[index] = 0;
}

static void halopad_career_mode(char *out, unsigned int capacity, wchar_t const *source)
{
	unsigned int index = 0, value;
	/* The native mode labels are English ASCII. Unknown text stays unknown;
	never truncate a multibyte character or manufacture a mode identifier. */
	if (source)
		while (index + 1 < capacity && source[index])
		{
			value = (unsigned int)source[index];
			if (value > 127) { out[0] = 0; return; }
			out[index++] = (char)value;
		}
	out[index] = 0;
}

static boolean halopad_career_prepare(struct halopad_career_event_v1 *event,
	unsigned int kind, struct player_datum const *player, char *path)
{
	struct network_game_server *server;
	struct network_game_client *client;
	struct network_game const *game;
	wchar_t const *mode;
	byte mode_kind;
	if (!game_engine_running() || !game_engine || network_coop_active() ||
		game_connection() == _game_connection_film_playback ||
		global_variant.game_engine_index == game_engine_none ||
		!player || player->quit_out_of_game || player->local_player_index < 0 ||
		player->local_player_index >= MAXIMUM_LOCAL_PLAYERS ||
		player->statistics.kills[0] < 0 || player->statistics.deaths < 0 ||
		player->statistics.assists[0] < 0)
		return FALSE;
	server = global_network_game_server_get();
	client = global_network_game_client_get();
	game = server ? network_game_server_get_game(server) : NULL;
	if (!game && client) game = network_game_client_get_game(client);
	if (!game) return FALSE;
	path[0] = path[260] = 0;
	csmemset(event, 0, sizeof(*event));
	/* A transient/default player still sees medals. The host discards flag2
	events before UUID resolution, so no synthetic profile is persisted. */
	if (!player_ui_get_path_to_local_player_profile_directory(player->local_player_index, path) || !path[0])
	{
		halopad_career_copy(path, 261, "u:\\udata\\000000000000");
		event->flags = 2;
	}
	path[260] = 0;
	event->version = 1; event->size = sizeof(*event); event->kind = kind;
	event->session_seed = game->random_seed;
	event->game_number = game->number_of_games_played;
	event->map_crc = cache_files_get_checksum();
	event->local_player = player->local_player_index;
	event->flags |= network_game_distributed_client() ? 1 : 0;
	event->kills = player->statistics.kills[0];
	event->deaths = player->statistics.deaths;
	event->assists = player->statistics.assists[0];
	event->streak = MAX(0, player->statistics.kills_in_a_row);
	mode_kind = game_modes_kind(&global_variant, game_variant_options_get());
	event->mode_id = (unsigned int)global_variant.game_engine_index | ((unsigned int)mode_kind << 16);
	halopad_career_copy(event->map, sizeof(event->map), game->map.name);
	mode = game_modes_variant_kind_name(&global_variant, game_variant_options_get());
	halopad_career_mode(event->mode, sizeof(event->mode), mode);
	if (!event->mode[0]) halopad_career_copy(event->mode, sizeof(event->mode), game_engine->name);
	halopad_career_copy(event->weapon, sizeof(event->weapon), "unknown");
	return TRUE;
}

static boolean halopad_career_submit(char const *path, struct halopad_career_event_v1 const *event)
{
	unsigned int index, result;
	struct halopad_career_pending *pending;
	/* Preserve event order while storage is unavailable, including baseline,
	combat, corrections and results. Never overtake an uncommitted record. */
	for (index = 0; index < halopad_career_count; index++)
	{
		pending = &halopad_career_pending[(halopad_career_head + index) % HALOPAD_CAREER_PENDING];
		if (!strcmp(pending->path, path) && !memcmp(&pending->event, event, sizeof(*event))) return TRUE;
	}
	/* Display a fresh medal even when an earlier storage event is waiting.
	The preview bit requests HUD delivery only: the host strips it,
	deduplicates the canonical award, and performs no profile/SQLite work.
	The original event remains in this FIFO for ordered durable persistence. */
	if (halopad_career_count && event->kind == 7)
	{
		struct halopad_career_event_v1 preview = *event;
		preview.flags |= 4;
		host_halopad_career_event_v1(path, (unsigned int)strlen(path), &preview, sizeof(preview));
	}
	if (!halopad_career_count)
	{
		result = host_halopad_career_event_v1(path, (unsigned int)strlen(path), event, sizeof(*event));
		if (result == 1 || result == 2) return TRUE;
	}
	if (halopad_career_count == HALOPAD_CAREER_PENDING)
	{
		halopad_career_dropped++;
		if (halopad_career_dropped == 1 || halopad_career_dropped % 64 == 0)
			platform_log("career: storage retry queue full; %u newest native events not retained", halopad_career_dropped);
		return FALSE;
	}
	pending = &halopad_career_pending[(halopad_career_head + halopad_career_count) % HALOPAD_CAREER_PENDING];
	pending->event = *event;
	halopad_career_copy(pending->path, sizeof(pending->path), path);
	halopad_career_count++;
	return TRUE;
}

static void halopad_career_retry(void)
{
	unsigned int remaining = 16, result;
	unsigned long now = system_milliseconds();
	struct halopad_career_pending *pending;
	if (!halopad_career_count || now - halopad_career_retry_time < 100) return;
	halopad_career_retry_time = now;
	while (halopad_career_count && remaining--)
	{
		pending = &halopad_career_pending[halopad_career_head];
		result = host_halopad_career_event_v1(pending->path, (unsigned int)strlen(pending->path), &pending->event, sizeof(pending->event));
		if (result != 1 && result != 2) break;
		halopad_career_head = (halopad_career_head + 1) % HALOPAD_CAREER_PENDING;
		halopad_career_count--;
	}
}

static struct halopad_career_match *halopad_career_enter(char const *path,
	struct halopad_career_event_v1 const *event, unsigned int subtract_kind)
{
	struct halopad_career_match *match = &halopad_career_matches[event->local_player];
	struct halopad_career_event_v1 entered;
	if (match->seed != event->session_seed || match->game_number != event->game_number ||
		match->map_crc != event->map_crc || strcmp(match->path, path))
	{
		csmemset(match, 0, sizeof(*match));
		match->seed = event->session_seed; match->game_number = event->game_number; match->map_crc = event->map_crc;
		halopad_career_copy(match->path, sizeof(match->path), path);
	}
	if (!match->entered && game_engine_in_play())
	{
		entered = *event; entered.kind = 1; entered.event_id = 0; entered.streak = 0;
		/* A first native tally can precede the first simulation update. Its
		baseline is before that tally, so the genuine first event is retained. */
		if (subtract_kind == 2 && entered.kills) entered.kills--;
		if (subtract_kind == 3 && entered.deaths) entered.deaths--;
		if (subtract_kind == 4 && entered.assists) entered.assists--;
		match->entered = halopad_career_submit(path, &entered);
	}
	return match;
}

/* Kind7 keeps the existing320byte local ABI. reserved is the medal ID;
 event_id/kills are the exact credited kill total when that threshold was met.
 A coalesced client snapshot proves the final chain/life's suffix only. */
static void halopad_career_medal(char const *path, struct halopad_career_event_v1 const *source,
 unsigned int medal, unsigned int kill, unsigned int streak)
{
 struct halopad_career_event_v1 event = *source;
 event.kind = 7; event.event_id = event.kills = kill; event.reserved = medal;
 event.streak = streak; event.result = 0;
 /* Kind7 alone uses mode_id for UTC award time, preserving season even
 when storage queues retry across a local quarter boundary. */
 event.mode_id = (unsigned int)system_seconds();
 halopad_career_submit(path, &event);
}

static void halopad_career_medal_suffix(char const *path, struct halopad_career_event_v1 const *event,
 unsigned int new_kills, unsigned int chain)
{
 unsigned int threshold, suffix, offset, streak;
 suffix = MIN(new_kills, chain);
 for (threshold = 2; threshold <= 10; threshold++)
 {
  if (chain >= threshold && chain - suffix < threshold)
  {
   offset = chain - threshold;
   streak = event->streak >= offset ? event->streak - offset : 0;
   halopad_career_medal(path, event, threshold - 1, event->kills - offset, streak);
  }
 }
 suffix = MIN(new_kills, event->streak);
 for (threshold = 5; threshold <= 30; threshold += 5)
 {
  if (event->streak >= threshold && event->streak - suffix < threshold)
  {
   offset = event->streak - threshold;
   halopad_career_medal(path, event, 9 + threshold / 5, event->kills - offset, threshold);
  }
 }
}

static void halopad_career_host_medals(char const *path, struct halopad_career_event_v1 const *event,
 struct halopad_career_match *match)
{
 unsigned int now = (unsigned int)game_time_get();
 if (event->kind == 3)
 {
  if (!match->medal_host_valid || event->deaths > match->medal_deaths)
  {
   match->medal_chain = 0; match->medal_last_kill_valid = FALSE;
   match->medal_deaths = event->deaths;
  }
  return;
 }
 if (event->kind != 2 || (match->medal_host_valid && event->kills <= match->medal_kills)) return;
 if (match->medal_last_kill_valid && event->deaths == match->medal_deaths &&
  (unsigned int)(now - match->medal_last_kill_tick) <= 120)
  match->medal_chain++;
 else match->medal_chain = 1;
 match->medal_host_valid = match->medal_last_kill_valid = TRUE;
 match->medal_last_kill_tick = now;
 match->medal_kills = event->kills; match->medal_deaths = event->deaths;
 halopad_career_medal_suffix(path, event, 1, match->medal_chain);
}

static void halopad_career_client_medals(char const *path, struct halopad_career_event_v1 const *event,
 struct player_datum const *player, struct halopad_career_match *match, unsigned int tick)
{
 unsigned int delta = 0, chain = 0, last_kill = 0;
 boolean time_valid = FALSE;
 /* First accepted snapshot establishes a late-join baseline; medals before
 tracking began are never manufactured. Older authoritative ticks are ignored. */
 if (match->medal_client_valid && (int)(tick - match->medal_tick) < 0) return;
 if (match->medal_client_valid && event->kills > match->medal_highwater)
 {
  delta = event->kills - match->medal_highwater;
  /* Native last_kill_time is a signed16bit field. Unwrap its low16 bits
  against this snapshot's full tick only if a new kill proves it occurred
  after the previous accepted snapshot. No long-match timestamp alias. */
  last_kill = tick - ((tick - (unsigned int)(unsigned short)player->statistics.last_kill_time) & 65535u);
  time_valid = (unsigned int)(tick - match->medal_tick) <= 65535u &&
   (int)(last_kill - match->medal_tick) >= 0 && (int)(tick - last_kill) >= 0;
  if (player->statistics.multiple_kills > 0)
   chain = (unsigned int)player->statistics.multiple_kills;
  /* Exact one-kill snapshots, or a whole batch within4s of the previous
  confirmed kill, safely extend our full32bit chain despite the native
  signed16bit last_kill_time wrap. Batched unknown gaps use only the
  server's explicitly confirmed latest chain suffix. */
  if (time_valid && match->medal_last_kill_valid && event->deaths == match->medal_deaths &&
   event->kills >= match->medal_kills &&
   (delta == 1 || (unsigned int)(last_kill - match->medal_last_kill_tick) <= 120u))
  {
   unsigned int observed = (unsigned int)(last_kill - match->medal_last_kill_tick) <= 120u ?
    match->medal_chain + delta : 1;
   chain = MAX(chain, observed);
  }
  /* A chain cannot exceed the confirmed current life or total kills. */
  chain = MIN(chain, MIN(event->streak, event->kills));
  halopad_career_medal_suffix(path, event, delta, chain);
 }
 else if (match->medal_client_valid && event->kills == match->medal_kills &&
  event->deaths == match->medal_deaths)
 {
  /* Periodic identical snapshots must retain the last confirmed kill
  timestamp/chain, but still advance the anti-stale snapshot tick. */
  match->medal_tick = tick;
  return;
 }
 match->medal_client_valid = TRUE;
 match->medal_highwater = MAX(match->medal_highwater, event->kills);
 match->medal_kills = event->kills; match->medal_deaths = event->deaths;
 match->medal_tick = tick; match->medal_chain = chain;
 match->medal_last_kill_valid = time_valid;
 match->medal_last_kill_tick = last_kill;
}

void halopad_career_tally(unsigned int kind, long player_index, long dead_unit_index)
{
	struct player_datum *player = player_try_and_get(player_index);
	struct halopad_career_event_v1 event;
	struct halopad_career_match *match;
	char path[261];
	char const *source;
	if (network_game_distributed_client() || !game_engine_in_play() ||
		!halopad_career_prepare(&event, kind, player, path)) return;
	event.event_id = kind == 2 ? event.kills : kind == 3 ? event.deaths : event.assists;
	if (!event.event_id) return;
	/* A lethal damage tag is actual attribution, never a held-weapon guess.
	Assists have no proven weapon identity and remain unknown. */
	if (kind == 2 && halopad_career_damage_unit == dead_unit_index &&
		halopad_career_damage_effect != NONE && tag_index_is_group(halopad_career_damage_effect, 'jpt!'))
	{
		source = tag_get_name(halopad_career_damage_effect);
		if (source && strlen(source) < sizeof(event.weapon))
			halopad_career_copy(event.weapon, sizeof(event.weapon), source);
	}
	match = halopad_career_enter(path, &event, kind);
	if (match->entered && !match->ended && halopad_career_submit(path, &event))
		halopad_career_host_medals(path, &event, match);
}

void halopad_career_record_kill(long dead_unit_index, long killing_player_index,
	long killing_object_index, short killing_team_index, long damage_effect)
{
	long saved_unit = halopad_career_damage_unit, saved_effect = halopad_career_damage_effect;
	halopad_career_damage_unit = dead_unit_index; halopad_career_damage_effect = damage_effect;
	game_statistics_record_kill(dead_unit_index, killing_player_index, killing_object_index, killing_team_index);
	halopad_career_damage_unit = saved_unit; halopad_career_damage_effect = saved_effect;
}

void halopad_career_authoritative_snapshot(struct player_datum const *player, unsigned int tick)
{
	struct halopad_career_event_v1 event;
	struct halopad_career_match *match;
	char path[261];
	if (!network_game_distributed_client() || !halopad_career_prepare(&event, 6, player, path)) return;
	event.event_id = tick;
	match = halopad_career_enter(path, &event, 0);
	if (match->entered && !match->ended && (!match->snapshot_valid ||
		match->snapshot_kills != event.kills || match->snapshot_deaths != event.deaths ||
		match->snapshot_assists != event.assists || match->snapshot_streak != event.streak))
	{
		if (!halopad_career_submit(path, &event)) return;
		match->snapshot_valid = TRUE;
		match->snapshot_kills = event.kills; match->snapshot_deaths = event.deaths;
		match->snapshot_assists = event.assists; match->snapshot_streak = event.streak;
	}
	if (match->entered && !match->ended)
		halopad_career_client_medals(path, &event, player, match, tick);
}

static void halopad_career_tick(void)
{
	struct data_iterator iterator;
	struct player_datum *player;
	struct halopad_career_event_v1 event;
	struct halopad_career_match *match;
	long result;
	char path[261];
	halopad_career_retry();
	if (!game_engine) return;
	data_iterator_new(&iterator, player_data);
	while ((player = (struct player_datum *)data_iterator_next(&iterator)))
	{
		if (!halopad_career_prepare(&event, 1, player, path)) continue;
		/* Client entry comes only from its first accepted authoritative host
		snapshot, not locally predicted/speculative player statistics. */
		match = &halopad_career_matches[event.local_player];
		if (!network_game_distributed_client()) match = halopad_career_enter(path, &event, 0);
		if (!match->entered || match->ended || match->seed != event.session_seed ||
			match->game_number != event.game_number || match->map_crc != event.map_crc ||
			strcmp(match->path, path) || game_engine_in_play()) continue;
		/* Only the game's real postgame transition confirms an outcome.
		Leaving a server never fabricates a loss or a completed match. */
		event.kind = 5; event.event_id = 0;
		result = game_engine_did_player_win(iterator.datum_index);
		/* Default engine NONE is its explicit tied-first/team-score draw.
		An override (Infection) can also mean missing/unconfirmed role/state:
		keep that unknown and retry if a confirmed result arrives later. */
		event.result = result == TRUE ? 1 : result == FALSE ? 2 :
			result == NONE && !game_engine->did_player_win ? 3 : 0;
		if (match->outcome_seen && match->outcome == event.result) continue;
		/* Client counters here may be predicted; only kind6 carries its
		accepted authoritative totals. Result events do not reconcile counts. */
		if (network_game_distributed_client()) event.kills = event.deaths = event.assists = event.streak = 0;
		if (!halopad_career_submit(path, &event)) continue;
		match->outcome_seen = TRUE; match->outcome = event.result;
		match->ended = event.result != 0;
	}
}
