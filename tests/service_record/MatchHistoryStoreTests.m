/* Synthetic fixtures only; no installed profiles or engine execution. */
#import "HPCareerStatsStore.h"
#import <sqlite3.h>
#include <math.h>

uintptr_t xg_base=0;
static NSUInteger checks;
static NSString *const P=@"12345678-1234-1234-1234-123456789ABC";
static NSString *const Q=@"ABCD1234-1234-1234-1234-123456789ABC";
#define CHECK(c) do { checks++; if(!(c)){fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#c);exit(1);} } while(0)

static NSDate *Date(NSString *text) { return [[NSISO8601DateFormatter new]dateFromString:text]; }
static NSCalendar *Calendar(void) {
    NSCalendar *calendar=[[NSCalendar alloc]initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone=[NSTimeZone timeZoneWithName:@"America/Chicago"];
    return calendar;
}
static NSURL *Root(NSString *name) {
    NSString *directory=[@(getenv("HALOPAD_TEST_RESULTS"))stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"HaloHistoryFixtures-%@-%@",NSUUID.UUID.UUIDString,name]];
    CHECK([NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL]);
    return [NSURL fileURLWithPath:directory isDirectory:YES];
}
static HPCareerStatsStore *Store(NSURL *root) {
    NSError *error=nil;
    HPCareerStatsStore *store=[[HPCareerStatsStore alloc]initWithSaveRootURL:root calendar:Calendar() error:&error];
    if(!store)fprintf(stderr,"store: %s\n",error.description.UTF8String);
    CHECK(store!=nil);return store;
}
static HPCareerStatsEventV1 Event(unsigned kind,unsigned game,unsigned kills,unsigned deaths,unsigned assists) {
    HPCareerStatsEventV1 event={0};
    event.version=1;event.size=sizeof event;event.kind=kind;event.session_seed=100;
    event.game_number=game;event.map_crc=123;event.kills=kills;event.deaths=deaths;event.assists=assists;
    event.mode_id=2;strcpy(event.map,"bloodgulch");strcpy(event.mode,"Slayer");strcpy(event.weapon,"pistol");
    return event;
}
static void Record(HPCareerStatsStore *store,HPCareerStatsEventV1 event,NSString *profile,NSDate *date) {
    NSError *error=nil;uint32_t result=[store recordEvent:&event profileID:profile date:date error:&error];
    if(result!=1)fprintf(stderr,"record: %s\n",error.description.UTF8String);
    CHECK(result==1);
}
static NSDictionary *History(HPCareerStatsStore *store,NSString *profile,NSDate *date,BOOL lifetime,NSUInteger limit) {
    NSError *error=nil;
    NSDictionary *history=[store matchHistoryForProfileID:profile date:date lifetime:lifetime limit:limit error:&error];
    if(!history)fprintf(stderr,"history: %s\n",error.description.UTF8String);
    CHECK(history!=nil);CHECK(error==nil);
    CHECK([NSJSONSerialization dataWithJSONObject:history options:0 error:NULL]!=nil);
    CHECK(![history[@"storage_error"]boolValue]);CHECK([history[@"lifetime"]boolValue]==lifetime);
    CHECK([history[@"profile_id"]isEqual:profile.uppercaseString]);
    return history;
}
static NSDictionary *Match(NSDictionary *history,unsigned game) {
    NSDictionary *found=nil;
    for(NSDictionary *row in history[@"matches"])if([row[@"game"]unsignedIntValue]==game){CHECK(found==nil);found=row;}
    CHECK(found!=nil);return found;
}
static long long N(NSDictionary *row,NSString *key) { return [row[key]longLongValue]; }
static long long MedalTotal(NSDictionary *counts) {
    CHECK(counts.count==15);long long total=0;
    for(unsigned index=1;index<=15;index++) {
        id value=counts[[NSString stringWithFormat:@"%u",index]];
        CHECK([value isKindOfClass:NSNumber.class]);CHECK([value longLongValue]>=0);total+=[value longLongValue];
    }
    return total;
}
static sqlite3 *DB(NSURL *root) {
    sqlite3 *db=NULL;CHECK(sqlite3_open([root URLByAppendingPathComponent:@".halopad-career.sqlite3"].fileSystemRepresentation,&db)==SQLITE_OK);return db;
}
static void SQL(sqlite3 *db,const char *sql) {
    char *error=NULL;int result=sqlite3_exec(db,sql,NULL,NULL,&error);
    if(result!=SQLITE_OK)fprintf(stderr,"SQL: %s\n",error);CHECK(result==SQLITE_OK);sqlite3_free(error);
}
static long long Scalar(sqlite3 *db,const char *sql) {
    sqlite3_stmt *statement=NULL;CHECK(sqlite3_prepare_v2(db,sql,-1,&statement,NULL)==SQLITE_OK);
    CHECK(sqlite3_step(statement)==SQLITE_ROW);long long value=sqlite3_column_int64(statement,0);sqlite3_finalize(statement);return value;
}

int main(void) { @autoreleasepool {
    NSDate *before=Date(@"2027-01-01T05:59:59Z"),*after=Date(@"2027-01-01T06:00:01Z");
    NSURL *root=Root(@"actual-events");
    NSData *xp=[@"Original progression bytes: history must never rewrite this file."dataUsingEncoding:NSUTF8StringEncoding];
    NSURL *xpURL=[root URLByAppendingPathComponent:@".halopad-progression.sqlite3"];
    CHECK([xp writeToURL:xpURL atomically:YES]);
    HPCareerStatsStore *store=Store(root);
    NSDictionary *history=History(store,P,after,NO,0);
    CHECK([history[@"season_id"]isEqual:@"2027-Q1"]);CHECK([history[@"matches"]count]==0);
    CHECK(N(history,@"limit")==50);CHECK(![history[@"has_more"]boolValue]);
    CHECK([history[@"tracking_started"]isEqual:NSNull.null]);

    // A joined client's pre-tracking totals are never presented as earned here.
    // One match can contribute to two quarters without becoming two history rows.
    HPCareerStatsEventV1 event=Event(HPCareerMatchEnter,10,5,3,2);event.flags=HPCareerReplicatedClient;
    Record(store,event,P,before);Record(store,event,P,before);
    event.kind=HPCareerAuthoritativeTotals;event.event_id=1;event.kills=7;event.deaths=4;event.assists=3;event.streak=2;
    Record(store,event,P,before);
    HPCareerStatsEventV1 medal=event;medal.kind=HPCareerMedal;medal.event_id=7;medal.reserved=HPCareerDoubleKill;
    Record(store,medal,P,before);Record(store,medal,P,before);
    event.event_id=2;event.kills=9;event.deaths=5;event.assists=4;event.streak=3;Record(store,event,P,after);
    event.event_id=3;event.kills=8;event.deaths=4;event.assists=3;Record(store,event,P,after);
    medal=event;medal.kind=HPCareerMedal;medal.event_id=8;medal.reserved=HPCareerTripleKill;Record(store,medal,P,after);
    event.kind=HPCareerMatchEnd;event.event_id=0;event.result=HPCareerWin;Record(store,event,P,after);
    NSDictionary *prior=History(store,P,before,NO,20),*current=History(store,P,after,NO,20);
    NSDictionary *row=Match(current,10),*oldRow=Match(prior,10);
    CHECK([current[@"matches"]count]==1&&[prior[@"matches"]count]==1);
    CHECK([row[@"match_id"]isEqual:oldRow[@"match_id"]]);
    CHECK(N(row,@"kills")==3&&N(row,@"deaths")==1&&N(row,@"assists")==1);
    CHECK(N(oldRow,@"kills")==3&&N(oldRow,@"deaths")==1&&N(oldRow,@"assists")==1);
    CHECK(N(oldRow,@"season_kills")==2&&N(row,@"season_kills")==1);
    CHECK(N(oldRow,@"season_deaths")==1&&N(row,@"season_deaths")==0);
    CHECK(N(oldRow,@"season_assists")==1&&N(row,@"season_assists")==0);
    CHECK(N(row,@"result")==HPCareerWin&&[row[@"completed"]boolValue]);
    CHECK([row[@"replicated"]boolValue]&&[row[@"partial"]boolValue]);
    CHECK([row[@"started_at"]isEqual:@"2027-01-01T05:59:59Z"]);
    CHECK([row[@"season_id"]isEqual:@"2026-Q4"]);
    CHECK(N(row,@"best_streak")==3&&N(row,@"season_best_streak")==3);
    CHECK(MedalTotal(row[@"medals"])==2&&N(row,@"medal_total")==2);
    CHECK(MedalTotal(row[@"season_medals"])==1&&N(row,@"season_medal_total")==1);
    CHECK(N(row[@"season_medals"],@"2")==1&&N(oldRow[@"season_medals"],@"1")==1);
    CHECK([row[@"medals_tracked"]boolValue]);

    // An award in a new quarter is real activity even without a combat period.
    event=Event(HPCareerMatchEnter,11,0,0,0);Record(store,event,P,before);
    event.kind=HPCareerKill;event.event_id=2;event.kills=2;event.streak=2;Record(store,event,P,before);
    event.kind=HPCareerMedal;event.reserved=HPCareerDoubleKill;Record(store,event,P,after);
    current=History(store,P,after,NO,20);row=Match(current,11);
    CHECK(N(row,@"kills")==2&&N(row,@"season_kills")==0);
    CHECK(N(row,@"result")==-1&&![row[@"completed"]boolValue]);
    CHECK(N(row,@"season_medal_total")==1);
    CHECK(![row[@"replicated"]boolValue]&&![row[@"partial"]boolValue]);

    // Unknown completion and an unfinished game remain distinct. A later
    // confirmed result may replace unknown, but cannot replace a known result.
    NSDate *later=[after dateByAddingTimeInterval:10];
    event=Event(HPCareerMatchEnter,12,0,0,0);Record(store,event,P,later);
    event.kind=HPCareerMatchEnd;event.result=HPCareerUnknown;Record(store,event,P,later);
    row=Match(History(store,P,after,NO,20),12);
    CHECK(N(row,@"result")==0&&[row[@"completed"]boolValue]);
    event.result=HPCareerLoss;Record(store,event,P,later);event.result=HPCareerWin;Record(store,event,P,later);
    CHECK(N(Match(History(store,P,after,NO,20),12),@"result")==HPCareerLoss);
    event=Event(HPCareerMatchEnter,13,0,0,0);Record(store,event,P,later);
    event.kind=HPCareerMatchEnd;event.result=HPCareerUnknown;Record(store,event,P,later);
    row=Match(History(store,P,after,NO,20),13);CHECK(N(row,@"result")==0&&[row[@"completed"]boolValue]);

    // The same guest match identifiers in another named profile are isolated.
    event=Event(HPCareerMatchEnter,10,0,0,0);Record(store,event,Q,later);
    event.kind=HPCareerKill;event.event_id=20;event.kills=20;Record(store,event,Q,later);
    history=History(store,Q,after,YES,100);CHECK([history[@"matches"]count]==1);
    CHECK(N(Match(history,10),@"kills")==20);
    CHECK(![History(store,Q,after,YES,1)[@"has_more"]boolValue]);
    CHECK(N(Match(History(store,P.lowercaseString,after,YES,100),10),@"kills")==3);

    // Read the actual stored migration result; do not infer old medals or rewrite
    // old XP. Repeat/read/reopen cannot add history rows or change committed data.
    sqlite3 *db=DB(root);long long events=Scalar(db,"SELECT COUNT(*) FROM career_events"),
        medals=Scalar(db,"SELECT COUNT(*) FROM career_medals"),matches=Scalar(db,"SELECT COUNT(*) FROM career_matches");
    CHECK(Scalar(db,"PRAGMA user_version")==4);sqlite3_close(db);
    NSDictionary *saved=History(store,P,after,YES,100);
    CHECK([saved isEqual:History(store,P,after,YES,100)]);
    [store close];store=Store(root);CHECK([saved isEqual:History(store,P,after,YES,100)]);
    db=DB(root);CHECK(Scalar(db,"SELECT COUNT(*) FROM career_events")==events);
    CHECK(Scalar(db,"SELECT COUNT(*) FROM career_medals")==medals);
    CHECK(Scalar(db,"SELECT COUNT(*) FROM career_matches")==matches);CHECK(Scalar(db,"PRAGMA user_version")==4);sqlite3_close(db);
    CHECK([[NSData dataWithContentsOfURL:xpURL]isEqual:xp]);
    NSError *error=nil;CHECK([store matchHistoryForProfileID:@"../not-a-profile" date:after lifetime:YES limit:10 error:&error]==nil&&error!=nil);
    error=nil;NSDate *invalidDate=[NSDate dateWithTimeIntervalSince1970:NAN];
    CHECK([store matchHistoryForProfileID:P date:invalidDate lifetime:YES limit:10 error:&error]==nil&&error!=nil);
    [store close];error=nil;CHECK([store matchHistoryForProfileID:P date:after lifetime:YES limit:10 error:&error]==nil&&error!=nil);

    // The production guest-path wrapper re-resolves the real profile for every
    // read; an invalid or unresolved path cannot retain another player's rows.
    HPCareerStatsConfigure(root);
    __block NSUInteger resolutions=0;
    NSString *guestPath=@"U:\\UDATA\\123456789ABC";
    HPCareerStatsSetProfileResolver(^NSString *(NSString *path){CHECK([path isEqual:guestPath]);resolutions++;return P;});
    history=HPCareerStatsMatchHistory(guestPath,YES,20);CHECK([history[@"profile_id"]isEqual:P]&&[history[@"matches"]count]==4);
    CHECK(resolutions==1);
    history=HPCareerStatsMatchHistory(@"../invalid",YES,20);CHECK([history[@"storage_error"]boolValue]&&[history[@"matches"]count]==0&&resolutions==1);
    HPCareerStatsSetProfileResolver(^NSString *(NSString *path){(void)path;resolutions++;return Q;});
    history=HPCareerStatsMatchHistory(guestPath,YES,20);CHECK([history[@"profile_id"]isEqual:Q]&&[history[@"matches"]count]==1);
    CHECK(N(Match(history,10),@"kills")==20);
    HPCareerStatsSetProfileResolver(nil);history=HPCareerStatsMatchHistory(guestPath,YES,20);
    CHECK([history[@"storage_error"]boolValue]&&[history[@"matches"]count]==0);

    // Equal timestamps sort by real guest identity; stable ordering matters when
    // a bounded list is refreshed and the newest matches are selected.
    NSURL *bounded=Root(@"bounded");store=Store(bounded);
    for(unsigned game=1;game<=105;game++){event=Event(HPCareerMatchEnter,game,0,0,0);Record(store,event,P,after);}
    history=History(store,P,after,YES,0);CHECK(N(history,@"limit")==50&&[history[@"matches"]count]==50&&[history[@"has_more"]boolValue]);
    CHECK(N(history[@"matches"][0],@"game")==105&&N(history[@"matches"][49],@"game")==56);
    history=History(store,P,after,YES,NSUIntegerMax);CHECK(N(history,@"limit")==100&&[history[@"matches"]count]==100&&[history[@"has_more"]boolValue]);
    CHECK(N(history[@"matches"][99],@"game")==6);
    history=History(store,P,after,YES,1);CHECK([history[@"matches"]count]==1&&[history[@"has_more"]boolValue]);
    NSMutableSet *identifiers=[NSMutableSet set];for(NSDictionary *match in History(store,P,after,YES,100)[@"matches"]){CHECK([match[@"match_id"]isKindOfClass:NSString.class]&&[match[@"match_id"]length]>0);[identifiers addObject:match[@"match_id"]];}CHECK(identifiers.count==100);
    for(unsigned seed=1;seed<=2;seed++)for(unsigned crc=1;crc<=2;crc++){event=Event(HPCareerMatchEnter,200,0,0,0);event.session_seed=seed;event.map_crc=crc;Record(store,event,P,after);}
    NSArray *ties=History(store,P,after,YES,4)[@"matches"];
    CHECK(N(ties[0],@"seed")==2&&N(ties[0],@"crc")==2);CHECK(N(ties[1],@"seed")==2&&N(ties[1],@"crc")==1);
    CHECK(N(ties[2],@"seed")==1&&N(ties[2],@"crc")==2);CHECK(N(ties[3],@"seed")==1&&N(ties[3],@"crc")==1);
    CHECK([History(store,P,before,NO,100)[@"matches"]count]==0);
    CHECK(![History(store,Q,after,YES,1)[@"has_more"]boolValue]);
    // A malformed saved row reports unavailable, not a partially successful
    // history. Its read transaction must roll back so a repaired store can retry.
    db=DB(bounded);SQL(db,"UPDATE career_matches SET result=9 WHERE game=200 AND seed=2 AND crc=2");
    error=nil;CHECK([store matchHistoryForProfileID:P date:after lifetime:YES limit:100 error:&error]==nil&&error!=nil);
    SQL(db,"UPDATE career_matches SET result=-1 WHERE game=200 AND seed=2 AND crc=2");sqlite3_close(db);
    CHECK([History(store,P,after,YES,4)[@"matches"]count]==4);
    [store close];

    NSURL *migration=Root(@"v1");db=DB(migration);
    SQL(db,"CREATE TABLE career_events(profile TEXT,kind INTEGER,seed INTEGER,game INTEGER,crc INTEGER,event INTEGER,local_player INTEGER,streak INTEGER,result INTEGER,mode_id INTEGER,map TEXT,mode TEXT,weapon TEXT,occurred REAL,season TEXT,PRIMARY KEY(profile,kind,seed,game,crc,event)); PRAGMA user_version=1;");
    NSString *sql=[NSString stringWithFormat:@"INSERT INTO career_events VALUES('%@',1,1,1,1,0,0,0,0,2,'legacy_map','Slayer','unknown',1700000000,'2023-Q4'),('%@',2,1,1,1,1,0,1,0,2,'legacy_map','Slayer','pistol',1700000001,'2023-Q4'),('%@',5,1,1,1,0,0,0,0,2,'legacy_map','Slayer','unknown',1700000002,'2023-Q4')",P,P,P];
    SQL(db,sql.UTF8String);sqlite3_close(db);
    NSURL *migrationXP=[migration URLByAppendingPathComponent:@".halopad-progression.sqlite3"];CHECK([xp writeToURL:migrationXP atomically:YES]);
    store=Store(migration);history=History(store,P,after,YES,100);CHECK([history[@"matches"]count]==1);row=Match(history,1);
    CHECK(N(row,@"kills")==1&&N(row,@"deaths")==0&&N(row,@"result")==0&&[row[@"completed"]boolValue]);
    CHECK([row[@"map"]isEqual:@"legacy_map"]&&[row[@"season_id"]isEqual:@"2023-Q4"]);
    CHECK(N(row,@"medal_total")==0&&! [row[@"medals_tracked"]boolValue]);
    CHECK([History(store,P,after,NO,100)[@"matches"]count]==0);
    CHECK([[NSData dataWithContentsOfURL:migrationXP]isEqual:xp]);
    db=DB(migration);CHECK(Scalar(db,"SELECT COUNT(*) FROM career_events")==3);CHECK(Scalar(db,"PRAGMA user_version")==4);sqlite3_close(db);[store close];
    for(NSURL *fixture in @[root,bounded,migration])CHECK([NSFileManager.defaultManager removeItemAtURL:fixture error:NULL]);
    printf("PASS %lu history checks: profile isolation, quarter/medal activity, whole-match baselines/corrections, unknown/unfinished results, stable bounded ordering, read-only queries, reopen and legacy migration preserving XP\n",(unsigned long)checks);
} return 0; }
