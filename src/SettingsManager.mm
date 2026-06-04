#import "SettingsManager.h"

static NSString* const kHomepage        = @"KBrowser.homepage";
static NSString* const kSearchEngine    = @"KBrowser.searchEngineURL";
static NSString* const kDomainLaunchers = @"KBrowser.domainLaunchers";
static NSString* const kUpdateFeedURL   = @"KBrowser.updateFeedURL";
static NSString* const kJavascript      = @"KBrowser.javascriptEnabled";
static NSString* const kBlockPopups     = @"KBrowser.blockPopups";
static NSString* const kPrivateBrowsing = @"KBrowser.privateBrowsing";
static NSString* const kBookmarksBar    = @"KBrowser.showBookmarksBar";
static NSString* const kAdBlock         = @"KBrowser.adBlockEnabled";
static NSString* const kAutoCheckUpdates = @"KBrowser.autoCheckUpdates";
static NSString* const kDefaultHomepage = @"buildbrowser://start";
static NSString* const kDefaultUpdateFeed = @"http://127.0.0.1:8787/manifest.json";

static NSDictionary* DefaultDomainLaunchers(void) {
    return @{
        @"github":   @{ @"url": @"https://github.com", @"search": @"https://github.com/search?q=%@" },
        @"mail":     @{ @"url": @"https://mail.google.com", @"search": @"https://mail.google.com/mail/u/0/#search/%@" },
        @"calendar": @{ @"url": @"https://calendar.google.com", @"search": @"https://calendar.google.com" },
        @"youtube":  @{ @"url": @"https://youtube.com", @"search": @"https://www.youtube.com/results?search_query=%@" },
        @"maps":     @{ @"url": @"https://maps.google.com", @"search": @"https://www.google.com/maps/search/%@" },
        @"docs":     @{ @"url": @"https://docs.google.com", @"search": @"https://drive.google.com/drive/search?q=%@" },
        @"drive":    @{ @"url": @"https://drive.google.com", @"search": @"https://drive.google.com/drive/search?q=%@" },
        @"reddit":   @{ @"url": @"https://reddit.com", @"search": @"https://www.reddit.com/search/?q=%@" },
        @"wiki":     @{ @"url": @"https://wikipedia.org", @"search": @"https://en.wikipedia.org/w/index.php?search=%@" },
    };
}

#import "ProfileManager.h"

@interface SettingsManager ()
@property (strong) NSMutableDictionary* settings;
@property (copy) NSString* rootPath;
@end

@implementation SettingsManager

+ (instancetype)profileShared {
    static NSMutableDictionary* instances;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ instances = [NSMutableDictionary new]; });
    
    Profile* p = [ProfileManager shared].activeProfile;
    if (!p) return nil;
    
    if (!instances[p.uuid]) {
        instances[p.uuid] = [[SettingsManager alloc] initWithRootPath:[p dataDirectory]];
    }
    return instances[p.uuid];
}

- (instancetype)initWithRootPath:(NSString*)path {
    self = [super init];
    if (self) {
        _rootPath = path;
        [self load];
    }
    return self;
}

- (void)load {
    NSString* path = [self filePath];
    _settings = [[NSMutableDictionary alloc] initWithContentsOfFile:path] ?: [NSMutableDictionary new];
    
    // Default values if not present
    NSDictionary* defaults = @{
        kHomepage:        kDefaultHomepage,
        kSearchEngine:    @"https://duckduckgo.com/?q=%@",
        kDomainLaunchers: DefaultDomainLaunchers(),
        kUpdateFeedURL:   kDefaultUpdateFeed,
        kJavascript:      @YES,
        kBlockPopups:     @YES,
        kPrivateBrowsing: @NO,
        kBookmarksBar:    @YES,
        kAdBlock:         @YES,
        kAutoCheckUpdates:@YES,
    };
    
    for (NSString* key in defaults) {
        if (!_settings[key]) _settings[key] = defaults[key];
    }
    if ([_settings[kHomepage] isEqualToString:@"https://start.duckduckgo.com"])
        _settings[kHomepage] = kDefaultHomepage;
    NSString* updateFeed = _settings[kUpdateFeedURL];
    if (![updateFeed isKindOfClass:[NSString class]] || !updateFeed.length)
        _settings[kUpdateFeedURL] = kDefaultUpdateFeed;
}

- (void)save {
    [_settings writeToFile:[self filePath] atomically:YES];
}

- (NSString*)filePath {
    return [_rootPath stringByAppendingPathComponent:@"settings.plist"];
}

// ── Accessors backed by NSUserDefaults ────────────────────────────────────────

#define STR_PREF(getter, setter, key) \
- (NSString*)getter { return _settings[key]; } \
- (void)setter:(NSString*)v { _settings[key] = v; [self save]; }

#define BOOL_PREF(getter, setter, key) \
- (BOOL)getter { return [_settings[key] boolValue]; } \
- (void)setter:(BOOL)v { _settings[key] = @(v); [self save]; }

STR_PREF(homepage,        setHomepage,        kHomepage)
STR_PREF(searchEngineURL, setSearchEngineURL, kSearchEngine)
STR_PREF(updateFeedURL,   setUpdateFeedURL,   kUpdateFeedURL)
BOOL_PREF(javascriptEnabled, setJavascriptEnabled, kJavascript)
BOOL_PREF(blockPopups,       setBlockPopups,       kBlockPopups)
BOOL_PREF(privateBrowsing,   setPrivateBrowsing,   kPrivateBrowsing)
BOOL_PREF(showBookmarksBar,  setShowBookmarksBar,  kBookmarksBar)
BOOL_PREF(adBlockEnabled,    setAdBlockEnabled,    kAdBlock)
BOOL_PREF(autoCheckUpdates,  setAutoCheckUpdates,  kAutoCheckUpdates)

- (NSDictionary*)domainLaunchers {
    NSDictionary* launchers = _settings[kDomainLaunchers];
    return [launchers isKindOfClass:[NSDictionary class]] ? launchers : DefaultDomainLaunchers();
}

- (void)setDomainLaunchers:(NSDictionary*)launchers {
    _settings[kDomainLaunchers] = [launchers isKindOfClass:[NSDictionary class]] ? launchers : DefaultDomainLaunchers();
    [self save];
}

- (void)resetToDefaults {
    [_settings removeAllObjects];
    [self load];
    [self save];
}
@end
