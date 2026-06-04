#import "BookmarkManager.h"

// ── Bookmark
// ──────────────────────────────────────────────────────────────────

@implementation Bookmark

+ (BOOL)supportsSecureCoding {
  return YES;
}

- (instancetype)initWithTitle:(NSString *)title url:(NSString *)url {
  return [self initWithTitle:title url:url folder:@"Favorites"];
}

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

// ── BookmarkManager
// ───────────────────────────────────────────────────────────

#import "ProfileManager.h"

@interface BookmarkManager ()
@property (strong) NSMutableArray<Bookmark*>* mutableBookmarks;
@property (copy) NSString* rootPath;
@end

@implementation BookmarkManager

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

- (instancetype)initWithRootPath:(NSString*)path {
    self = [super init];
    if (self) {
        _rootPath = path;
        _mutableBookmarks = [NSMutableArray new];
        [self load];
    }
    return self;
}

- (NSArray<Bookmark *> *)bookmarks {
  return _mutableBookmarks;
}

- (void)addBookmarkWithTitle:(NSString *)title url:(NSString *)url {
  [self addBookmarkWithTitle:title url:url folder:@"Favorites"];
}

- (void)addBookmarkWithTitle:(NSString*)title url:(NSString*)url folder:(NSString*)folder {
  if ([self isBookmarked:url])
    return;
  [_mutableBookmarks addObject:[[Bookmark alloc] initWithTitle:title url:url folder:folder]];
  [self save];
}

- (void)updateBookmarkAtIndex:(NSInteger)index title:(NSString*)title url:(NSString*)url {
  [self updateBookmarkAtIndex:index title:title url:url folder:nil];
}

- (void)updateBookmarkAtIndex:(NSInteger)index title:(NSString*)title url:(NSString*)url folder:(NSString*)folder {
  if (index < 0 || index >= (NSInteger)_mutableBookmarks.count || !url.length)
    return;
  Bookmark* bm = _mutableBookmarks[index];
  bm.title = title.length ? title : url;
  bm.url = url;
  if (folder) bm.folder = folder.length ? folder : @"Favorites";
  [self save];
}

- (void)removeBookmarkAtIndex:(NSInteger)index {
  if (index < 0 || index >= (NSInteger)_mutableBookmarks.count)
    return;
  [_mutableBookmarks removeObjectAtIndex:index];
  [self save];
}

- (BOOL)isBookmarked:(NSString *)url {
  for (Bookmark *b in _mutableBookmarks)
    if ([b.url isEqualToString:url])
      return YES;
  return NO;
}

- (NSArray<NSString*>*)folders {
  NSMutableSet<NSString*>* set = [NSMutableSet setWithObject:@"Favorites"];
  for (Bookmark* b in _mutableBookmarks) {
    if (b.folder.length) [set addObject:b.folder];
  }
  return [[set allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (void)save {
  NSError *err;
  NSData *data = [NSKeyedArchiver archivedDataWithRootObject:_mutableBookmarks
                                       requiringSecureCoding:YES
                                                       error:&err];
  if (data)
    [data writeToFile:[self filePath] atomically:YES];
}

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

- (NSString *)filePath {
  return [_rootPath stringByAppendingPathComponent:@"bookmarks.plist"];
}
@end
