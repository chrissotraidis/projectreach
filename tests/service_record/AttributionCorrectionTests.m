/* Synthetic regression for authoritative correction of attributed counters. */
#import "HPCareerStatsStore.h"
#import <sqlite3.h>
uintptr_t xg_base;
static unsigned checks;
#define CHECK(c) do { checks++; if (!(c)) { fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#c); exit(1); } } while(0)
int main(void) { @autoreleasepool {
    NSString *root=[@(getenv("HALOPAD_TEST_RESULTS"))stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    CHECK([NSFileManager.defaultManager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSString *profile=@"12345678-1234-1234-1234-123456789ABC";
    NSURL *url=[NSURL fileURLWithPath:root isDirectory:YES];
    NSError *error=nil;HPCareerStatsStore *store=[[HPCareerStatsStore alloc]initWithSaveRootURL:url calendar:nil error:&error];
    CHECK(store!=nil&&error==nil);
    HPCareerStatsEventV1 event={0};event.version=1;event.size=sizeof event;event.kind=HPCareerMatchEnter;
    event.session_seed=1;event.game_number=1;event.map_crc=1;event.mode_id=2;
    strcpy(event.map,"synthetic_map");strcpy(event.mode,"Slayer");strcpy(event.weapon,"synthetic_weapon");
    NSDate *date=[NSDate dateWithTimeIntervalSince1970:1793728800];
    CHECK([store recordEvent:&event profileID:profile date:date error:&error]==1);
    for(unsigned kill=1;kill<=2;kill++) {
        event.kind=HPCareerKill;event.event_id=kill;event.kills=kill;event.streak=kill;
        CHECK([store recordEvent:&event profileID:profile date:date error:&error]==1);
    }
    NSDictionary *before=[store snapshotForProfileID:profile date:date error:&error];
    CHECK([before[@"lifetime"][@"kills"]integerValue]==2);
    CHECK([before[@"weapons"][0][@"name"]isEqual:@"synthetic_weapon"]&&[before[@"weapons"][0][@"kills"]integerValue]==2);
    event.kind=HPCareerAuthoritativeTotals;event.event_id=100;event.kills=1;
    CHECK([store recordEvent:&event profileID:profile date:date error:&error]==1);
    NSDictionary *after=[store snapshotForProfileID:profile date:date error:&error];
    CHECK([after[@"lifetime"][@"kills"]integerValue]==1);
    for(NSString *key in @[@"weapons",@"season_weapons"]) {
        NSArray *rows=after[key];CHECK(rows.count==1);
        CHECK([rows[0][@"name"]isEqual:@"unknown"]&&[rows[0][@"kills"]integerValue]==1);
        CHECK([rows[0][@"attribution_note"]isKindOfClass:NSString.class]&&[rows[0][@"attribution_note"]length]>0);
    }
    [store close];
    sqlite3 *database=NULL;CHECK(sqlite3_open([url URLByAppendingPathComponent:@".halopad-career.sqlite3"].fileSystemRepresentation,&database)==SQLITE_OK);
    sqlite3_stmt *query=NULL;CHECK(sqlite3_prepare_v2(database,"SELECT COUNT(*) FROM career_events WHERE kind=2",-1,&query,NULL)==SQLITE_OK);
    CHECK(sqlite3_step(query)==SQLITE_ROW&&sqlite3_column_int(query,0)==2);
    sqlite3_finalize(query);sqlite3_close(database);
    CHECK([NSFileManager.defaultManager removeItemAtURL:url error:NULL]);
    printf("PASS %u attribution checks: authoritative correction bounds displayed breakdowns and retains original events\n",checks);
} return 0; }
