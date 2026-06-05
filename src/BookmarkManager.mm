/**
 * @file      BookmarkManager.mm
 * @project   BuildBrowser
 * @brief     Bookmark persistence with CRUD operations and folder support.
 *
 * @details   Persists bookmarks to a per-profile plist file via NSKeyedArchiver.
 *            Supports folders (default @"Favorites"), duplicate detection by URL,
 *            and automatic save-on-mutate semantics. The BookmarkManager is
 *            accessed through a per-profile singleton keyed by the active
 *            Profile's UUID.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#import "BookmarkManager.h"
#import "ProfileManager.h"

#pragma mark - Bookmark Implementation

@implementation Bookmark

+ (BOOL)supportsSecureCoding {
  return YES;
}

/**
 * @brief   Initialize with title and URL in the @"Favorites" folder.
 *
 * @param   title  The bookmark display title.
 * @param   url    The bookmark URL.
 * @return  An initialized Bookmark in the Favorites folder.
 */
- (instancetype)initWithTitle:(NSString *)title url:(NSString *)url {
  return [self initWithTitle:title url:url folder:@"Favorites"];
}

/**
 * @brief   Initialize with title, URL, and custom folder.
 *
 * @param   title  The bookmark display title.
 * @param   url    The bookmark URL.
 * @param   folder The folder name (default @"Favorites" if empty).
 * @return  An initialized Bookmark.
 */
- (instancetype)initWithTitle:(NSString*)title url:(NSString*)url folder:(NSString*)folder {
  self = [super init];
  if (self) {
    _title = title;
    _url = url;
    _folder = folder.length ? folder : @"Favorites";
    _dateAdded = [NSDate date];
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)c {
  self = [super init];
  if (self) {
    _title = [c decodeObjectOfClass:[NSString class] forKey:@"title"];
    _url = [c decodeObjectOfClass:[NSString class] forKey:@"url"];
    _folder = [c decodeObjectOfClass:[NSString class] forKey:@"folder"] ?: @"Favorites";
    _dateAdded = [c decodeObjectOfClass:[NSDate class] forKey:@"dateAdded"];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)c {
  [c encodeObject:_title forKey:@"title"];
  [c encodeObject:_url forKey:@"url"];
  [c encodeObject:_folder forKey:@"folder"];
  [c encodeObject:_dateAdded forKey:@"dateAdded"];
}

@end

#pragma mark - Private Interface

@interface BookmarkManager ()
@property (strong) NSMutableArray<Bookmark*>* mutableBookmarks;
@property (copy) NSString* rootPath;
@end

#pragma mark - BookmarkManager Implementation

@implementation BookmarkManager

/**
 * @brief   Returns the per-profile shared bookmark manager instance.
 *
 * @details One instance is created and cached per profile UUID.
 *
 * @return  The shared BookmarkManager, or nil if no active profile.
 */
+ (instancetype)profileShared {
    static NSMutableDictionary* instances;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ instances = [NSMutableDictionary new]; });

    Profile* p = [ProfileManager shared].activeProfile;
    if (!p) return nil;

    if (!instances[p.uuid]) {
        instances[p.uuid] = [[BookmarkManager alloc] initWithRootPath:[p dataDirectory]];
    }
    return instances[p.uuid];
}

/**
 * @brief   Initialize with a root path for the bookmarks plist.
 *
 * @param   path  The profile's data directory.
 * @return  An initialized BookmarkManager (loads existing bookmarks).
 */
- (instancetype)initWithRootPath:(NSString*)path {
    self = [super init];
    if (self) {
        _rootPath = path;
        _mutableBookmarks = [NSMutableArray new];
        [self load];
    }
    return self;
}

/// Returns the immutable bookmarks array.
- (NSArray<Bookmark *> *)bookmarks {
  return _mutableBookmarks;
}

/**
 * @brief   Add a bookmark to the Favorites folder (skips duplicates).
 *
 * @param   title  The bookmark title.
 * @param   url    The bookmark URL. No-op if already bookmarked.
 */
- (void)addBookmarkWithTitle:(NSString *)title url:(NSString *)url {
  [self addBookmarkWithTitle:title url:url folder:@"Favorites"];
}

/**
 * @brief   Add a bookmark to a specific folder (skips duplicates).
 *
 * @param   title  The bookmark title.
 * @param   url    The bookmark URL. No-op if already bookmarked.
 * @param   folder The folder name.
 */
- (void)addBookmarkWithTitle:(NSString*)title url:(NSString*)url folder:(NSString*)folder {
  if ([self isBookmarked:url])
    return;
  [_mutableBookmarks addObject:[[Bookmark alloc] initWithTitle:title url:url folder:folder]];
  [self save];
}

/**
 * @brief   Update a bookmark's title and URL (preserving folder).
 *
 * @param   index The index of the bookmark to update.
 * @param   title The new title (uses existing if empty).
 * @param   url   The new URL (must not be empty).
 */
- (void)updateBookmarkAtIndex:(NSInteger)index title:(NSString*)title url:(NSString*)url {
  [self updateBookmarkAtIndex:index title:title url:url folder:nil];
}

/**
 * @brief   Update a bookmark's title, URL, and folder.
 *
 * @param   index  The index of the bookmark to update.
 * @param   title  The new title (uses existing if empty).
 * @param   url    The new URL (must not be empty).
 * @param   folder The new folder (uses @"Favorites" if empty).
 */
- (void)updateBookmarkAtIndex:(NSInteger)index title:(NSString*)title url:(NSString*)url folder:(NSString*)folder {
  if (index < 0 || index >= (NSInteger)_mutableBookmarks.count || !url.length)
    return;
  Bookmark* bm = _mutableBookmarks[index];
  bm.title = title.length ? title : url;
  bm.url = url;
  if (folder) bm.folder = folder.length ? folder : @"Favorites";
  [self save];
}

/**
 * @brief   Remove the bookmark at the given index.
 *
 * @param   index The index of the bookmark to remove.
 */
- (void)removeBookmarkAtIndex:(NSInteger)index {
  if (index < 0 || index >= (NSInteger)_mutableBookmarks.count)
    return;
  [_mutableBookmarks removeObjectAtIndex:index];
  [self save];
}

/**
 * @brief   Check if a URL is already bookmarked.
 *
 * @param   url The URL string to check.
 * @return  YES if the URL exists in any bookmark, NO otherwise.
 */
- (BOOL)isBookmarked:(NSString *)url {
  for (Bookmark *b in _mutableBookmarks)
    if ([b.url isEqualToString:url])
      return YES;
  return NO;
}

/**
 * @brief   Get all unique folder names, sorted alphabetically.
 *
 * @return  Array of folder name strings.
 */
- (NSArray<NSString*>*)folders {
  NSMutableSet<NSString*>* set = [NSMutableSet setWithObject:@"Favorites"];
  for (Bookmark* b in _mutableBookmarks) {
    if (b.folder.length) [set addObject:b.folder];
  }
  return [[set allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

/**
 * @brief   Persist bookmarks to disk via NSKeyedArchiver.
 */
- (void)save {
  NSError *err;
  NSData *data = [NSKeyedArchiver archivedDataWithRootObject:_mutableBookmarks
                                       requiringSecureCoding:YES
                                                       error:&err];
  if (data)
    [data writeToFile:[self filePath] atomically:YES];
}

/**
 * @brief   Load bookmarks from disk via NSKeyedUnarchiver.
 */
- (void)load {
  NSData *data = [NSData dataWithContentsOfFile:[self filePath]];
  if (!data)
    return;
  NSError *err;
  NSArray *arr =
      [NSKeyedUnarchiver unarchivedArrayOfObjectsOfClass:[Bookmark class]
                                                fromData:data
                                                   error:&err];
  if (arr)
    [_mutableBookmarks addObjectsFromArray:arr];
}

/// Full path to the bookmarks.plist file.
- (NSString *)filePath {
  return [_rootPath stringByAppendingPathComponent:@"bookmarks.plist"];
}

@end
