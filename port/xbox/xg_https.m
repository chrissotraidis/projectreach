/* OpenCE's master-server GET: native TLS, bounded bytes, no redirects.
 * The guest calls this on its browser worker. Only the calling thread touches
 * guest memory; a late completion after a timeout cannot write into it. */
#import <Foundation/Foundation.h>
#include "xg_host.h"
#include <stdio.h>
#include <string.h>

@interface XGHTTPSRequest : NSObject <NSURLSessionDataDelegate>
@property(nonatomic) NSUInteger capacity;
@property(nonatomic, strong) NSMutableData *body;
@property(nonatomic, strong) NSHTTPURLResponse *response;
@property(nonatomic, copy) NSString *failure;
@property(nonatomic, strong) dispatch_semaphore_t done;
@end

@implementation XGHTTPSRequest
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
    didReceiveResponse:(NSURLResponse *)response
    completionHandler:(void (^)(NSURLSessionResponseDisposition))completion
{
    if (![response isKindOfClass:NSHTTPURLResponse.class]) {
        self.failure = @"The server did not return an HTTP response";
    } else if (response.expectedContentLength > (int64_t)self.capacity) {
        self.failure = @"The server response exceeds the guest buffer";
    } else {
        self.response = (NSHTTPURLResponse *)response;
    }
    completion(self.failure ? NSURLSessionResponseCancel : NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data
{
    if (data.length > self.capacity - self.body.length) {
        self.failure = @"The server response exceeds the guest buffer";
        [task cancel];
    } else if (!self.failure) {
        [self.body appendData:data];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSURLRequest *))completion
{
    /* Upstream returns the redirect's status and body, never its destination. */
    completion(nil);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
    if (!self.failure && error) self.failure = error.localizedDescription;
    dispatch_semaphore_signal(self.done);
}
@end

static BOOL xg_https_buffer(uint32_t address, int size)
{
    return size >= 0 && (!size || address) && (uint64_t)address + (unsigned)size <= UINT64_C(0x100000000);
}

static int xg_https_failure(uint32_t error, int size, NSString *message)
{
    if (size > 0 && xg_https_buffer(error, size))
        snprintf(G(char *, error), (size_t)size, "%s", message.UTF8String ?: "HTTPS request failed");
    return 0;
}

int xh_host_https_get(uint32_t url, uint32_t status, uint32_t headers, int headers_size,
    uint32_t body, int body_capacity, uint32_t body_size, uint32_t error, int error_size)
{
    @autoreleasepool {
        BOOL valid_status = status && xg_https_buffer(status, sizeof(int));
        BOOL valid_size = body_size && xg_https_buffer(body_size, sizeof(int));
        if (valid_status) *G(int *, status) = 0;
        if (valid_size) *G(int *, body_size) = 0;
        if (headers_size > 0 && xg_https_buffer(headers, headers_size)) *G(char *, headers) = 0;
        if (error_size > 0 && xg_https_buffer(error, error_size)) *G(char *, error) = 0;
        if (!url || !valid_status || !valid_size || headers_size <= 0 ||
            !xg_https_buffer(headers, headers_size) || !xg_https_buffer(body, body_capacity) ||
            !xg_https_buffer(error, error_size))
            return xg_https_failure(error, error_size, @"Invalid HTTPS guest buffers");

        size_t limit = (size_t)MIN(UINT64_C(2048), UINT64_C(0x100000000) - url);
        const char *text = G(const char *, url);
        size_t length = strnlen(text, limit);
        NSString *address = length < limit ? [[NSString alloc] initWithBytes:text length:length
            encoding:NSUTF8StringEncoding] : nil;
        NSURLComponents *parts = address ? [NSURLComponents componentsWithString:address] : nil;
        NSString *scheme = parts.scheme.lowercaseString, *host = parts.host.lowercaseString;
        BOOL secure = [scheme isEqualToString:@"https"];
        BOOL loopback = [scheme isEqualToString:@"http"] &&
            ([host isEqualToString:@"127.0.0.1"] || [host isEqualToString:@"localhost"]);
        if ((!secure && !loopback) || !host.length || parts.user || parts.password || parts.fragment || !parts.URL)
            return xg_https_failure(error, error_size, @"Expected HTTPS, or HTTP on localhost");

        XGHTTPSRequest *answer = [XGHTTPSRequest new];
        answer.capacity = (NSUInteger)body_capacity;
        answer.body = [NSMutableData data];
        answer.done = dispatch_semaphore_create(0);
        NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.URLCache = nil;
        config.HTTPCookieStorage = nil;
        config.URLCredentialStorage = nil;
        config.HTTPShouldSetCookies = NO;
        config.timeoutIntervalForRequest = 15;
        config.timeoutIntervalForResource = 20;
        /* No authentication-challenge override: Foundation verifies the server's
         * certificate and hostname using the system trust store. */
        NSURLSession *session = [NSURLSession sessionWithConfiguration:config delegate:answer delegateQueue:nil];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:parts.URL
            cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:15];
        [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        [request setValue:@"opence" forHTTPHeaderField:@"User-Agent"];
        [[session dataTaskWithRequest:request] resume];
        if (dispatch_semaphore_wait(answer.done, dispatch_time(DISPATCH_TIME_NOW, 25 * NSEC_PER_SEC))) {
            [session invalidateAndCancel];
            return xg_https_failure(error, error_size, @"HTTPS request timed out");
        }
        [session finishTasksAndInvalidate];
        if (answer.failure || !answer.response)
            return xg_https_failure(error, error_size, answer.failure ?: @"No HTTP response");

        NSMutableString *lines = [NSMutableString string];
        for (id key in answer.response.allHeaderFields)
            [lines appendFormat:@"%@: %@\n", key, answer.response.allHeaderFields[key]];
        NSData *encoded = [lines dataUsingEncoding:NSUTF8StringEncoding];
        if (encoded.length >= (NSUInteger)headers_size)
            return xg_https_failure(error, error_size, @"The response headers exceed the guest buffer");
        memcpy(G(char *, headers), encoded.bytes, encoded.length);
        G(char *, headers)[encoded.length] = 0;
        if (answer.body.length) memcpy(G(char *, body), answer.body.bytes, answer.body.length);
        *G(int *, status) = (int)answer.response.statusCode;
        *G(int *, body_size) = (int)answer.body.length;
        return 1;
    }
}
