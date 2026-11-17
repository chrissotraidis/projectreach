/*
 * xg_admin.m: the app's web page on the local network. A player opens it from
 * a computer or phone and chooses their Halo Xbox disc image. The page itself
 * reads the disc (admin.html) and uploads only maps/, one file at a time; the
 * disc image never leaves the player's device.
 *
 *   GET  /                          the page (admin.html in the app bundle)
 *   GET  /api/status                JSON: installed maps, free space, progress
 *   POST /api/import/begin?total=N  start an import of N bytes of maps: {"id"}
 *   PUT  /api/import/map?id=&name=  one map as the request body (Content-Length)
 *   POST /api/import/finish?id=     check every map, then install them
 *   POST /api/import/cancel?id=     drop the import
 *
 * Steam sign-in, when the engine has upstream's Steam host (XG_ADMIN_STEAM):
 * the /api/steam routes below the pairing section.
 *
 * Pairing: every /api/ request but the pairing ones carries a token
 * (X-Homecoming-Token) that a browser gets by typing a six-digit code the TV
 * shows (POST /api/pair/request, then POST /api/pair). Five wrong codes end
 * the code; a code lasts two minutes. Only a digest of each token is kept.
 *
 * Maps arrive in a staging folder. Finishing checks each one the way
 * xg_xiso.c does (header, footer, one common build, ui.map present) and then
 * swaps the folder in for data_root/maps with one rename, so a failed or
 * interrupted import leaves the installed maps as they were.
 *
 * Plain HTTP/1.1, one request per connection, a thread per connection (at
 * most four). Only addresses on the local network are answered.
 */
#import <Foundation/Foundation.h>
#include "xg_admin.h"
#include "xg_host.h"
#include <CommonCrypto/CommonDigest.h>
#include "third_party/tweetnacl/tweetnacl.h"
#include <arpa/inet.h>
#include <dns_sd.h>
#include <errno.h>
#include <fcntl.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define MAX_HEADER 16384
#define MAX_MAP_SIZE (512ull << 20)       /* the limits xg_xiso.c applies */
#define MAX_MAP_TOTAL (3ull << 30)
#define MAX_MAPS 256
#define SPARE_ROOM (256ull << 20)

enum import_state { IMPORT_IDLE, IMPORT_RECEIVING, IMPORT_DONE, IMPORT_FAILED };
static char const *const state_names[] = { "idle", "receiving", "done", "failed" };

static NSString *data_root, *work_root;
static void (^ready_handler)(void);
static int listen_port;
static dispatch_semaphore_t connection_slots;
static DNSServiceRef bonjour;
static atomic_int game_running;
static atomic_int listening_socket = -1, reopen_wanted;

static pthread_mutex_t import_lock = PTHREAD_MUTEX_INITIALIZER;
static struct {
	enum import_state state;
	unsigned long long received, expected;
	char id[33], current[64], message[256], build[33];
} import;

/* ---------- small helpers */

static int send_all(int socket, const void *data, size_t size)
{
	const char *bytes = data;
	while (size) {
		ssize_t sent = send(socket, bytes, size, 0);
		if (sent < 0 && errno == EINTR)
			continue;
		if (sent <= 0)
			return 0;
		bytes += sent;
		size -= (size_t)sent;
	}
	return 1;
}

static void respond(int socket, int status, const char *reason, NSString *type, NSData *body)
{
	NSString *head = [NSString stringWithFormat:@"HTTP/1.1 %d %s\r\nContent-Type: %@\r\nContent-Length: %lu\r\n"
		"Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n",
		status, reason, type, (unsigned long)body.length];
	NSData *headData = [head dataUsingEncoding:NSUTF8StringEncoding];
	if (send_all(socket, headData.bytes, headData.length) && body.length)
		send_all(socket, body.bytes, body.length);
}

static void respond_json(int socket, int status, const char *reason, NSDictionary *object)
{
	respond(socket, status, reason, @"application/json", [NSJSONSerialization dataWithJSONObject:object options:0 error:nil]);
}

static void respond_error(int socket, int status, const char *reason, NSString *message)
{
	respond_json(socket, status, reason, @{ @"error": message });
}

/* the private, link-local and loopback IPv4 ranges */
static int local_address(const struct sockaddr_in *address)
{
	uint32_t a = ntohl(address->sin_addr.s_addr);
	return (a >> 24) == 10 || (a >> 24) == 127 || (a >> 20) == (172u << 4 | 1) ||
		(a >> 16) == (192u << 8 | 168) || (a >> 16) == (169u << 8 | 254);
}

static unsigned long long free_bytes(NSString *path)
{
	struct statfs info;
	if (statfs(path.fileSystemRepresentation, &info))
		return 0;
	return (unsigned long long)info.f_bavail * info.f_bsize;
}

static void set_state(enum import_state state, NSString *message)
{
	pthread_mutex_lock(&import_lock);
	import.state = state;
	snprintf(import.message, sizeof(import.message), "%s", message ? message.UTF8String : "");
	pthread_mutex_unlock(&import_lock);
	if (message)
		xg_log("admin: %s", message.UTF8String);
}

/* ---------- what is installed */

int xg_admin_maps_present(NSString *root)
{
	struct stat info;
	return !stat([root stringByAppendingPathComponent:@"maps/ui.map"].fileSystemRepresentation, &info) &&
		S_ISREG(info.st_mode);
}

/* the build string in a map's header (as xg_xiso.c checks it) */
static NSString *map_build(NSString *path)
{
	char header[0x60] = {0};
	FILE *file = fopen(path.fileSystemRepresentation, "rb");
	size_t got = file ? fread(header, 1, sizeof(header), file) : 0;
	if (file)
		fclose(file);
	if (got < sizeof(header) || memcmp(header, "daeh", 4))
		return nil;
	header[0x40 + 31] = 0;
	return @(header + 0x40);
}

static NSDictionary *installed_maps(void)
{
	NSString *folder = [data_root stringByAppendingPathComponent:@"maps"];
	NSMutableArray *names = [NSMutableArray array];
	unsigned long long bytes = 0;
	for (NSString *name in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]
			sortedArrayUsingSelector:@selector(compare:)]) {
		NSDictionary *attributes;
		if (![name.pathExtension.lowercaseString isEqualToString:@"map"])
			continue;
		attributes = [NSFileManager.defaultManager attributesOfItemAtPath:[folder stringByAppendingPathComponent:name] error:nil];
		bytes += attributes.fileSize;
		[names addObject:name.stringByDeletingPathExtension];
	}
	return @{ @"present": @(xg_admin_maps_present(data_root) != 0), @"maps": names, @"bytes": @(bytes),
		@"build": map_build([folder stringByAppendingPathComponent:@"ui.map"]) ?: [NSNull null] };
}

static NSDictionary *status_object(void)
{
	NSDictionary *importing;
	pthread_mutex_lock(&import_lock);
	importing = @{ @"state": @(state_names[import.state]), @"received": @(import.received), @"expected": @(import.expected),
		@"current": @(import.current), @"message": @(import.message), @"build": @(import.build) };
	pthread_mutex_unlock(&import_lock);
	return @{ @"installed": installed_maps(), @"import": importing, @"free": @(free_bytes(work_root)),
		@"game_running": @(atomic_load(&game_running) != 0) };
}

/* ---------- the import */

static NSString *stage_path(void) { return [work_root stringByAppendingPathComponent:@"import/stage"]; }

/* the value of name in a query string ("a=1&b=2"); letters, digits, . _ - only */
static int query_value(const char *query, const char *name, char *out, size_t size)
{
	size_t length = strlen(name);
	while (query && *query) {
		if (!strncmp(query, name, length) && query[length] == '=') {
			size_t n = 0;
			query += length + 1;
			while (query[n] && query[n] != '&') {
				char c = query[n];
				if (n + 1 >= size || !((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
					c == '.' || c == '_' || c == '-'))
					return 0;
				out[n] = c;
				n++;
			}
			out[n] = 0;
			return n > 0;
		}
		query = strchr(query, '&');
		if (query)
			query++;
	}
	return 0;
}

/* a map file name as the disc spells it, lower-cased: [a-z0-9._-]+\.map */
static int map_name(char *name)
{
	size_t length = strlen(name);
	if (length < 5 || length > 60 || name[0] == '.')
		return 0;
	for (size_t i = 0; i < length; i++)
		if (name[i] >= 'A' && name[i] <= 'Z')
			name[i] = (char)(name[i] + ('a' - 'A'));
	return !strcmp(name + length - 4, ".map");
}

/* the import with this id is the current one; called with import_lock held */
static int current_import(const char *query)
{
	char id[33];
	return query_value(query, "id", id, sizeof(id)) && import.state == IMPORT_RECEIVING && !strcmp(id, import.id);
}

/* POST /api/import/begin?total=N: a new import replaces an unfinished one */
static void import_begin(int socket, const char *query)
{
	char total_text[24];
	unsigned long long total, room;
	unsigned char random[16];
	char id[33];
	NSString *stage = stage_path();

	if (!query_value(query, "total", total_text, sizeof(total_text)) || !(total = strtoull(total_text, NULL, 10)) ||
		total > MAX_MAP_TOTAL) {
		respond_error(socket, 400, "Bad Request", @"The maps' total size is missing or too large.");
		return;
	}
	arc4random_buf(random, sizeof(random));
	for (int i = 0; i < 16; i++)
		snprintf(id + 2 * i, 3, "%02x", random[i]);
	pthread_mutex_lock(&import_lock);
	[NSFileManager.defaultManager removeItemAtPath:stage error:nil];
	[NSFileManager.defaultManager createDirectoryAtPath:stage withIntermediateDirectories:YES attributes:nil error:nil];
	room = free_bytes(work_root);
	if (room < total + SPARE_ROOM) {
		NSString *message = [NSString stringWithFormat:@"Not enough space on the Apple TV: %.1f GB needed, %.1f GB free.",
			(total + SPARE_ROOM) / 1e9, room / 1e9];
		import.state = IMPORT_FAILED;
		snprintf(import.message, sizeof(import.message), "%s", message.UTF8String);
		pthread_mutex_unlock(&import_lock);
		respond_error(socket, 507, "Insufficient Storage", message);
		return;
	}
	import.state = IMPORT_RECEIVING;
	import.received = 0;
	import.expected = total;
	import.current[0] = import.build[0] = 0;
	snprintf(import.id, sizeof(import.id), "%s", id);
	snprintf(import.message, sizeof(import.message), "Receiving the maps.");
	pthread_mutex_unlock(&import_lock);
	xg_log("admin: import of %llu bytes of maps begins", total);
	respond_json(socket, 200, "OK", @{ @"id": @(id) });
}

/* PUT /api/import/map?id=&name=: body_start holds body bytes that came with the headers */
static void import_map(int socket, const char *query, unsigned long long length, const char *body_start, size_t body_size)
{
	char name[64];
	static char buffer[1 << 20];
	unsigned long long received = 0;
	NSString *path;
	struct stat info;
	int file;

	if (!query_value(query, "name", name, sizeof(name)) || !map_name(name)) {
		respond_error(socket, 400, "Bad Request", @"Not a map file name.");
		return;
	}
	if (!length || length > MAX_MAP_SIZE) {
		respond_error(socket, 411, "Length Required", @"Send the map as the request body, with its length.");
		return;
	}
	pthread_mutex_lock(&import_lock);
	if (!current_import(query)) {
		pthread_mutex_unlock(&import_lock);
		respond_error(socket, 409, "Conflict", @"This import is no longer the current one.");
		return;
	}
	path = [stage_path() stringByAppendingPathComponent:@(name)];
	if (!stat(path.fileSystemRepresentation, &info))       /* a retried map */
		import.received -= (unsigned long long)info.st_size < import.received ? (unsigned long long)info.st_size : import.received;
	snprintf(import.current, sizeof(import.current), "%s", name);
	pthread_mutex_unlock(&import_lock);

	file = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0600);
	if (file < 0) {
		respond_error(socket, 500, "Internal Server Error", @"The map could not be stored.");
		return;
	}
	if (body_size > length)
		body_size = (size_t)length;
	if (body_size && write(file, body_start, body_size) != (ssize_t)body_size)
		goto failed;
	received = body_size;
	pthread_mutex_lock(&import_lock);
	import.received += received;
	pthread_mutex_unlock(&import_lock);
	while (received < length) {
		size_t want = length - received < sizeof(buffer) ? (size_t)(length - received) : sizeof(buffer);
		ssize_t got = recv(socket, buffer, want, 0);
		if (got < 0 && errno == EINTR)
			continue;
		if (got <= 0 || write(file, buffer, (size_t)got) != got)
			goto failed;
		received += (unsigned long long)got;
		pthread_mutex_lock(&import_lock);
		import.received += (unsigned long long)got;
		pthread_mutex_unlock(&import_lock);
	}
	if (close(file)) {
		file = -1;
		goto failed;
	}
	respond_json(socket, 200, "OK", @{ @"name": @(name), @"received": @(received) });
	return;
failed:
	if (file >= 0)
		close(file);
	unlink(path.fileSystemRepresentation);
	pthread_mutex_lock(&import_lock);
	import.received -= received < import.received ? received : import.received;
	pthread_mutex_unlock(&import_lock);
	respond_error(socket, 400, "Bad Request", [NSString stringWithFormat:@"%s did not arrive whole.", name]);
}

/* A map as xg_xiso.c accepts it: "daeh", version 5, "toof" at 0x7fc and a
 * build string at 0x40. Returns 1 and fills build. */
static int check_map(NSString *path, unsigned long long size, char build[33])
{
	unsigned char header[0x800];
	FILE *file;
	size_t got;
	if (size < sizeof(header) || size > MAX_MAP_SIZE || !(file = fopen(path.fileSystemRepresentation, "rb")))
		return 0;
	got = fread(header, 1, sizeof(header), file);
	fclose(file);
	if (got != sizeof(header) || memcmp(header, "daeh", 4) || memcmp(header + 4, "\5\0\0\0", 4) ||
		memcmp(header + 0x7fc, "toof", 4) || !header[0x40] || !memchr(header + 0x40, 0, 32))
		return 0;
	memcpy(build, header + 0x40, 32);
	build[32] = 0;
	return 1;
}

static void import_failed(int socket, NSString *message)
{
	[NSFileManager.defaultManager removeItemAtPath:stage_path() error:nil];
	set_state(IMPORT_FAILED, message);
	respond_error(socket, 422, "Unprocessable Entity", message);
}

/* POST /api/import/finish?id=: check, then swap the staging folder in */
static void import_finish(int socket, const char *query)
{
	NSFileManager *files = NSFileManager.defaultManager;
	NSString *stage = stage_path(), *installed = [data_root stringByAppendingPathComponent:@"maps"];
	NSArray *names;
	char build[33] = {0}, common[33] = {0};
	unsigned long long total = 0;
	int had_maps = xg_admin_maps_present(data_root), has_ui = 0;

	pthread_mutex_lock(&import_lock);
	if (!current_import(query)) {
		pthread_mutex_unlock(&import_lock);
		respond_error(socket, 409, "Conflict", @"This import is no longer the current one.");
		return;
	}
	import.id[0] = 0;           /* no more maps for this import */
	import.current[0] = 0;
	pthread_mutex_unlock(&import_lock);

	names = [files contentsOfDirectoryAtPath:stage error:nil];
	if (!names.count || names.count > MAX_MAPS) {
		import_failed(socket, @"No maps arrived.");
		return;
	}
	for (NSString *name in names) {
		NSString *path = [stage stringByAppendingPathComponent:name];
		unsigned long long size = [files attributesOfItemAtPath:path error:nil].fileSize;
		if (!check_map(path, size, build) || (*common && strcmp(common, build))) {
			import_failed(socket, [NSString stringWithFormat:@"%@ is not a map from the same Halo Xbox disc.", name]);
			return;
		}
		if (!*common)
			memcpy(common, build, sizeof(common));
		has_ui |= [name isEqualToString:@"ui.map"];
		total += size;
	}
	if (!has_ui || total > MAX_MAP_TOTAL) {
		import_failed(socket, has_ui ? @"The maps are larger than a Halo disc's." : @"ui.map is missing: this is not Halo: Combat Evolved.");
		return;
	}
	[files createDirectoryAtPath:data_root withIntermediateDirectories:YES attributes:nil error:nil];
	{
		struct stat info;
		int present = !lstat(installed.fileSystemRepresentation, &info);
		if (present ? renamex_np(stage.fileSystemRepresentation, installed.fileSystemRepresentation, RENAME_SWAP)
				: rename(stage.fileSystemRepresentation, installed.fileSystemRepresentation)) {
			import_failed(socket, [NSString stringWithFormat:@"The new maps could not be put in place (%s).", strerror(errno)]);
			return;
		}
	}
	[files removeItemAtPath:stage error:nil];          /* now holds the old maps, if any */
	pthread_mutex_lock(&import_lock);
	snprintf(import.build, sizeof(import.build), "%s", common);
	pthread_mutex_unlock(&import_lock);
	set_state(IMPORT_DONE, had_maps && atomic_load(&game_running)
		? @"The maps are installed. Restart the app on your Apple TV to use them."
		: @"The maps are installed.");
	respond_json(socket, 200, "OK", @{ @"maps": @(names.count), @"build": @(common) });
	if (ready_handler)
		dispatch_async(dispatch_get_main_queue(), ready_handler);
}

/* POST /api/import/cancel?id= */
static void import_cancel(int socket, const char *query)
{
	pthread_mutex_lock(&import_lock);
	if (!current_import(query)) {
		pthread_mutex_unlock(&import_lock);
		respond_error(socket, 409, "Conflict", @"This import is no longer the current one.");
		return;
	}
	import.id[0] = 0;
	pthread_mutex_unlock(&import_lock);
	[NSFileManager.defaultManager removeItemAtPath:stage_path() error:nil];
	set_state(IMPORT_IDLE, @"The import was cancelled; your installed maps were kept.");
	respond_json(socket, 200, "OK", @{});
}

/* ---------- request bodies */

/* a small JSON body (at most 4 KiB): body_start holds what came with the headers */
static NSDictionary *read_json(int socket, unsigned long long length, const char *body_start, size_t body_size)
{
	char body[4096];
	size_t have;
	NSDictionary *object;
	if (!length || length > sizeof(body))
		return nil;
	have = body_size < length ? body_size : (size_t)length;
	memcpy(body, body_start, have);
	while (have < length) {
		ssize_t got = recv(socket, body + have, (size_t)length - have, 0);
		if (got < 0 && errno == EINTR)
			continue;
		if (got <= 0) {
			memset_s(body, sizeof(body), 0, sizeof(body));
			return nil;
		}
		have += (size_t)got;
	}
	object = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:body length:have] options:0 error:nil];
	memset_s(body, sizeof(body), 0, sizeof(body));
	return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

static NSString *json_text(NSDictionary *object, NSString *key)
{
	id value = object[key];
	return [value isKindOfClass:NSString.class] ? value : nil;
}

/* ---------- pairing */

#define PAIR_CODE_SECONDS 120
#define PAIR_ATTEMPTS 5
#define MAX_TOKENS 8

/* TweetNaCl's randomness (the Steam sign-in's key pair, below) */
void randombytes(unsigned char *bytes, unsigned long long size) { arc4random_buf(bytes, (size_t)size); }

static void (^pairing_display)(NSString *code);
static pthread_mutex_t pair_lock = PTHREAD_MUTEX_INITIALIZER;
static char pair_code[7];
static time_t pair_expires;
static int pair_attempts, pair_generation;
static NSString *const token_key = @"HomecomingAdminTokens";

static void hex_text(const unsigned char *bytes, size_t size, char *out)
{
	for (size_t i = 0; i < size; i++)
		snprintf(out + 2 * i, 3, "%02x", bytes[i]);
}

/* what is kept of a token: its SHA-256, in hex */
static NSString *token_digest(const char *token)
{
	unsigned char hash[CC_SHA256_DIGEST_LENGTH];
	char text[2 * CC_SHA256_DIGEST_LENGTH + 1];
	CC_SHA256(token, (CC_LONG)strlen(token), hash);
	hex_text(hash, sizeof(hash), text);
	return @(text);
}

static int token_valid(const char *token)
{
	NSArray *known;
	if (strlen(token) != 64)
		return 0;
	known = [NSUserDefaults.standardUserDefaults arrayForKey:token_key];
	return [known containsObject:token_digest(token)];
}

static void display_code(NSString *code)
{
	void (^display)(NSString *) = pairing_display;
	if (display)
		dispatch_async(dispatch_get_main_queue(), ^{ display(code); });
}

/* (pair_lock held) the code ended: off the TV */
static void pair_end(void)
{
	pair_code[0] = 0;
	pair_generation++;
	display_code(nil);
}

/* POST /api/pair/request: shows a code on the TV (the same one while it lasts) */
static void pair_request(int socket)
{
	time_t now = time(NULL);
	int generation;
	NSString *code;

	pthread_mutex_lock(&pair_lock);
	if (!pair_code[0] || now >= pair_expires) {
		snprintf(pair_code, sizeof(pair_code), "%06u", arc4random_uniform(1000000));
		pair_expires = now + PAIR_CODE_SECONDS;
		pair_attempts = 0;
		pair_generation++;
	}
	generation = pair_generation;
	code = @(pair_code);
	pthread_mutex_unlock(&pair_lock);
	display_code(code);
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)PAIR_CODE_SECONDS * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		pthread_mutex_lock(&pair_lock);
		if (pair_generation == generation)
			pair_end();
		pthread_mutex_unlock(&pair_lock);
	});
	xg_log("admin: a pairing code is on the TV");
	respond_json(socket, 200, "OK", @{ @"seconds": @(PAIR_CODE_SECONDS) });
}

/* POST /api/pair {"code"}: a token for this browser */
static void pair_confirm(int socket, NSDictionary *body)
{
	NSString *typed = [json_text(body, @"code") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
	unsigned char random[32];
	char token[65];
	NSMutableArray *known;

	pthread_mutex_lock(&pair_lock);
	if (!pair_code[0] || time(NULL) >= pair_expires) {
		pthread_mutex_unlock(&pair_lock);
		respond_error(socket, 410, "Gone", @"That code has ended. Show a new code on the TV.");
		return;
	}
	if (!typed || strcmp(typed.UTF8String, pair_code)) {
		int left = PAIR_ATTEMPTS - ++pair_attempts;
		if (left <= 0)
			pair_end();
		pthread_mutex_unlock(&pair_lock);
		respond_error(socket, 403, "Forbidden", left > 0 ? [NSString stringWithFormat:@"Wrong code: %d tries left.", left]
			: @"Wrong code too many times. Show a new code on the TV.");
		return;
	}
	pair_end();
	pthread_mutex_unlock(&pair_lock);
	arc4random_buf(random, sizeof(random));
	hex_text(random, sizeof(random), token);
	known = [[NSUserDefaults.standardUserDefaults arrayForKey:token_key] mutableCopy] ?: [NSMutableArray array];
	[known addObject:token_digest(token)];
	while (known.count > MAX_TOKENS)
		[known removeObjectAtIndex:0];
	[NSUserDefaults.standardUserDefaults setObject:known forKey:token_key];
	xg_log("admin: a browser paired");
	respond_json(socket, 200, "OK", @{ @"token": @(token) });
}


/* ---------- Steam sign-in (the game's Steam Workshop session, xg_steam_admin.h)
 *
 *   GET  /api/steam             JSON: state, account, what Steam Guard asks for
 *   GET  /api/steam/key         {"key", "challenge"}: the TV's public key for
 *                               this launch, and a one-use challenge
 *   POST /api/steam/sign-in     {"key", "nonce", "box"} (base64): nacl.box of
 *                               "challenge\0account\0password" from the
 *                               page's own key pair to the TV's
 *   POST /api/steam/code        {"code"}: a Steam Guard code
 *   POST /api/steam/cancel      stop a sign-in under way
 *   POST /api/steam/sign-out
 *
 * The password crosses the network only encrypted (X25519, XSalsa20-Poly1305;
 * TweetNaCl on both sides). It is opened here into a buffer that is wiped,
 * then goes straight to the session thread, which wipes it once Steam has
 * it; only Steam's refresh token is kept (in the Keychain). */

#if XG_ADMIN_STEAM
#include "xg_steam_admin.h"

static unsigned char box_public[crypto_box_PUBLICKEYBYTES], box_secret[crypto_box_SECRETKEYBYTES];
static char challenge[33];
static time_t challenge_expires;

static NSData *base64(NSDictionary *object, NSString *key)
{
	NSString *text = json_text(object, key);
	return text ? [[NSData alloc] initWithBase64EncodedString:text options:0] : nil;
}

/* Opens the page's box into account and password (each wiped by the caller).
 * 0 with a message when it cannot. */
static int open_sign_in(NSDictionary *body, char *account, size_t account_size, char *password, size_t password_size,
	NSString **message)
{
	NSData *peer = base64(body, @"key"), *nonce = base64(body, @"nonce"), *box = base64(body, @"box");
	unsigned char *cipher, *plain;
	size_t size;
	char const *text, *end, *name, *secret;
	int opened, fresh;

	*message = @"The sign-in did not arrive whole. Reload the page and try again.";
	if (peer.length != crypto_box_PUBLICKEYBYTES || nonce.length != crypto_box_NONCEBYTES ||
		box.length < crypto_box_ZEROBYTES - crypto_box_BOXZEROBYTES || box.length > 2048)
		return 0;
	size = crypto_box_BOXZEROBYTES + box.length;
	cipher = calloc(1, size);
	plain = calloc(1, size + 1);
	if (!cipher || !plain) {
		free(cipher);
		free(plain);
		return 0;
	}
	memcpy(cipher + crypto_box_BOXZEROBYTES, box.bytes, box.length);
	opened = !crypto_box_open(plain, cipher, size, nonce.bytes, peer.bytes, box_secret);
	free(cipher);
	text = (char const *)plain + crypto_box_ZEROBYTES;
	end = (char const *)plain + size;
	name = opened ? memchr(text, 0, (size_t)(end - text)) : NULL;
	secret = name ? memchr(name + 1, 0, (size_t)(end - name - 1)) : NULL;
	pthread_mutex_lock(&pair_lock);
	fresh = name && challenge[0] && time(NULL) < challenge_expires && !strcmp(text, challenge);
	challenge[0] = 0;                 /* one use, whatever came */
	pthread_mutex_unlock(&pair_lock);
	if (opened && !fresh)
		*message = @"The sign-in was not for this page's request. Reload the page and try again.";
	else if (!secret || (size_t)(secret - name - 1) >= account_size || (size_t)(end - secret - 1) >= password_size)
		opened = 0;
	if (opened && fresh && secret) {
		memcpy(account, name + 1, (size_t)(secret - name));            /* with its NUL */
		memcpy(password, secret + 1, (size_t)(end - secret - 1));
		password[end - secret - 1] = 0;
	}
	memset_s(plain, size + 1, 0, size + 1);
	free(plain);
	return opened && fresh && secret;
}

static NSDictionary *steam_status_object(void)
{
	static char const *const names[] = { "out", "connecting", "guard", "signing_in", "in", "unavailable" };
	struct xg_steam_admin_status status;
	unsigned c;
	xg_steam_admin_status(data_root.fileSystemRepresentation, &status);
	c = status.confirmations;
	return @{ @"available": @YES,
		@"state": @(status.state >= 0 && status.state <= 5 ? names[status.state] : "unavailable"),
		@"account": @(status.account), @"message": @(status.message),
		@"guard": @{ @"app_approval": @((c & XG_STEAM_GUARD_DEVICE_CONFIRMATION) != 0),
			@"email_approval": @((c & XG_STEAM_GUARD_EMAIL_CONFIRMATION) != 0),
			@"app_code": @((c & XG_STEAM_GUARD_DEVICE_CODE) != 0),
			@"email_code": @((c & XG_STEAM_GUARD_EMAIL_CODE) != 0) } };
}

static void steam_request(int socket, const char *method, const char *path, unsigned long long length,
	const char *body_start, size_t body_size)
{
	if (!strcmp(method, "GET") && !strcmp(path, "/api/steam")) {
		respond_json(socket, 200, "OK", steam_status_object());
	} else if (!strcmp(method, "GET") && !strcmp(path, "/api/steam/key")) {
		unsigned char random[16];
		char key[64];
		arc4random_buf(random, sizeof(random));
		pthread_mutex_lock(&pair_lock);
		hex_text(random, sizeof(random), challenge);
		challenge_expires = time(NULL) + 300;
		snprintf(key, sizeof(key), "%s", challenge);
		pthread_mutex_unlock(&pair_lock);
		respond_json(socket, 200, "OK", @{ @"key": [[NSData dataWithBytes:box_public length:sizeof(box_public)]
			base64EncodedStringWithOptions:0], @"challenge": @(key) });
	} else if (!strcmp(method, "POST") && !strcmp(path, "/api/steam/sign-in")) {
		NSDictionary *body = read_json(socket, length, body_start, body_size);
		char account[128], secret[128];
		NSString *message;
		int started;
		if (!body || !open_sign_in(body, account, sizeof(account), secret, sizeof(secret), &message)) {
			respond_error(socket, 400, "Bad Request", body ? message : @"Type your Steam account name and password.");
			return;
		}
		started = account[0] && secret[0] && xg_steam_admin_sign_in(data_root.fileSystemRepresentation, account, secret);
		memset_s(secret, sizeof(secret), 0, sizeof(secret));
		memset_s(account, sizeof(account), 0, sizeof(account));
		if (!started) {
			respond_error(socket, 409, "Conflict", @"Steam is already signed in or signing in.");
			return;
		}
		xg_log("admin: Steam sign-in started");
		respond_json(socket, 200, "OK", steam_status_object());
	} else if (!strcmp(method, "POST") && !strcmp(path, "/api/steam/code")) {
		NSString *code = json_text(read_json(socket, length, body_start, body_size), @"code");
		code = [code stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
		if (!code.length || code.length > 16) {
			respond_error(socket, 400, "Bad Request", @"Type the Steam Guard code.");
			return;
		}
		if (!xg_steam_admin_code(code.uppercaseString.UTF8String)) {
			respond_error(socket, 409, "Conflict", @"Steam is not waiting for a code.");
			return;
		}
		respond_json(socket, 200, "OK", steam_status_object());
	} else if (!strcmp(method, "POST") && !strcmp(path, "/api/steam/cancel")) {
		xg_steam_admin_cancel();
		respond_json(socket, 200, "OK", steam_status_object());
	} else if (!strcmp(method, "POST") && !strcmp(path, "/api/steam/sign-out")) {
		if (!xg_steam_admin_sign_out()) {
			respond_error(socket, 409, "Conflict", @"Steam is not signed in.");
			return;
		}
		respond_json(socket, 200, "OK", steam_status_object());
	} else
		respond_error(socket, 404, "Not Found", @"Nothing here.");
}
#else
static void steam_request(int socket, const char *method, const char *path, unsigned long long length,
	const char *body_start, size_t body_size)
{
	(void)method; (void)path; (void)length; (void)body_start; (void)body_size;
	respond_json(socket, 200, "OK", @{ @"available": @NO });
}
#endif

/* ---------- requests */

/* Reads one request and answers it. */
static void serve(int socket)
{
	char header[MAX_HEADER + 1];
	size_t size = 0;
	char *end = NULL, *query, method[8] = {0}, path[512] = {0};
	unsigned long long length = 0;
	char token[80] = {0};

	while (!end) {
		ssize_t got;
		if (size == MAX_HEADER) {
			respond_error(socket, 431, "Request Header Fields Too Large", @"The request headers are too large.");
			return;
		}
		got = recv(socket, header + size, MAX_HEADER - size, 0);
		if (got < 0 && errno == EINTR)
			continue;
		if (got <= 0)
			return;
		size += (size_t)got;
		header[size] = 0;
		end = strstr(header, "\r\n\r\n");
	}
	if (sscanf(header, "%7s %511s HTTP/1.", method, path) != 2) {
		respond_error(socket, 400, "Bad Request", @"Not an HTTP request.");
		return;
	}
	for (char *line = strstr(header, "\r\n"); line && line < end; line = strstr(line + 2, "\r\n"))
		if (!strncasecmp(line + 2, "Content-Length:", 15))
			length = strtoull(line + 17, NULL, 10);
		else if (!strncasecmp(line + 2, "X-Homecoming-Token:", 19))
			sscanf(line + 21, " %79[0-9a-f]", token);
		else if (!strncasecmp(line + 2, "Transfer-Encoding:", 18)) {
			respond_error(socket, 411, "Length Required", @"Chunked uploads are not accepted.");
			return;
		}
	query = strchr(path, '?');
	if (query)
		*query++ = 0;
	end += 4;
	if (!strcmp(method, "GET") && (!strcmp(path, "/") || !strcmp(path, "/index.html"))) {
		NSData *page = [NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"admin" ofType:@"html"]];
		if (page)
			respond(socket, 200, "OK", @"text/html; charset=utf-8", page);
		else
			respond_error(socket, 500, "Internal Server Error", @"admin.html is missing from the app.");
	} else if (!strcmp(method, "GET") && !strcmp(path, "/nacl.min.js")) {
		NSData *script = [NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"nacl.min" ofType:@"js"]];
		respond(socket, script ? 200 : 404, script ? "OK" : "Not Found", @"application/javascript", script);
	} else if (!strcmp(method, "GET") && !strcmp(path, "/favicon.ico"))
		respond(socket, 204, "No Content", @"text/plain", nil);
	else if (!strcmp(method, "GET") && !strcmp(path, "/api/pair"))
		respond_json(socket, 200, "OK", @{ @"paired": @(token_valid(token) != 0) });
	else if (!strcmp(method, "POST") && !strcmp(path, "/api/pair/request"))
		pair_request(socket);
	else if (!strcmp(method, "POST") && !strcmp(path, "/api/pair"))
		pair_confirm(socket, read_json(socket, length, end, size - (size_t)(end - header)));
	else if (!token_valid(token))
		respond_json(socket, 401, "Unauthorized", @{ @"error": @"Pair this browser with the Apple TV first.", @"pair": @YES });
	else if (!strcmp(method, "GET") && !strcmp(path, "/api/status"))
		respond_json(socket, 200, "OK", status_object());
	else if (!strcmp(method, "POST") && !strcmp(path, "/api/import/begin"))
		import_begin(socket, query);
	else if (!strcmp(method, "PUT") && !strcmp(path, "/api/import/map"))
		import_map(socket, query, length, end, size - (size_t)(end - header));
	else if (!strcmp(method, "POST") && !strcmp(path, "/api/import/finish"))
		import_finish(socket, query);
	else if (!strcmp(method, "POST") && !strcmp(path, "/api/import/cancel"))
		import_cancel(socket, query);
	else if (!strncmp(path, "/api/steam", 10) && (!path[10] || path[10] == '/')) {
		steam_request(socket, method, path, length, end, size - (size_t)(end - header));
		memset_s(header, sizeof(header), 0, sizeof(header));   /* may hold a password that came with the headers */
	} else
		respond_error(socket, 404, "Not Found", @"Nothing here.");
}

/* the listening socket on port, or -1 */
static int open_listener(int port)
{
	struct sockaddr_in address = { .sin_len = sizeof(address), .sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_ANY) };
	int listener = socket(AF_INET, SOCK_STREAM, 0), on = 1;
	if (listener < 0)
		return -1;
	setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));
	address.sin_port = htons((uint16_t)port);
	if (bind(listener, (struct sockaddr *)&address, sizeof(address)) || listen(listener, 8)) {
		int error = errno;
		close(listener);
		errno = error;
		return -1;
	}
	return listener;
}

/* (main queue) the page advertised with Bonjour, again after a suspension */
static void advertise(void)
{
	if (bonjour) {
		DNSServiceRefDeallocate(bonjour);
		bonjour = NULL;
	}
	if (DNSServiceRegister(&bonjour, 0, 0, "Homecoming", "_http._tcp", NULL, NULL, htons((uint16_t)listen_port), 0, NULL,
			NULL, NULL) == kDNSServiceErr_NoError)
		DNSServiceSetDispatchQueue(bonjour, dispatch_get_main_queue());
	else
		bonjour = NULL;
}

/* While the app is suspended, tvOS and iOS can take its listening socket away
 * ("defunct"): accept then fails for good and every browser is refused. So the
 * socket is opened again, and the page advertised again, after such failures
 * and whenever the app returns to the foreground (xg_admin_reopen). */
static void *accept_loop(void *argument)
{
	int listener = (int)(intptr_t)argument, failures = 0;
	pthread_setname_np("xg admin");
	atomic_store(&listening_socket, listener);
	for (;;) {
		struct sockaddr_in peer;
		socklen_t peer_size = sizeof(peer);
		int client = accept(listener, (struct sockaddr *)&peer, &peer_size), on = 1;
		int error = errno, asked = atomic_exchange(&reopen_wanted, 0);
		struct timeval timeout = { 60, 0 };
		if (asked && client >= 0)
			close(client);           /* xg_admin_reopen's own connection, or one that waits for the new socket */
		if (client < 0 || asked) {
			if (!asked && (error == EINTR || (error == ECONNABORTED && ++failures < 3)))
				continue;
			if (asked)
				xg_log("admin: back in the foreground; opening the listening socket again");
			else
				xg_log("admin: the listening socket failed (%s); opening it again", strerror(error));
			atomic_store(&listening_socket, -1);
			close(listener);
			while ((listener = open_listener(listen_port)) < 0)
				sleep(1);
			atomic_store(&listening_socket, listener);
			failures = 0;
			dispatch_async(dispatch_get_main_queue(), ^{ advertise(); });
			xg_log("admin: serving on port %d again", listen_port);
			continue;
		}
		failures = 0;
		if (peer.sin_family != AF_INET || !local_address(&peer)) {
			close(client);
			continue;
		}
		setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, sizeof(on));
		setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
		setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
		if (dispatch_semaphore_wait(connection_slots, DISPATCH_TIME_NOW)) {
			respond_error(client, 503, "Service Unavailable", @"Busy; try again.");
			close(client);
			continue;
		}
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
			@autoreleasepool {
				serve(client);
				close(client);
			}
			dispatch_semaphore_signal(connection_slots);
		});
	}
	return NULL;
}

/* ---------- start, address */

int xg_admin_start(NSString *data, NSString *work, int port, void (^maps_ready)(void), void (^pairing)(NSString *code))
{
	int listener;
	pthread_t thread;

	if (listen_port)
		return 0;
	data_root = [data copy];
	work_root = [work copy];
	ready_handler = [maps_ready copy];
	pairing_display = [pairing copy];
#if XG_ADMIN_STEAM
	crypto_box_keypair(box_public, box_secret);   /* this launch's: the page encrypts the Steam password to it */
#endif
	connection_slots = dispatch_semaphore_create(4);
	[NSFileManager.defaultManager removeItemAtPath:[work_root stringByAppendingPathComponent:@"import"] error:nil];
	port = port ? port : 8080;
	listener = open_listener(port);
	if (listener < 0) {
		xg_log("admin: port %d unavailable: %s", port, strerror(errno));
		return -1;
	}
	listen_port = port;
	if (pthread_create(&thread, NULL, accept_loop, (void *)(intptr_t)listener)) {
		close(listener);
		listen_port = 0;
		return -1;
	}
	pthread_detach(thread);
	advertise();
	xg_log("admin: serving on port %d (%s)", port, xg_admin_address().UTF8String ?: "no network address yet");
	return 0;
}

void xg_admin_set_game_running(int running) { atomic_store(&game_running, running); }

void xg_admin_reopen(void)
{
	int listener = atomic_load(&listening_socket);
	if (!listen_port || listener < 0)
		return;
	atomic_store(&reopen_wanted, 1);
	/* wake accept with a connection of our own; on a socket the system took,
	 * accept fails instead. Either way it then opens a new one. */
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		struct sockaddr_in self = { .sin_len = sizeof(self), .sin_family = AF_INET,
			.sin_port = htons((uint16_t)listen_port), .sin_addr.s_addr = htonl(INADDR_LOOPBACK) };
		int wake = socket(AF_INET, SOCK_STREAM, 0);
		struct timeval timeout = { 2, 0 };
		if (wake < 0)
			return;
		setsockopt(wake, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
		connect(wake, (struct sockaddr *)&self, sizeof(self));
		close(wake);
	});
}

NSString *xg_admin_address(void)
{
	struct ifaddrs *list, *item;
	NSString *found = nil;
	if (!listen_port || getifaddrs(&list))
		return nil;
	/* wired first (en0 on Apple TV), then Wi-Fi */
	for (int pass = 0; pass < 2 && !found; pass++)
		for (item = list; item && !found; item = item->ifa_next) {
			char text[INET_ADDRSTRLEN];
			if (!item->ifa_addr || item->ifa_addr->sa_family != AF_INET || !(item->ifa_flags & IFF_UP) ||
				(item->ifa_flags & IFF_LOOPBACK) || strncmp(item->ifa_name, "en", 2))
				continue;
			if (pass == 0 && strcmp(item->ifa_name, "en0"))
				continue;
			if (inet_ntop(AF_INET, &((struct sockaddr_in *)item->ifa_addr)->sin_addr, text, sizeof(text)) &&
				local_address((struct sockaddr_in *)item->ifa_addr) && strncmp(text, "169.254.", 8))
				found = [NSString stringWithFormat:@"http://%s:%d", text, listen_port];
		}
	freeifaddrs(list);
	return found;
}

NSString *xg_admin_progress_line(void)
{
	NSString *line = nil;
	pthread_mutex_lock(&import_lock);
	switch (import.state) {
	case IMPORT_RECEIVING:
		line = [NSString stringWithFormat:@"Receiving the maps: %.0f%% (%.1f of %.1f GB)%s%s",
			import.expected ? 100.0 * import.received / import.expected : 0.0, import.received / 1e9, import.expected / 1e9,
			import.current[0] ? ", " : "", import.current];
		break;
	case IMPORT_FAILED:
		line = [NSString stringWithFormat:@"The import failed: %s", import.message];
		break;
	case IMPORT_DONE:
		line = @(import.message);
		break;
	default:
		break;
	}
	pthread_mutex_unlock(&import_lock);
	return line;
}
