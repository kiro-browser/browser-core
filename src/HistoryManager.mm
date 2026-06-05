/**
 * @file      HistoryManager.mm
 * @project   BuildBrowser
 * @brief     Browsing history persistence with dedup and size limits.
 *
 * @details   Records page visits to a per-profile plist file. Deduplicates
 *            entries for the same URL visited on the same calendar day.
 *            Trims the oldest entries when exceeding kHistoryMaxEntries (2000).
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#import "HistoryManager.h"
#import "ProfileManager.h"

/// Maximum number of history entries retained.
static const NSInteger kMaxEntries = 2000;

#pragma mark - HistoryEntry

@implementation HistoryEntry

+ (BOOL)supportsSecureCoding {
  return YES;
}

/**
 * @brief   Initialize a history entry with title and URL.
 *
 * @details Sets visitDate to the current date and time.
 *
 * @param   title  The page title.
 * @param   url    The page URL.
 * @return  An initialized HistoryEntry.
 */
- (instancetype)initWithTitle:(NSString *)title url:(NSString *)url {
  self = [super init];
  if (self) {
    _title = title;
    _url = url;
    _visitDate = [NSDate date];
  }
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)c {
  self = [super init];
  if (self) {
    _title = [c decodeObjectOfClass:[NSString class] forKey:@"title"];
    _url = [c decodeObjectOfClass:[NSString class] forKey:@"url"];
    _visitDate = [c decodeObjectOfClass:[NSDate class] forKey:@"visitDate"];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)c {
  [c encodeObject:_title forKey:@"title"];
  [c encodeObject:_url forKey:@"url"];
  [c encodeObject:_visitDate forKey:@"visitDate"];
}

@end

#pragma mark - Private Interface

@interface HistoryManager ()
@property(strong) NSMutableArray<HistoryEntry *> *mutableEntries;
@property(copy) NSString* rootPath;
@end

#pragma mark - HistoryManager Implementation

@implementation HistoryManager

/**
 * @brief   Returns the per-profile shared history manager instance.
 *
 * @details One instance is created and cached per profile UUID.
 *
 * @return  The shared HistoryManager, or nil if no active profile.
 */
+ (instancetype)profileShared {
    static NSMutableDictionary* instances;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ instances = [NSMutableDictionary new]; });

    Profile* p = [ProfileManager shared].activeProfile;
    if (!p) return nil;

    if (!instances[p.uuid]) {
        instances[p.uuid] = [[HistoryManager alloc] initWithRootPath:[p dataDirectory]];
    }
    return instances[p.uuid];
}

/**
 * @brief   Initialize with a root path for the history plist.
 *
 * @details Loads existing history from disk.
 *
 * @param   path  The profile's data directory.
 * @return  An initialized HistoryManager.
 */
- (instancetype)initWithRootPath:(NSString*)path {
    self = [super init];
    if (self) {
        _rootPath = path;
        _mutableEntries = [NSMutableArray new];
        [self load];
    }
    return self;
}

/// Returns the immutable entries array (newest first).
- (NSArray<HistoryEntry *> *)entries {
  return _mutableEntries;
}

/**
 * @brief   Record a page visit in history.
 *
 * @details Skips about: and buildbrowser: scheme URLs. Deduplicates any
 *          existing entry for the same URL visited today, inserts at index 0
 *          (newest first), and trims to kMaxEntries.
 *
 * @param   title  The page title.
 * @param   url    The page URL.
 */
- (void)recordVisitWithTitle:(NSString *)title url:(NSString *)url {
  if (!url.length || [url hasPrefix:@"about:"] || [url hasPrefix:@"buildbrowser:"])
    return;

  // Remove any existing entry for the same URL visited today.
  NSCalendar *cal = [NSCalendar currentCalendar];
  [_mutableEntries
      filterUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(
                                            HistoryEntry *e, NSDictionary *_) {
        if (![e.url isEqualToString:url])
          return YES;
        return ![cal isDateInToday:e.visitDate];
      }]];

  HistoryEntry *entry = [[HistoryEntry alloc] initWithTitle:title url:url];
  [_mutableEntries insertObject:entry atIndex:0];

  // Trim to the maximum allowed count.
  if ((NSInteger)_mutableEntries.count > kMaxEntries)
    [_mutableEntries
        removeObjectsInRange:NSMakeRange(kMaxEntries,
                                         _mutableEntries.count - kMaxEntries)];

  [self save];
}

/**
 * @brief   Remove all history entries.
 */
- (void)clearAll {
  [_mutableEntries removeAllObjects];
  [self save];
}

/**
 * @brief   Persist history to disk via NSKeyedArchiver.
 */
- (void)save {
  NSError *err;
  NSData *data = [NSKeyedArchiver archivedDataWithRootObject:_mutableEntries
                                       requiringSecureCoding:YES
                                                       error:&err];
  if (data)
    [data writeToFile:[self filePath] atomically:YES];
}

/**
 * @brief   Load history from disk via NSKeyedUnarchiver.
 */
- (void)load {
  NSData *data = [NSData dataWithContentsOfFile:[self filePath]];
  if (!data)
    return;
  NSError *err;
  NSArray *arr =
      [NSKeyedUnarchiver unarchivedArrayOfObjectsOfClass:[HistoryEntry class]
                                                fromData:data
                                                   error:&err];
  if (arr)
    [_mutableEntries addObjectsFromArray:arr];
}

/// Full path to the history.plist file.
- (NSString *)filePath {
  return [_rootPath stringByAppendingPathComponent:@"history.plist"];
}

@end
