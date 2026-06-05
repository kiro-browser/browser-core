/**
 * @file      DefaultBrowserManager.h
 * @project   BuildBrowser
 * @brief     macOS default browser registration via Launch Services.
 *
 * @details   Wraps deprecated-but-functional Core Services / Launch Services
 *           (LSRegisterURL, LSSetDefaultHandlerForURLScheme) to register
 *           BuildBrowser as the system default for http:, https: schemes and
 *           public.html/public.xhtml content types.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#pragma once
#import <Foundation/Foundation.h>

/**
 * @interface DefaultBrowserManager
 * @brief     Utility class for checking and setting the default browser.
 *
 * @details   All methods are class-level. Uses LSRegisterURL and
 *            LSSetDefaultHandlerForURLScheme under the hood (with
 *            deprecation warnings suppressed). Compares the bundle
 *            identifier against the current HTTP/HTTPS handler.
 */
@interface DefaultBrowserManager : NSObject

/**
 * @brief   Check whether BuildBrowser is currently the default browser.
 * @details Compares the main bundle identifier against the current handler
 *          for both http: and https: URL schemes.
 * @return  YES if BuildBrowser handles both http and https, NO otherwise.
 */
+ (BOOL)isDefaultBrowser;

/**
 * @brief   Register BuildBrowser as the default browser for all web schemes.
 * @details Registers the app bundle with Launch Services, then sets the
 *          default handler for http:, https:, public.html, and public.xhtml.
 *
 * @param   error  On failure, populated with an NSError describing the issue.
 * @return  YES if all registrations succeeded, NO otherwise.
 */
+ (BOOL)setAsDefaultBrowserWithError:(NSError**)error;

/**
 * @brief   A human-readable status string describing default browser state.
 * @return  @"BuildBrowser is your default browser" or
 *          @"BuildBrowser is not your default browser".
 */
+ (NSString*)statusText;

@end
