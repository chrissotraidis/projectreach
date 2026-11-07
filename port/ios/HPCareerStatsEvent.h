#ifndef HP_CAREER_STATS_EVENT_H
#define HP_CAREER_STATS_EVENT_H
#include <stdint.h>
/* Private local-only ABI. No network messages or existing progression data change. */
enum HPCareerEventKind { HPCareerMatchEnter=1, HPCareerKill=2, HPCareerDeath=3, HPCareerAssist=4, HPCareerMatchEnd=5, HPCareerAuthoritativeTotals=6, HPCareerMedal=7 };
/* For kind 7, reserved is a medal ID, event_id is the credited kill total,
 * and mode_id is the original award's UTC Unix timestamp in seconds. The
 * native bridge uses that timestamp through storage/FIFO retries; mode[]
 * retains the human-readable game mode. All other event kinds retain their
 * original fields and reserved == 0. The explicit store date: API continues
 * to accept its caller-provided occurrence date for isolated fixtures. */
enum HPCareerMedalID {
    HPCareerDoubleKill=1, HPCareerTripleKill=2, HPCareerOverkill=3,
    HPCareerKilltacular=4, HPCareerKilltrocity=5, HPCareerKillamanjaro=6,
    HPCareerKilltastrophe=7, HPCareerKillpocalypse=8, HPCareerKillionaire=9,
    HPCareerKillingSpree=10, HPCareerKillingFrenzy=11, HPCareerRunningRiot=12,
    HPCareerRampage=13, HPCareerUntouchable=14, HPCareerInvincible=15
};
enum HPCareerMatchResult { HPCareerUnknown=0, HPCareerWin=1, HPCareerLoss=2, HPCareerDraw=3 };
/* PreviewOnly is a local kind7 HUD delivery while an older event is retrying.
 * The bridge strips this bit before display and never resolves/persists it. */
enum HPCareerEventFlags { HPCareerReplicatedClient=1, HPCareerTransientProfile=2, HPCareerMedalPreviewOnly=4 };
typedef struct HPCareerStatsEventV1 {
    uint32_t version, size, kind, session_seed, game_number, map_crc;
    uint32_t event_id, local_player, streak, result, mode_id, flags, kills, deaths, assists, reserved;
    char map[64], mode[64], weapon[128];
} HPCareerStatsEventV1;
_Static_assert(sizeof(HPCareerStatsEventV1)==320, "career event ABI must be 320 bytes");
#endif
