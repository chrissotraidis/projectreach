/*
 * HaloPadXbox.m: the launch picker (Halo PC or Halo Xbox) and the Xbox game's
 * screen. Compiled into HaloPad only when the Xbox engine was built on this
 * Mac (scripts/xbox/build-ios.sh; docs/XBOX-ENGINE.md). HaloPadApp.m finds
 * HPEngineChooserMake through a weak reference and, without it, starts the
 * PC game as before.
 *
 * One engine runs per launch: both claim the same guest memory, so choosing
 * the other game means closing HaloPad and opening it again (the shared menu's
 * Switch Edition…).
 */
#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <GameController/GameController.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <stdatomic.h>
#include <sys/utsname.h>
#include "xg_ios.h"
#include "xg_xiso.h"
#import "HaloPadOverlay.h"
#import "HaloPadXboxSaveIdentity.h"
#import "HaloPadXboxQuality.h"
#import "HaloPadXboxUpdate.h"
#include "xg_overlay_input.h"
#include "../runtime/halopad_log.h"

#if TARGET_OS_MACCATALYST
/* On a Mac the keyboard and mouse play the Xbox edition as on a PC: keys go to the engine,
   and while the game runs the pointer is locked so the mouse aims. F12 frees or recaptures
   the pointer (as upstream's PC version), to reach the ⋯ menu or other apps. */
static __weak UIViewController *xbox_pointer_owner;
static BOOL xbox_pointer_free;
static BOOL xbox_pointer_locked(void)
{
	return xbox_pointer_owner.view.window.windowScene.pointerLockState.isLocked;
}
static void xbox_attach_mouse(GCMouse *mouse)
{
	GCMouseInput *m = mouse.mouseInput;
	m.mouseMovedHandler = ^(GCMouseInput *input, float dx, float dy) {
		double speed = HPSettings.shared.mouseSpeed;                    /* ⋯ › Controls › Mouse Speed */
		if (xbox_pointer_locked()) xg_ios_add_touch_look(dx * speed, -dy * speed);  /* Game Controller's y points up */
	};
	m.leftButton.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) { if (xbox_pointer_locked()) xg_ios_mouse_button(1, p); };
	m.middleButton.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) { if (xbox_pointer_locked()) xg_ios_mouse_button(2, p); };
	m.rightButton.pressedChangedHandler = ^(GCControllerButtonInput *b, float v, BOOL p) { if (xbox_pointer_locked()) xg_ios_mouse_button(3, p); };
	m.scroll.valueChangedHandler = ^(GCControllerDirectionPad *pad, float x, float y) {
		if (xbox_pointer_locked() && y) xg_ios_mouse_wheel(y > 0 ? 1 : -1);
	};
}
#endif

/* the engine's log lines, also written to HaloPad's shareable log (xg_syscall.c) */
extern void (*xg_log_sink)(const char *line);

static void xbox_log_sink(const char *line)
{
	static atomic_int count;
	int n = atomic_fetch_add(&count, 1);
	if (n < 2000)
		HP_LOG("Xbox: %s", line);
	else if (n == 2000)
		HP_LOG("Xbox: later engine messages are not logged this session");
}

/* system link: iOS lets apps broadcast only with a restricted entitlement, so
 * the game searches the addresses the player lists instead (upstream's
 * network.broadcast, read when the game starts) */
static NSString *const link_key = @"HaloPadXboxLinkAddresses";

static NSString *own_addresses(void)
{
	NSMutableArray *found = [NSMutableArray array];
	struct ifaddrs *list = NULL, *entry;
	if (getifaddrs(&list) == 0)
	{
		for (entry = list; entry; entry = entry->ifa_next)
		{
			char text[INET_ADDRSTRLEN];
			if (!entry->ifa_addr || entry->ifa_addr->sa_family != AF_INET || (entry->ifa_flags & IFF_LOOPBACK) ||
				!(entry->ifa_flags & IFF_UP) || strncmp(entry->ifa_name, "en", 2))
				continue;
			inet_ntop(AF_INET, &((struct sockaddr_in *)entry->ifa_addr)->sin_addr, text, sizeof(text));
			if (strncmp(text, "169.254.", 8))
				[found addObject:@(text)];
		}
		freeifaddrs(list);
	}
	return found.count ? [found componentsJoinedByString:@", "] : @"not on a network";
}

static NSString *xbox_root(void)
{
	NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
	return [documents stringByAppendingPathComponent:@"Halo Xbox"];
}

static NSString *xbox_data(void)
{
	const char *development = getenv("XG_DATA");
	return development && *development ? @(development) : xbox_root();
}

static NSString *xbox_saves(void)
{
	const char *development = getenv("XG_SAVE");
	return development && *development ? @(development) : [xbox_root() stringByAppendingPathComponent:@"save"];
}

static BOOL xbox_has_maps(void)
{
	return [NSFileManager.defaultManager fileExistsAtPath:[xbox_data() stringByAppendingPathComponent:@"maps/ui.map"]];
}

static NSDictionary *xbox_build(void)
{
	NSData *data = [NSData dataWithContentsOfFile:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"data/xbox/build.json"]];
	return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : @{};
}

/* "build 85" for an upstream release tag, else the short revision */
static NSString *xbox_release(NSDictionary *build)
{
	NSString *release = build[@"release"], *revision = build[@"revision"] ?: @"";
	if ([release isKindOfClass:NSString.class] && [release hasPrefix:@"build-"])
		return [@"build " stringByAppendingString:[release substringFromIndex:6]];
	return revision.length ? [revision substringToIndex:MIN((NSUInteger)8, revision.length)] : @"unknown build";
}

static NSString *xbox_graphics_name(void)
{
	return HPXboxSharperSelected(NSUserDefaults.standardUserDefaults) ? @"Sharper (Preview)" : @"Original";
}

/* Preserve a copy before a different guest opens snapshot saves. */
static BOOL xbox_backup_saves(NSError **error)
{
	/* Test saves must not update the real installation's revision marker. */
	const char *development = getenv("XG_SAVE");
	if (development && *development)
		return YES;
	NSString *revision = HPXboxSaveIdentity(xbox_build());
	NSString *previous = [NSUserDefaults.standardUserDefaults stringForKey:@"HaloPadXboxSaveRevision"];
	if (!revision.length)
	{
		if (error) *error = [NSError errorWithDomain:@"HaloPadXbox" code:1 userInfo:@{
			NSLocalizedDescriptionKey: @"The Xbox build has no guest identity. Rebuild before opening saves." }];
		return NO;
	}
	if ([revision isEqualToString:previous])
		return YES;
	NSFileManager *files = NSFileManager.defaultManager;
	NSString *saves = xbox_saves();
	NSArray *contents = [files fileExistsAtPath:saves] ? [files contentsOfDirectoryAtPath:saves error:error] : @[];
	if (!contents)
		return NO;
	if (contents.count)
	{
		NSString *backupRoot = [xbox_root() stringByAppendingPathComponent:@"Save Backups"];
		NSString *name = [NSString stringWithFormat:@"%@-%.0f", previous ?: @"unversioned", NSDate.date.timeIntervalSince1970];
		if (![files createDirectoryAtPath:backupRoot withIntermediateDirectories:YES attributes:nil error:error] ||
			![files copyItemAtPath:saves toPath:[backupRoot stringByAppendingPathComponent:name] error:error])
			return NO;
	}
	[NSUserDefaults.standardUserDefaults setObject:revision forKey:@"HaloPadXboxSaveRevision"];
	return YES;
}

/* ---------- the Xbox game */

@interface HPXboxViewController : UIViewController <UIDocumentPickerDelegate, HPOverlayDelegate>
@property(nonatomic, copy) void (^returnToChooser)(void);
@end

@implementation HPXboxViewController
{
	UIView *game;
	HPOverlay *pad;
	struct xg_overlay_input touch_input;
	UIButton *link_button;
	UIView *import_panel;
	UILabel *import_status;
	UIProgressView *import_progress;
	UIButton *import_button;
	UIButton *back_button;
	NSTimer *fps_timer;
	BOOL started;
}

- (void)loadView
{
	UIView *root = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
	root.backgroundColor = UIColor.blackColor;
	game = xg_ios_make_view(root.bounds);
	game.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[root addSubview:game];
	link_button = [UIButton buttonWithType:UIButtonTypeSystem];
	[link_button setTitle:@"Link" forState:UIControlStateNormal];
	[link_button setTitleColor:[UIColor colorWithWhite:1 alpha:0.85] forState:UIControlStateNormal];
	link_button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
	link_button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28];
	link_button.layer.cornerRadius = 14;
	link_button.frame = CGRectMake(20, 16, 60, 32);
	[link_button addTarget:self action:@selector(showLink) forControlEvents:UIControlEventTouchUpInside];
	[root addSubview:link_button];
	self.view = root;
}

- (void)viewSafeAreaInsetsDidChange
{
	[super viewSafeAreaInsetsDidChange];
	link_button.frame = CGRectMake(self.view.safeAreaInsets.left + 20, self.view.safeAreaInsets.top + 16, 60, 32);
}

- (void)showLink
{
	NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:link_key] ?: @"";
	NSString *message = [NSString stringWithFormat:@"To play system link with other iPads, iPhones or computers running this "
		@"Xbox version, enter their addresses (separated by commas). They enter this device's address: %@.\n\n"
		@"Changes take effect the next time you open Halo Xbox.", own_addresses()];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"System Link" message:message
		preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
		field.text = saved;
		field.placeholder = @"192.168.1.20, 192.168.1.21";
		field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
		field.autocorrectionType = UITextAutocorrectionTypeNo;
	}];
	[alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		NSString *text = [alert.textFields.firstObject.text stringByReplacingOccurrencesOfString:@" " withString:@""];
		[NSUserDefaults.standardUserDefaults setObject:text forKey:link_key];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	xg_ios_view_resized();
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
#if TARGET_OS_MACCATALYST
	xbox_pointer_owner = self;
	[self becomeFirstResponder];
	static dispatch_once_t mice;
	dispatch_once(&mice, ^{
		for (GCMouse *mouse in GCMouse.mice) xbox_attach_mouse(mouse);
		[NSNotificationCenter.defaultCenter addObserverForName:GCMouseDidConnectNotification object:nil
			queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) { xbox_attach_mouse(n.object); }];
	});
#endif
	if (started)
		return;
	if (xbox_has_maps())
		[self startGame];
	else
	{
		[self showImport];
		/* development: HALOPAD_XBOX_IMPORT=<disc image> imports it as if the player had picked it */
		if (getenv("HALOPAD_XBOX_IMPORT"))
			[self documentPicker:nil didPickDocumentsAtURLs:@[ [NSURL fileURLWithPath:@(getenv("HALOPAD_XBOX_IMPORT"))] ]];
	}
}

- (void)startGame
{
	NSString *image = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"data/xbox/halo_guest.elf"];
	NSError *error = nil;
	if (!xbox_backup_saves(&error))
	{
		[self showProblem:[@"Your saves could not be backed up before this update. " stringByAppendingString:error.localizedDescription ?: @""]];
		return;
	}
	started = YES;
#if TARGET_OS_MACCATALYST
	[self setNeedsUpdateOfPrefersPointerLocked];
#endif
	back_button.hidden = YES;
	link_button.hidden = NO;
	import_panel.hidden = YES;
	/* The pad manages its own controller visibility. Create it only for the
	 * running game, so it cannot reappear or keep polling on the import screen. */
	if (!pad)
	{
		__weak HPXboxViewController *weak = self;
		pad = [[HPOverlay alloc] initWithFrame:self.view.bounds inputHandler:^(const hp_input *event) {
			HPXboxViewController *owner = weak;
			if (!owner) return;
			xg_overlay_event(&owner->touch_input, event);
			if (event->kind == HPI_CANCEL_TOUCH) xg_ios_clear_touch_pad();
			else if (event->kind == HPI_MOUSEMOVE) xg_ios_add_touch_look(event->dx, event->dy);
			else xg_ios_set_touch_pad(&owner->touch_input.pad);
		}];
		pad.analogMoveReady = YES;
		pad.inGame = YES;
		/* One finger owns both the held board and scrolling; no guest patch.
		 * Eighty points is one Page Up/Down; ordinary aim remains independent. */
		pad.scoreboardScroll = ^(CGFloat dy) { xg_ios_scroll_scoreboard(dy); };
		[pad setControllerLabel:nil hint:@"Hold to show scores. Drag up or down to scroll the roster." forControl:@"scores"];
		[pad setControllerLabel:@"A" hint:@"Xbox A. Select in menus." forControl:@"jump"];
		[pad setControllerLabel:@"B" hint:@"Xbox B. Back in menus." forControl:@"melee"];
		[pad setControllerLabel:@"X" hint:@"Xbox X. Use or reload with the default profile." forControl:@"action"];
		[pad setControllerLabel:@"X" hint:@"Xbox X. Use or reload with the default profile." forControl:@"reload"];
		[pad setControllerLabel:@"Y" hint:@"Xbox Y. Switch weapons or follow the menu prompt." forControl:@"switch"];
		pad.controllerConnected = ^BOOL {
			if (getenv("XG_TOUCH_SHOW")) return NO;
			for (GCController *controller in GCController.controllers) if (controller.extendedGamepad) return YES;
			return NO;
		};
		pad.delegate = self;
		pad.engineMenuItems = @[
			[UIAction actionWithTitle:@"System Link…" image:[UIImage systemImageNamed:@"network"] identifier:nil
				handler:^(__kindof UIAction *action) { [weak showLink]; }]];
		[self configureControllerGuide];
		[pad refreshControllerVisibility];
		pad.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
		[self.view insertSubview:pad belowSubview:link_button];
		link_button.hidden = YES;
		fps_timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
			static int last;
			HPXboxViewController *owner = weak;
			if (!owner) { [timer invalidate]; return; }
			int now = xg_ios_frames_presented();
			[owner->pad setFramesPerSecond:now - last];
			last = now;
		}];
	}
	[NSFileManager.defaultManager createDirectoryAtPath:xbox_saves() withIntermediateDirectories:YES attributes:nil error:nil];
	{
		/* online play's MQTT brokers (network.brokers_file, beside config.toml): written at each
		   start, as upstream's Android app and desktop updates do. Without it the server browser
		   finds no games and invites cannot connect. */
		NSString *source = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"data/xbox/brokers.txt"];
		NSData *brokers = [NSData dataWithContentsOfFile:source];
		NSString *target = [xbox_data() stringByAppendingPathComponent:@"brokers.txt"];
		if (brokers && [brokers writeToFile:target atomically:YES])
			HP_LOG("Xbox: online brokers written to brokers.txt (%lu bytes)", (unsigned long)brokers.length);
		else
			HP_LOG("Xbox: could not write brokers.txt; the server browser will find no games");
	}
	{
		NSString *addresses = [NSUserDefaults.standardUserDefaults stringForKey:link_key];
		if (addresses.length)
			setenv("HALO_NET_BROADCAST", addresses.UTF8String, 0);
	}
	/* development on a device: XG_FRAME_DUMP_DOCUMENTS=1 saves frames to Documents/xbox-frame.ppm */
	if (getenv("XG_FRAME_DUMP_DOCUMENTS"))
		setenv("XG_FRAME_DUMP", [xbox_root().stringByDeletingLastPathComponent stringByAppendingPathComponent:@"xbox-frame.ppm"].fileSystemRepresentation, 1);
	HPXboxApplyQuality(xbox_build(), NSUserDefaults.standardUserDefaults);
	{
		NSDictionary *build = xbox_build();
		xg_log_sink = xbox_log_sink;
		HP_LOG("Xbox: starting OpenCE %s (%s), %s, renderer %s, graphics %s",
			xbox_release(build).UTF8String, [build[@"revision"] ?: @"?" UTF8String],
			[build[@"guest_adaptation"][@"name"] ?: @"no adaptation" UTF8String],
			[build[@"renderer"] ?: @"apple-gles" UTF8String], xbox_graphics_name().UTF8String);
	}
	if (xg_ios_start(image.fileSystemRepresentation, xbox_data().fileSystemRepresentation, xbox_saves().fileSystemRepresentation))
	{
		HP_LOG("Xbox: the game could not start");
		[self showProblem:@"The Xbox game could not start. Its diagnostic log is in Files → HaloPad → HaloPad Logs."];
	}
}

/* The shared Controller Guide, with the Xbox game's Default profile and touch notes. */
- (void)configureControllerGuide
{
	NSString *adaptation = xbox_build()[@"guest_adaptation"][@"name"];
	BOOL profileBridge = [adaptation isEqual:@"shared-input-v1"] || [adaptation isEqual:@"render-present-v1"] ||
		[adaptation isEqual:@"render-camera-v1"];
	pad.controllerGuideIntro = @"Touch: MOVE highlights menu items, A (Jump) selects and B (Melee) goes back. In play, drag the screen to aim or drag FIRE while shooting. Hold Scoreboard and drag to scroll its roster.";
	pad.controllerGuideSections = @[
		@[@"Movement & View", @[@"Left stick", @"Move"], @[@"Right stick", @"Look"],
		  @[@"Left stick click", @"Crouch"], @[@"Right stick click", @"Zoom"]],
		@[@"Combat & Actions", @[@"RT", @"Fire"], @[@"LT", @"Throw grenade"],
		  @[@"A", @"Jump"], @[@"B", @"Melee"], @[@"X", @"Action / reload"],
		  @[@"Y", @"Switch weapon"], @[@"LB (White)", @"Flashlight"], @[@"RB (Black)", @"Switch grenade"]],
		@[@"Menus", @[@"Left stick / D-pad", @"Move selection"], @[@"A", @"Select"],
		  @[@"B", @"Back"], @[@"View (Back)", @"Scoreboard"], @[@"Menu (Start)", @"Pause"]]];
	pad.controllerGuideFootnote = profileBridge
		? @"This is the Default profile. Touch buttons keep their actions when you pick another preset in Halo → Settings → Controls; controller presets follow the game."
		: @"This is the Default profile. Other in-game presets do not match the touch labels yet.";
}

/* ---- the shared menu (HPOverlayDelegate) */

- (void)overlayDisplayChanged:(HPOverlay *)overlay { (void)overlay; }
- (void)overlayRequestsKeyboard:(HPOverlay *)overlay { (void)overlay; }

- (NSURL *)overlayDiagnosticLog:(HPOverlay *)overlay
{
	const char *path = halopad_log_path();
	return path ? [NSURL fileURLWithPath:@(path)] : nil;
}

- (NSString *)overlayDiagnostics:(HPOverlay *)overlay
{
	struct utsname machine;
	NSDictionary *build = xbox_build();
	NSMutableArray *pads = [NSMutableArray array];
	CGSize screen = UIScreen.mainScreen.bounds.size;
	uname(&machine);
	for (GCController *controller in GCController.controllers) [pads addObject:controller.vendorName ?: @"controller"];
	return [NSString stringWithFormat:@"HaloPad %@ (build %@), Xbox edition\nEngine: OpenCE %@ (%@), %@, renderer %@, graphics %@\n"
		@"Device: %s, %@ %@, %.0fx%.0f points\nFrames presented: %d\nControllers: %@\nTouch controls: %@\nSystem link addresses: %@",
		[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?",
		[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?",
		xbox_release(build), [build[@"revision"] ?: @"?" substringToIndex:MIN((NSUInteger)8, [build[@"revision"] ?: @"?" length])],
		build[@"guest_adaptation"][@"name"] ?: @"no adaptation", build[@"renderer"] ?: @"apple-gles", xbox_graphics_name(),
		machine.machine, UIDevice.currentDevice.systemName, UIDevice.currentDevice.systemVersion, screen.width, screen.height,
		xg_ios_frames_presented(), pads.count ? [pads componentsJoinedByString:@", "] : @"none",
		HPSettings.shared.hideTouchControls ? @"hidden" : @"shown",
		[[NSUserDefaults.standardUserDefaults stringForKey:link_key] length] ? @"set" : @"none"];
}

- (NSString *)overlayAbout:(HPOverlay *)overlay
{
	NSDictionary *build = xbox_build();
	return [NSString stringWithFormat:@"HaloPad %@ (%@)\nHalo: Combat Evolved for the original Xbox, running on OpenCE %@ (built %@).\n"
		@"Graphics: %@. Rendering: %@.\n\nGame files: Files app → HaloPad → Halo Xbox\nSaves are backed up whenever the engine changes.\n\n"
		@"HaloPad needs your own copy of Halo. It includes no game data.",
		[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?",
		[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?",
		xbox_release(build), build[@"built"] ?: @"locally", xbox_graphics_name(),
		[build[@"renderer"] isEqual:@"angle-metal"] ? @"Metal (ANGLE)" : @"OpenGL ES"];
}

- (NSString *)overlayEditionSwitchNote:(HPOverlay *)overlay
{
	if (!self.returnToChooser)
		return nil;
	return @"Your settings and touch layout are saved. The campaign continues from its last checkpoint; to be certain, pause and choose Save and Quit first.";
}

- (void)showProblem:(NSString *)text
{
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Halo Xbox" message:text preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)showImport
{
	UIStackView *stack;
	UILabel *title = [UILabel new], *body = [UILabel new];
	import_panel = [UIView new];
	import_panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
	import_panel.layer.cornerRadius = 20;
	import_panel.translatesAutoresizingMaskIntoConstraints = NO;
	title.text = @"Add your Halo Xbox disc";
	title.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
	title.textColor = UIColor.whiteColor;
	body.text = @"Choose a disc image (.iso or .xiso) of your own Halo: Combat Evolved for Xbox. "
		@"HaloPad copies its maps (about 1.8 GB) into the Halo Xbox folder; you can delete the image afterwards.";
	body.numberOfLines = 0;
	body.textColor = [UIColor colorWithWhite:0.8 alpha:1];
	body.font = [UIFont systemFontOfSize:16];
	import_button = [UIButton buttonWithType:UIButtonTypeSystem];
	[import_button setTitle:@"Choose Disc Image" forState:UIControlStateNormal];
	import_button.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
	[import_button addTarget:self action:@selector(pick) forControlEvents:UIControlEventTouchUpInside];
	import_progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
	import_progress.hidden = YES;
	import_status = [UILabel new];
	import_status.textColor = [UIColor colorWithWhite:0.7 alpha:1];
	import_status.numberOfLines = 0;
	import_status.font = [UIFont systemFontOfSize:14];
	stack = [[UIStackView alloc] initWithArrangedSubviews:@[ title, body, import_button, import_progress, import_status ]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 16;
	stack.alignment = UIStackViewAlignmentFill;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[import_panel addSubview:stack];
	[self.view addSubview:import_panel];
	back_button = [UIButton buttonWithType:UIButtonTypeSystem];
	[back_button setTitle:@"‹ Editions" forState:UIControlStateNormal];
	back_button.translatesAutoresizingMaskIntoConstraints = NO;
	back_button.hidden = !self.returnToChooser;
	[back_button addTarget:self action:@selector(backToChooser) forControlEvents:UIControlEventTouchUpInside];
	[self.view addSubview:back_button];
	link_button.hidden = YES;
	[NSLayoutConstraint activateConstraints:@[
		[back_button.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],
		[back_button.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
		[back_button.heightAnchor constraintGreaterThanOrEqualToConstant:44],
		[import_panel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
		[import_panel.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
		[import_panel.widthAnchor constraintLessThanOrEqualToConstant:520],
		[import_panel.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],
		[import_panel.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],
		[stack.topAnchor constraintEqualToAnchor:import_panel.topAnchor constant:28],
		[stack.bottomAnchor constraintEqualToAnchor:import_panel.bottomAnchor constant:-28],
		[stack.leadingAnchor constraintEqualToAnchor:import_panel.leadingAnchor constant:28],
		[stack.trailingAnchor constraintEqualToAnchor:import_panel.trailingAnchor constant:-28]]];
}

- (void)backToChooser
{
	if (!started && import_button.enabled && self.returnToChooser)
		self.returnToChooser();
}

- (void)pick
{
	UTType *iso = [UTType typeWithFilenameExtension:@"iso"] ?: UTTypeData;
	UTType *xiso = [UTType typeWithFilenameExtension:@"xiso"] ?: UTTypeData;
	UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[ iso, xiso, UTTypeData ]];
	picker.delegate = self;
	[self presentViewController:picker animated:YES completion:nil];
}

static void import_progress_update(double fraction, void *context)
{
	static int last = -1;
	int percent = (int)(fraction * 100);
	UIProgressView *progress = (__bridge UIProgressView *)context;
	if (percent == last)
		return;
	last = percent;
	dispatch_async(dispatch_get_main_queue(), ^{ progress.progress = (float)fraction; });
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls
{
	NSURL *url = urls.firstObject;
	NSString *destination = xbox_data();
	UIProgressView *progress = import_progress;
	if (!url)
		return;
	import_button.enabled = NO;
	back_button.enabled = NO;
	import_progress.progress = 0;
	import_progress.hidden = NO;
	import_status.text = @"Copying the maps from your disc…";
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		char build[64], error[256];
		BOOL access = [url startAccessingSecurityScopedResource];
		int result = xg_extract_maps(url.fileSystemRepresentation, destination.fileSystemRepresentation,
			import_progress_update, (__bridge void *)progress, build, sizeof(build), error, sizeof(error));
		NSString *message = @(error), *maps_build = @(build);
		if (access)
			[url stopAccessingSecurityScopedResource];
		dispatch_async(dispatch_get_main_queue(), ^{
			if (result == 0)
			{
				NSLog(@"HaloPad Xbox: imported maps build %@", maps_build);
				[self startGame];
				return;
			}
			self->import_button.enabled = YES;
			self->back_button.enabled = YES;
			self->import_progress.hidden = YES;
			self->import_status.text = message;
		});
	});
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
#if TARGET_OS_MACCATALYST
- (BOOL)prefersPointerLocked { return started && !xbox_pointer_free && !self.presentedViewController; }
- (BOOL)canBecomeFirstResponder { return YES; }
- (void)xboxKeys:(NSSet<UIPress *> *)presses down:(int)down
{
	for (UIPress *press in presses)
	{
		if (!press.key) continue;
		if (press.key.keyCode == UIKeyboardHIDUsageKeyboardF12)
		{
			if (down) { xbox_pointer_free = !xbox_pointer_free; [self setNeedsUpdateOfPrefersPointerLocked]; }
			continue;
		}
		xg_ios_key((int)press.key.keyCode, down);
	}
}
- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event
{
	if (self.presentedViewController || !started) { [super pressesBegan:presses withEvent:event]; return; }
	[self xboxKeys:presses down:1];
}
- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event { [self xboxKeys:presses down:0]; }
- (void)pressesCancelled:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event { [self xboxKeys:presses down:0]; }
#endif
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
@end

/* ---------- the launch picker */

static BOOL pc_has_files(void)
{
	const char *root = getenv("HALOPAD_GAME_ROOT");
	NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
	NSString *folder = root && *root ? @(root) : [documents stringByAppendingPathComponent:@"Halo Custom Edition"];
	return [NSFileManager.defaultManager fileExistsAtPath:[folder stringByAppendingPathComponent:@"maps/ui.map"]];
}

static NSString *const HPProjectURL = @"https://github.com/chrissotraidis/projectreach";

@interface HPEngineChooser : UIViewController <UIGestureRecognizerDelegate>
@property(nonatomic, copy) UIViewController *(^makePC)(void);
@end

@implementation HPEngineChooser
{
	UIStackView *cards, *footer;
	BOOL appeared;
	UIButton *pc_play, *xbox_play;
	BOOL choosing;
}

/* Online players must share OpenCE's network version, not necessarily its build.
   Report optional releases separately from incompatible multiplayer versions. */
static void xbox_check_upstream(NSDictionary *build, void (^notice)(NSString *message))
{
	NSString *repo = @"OpenCommunityEdition/OpenCE";
	NSURL *latest = [NSURL URLWithString:[NSString stringWithFormat:@"https://api.github.com/repos/%@/releases/latest", repo]];
	NSURLRequest *request = [NSURLRequest requestWithURL:latest cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
	[[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *r, NSError *e) {
		if (e || ![r isKindOfClass:NSHTTPURLResponse.class] || ((NSHTTPURLResponse *)r).statusCode != 200) return;
		NSDictionary *release = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
		NSString *tag = [release isKindOfClass:NSDictionary.class] ? release[@"tag_name"] : nil;
		if (!HPXboxReleaseTag(tag)) return;
		NSURL *limits = [NSURL URLWithString:[NSString stringWithFormat:
			@"https://raw.githubusercontent.com/%@/%@/port/linux/include/halo_port_limits.h", repo, tag]];
		NSURLRequest *headerRequest = [NSURLRequest requestWithURL:limits cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
		[[NSURLSession.sharedSession dataTaskWithRequest:headerRequest completionHandler:^(NSData *header, NSURLResponse *r2, NSError *e2) {
			BOOL ok = !e2 && [r2 isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse *)r2).statusCode == 200;
			NSString *text = ok && header ? [[NSString alloc] initWithData:header encoding:NSUTF8StringEncoding] : nil;
			NSString *message = HPXboxUpdateNotice(build, tag, HPXboxNetworkVersion(text));
			if (!message) return;
			dispatch_async(dispatch_get_main_queue(), ^{ notice(message); });
		}] resume];
	}] resume];
}

static UILabel *chooser_label(NSString *text, UIFontTextStyle style, UIFontWeight weight, UIColor *color)
{
	UILabel *label = [UILabel new];
	UIFontDescriptor *descriptor = [UIFontDescriptor preferredFontDescriptorWithTextStyle:style];
	label.text = text;
	label.font = [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:[UIFont systemFontOfSize:descriptor.pointSize weight:weight]];
	label.adjustsFontForContentSizeCategory = YES;
	label.textColor = color;
	label.numberOfLines = 0;
	return label;
}

static UIView *chooser_pill(NSString *text, UIColor *color)
{
	UILabel *label = chooser_label(text, UIFontTextStyleCaption1, UIFontWeightBold, color);
	UIView *pill = [UIView new];
	label.translatesAutoresizingMaskIntoConstraints = NO;
	pill.backgroundColor = [color colorWithAlphaComponent:0.14];
	pill.layer.cornerRadius = 10;
	[pill addSubview:label];
	[NSLayoutConstraint activateConstraints:@[
		[label.leadingAnchor constraintEqualToAnchor:pill.leadingAnchor constant:10],
		[label.trailingAnchor constraintEqualToAnchor:pill.trailingAnchor constant:-10],
		[label.topAnchor constraintEqualToAnchor:pill.topAnchor constant:4],
		[label.bottomAnchor constraintEqualToAnchor:pill.bottomAnchor constant:-4]]];
	return pill;
}

/* One edition: what it is, its exact version, whether it is ready, and how to play it. */
- (UIView *)cardTitle:(NSString *)title platform:(NSString *)platform symbol:(NSString *)symbol accent:(UIColor *)accent
	version:(NSString *)version about:(NSString *)about ready:(BOOL)ready status:(NSString *)status
	play:(NSString *)play identifier:(NSString *)identifier action:(SEL)action last:(BOOL)last extra:(UIView *)extra
	button:(UIButton * __strong *)button
{
	UIView *card = [UIView new];
	UIColor *muted = [UIColor colorWithWhite:0.72 alpha:1];
	UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol
		withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightSemibold]]];
	UIView *spacer = [UIView new];
	NSMutableArray *tags = [NSMutableArray arrayWithObjects:icon, spacer, nil];
	UIStackView *header, *statusRow, *info, *stack;
	UIView *dot = [UIView new];
	UIColor *statusColor = ready ? [UIColor colorWithRed:0.38 green:0.85 blue:0.45 alpha:1] : [UIColor colorWithRed:1 green:0.74 blue:0.28 alpha:1];
	UIButtonConfiguration *configuration = [UIButtonConfiguration filledButtonConfiguration];

	card.backgroundColor = [UIColor colorWithRed:0.06 green:0.095 blue:0.135 alpha:0.88];
	card.layer.cornerRadius = 22;
	card.layer.borderWidth = 1;
	card.layer.borderColor = [accent colorWithAlphaComponent:last ? 0.85 : 0.48].CGColor;
	icon.tintColor = accent;
	icon.contentMode = UIViewContentModeScaleAspectFit;
	[spacer setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
	if (last)
		[tags addObject:chooser_pill(@"LAST PLAYED", UIColor.whiteColor)];
	[tags addObject:chooser_pill(platform, accent)];
	header = [[UIStackView alloc] initWithArrangedSubviews:tags];
	header.spacing = 8;
	header.alignment = UIStackViewAlignmentCenter;

	[dot.widthAnchor constraintEqualToConstant:9].active = YES;
	[dot.heightAnchor constraintEqualToConstant:9].active = YES;
	dot.layer.cornerRadius = 4.5;
	dot.backgroundColor = statusColor;
	statusRow = [[UIStackView alloc] initWithArrangedSubviews:@[ dot, chooser_label(status, UIFontTextStyleSubheadline, UIFontWeightSemibold, statusColor) ]];
	statusRow.spacing = 8;
	statusRow.alignment = UIStackViewAlignmentCenter;

	info = [[UIStackView alloc] initWithArrangedSubviews:@[
		header,
		chooser_label(title, UIFontTextStyleTitle1, UIFontWeightBold, UIColor.whiteColor),
		chooser_label(version, UIFontTextStyleSubheadline, UIFontWeightMedium, accent),
		chooser_label(about, UIFontTextStyleBody, UIFontWeightRegular, muted),
		statusRow ]];
	info.axis = UILayoutConstraintAxisVertical;
	info.spacing = 10;
	[info setCustomSpacing:18 afterView:header];
	[info setCustomSpacing:4 afterView:info.arrangedSubviews[1]];
	[info setCustomSpacing:16 afterView:info.arrangedSubviews[3]];
	info.userInteractionEnabled = NO;

	configuration.title = play;
	configuration.baseBackgroundColor = accent;
	configuration.baseForegroundColor = [UIColor colorWithRed:0.02 green:0.04 blue:0.06 alpha:1];
	configuration.cornerStyle = UIButtonConfigurationCornerStyleLarge;
	configuration.image = [UIImage systemImageNamed:ready ? @"play.fill" : @"plus"];
	configuration.imagePadding = 8;
	configuration.contentInsets = NSDirectionalEdgeInsetsMake(14, 18, 14, 18);
	configuration.titleTextAttributesTransformer = ^NSDictionary *(NSDictionary *in) {
		NSMutableDictionary *out = [in mutableCopy];
		out[NSFontAttributeName] = [UIFont systemFontOfSize:[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline].pointSize weight:UIFontWeightBold];
		return out;
	};
	*button = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
	(*button).pointerInteractionEnabled = YES;
	(*button).accessibilityIdentifier = identifier;
	(*button).accessibilityHint = @"Opens this edition of Halo";
	[*button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];

	UIView *fill = [UIView new];
	[fill setContentHuggingPriority:UILayoutPriorityFittingSizeLevel forAxis:UILayoutConstraintAxisVertical];
	stack = [[UIStackView alloc] initWithArrangedSubviews:extra ? @[ info, fill, extra, *button ] : @[ info, fill, *button ]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 18;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	[card addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:24],
		[stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-24],
		[stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:24],
		[stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-24]]];

	/* the whole card plays, except its own controls (the graphics switch) */
	UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:action];
	tap.delegate = self;
	[card addGestureRecognizer:tap];
	card.accessibilityIdentifier = [identifier stringByAppendingString:@".card"];
	return card;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldReceiveTouch:(UITouch *)touch
{
	for (UIView *view = touch.view; view && view != recognizer.view; view = view.superview)
		if ([view isKindOfClass:UIControl.class])
			return NO;
	return YES;
}

/* Xbox only: Original or Sharper, applied the next time Xbox starts. */
- (UIView *)graphicsChoice
{
	UISegmentedControl *choice = [[UISegmentedControl alloc] initWithItems:@[ @"Original", @"Sharper (Preview)" ]];
	UILabel *caption = chooser_label(@"Graphics", UIFontTextStyleFootnote, UIFontWeightSemibold, [UIColor colorWithWhite:0.72 alpha:1]);
	UILabel *note = chooser_label(@"Sharper renders at twice the resolution with 4× texture filtering and needs more GPU power.",
		UIFontTextStyleCaption1, UIFontWeightRegular, [UIColor colorWithWhite:0.72 alpha:1]);
	UIStackView *stack;
	choice.selectedSegmentIndex = HPXboxSharperSelected(NSUserDefaults.standardUserDefaults) ? 1 : 0;
	choice.accessibilityIdentifier = @"engine.xbox.quality";
	choice.accessibilityLabel = @"Xbox graphics";
	choice.selectedSegmentTintColor = [UIColor colorWithRed:0.19 green:0.86 blue:0.94 alpha:1];
	[choice setTitleTextAttributes:@{ NSForegroundColorAttributeName: UIColor.blackColor } forState:UIControlStateSelected];
	[choice setTitleTextAttributes:@{ NSForegroundColorAttributeName: UIColor.whiteColor } forState:UIControlStateNormal];
	[choice addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
		UISegmentedControl *control = action.sender;
		[NSUserDefaults.standardUserDefaults setObject:control.selectedSegmentIndex ? @"sharper" : @"original" forKey:HPXboxQualityKey];
	}] forControlEvents:UIControlEventValueChanged];
	stack = [[UIStackView alloc] initWithArrangedSubviews:@[ caption, choice, note ]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 6;
	return stack;
}

- (UIButton *)footerButton:(NSString *)title symbol:(NSString *)symbol identifier:(NSString *)identifier action:(SEL)action
{
	UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
	UIButton *button;
	configuration.title = title;
	configuration.image = [UIImage systemImageNamed:symbol];
	configuration.imagePadding = 6;
	configuration.baseForegroundColor = [UIColor colorWithRed:0.6 green:0.78 blue:0.95 alpha:1];
	button = [UIButton buttonWithConfiguration:configuration primaryAction:nil];
	button.pointerInteractionEnabled = YES;
	button.accessibilityIdentifier = identifier;
	[button.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
	[button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
	return button;
}

- (void)loadView
{
	UIView *root = [UIView new];
	NSDictionary *build = xbox_build();
	NSString *last = [NSUserDefaults.standardUserDefaults stringForKey:@"HaloPadLastEngine"];
	NSString *app = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
	BOOL pc_ready = self.makePC && pc_has_files(), xbox_ready = xbox_has_maps();
	UIColor *blue = [UIColor colorWithRed:0.42 green:0.7 blue:1 alpha:1], *cyan = [UIColor colorWithRed:0.19 green:0.86 blue:0.94 alpha:1];
	UILabel *brand = chooser_label(@"HALOPAD", UIFontTextStyleFootnote, UIFontWeightBold, [UIColor colorWithRed:0.55 green:0.77 blue:0.94 alpha:1]);
	UILabel *title = chooser_label(@"Choose your edition", UIFontTextStyleLargeTitle, UIFontWeightBold, UIColor.whiteColor);
	UILabel *subtitle = chooser_label(@"Each edition keeps its own saves, settings and multiplayer. You can switch later from ⋯ › Switch Edition.",
		UIFontTextStyleSubheadline, UIFontWeightRegular, [UIColor colorWithWhite:0.7 alpha:1]);
	UIView *pc, *xbox;
	UIStackView *heading, *stack;
	UIImageView *background = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"ChooserBackground"]];
	background.contentMode = UIViewContentModeScaleAspectFill;
	background.clipsToBounds = YES;
	background.isAccessibilityElement = NO;
	background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	background.frame = root.bounds;
	root.backgroundColor = [UIColor colorWithRed:0.008 green:0.02 blue:0.035 alpha:1];
	[root addSubview:background];
	brand.attributedText = [[NSAttributedString alloc] initWithString:@"HALOPAD"
		attributes:@{ NSKernAttributeName: @5 }];

	pc = [self cardTitle:@"Halo Custom Edition" platform:@"WINDOWS" symbol:@"desktopcomputer" accent:blue
		version:@"Version 1.10 · runs natively on Apple silicon"
		about:@"Online multiplayer on community servers, custom maps and the PC game's own menus."
		ready:pc_ready status:!self.makePC ? @"Not included in this build" : pc_ready ? @"Ready to play" : @"Add your game files first"
		play:!self.makePC ? @"Add Custom Edition…" : pc_ready ? @"Play Custom Edition" : @"Set Up Custom Edition" identifier:@"engine.pc" action:@selector(choosePC)
		last:self.makePC && [last isEqual:@"pc"] extra:nil button:&pc_play];
	if (!self.makePC) pc_play.accessibilityHint = @"Explains how to add Custom Edition with PadMint";
	xbox = [self cardTitle:@"Halo: Combat Evolved" platform:[build[@"candidate"] boolValue] ? @"XBOX · PREVIEW" : @"XBOX · EXPERIMENTAL"
		symbol:@"gamecontroller" accent:cyan
		version:[NSString stringWithFormat:@"OpenCE %@ · Metal", xbox_release(build)]
		about:@"The original Xbox campaign and system link, from your own disc."
		ready:xbox_ready status:xbox_ready ? @"Ready to play" : @"Add your Xbox disc image first"
		play:xbox_ready ? @"Play Xbox" : @"Add Your Xbox Disc" identifier:@"engine.xbox" action:@selector(chooseXbox)
		last:[last isEqual:@"xbox"] extra:HPXboxSupportsQuality(build) ? [self graphicsChoice] : nil button:&xbox_play];
	cards = [[UIStackView alloc] initWithArrangedSubviews:@[ pc, xbox ]];
	cards.spacing = 20;
	cards.distribution = UIStackViewDistributionFillEqually;
	cards.alignment = UIStackViewAlignmentFill;

	heading = [[UIStackView alloc] initWithArrangedSubviews:@[ brand, title, subtitle ]];
	heading.axis = UILayoutConstraintAxisVertical;
	heading.spacing = 6;
	[heading setCustomSpacing:26 afterView:brand];
	footer = [[UIStackView alloc] initWithArrangedSubviews:@[
		[self footerButton:@"Update Xbox…" symbol:@"arrow.triangle.2.circlepath" identifier:@"engine.update" action:@selector(showUpdate)],
		[self footerButton:@"About These Builds" symbol:@"info.circle" identifier:@"engine.builds" action:@selector(showBuilds)],
		[self footerButton:@"Project Reach on GitHub" symbol:@"arrow.up.right.square" identifier:@"engine.github" action:@selector(openProject)],
		[UIView new],
		chooser_label([NSString stringWithFormat:@"HaloPad %@ · Bring your own copy of Halo; no game data is included.", app],
			UIFontTextStyleCaption1, UIFontWeightRegular, [UIColor colorWithWhite:0.72 alpha:1]) ]];
	footer.spacing = 8;
	footer.backgroundColor = [UIColor colorWithRed:0.02 green:0.04 blue:0.06 alpha:0.82];
	footer.layer.cornerRadius = 12;
	footer.layoutMargins = UIEdgeInsetsMake(8, 8, 8, 8);
	footer.layoutMarginsRelativeArrangement = YES;
	footer.alignment = UIStackViewAlignmentCenter;
	((UILabel *)footer.arrangedSubviews.lastObject).textAlignment = NSTextAlignmentRight;

	UILabel *update = chooser_label(@"", UIFontTextStyleFootnote, UIFontWeightSemibold, [UIColor colorWithRed:1 green:0.72 blue:0.3 alpha:1]);
	UIStackView *notice = [[UIStackView alloc] initWithArrangedSubviews:@[ update ]];
	notice.backgroundColor = [UIColor colorWithRed:0.02 green:0.04 blue:0.06 alpha:0.9];
	notice.layer.cornerRadius = 12;
	notice.layoutMargins = UIEdgeInsetsMake(12, 14, 12, 14);
	notice.layoutMarginsRelativeArrangement = YES;
	notice.hidden = YES;
	__weak UILabel *weak_update = update;
	__weak UIView *weak_notice = notice;
	xbox_check_upstream(build, ^(NSString *message) { weak_update.text = message; weak_notice.hidden = NO; });
	stack = [[UIStackView alloc] initWithArrangedSubviews:@[ heading, cards, notice, footer ]];
	stack.axis = UILayoutConstraintAxisVertical;
	stack.spacing = 24;
	stack.translatesAutoresizingMaskIntoConstraints = NO;
	UIScrollView *scroll = [UIScrollView new];
	UIView *content = [UIView new];
	scroll.translatesAutoresizingMaskIntoConstraints = NO;
	scroll.alwaysBounceVertical = NO;
	content.translatesAutoresizingMaskIntoConstraints = NO;
	[root addSubview:scroll];
	[scroll addSubview:content];
	[content addSubview:stack];
	[NSLayoutConstraint activateConstraints:@[
		[scroll.leadingAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.leadingAnchor],
		[scroll.trailingAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.trailingAnchor],
		[scroll.topAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.topAnchor],
		[scroll.bottomAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.bottomAnchor],
		[content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
		[content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
		[content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
		[content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
		[content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
		[content.heightAnchor constraintGreaterThanOrEqualToAnchor:scroll.frameLayoutGuide.heightAnchor],
		[stack.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
		[stack.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
		[stack.topAnchor constraintGreaterThanOrEqualToAnchor:content.topAnchor constant:24],
		[stack.bottomAnchor constraintLessThanOrEqualToAnchor:content.bottomAnchor constant:-24],
		[stack.widthAnchor constraintLessThanOrEqualToConstant:1040],
		[stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:content.leadingAnchor constant:24],
		[stack.trailingAnchor constraintLessThanOrEqualToAnchor:content.trailingAnchor constant:-24]]];
	NSLayoutConstraint *height = [content.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor];
	height.priority = UILayoutPriorityDefaultLow;
	height.active = YES;
	NSLayoutConstraint *width = [stack.widthAnchor constraintEqualToAnchor:content.widthAnchor constant:-64];
	width.priority = UILayoutPriorityDefaultHigh;
	width.active = YES;
	self.view = root;
	/* development: HALOPAD_CHOOSE=pc or xbox presses that card once the picker is up */
	if (getenv("HALOPAD_CHOOSE") && (!strcmp(getenv("HALOPAD_CHOOSE"), "pc") || !strcmp(getenv("HALOPAD_CHOOSE"), "xbox")))
	{
		UIButton *play = strcmp(getenv("HALOPAD_CHOOSE"), "xbox") ? pc_play : xbox_play;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
			[play sendActionsForControlEvents:UIControlEventTouchUpInside];
		});
	}
}

- (void)viewDidLayoutSubviews
{
	[super viewDidLayoutSubviews];
	BOOL narrow = self.view.bounds.size.width < 700 || UIContentSizeCategoryIsAccessibilityCategory(self.traitCollection.preferredContentSizeCategory);
	cards.distribution = narrow ? UIStackViewDistributionFill : UIStackViewDistributionFillEqually;
	cards.axis = narrow ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
	footer.alignment = narrow ? UIStackViewAlignmentFill : UIStackViewAlignmentCenter;
	footer.axis = narrow ? UILayoutConstraintAxisVertical : UILayoutConstraintAxisHorizontal;
	((UILabel *)footer.arrangedSubviews.lastObject).textAlignment = narrow ? NSTextAlignmentCenter : NSTextAlignmentRight;
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	if (appeared) return;
	appeared = YES;
	if (UIAccessibilityIsReduceMotionEnabled()) return;
	cards.alpha = 0;
	cards.transform = CGAffineTransformMakeTranslation(0, 10);
	[UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut animations:^{
		self->cards.alpha = 1;
		self->cards.transform = CGAffineTransformIdentity;
	} completion:nil];
}

- (void)openProject
{
	[UIApplication.sharedApplication openURL:[NSURL URLWithString:HPProjectURL] options:@{} completionHandler:nil];
}

- (void)showUpdate
{
	NSString *message = [NSString stringWithFormat:@"Installed: OpenCE %@.\n\nOn your Mac, open PadMint, select HaloPad and the same platform, then select %@. PadMint builds the latest Xbox release. Combined builds reuse verified Custom Edition work.\n\nInstall over the existing app with the same signing identity. Keep your imported files and profiles; do not delete HaloPad. Xbox checkpoints may need a level restart after an engine update.\n\nIf the update fails, keep playing your installed build and report the build log.", xbox_release(xbox_build()), self.makePC ? @"your original PC installer with product-key.txt beside it" : @"your Xbox ISO or XISO (no PC installer or product key needed)"];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Update Xbox with PadMint" message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"Update Guide" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
		[UIApplication.sharedApplication openURL:[NSURL URLWithString:[HPProjectURL stringByAppendingString:@"#updating-halopad"]] options:@{} completionHandler:nil];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)showBuilds
{
	NSDictionary *build = xbox_build();
	NSString *revision = build[@"revision"] ?: @"unknown";
	NSString *message = [NSString stringWithFormat:@"Windows: %@\n\n"
		@"Xbox: Halo: Combat Evolved on OpenCE %@ (%@, built %@), drawn through Metal.%@ The Xbox edition is experimental; full campaign progression and every system link setup are not yet verified on iPad.\n\n"
		@"The two editions cannot play together. Each keeps its own saves; Xbox saves are backed up whenever its engine changes.\n\nProject Reach: %@",
		self.makePC ? @"Halo Custom Edition 1.10, translated to run natively on Apple silicon with Metal." : @"Not included. Build with your PC installer in PadMint to add Custom Edition; your Xbox files stay in place.",
		xbox_release(build), [revision substringToIndex:MIN((NSUInteger)8, revision.length)], build[@"built"] ?: @"locally",
		[build[@"candidate"] boolValue] ? @" This is a preview build." : @"", HPProjectURL];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"About These Builds" message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"Open GitHub" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self openProject]; }]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)show:(UIViewController *)controller
{
	if (choosing || !controller)
		return;
	choosing = YES;
	UIWindow *window = self.view.window;
	[NSUserDefaults.standardUserDefaults setObject:[controller isKindOfClass:HPXboxViewController.class] ? @"xbox" : @"pc" forKey:@"HaloPadLastEngine"];
	window.rootViewController = controller;
}

- (void)choosePC
{
	if (self.makePC) { [self show:self.makePC()]; return; }
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Add Custom Edition"
		message:@"In PadMint on your Mac, select HaloPad and your original HaloCESetup.exe, with product-key.txt beside it. This builds both editions. Install over this app with the same signing identity to keep your Xbox maps, saves and settings. Do not delete HaloPad."
		preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:@"Build Guide" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self openProject]; }]];
	[alert addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}
- (void)chooseXbox
{
	HPXboxViewController *controller = [HPXboxViewController new];
	__weak UIWindow *window = self.view.window;
	controller.returnToChooser = ^{
		self->choosing = NO;
		window.rootViewController = self;
	};
	[self show:controller];
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
@end

/* HALOPAD_ENGINE=pc or xbox skips the picker (development and tests) */
UIViewController *HPEngineChooserMake(UIViewController *(^makePC)(void))
{
	const char *engine = getenv("HALOPAD_ENGINE");
	HPEngineChooser *chooser;
	if (makePC && engine && !strcmp(engine, "pc"))
		return makePC();
	if (engine && !strcmp(engine, "xbox"))
		return [HPXboxViewController new];
	chooser = [HPEngineChooser new];
	chooser.makePC = makePC;
	return chooser;
}
