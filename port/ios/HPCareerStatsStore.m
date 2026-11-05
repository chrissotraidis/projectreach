#import "HPCareerStatsStore.h"
#import <sqlite3.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#include <sys/stat.h>
#include <unistd.h>
#include <math.h>

NSNotificationName const HPCareerMedalEarnedNotification=@"HPCareerMedalEarnedNotification";
static NSString *const HCErrorDomain=@"dev.halopad.career";
static NSError *HCError(NSInteger code,NSString *message) { return [NSError errorWithDomain:HCErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey:message?:@"Career stats unavailable"}]; }
static void HCSetError(NSError **error,NSError *value) { if(error)*error=value; }
static NSString *HCProfile(NSString *value) { if(![value isKindOfClass:NSString.class])return nil;NSUUID *uuid=[[NSUUID alloc]initWithUUIDString:value];return uuid.UUIDString; }
static NSString *HCText(const char *bytes,size_t capacity) {
    const char *end=memchr(bytes,0,capacity);if(!end)return nil;
    NSString *v=[[NSString alloc]initWithBytes:bytes length:(NSUInteger)(end-bytes) encoding:NSUTF8StringEncoding];
    if(!v||[v rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound)return @"unknown";return v.length?v:@"unknown";
}
static NSString *HCSeason(NSCalendar *calendar,NSDate *date) {
    NSDateComponents *p=[calendar components:NSCalendarUnitYear|NSCalendarUnitMonth fromDate:date];
    return [NSString stringWithFormat:@"%04ld-Q%ld",(long)p.year,(long)((p.month-1)/3+1)];
}
static NSString *HCISODate(double t) {return [[NSISO8601DateFormatter new]stringFromDate:[NSDate dateWithTimeIntervalSince1970:t]];}
static BOOL HCMedalPayloadValid(const HPCareerStatsEventV1 *e) {
    if(!e||e->version!=1||e->size!=sizeof(*e)||e->kind!=HPCareerMedal||e->local_player>=4||e->result||e->reserved<1||e->reserved>15||(e->flags&~(HPCareerReplicatedClient|HPCareerTransientProfile))||e->kills>INT32_MAX||e->deaths>INT32_MAX||e->assists>INT32_MAX||e->streak>INT32_MAX||!e->event_id||e->event_id!=e->kills)return NO;
    unsigned int threshold=e->reserved<=9?e->reserved+1:(e->reserved-9)*5;
    return e->kills>=threshold&&(e->reserved<10||e->streak>=threshold)&&memchr(e->map,0,sizeof e->map)&&memchr(e->mode,0,sizeof e->mode)&&memchr(e->weapon,0,sizeof e->weapon);
}
static const char *HCSchema=
"CREATE TABLE IF NOT EXISTS career_events (profile TEXT NOT NULL,kind INTEGER NOT NULL,seed INTEGER NOT NULL,game INTEGER NOT NULL,crc INTEGER NOT NULL,event INTEGER NOT NULL,local_player INTEGER NOT NULL,streak INTEGER NOT NULL,result INTEGER NOT NULL,mode_id INTEGER NOT NULL,map TEXT NOT NULL,mode TEXT NOT NULL,weapon TEXT NOT NULL,occurred REAL NOT NULL,season TEXT NOT NULL,PRIMARY KEY(profile,kind,seed,game,crc,event)) WITHOUT ROWID;"
"CREATE TABLE IF NOT EXISTS career_matches (profile TEXT NOT NULL,seed INTEGER NOT NULL,game INTEGER NOT NULL,crc INTEGER NOT NULL,baseline_k INTEGER NOT NULL,baseline_d INTEGER NOT NULL,baseline_a INTEGER NOT NULL,total_k INTEGER NOT NULL,total_d INTEGER NOT NULL,total_a INTEGER NOT NULL,entered INTEGER NOT NULL,result INTEGER NOT NULL,best_streak INTEGER NOT NULL,last_tick INTEGER NOT NULL,replicated INTEGER NOT NULL,occurred REAL NOT NULL,season TEXT NOT NULL,map TEXT NOT NULL,mode TEXT NOT NULL,PRIMARY KEY(profile,seed,game,crc)) WITHOUT ROWID;"
"CREATE TABLE IF NOT EXISTS career_tracking(profile TEXT PRIMARY KEY,started REAL NOT NULL) WITHOUT ROWID;"
"CREATE TABLE IF NOT EXISTS career_periods(profile TEXT NOT NULL,seed INTEGER NOT NULL,game INTEGER NOT NULL,crc INTEGER NOT NULL,season TEXT NOT NULL,kills INTEGER NOT NULL,deaths INTEGER NOT NULL,assists INTEGER NOT NULL,best_streak INTEGER NOT NULL,entered INTEGER NOT NULL,result INTEGER NOT NULL,PRIMARY KEY(profile,seed,game,crc,season)) WITHOUT ROWID;"
"CREATE TABLE IF NOT EXISTS career_medals(profile TEXT NOT NULL,seed INTEGER NOT NULL,game INTEGER NOT NULL,crc INTEGER NOT NULL,event INTEGER NOT NULL,medal_id INTEGER NOT NULL CHECK(medal_id BETWEEN 1 AND 15),local_player INTEGER NOT NULL,flags INTEGER NOT NULL,occurred REAL NOT NULL,season TEXT NOT NULL,PRIMARY KEY(profile,seed,game,crc,event,medal_id)) WITHOUT ROWID;"
"CREATE TABLE IF NOT EXISTS career_medal_tracking(profile TEXT PRIMARY KEY,started REAL NOT NULL) WITHOUT ROWID;";

@interface HPCareerStatsStore () {sqlite3 *_db;NSRecursiveLock *_lock;NSCalendar *_calendar;}
@end
@implementation HPCareerStatsStore
- (BOOL)exec:(const char *)sql error:(NSError **)error {
    int rc=sqlite3_exec(_db,sql,NULL,NULL,NULL);if(rc!=SQLITE_OK){HCSetError(error,HCError(rc,[NSString stringWithUTF8String:sqlite3_errmsg(_db)]));return NO;}return YES;
}
- (sqlite3_stmt *)prepare:(const char *)sql error:(NSError **)error {
    sqlite3_stmt *s=NULL;int rc=sqlite3_prepare_v2(_db,sql,-1,&s,NULL);if(rc!=SQLITE_OK){HCSetError(error,HCError(rc,[NSString stringWithUTF8String:sqlite3_errmsg(_db)]));return NULL;}return s;
}
- (BOOL)step:(sqlite3_stmt *)s error:(NSError **)error {
    int rc=sqlite3_step(s);if(rc!=SQLITE_DONE){HCSetError(error,HCError(rc,[NSString stringWithUTF8String:sqlite3_errmsg(_db)]));return NO;}return YES;
}
- (instancetype)initWithSaveRootURL:(NSURL *)root calendar:(NSCalendar *)calendar error:(NSError **)error {
    if(!(self=[super init]))return nil;_lock=[NSRecursiveLock new];
    _calendar=calendar?[calendar copy]:[[NSCalendar alloc]initWithCalendarIdentifier:NSCalendarIdentifierGregorian];if(!calendar)_calendar.timeZone=NSTimeZone.localTimeZone;
    if(!root.isFileURL){HCSetError(error,HCError(1,@"A local save root is required"));return nil;}
    struct stat st;if(lstat(root.fileSystemRepresentation,&st)!=0||!S_ISDIR(st.st_mode)||S_ISLNK(st.st_mode)){HCSetError(error,HCError(2,@"Save root must be an existing directory"));return nil;}
    NSURL *dbURL=[root URLByAppendingPathComponent:@".halopad-career.sqlite3"];
    for(NSString *suffix in @[@"",@"-wal",@"-shm",@"-journal"]) {
        NSString *path=[dbURL.path stringByAppendingString:suffix];if(lstat(path.fileSystemRepresentation,&st)==0&&(!S_ISREG(st.st_mode)||S_ISLNK(st.st_mode)||st.st_nlink!=1)){HCSetError(error,HCError(3,@"Career database path is not a regular local file"));return nil;}
    }
    int flags=SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE|SQLITE_OPEN_FULLMUTEX;
#ifdef SQLITE_OPEN_NOFOLLOW
    flags|=SQLITE_OPEN_NOFOLLOW;
#endif
    int rc=sqlite3_open_v2(dbURL.fileSystemRepresentation,&_db,flags,NULL);
    if(rc!=SQLITE_OK){HCSetError(error,HCError(rc,@"Unable to open career database"));[self close];return nil;}chmod(dbURL.fileSystemRepresentation,0600);sqlite3_busy_timeout(_db,250);
    sqlite3_stmt *s=[self prepare:"PRAGMA user_version" error:error];if(!s){[self close];return nil;}
    int version=sqlite3_step(s)==SQLITE_ROW?sqlite3_column_int(s,0):-1;sqlite3_finalize(s);
    if(version<0||version>4){HCSetError(error,HCError(4,@"Unsupported career database version"));[self close];return nil;}
    if(![self exec:"PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON; PRAGMA trusted_schema=OFF; BEGIN IMMEDIATE;" error:error]){[self close];return nil;}
    BOOL ok=[self exec:HCSchema error:error];
    /* v1 event-only companion databases migrate without touching the original XP DB. */
    if(ok&&version==1)ok=[self exec:
      "INSERT OR IGNORE INTO career_matches SELECT profile,seed,game,crc,0,0,0,SUM(kind=2),SUM(kind=3),SUM(kind=4),MAX(kind=1),COALESCE(MAX(CASE WHEN kind=5 THEN result ELSE -1 END),-1),MAX(CASE WHEN kind=2 THEN streak ELSE 0 END),-1,0,MIN(occurred),MIN(season),MIN(map),MIN(mode) FROM career_events GROUP BY profile,seed,game,crc;" error:error];
    if(ok&&version<3)ok=[self exec:
      "INSERT OR IGNORE INTO career_periods SELECT profile,seed,game,crc,season,MAX(0,total_k-baseline_k),MAX(0,total_d-baseline_d),MAX(0,total_a-baseline_a),best_streak,entered,result FROM career_matches;" error:error];
    if(ok)ok=[self exec:
      "INSERT OR IGNORE INTO career_tracking SELECT profile,MIN(occurred) FROM career_matches GROUP BY profile;"
      "CREATE INDEX IF NOT EXISTS career_season ON career_matches(profile,season);"
      "CREATE INDEX IF NOT EXISTS career_event_season ON career_events(profile,season);"
      "CREATE INDEX IF NOT EXISTS career_medal_season ON career_medals(profile,season);"
      "CREATE INDEX IF NOT EXISTS career_latest_match ON career_matches(profile,occurred DESC,game DESC,seed DESC,crc DESC);"
      "PRAGMA user_version=4; COMMIT;" error:error];
    if(!ok){sqlite3_exec(_db,"ROLLBACK",NULL,NULL,NULL);[self close];return nil;}return self;
}
- (void)close {[_lock lock];if(_db){sqlite3_close_v2(_db);_db=NULL;}[_lock unlock];}
- (void)dealloc {[self close];}
static void HCBindText(sqlite3_stmt *s,int i,NSString *v){sqlite3_bind_text(s,i,v.UTF8String,-1,SQLITE_TRANSIENT);}
static void HCBindMatch(sqlite3_stmt *s,NSString *p,const HPCareerStatsEventV1 *e){HCBindText(s,1,p);sqlite3_bind_int64(s,2,e->session_seed);sqlite3_bind_int64(s,3,e->game_number);sqlite3_bind_int64(s,4,e->map_crc);}
/* Medal tracking starts with new activity after this update, never from legacy
 * kill counts or old best streaks. The INSERT shares the event transaction. */
- (BOOL)beginMedalTracking:(NSString *)profile date:(NSDate *)date error:(NSError **)error {
    sqlite3_stmt *s=[self prepare:"INSERT INTO career_medal_tracking(profile,started) VALUES(?,?) ON CONFLICT(profile) DO UPDATE SET started=MIN(started,excluded.started)" error:error];if(!s)return NO;
    HCBindText(s,1,profile);sqlite3_bind_double(s,2,date.timeIntervalSince1970);BOOL ok=[self step:s error:error];sqlite3_finalize(s);return ok;
}
- (uint32_t)recordMedal:(const HPCareerStatsEventV1 *)e profile:(NSString *)profile date:(NSDate *)date error:(NSError **)error {
    [_lock lock];if(!_db){HCSetError(error,HCError(7,@"Career database is closed"));[_lock unlock];return 0;}
    if(![self exec:"BEGIN IMMEDIATE" error:error]){[_lock unlock];return 0;}
    sqlite3_stmt *s=[self prepare:"SELECT baseline_k FROM career_matches WHERE profile=? AND seed=? AND game=? AND crc=?" error:error];BOOL ok=s!=NULL;
    if(s){HCBindMatch(s,profile,e);int rc=sqlite3_step(s);if(rc!=SQLITE_ROW){ok=NO;HCSetError(error,HCError(rc==SQLITE_DONE?9:rc,@"Waiting for medal match entry baseline"));}sqlite3_finalize(s);}
    BOOL inserted=NO;NSString *season=HCSeason(_calendar,date);
    if(ok){s=[self prepare:"INSERT OR IGNORE INTO career_medals(profile,seed,game,crc,event,medal_id,local_player,flags,occurred,season) VALUES(?,?,?,?,?,?,?,?,?,?)" error:error];ok=s!=NULL;
        if(s){HCBindMatch(s,profile,e);sqlite3_bind_int64(s,5,e->event_id);sqlite3_bind_int64(s,6,e->reserved);sqlite3_bind_int64(s,7,e->local_player);sqlite3_bind_int64(s,8,e->flags);sqlite3_bind_double(s,9,date.timeIntervalSince1970);HCBindText(s,10,season);ok=[self step:s error:error];inserted=ok&&sqlite3_changes(_db)>0;sqlite3_finalize(s);}}
    if(ok)ok=[self beginMedalTracking:profile date:date error:error];
    if(ok)ok=[self exec:"COMMIT" error:error];if(!ok)sqlite3_exec(_db,"ROLLBACK",NULL,NULL,NULL);[_lock unlock];
    if(ok&&inserted){NSString *timestamp=HCISODate(date.timeIntervalSince1970);NSDictionary *info=@{@"profile_id":profile,@"medal_id":@(e->reserved),@"season":season,@"event_id":@(e->event_id),@"awarded_at":timestamp,@"earned_at":timestamp};
        dispatch_async(dispatch_get_main_queue(),^{[NSNotificationCenter.defaultCenter postNotificationName:HPCareerMedalEarnedNotification object:nil userInfo:info];});
        const char *trace=getenv("HALOPAD_CAREER_TRACE");if(trace&&!strcmp(trace,"true"))fprintf(stderr,"HALOPAD_MEDAL {\"medal_id\":%u,\"kill\":%u,\"season\":\"%s\"}\n",e->reserved,e->event_id,season.UTF8String);
    }
    return ok?1:0;
}
/* Period allocations keep calendar-boundary kills/deaths/assists in their observed
 * local quarter. A later authoritative downward correction removes the most recent
 * allocations first, so no quarter can become negative and lifetime stays exact. */
- (BOOL)allocatePeriods:(const HPCareerStatsEventV1 *)e profile:(NSString *)profile date:(NSDate *)date old:(int64_t *)old now:(int64_t *)now newMatch:(BOOL)newMatch error:(NSError **)error {
    NSString *season=HCSeason(_calendar,date);
    sqlite3_stmt *s=[self prepare:"INSERT OR IGNORE INTO career_periods(profile,seed,game,crc,season,kills,deaths,assists,best_streak,entered,result) VALUES(?,?,?,?,?,0,0,0,0,0,-1)" error:error];if(!s)return NO;HCBindMatch(s,profile,e);HCBindText(s,5,season);BOOL ok=[self step:s error:error];sqlite3_finalize(s);if(!ok)return NO;
    NSArray *columns=@[@"kills",@"deaths",@"assists"];
    for(int i=0;i<3;i++) {
        int64_t before=newMatch?0:MAX(0,old[i+3]-old[i]),after=MAX(0,now[i+3]-now[i]),delta=after-before;
        if(!delta)continue;NSString *col=columns[i];
        if(delta>0) {
            NSString *sql=[NSString stringWithFormat:@"UPDATE career_periods SET %@=%@+? WHERE profile=? AND seed=? AND game=? AND crc=? AND season=?",col,col];
            s=[self prepare:sql.UTF8String error:error];if(!s)return NO;sqlite3_bind_int64(s,1,delta);HCBindText(s,2,profile);sqlite3_bind_int64(s,3,e->session_seed);sqlite3_bind_int64(s,4,e->game_number);sqlite3_bind_int64(s,5,e->map_crc);HCBindText(s,6,season);ok=[self step:s error:error];sqlite3_finalize(s);if(!ok)return NO;
        } else {
            NSString *sql=[NSString stringWithFormat:@"SELECT season,%@ FROM career_periods WHERE profile=? AND seed=? AND game=? AND crc=? AND %@>0 ORDER BY season DESC",col,col];
            s=[self prepare:sql.UTF8String error:error];if(!s)return NO;HCBindMatch(s,profile,e);NSMutableArray *reductions=[NSMutableArray array];int rc;int64_t remaining=-delta;
            while((rc=sqlite3_step(s))==SQLITE_ROW){int64_t n=MIN(remaining,sqlite3_column_int64(s,1));if(n){[reductions addObject:@[[NSString stringWithUTF8String:(const char *)sqlite3_column_text(s,0)],@(n)]];remaining-=n;}}
            sqlite3_finalize(s);if(rc!=SQLITE_DONE||remaining){HCSetError(error,HCError(10,@"Inconsistent career period allocation"));return NO;}
            for(NSArray *row in reductions){sql=[NSString stringWithFormat:@"UPDATE career_periods SET %@=%@-? WHERE profile=? AND seed=? AND game=? AND crc=? AND season=?",col,col];s=[self prepare:sql.UTF8String error:error];if(!s)return NO;sqlite3_bind_int64(s,1,[row[1]longLongValue]);HCBindText(s,2,profile);sqlite3_bind_int64(s,3,e->session_seed);sqlite3_bind_int64(s,4,e->game_number);sqlite3_bind_int64(s,5,e->map_crc);HCBindText(s,6,row[0]);ok=[self step:s error:error];sqlite3_finalize(s);if(!ok)return NO;}
        }
    }
    {s=[self prepare:"UPDATE career_periods SET entered=1 WHERE profile=? AND seed=? AND game=? AND crc=? AND season=?" error:error];if(!s)return NO;HCBindMatch(s,profile,e);HCBindText(s,5,season);ok=[self step:s error:error];sqlite3_finalize(s);if(!ok)return NO;}
    if((e->kind==HPCareerKill||e->kind==HPCareerAuthoritativeTotals)&&e->streak){s=[self prepare:"UPDATE career_periods SET best_streak=MAX(best_streak,?) WHERE profile=? AND seed=? AND game=? AND crc=? AND season=?" error:error];if(!s)return NO;sqlite3_bind_int64(s,1,e->streak);HCBindText(s,2,profile);sqlite3_bind_int64(s,3,e->session_seed);sqlite3_bind_int64(s,4,e->game_number);sqlite3_bind_int64(s,5,e->map_crc);HCBindText(s,6,season);ok=[self step:s error:error];sqlite3_finalize(s);if(!ok)return NO;}
    if(now[7]>=0&&(newMatch||old[7]!=now[7])) {
        NSString *resultSeason=season;s=[self prepare:"SELECT season FROM career_periods WHERE profile=? AND seed=? AND game=? AND crc=? AND result>=0 LIMIT 1" error:error];if(!s)return NO;HCBindMatch(s,profile,e);int rc=sqlite3_step(s);if(rc==SQLITE_ROW)resultSeason=[NSString stringWithUTF8String:(const char *)sqlite3_column_text(s,0)];else if(rc!=SQLITE_DONE)ok=NO;sqlite3_finalize(s);if(!ok)return NO;
        s=[self prepare:"UPDATE career_periods SET result=? WHERE profile=? AND seed=? AND game=? AND crc=? AND season=?" error:error];if(!s)return NO;sqlite3_bind_int64(s,1,now[7]);HCBindText(s,2,profile);sqlite3_bind_int64(s,3,e->session_seed);sqlite3_bind_int64(s,4,e->game_number);sqlite3_bind_int64(s,5,e->map_crc);HCBindText(s,6,resultSeason);ok=[self step:s error:error];sqlite3_finalize(s);if(!ok)return NO;
    }
    return YES;
}
- (uint32_t)recordEvent:(const HPCareerStatsEventV1 *)e profileID:(NSString *)profileID date:(NSDate *)date error:(NSError **)error {
    NSString *profile=HCProfile(profileID);
    if(!e||!profile||!date||!isfinite(date.timeIntervalSince1970)||e->version!=1||e->size!=sizeof(*e)||e->kind<1||e->kind>7||e->local_player>=4||e->result>3||e->streak>INT32_MAX||e->kills>INT32_MAX||e->deaths>INT32_MAX||e->assists>INT32_MAX||(e->flags&~HPCareerReplicatedClient)||(e->kind!=HPCareerMedal&&e->reserved)||
       (e->kind!=HPCareerMatchEnd&&e->result!=0)||((e->kind==HPCareerMatchEnter||e->kind==HPCareerMatchEnd)&&e->event_id!=0)) {HCSetError(error,HCError(5,@"Invalid career event"));return 2;}
    NSString *map=HCText(e->map,sizeof e->map),*mode=HCText(e->mode,sizeof e->mode),*weapon=HCText(e->weapon,sizeof e->weapon);
    if(!map||!mode||!weapon){HCSetError(error,HCError(6,@"Invalid career event text"));return 2;}
    if(e->kind==HPCareerMedal){
        if(!HCMedalPayloadValid(e)){HCSetError(error,HCError(5,@"Invalid medal event"));return 2;}
        return [self recordMedal:e profile:profile date:date error:error];
    }
    [_lock lock];if(!_db){HCSetError(error,HCError(7,@"Career database is closed"));[_lock unlock];return 0;}
    if(![self exec:"BEGIN IMMEDIATE" error:error]){[_lock unlock];return 0;}
    sqlite3_stmt *s=[self prepare:"SELECT baseline_k,baseline_d,baseline_a,total_k,total_d,total_a,entered,result,best_streak,last_tick,replicated,occurred,season,map,mode FROM career_matches WHERE profile=? AND seed=? AND game=? AND crc=?" error:error];
    BOOL ok=s!=NULL,exists=NO;int64_t state[11]={0,0,0,0,0,0,1,-1,0,-1,0};double occurred=date.timeIntervalSince1970;NSString *season=HCSeason(_calendar,date),*matchMap=map,*matchMode=mode;
    if(s){HCBindMatch(s,profile,e);int rc=sqlite3_step(s);exists=rc==SQLITE_ROW;
        if(exists){for(int i=0;i<11;i++)state[i]=sqlite3_column_int64(s,i);occurred=sqlite3_column_double(s,11);season=[NSString stringWithUTF8String:(const char *)sqlite3_column_text(s,12)];matchMap=[NSString stringWithUTF8String:(const char *)sqlite3_column_text(s,13)];matchMode=[NSString stringWithUTF8String:(const char *)sqlite3_column_text(s,14)];}
        else if(rc!=SQLITE_DONE){ok=NO;HCSetError(error,HCError(rc,@"Unable to read match"));}sqlite3_finalize(s);
    }
    /* The guest queues genuine match entry before events. Without that baseline,
     * retry rather than claim kills that happened before tracking/joining. */
    if(ok&&!exists&&e->kind!=HPCareerMatchEnter){ok=NO;HCSetError(error,HCError(9,@"Waiting for match entry baseline"));}
    int64_t oldState[11];memcpy(oldState,state,sizeof state);
    BOOL detailNew=NO,apply=NO;
    if(ok&&e->kind!=HPCareerAuthoritativeTotals) {
        s=[self prepare:"INSERT OR IGNORE INTO career_events(profile,kind,seed,game,crc,event,local_player,streak,result,mode_id,map,mode,weapon,occurred,season) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)" error:error];ok=s!=NULL;
        if(s){HCBindText(s,1,profile);sqlite3_bind_int64(s,2,e->kind);sqlite3_bind_int64(s,3,e->session_seed);sqlite3_bind_int64(s,4,e->game_number);sqlite3_bind_int64(s,5,e->map_crc);sqlite3_bind_int64(s,6,e->event_id);sqlite3_bind_int64(s,7,e->local_player);sqlite3_bind_int64(s,8,e->streak);sqlite3_bind_int64(s,9,e->result);sqlite3_bind_int64(s,10,e->mode_id);HCBindText(s,11,map);HCBindText(s,12,mode);HCBindText(s,13,weapon);sqlite3_bind_double(s,14,date.timeIntervalSince1970);HCBindText(s,15,HCSeason(_calendar,date));ok=[self step:s error:error];detailNew=ok&&sqlite3_changes(_db)>0;sqlite3_finalize(s);}
    }
    if(ok) {
        if(!exists){state[0]=state[3]=e->kills;state[1]=state[4]=e->deaths;state[2]=state[5]=e->assists;state[10]=(e->flags&HPCareerReplicatedClient)!=0;apply=YES;}
        else if(e->kind==HPCareerAuthoritativeTotals) {
            /* Native game_time wraps at uint32. Older ticks cannot undo a newer tally. Equal-tick changed payloads
             * follow the ordered native dispatcher/FIFO, including corrections. */
            if(state[9]<0||(int32_t)(e->event_id-(uint32_t)state[9])>0||((uint32_t)state[9]==e->event_id&&(state[3]!=e->kills||state[4]!=e->deaths||state[5]!=e->assists||state[8]<e->streak))){state[3]=e->kills;state[4]=e->deaths;state[5]=e->assists;state[9]=e->event_id;state[10]=1;apply=YES;}
        } else if(detailNew&&e->kind!=HPCareerMatchEnter) {
            if(!(e->flags&HPCareerReplicatedClient)){state[3]=MAX(state[3],e->kills);state[4]=MAX(state[4],e->deaths);state[5]=MAX(state[5],e->assists);}apply=YES;
        }
        if(e->kind==HPCareerMatchEnd&&(state[7]<0||(state[7]==0&&e->result>0))){state[7]=e->result;apply=YES;}
        if(apply)state[8]=MAX(state[8],e->streak);
    }
    if(ok&&apply)ok=[self allocatePeriods:e profile:profile date:date old:oldState now:state newMatch:!exists error:error];
    if(ok&&apply) {
        s=[self prepare:"INSERT INTO career_matches(profile,seed,game,crc,baseline_k,baseline_d,baseline_a,total_k,total_d,total_a,entered,result,best_streak,last_tick,replicated,occurred,season,map,mode) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(profile,seed,game,crc) DO UPDATE SET total_k=excluded.total_k,total_d=excluded.total_d,total_a=excluded.total_a,result=excluded.result,best_streak=excluded.best_streak,last_tick=excluded.last_tick,replicated=excluded.replicated" error:error];ok=s!=NULL;
        if(s){HCBindMatch(s,profile,e);for(int i=0;i<11;i++)sqlite3_bind_int64(s,i+5,state[i]);sqlite3_bind_double(s,16,occurred);HCBindText(s,17,season);HCBindText(s,18,matchMap);HCBindText(s,19,matchMode);ok=[self step:s error:error];sqlite3_finalize(s);}
        if(ok){s=[self prepare:"INSERT OR IGNORE INTO career_tracking(profile,started) VALUES(?,?)" error:error];ok=s!=NULL;if(s){HCBindText(s,1,profile);sqlite3_bind_double(s,2,occurred);ok=[self step:s error:error];sqlite3_finalize(s);}}
    }
    if(ok)ok=[self beginMedalTracking:profile date:date error:error];
    if(ok)ok=[self exec:"COMMIT" error:error];if(!ok)sqlite3_exec(_db,"ROLLBACK",NULL,NULL,NULL);[_lock unlock];
    const char *trace=getenv("HALOPAD_CAREER_TRACE");
    if(ok&&trace&&!strcmp(trace,"true")) {
        NSDictionary *totals=[self snapshotForProfileID:profile date:date error:NULL][@"lifetime"];
        if(totals)fprintf(stderr,"HALOPAD_CAREER_STATS {\"event_kind\":%u,\"kills\":%lld,\"deaths\":%lld,\"assists\":%lld,\"matches\":%lld,\"wins\":%lld,\"losses\":%lld,\"draws\":%lld}\n",e->kind,[totals[@"kills"]longLongValue],[totals[@"deaths"]longLongValue],[totals[@"assists"]longLongValue],[totals[@"matches_played"]longLongValue],[totals[@"wins"]longLongValue],[totals[@"losses"]longLongValue],[totals[@"draws"]longLongValue]);
    }
    return ok?1:0;
}
static NSMutableDictionary *HCCounts(sqlite3_stmt *s,int offset) {
    static NSArray *names;static dispatch_once_t once;dispatch_once(&once,^{names=@[@"kills",@"deaths",@"assists",@"best_streak",@"matches_played",@"wins",@"losses",@"draws",@"unknown_results",@"completed_matches"];});
    NSMutableDictionary *v=[NSMutableDictionary dictionary];for(int i=0;i<10;i++)v[names[i]]=@(sqlite3_column_int64(s,offset+i));
    double deaths=[v[@"deaths"]doubleValue],kills=[v[@"kills"]doubleValue],known=[v[@"wins"]doubleValue]+[v[@"losses"]doubleValue]+[v[@"draws"]doubleValue];
    v[@"kd"]=@(deaths>0?kills/deaths:0);v[@"kd_defined"]=@(deaths>0);v[@"win_rate"]=@(known>0?100.0*[v[@"wins"]doubleValue]/known:0);v[@"win_rate_defined"]=@(known>0);v[@"win_rate_basis"]=@"known_completed_matches";v[@"incomplete_matches"]=@(MAX(0,[v[@"matches_played"]longLongValue]-[v[@"completed_matches"]longLongValue]));return v;
}
static NSString *HCAggregates=@"COALESCE(SUM(p.kills),0),COALESCE(SUM(p.deaths),0),COALESCE(SUM(p.assists),0),COALESCE(MAX(p.best_streak),0),COALESCE(SUM(p.entered),0),COALESCE(SUM(p.result=1),0),COALESCE(SUM(p.result=2),0),COALESCE(SUM(p.result=3),0),COALESCE(SUM(p.result=0),0),COALESCE(SUM(p.result>=0),0)";
- (NSDictionary *)countsForProfile:(NSString *)profile season:(NSString *)season error:(NSError **)error {
    NSString *aggregates=season?HCAggregates:[HCAggregates stringByReplacingOccurrencesOfString:@"COALESCE(SUM(p.entered),0)" withString:@"COUNT(DISTINCT printf('%u:%u:%u',m.seed,m.game,m.crc))"];
    NSString *sql=[NSString stringWithFormat:@"SELECT %@ FROM career_periods p JOIN career_matches m USING(profile,seed,game,crc) WHERE p.profile=?%@",aggregates,season?@" AND p.season=?":@""];
    sqlite3_stmt *s=[self prepare:sql.UTF8String error:error];if(!s)return nil;HCBindText(s,1,profile);if(season)HCBindText(s,2,season);int rc=sqlite3_step(s);NSDictionary *v=rc==SQLITE_ROW?HCCounts(s,0):nil;if(!v)HCSetError(error,HCError(rc,@"Unable to read career totals"));sqlite3_finalize(s);return v;
}
- (NSArray *)groupsForProfile:(NSString *)profile column:(NSString *)column season:(NSString *)season error:(NSError **)error {
    NSString *group=[column isEqualToString:@"season"]?@"p.season":[@"m." stringByAppendingString:column];
    NSString *sql=[NSString stringWithFormat:@"SELECT %@,%@ FROM career_periods p JOIN career_matches m USING(profile,seed,game,crc) WHERE p.profile=?%@ GROUP BY %@ ORDER BY SUM(p.kills) DESC,%@",group,[HCAggregates stringByReplacingOccurrencesOfString:@"COALESCE(SUM(p.entered),0)" withString:@"COUNT(DISTINCT printf('%u:%u:%u',m.seed,m.game,m.crc))"],season?@" AND p.season=?":@"",group,group];
    sqlite3_stmt *s=[self prepare:sql.UTF8String error:error];if(!s)return nil;HCBindText(s,1,profile);if(season)HCBindText(s,2,season);NSMutableArray *rows=[NSMutableArray array];int rc;
    while((rc=sqlite3_step(s))==SQLITE_ROW){NSMutableDictionary *v=HCCounts(s,1);v[[column isEqualToString:@"season"]?@"season_id":@"name"]=[NSString stringWithUTF8String:(const char *)sqlite3_column_text(s,0)];[rows addObject:v];}
    sqlite3_finalize(s);if(rc!=SQLITE_DONE){HCSetError(error,HCError(rc,@"Unable to read career breakdown"));return nil;}return rows;
}
- (NSArray *)weaponsForProfile:(NSString *)profile season:(NSString *)season totals:(NSDictionary *)totals error:(NSError **)error {
    NSString *sql=[NSString stringWithFormat:@"SELECT weapon,COALESCE(SUM(kind=2),0),COALESCE(SUM(kind=3),0),COALESCE(SUM(kind=4),0),0,0,0,0,0,0,0 FROM career_events WHERE profile=? AND kind IN (2,3,4)%@ GROUP BY weapon ORDER BY SUM(kind=2) DESC,weapon",season?@" AND season=?":@""];
    sqlite3_stmt *s=[self prepare:sql.UTF8String error:error];if(!s)return nil;HCBindText(s,1,profile);if(season)HCBindText(s,2,season);NSMutableArray *rows=[NSMutableArray array];int rc;int64_t detailed[3]={0};NSMutableDictionary *unknown=nil;
    while((rc=sqlite3_step(s))==SQLITE_ROW){NSMutableDictionary *v=HCCounts(s,1);v[@"name"]=[NSString stringWithUTF8String:(const char *)sqlite3_column_text(s,0)];for(int i=0;i<3;i++)detailed[i]+=sqlite3_column_int64(s,i+1);if([v[@"name"]isEqualToString:@"unknown"])unknown=v;[rows addObject:v];}
    sqlite3_finalize(s);if(rc!=SQLITE_DONE){HCSetError(error,HCError(rc,@"Unable to read weapon breakdown"));return nil;}
    NSArray *keys=@[@"kills",@"deaths",@"assists"];
    /* Authoritative totals may later be corrected downward. Those corrections
     * cannot identify which earlier damage-source event was revoked. Preserve
     * the original ledger but withhold ambiguous attribution rather than show a
     * breakdown larger than the corrected aggregate or guess a weapon. */
    for(int i=0;i<3;i++)if(detailed[i]>[totals[keys[i]]longLongValue]){
        NSMutableDictionary *corrected=[@{@"name":@"unknown",@"kills":totals[@"kills"],@"deaths":totals[@"deaths"],@"assists":totals[@"assists"],
            @"attribution_note":@"Damage-source attribution is unavailable after a combat-total correction. Corrected aggregate totals are preserved."} mutableCopy];
        double deaths=[corrected[@"deaths"]doubleValue];corrected[@"kd"]=@(deaths>0?[corrected[@"kills"]doubleValue]/deaths:0);corrected[@"kd_defined"]=@(deaths>0);
        return @[[corrected copy]];
    }
    BOOL hasUnknown=NO;int64_t missing[3];for(int i=0;i<3;i++){missing[i]=MAX(0,[totals[keys[i]]longLongValue]-detailed[i]);hasUnknown|=missing[i]>0;}
    if(hasUnknown){if(!unknown){unknown=[@{@"name":@"unknown",@"kills":@0,@"deaths":@0,@"assists":@0,@"best_streak":@0,@"matches_played":@0,@"wins":@0,@"losses":@0,@"draws":@0,@"unknown_results":@0,@"completed_matches":@0}mutableCopy];[rows addObject:unknown];}for(int i=0;i<3;i++)unknown[keys[i]]=@([unknown[keys[i]]longLongValue]+missing[i]);double d=[unknown[@"deaths"]doubleValue];unknown[@"kd"]=@(d>0?[unknown[@"kills"]doubleValue]/d:0);unknown[@"kd_defined"]=@(d>0);}
    return rows;
}
static NSMutableDictionary *HCEmptyMedals(void) {
    NSMutableDictionary *v=[NSMutableDictionary dictionaryWithCapacity:15];for(unsigned int i=1;i<=15;i++)v[[NSString stringWithFormat:@"%u",i]]=@0;return v;
}
- (NSDictionary *)latestMatchMedalsForProfile:(NSString *)profile trackingStarted:(double)trackingStarted error:(NSError **)error {
    sqlite3_stmt *s=[self prepare:"SELECT seed,game,crc,occurred,map,mode,result FROM career_matches WHERE profile=? ORDER BY occurred DESC,game DESC,seed DESC,crc DESC LIMIT 1" error:error];if(!s)return nil;
    HCBindText(s,1,profile);int rc=sqlite3_step(s);
    if(rc==SQLITE_DONE){sqlite3_finalize(s);return @{@"available":@NO,@"tracked":@NO,@"medals":HCEmptyMedals(),@"total":@0,@"map":@"",@"mode":@"",@"result":@(-1),@"completed":@NO,@"started_at":NSNull.null};}
    if(rc!=SQLITE_ROW){sqlite3_finalize(s);HCSetError(error,HCError(rc,@"Unable to read latest match"));return nil;}
    int64_t seed=sqlite3_column_int64(s,0),game=sqlite3_column_int64(s,1),crc=sqlite3_column_int64(s,2),result=sqlite3_column_int64(s,6);double occurred=sqlite3_column_double(s,3);
    NSString *map=[NSString stringWithUTF8String:(const char *)sqlite3_column_text(s,4)],*mode=[NSString stringWithUTF8String:(const char *)sqlite3_column_text(s,5)];sqlite3_finalize(s);
    s=[self prepare:"SELECT medal_id,COUNT(*) FROM career_medals WHERE profile=? AND seed=? AND game=? AND crc=? GROUP BY medal_id" error:error];if(!s)return nil;
    HCBindText(s,1,profile);sqlite3_bind_int64(s,2,seed);sqlite3_bind_int64(s,3,game);sqlite3_bind_int64(s,4,crc);NSMutableDictionary *counts=HCEmptyMedals();long long total=0;
    while((rc=sqlite3_step(s))==SQLITE_ROW){NSString *medal=[NSString stringWithFormat:@"%d",sqlite3_column_int(s,0)];long long count=sqlite3_column_int64(s,1);
        if(!counts[medal]||count<0){sqlite3_finalize(s);HCSetError(error,HCError(10,@"Inconsistent latest match medals"));return nil;}counts[medal]=@(count);total+=count;}
    sqlite3_finalize(s);if(rc!=SQLITE_DONE){HCSetError(error,HCError(rc,@"Unable to read latest match medals"));return nil;}
    return @{@"available":@YES,@"tracked":@(total>0||(isfinite(trackingStarted)&&occurred>=trackingStarted)),@"medals":counts,@"total":@(total),@"map":map,@"mode":mode,@"result":@(result),@"completed":@(result>=0),@"started_at":HCISODate(occurred)};
}
- (NSDictionary *)medalSnapshotForProfile:(NSString *)profile season:(NSString *)seasonID error:(NSError **)error {
    id started=NSNull.null;NSString *trackingSeason=nil;double trackingStarted=NAN;
    sqlite3_stmt *s=[self prepare:"SELECT started FROM career_medal_tracking WHERE profile=?" error:error];if(!s)return nil;
    HCBindText(s,1,profile);int rc=sqlite3_step(s);
    if(rc==SQLITE_ROW){double seconds=sqlite3_column_double(s,0);trackingStarted=seconds;started=HCISODate(seconds);trackingSeason=HCSeason(_calendar,[NSDate dateWithTimeIntervalSince1970:seconds]);}
    sqlite3_finalize(s);if(rc!=SQLITE_ROW&&rc!=SQLITE_DONE){HCSetError(error,HCError(rc,@"Unable to read medal tracking start"));return nil;}
    /* Include seasons with ordinary career activity but no medals. Their tracked
     * flag distinguishes a measured zero from a quarter predating this update. */
    s=[self prepare:"SELECT season FROM career_periods WHERE profile=? UNION SELECT season FROM career_medals WHERE profile=? UNION SELECT ? ORDER BY season DESC" error:error];if(!s)return nil;
    HCBindText(s,1,profile);HCBindText(s,2,profile);HCBindText(s,3,seasonID);
    NSMutableArray *rows=[NSMutableArray array];NSMutableDictionary *bySeason=[NSMutableDictionary dictionary];
    while((rc=sqlite3_step(s))==SQLITE_ROW){NSString *season=[NSString stringWithUTF8String:(const char *)sqlite3_column_text(s,0)];
        NSMutableDictionary *row=[@{@"season":season,@"medals":HCEmptyMedals(),@"total":@0,@"tracked":@(trackingSeason&&[season compare:trackingSeason]!=NSOrderedAscending)}mutableCopy];[rows addObject:row];bySeason[season]=row;}
    sqlite3_finalize(s);if(rc!=SQLITE_DONE){HCSetError(error,HCError(rc,@"Unable to read medal seasons"));return nil;}
    s=[self prepare:"SELECT season,medal_id,COUNT(*) FROM career_medals WHERE profile=? GROUP BY season,medal_id" error:error];if(!s)return nil;HCBindText(s,1,profile);
    NSMutableDictionary *lifetime=HCEmptyMedals();
    while((rc=sqlite3_step(s))==SQLITE_ROW){NSString *season=[NSString stringWithUTF8String:(const char *)sqlite3_column_text(s,0)],*medal=[NSString stringWithFormat:@"%d",sqlite3_column_int(s,1)];long long count=sqlite3_column_int64(s,2);
        NSMutableDictionary *row=bySeason[season];if(!row||!lifetime[medal]||count<0){sqlite3_finalize(s);HCSetError(error,HCError(10,@"Inconsistent medal totals"));return nil;}
        row[@"medals"][medal]=@(count);row[@"total"]=@([row[@"total"]longLongValue]+count);lifetime[medal]=@([lifetime[medal]longLongValue]+count);}
    sqlite3_finalize(s);if(rc!=SQLITE_DONE){HCSetError(error,HCError(rc,@"Unable to read medal totals"));return nil;}
    NSDictionary *latest=[self latestMatchMedalsForProfile:profile trackingStarted:trackingStarted error:error];if(!latest)return nil;
    return @{@"medals":lifetime,@"season_medals":bySeason[seasonID][@"medals"]?:HCEmptyMedals(),@"medal_seasons":rows,@"medals_tracking_started":started,@"medals_tracking_active":@(![started isEqual:NSNull.null]),@"latest_match_medals":latest};
}
- (NSDictionary *)snapshotForProfileID:(NSString *)profileID date:(NSDate *)date error:(NSError **)error {
    NSString *profile=HCProfile(profileID);if(!profile||!date||!isfinite(date.timeIntervalSince1970)){HCSetError(error,HCError(8,@"A valid profile is required"));return nil;}
    [_lock lock];if(!_db){HCSetError(error,HCError(7,@"Career database is closed"));[_lock unlock];return nil;}if(![self exec:"BEGIN" error:error]){[_lock unlock];return nil;}
    NSString *seasonID=HCSeason(_calendar,date);NSDictionary *lifetime=[self countsForProfile:profile season:nil error:error],*season=lifetime?[self countsForProfile:profile season:seasonID error:error]:nil;
    NSArray *seasons=season?[self groupsForProfile:profile column:@"season" season:nil error:error]:nil,*maps=nil,*modes=nil,*weapons=nil,*seasonMaps=nil,*seasonModes=nil,*seasonWeapons=nil;
    BOOL ok=seasons!=nil;
    if(ok)ok=(maps=[self groupsForProfile:profile column:@"map" season:nil error:error])!=nil;
    if(ok)ok=(modes=[self groupsForProfile:profile column:@"mode" season:nil error:error])!=nil;
    if(ok)ok=(weapons=[self weaponsForProfile:profile season:nil totals:lifetime error:error])!=nil;
    if(ok)ok=(seasonMaps=[self groupsForProfile:profile column:@"map" season:seasonID error:error])!=nil;
    if(ok)ok=(seasonModes=[self groupsForProfile:profile column:@"mode" season:seasonID error:error])!=nil;
    if(ok)ok=(seasonWeapons=[self weaponsForProfile:profile season:seasonID totals:season error:error])!=nil;
    NSDictionary *medals=ok?[self medalSnapshotForProfile:profile season:seasonID error:error]:nil;if(ok)ok=medals!=nil;
    id started=NSNull.null;
    if(ok){sqlite3_stmt *s=[self prepare:"SELECT started FROM career_tracking WHERE profile=?" error:error];ok=s!=NULL;if(s){HCBindText(s,1,profile);int rc=sqlite3_step(s);if(rc==SQLITE_ROW)started=HCISODate(sqlite3_column_double(s,0));else if(rc!=SQLITE_DONE){ok=NO;HCSetError(error,HCError(rc,@"Unable to read tracking start"));}sqlite3_finalize(s);}}
    if(ok)ok=[self exec:"COMMIT" error:error];if(!ok)sqlite3_exec(_db,"ROLLBACK",NULL,NULL,NULL);
    NSMutableDictionary *v=ok?[@{@"profile_id":profile,@"tracking_started":started,@"tracking_active":@(![started isEqual:NSNull.null]),@"storage_error":@NO,@"season_id":seasonID,@"lifetime":lifetime,@"season":season,@"seasons":seasons,@"maps":maps,@"modes":modes,@"weapons":weapons,@"season_maps":seasonMaps,@"season_modes":seasonModes,@"season_weapons":seasonWeapons}mutableCopy]:nil;
    if(v)[v addEntriesFromDictionary:medals];[_lock unlock];return v;
}

- (NSDictionary *)matchHistoryForProfileID:(NSString *)profileID date:(NSDate *)date
                                 lifetime:(BOOL)lifetime limit:(NSUInteger)requestedLimit error:(NSError **)error {
    NSString *profile=HCProfile(profileID);
    if(!profile||!date||!isfinite(date.timeIntervalSince1970)) {
        HCSetError(error,HCError(8,@"A valid profile and date are required"));return nil;
    }
    NSUInteger limit=requestedLimit?MIN(requestedLimit,(NSUInteger)100):50;
    NSString *season=HCSeason(_calendar,date);
    [_lock lock];
    if(!_db){HCSetError(error,HCError(7,@"Career database is closed"));[_lock unlock];return nil;}
    if(![self exec:"BEGIN" error:error]){[_lock unlock];return nil;}
    BOOL ok=YES,hasMore=NO;
    id trackingStarted=NSNull.null;
    double medalTrackingStarted=NAN;
    sqlite3_stmt *s=[self prepare:"SELECT (SELECT started FROM career_tracking WHERE profile=?), (SELECT started FROM career_medal_tracking WHERE profile=?)" error:error];
    if(!s)ok=NO;
    if(s) {
        HCBindText(s,1,profile);HCBindText(s,2,profile);
        int rc=sqlite3_step(s);
        if(rc!=SQLITE_ROW){ok=NO;HCSetError(error,HCError(rc,@"Unable to read match tracking"));}
        else {
            if(sqlite3_column_type(s,0)!=SQLITE_NULL) {
                double started=sqlite3_column_double(s,0);
                NSString *stamp=isfinite(started)?HCISODate(started):nil;
                if(stamp)trackingStarted=stamp;
                else {ok=NO;HCSetError(error,HCError(10,@"Invalid match tracking date"));}
            }
            if(sqlite3_column_type(s,1)!=SQLITE_NULL)medalTrackingStarted=sqlite3_column_double(s,1);
        }
        sqlite3_finalize(s);
    }
    /* The primary match identity stays intact across a quarter boundary. A
     * medal may retain an earlier award date while its storage retry commits
     * later, so include either period or medal activity without duplicating it. */
    NSString *sql=[NSString stringWithFormat:
        @"SELECT m.seed,m.game,m.crc,m.occurred,m.season,m.map,m.mode,"
         "m.baseline_k,m.baseline_d,m.baseline_a,m.total_k,m.total_d,m.total_a,"
         "m.best_streak,m.result,m.replicated,COALESCE(p.kills,0),COALESCE(p.deaths,0),"
         "COALESCE(p.assists,0),COALESCE(p.best_streak,0) "
         "FROM career_matches m LEFT JOIN career_periods p ON p.profile=m.profile "
         "AND p.seed=m.seed AND p.game=m.game AND p.crc=m.crc AND p.season=? "
         "WHERE m.profile=?%@ ORDER BY m.occurred DESC,m.game DESC,m.seed DESC,m.crc DESC LIMIT ?",
         lifetime?@"":@" AND (p.profile IS NOT NULL OR EXISTS (SELECT 1 FROM career_medals d WHERE d.profile=m.profile AND d.seed=m.seed AND d.game=m.game AND d.crc=m.crc AND d.season=?))"];
    s=ok?[self prepare:sql.UTF8String error:error]:NULL;
    if(ok&&!s)ok=NO;
    NSMutableArray *matches=[NSMutableArray arrayWithCapacity:limit];
    if(s) {
        HCBindText(s,1,season);HCBindText(s,2,profile);
        int limitIndex=3;if(!lifetime){HCBindText(s,3,season);limitIndex=4;}
        sqlite3_bind_int64(s,limitIndex,(sqlite3_int64)limit+1);
        int rc=SQLITE_DONE;
        while((rc=sqlite3_step(s))==SQLITE_ROW) {
            if(matches.count==limit){hasMore=YES;break;}
            int64_t seed=sqlite3_column_int64(s,0),game=sqlite3_column_int64(s,1),crc=sqlite3_column_int64(s,2);
            double occurred=sqlite3_column_double(s,3);
            const char *seasonBytes=(const char *)sqlite3_column_text(s,4);
            const char *mapBytes=(const char *)sqlite3_column_text(s,5);
            const char *modeBytes=(const char *)sqlite3_column_text(s,6);
            NSString *matchSeason=seasonBytes?[NSString stringWithUTF8String:seasonBytes]:nil;
            NSString *map=mapBytes?[NSString stringWithUTF8String:mapBytes]:nil;
            NSString *mode=modeBytes?[NSString stringWithUTF8String:modeBytes]:nil;
            int64_t values[13];for(int i=0;i<13;i++)values[i]=sqlite3_column_int64(s,i+7);
            NSString *recordedAt=isfinite(occurred)?HCISODate(occurred):nil;
            BOOL valid=recordedAt&&seed>=0&&seed<=UINT32_MAX&&game>=0&&game<=UINT32_MAX&&crc>=0&&crc<=UINT32_MAX&&matchSeason&&map&&mode;
            for(int i=0;i<13;i++) {
                if(i==7)valid&=values[i]>=-1&&values[i]<=3;
                else if(i==8)valid&=values[i]==0||values[i]==1;
                else valid&=values[i]>=0&&values[i]<=INT32_MAX;
            }
            if(!valid){ok=NO;HCSetError(error,HCError(10,@"Inconsistent saved match"));break;}
            NSMutableDictionary *row=[@{
                @"match_id":[NSString stringWithFormat:@"%lld:%lld:%lld",(long long)seed,(long long)game,(long long)crc],
                @"seed":@(seed),@"game":@(game),@"crc":@(crc),@"map":map,@"mode":mode,
                @"started_at":recordedAt,@"season_id":matchSeason,
                @"kills":@(MAX(0,values[3]-values[0])),@"deaths":@(MAX(0,values[4]-values[1])),
                @"assists":@(MAX(0,values[5]-values[2])),@"best_streak":@(values[6]),
                @"result":@(values[7]),@"completed":@(values[7]>=0),@"replicated":@(values[8]!=0),
                @"partial":@(values[0]>0||values[1]>0||values[2]>0),
                @"season_kills":@(values[9]),@"season_deaths":@(values[10]),
                @"season_assists":@(values[11]),@"season_best_streak":@(values[12])
            } mutableCopy];
            sqlite3_stmt *medals=[self prepare:"SELECT medal_id,COUNT(*),SUM(season=?) FROM career_medals WHERE profile=? AND seed=? AND game=? AND crc=? GROUP BY medal_id" error:error];
            if(!medals){ok=NO;break;}
            HCBindText(medals,1,season);HCBindText(medals,2,profile);
            sqlite3_bind_int64(medals,3,seed);sqlite3_bind_int64(medals,4,game);sqlite3_bind_int64(medals,5,crc);
            NSMutableDictionary *all=HCEmptyMedals(),*inSeason=HCEmptyMedals();
            int medalRC;int64_t total=0,seasonTotal=0;
            while((medalRC=sqlite3_step(medals))==SQLITE_ROW) {
                NSString *medal=[NSString stringWithFormat:@"%d",sqlite3_column_int(medals,0)];
                int64_t count=sqlite3_column_int64(medals,1),periodCount=sqlite3_column_int64(medals,2);
                if(!all[medal]||count<0||periodCount<0||periodCount>count||count>INT64_MAX-total||periodCount>INT64_MAX-seasonTotal){ok=NO;break;}
                all[medal]=@(count);inSeason[medal]=@(periodCount);total+=count;seasonTotal+=periodCount;
            }
            sqlite3_finalize(medals);
            if(!ok||medalRC!=SQLITE_DONE){ok=NO;HCSetError(error,HCError(10,@"Unable to read saved match medals"));break;}
            row[@"medals"]=[all copy];row[@"season_medals"]=[inSeason copy];
            row[@"medal_total"]=@(total);row[@"season_medal_total"]=@(seasonTotal);
            row[@"medals_tracked"]=@(total>0||(isfinite(medalTrackingStarted)&&occurred>=medalTrackingStarted));
            [matches addObject:[row copy]];
        }
        if(ok&&rc!=SQLITE_DONE&&!hasMore){ok=NO;HCSetError(error,HCError(rc,@"Unable to read match history"));}
        sqlite3_finalize(s);
    }
    if(ok)ok=[self exec:"COMMIT" error:error];
    if(!ok)sqlite3_exec(_db,"ROLLBACK",NULL,NULL,NULL);
    NSDictionary *result=ok?@{@"profile_id":profile,@"season_id":season,@"lifetime":@(lifetime),
        @"matches":[matches copy],@"limit":@(limit),@"has_more":@(hasMore),
        @"tracking_started":trackingStarted,@"storage_error":@NO}:nil;
    [_lock unlock];return result;
}
@end

/* The native bridge never dereferences an unchecked guest pointer. */
extern uintptr_t xg_base;
static BOOL HCCopyGuest(uint32_t address,uint32_t length,void *dest) {
    _Static_assert(sizeof(vm_address_t)==sizeof(uintptr_t), "Guest copying requires native-width VM addresses");
    if(!xg_base||!address||!length||!dest||(uint64_t)address+length>UINT32_MAX+1ULL)return NO;
    uintptr_t base=xg_base;
    if(base>UINTPTR_MAX-address)return NO;
    uintptr_t source=base+address;
    if(source>UINTPTR_MAX-length)return NO;
    vm_size_t copied=0;
    return vm_read_overwrite(mach_task_self(),(vm_address_t)source,(vm_size_t)length,
                             (vm_address_t)dest,&copied)==KERN_SUCCESS && copied==length;
}
static HPCareerStatsStore *HCGlobalStore;static NSURL *HCGlobalRoot;
static NSString *(^HCResolver)(NSString *);static NSObject *HCGlobalLock;
static NSObject *HCGlobalMutex(void){static dispatch_once_t once;dispatch_once(&once,^{HCGlobalLock=[NSObject new];});return HCGlobalLock;}
void HPCareerStatsConfigure(NSURL *root) {
    @synchronized(HCGlobalMutex()) { if([HCGlobalRoot isEqual:root]&&HCGlobalStore)return;HCGlobalRoot=[root copy];HCGlobalStore=[[HPCareerStatsStore alloc]initWithSaveRootURL:root calendar:nil error:NULL]; }
}
void HPCareerStatsSetProfileResolver(NSString *(^resolver)(NSString *)) {@synchronized(HCGlobalMutex()){HCResolver=[resolver copy];}}
static BOOL HCPathValid(NSString *path) {
    if(![path isKindOfClass:NSString.class]||!path.length||path.length>260)return NO;
    NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:@"^[uU]:[\\\\/][uU][dD][aA][tT][aA][\\\\/][0-9a-fA-F]{12}[\\\\/]?$" options:0 error:NULL];
    NSTextCheckingResult *r=[regex firstMatchInString:path options:0 range:NSMakeRange(0,path.length)];return r && NSEqualRanges(r.range,NSMakeRange(0,path.length));
}
static NSString *HCResolve(NSString *path) {
    if(!HCPathValid(path))return nil;
    NSString *(^resolver)(NSString *);@synchronized(HCGlobalMutex()){resolver=HCResolver;}
    return resolver?HCProfile(resolver(path)):nil;
}
static HPCareerStatsStore *HCStore(void) {
    @synchronized(HCGlobalMutex()) { if(!HCGlobalStore&&HCGlobalRoot)HCGlobalStore=[[HPCareerStatsStore alloc]initWithSaveRootURL:HCGlobalRoot calendar:nil error:NULL];return HCGlobalStore; }
}
extern void HPHaloMedalOverlayObserve(NSString *guestPath,const HPCareerStatsEventV1 *event) __attribute__((weak_import));
NSDictionary *HPCareerStatsSnapshot(NSString *path) {
    NSString *profile=HCResolve(path);HPCareerStatsStore *store=profile?HCStore():nil;
    NSDictionary *v=store?[store snapshotForProfileID:profile date:NSDate.date error:NULL]:nil;
    return v?:@{@"storage_error":@YES,@"tracking_active":@NO,@"tracking_started":NSNull.null};
}
NSDictionary *HPCareerStatsMatchHistory(NSString *path,BOOL lifetime,NSUInteger limit) {
    /* Resolve the validated save-profile UUID before taking a career-store lock. */
    NSString *profile=HCResolve(path);HPCareerStatsStore *store=profile?HCStore():nil;
    NSDictionary *v=store?[store matchHistoryForProfileID:profile date:NSDate.date lifetime:lifetime limit:limit error:NULL]:nil;
    return v?:@{@"storage_error":@YES,@"matches":@[],@"has_more":@NO,@"tracking_started":NSNull.null};
}
uint32_t xh_host_halopad_career_event_v1(uint32_t path,uint32_t pathLength,uint32_t event,uint32_t eventLength) {
    @autoreleasepool {
        if(!pathLength||pathLength>260||eventLength!=sizeof(HPCareerStatsEventV1))return 2;
        char text[261];HPCareerStatsEventV1 value;
        if(!HCCopyGuest(path,pathLength,text)||!HCCopyGuest(event,eventLength,&value)||memchr(text,0,pathLength))return 2;
        text[pathLength]=0;NSString *guestPath=[[NSString alloc]initWithBytes:text length:pathLength encoding:NSUTF8StringEncoding];
        if(!HCPathValid(guestPath))return 2;
        BOOL preview=(value.flags&HPCareerMedalPreviewOnly)!=0;
        if(preview){if(value.kind!=HPCareerMedal)return 2;value.flags&=~HPCareerMedalPreviewOnly;}
        /* Visual awards also work for transient profiles and while storage is
         * retrying. Their overlay deduplicates retries separately from SQLite. */
        NSDate *date=NSDate.date;
        if(value.kind==HPCareerMedal){
            if(!HCMedalPayloadValid(&value)||!value.mode_id||(NSTimeInterval)value.mode_id>date.timeIntervalSince1970+5.0)return 2;
            date=[NSDate dateWithTimeIntervalSince1970:value.mode_id];
            if(HPHaloMedalOverlayObserve)HPHaloMedalOverlayObserve(guestPath,&value);
        }
        if(preview||(value.flags&HPCareerTransientProfile))return 2;
        NSString *profile=HCResolve(guestPath);HPCareerStatsStore *store=profile?HCStore():nil;
        return store?[store recordEvent:&value profileID:profile date:date error:NULL]:0;
    }
}
