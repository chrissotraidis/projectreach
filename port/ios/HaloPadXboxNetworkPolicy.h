/* HaloPad network policy v1: online compatibility updates without a new app.
 *
 * OpenCE joins only hosts of its own network version, although its raises have
 * so far been additive. HaloPad downloads a small signed policy that may widen
 * that rule for this app's fixed engine: announce a newer compatible version, and
 * join hosts in a range that always includes its own. The engine itself never
 * changes. scripts/xbox/network_policy.py makes and signs the policy; the guest
 * and host halves are scripts/xbox/network_bridge.py and port/xbox/xg_network_policy.h.
 *
 * A downloaded policy is cached when its signature verifies and its serial is
 * newer, and is applied when the game next starts. Missing, invalid or older data
 * leaves the cached policy, or upstream's exact rule, in place. */
#import <Foundation/Foundation.h>
#import <Security/Security.h>

static NSString *const HPNetworkPolicyURL =
    @"https://raw.githubusercontent.com/chrissotraidis/projectreach/halopad-network/network-policy.json";
/* development override (HALOPAD_NETWORK_POLICY_URL), still signed, never another host */
static NSString *const HPNetworkPolicyURLPrefix = @"https://raw.githubusercontent.com/chrissotraidis/projectreach/";
/* config/network-policy-public.pem: P-256, X9.63 uncompressed */
static const unsigned char HPNetworkPolicyPublicKey[65] = {
    0x04, 0x50, 0x41, 0x61, 0x92, 0x96, 0x83, 0x11, 0x7f, 0x95, 0x6c, 0x4a, 0x98, 0xb2, 0x9c, 0xae,
    0x25, 0x20, 0x85, 0x3f, 0x78, 0x3c, 0x7b, 0xf5, 0xd6, 0xec, 0x53, 0xd6, 0x92, 0x80, 0x56, 0x91,
    0x5d, 0x64, 0x49, 0x56, 0x18, 0x03, 0x0e, 0x23, 0xe9, 0x43, 0xc5, 0xe5, 0xa5, 0x4d, 0x9d, 0x2f,
    0xfb, 0x0e, 0x20, 0xf6, 0x49, 0x97, 0x12, 0x43, 0xdc, 0xa8, 0xf8, 0xe3, 0x73, 0x65, 0xd4, 0x75, 0xfd };
static const NSUInteger HPNetworkPolicyMaximumSize = 16384;

static NSData *HPNetworkPolicyDefaultKey(void)
{
    return [NSData dataWithBytes:HPNetworkPolicyPublicKey length:sizeof(HPNetworkPolicyPublicKey)];
}

/* a JSON whole number within [minimum, maximum], never a boolean or a fraction */
static NSNumber *HPNetworkPolicyInteger(id value, long long minimum, long long maximum)
{
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() ||
        CFNumberIsFloatType((__bridge CFNumberRef)value)) return nil;
    long long number = [value longLongValue];
    return number >= minimum && number <= maximum ? value : nil;
}

static BOOL HPNetworkPolicySignatureValid(NSData *document, NSData *signature, NSData *publicKey)
{
    NSDictionary *attributes = @{(id)kSecAttrKeyType: (id)kSecAttrKeyTypeECSECPrimeRandom,
                                 (id)kSecAttrKeyClass: (id)kSecAttrKeyClassPublic,
                                 (id)kSecAttrKeySizeInBits: @256};
    SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)publicKey, (__bridge CFDictionaryRef)attributes, NULL);
    if (!key) return NO;
    BOOL valid = SecKeyVerifySignature(key, kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
        (__bridge CFDataRef)document, (__bridge CFDataRef)signature, NULL);
    CFRelease(key);
    return valid;
}

/* one engine's row: minimum <= engine <= announce <= maximum */
static NSDictionary *HPNetworkPolicyRow(id row, long long engine)
{
    if (![row isKindOfClass:NSDictionary.class]) return nil;
    NSNumber *announce = HPNetworkPolicyInteger(row[@"announce"], 1, 65535);
    NSNumber *minimum = HPNetworkPolicyInteger(row[@"minimum"], 1, 65535);
    NSNumber *maximum = HPNetworkPolicyInteger(row[@"maximum"], 1, 65535);
    id follows = row[@"follows"];
    if (!announce || !minimum || !maximum || minimum.longLongValue > engine || engine > announce.longLongValue ||
        announce.longLongValue > maximum.longLongValue) return nil;
    if (follows && (![follows isKindOfClass:NSString.class] || [follows length] > 32 ||
        [follows rangeOfString:@"^[A-Za-z0-9._-]+\\z" options:NSRegularExpressionSearch].location == NSNotFound)) return nil;
    return @{@"engine": @(engine), @"announce": announce, @"minimum": minimum, @"maximum": maximum,
             @"follows": follows ?: @""};
}

/* The verified policy in a downloaded or cached file, or nil:
 * @{serial, row (this engine's, absent for upstream's exact rule)}. */
static NSDictionary *HPNetworkPolicyRead(NSData *file, unsigned int engine, NSData *publicKey)
{
    if (![file isKindOfClass:NSData.class] || file.length > HPNetworkPolicyMaximumSize * 2) return nil;
    NSDictionary *envelope = [NSJSONSerialization JSONObjectWithData:file options:0 error:nil];
    if (![envelope isKindOfClass:NSDictionary.class] || !HPNetworkPolicyInteger(envelope[@"format"], 1, 1) ||
        ![envelope[@"document"] isKindOfClass:NSString.class] || ![envelope[@"signature"] isKindOfClass:NSString.class])
        return nil;
    NSData *document = [[NSData alloc] initWithBase64EncodedString:envelope[@"document"] options:0];
    NSData *signature = [[NSData alloc] initWithBase64EncodedString:envelope[@"signature"] options:0];
    if (!document || document.length > HPNetworkPolicyMaximumSize || signature.length < 8 || signature.length > 80 ||
        !HPNetworkPolicySignatureValid(document, signature, publicKey)) return nil;
    NSDictionary *policy = [NSJSONSerialization JSONObjectWithData:document options:0 error:nil];
    NSNumber *serial = [policy isKindOfClass:NSDictionary.class] ? HPNetworkPolicyInteger(policy[@"serial"], 1, 1LL << 53) : nil;
    NSDictionary *engines = [policy isKindOfClass:NSDictionary.class] ? policy[@"engines"] : nil;
    if (!serial || !HPNetworkPolicyInteger(policy[@"format"], 1, 1) || ![engines isKindOfClass:NSDictionary.class])
        return nil;
    NSDictionary *mine = nil;
    for (id key in engines) {
        /* every row must be well formed: a malformed document is never partly used */
        if (![key isKindOfClass:NSString.class] ||
            [key rangeOfString:@"^[1-9][0-9]{0,4}\\z" options:NSRegularExpressionSearch].location == NSNotFound) return nil;
        NSDictionary *row = HPNetworkPolicyRow(engines[key], [key longLongValue]);
        if (!row) return nil;
        if ([key longLongValue] == engine) mine = row;
    }
    return mine ? @{@"serial": serial, @"row": mine} : @{@"serial": serial};
}

static NSURL *HPNetworkPolicyCacheURL(void)
{
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    return [[support URLByAppendingPathComponent:@"HaloPad" isDirectory:YES] URLByAppendingPathComponent:@"network-policy.json"];
}

static NSDictionary *HPNetworkPolicyCached(unsigned int engine)
{
    return HPNetworkPolicyRead([NSData dataWithContentsOfURL:HPNetworkPolicyCacheURL()], engine, HPNetworkPolicyDefaultKey());
}

/* Keep a verified download only if it is newer than the verified cache. */
static BOOL HPNetworkPolicyStore(NSData *file, unsigned int engine, NSURL *cache, NSData *publicKey)
{
    NSDictionary *fresh = HPNetworkPolicyRead(file, engine, publicKey);
    if (!fresh) return NO;
    NSDictionary *current = HPNetworkPolicyRead([NSData dataWithContentsOfURL:cache], engine, publicKey);
    if (current && [fresh[@"serial"] longLongValue] <= [current[@"serial"] longLongValue]) return NO;
    [NSFileManager.defaultManager createDirectoryAtURL:cache.URLByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:nil];
    return [file writeToURL:cache atomically:YES];
}

static NSURL *HPNetworkPolicySourceURL(void)
{
    const char *override = getenv("HALOPAD_NETWORK_POLICY_URL");
    NSString *text = override && *override ? @(override) : nil;
    if (text && [text hasPrefix:HPNetworkPolicyURLPrefix] && ![text containsString:@".."] &&
        ![text containsString:@"?"] && ![text containsString:@"#"])
        return [NSURL URLWithString:text];
    return [NSURL URLWithString:HPNetworkPolicyURL];
}

/* Background download; done(YES) on the main queue when a newer policy was cached. */
static void HPNetworkPolicyRefresh(unsigned int engine, void (^done)(BOOL updated))
{
    if (!engine) return;
    NSURLRequest *request = [NSURLRequest requestWithURL:HPNetworkPolicySourceURL()
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *body, NSURLResponse *response, NSError *error) {
        BOOL updated = !error && [response isKindOfClass:NSHTTPURLResponse.class] &&
            ((NSHTTPURLResponse *)response).statusCode == 200 && body.length <= HPNetworkPolicyMaximumSize * 2 &&
            HPNetworkPolicyStore(body, engine, HPNetworkPolicyCacheURL(), HPNetworkPolicyDefaultKey());
        if (done) dispatch_async(dispatch_get_main_queue(), ^{ done(updated); });
    }] resume];
}

/* For Updates: what online play currently follows. */
static NSString *HPNetworkPolicySummary(unsigned int engine, NSDictionary *policy)
{
    NSDictionary *row = policy[@"row"];
    if (!engine) return @"Online play: this build reports no network version.";
    if (!row || ([row[@"announce"] unsignedIntValue] == engine && [row[@"minimum"] unsignedIntValue] == engine &&
        [row[@"maximum"] unsignedIntValue] == engine))
        return [NSString stringWithFormat:@"Online play: OpenCE network version %u.", engine];
    return [NSString stringWithFormat:@"Online play: OpenCE network versions %@ to %@ (this engine is version %u).",
        row[@"minimum"], row[@"maximum"], engine];
}
