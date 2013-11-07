#import "NSData+BSSID.h"

@implementation NSData (BSSID)

- (NSString *)BSSIDString {
	const unsigned char *dataBuffer = (const unsigned char *)[self bytes];
	
    if(!dataBuffer) {
        return nil;
	}
	
    NSUInteger dataLength  = [self length];
    NSMutableString *BSSID  = [NSMutableString stringWithCapacity:(dataLength * 2)];
	
    for (int i = 0; i < dataLength; i++) {
		if(i != 0) {
			[BSSID appendString:@":"];
		}
        [BSSID appendFormat:@"%02lX", (unsigned long)dataBuffer[i]];
	}
	
    return [NSString stringWithString:BSSID];
}

@end
