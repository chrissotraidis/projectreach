/* Synthetic fixtures only; no installed profiles or engine execution. */
#import "HPCareerStatsStore.h"
#import <sqlite3.h>
#include <sys/wait.h>
#include <unistd.h>
#include <spawn.h>
#include <signal.h>
extern char **environ;
#include <math.h>
uintptr_t xg_base=0;
static int checks=0;
#define CHECK(c) do { checks++;if(!(c)){fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#c);exit(1);} }while(0)
static NSString *P=@"12345678-1234-1234-1234-123456789ABC",*Q=@"ABCD1234-1234-1234-1234-123456789ABC";
static NSCalendar *Calendar(void){NSCalendar*c=[[NSCalendar alloc]initWithCalendarIdentifier:NSCalendarIdentifierGregorian];c.timeZone=[NSTimeZone timeZoneWithName:@"America/Chicago"];return c;}
static NSDate *Date(NSString *text){return [[NSISO8601DateFormatter new]dateFromString:text];}
static NSURL *Root(NSString *name){NSString*p=[@(getenv("HALOPAD_TEST_RESULTS")) stringByAppendingPathComponent:[NSString stringWithFormat:@"HaloCareerFixtures-%@-%@",NSUUID.UUID.UUIDString,name]];CHECK([NSFileManager.defaultManager createDirectoryAtPath:p withIntermediateDirectories:YES attributes:nil error:NULL]);return [NSURL fileURLWithPath:p isDirectory:YES];}
static HPCareerStatsStore *Store(NSURL*r){NSError*e=nil;HPCareerStatsStore*s=[[HPCareerStatsStore alloc]initWithSaveRootURL:r calendar:Calendar() error:&e];if(!s)fprintf(stderr,"store: %s\n",e.description.UTF8String);CHECK(s!=nil);return s;}
static HPCareerStatsEventV1 Event(unsigned kind,unsigned id,unsigned k,unsigned d,unsigned a){HPCareerStatsEventV1 e={0};e.version=1;e.size=sizeof e;e.kind=kind;e.session_seed=100;e.game_number=7;e.map_crc=123;e.event_id=id;e.kills=k;e.deaths=d;e.assists=a;e.mode_id=2;strcpy(e.map,"bloodgulch");strcpy(e.mode,"Slayer");strcpy(e.weapon,"pistol");return e;}
static void Record(HPCareerStatsStore*s,HPCareerStatsEventV1 e,NSString*p,NSDate*d){NSError*err=nil;uint32_t r=[s recordEvent:&e profileID:p date:d error:&err];if(r!=1)fprintf(stderr,"record: %s\n",err.description.UTF8String);CHECK(r==1);}
static NSDictionary *Snap(HPCareerStatsStore*s,NSString*p,NSDate*d){NSError*e=nil;NSDictionary*v=[s snapshotForProfileID:p date:d error:&e];if(!v)fprintf(stderr,"snapshot: %s\n",e.description.UTF8String);CHECK(v!=nil);return v;}
static long long N(NSDictionary*d,NSString*k){return[d[k]longLongValue];}
static sqlite3 *DB(NSURL*r){sqlite3*db=NULL;CHECK(sqlite3_open([[r URLByAppendingPathComponent:@".halopad-career.sqlite3"]fileSystemRepresentation],&db)==SQLITE_OK);return db;}
static void SQL(sqlite3*d,const char*q){char*err=NULL;int rc=sqlite3_exec(d,q,NULL,NULL,&err);if(rc!=SQLITE_OK)fprintf(stderr,"SQL: %s\n",err);CHECK(rc==SQLITE_OK);sqlite3_free(err);}
int main(int argc,char **argv){if(argc==3&&!strcmp(argv[1],"--uncommitted-writer")){sqlite3*z=NULL;if(sqlite3_open(argv[2],&z)!=SQLITE_OK)return 91;if(sqlite3_exec(z,"BEGIN IMMEDIATE; UPDATE career_matches SET total_k=999999; UPDATE career_periods SET kills=999999;",NULL,NULL,NULL)!=SQLITE_OK)return 92;raise(SIGKILL);return 93;}@autoreleasepool {
 NSDate*t=Date(@"2026-11-03T18:00:00Z");NSURL*r=Root(@"basic");NSData*legacy=[@"original XP bytes must stay untouched" dataUsingEncoding:NSUTF8StringEncoding];NSURL*legacyPath=[r URLByAppendingPathComponent:@".halopad-progression.sqlite3"];CHECK([legacy writeToURL:legacyPath atomically:YES]);
 HPCareerStatsStore*s=Store(r);NSDictionary*v=Snap(s,P,t);CHECK(N(v[@"lifetime"],@"kills")==0);CHECK(![v[@"tracking_active"]boolValue]);CHECK(![v[@"lifetime"][@"kd_defined"]boolValue]);CHECK(![v[@"lifetime"][@"win_rate_defined"]boolValue]);CHECK(isfinite([v[@"lifetime"][@"kd"]doubleValue]));CHECK([NSJSONSerialization dataWithJSONObject:v options:0 error:NULL]!=nil);
 HPCareerStatsEventV1 e=Event(HPCareerMatchEnter,0,0,0,0);Record(s,e,P,t);Record(s,e,P,t);v=Snap(s,P,t);CHECK(N(v[@"lifetime"],@"matches_played")==1);CHECK([v[@"tracking_active"]boolValue]);
 e=Event(HPCareerKill,1,1,0,0);e.streak=1;Record(s,e,P,t);Record(s,e,P,t);e=Event(HPCareerKill,2,2,0,0);e.streak=2;Record(s,e,P,t);e=Event(HPCareerDeath,1,2,1,0);Record(s,e,P,t);e=Event(HPCareerAssist,1,2,1,1);Record(s,e,P,t);
 e=Event(HPCareerMatchEnd,0,2,1,1);e.result=HPCareerWin;Record(s,e,P,t);Record(s,e,P,t);v=Snap(s,P,t);NSDictionary*l=v[@"lifetime"];CHECK(N(l,@"kills")==2&&N(l,@"deaths")==1&&N(l,@"assists")==1);CHECK(N(l,@"best_streak")==2);CHECK(N(l,@"wins")==1&&N(l,@"matches_played")==1);CHECK([l[@"kd"]doubleValue]==2);CHECK([l[@"win_rate"]doubleValue]==100);CHECK([v[@"maps"]count]==1&&[v[@"weapons"]count]==1);CHECK(N(v[@"weapons"][0],@"kills")==2);CHECK(N(Snap(s,Q,t)[@"lifetime"],@"kills")==0);CHECK([[NSData dataWithContentsOfURL:legacyPath]isEqual:legacy]);
 // Restart/resume, duplicate retransmission, separate map/game identities.
 [s close];s=Store(r);e=Event(HPCareerKill,2,2,0,0);Record(s,e,P,t);CHECK(N(Snap(s,P,t)[@"lifetime"],@"kills")==2);
 e=Event(HPCareerMatchEnter,0,0,0,0);e.game_number++;Record(s,e,P,t);e.kind=HPCareerMatchEnd;e.result=HPCareerUnknown;Record(s,e,P,t);e.result=HPCareerLoss;Record(s,e,P,t);Record(s,e,P,t);e.result=HPCareerWin;Record(s,e,P,t);v=Snap(s,P,t);CHECK(N(v[@"lifetime"],@"losses")==1&&N(v[@"lifetime"],@"draws")==0);CHECK([v[@"lifetime"][@"win_rate"]doubleValue]==50);CHECK(N(v[@"lifetime"],@"unknown_results")==0);
 // Joined distributed client baseline; exact replication, stale suppression, signed correction.
 e=Event(HPCareerMatchEnter,0,5,3,1);e.game_number=9;e.flags=HPCareerReplicatedClient;Record(s,e,P,t);
 e.kind=HPCareerAuthoritativeTotals;e.event_id=100;e.kills=8;e.deaths=5;e.assists=3;e.streak=3;strcpy(e.weapon,"unknown");Record(s,e,P,t);Record(s,e,P,t);v=Snap(s,P,t);CHECK(N(v[@"lifetime"],@"kills")==5);CHECK(N(v[@"lifetime"],@"deaths")==3);CHECK(N(v[@"lifetime"],@"assists")==3);
 e.event_id=90;e.kills=50;Record(s,e,P,t);CHECK(N(Snap(s,P,t)[@"lifetime"],@"kills")==5);
 e.event_id=101;e.kills=7;e.deaths=4;e.assists=2;Record(s,e,P,t);CHECK(N(Snap(s,P,t)[@"lifetime"],@"kills")==4);
 // Equal tick changed accepted native payload follows guest FIFO; exact retry remains no-op.
 e.kills=6;Record(s,e,P,t);Record(s,e,P,t);CHECK(N(Snap(s,P,t)[@"lifetime"],@"kills")==3);
 e.kind=HPCareerMatchEnd;e.event_id=0;e.kills=e.deaths=e.assists=e.streak=0;e.result=HPCareerDraw;Record(s,e,P,t);v=Snap(s,P,t);CHECK(N(v[@"lifetime"],@"kills")==3);CHECK(N(v[@"lifetime"],@"draws")==1);CHECK(N(v[@"lifetime"],@"matches_played")==3);CHECK(fabs([v[@"lifetime"][@"win_rate"]doubleValue]-100.0/3)<0.001);
 // Client correction below join baseline cannot invent negative career totals.
 e=Event(HPCareerMatchEnter,0,10,10,10);e.game_number=10;e.flags=1;Record(s,e,P,t);e.kind=HPCareerAuthoritativeTotals;e.event_id=UINT32_MAX-1;e.kills=e.deaths=e.assists=9;Record(s,e,P,t);e.event_id=2;e.kills=12;e.deaths=11;e.assists=10;Record(s,e,P,t);CHECK(N(Snap(s,P,t)[@"lifetime"],@"kills")==5);
 // Invalid ABI/text/profile cannot mutate state; premature events retry until real entry.
 HPCareerStatsEventV1 bad=e;bad.version=2;CHECK([s recordEvent:&bad profileID:P date:t error:NULL]==2);bad=e;memset(bad.map,'a',sizeof bad.map);CHECK([s recordEvent:&bad profileID:P date:t error:NULL]==2);CHECK([s recordEvent:&e profileID:@"../evil" date:t error:NULL]==2);bad=Event(HPCareerKill,1,1,0,0);bad.game_number=555;CHECK([s recordEvent:&bad profileID:P date:t error:NULL]==0);
 // Chicago local year/quarter, duplicate retried after boundary stays in original season.
 NSDate*before=Date(@"2027-01-01T05:59:59Z"),*after=Date(@"2027-01-01T06:00:01Z");e=Event(HPCareerMatchEnter,0,0,0,0);e.game_number=11;Record(s,e,P,before);e.kind=HPCareerKill;e.event_id=1;e.kills=1;Record(s,e,P,before);Record(s,e,P,after);v=Snap(s,P,after);CHECK([v[@"season_id"]isEqual:@"2027-Q1"]);CHECK(N(v[@"season"],@"kills")==0);CHECK([v[@"season_maps"]count]==0);e=Event(HPCareerMatchEnter,0,0,0,0);e.game_number=12;Record(s,e,P,after);e.kind=HPCareerKill;e.event_id=1;e.kills=1;Record(s,e,P,after);v=Snap(s,P,after);CHECK(N(v[@"season"],@"kills")==1);CHECK([v[@"season_maps"]count]==1);
 // One match crossing Chicago New Year: per-quarter activity/results remain coherent;
 // lifetime counts the real match once. Downward correction removes newest allocations.
 e=Event(HPCareerMatchEnter,0,0,0,0);e.game_number=30;e.flags=1;Record(s,e,Q,before);e.kind=HPCareerAuthoritativeTotals;e.event_id=1;e.kills=2;e.deaths=1;Record(s,e,Q,before);e.event_id=2;e.kills=4;e.deaths=2;Record(s,e,Q,after);e.event_id=3;e.kills=3;e.deaths=1;Record(s,e,Q,after);e.kind=HPCareerMatchEnd;e.event_id=0;e.result=HPCareerWin;e.kills=e.deaths=e.assists=0;Record(s,e,Q,after);v=Snap(s,Q,after);CHECK(N(v[@"lifetime"],@"kills")==3);CHECK(N(v[@"lifetime"],@"matches_played")==1);CHECK(N(v[@"season"],@"kills")==1);CHECK(N(v[@"season"],@"deaths")==0);CHECK(N(v[@"season"],@"matches_played")==1&&N(v[@"season"],@"wins")==1);CHECK(N(v[@"maps"][0],@"matches_played")==1);CHECK(N(Snap(s,Q,before)[@"season"],@"kills")==2);
 // SQLite writer contention yields retry without losing/recounting the event.
 sqlite3*d=DB(r);SQL(d,"BEGIN IMMEDIATE");e=Event(HPCareerKill,2,2,0,0);e.game_number=12;CHECK([s recordEvent:&e profileID:P date:after error:NULL]==0);SQL(d,"ROLLBACK");sqlite3_close(d);Record(s,e,P,after);CHECK(N(Snap(s,P,after)[@"season"],@"kills")==2);
 // Unknown/custom non-UTF8 metadata must not discard genuine native totals.
 e=Event(HPCareerMatchEnter,0,0,0,0);e.game_number=40;e.map[0]=(char)0xff;e.map[1]=0;e.mode[0]='\n';e.mode[1]=0;Record(s,e,Q,after);e.kind=HPCareerKill;e.event_id=1;e.kills=1;e.weapon[0]=(char)0xff;e.weapon[1]=0;Record(s,e,Q,after);v=Snap(s,Q,after);CHECK(N(v[@"lifetime"],@"kills")==4);BOOL foundUnknown=NO;for(NSDictionary*row in v[@"maps"])if([row[@"name"]isEqual:@"unknown"])foundUnknown=N(row,@"kills")==1;CHECK(foundUnknown);
 [s close];
 // Kill a separate process with an uncommitted event; SQLite recovery must discard it.
 pid_t child=0;NSString*dbPath=[r URLByAppendingPathComponent:@".halopad-career.sqlite3"].path;char*childArgs[]={argv[0],"--uncommitted-writer",(char*)dbPath.fileSystemRepresentation,NULL};CHECK(posix_spawn(&child,argv[0],NULL,NULL,childArgs,environ)==0);int status=0;CHECK(waitpid(child,&status,0)==child);CHECK(WIFSIGNALED(status)&&WTERMSIG(status)==SIGKILL);s=Store(r);CHECK(N(Snap(s,P,after)[@"season"],@"kills")==2);[s close];
 // v1 event-only companion migration, preserving unknown outcomes and tracking date.
 NSURL*m=Root(@"migration");d=DB(m);SQL(d,"CREATE TABLE career_events(profile TEXT,kind INTEGER,seed INTEGER,game INTEGER,crc INTEGER,event INTEGER,local_player INTEGER,streak INTEGER,result INTEGER,mode_id INTEGER,map TEXT,mode TEXT,weapon TEXT,occurred REAL,season TEXT,PRIMARY KEY(profile,kind,seed,game,crc,event)); PRAGMA user_version=1;");NSString*q=[NSString stringWithFormat:@"INSERT INTO career_events VALUES('%@',1,1,1,1,0,0,0,0,2,'map','Slayer','unknown',1700000000,'2023-Q4'),('%@',2,1,1,1,1,0,1,0,2,'map','Slayer','pistol',1700000001,'2023-Q4')",P,P];SQL(d,q.UTF8String);sqlite3_close(d);HPCareerStatsStore*ms=Store(m);v=Snap(ms,P,t);CHECK(N(v[@"lifetime"],@"kills")==1);CHECK(N(v[@"lifetime"],@"matches_played")==1);CHECK([v[@"tracking_active"]boolValue]);[ms close];
 // Reject future schema and symlink DB; do not overwrite either.
 NSURL*f=Root(@"future");d=DB(f);SQL(d,"PRAGMA user_version=99");sqlite3_close(d);CHECK([[HPCareerStatsStore alloc]initWithSaveRootURL:f calendar:Calendar() error:NULL]==nil);
 NSURL*y=Root(@"symlink");CHECK(symlink(legacyPath.fileSystemRepresentation,[[y URLByAppendingPathComponent:@".halopad-career.sqlite3"]fileSystemRepresentation])==0);CHECK([[HPCareerStatsStore alloc]initWithSaveRootURL:y calendar:Calendar() error:NULL]==nil);CHECK([[NSData dataWithContentsOfURL:legacyPath]isEqual:legacy]);
 // Invalid guest bridge input is rejected without touching native memory/container.
 CHECK(xh_host_halopad_career_event_v1(1,261,1,320)==2);CHECK(xh_host_halopad_career_event_v1(1,12,1,319)==2);CHECK(xh_host_halopad_career_event_v1(1,12,1,320)==2);
 for(NSURL*x in @[r,m,f,y])CHECK([NSFileManager.defaultManager removeItemAtURL:x error:NULL]);
 printf("PASS %d checks: dedup, authoritative host/client counters, correction, baseline, outcomes, unknowns, quarter/year, restart, contention, crash recovery, v1 migration, schema/security, no original XP changes\n",checks);
}return 0;}
