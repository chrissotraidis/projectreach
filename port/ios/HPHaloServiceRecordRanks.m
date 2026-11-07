#import "HPHaloServiceRecordRanks.h"

NSArray<NSDictionary *> *HPHaloServiceRecordValidateRankCatalog(id input)
{
    if (![input isKindOfClass:NSArray.class] || [input count] == 0 || [input count] > 64) return nil;
    NSMutableArray *tiers = [NSMutableArray array];
    long long previous = -1;
    for (id item in input) {
        if (![item isKindOfClass:NSDictionary.class]) return nil;
        NSString *name = item[@"name"];
        NSNumber *value = item[@"minXP"];
        if (![name isKindOfClass:NSString.class] || [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0 || name.length > 80 ||
            [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound ||
            ![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return nil;
        /* Decimal comparison avoids rounding the upper int64 boundary to 2^63. */
        NSDecimalNumber *number = [NSDecimalNumber decimalNumberWithString:value.stringValue locale:@{@"NSLocaleIdentifier":@"en_US_POSIX"}];
        if ([number isEqualToNumber:NSDecimalNumber.notANumber] ||
            [number compare:NSDecimalNumber.zero] == NSOrderedAscending ||
            [number compare:[NSDecimalNumber decimalNumberWithString:@"9223372036854775807"]] == NSOrderedDescending) return nil;
        long long minimum = number.longLongValue;
        if ([number compare:[NSDecimalNumber decimalNumberWithMantissa:(unsigned long long)minimum exponent:0 isNegative:NO]] != NSOrderedSame ||
            minimum <= previous || (tiers.count == 0 && minimum != 0)) return nil;
        NSUInteger order = tiers.count + 1;
        [tiers addObject:@{ @"name":name, @"minXP":@(minimum), @"order":@(order),
            @"rankId":[NSString stringWithFormat:@"local-%lu",(unsigned long)order],
            @"file":[NSString stringWithFormat:@"local-%lu.png",(unsigned long)order] }];
        previous = minimum;
    }
    return [tiers copy];
}

NSArray<NSDictionary *> *HPHaloServiceRecordRankCatalog(void)
{
    static NSArray *tiers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *url = [NSBundle.mainBundle URLForResource:@"HaloPadServiceRecordRanks" withExtension:@"json"];
        NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
        id catalog = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if ([catalog isKindOfClass:NSDictionary.class]) tiers = HPHaloServiceRecordValidateRankCatalog(catalog[@"tiers"]);
        if (!tiers) tiers = HPHaloServiceRecordValidateRankCatalog(@[
            @{ @"name":@"Level 1", @"minXP":@0 }, @{ @"name":@"Level 2", @"minXP":@100 },
            @{ @"name":@"Level 3", @"minXP":@250 }, @{ @"name":@"Level 4", @"minXP":@500 },
            @{ @"name":@"Level 5", @"minXP":@1000 }, @{ @"name":@"Level 6", @"minXP":@2500 }]);
    });
    return tiers;
}
