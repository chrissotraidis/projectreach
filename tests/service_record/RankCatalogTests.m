/* An independently generated catalog only; no rank PNG pack is required. */
#import "HPHaloServiceRecordRanks.h"
#include <limits.h>
static unsigned checks;
#define CHECK(c) do { checks++; if (!(c)) { fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#c); return 1; } } while (0)
int main(void) { @autoreleasepool {
    NSArray *tiers=HPHaloServiceRecordRankCatalog();
    CHECK(tiers.count==6);
    CHECK([tiers.firstObject[@"minXP"]longLongValue]==0);
    CHECK([tiers.lastObject[@"minXP"]longLongValue]==2500);
    for(NSUInteger index=0;index<tiers.count;index++) {
        NSDictionary *tier=tiers[index];
        CHECK([tier[@"order"]unsignedIntegerValue]==index+1);
        CHECK(([tier[@"file"]isEqual:[NSString stringWithFormat:@"local-%lu.png",(unsigned long)index+1]]));
    }
    NSArray *input=@[@{@"name":@"First",@"minXP":@0,@"file":@"../../unexpected.png"},
                     @{@"name":@"Second",@"minXP":@(LLONG_MAX)}];
    NSArray *valid=HPHaloServiceRecordValidateRankCatalog(input);
    CHECK(valid.count==2&&[valid[1][@"minXP"]longLongValue]==LLONG_MAX);
    CHECK([valid[0][@"file"]isEqual:@"local-1.png"]);
    CHECK([input[0][@"file"]isEqual:@"../../unexpected.png"]);
    for(id invalid in @[
        NSNull.null,@{},@[],@[@{@"name":@"First",@"minXP":@1}],
        @[@{@"name":@"",@"minXP":@0}],@[@{@"name":@" \n ",@"minXP":@0}],
        @[@{@"name":@"Control\x01",@"minXP":@0}],
        @[@{@"name":@"First",@"minXP":@YES}],
        @[@{@"name":@"First",@"minXP":@0},@{@"name":@"Duplicate",@"minXP":@0}],
        @[@{@"name":@"First",@"minXP":@0},@{@"name":@"Negative",@"minXP":@(-1)}],
        @[@{@"name":@"First",@"minXP":@0},@{@"name":@"Fraction",@"minXP":@1.5}],
        @[@{@"name":@"First",@"minXP":@0},@{@"name":@"Overflow",@"minXP":@18446744073709551615ULL}],
        @[@{@"name":@"First",@"minXP":@0},@{@"name":@"NaN",@"minXP":NSDecimalNumber.notANumber}],
        @[@{@"name":@"First",@"minXP":@0},@{@"name":@"String",@"minXP":@"10"}],
        @[@{@"name":@"First",@"minXP":@0},@{@"name":@3,@"minXP":@10}]
    ]) CHECK(HPHaloServiceRecordValidateRankCatalog(invalid)==nil);
    NSMutableArray *maximum=[NSMutableArray array];
    for(unsigned index=0;index<64;index++)[maximum addObject:@{@"name":@"Synthetic tier",@"minXP":@(index)}];
    CHECK(HPHaloServiceRecordValidateRankCatalog(maximum).count==64);
    [maximum addObject:@{@"name":@"Too many",@"minXP":@64}];
    CHECK(HPHaloServiceRecordValidateRankCatalog(maximum)==nil);
    printf("PASS %u rank catalog checks: generated identities, exact int64 bounds, malformed/duplicate/fractional policies, size limit and source immutability\n",checks);
} return 0; }
