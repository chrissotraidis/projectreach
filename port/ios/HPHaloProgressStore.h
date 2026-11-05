/* Private, device-local multiplayer progression. No network or analytics use. */
#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    uint32_t version, size;
    uint32_t session_seed, game_number, map_crc, victim_full_datum;
} HPHaloProgressKillV1;

typedef NS_ENUM(uint32_t, HPHaloProgressResult) {
    HPHaloProgressRetry = 0,
    HPHaloProgressCommitted = 1, /* includes an already committed event */
    HPHaloProgressInvalid = 2,
};

/* Call before starting the guest. Nothing is stored outside saveRoot. */
FOUNDATION_EXPORT void HPHaloProgressConfigure(NSString *saveRoot);

/* Thread-safe cached snapshot, refreshed for the host's current local season.
   Hidden: {visible:NO}. storage_error is a cached boolean when available.
   A failed profile/store load in an actual MP context includes menu_context:YES,
   menu_kind and local_player, permitting a storage-error card without fake XP.
   Visible additionally contains menu_kind, local_player,
   profile_id, season (Gregorian YYYY-Q1 through YYYY-Q4), xp, kills and history
   (newest first). History entries have profile_id, season, xp and kills;
   current season excluded. Existing monthly records are grouped into quarters
   without changing or deleting the stored records.
   Reading never waits on the database queue or reads guest memory. A cached
   calendar refresh is scheduled at most once a second while queried. */
FOUNDATION_EXPORT NSDictionary *HPHaloProgressMenuSnapshot(void);
/* Display-only bounded player name from a validated local profile. */
FOUNDATION_EXPORT NSString * _Nullable HPHaloProgressPlayerName(NSString *guestPath);

/* The native renderer calls this once per presented frame. It publishes the
   pending menu context, then clears the pending context for the following frame.
   A frame without guest menu rendering therefore hides the card. */
FOUNDATION_EXPORT void xg_progress_frame_presented(void);

/* Public only for focused persistence tests; production uses the functions above.
   A nil calendar follows Gregorian quarters in the device's current time zone. */
@interface HPHaloProgressStore : NSObject
- (instancetype)initWithSaveRootURL:(NSURL *)root calendar:(nullable NSCalendar *)calendar;
- (HPHaloProgressResult)recordKill:(HPHaloProgressKillV1)event
                      profilePath:(NSString *)profilePath
                             date:(NSDate *)date;
- (nullable NSDictionary *)snapshotForProfilePath:(NSString *)profilePath date:(NSDate *)date;
- (void)close;
@end

/* Guest ABI: bounded ASCII path bytes exclude the NUL terminator. Event bytes
   are the six little-endian uint32 fields above, exactly 24 bytes. */
FOUNDATION_EXPORT uint32_t xh_host_halopad_progress_kill_v1(uint32_t path, uint32_t pathLength,
                                                         uint32_t event, uint32_t eventLength);
FOUNDATION_EXPORT uint32_t xh_host_halopad_progress_menu_v1(uint32_t path, uint32_t pathLength,
                                                         uint32_t kind, uint32_t localPlayer);

NS_ASSUME_NONNULL_END
