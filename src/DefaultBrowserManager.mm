#import "DefaultBrowserManager.h"
#import <AppKit/AppKit.h>
#import <CoreServices/CoreServices.h>

@implementation DefaultBrowserManager

+ (NSError*)errorWithMessage:(NSString*)message code:(NSInteger)code details:(NSString*)details {
    NSMutableDictionary* userInfo = [@{ NSLocalizedDescriptionKey: message } mutableCopy];
    if (details.length) userInfo[NSLocalizedRecoverySuggestionErrorKey] = details;
    return [NSError errorWithDomain:@"BuildBrowserDefaultBrowser" code:code userInfo:userInfo];
}

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
        if (error) *error = [self errorWithMessage:@"BuildBrowser does not have a bundle identifier." code:-1 details:nil];
        return NO;
    }

    NSURL* bundleURL = NSBundle.mainBundle.bundleURL;
    OSStatus registerStatus = bundleURL ? LSRegisterURL((__bridge CFURLRef)bundleURL, true) : -1;
    if (registerStatus != noErr) {
        if (error) {
            NSString* details = [NSString stringWithFormat:@"Launch Services could not register %@. OSStatus: %d", bundleURL.path ?: @"the app bundle", (int)registerStatus];
            *error = [self errorWithMessage:@"macOS could not register BuildBrowser as an app that can open links." code:(NSInteger)registerStatus details:details];
        }
        return NO;
    }

    OSStatus httpStatus = LSSetDefaultHandlerForURLScheme(CFSTR("http"), (__bridge CFStringRef)bundleID);
    OSStatus httpsStatus = LSSetDefaultHandlerForURLScheme(CFSTR("https"), (__bridge CFStringRef)bundleID);
    if (httpStatus == noErr && httpsStatus == noErr) return YES;

    if (error) {
        NSString* details = [NSString stringWithFormat:@"Bundle ID: %@. http OSStatus: %d. https OSStatus: %d.", bundleID, (int)httpStatus, (int)httpsStatus];
        *error = [self errorWithMessage:@"macOS could not set BuildBrowser as the default browser." code:(NSInteger)(httpStatus != noErr ? httpStatus : httpsStatus) details:details];
    }
    return NO;
}

+ (NSString*)statusText {
    return [self isDefaultBrowser] ? @"BuildBrowser is your default browser" : @"BuildBrowser is not your default browser";
}

@end
