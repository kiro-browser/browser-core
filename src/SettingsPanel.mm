/**
 * @file      SettingsPanel.mm
 * @project   BuildBrowser
 * @brief     Settings sheet with sidebar navigation and content panes.
 *
 * @details   macOS-style settings panel: sidebar on the left with section
 *            names and SF Symbols, content pane on the right. Sections:
 *            General (homepage, search engine, default browser),
 *            Launchers (domain aliases), Privacy (JS, pop-ups, private
 *            browsing, ad block), Updates (feed URL, auto-check),
 *            Appearance (bookmarks bar), Data (clear history, reset).
 *            Presented as a sheet on the browser window.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#import "SettingsManager.h"
#import "HistoryManager.h"
#import "ProfileManager.h"
#import "UpdateManager.h"
#import "DefaultBrowserManager.h"

/// Fallback update feed URL if the user clears the field.
static NSString* const kDefaultUpdateFeedURL = @"https://raw.githubusercontent.com/kiro-browser/browser-core/dev/updates/manifest.json";

#pragma mark - SettingsSidebarItem

/// Simple model object for a sidebar row.
@interface SettingsSidebarItem : NSObject
@property (copy) NSString* label;
@property (copy) NSString* symbol;
+ (instancetype)item:(NSString*)label symbol:(NSString*)sym;
@end
@implementation SettingsSidebarItem
+ (instancetype)item:(NSString*)label symbol:(NSString*)sym {
    SettingsSidebarItem* i = [self new];
    i.label = label; i.symbol = sym; return i;
}
@end

#pragma mark - UI Helpers

/// Creates a rounded group box (macOS settings card style).
static NSView* makeGroupBox(CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    NSView* box = [[NSView alloc] initWithFrame:NSMakeRect(x, y, w, h)];
    box.wantsLayer = YES;
    box.layer.cornerRadius = 10;
    box.layer.backgroundColor = [NSColor colorWithWhite:0.5 alpha:0.08].CGColor;
    box.layer.borderColor     = [NSColor separatorColor].CGColor;
    box.layer.borderWidth     = 0.5;
    return box;
}

/// Creates a horizontal separator line inside a group box.
static NSView* makeSeparator(CGFloat y, CGFloat w) {
    NSView* sep = [[NSView alloc] initWithFrame:NSMakeRect(16, y, w - 32, 1)];
    sep.wantsLayer = YES;
    sep.layer.backgroundColor = [NSColor separatorColor].CGColor;
    return sep;
}

/// Creates a standard row label on the left side of a setting.
static NSTextField* makeRowLabel(NSString* text) {
    NSTextField* f = [NSTextField labelWithString:text];
    f.font = [NSFont systemFontOfSize:13];
    return f;
}

#pragma mark - SettingsPanel

@interface SettingsPanel : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
+ (void)showAsSheetOnWindow:(NSWindow*)parent;
@end

@implementation SettingsPanel {
    // Sidebar
    NSTableView*  _sidebar;
    NSArray*      _sidebarItems;
    // Content host
    NSView*       _contentHost;
    NSArray*      _contentViews;
    // General
    NSTextField*  _homepageField;
    NSTextField*  _searchField;
    NSTextField*  _defaultBrowserStatusLabel;
    NSButton*     _defaultBrowserButton;
    NSTextView*   _launchersTextView;
    // Privacy
    NSButton*     _jsToggle;
    NSButton*     _popupToggle;
    NSButton*     _privateToggle;
    NSButton*     _adBlockToggle;
    // Updates
    NSTextField*  _updateFeedField;
    NSButton*     _autoCheckToggle;
    // Appearance
    NSButton*     _bookmarksBarToggle;
    // General
    NSWindow*     _parentWindow;
}

/**
 * @brief   Returns the shared SettingsPanel singleton.
 *
 * @return  The singleton instance.
 */
+ (instancetype)shared {
    static SettingsPanel* inst;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ inst = [SettingsPanel new]; });
    return inst;
}

/**
 * @brief   Show the settings panel as a sheet on the given window.
 *
 * @param   parent  The parent window to attach the sheet.
 */
+ (void)showAsSheetOnWindow:(NSWindow*)parent {
    SettingsPanel* p = [SettingsPanel shared];
    [p reloadValues];
    p->_parentWindow = parent;
    [parent beginSheet:p.window completionHandler:nil];
}

/**
 * @brief   Initialize the settings window.
 *
 * @return  An initialized SettingsPanel.
 */
- (instancetype)init {
    NSWindow* win = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 620, 420)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
                    backing:NSBackingStoreBuffered defer:NO];
    win.title = @"Settings";
    win.titlebarAppearsTransparent = YES;
    win.movableByWindowBackground  = YES;
    self = [super initWithWindow:win];
    if (!self) return nil;
    [self buildUI];
    return self;
}

// ───────────────────────────────────────────────────────────────────────────────
// @name UI Building
// ───────────────────────────────────────────────────────────────────────────────

/**
 * @brief   Build the complete settings UI: sidebar navigation + content panes.
 */
- (void)buildUI {
    NSView* root = self.window.contentView;
    root.wantsLayer = YES;
    CGFloat W = 620, H = 420;

    // Sidebar (left 160px)
    NSVisualEffectView* sidebarBg = [[NSVisualEffectView alloc]
        initWithFrame:NSMakeRect(0, 0, 160, H)];
    sidebarBg.material     = NSVisualEffectMaterialSidebar;
    sidebarBg.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    sidebarBg.state        = NSVisualEffectStateActive;
    [root addSubview:sidebarBg];

    NSTextField* sideTitle = [NSTextField labelWithString:@"Settings"];
    sideTitle.frame = NSMakeRect(16, H - 52, 128, 22);
    sideTitle.font  = [NSFont boldSystemFontOfSize:15];
    [sidebarBg addSubview:sideTitle];

    NSScrollView* sideScroll = [[NSScrollView alloc]
        initWithFrame:NSMakeRect(0, 0, 160, H - 60)];
    sideScroll.drawsBackground = NO;
    sideScroll.hasVerticalScroller = NO;

    _sidebar = [[NSTableView alloc] initWithFrame:sideScroll.bounds];
    _sidebar.backgroundColor = [NSColor clearColor];
    _sidebar.style = NSTableViewStyleSourceList;
    _sidebar.rowHeight  = 36;
    _sidebar.headerView = nil;
    _sidebar.dataSource = self;
    _sidebar.delegate   = self;
    NSTableColumn* sc = [[NSTableColumn alloc] initWithIdentifier:@"s"];
    sc.width = 160;
    [_sidebar addTableColumn:sc];
    sideScroll.documentView = _sidebar;
    [sidebarBg addSubview:sideScroll];

    _sidebarItems = @[
        [SettingsSidebarItem item:@"General"    symbol:@"house"],
        [SettingsSidebarItem item:@"Launchers"  symbol:@"at"],
        [SettingsSidebarItem item:@"Privacy"    symbol:@"lock.shield"],
        [SettingsSidebarItem item:@"Updates"    symbol:@"arrow.triangle.2.circlepath"],
        [SettingsSidebarItem item:@"Appearance" symbol:@"paintbrush"],
        [SettingsSidebarItem item:@"Data"       symbol:@"internaldrive"],
    ];
    [_sidebar reloadData];
    [_sidebar selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];

    // Vertical divider
    NSView* divider = [[NSView alloc] initWithFrame:NSMakeRect(160, 0, 1, H)];
    divider.wantsLayer = YES;
    divider.layer.backgroundColor = [NSColor separatorColor].CGColor;
    [root addSubview:divider];

    // Content host (right side)
    _contentHost = [[NSView alloc] initWithFrame:NSMakeRect(161, 0, W - 161, H)];
    [root addSubview:_contentHost];

    _contentViews = @[
        [self buildGeneralPane],
        [self buildLaunchersPane],
        [self buildPrivacyPane],
        [self buildUpdatesPane],
        [self buildAppearancePane],
        [self buildDataPane],
    ];
    for (NSView* v in _contentViews) {
        v.frame = _contentHost.bounds;
        v.hidden = YES;
        [_contentHost addSubview:v];
    }
    ((NSView*)_contentViews[0]).hidden = NO;

    // Done button (bottom right, always visible)
    NSButton* done = [NSButton buttonWithTitle:@"Done" target:self action:@selector(done:)];
    done.frame         = NSMakeRect(W - 100, 16, 84, 28);
    done.bezelStyle    = NSBezelStyleRounded;
    done.keyEquivalent = @"\r";
    [root addSubview:done];
}

/** @brief   Build the "General" content pane. */
- (NSView*)buildGeneralPane {
    NSView* v = [NSView new];
    CGFloat W = 459, y = 340;

    NSTextField* title = [NSTextField labelWithString:@"General"];
    title.frame = NSMakeRect(24, y, 400, 24);
    title.font  = [NSFont boldSystemFontOfSize:17];
    [v addSubview:title]; y -= 36;

    NSView* box1 = makeGroupBox(16, y - 44, W - 32, 52);
    [v addSubview:box1];
    NSTextField* hpLabel = makeRowLabel(@"Homepage");
    hpLabel.frame = NSMakeRect(16, 16, 100, 20);
    [box1 addSubview:hpLabel];
    _homepageField = [[NSTextField alloc] initWithFrame:NSMakeRect(120, 14, W - 32 - 136, 22)];
    _homepageField.bezelStyle    = NSTextFieldRoundedBezel;
    _homepageField.focusRingType = NSFocusRingTypeNone;
    _homepageField.font          = [NSFont systemFontOfSize:13];
    [box1 addSubview:_homepageField];
    y -= 64;

    NSView* box2 = makeGroupBox(16, y - 64, W - 32, 72);
    [v addSubview:box2];
    NSTextField* seLabel = makeRowLabel(@"Search URL");
    seLabel.frame = NSMakeRect(16, 34, 100, 20);
    [box2 addSubview:seLabel];
    _searchField = [[NSTextField alloc] initWithFrame:NSMakeRect(120, 32, W - 32 - 136, 22)];
    _searchField.bezelStyle    = NSTextFieldRoundedBezel;
    _searchField.focusRingType = NSFocusRingTypeNone;
    _searchField.font          = [NSFont systemFontOfSize:13];
    [box2 addSubview:_searchField];
    NSTextField* hint = [NSTextField labelWithString:@"Use %@ as the search query placeholder"];
    hint.frame     = NSMakeRect(120, 12, W - 32 - 136, 16);
    hint.font      = [NSFont systemFontOfSize:10];
    hint.textColor = [NSColor secondaryLabelColor];
    [box2 addSubview:hint];
    y -= 84;

    NSView* box3 = makeGroupBox(16, y - 58, W - 32, 58);
    [v addSubview:box3];
    NSTextField* dbLabel = makeRowLabel(@"Default Browser");
    dbLabel.frame = NSMakeRect(16, 30, 160, 18);
    [box3 addSubview:dbLabel];
    _defaultBrowserStatusLabel = [NSTextField labelWithString:@""];
    _defaultBrowserStatusLabel.frame = NSMakeRect(16, 12, W - 32 - 150, 16);
    _defaultBrowserStatusLabel.font = [NSFont systemFontOfSize:11];
    _defaultBrowserStatusLabel.textColor = [NSColor secondaryLabelColor];
    [box3 addSubview:_defaultBrowserStatusLabel];
    _defaultBrowserButton = [NSButton buttonWithTitle:@"Make Default" target:self action:@selector(makeDefaultBrowser:)];
    _defaultBrowserButton.frame = NSMakeRect(W - 32 - 118, 17, 110, 24);
    _defaultBrowserButton.bezelStyle = NSBezelStyleRounded;
    [box3 addSubview:_defaultBrowserButton];

    return v;
}

/** @brief   Build the "Launchers" content pane. */
- (NSView*)buildLaunchersPane {
    NSView* v = [NSView new];
    CGFloat W = 459, y = 340;

    NSTextField* title = [NSTextField labelWithString:@"Launchers"];
    title.frame = NSMakeRect(24, y, 400, 24);
    title.font  = [NSFont boldSystemFontOfSize:17];
    [v addSubview:title]; y -= 32;

    NSTextField* hint = [NSTextField labelWithString:@"One per line: alias = open-url | optional-search-url-with-%@"];
    hint.frame = NSMakeRect(24, y, W - 48, 18);
    hint.font = [NSFont systemFontOfSize:11];
    hint.textColor = [NSColor secondaryLabelColor];
    [v addSubview:hint]; y -= 26;

    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 72, W - 32, y - 72)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    _launchersTextView = [[NSTextView alloc] initWithFrame:scroll.bounds];
    _launchersTextView.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    _launchersTextView.automaticQuoteSubstitutionEnabled = NO;
    _launchersTextView.automaticDashSubstitutionEnabled = NO;
    scroll.documentView = _launchersTextView;
    [v addSubview:scroll];

    NSTextField* examples = [NSTextField labelWithString:@"Example: github = https://github.com | https://github.com/search?q=%@"];
    examples.frame = NSMakeRect(24, 48, W - 48, 16);
    examples.font = [NSFont systemFontOfSize:10];
    examples.textColor = [NSColor tertiaryLabelColor];
    [v addSubview:examples];

    return v;
}

/** @brief   Build the "Privacy" content pane. */
- (NSView*)buildPrivacyPane {
    NSView* v = [NSView new];
    CGFloat W = 459, y = 340;

    NSTextField* title = [NSTextField labelWithString:@"Privacy"];
    title.frame = NSMakeRect(24, y, 400, 24);
    title.font  = [NSFont boldSystemFontOfSize:17];
    [v addSubview:title]; y -= 36;

    NSView* box = makeGroupBox(16, y - 4*44 - 2, W - 32, 4*44 + 2);
    [v addSubview:box];

    NSString* labels[] = { @"Enable JavaScript", @"Block pop-up windows", @"Private browsing", @"Block ads and trackers" };
    NSString* subtitles[] = {
        @"Required by most modern websites",
        @"Prevent sites from opening new windows",
        @"Use temporary website data and skip history",
        @"Apply built-in WebKit content blocking rules"
    };

    for (NSInteger i = 0; i < 4; i++) {
        CGFloat rowY = (3 - i) * 44 + 2;
        if (i > 0) [box addSubview:makeSeparator(rowY + 44, W - 32)];

        NSTextField* lbl = makeRowLabel(labels[i]);
        lbl.frame = NSMakeRect(16, rowY + 22, W - 32 - 60, 18);
        [box addSubview:lbl];

        NSTextField* sub = [NSTextField labelWithString:subtitles[i]];
        sub.frame     = NSMakeRect(16, rowY + 6, W - 32 - 60, 14);
        sub.font      = [NSFont systemFontOfSize:11];
        sub.textColor = [NSColor secondaryLabelColor];
        [box addSubview:sub];

        NSButton* toggle = [NSButton buttonWithTitle:@"" target:nil action:nil];
        toggle.buttonType = NSButtonTypeSwitch;
        toggle.frame      = NSMakeRect(W - 32 - 52, rowY + 14, 44, 22);
        toggle.tag        = i;
        [box addSubview:toggle];

        if (i == 0) _jsToggle      = toggle;
        else if (i == 1) _popupToggle   = toggle;
        else if (i == 2) _privateToggle = toggle;
        else             _adBlockToggle = toggle;
    }

    return v;
}

/** @brief   Build the "Updates" content pane. */
- (NSView*)buildUpdatesPane {
    NSView* v = [NSView new];
    CGFloat W = 459, y = 340;

    NSTextField* title = [NSTextField labelWithString:@"Updates"];
    title.frame = NSMakeRect(24, y, 400, 24);
    title.font  = [NSFont boldSystemFontOfSize:17];
    [v addSubview:title]; y -= 36;

    NSView* box = makeGroupBox(16, y - 88, W - 32, 88);
    [v addSubview:box];

    NSTextField* feedLabel = makeRowLabel(@"Manifest URL");
    feedLabel.frame = NSMakeRect(16, 50, 100, 18);
    [box addSubview:feedLabel];

    _updateFeedField = [[NSTextField alloc] initWithFrame:NSMakeRect(120, 48, W - 32 - 136, 22)];
    _updateFeedField.bezelStyle = NSTextFieldRoundedBezel;
    _updateFeedField.focusRingType = NSFocusRingTypeNone;
    _updateFeedField.font = [NSFont systemFontOfSize:13];
    [box addSubview:_updateFeedField];

    NSTextField* autoLabel = makeRowLabel(@"Auto-check on launch");
    autoLabel.frame = NSMakeRect(16, 18, 180, 18);
    [box addSubview:autoLabel];

    _autoCheckToggle = [NSButton buttonWithTitle:@"" target:nil action:nil];
    _autoCheckToggle.buttonType = NSButtonTypeSwitch;
    _autoCheckToggle.frame = NSMakeRect(W - 32 - 52, 14, 44, 22);
    [box addSubview:_autoCheckToggle];

    NSButton* checkNow = [NSButton buttonWithTitle:@"Check Now" target:self action:@selector(checkNowForUpdates:)];
    checkNow.bezelStyle = NSBezelStyleRounded;
    checkNow.frame = NSMakeRect(W - 32 - 110, 8, 102, 24);
    [box addSubview:checkNow];

    NSTextField* hint = [NSTextField labelWithString:@"Default: GitHub public update manifest"];
    hint.frame = NSMakeRect(24, 48, 280, 16);
    hint.font = [NSFont systemFontOfSize:10];
    hint.textColor = [NSColor secondaryLabelColor];
    [v addSubview:hint];

    return v;
}

/** @brief   Build the "Appearance" content pane. */
- (NSView*)buildAppearancePane {
    NSView* v = [NSView new];
    CGFloat W = 459, y = 340;

    NSTextField* title = [NSTextField labelWithString:@"Appearance"];
    title.frame = NSMakeRect(24, y, 400, 24);
    title.font  = [NSFont boldSystemFontOfSize:17];
    [v addSubview:title]; y -= 36;

    NSView* box = makeGroupBox(16, y - 46, W - 32, 46);
    [v addSubview:box];

    NSTextField* lbl = makeRowLabel(@"Show bookmarks bar");
    lbl.frame = NSMakeRect(16, 14, W - 32 - 60, 18);
    [box addSubview:lbl];

    _bookmarksBarToggle = [NSButton buttonWithTitle:@"" target:nil action:nil];
    _bookmarksBarToggle.buttonType = NSButtonTypeSwitch;
    _bookmarksBarToggle.frame      = NSMakeRect(W - 32 - 52, 12, 44, 22);
    [box addSubview:_bookmarksBarToggle];

    return v;
}

/** @brief   Build the "Data" content pane. */
- (NSView*)buildDataPane {
    NSView* v = [NSView new];
    CGFloat W = 459, y = 340;

    NSTextField* title = [NSTextField labelWithString:@"Data"];
    title.frame = NSMakeRect(24, y, 400, 24);
    title.font  = [NSFont boldSystemFontOfSize:17];
    [v addSubview:title]; y -= 36;

    NSView* box = makeGroupBox(16, y - 96, W - 32, 96);
    [v addSubview:box];

    NSTextField* histLabel = makeRowLabel(@"Browsing History");
    histLabel.frame = NSMakeRect(16, 56, 200, 18);
    [box addSubview:histLabel];
    NSTextField* histSub = [NSTextField labelWithString:@"Visited pages and search queries"];
    histSub.frame = NSMakeRect(16, 40, 240, 14);
    histSub.font  = [NSFont systemFontOfSize:11];
    histSub.textColor = [NSColor secondaryLabelColor];
    [box addSubview:histSub];
    NSButton* clearHist = [NSButton buttonWithTitle:@"Clear…" target:self action:@selector(clearHistory:)];
    clearHist.frame = NSMakeRect(W - 32 - 90, 50, 84, 24);
    clearHist.bezelStyle = NSBezelStyleRounded;
    [box addSubview:clearHist];

    [box addSubview:makeSeparator(44, W - 32)];

    NSTextField* resetLabel = makeRowLabel(@"Reset All Settings");
    resetLabel.frame = NSMakeRect(16, 12, 200, 18);
    [box addSubview:resetLabel];
    NSButton* resetBtn = [NSButton buttonWithTitle:@"Reset…" target:self action:@selector(resetDefaults:)];
    resetBtn.frame = NSMakeRect(W - 32 - 90, 6, 84, 24);
    resetBtn.bezelStyle = NSBezelStyleRounded;
    [box addSubview:resetBtn];

    return v;
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Data Loading
// ───────────────────────────────────────────────────────────────────────────────

/**
 * @brief   Load current setting values into all UI controls.
 */
- (void)reloadValues {
    SettingsManager* s = [SettingsManager profileShared];
    _homepageField.stringValue     = s.homepage ?: @"";
    _searchField.stringValue       = s.searchEngineURL ?: @"";
    _launchersTextView.string      = [self textFromLaunchers:s.domainLaunchers];
    _updateFeedField.stringValue   = s.updateFeedURL ?: @"";
    _jsToggle.state                = s.javascriptEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    _popupToggle.state             = s.blockPopups       ? NSControlStateValueOn : NSControlStateValueOff;
    _privateToggle.state           = s.privateBrowsing   ? NSControlStateValueOn : NSControlStateValueOff;
    _adBlockToggle.state           = s.adBlockEnabled    ? NSControlStateValueOn : NSControlStateValueOff;
    _autoCheckToggle.state         = s.autoCheckUpdates  ? NSControlStateValueOn : NSControlStateValueOff;
    _bookmarksBarToggle.state      = s.showBookmarksBar  ? NSControlStateValueOn : NSControlStateValueOff;
    [self reloadDefaultBrowserStatus];
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Actions
// ───────────────────────────────────────────────────────────────────────────────

/**
 * @brief   Save all settings and dismiss the sheet.
 */
- (void)done:(id)_ {
    SettingsManager* s  = [SettingsManager profileShared];
    NSString* homepage = [_homepageField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString* searchURL = [_searchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!homepage.length) homepage = @"buildbrowser://start";
    if (!searchURL.length || ![searchURL containsString:@"%@"]) searchURL = @"https://duckduckgo.com/?q=%@";
    s.homepage          = homepage;
    s.searchEngineURL   = searchURL;
    s.domainLaunchers   = [self launchersFromText:_launchersTextView.string];
    NSString* updateFeed = [_updateFeedField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    s.updateFeedURL     = updateFeed.length ? updateFeed : kDefaultUpdateFeedURL;
    s.javascriptEnabled = (_jsToggle.state             == NSControlStateValueOn);
    s.blockPopups       = (_popupToggle.state           == NSControlStateValueOn);
    s.privateBrowsing   = (_privateToggle.state         == NSControlStateValueOn);
    s.adBlockEnabled    = (_adBlockToggle.state         == NSControlStateValueOn);
    s.autoCheckUpdates  = (_autoCheckToggle.state       == NSControlStateValueOn);
    s.showBookmarksBar  = (_bookmarksBarToggle.state    == NSControlStateValueOn);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"BuildBrowserSettingsDidChangeNotification"
                                                        object:self];
    [_parentWindow endSheet:self.window];
    [self.window orderOut:nil];
    _parentWindow = nil;
}

/**
 * @brief   Trigger an immediate update check.
 */
- (void)checkNowForUpdates:(id)_ {
    SettingsManager* s = [SettingsManager profileShared];
    NSString* updateFeed = [_updateFeedField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    s.updateFeedURL = updateFeed.length ? updateFeed : kDefaultUpdateFeedURL;
    s.autoCheckUpdates = (_autoCheckToggle.state == NSControlStateValueOn);
    [[UpdateManager shared] checkForUpdates];
}

/// Refresh the default browser status label and button.
- (void)reloadDefaultBrowserStatus {
    BOOL isDefault = [DefaultBrowserManager isDefaultBrowser];
    _defaultBrowserStatusLabel.stringValue = [DefaultBrowserManager statusText];
    _defaultBrowserButton.enabled = !isDefault;
    _defaultBrowserButton.title = isDefault ? @"Default" : @"Make Default";
}

/// Attempt to set BuildBrowser as the default browser.
- (void)makeDefaultBrowser:(id)_ {
    NSError* error = nil;
    if ([DefaultBrowserManager setAsDefaultBrowserWithError:&error]) {
        [self reloadDefaultBrowserStatus];
        return;
    }

    NSAlert* a = [NSAlert new];
    a.messageText = @"Could not update default browser";
    a.informativeText = error.localizedDescription ?: @"Open macOS System Settings and choose BuildBrowser as the default browser.";
    [a addButtonWithTitle:@"OK"];
    [a beginSheetModalForWindow:self.window completionHandler:nil];
    [self reloadDefaultBrowserStatus];
}

/**
 * @brief   Convert the domain launchers dictionary to editable text format.
 *
 * @param   launchers  The launchers dictionary.
 * @return  A string with one "alias = url | search-url" per line.
 */
- (NSString*)textFromLaunchers:(NSDictionary*)launchers {
    NSMutableArray<NSString*>* lines = [NSMutableArray new];
    NSArray<NSString*>* aliases = [[launchers allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString* alias in aliases) {
        NSDictionary* entry = launchers[alias];
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString* url = entry[@"url"] ?: @"";
        NSString* search = entry[@"search"] ?: @"";
        if (search.length)
            [lines addObject:[NSString stringWithFormat:@"%@ = %@ | %@", alias, url, search]];
        else if (url.length)
            [lines addObject:[NSString stringWithFormat:@"%@ = %@", alias, url]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

/**
 * @brief   Parse the launchers text format back into a dictionary.
 *
 * @param   text  The multi-line text to parse.
 * @return  A dictionary mapping aliases to @{ @"url", @"search" }.
 */
- (NSDictionary*)launchersFromText:(NSString*)text {
    NSMutableDictionary* launchers = [NSMutableDictionary new];
    NSArray<NSString*>* lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    for (NSString* raw in lines) {
        NSString* line = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!line.length || [line hasPrefix:@"#"]) continue;
        NSRange eq = [line rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;
        NSString* alias = [[line substringToIndex:eq.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
        if ([alias hasPrefix:@"@"]) alias = [alias substringFromIndex:1];
        NSString* rhs = [[line substringFromIndex:eq.location + 1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSArray<NSString*>* parts = [rhs componentsSeparatedByString:@"|"];
        NSString* url = [parts.firstObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!alias.length || !url.length) continue;
        NSMutableDictionary* entry = [@{ @"url": url } mutableCopy];
        if (parts.count > 1) {
            NSString* search = [parts[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (search.length) entry[@"search"] = search;
        }
        launchers[alias] = entry;
    }
    return launchers;
}

/// Clear all browsing history after confirmation.
- (void)clearHistory:(id)_ {
    NSAlert* a        = [NSAlert new];
    a.messageText     = @"Clear all browsing history?";
    a.informativeText = @"This cannot be undone.";
    [a addButtonWithTitle:@"Clear"];
    [a addButtonWithTitle:@"Cancel"];
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r == NSAlertFirstButtonReturn) [[HistoryManager profileShared] clearAll];
    }];
}

/// Reset all settings to defaults after confirmation.
- (void)resetDefaults:(id)_ {
    NSAlert* a        = [NSAlert new];
    a.messageText     = @"Reset all settings to defaults?";
    a.informativeText = @"This cannot be undone.";
    [a addButtonWithTitle:@"Reset"];
    [a addButtonWithTitle:@"Cancel"];
    [a beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse r) {
        if (r == NSAlertFirstButtonReturn) {
            [[SettingsManager profileShared] resetToDefaults];
            [self reloadValues];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"BuildBrowserSettingsDidChangeNotification"
                                                                object:self];
        }
    }];
}

// ───────────────────────────────────────────────────────────────────────────────
// @name NSTableViewDataSource / Delegate (Sidebar)
// ───────────────────────────────────────────────────────────────────────────────

- (NSInteger)numberOfRowsInTableView:(NSTableView*)_ { return (NSInteger)_sidebarItems.count; }

- (NSView*)tableView:(NSTableView*)tv viewForTableColumn:(NSTableColumn*)_ row:(NSInteger)row {
    NSTableCellView* cell = [tv makeViewWithIdentifier:@"si" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 160, 36)];
        cell.identifier = @"si";

        NSImageView* iv = [[NSImageView alloc] initWithFrame:NSMakeRect(12, 8, 20, 20)];
        iv.identifier = @"icon";
        [cell addSubview:iv];

        NSTextField* lbl = [NSTextField labelWithString:@""];
        lbl.frame      = NSMakeRect(40, 9, 110, 18);
        lbl.font       = [NSFont systemFontOfSize:13];
        lbl.identifier = @"lbl";
        [cell addSubview:lbl];
    }
    SettingsSidebarItem* item = _sidebarItems[row];
    for (NSView* sub in cell.subviews) {
        if ([sub.identifier isEqualToString:@"icon"])
            ((NSImageView*)sub).image = [NSImage imageWithSystemSymbolName:item.symbol
                                                   accessibilityDescription:nil];
        else if ([sub.identifier isEqualToString:@"lbl"])
            ((NSTextField*)sub).stringValue = item.label;
    }
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification*)_ {
    NSInteger sel = _sidebar.selectedRow;
    for (NSInteger i = 0; i < (NSInteger)_contentViews.count; i++)
        ((NSView*)_contentViews[i]).hidden = (i != sel);
}

- (CGFloat)tableView:(NSTableView*)_ heightOfRow:(NSInteger)__ { return 36; }

@end
