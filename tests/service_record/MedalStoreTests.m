/* Synthetic fixtures only; no installed profiles or engine execution. */
#import "HPCareerStatsStore.h"
#import <sqlite3.h>
#include <math.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;
uintptr_t xg_base=0;
static int checks=0, observed=0, resolved=0;
static unsigned observedFlags=0;
static NSMutableArray *notifications;
static NSString *const P=@"12345678-1234-1234-1234-123456789ABC";
static NSString *const Q=@"ABCD1234-1234-1234-1234-123456789ABC";
#define CHECK(c) do { checks++;if(!(c)){fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#c);exit(1);} }while(0)
void HPHaloMedalOverlayObserve(NSString *path,const HPCareerStatsEventV1 *event) {
    CHECK([path isEqual:@"u:\\udata\\000000000000"]);CHECK(event->kind==HPCareerMedal);CHECK((event->flags&~(HPCareerReplicatedClient|HPCareerTransientProfile))==0);observedFlags=event->flags;observed++;
}
static NSCalendar *Calendar(void) { NSCalendar *c=[[NSCalendar alloc]initWithCalendarIdentifier:NSCalendarIdentifierGregorian];c.timeZone=[NSTimeZone timeZoneWithName:@"America/Chicago"];return c; }
static NSDate *Date(NSString *v) {return [[NSISO8601DateFormatter new]dateFromString:v];}
static NSURL *Root(NSString *name) {NSURL *r=[NSURL fileURLWithPath:[@(getenv("HALOPAD_TEST_RESULTS"))stringByAppendingPathComponent:[NSString stringWithFormat:@"HaloMedalFixtures-%@-%@",NSUUID.UUID.UUIDString,name]] isDirectory:YES];CHECK([NSFileManager.defaultManager createDirectoryAtURL:r withIntermediateDirectories:YES attributes:nil error:NULL]);return r;}
static HPCareerStatsStore *Store(NSURL *root) {NSError *error=nil;HPCareerStatsStore *s=[[HPCareerStatsStore alloc]initWithSaveRootURL:root calendar:Calendar() error:&error];if(!s)fprintf(stderr,"store: %s\n",error.description.UTF8String);CHECK(s!=nil);return s;}
static NSDictionary *Snap(HPCareerStatsStore *s,NSString *p,NSDate *date) {NSError *error=nil;NSDictionary *v=[s snapshotForProfileID:p date:date error:&error];if(!v)fprintf(stderr,"snapshot: %s\n",error.description.UTF8String);CHECK(v!=nil);CHECK([NSJSONSerialization dataWithJSONObject:v options:0 error:NULL]!=nil);return v;}
static HPCareerStatsEventV1 Event(unsigned kind,unsigned kill,unsigned medal) {HPCareerStatsEventV1 e={0};e.version=1;e.size=sizeof e;e.kind=kind;e.session_seed=100;e.game_number=7;e.map_crc=123;e.event_id=kind==HPCareerMatchEnter?0:kill;e.kills=kill;e.streak=kill;e.mode_id=2;e.reserved=medal;strcpy(e.map,"bloodgulch");strcpy(e.mode,"Slayer");strcpy(e.weapon,"pistol");return e;}
static void Record(HPCareerStatsStore *s,HPCareerStatsEventV1 e,NSString *p,NSDate *date) {NSError *error=nil;uint32_t code=[s recordEvent:&e profileID:p date:date error:&error];if(code!=1)fprintf(stderr,"record: %s\n",error.description.UTF8String);CHECK(code==1);}
static long long Count(NSDictionary *v,NSString *key,unsigned medal) {return[v[key][[NSString stringWithFormat:@"%u",medal]]longLongValue];}
static NSDictionary *Season(NSDictionary *v,NSString *season) {for(NSDictionary *row in v[@"medal_seasons"])if([row[@"season"]isEqual:season])return row;return nil;}
static long long Total(NSDictionary *counts) {long long n=0;CHECK(counts.count==15);for(unsigned i=1;i<=15;i++){NSNumber *v=counts[[NSString stringWithFormat:@"%u",i]];CHECK([v isKindOfClass:NSNumber.class]&&v.longLongValue>=0);n+=v.longLongValue;}return n;}
static void Flush(void) {[[NSRunLoop mainRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.025]];}
static sqlite3 *DB(NSURL *root) {sqlite3 *db=NULL;CHECK(sqlite3_open([root URLByAppendingPathComponent:@".halopad-career.sqlite3"].fileSystemRepresentation,&db)==SQLITE_OK);return db;}
static void SQL(sqlite3 *db,const char *sql) {char *error=NULL;int rc=sqlite3_exec(db,sql,NULL,NULL,&error);if(rc!=SQLITE_OK)fprintf(stderr,"SQL: %s\n",error);CHECK(rc==SQLITE_OK);sqlite3_free(error);}
static long long Scalar(sqlite3 *db,const char *sql) {sqlite3_stmt *s=NULL;CHECK(sqlite3_prepare_v2(db,sql,-1,&s,NULL)==SQLITE_OK);CHECK(sqlite3_step(s)==SQLITE_ROW);long long n=sqlite3_column_int64(s,0);sqlite3_finalize(s);return n;}
int main(int argc,char **argv) {
    if(argc==3&&!strcmp(argv[1],"--uncommitted-medal")){sqlite3 *db=NULL;if(sqlite3_open(argv[2],&db)!=SQLITE_OK)return 91;if(sqlite3_exec(db,"BEGIN IMMEDIATE; INSERT INTO career_medals VALUES('12345678-1234-1234-1234-123456789ABC',999,999,999,2,1,0,0,1800000000,'2027-Q1');",NULL,NULL,NULL)!=SQLITE_OK)return 92;raise(SIGKILL);return 93;}
    @autoreleasepool {
        notifications=[NSMutableArray array];
        id observer=[NSNotificationCenter.defaultCenter addObserverForName:HPCareerMedalEarnedNotification object:nil queue:nil usingBlock:^(NSNotification *n){CHECK(NSThread.isMainThread);[notifications addObject:n.userInfo];}];
        NSDate *t=Date(@"2026-11-03T18:00:00Z"),*before=Date(@"2027-01-01T05:59:59Z"),*after=Date(@"2027-01-01T06:00:01Z");
        NSURL *r=Root(@"basic");HPCareerStatsStore *s=Store(r);NSDictionary *v=Snap(s,P,t);
        CHECK(Total(v[@"medals"])==0&&Total(v[@"season_medals"])==0);CHECK([v[@"medals_tracking_started"]isEqual:NSNull.null]);CHECK(![v[@"medals_tracking_active"]boolValue]);CHECK([v[@"medal_seasons"]count]==1);CHECK(![Season(v,@"2026-Q4")[@"tracked"]boolValue]);
        CHECK(![v[@"latest_match_medals"][@"available"]boolValue]);CHECK(![v[@"latest_match_medals"][@"tracked"]boolValue]);CHECK(Total(v[@"latest_match_medals"][@"medals"])==0);CHECK([v[@"latest_match_medals"][@"started_at"]isEqual:NSNull.null]);
        HPCareerStatsEventV1 e=Event(HPCareerMedal,2,HPCareerDoubleKill);CHECK([s recordEvent:&e profileID:P date:t error:NULL]==0);Flush();CHECK(notifications.count==0);
        Record(s,Event(HPCareerMatchEnter,0,0),P,t);v=Snap(s,P,t);CHECK([v[@"medals_tracking_active"]boolValue]);CHECK([v[@"medals_tracking_started"]isEqual:@"2026-11-03T18:00:00Z"]);CHECK([Season(v,@"2026-Q4")[@"tracked"]boolValue]);
        CHECK([v[@"latest_match_medals"][@"available"]boolValue]);CHECK([v[@"latest_match_medals"][@"tracked"]boolValue]);CHECK(![v[@"latest_match_medals"][@"completed"]boolValue]);CHECK([v[@"latest_match_medals"][@"result"]intValue]==-1);CHECK([v[@"latest_match_medals"][@"total"]longLongValue]==0);CHECK([v[@"latest_match_medals"][@"started_at"]isEqual:@"2026-11-03T18:00:00Z"]);
        // Genuine combat records do not invent any medal from their totals.
        Record(s,Event(HPCareerKill,1,0),P,t);Record(s,Event(HPCareerKill,2,0),P,t);v=Snap(s,P,t);CHECK(Total(v[@"medals"])==0);
        // All nine multikill tiers and six spree tiers are independent awards.
        for(unsigned kill=2;kill<=30;kill++) {
            if(kill>2)Record(s,Event(HPCareerKill,kill,0),P,t);
            if(kill<=10){e=Event(HPCareerMedal,kill,kill-1);Record(s,e,P,t);Record(s,e,P,t);}
            if(kill%5==0){e=Event(HPCareerMedal,kill,kill/5+9);Record(s,e,P,t);Record(s,e,P,t);}
        }
        Flush();v=Snap(s,P,t);CHECK(Total(v[@"medals"])==15);CHECK(Total(v[@"season_medals"])==15);CHECK([v[@"lifetime"][@"kills"]longLongValue]==30);CHECK(notifications.count==15);
        for(unsigned i=1;i<=15;i++){CHECK(Count(v,@"medals",i)==1);CHECK(Count(v,@"season_medals",i)==1);}
        CHECK([notifications[0][@"profile_id"]isEqual:P]);CHECK([notifications[0][@"medal_id"]unsignedIntValue]==1);CHECK([notifications[0][@"event_id"]unsignedIntValue]==2);CHECK([notifications[0][@"season"]isEqual:@"2026-Q4"]);CHECK([notifications[0][@"awarded_at"]isEqual:@"2026-11-03T18:00:00Z"]);
        CHECK([Season(v,@"2026-Q4")[@"total"]longLongValue]==15);
        CHECK(Total(v[@"latest_match_medals"][@"medals"])==15);CHECK([v[@"latest_match_medals"][@"total"]longLongValue]==15);CHECK([v[@"latest_match_medals"][@"map"]isEqual:@"bloodgulch"]);CHECK([v[@"latest_match_medals"][@"mode"]isEqual:@"Slayer"]);
        // A new chain earns another double; duplicates keep their first season.
        e=Event(HPCareerDeath,30,0);e.event_id=1;e.deaths=1;e.streak=0;Record(s,e,P,before);
        e=Event(HPCareerKill,31,0);e.deaths=1;e.streak=1;Record(s,e,P,before);
        e=Event(HPCareerKill,32,0);e.deaths=1;e.streak=2;Record(s,e,P,before);e.kind=HPCareerMedal;e.reserved=HPCareerDoubleKill;Record(s,e,P,before);Record(s,e,P,after);
        e=Event(HPCareerKill,33,0);e.deaths=1;e.streak=3;Record(s,e,P,after);e.kind=HPCareerMedal;e.reserved=HPCareerTripleKill;Record(s,e,P,after);Flush();
        v=Snap(s,P,after);CHECK([v[@"season_id"]isEqual:@"2027-Q1"]);CHECK(Count(v,@"medals",1)==2&&Count(v,@"medals",2)==2);CHECK(Count(v,@"season_medals",1)==0&&Count(v,@"season_medals",2)==1);CHECK([Season(v,@"2026-Q4")[@"total"]longLongValue]==16);CHECK([Season(v,@"2027-Q1")[@"total"]longLongValue]==1);CHECK(notifications.count==17);
        CHECK([v[@"latest_match_medals"][@"total"]longLongValue]==17);CHECK(Total(v[@"latest_match_medals"][@"medals"])==17);CHECK([v[@"latest_match_medals"][@"medals"][@"1"]longLongValue]==2);CHECK([v[@"latest_match_medals"][@"medals"][@"2"]longLongValue]==2);
        // State survives close/reopen, and another profile has no inherited awards.
        [s close];s=Store(r);Record(s,e,P,after);Flush();CHECK(notifications.count==17);v=Snap(s,P,after);CHECK(Total(v[@"medals"])==17);v=Snap(s,Q,after);CHECK(Total(v[@"medals"])==0);CHECK([v[@"medals_tracking_started"]isEqual:NSNull.null]);
        CHECK(![v[@"latest_match_medals"][@"available"]boolValue]);CHECK([Snap(s,P,after)[@"latest_match_medals"][@"total"]longLongValue]==17);
        Record(s,Event(HPCareerMatchEnter,0,0),Q,after);Record(s,Event(HPCareerKill,2,0),Q,after);Record(s,Event(HPCareerMedal,2,1),Q,after);CHECK(Count(Snap(s,Q,after),@"medals",1)==1);CHECK(Count(Snap(s,P,after),@"medals",1)==2);
        CHECK([Snap(s,Q,after)[@"latest_match_medals"][@"total"]longLongValue]==1);
        // Same medal and kill number in another real match remain distinct.
        e=Event(HPCareerMatchEnter,0,0);e.game_number++;Record(s,e,P,after);e=Event(HPCareerKill,2,0);e.game_number++;Record(s,e,P,after);e.kind=HPCareerMedal;e.reserved=1;Record(s,e,P,after);CHECK(Count(Snap(s,P,after),@"medals",1)==3);
        CHECK([Snap(s,P,after)[@"latest_match_medals"][@"total"]longLongValue]==1);
        // Corrected/cumulative client snapshots cannot retroactively create medals.
        e=Event(HPCareerMatchEnter,12,0);e.game_number=9;e.flags=1;Record(s,e,P,after);e.kind=HPCareerAuthoritativeTotals;e.event_id=100;e.kills=40;e.streak=30;Record(s,e,P,after);v=Snap(s,P,after);CHECK(Total(v[@"medals"])==18);
        e=Event(HPCareerMedal,15,HPCareerKillingSpree);e.game_number=9;e.flags=1;e.streak=5;Record(s,e,P,after);CHECK(Count(Snap(s,P,after),@"medals",10)==2);
        v=Snap(s,P,after);CHECK([v[@"latest_match_medals"][@"total"]longLongValue]==1);CHECK([v[@"latest_match_medals"][@"medals"][@"10"]longLongValue]==1);CHECK([v[@"latest_match_medals"][@"medals"][@"1"]longLongValue]==0);
        // A confirmed result belongs to this match; starting a new zero-medal
        // game immediately replaces its summary rather than leaking old awards.
        e=Event(HPCareerMatchEnd,0,0);e.game_number=9;e.flags=1;e.result=HPCareerWin;Record(s,e,P,after);v=Snap(s,P,after);CHECK([v[@"latest_match_medals"][@"completed"]boolValue]);CHECK([v[@"latest_match_medals"][@"result"]intValue]==1);CHECK([v[@"latest_match_medals"][@"total"]longLongValue]==1);
        e=Event(HPCareerMatchEnter,0,0);e.game_number=10;strcpy(e.map,"hangemhigh");strcpy(e.mode,"CTF");Record(s,e,P,[after dateByAddingTimeInterval:1]);v=Snap(s,P,after);CHECK([v[@"latest_match_medals"][@"total"]longLongValue]==0);CHECK(Total(v[@"latest_match_medals"][@"medals"])==0);CHECK([v[@"latest_match_medals"][@"map"]isEqual:@"hangemhigh"]);CHECK([v[@"latest_match_medals"][@"mode"]isEqual:@"CTF"]);CHECK([v[@"latest_match_medals"][@"tracked"]boolValue]);CHECK(![v[@"latest_match_medals"][@"completed"]boolValue]);CHECK([v[@"latest_match_medals"][@"result"]intValue]==-1);CHECK([Snap(s,Q,after)[@"latest_match_medals"][@"total"]longLongValue]==1);
        // Invalid payloads never modify records; transient profiles never persist.
        Flush();NSUInteger validNotifications=notifications.count;long long validTotal=Total(Snap(s,P,after)[@"medals"]);
        HPCareerStatsEventV1 good=Event(HPCareerMedal,5,HPCareerKillingSpree),bad;
        for(unsigned i=0;i<16;i++) {bad=good;switch(i){case 0:bad.reserved=0;break;case 1:bad.reserved=16;break;case 2:bad.version=2;break;case 3:bad.size=319;break;case 4:bad.local_player=4;break;case 5:bad.result=1;break;case 6:bad.event_id=0;break;case 7:bad.event_id=6;break;case 8:bad.streak=4;break;case 9:bad.kills=bad.event_id=4;break;case 10:bad.flags=4;break;case 11:bad.flags=2;break;case 12:bad.kills=bad.event_id=UINT32_MAX;break;case 13:memset(bad.map,'a',sizeof bad.map);break;case 14:memset(bad.mode,'a',sizeof bad.mode);break;case 15:memset(bad.weapon,'a',sizeof bad.weapon);break;}CHECK([s recordEvent:&bad profileID:P date:after error:NULL]==2);}
        bad=Event(HPCareerKill,5,1);CHECK([s recordEvent:&bad profileID:P date:after error:NULL]==2);CHECK([s recordEvent:&good profileID:@"bad" date:after error:NULL]==2);CHECK([s recordEvent:&good profileID:P date:[NSDate dateWithTimeIntervalSince1970:NAN] error:NULL]==2);CHECK([s snapshotForProfileID:P date:[NSDate dateWithTimeIntervalSince1970:INFINITY] error:NULL]==nil);
        Flush();CHECK(notifications.count==validNotifications);CHECK(Total(Snap(s,P,after)[@"medals"])==validTotal);
        // Writer contention and failed transactions remain retryable and silent.
        sqlite3 *db=DB(r);SQL(db,"BEGIN IMMEDIATE");good=Event(HPCareerMedal,4,3);good.game_number=8;CHECK([s recordEvent:&good profileID:P date:after error:NULL]==0);Flush();CHECK(notifications.count==validNotifications);SQL(db,"ROLLBACK");Record(s,good,P,after);Record(s,good,P,after);Flush();CHECK(notifications.count==validNotifications+1);
        SQL(db,"CREATE TRIGGER fixture_reject_medal BEFORE INSERT ON career_medals BEGIN SELECT RAISE(ABORT,'fixture'); END;");good=Event(HPCareerMedal,3,2);good.game_number=8;CHECK([s recordEvent:&good profileID:P date:after error:NULL]==0);Flush();CHECK(notifications.count==validNotifications+1);SQL(db,"DROP TRIGGER fixture_reject_medal");Record(s,good,P,after);Flush();CHECK(notifications.count==validNotifications+2);CHECK(Scalar(db,"PRAGMA user_version")==4);sqlite3_close(db);[s close];
        // A killed writer cannot leave an uncommitted medal behind.
        pid_t child=0;NSString *dbPath=[r URLByAppendingPathComponent:@".halopad-career.sqlite3"].path;char *childArgs[]={argv[0],"--uncommitted-medal",(char *)dbPath.fileSystemRepresentation,NULL};CHECK(posix_spawn(&child,argv[0],NULL,NULL,childArgs,environ)==0);int status=0;CHECK(waitpid(child,&status,0)==child);CHECK(WIFSIGNALED(status)&&WTERMSIG(status)==SIGKILL);s=Store(r);CHECK(Total(Snap(s,P,after)[@"medals"])==validTotal+2);[s close];
        // Upgrade an actual v3 schema without interpreting past streaks as medals.
        NSURL *m=Root(@"migration-v3");db=DB(m);
        SQL(db,"CREATE TABLE career_events(profile TEXT NOT NULL,kind INTEGER NOT NULL,seed INTEGER NOT NULL,game INTEGER NOT NULL,crc INTEGER NOT NULL,event INTEGER NOT NULL,local_player INTEGER NOT NULL,streak INTEGER NOT NULL,result INTEGER NOT NULL,mode_id INTEGER NOT NULL,map TEXT NOT NULL,mode TEXT NOT NULL,weapon TEXT NOT NULL,occurred REAL NOT NULL,season TEXT NOT NULL,PRIMARY KEY(profile,kind,seed,game,crc,event)) WITHOUT ROWID; CREATE TABLE career_matches(profile TEXT NOT NULL,seed INTEGER NOT NULL,game INTEGER NOT NULL,crc INTEGER NOT NULL,baseline_k INTEGER NOT NULL,baseline_d INTEGER NOT NULL,baseline_a INTEGER NOT NULL,total_k INTEGER NOT NULL,total_d INTEGER NOT NULL,total_a INTEGER NOT NULL,entered INTEGER NOT NULL,result INTEGER NOT NULL,best_streak INTEGER NOT NULL,last_tick INTEGER NOT NULL,replicated INTEGER NOT NULL,occurred REAL NOT NULL,season TEXT NOT NULL,map TEXT NOT NULL,mode TEXT NOT NULL,PRIMARY KEY(profile,seed,game,crc)) WITHOUT ROWID; CREATE TABLE career_periods(profile TEXT NOT NULL,seed INTEGER NOT NULL,game INTEGER NOT NULL,crc INTEGER NOT NULL,season TEXT NOT NULL,kills INTEGER NOT NULL,deaths INTEGER NOT NULL,assists INTEGER NOT NULL,best_streak INTEGER NOT NULL,entered INTEGER NOT NULL,result INTEGER NOT NULL,PRIMARY KEY(profile,seed,game,crc,season)) WITHOUT ROWID; CREATE TABLE career_tracking(profile TEXT PRIMARY KEY,started REAL NOT NULL) WITHOUT ROWID; PRAGMA user_version=3;");
        NSString *sql=[NSString stringWithFormat:@"INSERT INTO career_events VALUES('%@',2,100,7,123,1000,0,1000,0,2,'bloodgulch','Slayer','pistol',1750000000,'2026-Q3'); INSERT INTO career_matches VALUES('%@',100,7,123,0,0,0,1000,5,10,1,1,1000,-1,0,1750000000,'2026-Q3','bloodgulch','Slayer'); INSERT INTO career_periods VALUES('%@',100,7,123,'2026-Q3',1000,5,10,1000,1,1); INSERT INTO career_tracking VALUES('%@',1750000000);",P,P,P,P];SQL(db,sql.UTF8String);sqlite3_close(db);
        NSData *legacy=[@"original XP database bytes"dataUsingEncoding:NSUTF8StringEncoding];NSURL *xp=[m URLByAppendingPathComponent:@".halopad-progression.sqlite3"];CHECK([legacy writeToURL:xp atomically:YES]);s=Store(m);v=Snap(s,P,t);CHECK([v[@"lifetime"][@"kills"]longLongValue]==1000);CHECK([v[@"lifetime"][@"best_streak"]longLongValue]==1000);CHECK(Total(v[@"medals"])==0);CHECK([v[@"medals_tracking_started"]isEqual:NSNull.null]);CHECK(Season(v,@"2026-Q3")!=nil);CHECK(![Season(v,@"2026-Q3")[@"tracked"]boolValue]);CHECK([Season(v,@"2026-Q3")[@"total"]longLongValue]==0);
        CHECK([v[@"latest_match_medals"][@"available"]boolValue]);CHECK(![v[@"latest_match_medals"][@"tracked"]boolValue]);CHECK([v[@"latest_match_medals"][@"completed"]boolValue]);CHECK([v[@"latest_match_medals"][@"result"]intValue]==1);CHECK([v[@"latest_match_medals"][@"total"]longLongValue]==0);
        Record(s,Event(HPCareerKill,1001,0),P,t);v=Snap(s,P,t);CHECK(Total(v[@"medals"])==0);CHECK([v[@"medals_tracking_started"]isEqual:@"2026-11-03T18:00:00Z"]);CHECK(![Season(v,@"2026-Q3")[@"tracked"]boolValue]);CHECK([Season(v,@"2026-Q4")[@"tracked"]boolValue]);CHECK([[NSData dataWithContentsOfURL:xp]isEqual:legacy]);[s close];
        // Verified guest memory is observed before profile resolution/persistence.
        char *guest=calloc(1,1024);CHECK(guest!=NULL);xg_base=(uintptr_t)guest;NSString *path=@"u:\\udata\\000000000000";memcpy(guest+16,path.UTF8String,path.length);
        HPCareerStatsSetProfileResolver(^NSString *(NSString *p){(void)p;resolved++;return nil;});
        e=Event(HPCareerMedal,2,HPCareerDoubleKill);e.mode_id=(uint32_t)NSDate.date.timeIntervalSince1970;e.flags=HPCareerTransientProfile;memcpy(guest+512,&e,sizeof e);CHECK(xh_host_halopad_career_event_v1(16,(uint32_t)path.length,512,sizeof e)==2);CHECK(observed==1&&resolved==0);
        e.flags=0;memcpy(guest+512,&e,sizeof e);CHECK(xh_host_halopad_career_event_v1(16,(uint32_t)path.length,512,sizeof e)==0);CHECK(observed==2&&resolved==1);
        e.reserved=16;memcpy(guest+512,&e,sizeof e);CHECK(xh_host_halopad_career_event_v1(16,(uint32_t)path.length,512,sizeof e)==2);CHECK(observed==2&&resolved==1);
        e=Event(HPCareerMatchEnter,0,0);e.flags=HPCareerTransientProfile;memcpy(guest+512,&e,sizeof e);CHECK(xh_host_halopad_career_event_v1(16,(uint32_t)path.length,512,sizeof e)==2);CHECK(observed==2&&resolved==1);
        // FIFO retries retain the actual earned quarter even when their first
        // native bridge call occurs after the calendar boundary.
        [NSTimeZone setDefaultTimeZone:[NSTimeZone timeZoneWithName:@"America/Chicago"]];
        NSURL *b=Root(@"delayed-bridge");HPCareerStatsConfigure(b);HPCareerStatsSetProfileResolver(^NSString *(NSString *p){(void)p;resolved++;return P;});
        e=Event(HPCareerMatchEnter,0,0);memcpy(guest+512,&e,sizeof e);CHECK(xh_host_halopad_career_event_v1(16,(uint32_t)path.length,512,sizeof e)==1);
        NSDate *earnedBefore=Date(@"2026-10-01T04:59:59Z"),*earnedAfter=Date(@"2026-10-01T05:00:01Z");
        e=Event(HPCareerMedal,2,HPCareerDoubleKill);e.mode_id=(uint32_t)earnedBefore.timeIntervalSince1970;
        HPCareerStatsEventV1 delayedDouble=e;e=Event(HPCareerMedal,4,HPCareerOverkill);e.mode_id=(uint32_t)NSDate.date.timeIntervalSince1970;
        // A preview gets the HUD past a blocked older FIFO entry, without any
        // profile resolution or persistence. Its later real delivery commits
        // exactly once and keeps the original award quarter.
        sqlite3 *blocked=DB(b);SQL(blocked,"BEGIN IMMEDIATE");int beforePreviewResolver=resolved,beforePreviewObserved=observed;e.flags=HPCareerMedalPreviewOnly;
        memcpy(guest+512,&e,sizeof e);CHECK(xh_host_halopad_career_event_v1(16,(uint32_t)path.length,512,sizeof e)==2);CHECK(resolved==beforePreviewResolver&&observed==beforePreviewObserved+1);CHECK(observedFlags==0);CHECK(Scalar(blocked,"SELECT COUNT(*) FROM career_medals")==0);
        e.flags=0;memcpy(guest+512,&e,sizeof e);CHECK(xh_host_halopad_career_event_v1(16,(uint32_t)path.length,512,sizeof e)==0);CHECK(resolved==beforePreviewResolver+1);CHECK(Scalar(blocked,"SELECT COUNT(*) FROM career_medals")==0);
        e.flags=HPCareerMedalPreviewOnly|HPCareerReplicatedClient;memcpy(guest+512,&e,sizeof e);CHECK(xh_host_halopad_career_event_v1(16,(uint32_t)path.length,512,sizeof e)==2);CHECK(resolved==beforePreviewResolver+1);CHECK(observedFlags==HPCareerReplicatedClient);
        e.flags=HPCareerMedalPreviewOnly|HPCareerTransientProfile;memcpy(guest+512,&e,sizeof e);CHECK(xh_host_halopad_career_event_v1(16,(uint32_t)path.length,512,sizeof e)==2);CHECK(resolved==beforePreviewResolver+1);CHECK(observedFlags==HPCareerTransientProfile);
        e.flags=HPCareerMedalPreviewOnly|8;memcpy(guest+512,&e,sizeof e);beforePreviewObserved=observed;CHECK(xh_host_halopad_career_event_v1(16,(uint32_t)path.length,512,sizeof e)==2);CHECK(observed==beforePreviewObserved&&resolved==beforePreviewResolver+1);
        e.flags=HPCareerMedalPreviewOnly;e.kind=HPCareerKill;e.reserved=0;memcpy(guest+512,&e,sizeof e);CHECK(xh_host_halopad_career_event_v1(16,(uint32_t)path.length,512,sizeof e)==2);CHECK(observed==beforePreviewObserved&&resolved==beforePreviewResolver+1);
        SQL(blocked,"ROLLBACK");sqlite3_close(blocked);e.kind=HPCareerMedal;e.reserved=HPCareerOverkill;e.flags=0;memcpy(guest+512,&e,sizeof e);CHECK(xh_host_halopad_career_event_v1(16,(uint32_t)path.length,512,sizeof e)==1);CHECK(xh_host_halopad_career_event_v1(16,(uint32_t)path.length,512,sizeof e)==1);
        e=delayedDouble;memcpy(guest+512,&e,sizeof e);CHECK(xh_host_halopad_career_event_v1(16,(uint32_t)path.length,512,sizeof e)==1);
        e=Event(HPCareerMedal,3,HPCareerTripleKill);e.mode_id=(uint32_t)earnedAfter.timeIntervalSince1970;memcpy(guest+512,&e,sizeof e);CHECK(xh_host_halopad_career_event_v1(16,(uint32_t)path.length,512,sizeof e)==1);
        e=Event(HPCareerMedal,2,HPCareerDoubleKill);e.mode_id=(uint32_t)NSDate.date.timeIntervalSince1970;memcpy(guest+512,&e,sizeof e);CHECK(xh_host_halopad_career_event_v1(16,(uint32_t)path.length,512,sizeof e)==1);
        HPCareerStatsStore *bs=Store(b);v=Snap(bs,P,t);CHECK(Count(v,@"medals",1)==1&&Count(v,@"medals",2)==1);CHECK(Count(v,@"season_medals",1)==0&&Count(v,@"season_medals",2)==1);CHECK(Count(v,@"medals",3)==1);CHECK([Season(v,@"2026-Q3")[@"medals"][@"1"]longLongValue]==1);CHECK([Season(v,@"2026-Q4")[@"medals"][@"2"]longLongValue]==1);CHECK([Season(v,@"2026-Q3")[@"tracked"]boolValue]);CHECK([v[@"medals_tracking_started"]isEqual:@"2026-10-01T04:59:59Z"]);[bs close];
        unsigned validObserved=observed;e.mode_id=0;memcpy(guest+512,&e,sizeof e);CHECK(xh_host_halopad_career_event_v1(16,(uint32_t)path.length,512,sizeof e)==2);e.mode_id=(uint32_t)NSDate.date.timeIntervalSince1970+3600;memcpy(guest+512,&e,sizeof e);CHECK(xh_host_halopad_career_event_v1(16,(uint32_t)path.length,512,sizeof e)==2);CHECK((unsigned)observed==validObserved);
        Flush();CHECK([notifications.lastObject[@"earned_at"]isEqual:@"2026-10-01T05:00:01Z"]);HPCareerStatsConfigure(r);
        xg_base=0;free(guest);HPCareerStatsSetProfileResolver(nil);
        Flush();[NSNotificationCenter.defaultCenter removeObserver:observer];for(NSURL *root in @[r,m,b])CHECK([NSFileManager.defaultManager removeItemAtURL:root error:NULL]);
        printf("PASS %d medal checks: all15 tiers, transaction dedup, profile/match identity, local-quarter history, zero seasons, additive v3 migration, no backfill, restart, contention, rollback, crash recovery, validated transient HUD bridge and committed notifications\n",checks);
    }
    return 0;
}
