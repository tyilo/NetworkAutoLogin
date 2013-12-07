#include <signal.h>

#import <SystemConfiguration/SystemConfiguration.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#import "NSData+BSSID.h"

#define AIRPORT_CONNECTED 1
#define AIRPORT_KEY @"State:/Network/Interface/en1/AirPort"
#define IP_KEY @"State:/Network/Global/IPv4"
#define CONFIG_PATH [NSHomeDirectory() stringByAppendingPathComponent:@".networkautologin.js"]
#define EXAMPLE_CONFIG_PATH @"./resources/config.js"
#define PATH_ENV [[NSProcessInfo processInfo] environment][@"PATH"]

#define NOT_CONNECTED_ERROR 99

NSString *oldBSSID;

static NSDictionary *getAirportStatus(SCDynamicStoreRef dynStore) {
	return (__bridge NSDictionary *)SCDynamicStoreCopyValue(dynStore, (__bridge CFStringRef)AIRPORT_KEY);
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
				task.launchPath = @"resources/casperjs/bin/casperjs";
				task.arguments = @[@"resources/autologin.js", CONFIG_PATH, SSID, BSSID];
				
				[task launch];
				
				while([task isRunning]) {
					system("killall -9 'Captive Network Assistant' &> /dev/null");
					usleep(250 * 1000);
				}
				
				result = [task terminationStatus];
				
				if(result != NOT_CONNECTED_ERROR) {
					break;
				}
				
				sleep(1);
			}
			
			if(result != EXIT_SUCCESS) {
				system("open -a 'Captive Network Assistant' &");
			}
			NSLog(@"Done.");
		}
		
		oldBSSID = BSSID;
	} else {
		oldBSSID = nil;
	}
}

static void callback(SCDynamicStoreRef dynStore, CFArrayRef changedKeys, void *info) {
	for(NSString *key in (__bridge NSArray *)changedKeys) {
		if([key isEqualToString:AIRPORT_KEY] || [key isEqualToString:IP_KEY]) {
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
		(__bridge CFStringRef)AIRPORT_KEY,
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

int main(int argc, const char * argv[]) {
	@autoreleasepool {
		chdir([[[NSBundle mainBundle] bundlePath] UTF8String]);
		
		if(![[NSFileManager defaultManager] fileExistsAtPath:CONFIG_PATH]) {
			[[NSFileManager defaultManager] copyItemAtPath:EXAMPLE_CONFIG_PATH toPath:CONFIG_PATH error:nil];
			NSLog(@"~/.networkautologin.js doesn't exist, creating...");
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
