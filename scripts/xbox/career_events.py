"""Pinned OpenCE337 career events from genuine native statistics/lifecycle hooks."""
import hashlib
from pathlib import Path

NAME = 'native-career-statistics-v1'
MEDALS_NAME = 'confirmed-multikills-sprees-v1'
GAME = Path('source/game/game_engine.c')
STATS = Path('source/game/game_statistics.c')
DAMAGE = Path('source/objects/damage.c')
DISTRIBUTED = Path('port/linux/game/network_distributed.c')
IMPORTS = Path('port/android/host_imports.list')
CORE = Path(__file__).with_name('career_runtime.inc').read_bytes()
ANCHOR = b'void game_engine_update(\n\tvoid)\n{\n'

def recipe():
    return NAME.encode() + CORE + Path(__file__).read_bytes()

def compose_changes(engine, changes):
    planned = {path: index for index, (path, _, _) in enumerate(changes)}
    def edit(relative, transform):
        path = engine / relative
        if path in planned:
            index = planned[path]
            path, original, current = changes[index]
            changes[index] = path, original, transform(current)
        else:
            original = path.read_bytes()
            planned[path] = len(changes)
            changes.append((path, original, transform(original)))
    def replace(data, old, new):
        if data.count(old) != 1:
            raise ValueError('Career statistics source anchor changed: ' + repr(old[:100]))
        return data.replace(old, new)
    def game(data):
        data = b'static void halopad_career_retry(void);\n' + data
        retry = b'void halopad_progress_retry(\n\tvoid)\n{\n'
        data = replace(data, retry, retry + b'\thalopad_career_retry();\n')
        return replace(data, ANCHOR, CORE + b'\n' + ANCHOR + b'\thalopad_career_tick();\n')
    def stats(data):
        data = replace(data, b'#include "game/game_statistics_internal.h"\n',
            b'#include "game/game_statistics_internal.h"\nvoid halopad_career_tally(unsigned int kind, long player_index, long dead_unit_index);\n')
        old = b'\t\t\tdead_player->statistics.multiple_kills = 0;\n'
        data = replace(data, old, old + b'\t\t\thalopad_career_tally(3, dead_player_index, dead_unit_index);\n')
        old = b'\t\t\t\t\tcredited_player->statistics.last_kill_time = (short)game_time_get();\n'
        data = replace(data, old, old + b'\t\t\t\t\thalopad_career_tally(2, credited_player_index, dead_unit_index);\n')
        old = (b'\t\t\t\t\t\tif (assisting_player && game_team_is_enemy(dead_team_index, (short)assisting_player->team_index))\n'
               b'\t\t\t\t\t\t\tassisting_player->statistics.assists[statistic_index]++;\n')
        new = (b'\t\t\t\t\t\tif (assisting_player && game_team_is_enemy(dead_team_index, (short)assisting_player->team_index))\n'
               b'\t\t\t\t\t\t{\n\t\t\t\t\t\t\tassisting_player->statistics.assists[statistic_index]++;\n'
               b'\t\t\t\t\t\t\thalopad_career_tally(4, attacker->player_index, dead_unit_index);\n\t\t\t\t\t\t}\n')
        return replace(data, old, new)
    def damage(data):
        marker = b'void halopad_career_record_kill(long, long, long, short, long);\n'
        data = marker + data
        old = (b'\t\t\tgame_statistics_record_kill(\n\t\t\t\tobject_index,\n'
               b'\t\t\t\tdamage->owner_player_index,\n\t\t\t\tdamage->owner_object_index,\n'
               b'\t\t\t\tdamage->owner_team_index);')
        return replace(data, old, old.replace(b'game_statistics_record_kill(', b'halopad_career_record_kill(')
            .replace(b'damage->owner_team_index);', b'damage->owner_team_index, damage->definition_index);'))
    def distributed(data):
        data = b'struct player_datum;\nvoid halopad_career_authoritative_snapshot(struct player_datum const *, unsigned int);\n' + data
        old = b'\t\t\tif (player)\n\t\t\t\tplayer->statistics = players[index].statistics;\n'
        new = (b'\t\t\tif (player)\n\t\t\t{\n\t\t\t\tplayer->statistics = players[index].statistics;\n'
               b'\t\t\t\thalopad_career_authoritative_snapshot(player, (unsigned int)header.game_time);\n\t\t\t}\n')
        return replace(data, old, new)
    edit(GAME, game)
    edit(STATS, stats)
    edit(DAMAGE, damage)
    edit(DISTRIBUTED, distributed)
    edit(IMPORTS, lambda data: data + b'\n# Native career statistics; no network format changes.\nhost_halopad_career_event_v1\n')
    return changes
