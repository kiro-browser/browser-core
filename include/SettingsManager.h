/**
 * @file      SettingsManager.h
 * @project   BuildBrowser
 * @brief     User-configurable settings with per-profile persistence.
 *
 * @details   Stores settings in a per-profile settings.plist file, backed
 *            by an NSMutableDictionary. Covers general (homepage, search),
 *            privacy (JS, pop-ups, private browsing, ad block), appearance
 *            (bookmarks bar), and updates (feed URL, auto-check). Defaults
 *            are applied on first load and can be restored via resetToDefaults.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#pragma once
#import <Foundation/Foundation.h>

/**
 * @interface SettingsManager
 * @brief     Per-profile settings manager with dict-backed key-value storage.
 *
 * @details   All settings are stored under keys with the @"KBrowser." prefix
 *            in a settings.plist file. Accessor macros (STR_PREF, BOOL_PREF)
 *            generate the property getter/setter pairs automatically.
 *            A notification named @"BuildBrowserSettingsDidChangeNotification"
 *            is posted by the SettingsPanel when the user commits changes.
 */
@interface SettingsManager : NSObject

/**
 * @brief   Returns the per-profile shared settings manager instance.
 * @return  The shared SettingsManager, or nil if no active profile exists.
 */
+ (instancetype)profileShared;

/**
 * @brief   Initialize with a custom root directory (for testing or per-profile).
 * @param   path  The directory path where settings.plist is stored.
 * @return  An initialized SettingsManager.
 */
- (instancetype)initWithRootPath:(NSString*)path;

// ───────────────────────────────────────────────────────────────────────────────
// @name General Settings
// ───────────────────────────────────────────────────────────────────────────────

/// The homepage URL opened in new windows / last-tab (default: @"buildbrowser://start").
@property (copy) NSString* homepage;
/// The search engine URL template with %@ as the query placeholder (default: DuckDuckGo).
@property (copy) NSString* searchEngineURL;
/// Dictionary mapping aliases to @{ @"url", @"search" } entries for domain launchers.
@property (copy) NSDictionary* domainLaunchers;
/// URL of the update manifest feed (default: GitHub raw manifest.json).
@property (copy) NSString* updateFeedURL;

// ───────────────────────────────────────────────────────────────────────────────
// @name Privacy Settings
// ───────────────────────────────────────────────────────────────────────────────

/// Whether JavaScript is enabled in web views (default: YES).
@property (assign) BOOL javascriptEnabled;
/// Whether pop-up windows are blocked (default: YES).
@property (assign) BOOL blockPopups;
/// Whether private browsing mode is active (default: NO).
@property (assign) BOOL privateBrowsing;
/// Whether built-in ad/tracker blocking is enabled (default: YES).
@property (assign) BOOL adBlockEnabled;
/// Whether to automatically check for updates on launch (default: YES).
@property (assign) BOOL autoCheckUpdates;

// ───────────────────────────────────────────────────────────────────────────────
// @name Appearance Settings
// ───────────────────────────────────────────────────────────────────────────────

/// Whether the bookmarks bar is visible (default: YES).
@property (assign) BOOL showBookmarksBar;
/// Whether the in-window left sidebar is visible (default: NO).
@property (assign) BOOL showSidebar;

/**
 * @brief   Reset all settings to their default values.
 * @details Clears the in-memory dictionary and reloads defaults, then persists.
 */
- (void)resetToDefaults;

@end
