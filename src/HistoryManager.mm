#import "HistoryManager.h"

static const NSInteger kMaxEntries = 2000;

// ── HistoryEntry
// ──────────────────────────────────────────────────────────────

@implementation HistoryEntry

+ (BOOL)supportsSecureCoding {
  return YES;
}

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

// ── HistoryManager
// ────────────────────────────────────────────────────────────

#import "ProfileManager.h"

@interface HistoryManager ()
@property(strong) NSMutableArray<HistoryEntry *> *mutableEntries;
@property(copy) NSString* rootPath;
@end

@implementation HistoryManager

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

- (instancetype)initWithRootPath:(NSString*)path {
    self = [super init];
    if (self) {
        _rootPath = path;
        _mutableEntries = [NSMutableArray new];
        [self load];
    }
    return self;
}

- (NSArray<HistoryEntry *> *)entries {
  return _mutableEntries;
}

- (void)recordVisitWithTitle:(NSString *)title url:(NSString *)url {
  if (!url.length || [url hasPrefix:@"about:"] || [url hasPrefix:@"buildbrowser:"])
    return;

  // Deduplicate: remove existing entry for same URL visited today
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

  // Trim to max
  if ((NSInteger)_mutableEntries.count > kMaxEntries)
    [_mutableEntries
        removeObjectsInRange:NSMakeRange(kMaxEntries,
                                         _mutableEntries.count - kMaxEntries)];

  [self save];
}

- (void)clearAll {
  [_mutableEntries removeAllObjects];
  [self save];
}

- (void)save {
  NSError *err;
  NSData *data = [NSKeyedArchiver archivedDataWithRootObject:_mutableEntries
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
      [NSKeyedUnarchiver unarchivedArrayOfObjectsOfClass:[HistoryEntry class]
                                                fromData:data
                                                   error:&err];
  if (arr)
    [_mutableEntries addObjectsFromArray:arr];
}

- (NSString *)filePath {
  return [_rootPath stringByAppendingPathComponent:@"history.plist"];
}
@end
