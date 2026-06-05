/**
 * @file      SettingsManager.mm
 * @project   BuildBrowser
 * @brief     Per-profile settings persistence with property-based accessors.
 *
 * @details   Stores all settings in a per-profile settings.plist file
 *            backed by an NSMutableDictionary. Uses C preprocessor macros
 *            (STR_PREF, BOOL_PREF) to auto-generate getter/setter pairs
 *            that persist on every mutation. Default values are applied on
 *            first load and can be restored via resetToDefaults.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#import "SettingsManager.h"

/// NSUserDefaults/plist keys for all settings (prefix @"KBrowser.").
static NSString* const kHomepage        = @"KBrowser.homepage";
static NSString* const kSearchEngine    = @"KBrowser.searchEngineURL";
static NSString* const kDomainLaunchers = @"KBrowser.domainLaunchers";
static NSString* const kUpdateFeedURL   = @"KBrowser.updateFeedURL";
static NSString* const kJavascript      = @"KBrowser.javascriptEnabled";
static NSString* const kBlockPopups     = @"KBrowser.blockPopups";
static NSString* const kPrivateBrowsing = @"KBrowser.privateBrowsing";
static NSString* const kBookmarksBar    = @"KBrowser.showBookmarksBar";
static NSString* const kSidebar         = @"KBrowser.showSidebar";
static NSString* const kAdBlock         = @"KBrowser.adBlockEnabled";
static NSString* const kAutoCheckUpdates = @"KBrowser.autoCheckUpdates";

/// Default values.
static NSString* const kDefaultHomepage  = @"buildbrowser://start";
static NSString* const kLegacyLocalUpdateFeed = @"http://127.0.0.1:8787/manifest.json";
static NSString* const kDefaultUpdateFeed = @"https://raw.githubusercontent.com/kiro-browser/browser-core/dev/updates/manifest.json";

/**
 * @brief   Returns the default domain launcher dictionary.
 *
 * @details Each entry maps an alias (e.g. @"github") to an NSDictionary
 *          with @"url" (the destination URL) and optionally @"search"
 *          (a search URL template with %@ placeholder).
 *
 * @return  NSDictionary of default domain launcher entries.
 */
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

#pragma mark - Private Interface

@interface SettingsManager ()
@property (strong) NSMutableDictionary* settings;
@property (copy) NSString* rootPath;
@end

#pragma mark - Implementation

@implementation SettingsManager

/**
 * @brief   Returns the per-profile shared settings manager instance.
 *
 * @return  The shared SettingsManager, or nil if no active profile.
 */
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

/**
 * @brief   Initialize with a root path for the settings plist.
 *
 * @param   path  The profile's data directory.
 * @return  An initialized SettingsManager.
 */
- (instancetype)initWithRootPath:(NSString*)path {
    self = [super init];
    if (self) {
        _rootPath = path;
        [self load];
    }
    return self;
}

/**
 * @brief   Load settings from disk, merging in defaults for any missing keys.
 */
- (void)load {
    NSString* path = [self filePath];
    _settings = [[NSMutableDictionary alloc] initWithContentsOfFile:path] ?: [NSMutableDictionary new];

    /// Default values applied for any missing keys.
    NSDictionary* defaults = @{
        kHomepage:        kDefaultHomepage,
        kSearchEngine:    @"https://duckduckgo.com/?q=%@",
        kDomainLaunchers: DefaultDomainLaunchers(),
        kUpdateFeedURL:   kDefaultUpdateFeed,
        kJavascript:      @YES,
        kBlockPopups:     @YES,
        kPrivateBrowsing: @NO,
        kBookmarksBar:    @YES,
        kSidebar:         @NO,
        kAdBlock:         @YES,
        kAutoCheckUpdates:@YES,
    };

    for (NSString* key in defaults) {
        if (!_settings[key]) _settings[key] = defaults[key];
    }

    // Migrate old DuckDuckGo start page URL to internal scheme.
    if ([_settings[kHomepage] isEqualToString:@"https://start.duckduckgo.com"])
        _settings[kHomepage] = kDefaultHomepage;

    // Migrate legacy local update feed to public GitHub URL.
    NSString* updateFeed = _settings[kUpdateFeedURL];
    if (![updateFeed isKindOfClass:[NSString class]] || !updateFeed.length)
        _settings[kUpdateFeedURL] = kDefaultUpdateFeed;
    else if ([updateFeed isEqualToString:kLegacyLocalUpdateFeed])
        _settings[kUpdateFeedURL] = kDefaultUpdateFeed;
}

/**
 * @brief   Persist the settings dictionary to disk immediately.
 */
- (void)save {
    [_settings writeToFile:[self filePath] atomically:YES];
}

/// Full path to the settings.plist file.
- (NSString*)filePath {
    return [_rootPath stringByAppendingPathComponent:@"settings.plist"];
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Accessors (auto-generated by macros)
// ───────────────────────────────────────────────────────────────────────────────

/// Macro for string-typed settings properties (getter + setter).
#define STR_PREF(getter, setter, key) \
- (NSString*)getter { return _settings[key]; } \
- (void)setter:(NSString*)v { _settings[key] = v; [self save]; }

/// Macro for boolean-typed settings properties (getter + setter).
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
BOOL_PREF(showSidebar,       setShowSidebar,       kSidebar)
BOOL_PREF(adBlockEnabled,    setAdBlockEnabled,    kAdBlock)
BOOL_PREF(autoCheckUpdates,  setAutoCheckUpdates,  kAutoCheckUpdates)

/**
 * @brief   Get domain launchers dictionary (with type safety).
 *
 * @return  The launchers dictionary, or the defaults if corrupt.
 */
- (NSDictionary*)domainLaunchers {
    NSDictionary* launchers = _settings[kDomainLaunchers];
    return [launchers isKindOfClass:[NSDictionary class]] ? launchers : DefaultDomainLaunchers();
}

/**
 * @brief   Set domain launchers dictionary (with type safety).
 *
 * @param   launchers  The new launchers dictionary.
 */
- (void)setDomainLaunchers:(NSDictionary*)launchers {
    _settings[kDomainLaunchers] = [launchers isKindOfClass:[NSDictionary class]] ? launchers : DefaultDomainLaunchers();
    [self save];
}

/**
 * @brief   Reset all settings to defaults.
 *
 * @details Clears the dictionary and reloads defaults, then persists.
 */
- (void)resetToDefaults {
    [_settings removeAllObjects];
    [self load];
    [self save];
}

@end
