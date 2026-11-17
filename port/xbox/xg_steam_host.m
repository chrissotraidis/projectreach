/*
 * xg_steam_host.m: what upstream's Steam Workshop host code (port/android/host/
 * steam_*.c, compiled for HaloPad by scripts/xbox/build-ios.sh) asks of its
 * host, done the Apple way:
 *
 *   host_logf              into HaloPad's log (xg_log)
 *   xg_mcc_share_publish   a finished download moved into mcc_maps (below)
 *   update_https_request   upstream's HTTPS client (port/linux/src/update.h):
 *                          NSURLSession with the system's certificate checks,
 *                          no redirect followed, the body bounded
 *   steam_seal_*           where the Steam sign-in is kept (steam_seal.h):
 *                          the refresh token in this device's Keychain
 *                          (this device only, after first unlock); the
 *                          session file holds only a reference to it
 */
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "xg_host.h"
#include "update.h"
#include "steam_seal.h"

/* ---------- host.h's log */

void host_logf(int priority, const char *format, ...)
{
	char line[1024];
	va_list arguments;
	(void)priority;
	va_start(arguments, format);
	vsnprintf(line, sizeof(line), format, arguments);
	va_end(arguments);
	xg_log("%s", line);
}

/* platform.h's log, which upstream's desktop code (workshop_authors.c) uses */
void platform_log(const char *format, ...)
{
	char line[1024];
	va_list arguments;
	va_start(arguments, format);
	vsnprintf(line, sizeof(line), format, arguments);
	va_end(arguments);
	xg_log("%s", line);
}

/* ---------- moving a finished download into mcc_maps
 *
 * Upstream's posix_mcc_share_publish moves a folder into place only with
 * Linux's renameat2(RENAME_NOREPLACE), and refuses elsewhere (ENOTSUP), so
 * every Workshop download failed at its last step. gen-host-steam.py points
 * steam_downloads.c's one call here: the same path checks, then Darwin's
 * RENAME_EXCL, which likewise never replaces what is there (xg_posix.c does
 * the same for the game's own calls). */

int posix_mcc_share_path_safe(const char *path);

int xg_mcc_share_publish(const char *from, const char *to)
{
	if (!posix_mcc_share_path_safe(from) || !posix_mcc_share_path_safe(to))
		return 0;
	if (renamex_np(from, to, RENAME_EXCL) == 0)
		return 1;
	host_logf(5, "steam: could not move %s to %s: %s", from, to, strerror(errno));
	return 0;
}

/* ---------- update.h's HTTPS request */

@interface XGSteamHTTPS : NSObject <NSURLSessionTaskDelegate>
@end

@implementation XGSteamHTTPS
/* "no redirect followed": the redirect's own answer is the answer */
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
	willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
	completionHandler:(void (^)(NSURLRequest *))completionHandler
{
	(void)session; (void)task; (void)response; (void)request;
	completionHandler(nil);
}
@end

static int https_failure(char *error, int error_size, NSString *message)
{
	if (error && error_size > 0)
		snprintf(error, (size_t)error_size, "%s", message.UTF8String ?: "HTTPS request failed");
	return 0;
}

static int local_http(NSURL *url)
{
	NSString *host = url.host.lowercaseString;
	return [url.scheme.lowercaseString isEqualToString:@"http"] &&
		([host isEqualToString:@"127.0.0.1"] || [host isEqualToString:@"localhost"]);
}

int update_https_request(const char *method, const char *url, const char *headers, const void *body,
	unsigned long body_size, unsigned long maximum, struct update_response *response, char *error, int error_size)
{
	@autoreleasepool {
		NSURL *address = url ? [NSURL URLWithString:@(url)] : nil;
		NSMutableURLRequest *request;
		NSURLSessionConfiguration *configuration;
		NSURLSession *session;
		dispatch_semaphore_t done = dispatch_semaphore_create(0);
		__block NSData *answer = nil;
		__block NSHTTPURLResponse *reply = nil;
		__block NSError *failure = nil;
		NSMutableString *received = [NSMutableString string];

		memset(response, 0, sizeof(*response));
		if (!address || !method)
			return https_failure(error, error_size, @"not a URL");
		if (![address.scheme.lowercaseString isEqualToString:@"https"] && !local_http(address))
			return https_failure(error, error_size, @"only https:// is fetched");
		request = [NSMutableURLRequest requestWithURL:address];
		request.HTTPMethod = @(method);
		request.timeoutInterval = 30;
		if (body && body_size)
			request.HTTPBody = [NSData dataWithBytes:body length:body_size];
		/* extra header lines, each "Name: value\r\n" */
		for (NSString *line in [@(headers ?: "") componentsSeparatedByString:@"\r\n"]) {
			NSRange colon = [line rangeOfString:@":"];
			if (!line.length || colon.location == NSNotFound)
				continue;
			[request setValue:[[line substringFromIndex:colon.location + 1]
					stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]
				forHTTPHeaderField:[line substringToIndex:colon.location]];
		}
		configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
		configuration.URLCache = nil;
		configuration.HTTPCookieStorage = nil;
		session = [NSURLSession sessionWithConfiguration:configuration delegate:[XGSteamHTTPS new] delegateQueue:nil];
		[[session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *urlResponse, NSError *taskError) {
			answer = data;
			reply = [urlResponse isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)urlResponse : nil;
			failure = taskError;
			dispatch_semaphore_signal(done);
		}] resume];
		dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
		[session finishTasksAndInvalidate];
		if (!reply)
			return https_failure(error, error_size, failure.localizedDescription ?: @"no answer");
		if (answer.length > maximum)
			return https_failure(error, error_size, @"the answer is larger than allowed");
		response->status = (int)reply.statusCode;
		[reply.allHeaderFields enumerateKeysAndObjectsUsingBlock:^(id name, id value, BOOL *stop) {
			(void)stop;
			[received appendFormat:@"%@: %@\n", name, value];
		}];
		snprintf(response->headers, sizeof(response->headers), "%s", received.UTF8String ?: "");
		response->body = malloc(answer.length + 1);
		if (!response->body)
			return https_failure(error, error_size, @"out of memory");
		if (answer.length)
			memcpy(response->body, answer.bytes, answer.length);
		response->body[answer.length] = 0;
		response->body_size = answer.length;
		return 1;
	}
}

/* ---------- steam_seal.h: the sign-in in this device's Keychain */

static NSString *const seal_service = @"dev.halopad.steam-signin";
static char const seal_scheme[] = "keychain:";

static NSDictionary *seal_query(NSString *account)
{
	NSMutableDictionary *query = [@{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
		(__bridge id)kSecAttrService: seal_service } mutableCopy];
	if (account)
		query[(__bridge id)kSecAttrAccount] = account;
	return query;
}

void steam_seal_folder(char const *root, char *folder, size_t size)
{
	snprintf(folder, size, "%s/steam", root);
	mkdir(folder, 0700);
}

/* One sign-in is kept: sealing a new token replaces the old one. */
int steam_seal(char const *text, char *out, size_t out_size)
{
	@autoreleasepool {
		unsigned char identity[16];
		char hex[sizeof(identity) * 2 + 1];
		NSMutableDictionary *item;
		size_t i;

		if (out_size)
			out[0] = 0;
		if (SecRandomCopyBytes(kSecRandomDefault, sizeof(identity), identity) != errSecSuccess)
			return 0;
		for (i = 0; i < sizeof(identity); i++)
			snprintf(hex + 2 * i, 3, "%02x", identity[i]);
		if (sizeof(seal_scheme) - 1 + strlen(hex) + 1 > out_size)
			return 0;
		SecItemDelete((__bridge CFDictionaryRef)seal_query(nil));
		item = [seal_query(@(hex)) mutableCopy];
		item[(__bridge id)kSecValueData] = [NSData dataWithBytes:text length:strlen(text)];
		item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
		if (SecItemAdd((__bridge CFDictionaryRef)item, NULL) != errSecSuccess) {
			host_logf(5, "steam: the sign-in could not be kept in the Keychain; it lasts until the app closes");
			return 0;
		}
		snprintf(out, out_size, "%s%s", seal_scheme, hex);
		return 1;
	}
}

int steam_unseal(char const *sealed, char *out, size_t out_size)
{
	@autoreleasepool {
		NSMutableDictionary *query;
		CFTypeRef found = NULL;
		NSData *data;

		if (out_size)
			out[0] = 0;
		if (strncmp(sealed, seal_scheme, sizeof(seal_scheme) - 1))
			return 0;
		query = [seal_query(@(sealed + sizeof(seal_scheme) - 1)) mutableCopy];
		query[(__bridge id)kSecReturnData] = @YES;
		query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
		if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &found) != errSecSuccess || !found)
			return 0;
		data = CFBridgingRelease(found);
		if (data.length + 1 > out_size)
			return 0;
		memcpy(out, data.bytes, data.length);
		out[data.length] = 0;
		return 1;
	}
}

void steam_seal_forget(void)
{
	@autoreleasepool {
		SecItemDelete((__bridge CFDictionaryRef)seal_query(nil));
	}
}

FILE *steam_seal_create(char const *path)
{
	int descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
	FILE *file;

	if (descriptor < 0)
		return NULL;
	file = fdopen(descriptor, "w");
	if (!file)
		close(descriptor);
	return file;
}
