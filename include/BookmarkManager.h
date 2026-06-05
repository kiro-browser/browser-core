/**
 * @file      BookmarkManager.h
 * @project   BuildBrowser
 * @brief     Bookmark data model and persistence manager.
 *
 * @details   Provides the `Bookmark` model class (NSSecureCoding compliant)
 *            and the `BookmarkManager` singleton that persists bookmarks to
 *            per-profile plist files. Supports folders, CRUD operations,
 *            and duplicate detection.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#pragma once
#import <Foundation/Foundation.h>

#pragma mark - Bookmark Model

/**
 * @interface Bookmark
 * @brief     A single bookmark entry with title, URL, folder, and date.
 *
 * @details   Conforms to NSSecureCoding for secure archiving to disk.
 *            Each bookmark belongs to a folder (default @"Favorites").
 */
@interface Bookmark : NSObject <NSSecureCoding>

/// The display title of the bookmark (e.g. "GitHub").
@property (copy) NSString* title;
/// The full URL string of the bookmark.
@property (copy) NSString* url;
/// The folder/group this bookmark belongs to (default @"Favorites").
@property (copy) NSString* folder;
/// The date and time when the bookmark was created.
@property (strong) NSDate* dateAdded;

/**
 * @brief   Initialize a bookmark with title and URL in @"Favorites".
 * @param   title  The bookmark display title.
 * @param   url    The bookmark URL string.
 * @return  A fully initialized Bookmark instance.
 */
- (instancetype)initWithTitle:(NSString*)title url:(NSString*)url;

/**
 * @brief   Initialize a bookmark with title, URL, and custom folder.
 * @param   title  The bookmark display title.
 * @param   url    The bookmark URL string.
 * @param   folder The folder name (e.g. @"Work", @"School").
 * @return  A fully initialized Bookmark instance.
 */
- (instancetype)initWithTitle:(NSString*)title url:(NSString*)url folder:(NSString*)folder;

@end

#pragma mark - Bookmark Manager

/**
 * @interface BookmarkManager
 * @brief     Manages bookmark persistence for the active profile.
 *
 * @details   Persists bookmarks to ~/Library/Application Support/BuildBrowser/
 *            Profiles/<uuid>/bookmarks.plist via NSKeyedArchiver.
 *            Accessed through +profileShared which returns a per-profile
 *            singleton. Automatically loads on init and saves on every mutation.
 */
@interface BookmarkManager : NSObject

/**
 * @brief   Returns the per-profile shared bookmark manager instance.
 * @details The instance is keyed by the active Profile's UUID. A separate
 *          manager exists for each profile.
 * @return  The shared BookmarkManager, or nil if no active profile exists.
 */
+ (instancetype)profileShared;

/// All bookmarks for this profile, ordered by insertion.
@property (readonly) NSArray<Bookmark*>* bookmarks;

/**
 * @brief   Initialize with a custom root directory (for testing or per-profile).
 * @param   path  The directory path where bookmarks.plist is stored.
 * @return  An initialized BookmarkManager.
 */
- (instancetype)initWithRootPath:(NSString*)path;

/**
 * @brief   Add a bookmark with title and URL to the @"Favorites" folder.
 * @param   title  The bookmark title.
 * @param   url    The bookmark URL. Duplicate URLs are silently ignored.
 */
- (void)addBookmarkWithTitle:(NSString*)title url:(NSString*)url;

/**
 * @brief   Add a bookmark with title, URL, and specific folder.
 * @param   title  The bookmark title.
 * @param   url    The bookmark URL. Duplicate URLs are silently ignored.
 * @param   folder The folder to place the bookmark in.
 */
- (void)addBookmarkWithTitle:(NSString*)title url:(NSString*)url folder:(NSString*)folder;

/**
 * @brief   Update a bookmark's title and URL (preserving existing folder).
 * @param   index The index of the bookmark to update.
 * @param   title The new title (empty string leaves the existing title).
 * @param   url   The new URL (must not be empty).
 */
- (void)updateBookmarkAtIndex:(NSInteger)index title:(NSString*)title url:(NSString*)url;

/**
 * @brief   Update a bookmark's title, URL, and folder.
 * @param   index  The index of the bookmark to update.
 * @param   title  The new title (empty string leaves the existing title).
 * @param   url    The new URL (must not be empty).
 * @param   folder The new folder name.
 */
- (void)updateBookmarkAtIndex:(NSInteger)index title:(NSString*)title url:(NSString*)url folder:(NSString*)folder;

/**
 * @brief   Remove the bookmark at the given index.
 * @param   index The index of the bookmark to remove.
 */
- (void)removeBookmarkAtIndex:(NSInteger)index;

/**
 * @brief   Check whether a URL is already bookmarked.
 * @param   url The URL string to check.
 * @return  YES if the URL exists in any bookmark, NO otherwise.
 */
- (BOOL)isBookmarked:(NSString*)url;

/**
 * @brief   Get all unique folder names across bookmarks, sorted alphabetically.
 * @return  An array of folder name strings.
 */
- (NSArray<NSString*>*)folders;

/**
 * @brief   Immediately persist the current bookmarks to disk.
 * @details Called automatically by all mutation methods. Explicit calls
 *          are useful before the app terminates.
 */
- (void)save;

@end
