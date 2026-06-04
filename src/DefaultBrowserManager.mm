#import "DefaultBrowserManager.h"
#import <AppKit/AppKit.h>
#import <CoreServices/CoreServices.h>

@implementation DefaultBrowserManager

+ (BOOL)isDefaultBrowser {
    NSString* bundleID = NSBundle.mainBundle.bundleIdentifier;
    if (!bundleID.length) return NO;

    NSURL* httpAppURL = [NSWorkspace.sharedWorkspace URLForApplicationToOpenURL:[NSURL URLWithString:@"http://example.com"]];
    NSURL* httpsAppURL = [NSWorkspace.sharedWorkspace URLForApplicationToOpenURL:[NSURL URLWithString:@"https://example.com"]];
    NSString* httpHandler = httpAppURL ? [NSBundle bundleWithURL:httpAppURL].bundleIdentifier : nil;
    NSString* httpsHandler = httpsAppURL ? [NSBundle bundleWithURL:httpsAppURL].bundleIdentifier : nil;
    return [httpHandler isEqualToString:bundleID] && [httpsHandler isEqualToString:bundleID];
}

+ (BOOL)setAsDefaultBrowserWithError:(NSError**)error {
    NSString* bundleID = NSBundle.mainBundle.bundleIdentifier;
    if (!bundleID.length) {
        if (error) {
            *error = [NSError errorWithDomain:@"BuildBrowserDefaultBrowser"
                                         code:-1
                                     userInfo:@{ NSLocalizedDescriptionKey: @"BuildBrowser does not have a bundle identifier." }];
        }
        return NO;
    }

    OSStatus httpStatus = LSSetDefaultHandlerForURLScheme(CFSTR("http"), (__bridge CFStringRef)bundleID);
    OSStatus httpsStatus = LSSetDefaultHandlerForURLScheme(CFSTR("https"), (__bridge CFStringRef)bundleID);
    if (httpStatus == noErr && httpsStatus == noErr) return YES;

    if (error) {
        *error = [NSError errorWithDomain:@"BuildBrowserDefaultBrowser"
                                     code:(NSInteger)(httpStatus != noErr ? httpStatus : httpsStatus)
                                 userInfo:@{ NSLocalizedDescriptionKey: @"macOS could not set BuildBrowser as the default browser." }];
    }
    return NO;
}

+ (NSString*)statusText {
    return [self isDefaultBrowser] ? @"BuildBrowser is your default browser" : @"BuildBrowser is not your default browser";
}

@end
