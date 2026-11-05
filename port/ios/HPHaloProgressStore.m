#import "HPHaloProgressStore.h"
#import <TargetConditionals.h>
/* UIKit app builds (iPhone, iPad and Mac Catalyst) own career stats; the plain
 * macOS store test compiles this file without the companion modules. */
#if TARGET_OS_IOS
#import "HPHaloCareerStatsIntegration.h"
#endif
#include "../xbox/xg_host.h"
#include <sqlite3.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <mach/mach.h>
#include <mach/vm_map.h>
#include <limits.h>

static NSString *const HPProfileIDFile = @".halopad-profile-id";
static NSString *const HPProgressDatabase = @".halopad-progression.sqlite3";

/* Keep the schema-1 monthly storage keys and frozen retry dates. Seasonal
   snapshots combine those records, including XP earned before this update. */
static NSString *HPProgressMonth(NSDate *date, NSCalendar *fixedCalendar)
{
    NSCalendar *calendar = fixedCalendar;
    if (!calendar) {
        calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        calendar.timeZone = NSTimeZone.localTimeZone;
    }
    NSDateComponents *parts = [calendar components:NSCalendarUnitYear | NSCalendarUnitMonth fromDate:date];
    return [NSString stringWithFormat:@"%04ld-%02ld", (long)parts.year, (long)parts.month];
}

static NSString *HPProgressSeasonForMonth(NSString *month)
{
    if (![month isKindOfClass:NSString.class] || month.length != 7 ||
        [month characterAtIndex:4] != '-') return nil;
    for (NSUInteger index = 0; index < month.length; index++) {
        if (index == 4) continue;
        unichar digit = [month characterAtIndex:index];
        if (digit < '0' || digit > '9') return nil;
    }
    NSInteger year = [[month substringToIndex:4] integerValue];
    NSInteger number = [[month substringFromIndex:5] integerValue];
    if (year < 1 || number < 1 || number > 12) return nil;
    NSInteger quarter = (number - 1) / 3 + 1;
    return [NSString stringWithFormat:@"%04ld-Q%ld", (long)year, (long)quarter];
}

static NSDictionary<NSString *, NSNumber *> *HPProgressSeasonTotals(NSDictionary *months)
{
    NSMutableDictionary<NSString *, NSNumber *> *seasons = [NSMutableDictionary dictionary];
    for (NSString *month in months) {
        NSString *season = HPProgressSeasonForMonth(month);
        id stored = months[month];
        if (!season || ![stored isKindOfClass:NSNumber.class]) return nil;
        long long amount = [stored longLongValue];
        long long total = [seasons[season] longLongValue];
        /* Do not wrap or silently truncate XP while combining three months.
           The caller presents a storage error and leaves the ledger intact. */
        if (amount < 0 || amount > LLONG_MAX - total) return nil;
        seasons[season] = @(total + amount);
    }
    return [seasons copy];
}

static NSString *HPProgressPathKey(NSString *path)
{
    if (![path isKindOfClass:NSString.class] || !path.length || path.length > 260 ||
        ![path canBeConvertedToEncoding:NSASCIIStringEncoding]) return nil;
    static NSRegularExpression *pattern;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pattern = [NSRegularExpression regularExpressionWithPattern:
            @"^[uU]:[\\\\/][uU][dD][aA][tT][aA][\\\\/][0-9a-fA-F]{12}[\\\\/]?$"
            options:0 error:NULL];
    });
    NSTextCheckingResult *match = [pattern firstMatchInString:path options:0 range:NSMakeRange(0, path.length)];
    if (!match || match.range.location || NSMaxRange(match.range) != path.length) return nil;
    NSString *key = [[path stringByReplacingOccurrencesOfString:@"\\" withString:@"/"] uppercaseString];
    return [key hasSuffix:@"/"] ? [key substringToIndex:key.length - 1] : key;
}

/* The Xbox filesystem resolves existing components case-insensitively. Refuse
   ambiguous names, symlinks, missing profiles and paths outside this save root. */
static NSString *HPExistingChild(NSString *parent, NSString *name, BOOL directory)
{
    NSString *match = nil;
    NSArray *entries = [NSFileManager.defaultManager contentsOfDirectoryAtPath:parent error:NULL];
    for (NSString *entry in entries) {
        if ([entry caseInsensitiveCompare:name] != NSOrderedSame) continue;
        if (match) return nil;
        match = entry;
    }
    if (!match) return nil;
    NSString *path = [parent stringByAppendingPathComponent:match];
    struct stat status;
    if (lstat(path.fileSystemRepresentation, &status) || S_ISLNK(status.st_mode) ||
        (directory ? !S_ISDIR(status.st_mode) : !S_ISREG(status.st_mode))) return nil;
    return path;
}

static NSString *HPCanonicalRoot(NSURL *root)
{
    char resolved[PATH_MAX];
    if (!root.isFileURL || !realpath(root.path.fileSystemRepresentation, resolved)) return nil;
    struct stat status;
    if (stat(resolved, &status) || !S_ISDIR(status.st_mode)) return nil;
    return [NSFileManager.defaultManager stringWithFileSystemRepresentation:resolved length:strlen(resolved)];
}

static int HPProfileDirectory(NSURL *rootURL, NSString *key)
{
    NSString *root = HPCanonicalRoot(rootURL);
    NSString *drive = root ? HPExistingChild(root, @"u", YES) : nil;
    NSString *data = drive ? HPExistingChild(drive, @"UDATA", YES) : nil;
    NSString *folder = data ? HPExistingChild(data, key.lastPathComponent, YES) : nil;
    if (!folder || !HPExistingChild(folder, @"blam.sav", NO)) return -1;
    return open(folder.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
}

static NSString *HPReadProfileID(int directory)
{
    int file = openat(directory, HPProfileIDFile.UTF8String, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (file < 0) return nil;
    struct stat status;
    char bytes[38];
    ssize_t length = read(file, bytes, sizeof(bytes));
    BOOL valid = fstat(file, &status) == 0 && S_ISREG(status.st_mode) && status.st_nlink == 1 &&
        status.st_size == 37 && length == 37 && bytes[36] == '\n';
    close(file);
    if (!valid) return nil;
    NSString *text = [[NSString alloc] initWithBytes:bytes length:36 encoding:NSASCIIStringEncoding];
    NSUUID *identifier = text ? [[NSUUID alloc] initWithUUIDString:text] : nil;
    return identifier.UUIDString;
}

static NSString *HPProfileID(NSURL *root, NSString *key)
{
    int directory = HPProfileDirectory(root, key);
    if (directory < 0) return nil;
    struct stat existing;
    if (fstatat(directory, HPProfileIDFile.UTF8String, &existing, AT_SYMLINK_NOFOLLOW) == 0) {
        NSString *identifier = HPReadProfileID(directory);
        close(directory);
        return identifier; /* Never replace an invalid/concurrently changed identity. */
    }
    if (errno != ENOENT) { close(directory); return nil; }
    NSString *identifier = NSUUID.UUID.UUIDString;
    NSString *temporary = [NSString stringWithFormat:@".halopad-profile-%@.tmp", NSUUID.UUID.UUIDString];
    int file = openat(directory, temporary.UTF8String,
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    BOOL success = NO;
    if (file >= 0) {
        NSData *data = [[identifier stringByAppendingString:@"\n"] dataUsingEncoding:NSASCIIStringEncoding];
        const char *bytes = data.bytes;
        size_t written = 0;
        while (written < data.length) {
            ssize_t count = write(file, bytes + written, data.length - written);
            if (count < 0 && errno == EINTR) continue;
            if (count <= 0) break;
            written += (size_t)count;
        }
        success = written == data.length && fsync(file) == 0;
        if (close(file)) success = NO;
        if (success) {
            /* linkat publishes complete bytes without replacing another writer. */
            success = linkat(directory, temporary.UTF8String, directory, HPProfileIDFile.UTF8String, 0) == 0;
            if (!success && errno == EEXIST) identifier = HPReadProfileID(directory);
            else if (!success) identifier = nil;
        } else identifier = nil;
        unlinkat(directory, temporary.UTF8String, 0);
        if (fsync(directory)) identifier = nil;
    } else identifier = nil;
    close(directory);
    return identifier;
}

static BOOL HPRegularDatabaseFile(NSString *path)
{
    struct stat status;
    if (lstat(path.fileSystemRepresentation, &status)) return errno == ENOENT;
    return S_ISREG(status.st_mode) && !S_ISLNK(status.st_mode) && status.st_nlink == 1;
}

static BOOL HPExec(sqlite3 *database, const char *sql)
{
    return sqlite3_exec(database, sql, NULL, NULL, NULL) == SQLITE_OK;
}

static NSString *HPEventKey(NSString *path, HPHaloProgressKillV1 event)
{
    return [NSString stringWithFormat:@"%@:%08x:%08x:%08x:%08x", path,
        event.session_seed, event.game_number, event.map_crc, event.victim_full_datum];
}

@interface HPHaloProgressStore ()
- (NSURL *)playerNameSaveRoot;
- (void)presentMenuContext:(nullable NSDictionary *)context;
- (NSDictionary *)menuSnapshotForContext:(NSDictionary *)context;
- (void)invalidateMenuSnapshot;
- (void)publishSnapshot;
@end

@implementation HPHaloProgressStore {
    NSURL *_root;
    NSCalendar *_calendar;
    dispatch_queue_t _queue;
    sqlite3 *_database;
    NSMutableDictionary<NSString *, NSMutableDictionary *> *_pending;
    NSMutableDictionary<NSString *, NSString *> *_pendingPaths;
    NSString *_activePath;
    NSString *_activeProfile;
    NSDictionary<NSString *, NSNumber *> *_activeMonths;
    NSUInteger _menuKind, _localPlayer;
    BOOL _storageError;
    NSDictionary *_publishedSnapshot;
    NSDictionary *_publishedContext;
    NSDictionary *_requestedContext;
    NSTimeInterval _lastCalendarRefresh;
}

- (instancetype)initWithSaveRootURL:(NSURL *)root calendar:(NSCalendar *)calendar
{
    if ((self = [super init])) {
        _root = [root copy];
        _calendar = [calendar copy];
        _queue = dispatch_queue_create("dev.halopad.local-progression", DISPATCH_QUEUE_SERIAL);
        _pending = [NSMutableDictionary dictionary];
        _pendingPaths = [NSMutableDictionary dictionary];
        _publishedSnapshot = @{@"visible":@NO, @"storage_error":@NO};
    }
    return self;
}

- (NSURL *)playerNameSaveRoot { return _root; }

- (void)dealloc
{
    if (_database) sqlite3_close(_database);
}

- (void)close
{
    dispatch_sync(_queue, ^{
        if (self->_database) sqlite3_close(self->_database);
        self->_database = NULL;
        self->_activePath = nil;
        self->_activeProfile = nil;
        self->_activeMonths = nil;
        self->_menuKind = 0;
        self->_requestedContext = nil;
        [self publishSnapshot];
    });
}

/* All database operations and mutable state belong to _queue. */
- (BOOL)openDatabase
{
    if (_database) return YES;
    NSString *root = HPCanonicalRoot(_root);
    if (!root) return NO;
    NSString *path = [root stringByAppendingPathComponent:HPProgressDatabase];
    for (NSString *suffix in @[@"", @"-wal", @"-shm", @"-journal"])
        if (!HPRegularDatabaseFile([path stringByAppendingString:suffix])) return NO;
    int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX;
#ifdef SQLITE_OPEN_NOFOLLOW
    flags |= SQLITE_OPEN_NOFOLLOW;
#endif
    sqlite3 *database = NULL;
    if (sqlite3_open_v2(path.fileSystemRepresentation, &database, flags, NULL) != SQLITE_OK) {
        if (database) sqlite3_close(database);
        return NO;
    }
    sqlite3_busy_timeout(database, 250);
    sqlite3_stmt *statement = NULL;
    int version = -1;
    if (sqlite3_prepare_v2(database, "PRAGMA user_version", -1, &statement, NULL) == SQLITE_OK &&
        sqlite3_step(statement) == SQLITE_ROW) version = sqlite3_column_int(statement, 0);
    sqlite3_finalize(statement);
    BOOL success = (version == 0 || version == 1) &&
        HPExec(database, "PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON; PRAGMA trusted_schema=OFF;") &&
        HPExec(database,
            "BEGIN IMMEDIATE;"
            "CREATE TABLE IF NOT EXISTS events ("
            " profile_id TEXT NOT NULL, seed INTEGER NOT NULL, game_number INTEGER NOT NULL,"
            " map_crc INTEGER NOT NULL, victim INTEGER NOT NULL, month TEXT NOT NULL,"
            " PRIMARY KEY(profile_id,seed,game_number,map_crc,victim)) WITHOUT ROWID;"
            "CREATE TABLE IF NOT EXISTS months (profile_id TEXT NOT NULL, month TEXT NOT NULL,"
            " kills INTEGER NOT NULL CHECK(kills>=0), xp INTEGER NOT NULL CHECK(xp>=0),"
            " PRIMARY KEY(profile_id,month)) WITHOUT ROWID;"
            "PRAGMA user_version=1; COMMIT;");
    if (!success) {
        HPExec(database, "ROLLBACK");
        sqlite3_close(database);
        return NO;
    }
    chmod(path.fileSystemRepresentation, 0600);
    _database = database;
    return YES;
}

- (NSDictionary<NSString *, NSNumber *> *)monthsForProfile:(NSString *)profile
{
    if (![self openDatabase]) return nil;
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(_database,
        "SELECT month,xp,kills FROM months WHERE profile_id=? ORDER BY month DESC", -1, &statement, NULL) != SQLITE_OK)
        return nil;
    sqlite3_bind_text(statement, 1, profile.UTF8String, -1, SQLITE_TRANSIENT);
    NSMutableDictionary *months = [NSMutableDictionary dictionary];
    int result;
    while ((result = sqlite3_step(statement)) == SQLITE_ROW) {
        const unsigned char *month = sqlite3_column_text(statement, 0);
        sqlite3_int64 xp = sqlite3_column_int64(statement, 1), kills = sqlite3_column_int64(statement, 2);
        NSString *key = month ? [NSString stringWithUTF8String:(const char *)month] : nil;
        if (!HPProgressSeasonForMonth(key) || xp < 0 || kills < 0 || xp != kills) { result = SQLITE_CORRUPT; break; }
        months[key] = @(xp);
    }
    sqlite3_finalize(statement);
    return result == SQLITE_DONE ? [months copy] : nil;
}

- (NSDictionary *)snapshotForProfile:(NSString *)profile months:(NSDictionary *)months date:(NSDate *)date
{
    NSString *season = HPProgressSeasonForMonth(HPProgressMonth(date, _calendar));
    NSDictionary *seasons = HPProgressSeasonTotals(months);
    if (!season || !seasons) return nil;
    NSMutableArray *history = [NSMutableArray array];
    NSArray *keys = [[seasons allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [b compare:a];
    }];
    for (NSString *key in keys) {
        if ([key isEqualToString:season]) continue;
        [history addObject:@{@"profile_id":profile, @"season":key, @"xp":seasons[key], @"kills":seasons[key]}];
    }
    NSNumber *xp = seasons[season] ?: @0;
    return @{@"profile_id":profile, @"season":season, @"xp":xp, @"kills":xp, @"history":[history copy]};
}

- (NSDictionary *)snapshotForProfilePath:(NSString *)profilePath date:(NSDate *)date
{
    NSString *key = HPProgressPathKey(profilePath);
    if (!key || !date) return nil;
    __block NSDictionary *snapshot;
    dispatch_sync(_queue, ^{
        NSString *profile = HPProfileID(self->_root, key);
        NSDictionary *months = profile ? [self monthsForProfile:profile] : nil;
        if (months) snapshot = [self snapshotForProfile:profile months:months date:date];
    });
    return snapshot;
}

- (HPHaloProgressResult)recordKill:(HPHaloProgressKillV1)event profilePath:(NSString *)profilePath date:(NSDate *)date
{
    NSString *key = HPProgressPathKey(profilePath);
    if (!key || !date || event.version != 1 || event.size != sizeof(event) ||
        event.game_number > INT32_MAX || event.victim_full_datum == UINT32_MAX ||
        !(event.victim_full_datum >> 16)) return HPHaloProgressInvalid;
    __block HPHaloProgressResult result = HPHaloProgressRetry;
    dispatch_sync(_queue, ^{
        self->_storageError = YES;
        NSString *pathKey = HPEventKey(key, event);
        NSString *eventKey = self->_pendingPaths[pathKey] ?: pathKey;
        NSMutableDictionary *pending = self->_pending[eventKey];
        NSString *profile = pending[@"profile"] ?: HPProfileID(self->_root, key);
        if (profile) {
            NSString *identityKey = HPEventKey(profile, event);
            NSMutableDictionary *identityPending = self->_pending[identityKey];
            if (identityPending) pending = identityPending;
            if (![eventKey isEqualToString:identityKey]) [self->_pending removeObjectForKey:eventKey];
            eventKey = identityKey;
        }
        if (!pending) {
            if (self->_pending.count >= 256) return; /* Guest keeps the same event for retry. */
            pending = [@{@"month":HPProgressMonth(date, self->_calendar)} mutableCopy];
        }
        self->_pending[eventKey] = pending;
        if (!profile) return;
        pending[@"profile"] = profile;
        if (self->_pendingPaths.count >= 1024) [self->_pendingPaths removeAllObjects];
        self->_pendingPaths[pathKey] = eventKey;
        /* UUID + event preserves its first-seen storage month, and therefore
           season, when a profile rename retargets the frozen directory path. */
        if (![eventKey isEqualToString:pathKey]) {
            [self->_pending removeObjectForKey:pathKey];
        }
        if (![self openDatabase] || !HPExec(self->_database, "BEGIN IMMEDIATE")) return;
        sqlite3_stmt *statement = NULL;
        BOOL success = sqlite3_prepare_v2(self->_database,
            "INSERT OR IGNORE INTO events(profile_id,seed,game_number,map_crc,victim,month) VALUES(?,?,?,?,?,?)",
            -1, &statement, NULL) == SQLITE_OK;
        if (success) {
            sqlite3_bind_text(statement, 1, profile.UTF8String, -1, SQLITE_TRANSIENT);
            sqlite3_bind_int64(statement, 2, event.session_seed);
            sqlite3_bind_int64(statement, 3, event.game_number);
            sqlite3_bind_int64(statement, 4, event.map_crc);
            sqlite3_bind_int64(statement, 5, event.victim_full_datum);
            sqlite3_bind_text(statement, 6, [pending[@"month"] UTF8String], -1, SQLITE_TRANSIENT);
            success = sqlite3_step(statement) == SQLITE_DONE;
        }
        sqlite3_finalize(statement);
        BOOL inserted = success && sqlite3_changes(self->_database) == 1;
        if (inserted) {
            statement = NULL;
            success = sqlite3_prepare_v2(self->_database,
                "INSERT INTO months(profile_id,month,kills,xp) VALUES(?,?,1,1) "
                "ON CONFLICT(profile_id,month) DO UPDATE SET kills=kills+1,xp=xp+1 "
                "WHERE kills<9223372036854775807 AND xp<9223372036854775807", -1, &statement, NULL) == SQLITE_OK;
            if (success) {
                sqlite3_bind_text(statement, 1, profile.UTF8String, -1, SQLITE_TRANSIENT);
                sqlite3_bind_text(statement, 2, [pending[@"month"] UTF8String], -1, SQLITE_TRANSIENT);
                success = sqlite3_step(statement) == SQLITE_DONE && sqlite3_changes(self->_database) == 1;
            }
            sqlite3_finalize(statement);
        }
        if (!success || !HPExec(self->_database, "COMMIT")) {
            HPExec(self->_database, "ROLLBACK");
            return;
        }
        result = HPHaloProgressCommitted;
        self->_storageError = NO;
        [self->_pending removeObjectForKey:eventKey];
        NSArray *aliases = [self->_pendingPaths allKeysForObject:eventKey];
        [self->_pendingPaths removeObjectsForKeys:aliases];
        if (inserted && [profile isEqualToString:self->_activeProfile]) {
            NSDictionary *months = [self monthsForProfile:profile];
            if (months) self->_activeMonths = months;
        }
    });
    dispatch_async(_queue, ^{ [self publishSnapshot]; });
    return result;
}

- (void)presentMenuContext:(NSDictionary *)context
{
    dispatch_async(_queue, ^{
        self->_requestedContext = context;
        if (!context) {
            self->_menuKind = 0;
            self->_activePath = nil;
            self->_activeProfile = nil;
            self->_activeMonths = nil;
            [self publishSnapshot];
            return;
        }
        NSString *key = context[@"path"];
        if (![key isEqualToString:self->_activePath] || !self->_activeMonths) {
            NSString *profile = HPProfileID(self->_root, key);
            NSDictionary *months = profile ? [self monthsForProfile:profile] : nil;
            self->_activePath = key;
            self->_activeProfile = months ? profile : nil;
            self->_activeMonths = months;
            if (!months) self->_storageError = YES;
            else if (!self->_pending.count) self->_storageError = NO;
        }
        self->_menuKind = self->_activeMonths ? [context[@"kind"] unsignedIntegerValue] : 0;
        self->_localPlayer = [context[@"player"] unsignedIntegerValue];
        [self publishSnapshot];
    });
}

- (void)publishSnapshot
{
    NSDictionary *snapshot;
    if (!_menuKind || !_activeProfile || !_activeMonths) {
        NSMutableDictionary *hidden = [@{@"visible":@NO, @"storage_error":@(_storageError)} mutableCopy];
        if (_requestedContext) {
            hidden[@"menu_context"] = @YES;
            hidden[@"menu_kind"] = _requestedContext[@"kind"];
            hidden[@"local_player"] = _requestedContext[@"player"];
        }
        snapshot = [hidden copy];
    }
    else {
        NSMutableDictionary *visible = [[self snapshotForProfile:_activeProfile
            months:_activeMonths date:NSDate.date] mutableCopy];
        if (!visible) {
            _storageError = YES;
            snapshot = @{@"visible":@NO, @"storage_error":@YES, @"menu_context":@YES,
                @"menu_kind":@(_menuKind), @"local_player":@(_localPlayer)};
        } else {
            visible[@"visible"] = @YES;
            visible[@"menu_kind"] = @(_menuKind);
            visible[@"local_player"] = @(_localPlayer);
            visible[@"storage_error"] = @(_storageError);
            visible[@"menu_context"] = @YES;
            snapshot = [visible copy];
        }
    }
    NSDictionary *context = _requestedContext;
    @synchronized(self) { _publishedSnapshot = snapshot; _publishedContext = context; }
}

- (void)invalidateMenuSnapshot
{
    @synchronized(self) { _publishedSnapshot = @{@"visible":@NO}; _publishedContext = nil; }
}

- (NSDictionary *)menuSnapshotForContext:(NSDictionary *)context
{
    NSDictionary *snapshot;
    BOOL refresh = NO;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    @synchronized(self) {
        snapshot = [context isEqual:_publishedContext] ? _publishedSnapshot : @{@"visible":@NO};
        if (now - _lastCalendarRefresh >= 1.0) {
            _lastCalendarRefresh = now;
            refresh = YES;
        }
    }
    if (refresh) dispatch_async(_queue, ^{ [self publishSnapshot]; });
    return snapshot;
}
@end

static HPHaloProgressStore *HPProgressStore;
static NSDictionary *HPProgressPendingMenu, *HPProgressPresentedMenu;
static NSTimeInterval HPProgressMenuRefresh;

/* blam.sav begins with the player's name: up to 11 UTF-16LE characters, NUL
   terminated, as set by the game's own profile editor. */
static NSString *HPReadPlayerName(int directory)
{
    int file = openat(directory, "blam.sav", O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (file < 0) return nil;
    struct stat status;
    uint8_t bytes[24] = {0};
    BOOL regular = fstat(file, &status) == 0 && S_ISREG(status.st_mode) && status.st_size >= (off_t)sizeof(bytes);
    ssize_t length = regular ? read(file, bytes, sizeof(bytes)) : -1;
    close(file);
    if (length != (ssize_t)sizeof(bytes)) return nil;
    unichar characters[12];
    NSUInteger count = 0;
    for (; count < 12; count++) {
        characters[count] = (unichar)(bytes[count * 2] | (bytes[count * 2 + 1] << 8));
        if (!characters[count]) break;
    }
    if (!count || count > 11) return nil;
    NSString *name = [NSString stringWithCharacters:characters length:count];
    NSMutableCharacterSet *invalid = [NSCharacterSet.controlCharacterSet mutableCopy];
    [invalid formUnionWithCharacterSet:NSCharacterSet.illegalCharacterSet];
    if ([name rangeOfCharacterFromSet:invalid].location != NSNotFound) return nil;
    name = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    return name.length ? name : nil;
}

NSString *HPHaloProgressPlayerName(NSString *guestPath)
{
    NSString *key = HPProgressPathKey(guestPath);
    HPHaloProgressStore *store;
    @synchronized(HPHaloProgressStore.class) { store = HPProgressStore; }
    NSURL *root = [store playerNameSaveRoot];
    if (!key || !root) return nil;
    int directory = HPProfileDirectory(root, key);
    if (directory < 0) return nil;
    NSString *name = HPReadPlayerName(directory);
    close(directory);
    return name;
}


void HPHaloProgressConfigure(NSString *saveRoot)
{
    HPHaloProgressStore *store = [[HPHaloProgressStore alloc] initWithSaveRootURL:
        [NSURL fileURLWithPath:saveRoot isDirectory:YES] calendar:nil];
    @synchronized(HPHaloProgressStore.class) {
        HPProgressStore = store;
        HPProgressPendingMenu = nil;
        HPProgressPresentedMenu = nil;
        HPProgressMenuRefresh = 0;
    }
#if TARGET_OS_IOS
    HPHaloCareerStatsConfigure([NSURL fileURLWithPath:saveRoot isDirectory:YES], store);
#endif
}

NSDictionary *HPHaloProgressMenuSnapshot(void)
{
    HPHaloProgressStore *store;
    NSDictionary *context;
    @synchronized(HPHaloProgressStore.class) {
        if (!HPProgressPresentedMenu) return @{@"visible":@NO};
        store = HPProgressStore;
        context = HPProgressPresentedMenu;
    }
    NSDictionary *snapshot = store ? [store menuSnapshotForContext:context] : @{@"visible":@NO};
    /* Keep the existing boolean menu_context contract. Native local Stats uses
       this validated guest path to resolve the same saved-profile UUID as XP. */
    if ([snapshot[@"visible"] boolValue] && [context[@"path"] isKindOfClass:NSString.class]) {
        NSMutableDictionary *visible = [snapshot mutableCopy];
        visible[@"guest_profile_path"] = context[@"path"];
        return [visible copy];
    }
    return snapshot;
}

void xg_progress_frame_presented(void)
{
    @synchronized(HPHaloProgressStore.class) {
        NSDictionary *pending = HPProgressPendingMenu;
        HPProgressPendingMenu = nil;
        if (pending == nil && HPProgressPresentedMenu == nil) return;
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        /* Successful contexts are entirely cached. A failed initial load may
           retry at most once a second, rather than opening SQLite each frame. */
        if ([pending isEqual:HPProgressPresentedMenu] && now - HPProgressMenuRefresh < 1.0) return;
        if (![pending isEqual:HPProgressPresentedMenu]) [HPProgressStore invalidateMenuSnapshot];
        HPProgressPresentedMenu = pending;
        HPProgressMenuRefresh = now;
        [HPProgressStore presentMenuContext:pending];
    }
}

/* Bounded payloads can straddle VM regions. Verify that every byte is currently
   readable before copying; guest memory is never retained for asynchronous work. */
static BOOL HPCopyGuestBytes(uint32_t pointer, uint32_t length, void *destination)
{
    if (!xg_base || !pointer || !length || (uint64_t)pointer + length > (UINT64_C(1) << 32)) return NO;
    vm_address_t cursor = (vm_address_t)xg_base + pointer;
    vm_address_t end = cursor + length;
    if (end < cursor) return NO;
    while (cursor < end) {
        vm_address_t region = cursor;
        vm_size_t size = 0;
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t object = MACH_PORT_NULL;
        kern_return_t result = vm_region_64(mach_task_self(), &region, &size,
            VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object);
        if (object != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), object);
        if (result != KERN_SUCCESS || region > cursor || !size || !(info.protection & VM_PROT_READ) ||
            region + size <= cursor) return NO;
        cursor = MIN(end, region + size);
    }
    memcpy(destination, (const void *)((uintptr_t)xg_base + pointer), length);
    return YES;
}

static NSString *HPCopyGuestProfile(uint32_t pointer, uint32_t length)
{
    if (!length || length > 260) return nil;
    char bytes[260];
    if (!HPCopyGuestBytes(pointer, length, bytes) || memchr(bytes, 0, length)) return nil;
    NSString *path = [[NSString alloc] initWithBytes:bytes length:length encoding:NSASCIIStringEncoding];
    return HPProgressPathKey(path);
}

uint32_t xh_host_halopad_progress_kill_v1(uint32_t path, uint32_t pathLength,
                                        uint32_t eventPointer, uint32_t eventLength)
{
    @autoreleasepool {
        if (eventLength != sizeof(HPHaloProgressKillV1)) return HPHaloProgressInvalid;
        NSString *profile = HPCopyGuestProfile(path, pathLength);
        uint32_t words[6];
        if (!profile || !HPCopyGuestBytes(eventPointer, eventLength, words)) return HPHaloProgressInvalid;
        for (unsigned index = 0; index < 6; index++) words[index] = CFSwapInt32LittleToHost(words[index]);
        HPHaloProgressKillV1 event;
        memcpy(&event, words, sizeof(event));
        HPHaloProgressStore *store;
        @synchronized(HPHaloProgressStore.class) { store = HPProgressStore; }
        return store ? [store recordKill:event profilePath:profile date:NSDate.date] : HPHaloProgressRetry;
    }
}

uint32_t xh_host_halopad_progress_menu_v1(uint32_t path, uint32_t pathLength,
                                        uint32_t kind, uint32_t localPlayer)
{
    @autoreleasepool {
        if (kind > 2 || localPlayer >= 4) return HPHaloProgressInvalid;
        NSString *profile = kind ? HPCopyGuestProfile(path, pathLength) : nil;
        if (kind && !profile) return HPHaloProgressInvalid;
        @synchronized(HPHaloProgressStore.class) {
            HPProgressPendingMenu = kind ? @{@"path":profile, @"kind":@(kind), @"player":@(localPlayer)} : nil;
        }
        return HPHaloProgressCommitted; /* Menu context has no durable write acknowledgement. */
    }
}
