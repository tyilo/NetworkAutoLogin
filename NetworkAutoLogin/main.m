#include <signal.h>

#import <SystemConfiguration/SystemConfiguration.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#import "NSData+BSSID.h"

#define AIRPORT_CONNECTED 1
#define AIRPORT_KEY_PATTERN @"State:/Network/Interface/%@/AirPort"
#define IP_KEY @"State:/Network/Global/IPv4"
#define CONFIG_PATH [NSHomeDirectory() stringByAppendingPathComponent:@".networkautologin.js"]
#define EXAMPLE_CONFIG_PATH @"resources/config.js"
#define CASPERJS_BIN_PATH @"resources/casperjs/bin/casperjs"
#define PHANTOMJS_BIN_PATH @"resources/phantomjs"
#define PATH_ENV [[NSProcessInfo processInfo] environment][@"PATH"]

#define EXIT_LOGGED_IN         1
#define EXIT_ALREADY_LOGGED_IN 2
#define EXIT_TIMEOUT           3
#define EXIT_NO_MATCH          4
#define EXIT_NOT_CONNECTED     5

NSString *oldBSSID;
NSString *airportKey;

static NSDictionary *getAirportStatus(SCDynamicStoreRef dynStore) {
	return (__bridge NSDictionary *)SCDynamicStoreCopyValue(dynStore, (__bridge CFStringRef)airportKey);
}

static void checkUpdate(SCDynamicStoreRef dynStore) {
	NSDictionary *airportStatus = getAirportStatus(dynStore);

	NSString *SSID = airportStatus[@"SSID_STR"];
	NSString *BSSID = [airportStatus[@"BSSID"] BSSIDString];

	int powerStatus = [airportStatus[@"Power Status"] intValue];

	if(powerStatus == AIRPORT_CONNECTED) {
		if(BSSID && !([BSSID isEqualToString:oldBSSID])) {
			int result;
			for(int tries = 0; tries < 20; tries++) {
				powerStatus = [getAirportStatus(dynStore)[@"Power Status"] intValue];
				if(powerStatus != AIRPORT_CONNECTED) {
					break;
				}

				NSLog(@"Running script...");

				NSTask *task = [[NSTask alloc] init];
				task.environment = @{@"PATH": [@"resources:" stringByAppendingString:PATH_ENV]};
				task.launchPath = CASPERJS_BIN_PATH;
				task.arguments = @[@"resources/autologin.js", CONFIG_PATH, SSID, BSSID];

				// This is used to get rid of 'CoreText performance note:' error messages from phantomjs
				task.standardError = [NSFileHandle fileHandleWithNullDevice];

				[task launch];

				while([task isRunning]) {
					// While CNA is running, only it will have access to the network
					// and all other requests will fail.
					// Simple solution: KILL IT!
					system("killall 'Captive Network Assistant' &> /dev/null");
					usleep(250 * 1000);
				}

				result = [task terminationStatus];

				if(result != EXIT_TIMEOUT && result != EXIT_NOT_CONNECTED) {
					break;
				}

				sleep(1);
			}

			switch(result) {
				case EXIT_LOGGED_IN:
					NSLog(@"Successfully logged in.");
					break;
				case EXIT_ALREADY_LOGGED_IN:
					NSLog(@"Already logged in.");
					break;
				case EXIT_NO_MATCH:
					NSLog(@"No credentials found for current SSID/BSSID.");
					break;
				case EXIT_TIMEOUT:
					NSLog(@"Timed out while trying to login.");
					break;
				case EXIT_NOT_CONNECTED:
					NSLog(@"Could not connect to the network.");
					break;
			}
		}

		oldBSSID = BSSID;
	} else {
		oldBSSID = nil;
	}
}

static void callback(SCDynamicStoreRef dynStore, CFArrayRef changedKeys, void *info) {
	for(NSString *key in (__bridge NSArray *)changedKeys) {
		if([key isEqualToString:airportKey] || [key isEqualToString:IP_KEY]) {
			checkUpdate(dynStore);
			break;
		}
	}
}

static SCDynamicStoreRef setupInterfaceWatch(void) {
	SCDynamicStoreContext context = {0, NULL, NULL, NULL, NULL};

	SCDynamicStoreRef dynStore = SCDynamicStoreCreate(kCFAllocatorDefault,
													  CFBundleGetIdentifier(CFBundleGetMainBundle()),
													  callback,
													  &context);

	if (!dynStore) {
		NSLog(@"SCDynamicStoreCreate() failed: %s", SCErrorString(SCError()));
		return NULL;
	}

	const CFStringRef keys[] = {
		(__bridge CFStringRef)airportKey,
		(__bridge CFStringRef)IP_KEY
	};

	CFArrayRef watchedKeys = CFArrayCreate(kCFAllocatorDefault,
										   (const void **)keys,
										   2,
										   &kCFTypeArrayCallBacks);

	if (!SCDynamicStoreSetNotificationKeys(dynStore,
										   watchedKeys,
										   NULL)) {
		CFRelease(watchedKeys);
		NSLog(@"SCDynamicStoreSetNotificationKeys() failed: %s", SCErrorString(SCError()));
		CFRelease(dynStore);
		dynStore = NULL;

		return NULL;
	}
	CFRelease(watchedKeys);

	CFRunLoopSourceRef rlSrc = SCDynamicStoreCreateRunLoopSource(kCFAllocatorDefault, dynStore, 0);
	CFRunLoopAddSource(CFRunLoopGetCurrent(), rlSrc, kCFRunLoopDefaultMode);
	CFRelease(rlSrc);

	return dynStore;
}

NSString *getInterfaceName(void) {
	NSPipe *pipe = [NSPipe pipe];

	NSTask *task = [[NSTask alloc] init];
	task.launchPath = @"/sbin/route";
	task.arguments = @[@"get", @"10.10.10.10"];

	task.standardOutput = pipe;

	[task launch];

	NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
	NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^\\s*interface:\\s*(.*)$" options:NSRegularExpressionAnchorsMatchLines error:nil];

	NSTextCheckingResult *result = [regex firstMatchInString:str options:0 range:NSMakeRange(0, [str length])];
	if(!result) {
		return @"en1";
	}

	return [str substringWithRange:[result rangeAtIndex:1]];
}

int main(int argc, const char * argv[]) {
	@autoreleasepool {
		NSString *interfaceName = getInterfaceName();
		NSLog(@"Interface selected for NetworkAutoLogin: %@", interfaceName);

		airportKey = [NSString stringWithFormat:AIRPORT_KEY_PATTERN, interfaceName];

		NSFileManager *fileManager = [NSFileManager defaultManager];

		[fileManager changeCurrentDirectoryPath:[[NSBundle mainBundle] bundlePath]];

		if(![fileManager fileExistsAtPath:CONFIG_PATH]) {
			[fileManager copyItemAtPath:EXAMPLE_CONFIG_PATH toPath:CONFIG_PATH error:nil];
			NSLog(@"~/.networkautologin.js doesn't exist, creating...");
		}

		if(![fileManager fileExistsAtPath:CASPERJS_BIN_PATH]) {
			NSLog(@"casperjs binary not found at '%@/%@'!", [fileManager currentDirectoryPath], CASPERJS_BIN_PATH);
			return EXIT_FAILURE;
		}

		if(![fileManager fileExistsAtPath:CASPERJS_BIN_PATH]) {
			NSLog(@"phantomjs binary not found at '%@/%@'!", [fileManager currentDirectoryPath], CASPERJS_BIN_PATH);
			return EXIT_FAILURE;
		}

		SCDynamicStoreRef dynStore = setupInterfaceWatch();
		if(!dynStore) {
			return EXIT_FAILURE;
		}

		checkUpdate(dynStore);

		CFRunLoopRun();

	}

	return EXIT_SUCCESS;
}
