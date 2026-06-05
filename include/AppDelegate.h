/**
 * @file      AppDelegate.h
 * @project   BuildBrowser
 * @brief     Application lifecycle delegate for BuildBrowser.
 *
 * @details   Handles application launch, menu bar construction, session
 *            save/restore, URL/file open requests, and default browser prompts.
 *            This is the root controller instantiated by main.mm.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#pragma once
#import <Cocoa/Cocoa.h>

/**
 * @interface AppDelegate
 * @brief     The NSApplication delegate managing the app lifecycle.
 *
 * @details   Conforms to NSApplicationDelegate to receive launch, terminate,
 *            and open-file events. Owns a mutable array of
 *            BrowserWindowController instances (one per window).
 */
@interface AppDelegate : NSObject <NSApplicationDelegate>
@end
