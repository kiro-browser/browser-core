/**
 * @file      HistoryManager.h
 * @project   BuildBrowser
 * @brief     Browsing history persistence and management.
 *
 * @details   Records page visits with title, URL, and timestamp. Persists
 *            to ~/Library/Application Support/BuildBrowser/Profiles/<uuid>/
 *            history.plist. Keeps the 2000 most recent entries and
 *            auto-deduplicates by URL within the same calendar day.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#pragma once
#import <Foundation/Foundation.h>

/// Maximum number of history entries kept in the store.
static const NSInteger kHistoryMaxEntries = 2000;

#pragma mark - HistoryEntry Model

/**
 * @interface HistoryEntry
 * @brief     A single browsing history entry.
 *
 * @details   Conforms to NSSecureCoding. Stores the page title, URL, and
 *            the date/time of the visit. Entries are ordered newest-first.
 */
@interface HistoryEntry : NSObject <NSSecureCoding>

/// The page title at the time of visit.
@property (copy)   NSString* title;
/// The full URL string of the visited page.
@property (copy)   NSString* url;
/// The date and time when the visit occurred.
@property (strong) NSDate*   visitDate;

/**
 * @brief   Initialize a history entry with title and URL.
 * @details Sets visitDate to the current date/time.
 * @param   title  The page title.
 * @param   url    The page URL.
 * @return  A fully initialized HistoryEntry.
 */
- (instancetype)initWithTitle:(NSString*)title url:(NSString*)url;

@end

#pragma mark - HistoryManager

/**
 * @interface HistoryManager
 * @brief     Manages browsing history for the active profile.
 *
 * @details   Persists history to a per-profile plist file. Automatically
 *            loads on init and saves after every mutation. Deduplicates
 *            entries for the same URL visited on the same day. Trims
 *            to kHistoryMaxEntries (2000) on each insert.
 */
@interface HistoryManager : NSObject

/**
 * @brief   Returns the per-profile shared history manager instance.
 * @details The instance is keyed by the active Profile's UUID.
 * @return  The shared HistoryManager, or nil if no active profile exists.
 */
+ (instancetype)profileShared;

/// All history entries, ordered newest first.
@property (readonly) NSArray<HistoryEntry*>* entries;

/**
 * @brief   Initialize with a custom root directory.
 * @param   path  The directory path where history.plist is stored.
 * @return  An initialized HistoryManager.
 */
- (instancetype)initWithRootPath:(NSString*)path;

/**
 * @brief   Record a page visit in history.
 * @details Skips about: and buildbrowser: scheme URLs. Deduplicates any
 *          existing entry for the same URL visited today, inserts the new
 *          entry at index 0, and trims to the maximum allowed count.
 *
 * @param   title  The page title.
 * @param   url    The page URL.
 */
- (void)recordVisitWithTitle:(NSString*)title url:(NSString*)url;

/**
 * @brief   Remove all history entries and persist the empty list.
 */
- (void)clearAll;

/**
 * @brief   Immediately persist the current history to disk.
 */
- (void)save;

@end
