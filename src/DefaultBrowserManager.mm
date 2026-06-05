/**
 * @file      DefaultBrowserManager.mm
 * @project   BuildBrowser
 * @brief     macOS default browser registration via Launch Services.
 *
 * @details   Uses the C-based Launch Services API (LSRegisterURL,
 *            LSSetDefaultHandlerForURLScheme) to register BuildBrowser
 *            as the system default browser. Suppresses deprecation warnings
 *            since no modern replacement is available for this functionality.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#import "DefaultBrowserManager.h"
#import <AppKit/AppKit.h>
#import <CoreServices/CoreServices.h>

#pragma mark - Implementation

@implementation DefaultBrowserManager

/**
 * @brief   Retrieve the current default handler for a URL scheme.
 *
 * @param   scheme  The URL scheme as a CFString (e.g. CFSTR("http")).
 * @return  The bundle identifier of the application currently handling
 *          that scheme, or nil if none is registered.
 *
 * @note    Uses LSCopyDefaultHandlerForURLScheme which is deprecated but
 *          still functional as of macOS 15.
 */
+ (NSString*)defaultHandlerForURLScheme:(CFStringRef)scheme {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return CFBridgingRelease(LSCopyDefaultHandlerForURLScheme(scheme));
#pragma clang diagnostic pop
}

/**
 * @brief   Create a standard NSError for default-browser failures.
 *
 * @param   message  The localized description.
 * @param   code     The error code.
 * @param   details  Optional recovery suggestion.
 * @return  A configured NSError with domain @"BuildBrowserDefaultBrowser".
 */
+ (NSError*)errorWithMessage:(NSString*)message code:(NSInteger)code details:(NSString*)details {
    NSMutableDictionary* userInfo = [@{ NSLocalizedDescriptionKey: message } mutableCopy];
    if (details.length) userInfo[NSLocalizedRecoverySuggestionErrorKey] = details;
    return [NSError errorWithDomain:@"BuildBrowserDefaultBrowser" code:code userInfo:userInfo];
}

/**
 * @brief   Check if BuildBrowser is the default handler for http and https.
 *
 * @details Compares the main bundle identifier against the current
 *          http: and https: URL scheme handlers.
 *
 * @return  YES if both schemes are handled by BuildBrowser, NO otherwise.
 */
+ (BOOL)isDefaultBrowser {
    NSString* bundleID = NSBundle.mainBundle.bundleIdentifier;
    if (!bundleID.length) return NO;

    NSString* httpHandler = [self defaultHandlerForURLScheme:CFSTR("http")];
    NSString* httpsHandler = [self defaultHandlerForURLScheme:CFSTR("https")];
    return [httpHandler isEqualToString:bundleID] && [httpsHandler isEqualToString:bundleID];
}

/**
 * @brief   Register BuildBrowser as the default browser for web schemes.
 *
 * @details Registers the app bundle with Launch Services, then sets the
 *          default handler for http:, https:, public.html, and public.xhtml.
 *          All four must succeed for the method to return YES.
 *
 * @param   error  Out-parameter populated on failure with a descriptive error.
 * @return  YES if all registrations succeeded, NO otherwise.
 */
+ (BOOL)setAsDefaultBrowserWithError:(NSError**)error {
    NSString* bundleID = NSBundle.mainBundle.bundleIdentifier;
    if (!bundleID.length) {
        if (error) *error = [self errorWithMessage:@"BuildBrowser does not have a bundle identifier." code:-1 details:nil];
        return NO;
    }

    // Register the app bundle with Launch Services so it can be recognized.
    NSURL* bundleURL = NSBundle.mainBundle.bundleURL;
    OSStatus registerStatus = bundleURL ? LSRegisterURL((__bridge CFURLRef)bundleURL, true) : -1;
    if (registerStatus != noErr) {
        if (error) {
            NSString* details = [NSString stringWithFormat:@"Launch Services could not register %@. OSStatus: %d", bundleURL.path ?: @"the app bundle", (int)registerStatus];
            *error = [self errorWithMessage:@"macOS could not register BuildBrowser as an app that can open links." code:(NSInteger)registerStatus details:details];
        }
        return NO;
    }

    // Set default handlers for URL schemes and content types.
    OSStatus httpStatus = LSSetDefaultHandlerForURLScheme(CFSTR("http"), (__bridge CFStringRef)bundleID);
    OSStatus httpsStatus = LSSetDefaultHandlerForURLScheme(CFSTR("https"), (__bridge CFStringRef)bundleID);
    OSStatus htmlStatus = LSSetDefaultRoleHandlerForContentType(CFSTR("public.html"), kLSRolesViewer, (__bridge CFStringRef)bundleID);
    OSStatus xhtmlStatus = LSSetDefaultRoleHandlerForContentType(CFSTR("public.xhtml"), kLSRolesViewer, (__bridge CFStringRef)bundleID);
    if (httpStatus == noErr && httpsStatus == noErr && htmlStatus == noErr && xhtmlStatus == noErr) return YES;

    // Build a detailed error if any registration failed.
    if (error) {
        NSString* details = [NSString stringWithFormat:@"Bundle ID: %@. http OSStatus: %d. https OSStatus: %d. public.html OSStatus: %d. public.xhtml OSStatus: %d.", bundleID, (int)httpStatus, (int)httpsStatus, (int)htmlStatus, (int)xhtmlStatus];
        OSStatus status = httpStatus != noErr ? httpStatus : (httpsStatus != noErr ? httpsStatus : (htmlStatus != noErr ? htmlStatus : xhtmlStatus));
        *error = [self errorWithMessage:@"macOS could not set BuildBrowser as the default browser." code:(NSInteger)status details:details];
    }
    return NO;
}

/**
 * @brief   Returns a human-readable string describing default browser status.
 *
 * @return  Status text suitable for display in the settings panel.
 */
+ (NSString*)statusText {
    return [self isDefaultBrowser] ? @"BuildBrowser is your default browser" : @"BuildBrowser is not your default browser";
}

@end
