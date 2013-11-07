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

NSString *oldBSSID;

static void cleanUp()
{
	system("xargs kill < $TMPDIR/killscript_pid &> /dev/null");
}

static void checkUpdate(SCDynamicStoreRef dynStore) {
	NSDictionary *airportStatus = (__bridge NSDictionary *)SCDynamicStoreCopyValue(dynStore, (__bridge CFStringRef)AIRPORT_KEY);
	
	NSString *SSID = [airportStatus objectForKey:@"SSID_STR"];
	NSString *BSSID = [[airportStatus objectForKey:@"BSSID"] BSSIDString];
	
	int powerStatus = [[airportStatus objectForKey:@"Power Status"] intValue];
	
	if(powerStatus == AIRPORT_CONNECTED) {
		if(BSSID && !([BSSID isEqualToString:oldBSSID])) {
			printf("Running script...\n");
			
			// Force quit or else it will disconnect from the network
			system("(while ! killall -9 'Captive Network Assistant' &> /dev/null; do sleep 0.5; done) & echo $! > $TMPDIR/killscript_pid");
			
			int result = system([[NSString stringWithFormat:@"PATH=resources:$PATH resources/casperjs/bin/casperjs resources/autologin.js '%@' '%@' '%@'", CONFIG_PATH, SSID, BSSID, nil] UTF8String]);
			
			cleanUp();
			
			if(result != EXIT_SUCCESS) {
				system("open -a 'Captive Network Assistant' &");
			}
			printf("Done.\n");
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

SCDynamicStoreRef setupInterfaceWatch(void) {
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

int main(int argc, const char * argv[])
{
	
	@autoreleasepool {
		signal(SIGINT, cleanUp);
		signal(SIGTERM, cleanUp);
	    
		chdir([[[NSBundle mainBundle] bundlePath] UTF8String]);
		
		if(![[NSFileManager defaultManager] fileExistsAtPath:CONFIG_PATH]) {
			[[NSFileManager defaultManager] copyItemAtPath:EXAMPLE_CONFIG_PATH toPath:CONFIG_PATH error:nil];
			printf("~/.networkautologin.js doesn't exist, creating...\n");
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
