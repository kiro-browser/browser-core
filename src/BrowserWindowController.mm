/**
 * @file      BrowserWindowController.mm
 * @project   BuildBrowser
 * @brief     Main browser window — chrome, toolbar, tabs, and panels.
 *
 * @details   The primary NSWindowController subclass. Builds the complete
 *            window chrome: frosted toolbar with navigation buttons and URL
 *            bar, tab strip with favicons and close buttons, bookmarks bar,
 *            find-in-page bar, progress bar, and content area. Owns a
 *            TabManager and wires its callbacks to update the UI. Handles
 *            all user-facing actions: navigation, bookmarks, profiles,
 *            security info, find-in-page, and window state save/restore.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#import "BrowserWindowController.h"
#import "BookmarkManager.h"
#import "HistoryManager.h"
#import "SettingsManager.h"
#import "DownloadManager.h"
#import "ProfilePanel.h"
#import "ProfileManager.h"
#import <objc/runtime.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// Forward declarations for sibling panels compiled in the same target.
@class SettingsPanel, SidePanel, DownloadsPanel;

#pragma mark - Forward-Declared Panel Interfaces

@interface SettingsPanel : NSWindowController
+ (void)showAsSheetOnWindow:(NSWindow*)parent;
@end

@interface SidePanel : NSWindowController
+ (instancetype)shared;
@property (copy) void (^openURLCallback)(NSString* url);
- (void)showBookmarks;
- (void)showHistory;
@end

@interface DownloadsPanel : NSWindowController
+ (instancetype)shared;
- (void)show;
@end

#pragma mark - Layout Constants

/// Toolbar height in points.
static const CGFloat kToolbarH      = 44.0;
/// Tab bar height in points.
static const CGFloat kTabBarH       = 32.0;
/// Bookmarks bar height in points.
static const CGFloat kBookmarksBarH = 28.0;
/// Default tab width in points.
static const CGFloat kTabW          = 180.0;
/// Minimum tab width in points.
static const CGFloat kTabMinW       = 80.0;
/// Progress bar height in points.
static const CGFloat kProgressH     = 3.0;
/// Toolbar button size (square).
static const CGFloat kBtnSize       = 28.0;
/// Find bar height in points.
static const CGFloat kFindBarH      = 36.0;
/// Left sidebar width in points.
static const CGFloat kSidebarW      = 240.0;
/// Header/action area height inside the sidebar.
static const CGFloat kSidebarHeaderH = 88.0;

#pragma mark - ProgressBarView

/**
 * @class     ProgressBarView
 * @brief     Custom NSView that draws a thin accent-colored progress bar.
 *
 * @details   Draws a gradient from controlAccentColor to a lighter variant.
 *          Only renders when visible and progress > 0.
 */
@interface ProgressBarView : NSView
/// Progress value (0.0 to 1.0).
@property (nonatomic, assign) double progress;
/// Whether the progress bar should be drawn.
@property (nonatomic, assign) BOOL   visible;
@end
@implementation ProgressBarView
- (void)setProgress:(double)p { _progress = p; [self setNeedsDisplay:YES]; }
- (void)drawRect:(NSRect)_ {
    if (!_visible || _progress <= 0.0) return;
    NSGradient* grad = [[NSGradient alloc] initWithStartingColor:[NSColor controlAccentColor]
                                                     endingColor:[[NSColor controlAccentColor] colorWithAlphaComponent:0.7]];
    [grad drawInRect:NSMakeRect(0, 0, NSWidth(self.bounds) * _progress, NSHeight(self.bounds)) angle:0];
}
@end

#pragma mark - Private Interface

@interface BrowserWindowController () <NSWindowDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate>

// Managers
@property (strong) TabManager*      tabManager;

// Chrome views
@property (strong) NSView*          toolbarView;
@property (strong) NSView*          tabBarView;
@property (strong) NSView*          bookmarksBarView;
@property (strong) NSView*          sidebarView;
@property (strong) NSTableView*     sidebarTabsTableView;
@property (strong) NSTextField*     sidebarTitleLabel;
@property (strong) NSButton*        sidebarNewTabBtn;
@property (strong) NSArray<NSButton*>* sidebarActionButtons;
@property (strong) NSView*          sidebarHeaderSeparator;
@property (strong) NSView*          findBarView;
@property (strong) ProgressBarView* progressBar;
@property (strong) NSView*          contentArea;

// Toolbar widgets
@property (strong) NSButton*        backBtn;
@property (strong) NSButton*        fwdBtn;
@property (strong) NSButton*        reloadBtn;
@property (strong) NSButton*        homeBtn;
@property (strong) NSButton*        securityIndicatorBtn;
@property (strong) NSTextField*     urlField;
@property (strong) NSButton*        readerModeBtn;
@property (strong) NSButton*        bookmarkStarBtn;
@property (strong) NSButton*        sidebarModeBtn;
@property (strong) NSButton*        profileBtn;
@property (strong) NSArray<NSButton*>* toolbarRightButtons;

// Find bar widgets
@property (strong) NSTextField*     findField;
@property (strong) NSTextField*     findStatusLabel;
@property (assign) BOOL             findBarVisible;
@end

#pragma mark - Implementation

@implementation BrowserWindowController

// ───────────────────────────────────────────────────────────────────────────────
// @name Initialization
// ───────────────────────────────────────────────────────────────────────────────

/**
 * @brief   Initialize with a profile (new window, no session).
 *
 * @param   profile  The profile to associate with this window.
 * @return  A BrowserWindowController showing the default homepage.
 */
- (instancetype)initWithProfile:(Profile*)profile {
    return [self initWithProfile:profile restoredURLs:nil activeIndex:0];
}

/**
 * @brief   Initialize with a profile and restored URLs (no pinned state).
 *
 * @param   profile      The profile to associate.
 * @param   urls         Array of URL strings to restore.
 * @param   activeIndex  The index of the active tab.
 * @return  A BrowserWindowController restoring the given tabs.
 */
- (instancetype)initWithProfile:(Profile*)profile restoredURLs:(NSArray<NSString*>*)urls activeIndex:(NSInteger)activeIndex {
    return [self initWithProfile:profile restoredURLs:urls pinned:nil activeIndex:activeIndex];
}

/**
 * @brief   Designated initializer — creates the window, builds chrome, restores tabs.
 *
 * @details Creates a full-size-content-view window with transparent titlebar.
 *          Builds the UI chrome, wires TabManager callbacks, and restores
 *          tabs from the provided session (or opens the homepage).
 *
 * @param   profile      The profile to associate.
 * @param   urls         Array of URL strings to restore (or nil for default).
 * @param   pinned       Array of NSNumber BOOLs for pinned state.
 * @param   activeIndex  The tab index to activate.
 * @return  A fully initialized BrowserWindowController.
 */
- (instancetype)initWithProfile:(Profile*)profile restoredURLs:(NSArray<NSString*>*)urls pinned:(NSArray<NSNumber*>*)pinned activeIndex:(NSInteger)activeIndex {
    NSRect frame = NSMakeRect(0, 0, 1280, 800);
    NSWindowStyleMask style = NSWindowStyleMaskTitled
                            | NSWindowStyleMaskClosable
                            | NSWindowStyleMaskMiniaturizable
                            | NSWindowStyleMaskResizable
                            | NSWindowStyleMaskFullSizeContentView;
    NSWindow* win = [[NSWindow alloc] initWithContentRect:frame
                                               styleMask:style
                                                 backing:NSBackingStoreBuffered defer:NO];
    win.title                      = @"BuildBrowser";
    win.titlebarAppearsTransparent = YES;
    win.movableByWindowBackground  = YES;
    win.minSize                    = NSMakeSize(640, 480);
    [win center];

    self = [super initWithWindow:win];
    if (!self) return nil;
    win.delegate = self;
    _profile     = profile;
    _tabManager  = [[TabManager alloc] initWithProfile:profile];

    [self buildUI];
    [self wireTabManagerCallbacks];
    [self wireSidePanel];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(settingsDidChange:)
                                                 name:@"BuildBrowserSettingsDidChangeNotification"
                                               object:nil];

    NSArray<NSString*>* restoreURLs = urls.count ? urls : @[ [SettingsManager profileShared].homepage ];
    for (NSInteger i = 0; i < (NSInteger)restoreURLs.count; i++) {
        NSString* url = restoreURLs[i];
        if ([url isKindOfClass:[NSString class]] && url.length) {
            BrowserTab* tab = [_tabManager newTabWithURL:url];
            if (i < (NSInteger)pinned.count && [pinned[i] boolValue]) tab.pinned = YES;
        }
    }
    if (!_tabManager.tabs.count) [_tabManager newTabWithURL:[SettingsManager profileShared].homepage];
    if (activeIndex >= 0 && activeIndex < (NSInteger)_tabManager.tabs.count)
        [_tabManager switchToIndex:activeIndex];
    return self;
}

- (instancetype)init {
    return [self initWithProfile:[ProfileManager shared].activeProfile];
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Session State (Save / Restore)
// ───────────────────────────────────────────────────────────────────────────────

/**
 * @brief   Capture the current window and tab state for session restore.
 *
 * @return  A dictionary with urls, pinned, activeIndex, profileUUID,
 *          windowFrame, windowZoomed, and windowFullscreen.
 */
- (NSDictionary*)sessionState {
    NSMutableArray<NSString*>* urls = [NSMutableArray new];
    for (BrowserTab* tab in _tabManager.tabs) {
        if (tab.url.length) [urls addObject:tab.url];
    }
    NSMutableArray<NSNumber*>* pinned = [NSMutableArray new];
    for (BrowserTab* tab in _tabManager.tabs) [pinned addObject:@(tab.pinned)];
    NSWindow* win = self.window;
    return @{
        @"urls": urls,
        @"pinned": pinned,
        @"activeIndex": @(_tabManager.activeIndex),
        @"profileUUID": _profile.uuid ?: @"",
        @"windowFrame": NSStringFromRect(win.frame),
        @"windowZoomed": @(win.isZoomed),
        @"windowFullscreen": @((win.styleMask & NSWindowStyleMaskFullScreen) == NSWindowStyleMaskFullScreen)
    };
}

/**
 * @brief   Restore the window frame, zoom, and fullscreen state from a session.
 *
 * @param   state  The session dictionary captured earlier.
 */
- (void)restoreWindowState:(NSDictionary*)state {
    if (![state isKindOfClass:[NSDictionary class]]) return;

    NSString* frameString = [state[@"windowFrame"] isKindOfClass:[NSString class]] ? state[@"windowFrame"] : nil;
    if (frameString.length) {
        NSRect frame = NSRectFromString(frameString);
        if ([self frameIsVisibleOnAnyScreen:frame]) {
            [self.window setFrame:frame display:NO];
        }
    }

    if ([state[@"windowZoomed"] boolValue] && !self.window.isZoomed) {
        [self.window zoom:nil];
    }

    if ([state[@"windowFullscreen"] boolValue]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if ((self.window.styleMask & NSWindowStyleMaskFullScreen) != NSWindowStyleMaskFullScreen)
                [self.window toggleFullScreen:nil];
        });
    }
}

/**
 * @brief   Validate that a frame is at least partially visible on any screen.
 *
 * @param   frame  The proposed window frame.
 * @return  YES if at least 160x120 of the frame intersects a visible screen.
 */
- (BOOL)frameIsVisibleOnAnyScreen:(NSRect)frame {
    if (NSWidth(frame) < self.window.minSize.width || NSHeight(frame) < self.window.minSize.height)
        return NO;
    for (NSScreen* screen in [NSScreen screens]) {
        NSRect visible = screen.visibleFrame;
        NSRect intersection = NSIntersectionRect(frame, visible);
        if (!NSIsEmptyRect(intersection) && NSWidth(intersection) >= 160 && NSHeight(intersection) >= 120)
            return YES;
    }
    return NO;
}

// ───────────────────────────────────────────────────────────────────────────────
// @name UI Construction
// ───────────────────────────────────────────────────────────────────────────────

/**
 * @brief   Build all chrome: toolbar, progress bar, tab bar, bookmarks bar,
 *          find bar, and content area.
 */
- (void)buildUI {
    NSView* root = self.window.contentView;
    root.wantsLayer = YES;
    CGFloat W = root.bounds.size.width;
    CGFloat H = root.bounds.size.height;

    // ── Toolbar ──
    _toolbarView = [[NSView alloc] initWithFrame:NSMakeRect(0, H - kToolbarH, W, kToolbarH)];
    _toolbarView.wantsLayer = YES;
    _toolbarView.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [root addSubview:_toolbarView];

    NSVisualEffectView* bg = [[NSVisualEffectView alloc] initWithFrame:_toolbarView.bounds];
    bg.material = NSVisualEffectMaterialTitlebar;
    bg.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    bg.state = NSVisualEffectStateActive;
    bg.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_toolbarView addSubview:bg];

    // Nav cluster: back, forward, reload, home
    CGFloat cx = 76;
    _backBtn   = [self makeSymbolButton:@"chevron.left"    size:16 tooltip:@"Back (⌘[)"];
    _fwdBtn    = [self makeSymbolButton:@"chevron.right"   size:16 tooltip:@"Forward (⌘])"];
    _reloadBtn = [self makeSymbolButton:@"arrow.clockwise" size:15 tooltip:@"Reload (⌘R)"];
    _backBtn.frame   = NSMakeRect(cx,      (kToolbarH-kBtnSize)/2, kBtnSize, kBtnSize);
    _fwdBtn.frame    = NSMakeRect(cx+30,   (kToolbarH-kBtnSize)/2, kBtnSize, kBtnSize);
    _reloadBtn.frame = NSMakeRect(cx+62,   (kToolbarH-kBtnSize)/2, kBtnSize, kBtnSize);
    _homeBtn   = [self makeSymbolButton:@"house" size:15 tooltip:@"Home"];
    _homeBtn.frame   = NSMakeRect(cx+94,   (kToolbarH-kBtnSize)/2, kBtnSize, kBtnSize);
    _backBtn.target   = self; _backBtn.action   = @selector(goBack:);
    _fwdBtn.target    = self; _fwdBtn.action    = @selector(goForward:);
    _reloadBtn.target = self; _reloadBtn.action = @selector(reloadOrStop:);
    _homeBtn.target   = self; _homeBtn.action   = @selector(goHome:);
    [_toolbarView addSubview:_backBtn];
    [_toolbarView addSubview:_fwdBtn];
    [_toolbarView addSubview:_reloadBtn];
    [_toolbarView addSubview:_homeBtn];

    // Right toolbar buttons: sidebar, profile, bookmark, bookmarks, history, downloads, settings, new tab
    NSArray* syms  = @[@"sidebar.left", @"person.circle", @"bookmark",       @"books.vertical", @"clock",   @"arrow.down.circle", @"gearshape", @"plus"];
    NSArray* tips  = @[@"Sidebar",      @"Profile",       @"Bookmark (⌘D)",  @"Bookmarks (⌘B)", @"History (⌘Y)", @"Downloads (⌘J)", @"Settings (⌘,)", @"New Tab (⌘T)"];
    SEL acts[] = { @selector(toggleSidebarMode:), @selector(showProfileMenu:), @selector(toggleBookmark:), @selector(showBookmarks:), @selector(showHistory:),
                   @selector(showDownloads:),     @selector(showSettings:),  @selector(newTab:) };
    CGFloat rBase = W - 8 * 32 - 8;
    NSMutableArray<NSButton*>* rightButtons = [NSMutableArray new];
    for (NSInteger i = 0; i < 8; i++) {
        NSButton* btn = [self makeSymbolButton:syms[i] size:15 tooltip:tips[i]];
        btn.frame = NSMakeRect(rBase + i * 32, (kToolbarH-kBtnSize)/2, kBtnSize, kBtnSize);
        btn.autoresizingMask = NSViewMinXMargin;
        btn.target = self; btn.action = acts[i];
        [_toolbarView addSubview:btn];
        [rightButtons addObject:btn];
        if (i == 0) _sidebarModeBtn = btn;
        if (i == 1) _profileBtn = btn;
        if (i == 2) _bookmarkStarBtn = btn;
    }
    _toolbarRightButtons = rightButtons.copy;
    [self updateProfileButtonIcon];

    // URL field
    CGFloat urlX = cx + 128;
    CGFloat urlW = rBase - urlX - 8;
    _securityIndicatorBtn = [self makeSymbolButton:@"globe" size:13 tooltip:@"Page security"];
    _securityIndicatorBtn.frame = NSMakeRect(urlX, (kToolbarH-24)/2, 24, 24);
    _securityIndicatorBtn.target = self;
    _securityIndicatorBtn.action = @selector(showSecurityInfo:);
    [_toolbarView addSubview:_securityIndicatorBtn];

    _urlField = [[NSTextField alloc] initWithFrame:NSMakeRect(urlX + 28, (kToolbarH-26)/2, urlW - 28, 26)];
    _urlField.placeholderString = @"Search or enter address…";
    _urlField.bezelStyle        = NSTextFieldRoundedBezel;
    _urlField.focusRingType     = NSFocusRingTypeNone;
    _urlField.font              = [NSFont systemFontOfSize:13];
    _urlField.autoresizingMask  = NSViewWidthSizable;
    _urlField.delegate = self;
    _urlField.target = self; _urlField.action = @selector(urlFieldActivated:);
    [_toolbarView addSubview:_urlField];

    // Reader mode button (inside URL field)
    _readerModeBtn = [self makeSymbolButton:@"doc.plaintext" size:13 tooltip:@"Reader Mode"];
    _readerModeBtn.frame = NSMakeRect(urlX + urlW - 28, (kToolbarH-24)/2, 24, 24);
    _readerModeBtn.autoresizingMask = NSViewMinXMargin;
    _readerModeBtn.target = self; _readerModeBtn.action = @selector(toggleReaderMode:);
    _readerModeBtn.hidden = YES;
    [_toolbarView addSubview:_readerModeBtn];

    // Toolbar separator (1px)
    NSView* toolSep = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, W, 1)];
    toolSep.wantsLayer = YES;
    toolSep.layer.backgroundColor = [NSColor separatorColor].CGColor;
    toolSep.autoresizingMask = NSViewWidthSizable;
    [_toolbarView addSubview:toolSep];

    // ── Progress bar ──
    _progressBar = [[ProgressBarView alloc] initWithFrame:
                    NSMakeRect(0, H-kToolbarH-kProgressH, W, kProgressH)];
    _progressBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _progressBar.visible = NO;
    [root addSubview:_progressBar];

    // ── Tab bar ──
    CGFloat tabBarY = H - kToolbarH - kProgressH - kTabBarH;
    _tabBarView = [[NSView alloc] initWithFrame:NSMakeRect(0, tabBarY, W, kTabBarH)];
    _tabBarView.wantsLayer = YES;
    _tabBarView.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;

    NSVisualEffectView* tabBg = [[NSVisualEffectView alloc] initWithFrame:_tabBarView.bounds];
    tabBg.material      = NSVisualEffectMaterialTitlebar;
    tabBg.blendingMode  = NSVisualEffectBlendingModeBehindWindow;
    tabBg.state         = NSVisualEffectStateActive;
    tabBg.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_tabBarView addSubview:tabBg];

    NSView* tabSep = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, W, 1)];
    tabSep.wantsLayer = YES;
    tabSep.layer.backgroundColor = [NSColor separatorColor].CGColor;
    tabSep.autoresizingMask = NSViewWidthSizable;
    [_tabBarView addSubview:tabSep];
    [root addSubview:_tabBarView];

    // ── Bookmarks bar ──
    CGFloat bmBarY = tabBarY - kBookmarksBarH;
    _bookmarksBarView = [[NSView alloc] initWithFrame:NSMakeRect(0, bmBarY, W, kBookmarksBarH)];
    _bookmarksBarView.wantsLayer = YES;
    _bookmarksBarView.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;

    NSVisualEffectView* bmBg = [[NSVisualEffectView alloc] initWithFrame:_bookmarksBarView.bounds];
    bmBg.material     = NSVisualEffectMaterialTitlebar;
    bmBg.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    bmBg.state        = NSVisualEffectStateActive;
    bmBg.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_bookmarksBarView addSubview:bmBg];

    NSView* bmSep = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, W, 1)];
    bmSep.wantsLayer = YES;
    bmSep.layer.backgroundColor = [NSColor separatorColor].CGColor;
    bmSep.autoresizingMask = NSViewWidthSizable;
    [_bookmarksBarView addSubview:bmSep];
    [root addSubview:_bookmarksBarView];
    _bookmarksBarView.hidden = ![SettingsManager profileShared].showBookmarksBar;
    [self rebuildBookmarksBar];

    [self buildSidebarInRoot:root width:W height:H];

    // ── Find bar ──
    _findBarView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, W, kFindBarH)];
    _findBarView.wantsLayer = YES;
    _findBarView.autoresizingMask = NSViewWidthSizable;
    _findBarView.hidden = YES;

    NSVisualEffectView* findBg = [[NSVisualEffectView alloc] initWithFrame:_findBarView.bounds];
    findBg.material     = NSVisualEffectMaterialHUDWindow;
    findBg.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    findBg.state        = NSVisualEffectStateActive;
    findBg.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_findBarView addSubview:findBg];

    NSView* findTopSep = [[NSView alloc] initWithFrame:NSMakeRect(0, kFindBarH-1, W, 1)];
    findTopSep.wantsLayer = YES;
    findTopSep.layer.backgroundColor = [NSColor separatorColor].CGColor;
    findTopSep.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [_findBarView addSubview:findTopSep];

    _findField = [[NSTextField alloc] initWithFrame:NSMakeRect(12, (kFindBarH-24)/2, 200, 24)];
    _findField.placeholderString = @"Find in page…";
    _findField.bezelStyle = NSTextFieldRoundedBezel;
    _findField.focusRingType = NSFocusRingTypeNone;
    _findField.font = [NSFont systemFontOfSize:13];
    _findField.target = self; _findField.action = @selector(findNext:);
    [_findBarView addSubview:_findField];

    NSButton* prevBtn = [self makeSymbolButton:@"chevron.up"   size:12 tooltip:@"Previous"];
    NSButton* nextBtn = [self makeSymbolButton:@"chevron.down" size:12 tooltip:@"Next"];
    prevBtn.frame = NSMakeRect(218, (kFindBarH-24)/2, 28, 24);
    nextBtn.frame = NSMakeRect(250, (kFindBarH-24)/2, 28, 24);
    prevBtn.target = self; prevBtn.action = @selector(findPrev:);
    nextBtn.target = self; nextBtn.action = @selector(findNext:);
    [_findBarView addSubview:prevBtn];
    [_findBarView addSubview:nextBtn];

    _findStatusLabel = [NSTextField labelWithString:@""];
    _findStatusLabel.frame = NSMakeRect(284, (kFindBarH-16)/2, 140, 16);
    _findStatusLabel.font = [NSFont systemFontOfSize:11];
    _findStatusLabel.textColor = [NSColor secondaryLabelColor];
    [_findBarView addSubview:_findStatusLabel];

    NSButton* closeFind = [self makeSymbolButton:@"xmark" size:11 tooltip:@"Close (Esc)"];
    closeFind.frame = NSMakeRect(W - 32, (kFindBarH-kBtnSize)/2, kBtnSize, kBtnSize);
    closeFind.autoresizingMask = NSViewMinXMargin;
    closeFind.target = self; closeFind.action = @selector(closeFindBar:);
    [_findBarView addSubview:closeFind];
    [root addSubview:_findBarView];

    // ── Content area ──
    [self layoutChrome];
}

- (void)buildSidebarInRoot:(NSView*)root width:(CGFloat)W height:(CGFloat)H {
    _sidebarView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kSidebarW, H - kToolbarH - kProgressH)];
    _sidebarView.wantsLayer = YES;
    _sidebarView.hidden = ![SettingsManager profileShared].showSidebar;
    [root addSubview:_sidebarView];

    NSVisualEffectView* bg = [[NSVisualEffectView alloc] initWithFrame:_sidebarView.bounds];
    bg.material = NSVisualEffectMaterialSidebar;
    bg.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    bg.state = NSVisualEffectStateActive;
    bg.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_sidebarView addSubview:bg];

    _sidebarTitleLabel = [NSTextField labelWithString:@"Tabs"];
    _sidebarTitleLabel.frame = NSMakeRect(14, NSHeight(_sidebarView.bounds) - 32, 120, 20);
    _sidebarTitleLabel.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
    _sidebarTitleLabel.autoresizingMask = NSViewMinYMargin;
    [_sidebarView addSubview:_sidebarTitleLabel];

    _sidebarNewTabBtn = [self sidebarActionButtonWithSymbol:@"plus" tooltip:@"New Tab" action:@selector(newTab:)];
    _sidebarNewTabBtn.frame = NSMakeRect(kSidebarW - 40, NSHeight(_sidebarView.bounds) - 36, 28, 28);
    _sidebarNewTabBtn.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [_sidebarView addSubview:_sidebarNewTabBtn];

    NSArray* syms = @[@"books.vertical", @"clock", @"arrow.down.circle", @"gearshape"];
    NSArray* tips = @[@"Bookmarks", @"History", @"Downloads", @"Settings"];
    SEL acts[] = { @selector(showBookmarks:), @selector(showHistory:), @selector(showDownloads:), @selector(showSettings:) };
    CGFloat actionY = NSHeight(_sidebarView.bounds) - 74;
    NSMutableArray<NSButton*>* actionButtons = [NSMutableArray new];
    for (NSInteger i = 0; i < 4; i++) {
        NSButton* btn = [self sidebarActionButtonWithSymbol:syms[i] tooltip:tips[i] action:acts[i]];
        btn.frame = NSMakeRect(12 + i * 34, actionY, 30, 28);
        btn.autoresizingMask = NSViewMinYMargin;
        [_sidebarView addSubview:btn];
        [actionButtons addObject:btn];
    }
    _sidebarActionButtons = actionButtons.copy;

    _sidebarHeaderSeparator = [[NSView alloc] initWithFrame:NSMakeRect(0, NSHeight(_sidebarView.bounds) - kSidebarHeaderH, kSidebarW, 1)];
    _sidebarHeaderSeparator.wantsLayer = YES;
    _sidebarHeaderSeparator.layer.backgroundColor = [NSColor separatorColor].CGColor;
    _sidebarHeaderSeparator.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [_sidebarView addSubview:_sidebarHeaderSeparator];

    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, kSidebarW, NSHeight(_sidebarView.bounds) - kSidebarHeaderH)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.drawsBackground = NO;

    _sidebarTabsTableView = [[NSTableView alloc] initWithFrame:scroll.bounds];
    _sidebarTabsTableView.backgroundColor = [NSColor clearColor];
    _sidebarTabsTableView.headerView = nil;
    _sidebarTabsTableView.rowHeight = 46;
    _sidebarTabsTableView.intercellSpacing = NSMakeSize(0, 0);
    _sidebarTabsTableView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    _sidebarTabsTableView.dataSource = self;
    _sidebarTabsTableView.delegate = self;

    NSTableColumn* col = [[NSTableColumn alloc] initWithIdentifier:@"tab"];
    col.width = kSidebarW;
    [_sidebarTabsTableView addTableColumn:col];
    scroll.documentView = _sidebarTabsTableView;
    [_sidebarView addSubview:scroll];
}

- (NSButton*)sidebarActionButtonWithSymbol:(NSString*)symbol tooltip:(NSString*)tooltip action:(SEL)action {
    NSButton* btn = [self makeSymbolButton:symbol size:14 tooltip:tooltip];
    btn.target = self;
    btn.action = action;
    btn.bezelStyle = NSBezelStyleTexturedRounded;
    return btn;
}

/// Whether the bookmarks bar is currently visible.
- (BOOL)bookmarksBarVisible {
    return [SettingsManager profileShared].showBookmarksBar && !_bookmarksBarView.hidden;
}

/// Reposition toolbar controls on window resize.
- (void)layoutToolbarControls {
    CGFloat W = _toolbarView.bounds.size.width;
    CGFloat cx = 76;
    _backBtn.frame   = NSMakeRect(cx,      (kToolbarH-kBtnSize)/2, kBtnSize, kBtnSize);
    _fwdBtn.frame    = NSMakeRect(cx+30,   (kToolbarH-kBtnSize)/2, kBtnSize, kBtnSize);
    _reloadBtn.frame = NSMakeRect(cx+62,   (kToolbarH-kBtnSize)/2, kBtnSize, kBtnSize);
    _homeBtn.frame   = NSMakeRect(cx+94,   (kToolbarH-kBtnSize)/2, kBtnSize, kBtnSize);

    CGFloat rightW = _toolbarRightButtons.count * 32;
    CGFloat rBase = MAX(cx + 172, W - rightW - 8);
    for (NSInteger i = 0; i < (NSInteger)_toolbarRightButtons.count; i++) {
        NSButton* btn = _toolbarRightButtons[i];
        btn.frame = NSMakeRect(rBase + i * 32, (kToolbarH-kBtnSize)/2, kBtnSize, kBtnSize);
    }

    CGFloat urlX = cx + 128;
    CGFloat urlW = MAX(120, rBase - urlX - 8);
    _securityIndicatorBtn.frame = NSMakeRect(urlX, (kToolbarH-24)/2, 24, 24);
    _urlField.frame = NSMakeRect(urlX + 28, (kToolbarH-26)/2, MAX(92, urlW - 28), 26);
    _readerModeBtn.frame = NSMakeRect(NSMaxX(_urlField.frame) - 28, (kToolbarH-24)/2, 24, 24);
}

/**
 * @brief   Recalculate and resize all chrome views and the content area.
 */
- (void)layoutChrome {
    NSView* root = self.window.contentView;
    CGFloat W = root.bounds.size.width;
    CGFloat H = root.bounds.size.height;
    BOOL sidebarVisible = [SettingsManager profileShared].showSidebar;
    CGFloat sidebarW = sidebarVisible ? kSidebarW : 0;

    _toolbarView.frame = NSMakeRect(0, H - kToolbarH, W, kToolbarH);
    _progressBar.frame = NSMakeRect(0, NSMinY(_toolbarView.frame) - kProgressH, W, kProgressH);
    _tabBarView.hidden = sidebarVisible;
    _tabBarView.frame = NSMakeRect(sidebarW, NSMinY(_progressBar.frame) - kTabBarH, W - sidebarW, kTabBarH);

    BOOL bookmarksVisible = [self bookmarksBarVisible];
    CGFloat contentTop = sidebarVisible ? NSMinY(_progressBar.frame) : NSMinY(_tabBarView.frame);
    if (bookmarksVisible) {
        _bookmarksBarView.frame = NSMakeRect(sidebarW, contentTop - kBookmarksBarH, W - sidebarW, kBookmarksBarH);
        contentTop = NSMinY(_bookmarksBarView.frame);
    } else {
        _bookmarksBarView.frame = NSMakeRect(sidebarW, contentTop - kBookmarksBarH, W - sidebarW, kBookmarksBarH);
    }

    CGFloat bottom = _findBarVisible ? kFindBarH : 0;
    CGFloat contentH = MAX(0, contentTop - bottom);

    if (!_contentArea) {
        _contentArea = [[NSView alloc] initWithFrame:NSMakeRect(sidebarW, bottom, W - sidebarW, contentH)];
        _contentArea.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [root addSubview:_contentArea];
    } else {
        _contentArea.frame = NSMakeRect(sidebarW, bottom, W - sidebarW, contentH);
    }

    _sidebarView.hidden = !sidebarVisible;
    _sidebarView.frame = NSMakeRect(0, bottom, kSidebarW, MAX(0, NSMinY(_progressBar.frame) - bottom));
    NSView* sidebarScroll = _sidebarTabsTableView.enclosingScrollView;
    sidebarScroll.frame = NSMakeRect(0, 0, kSidebarW, MAX(0, NSHeight(_sidebarView.bounds) - kSidebarHeaderH));
    _sidebarTitleLabel.frame = NSMakeRect(14, NSHeight(_sidebarView.bounds) - 32, 120, 20);
    _sidebarNewTabBtn.frame = NSMakeRect(kSidebarW - 40, NSHeight(_sidebarView.bounds) - 36, 28, 28);
    _sidebarHeaderSeparator.frame = NSMakeRect(0, NSHeight(_sidebarView.bounds) - kSidebarHeaderH, kSidebarW, 1);
    CGFloat actionY = NSHeight(_sidebarView.bounds) - 74;
    for (NSInteger i = 0; i < (NSInteger)_sidebarActionButtons.count; i++) {
        _sidebarActionButtons[i].frame = NSMakeRect(12 + i * 34, actionY, 30, 28);
    }

    _findBarView.frame = NSMakeRect(0, 0, W, kFindBarH);
    [self layoutToolbarControls];
    [self updateSidebarModeButton];
    [self rebuildSidebarTabs];

    for (BrowserTab* t in _tabManager.tabs) {
        t.webView.frame = _contentArea.bounds;
    }
}

- (void)recalcContentArea {
    [self layoutChrome];
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Tab Manager Callbacks
// ───────────────────────────────────────────────────────────────────────────────

/// Wire TabManager callback blocks to local event handler methods.
- (void)wireTabManagerCallbacks {
    __unsafe_unretained typeof(self) ws = self;
    _tabManager.onTabAdded        = ^(BrowserTab* t, NSInteger i) { [ws onTabAdded:t atIndex:i]; };
    _tabManager.onTabClosed       = ^(NSInteger i)                 { [ws onTabClosedAtIndex:i]; };
    _tabManager.onTabSwitched     = ^(BrowserTab* t, NSInteger i)  { [ws onTabSwitched:t atIndex:i]; };
    _tabManager.onTitleChanged    = ^(BrowserTab* t, NSString* s)  { [ws onTitleChanged:s forTab:t]; };
    _tabManager.onURLChanged      = ^(BrowserTab* t, NSString* s)  { [ws onURLChanged:s forTab:t]; };
    _tabManager.onLoadProgress    = ^(BrowserTab* t, double p)     { [ws onLoadProgress:p forTab:t]; };
    _tabManager.onLoadStateChanged= ^(BrowserTab* t, BOOL l)       { [ws onLoadStateChanged:l forTab:t]; };
    _tabManager.onFaviconChanged  = ^(BrowserTab* t, NSImage* i)   { [ws onFaviconChanged:i forTab:t]; };
    _tabManager.onInternalCommand = ^(NSString* c)                  { [ws handleInternalCommand:c]; };
}

/// Wire the SidePanel openURL callback to open tabs in this window.
- (void)wireSidePanel {
    __unsafe_unretained typeof(self) ws = self;
    [SidePanel shared].openURLCallback = ^(NSString* url) {
        [ws.tabManager newTabWithURL:url];
        [ws rebuildTabStrip];
        [ws rebuildSidebarTabs];
    };
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Tab Event Handlers
// ───────────────────────────────────────────────────────────────────────────────

- (void)onTabAdded:(BrowserTab*)tab atIndex:(NSInteger)index {
    tab.webView.frame            = _contentArea.bounds;
    tab.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    tab.webView.hidden           = YES;
    [self rebuildTabStrip];
    [self rebuildSidebarTabs];
}

- (void)onTabClosedAtIndex:(NSInteger)_ {
    for (NSView* subview in _contentArea.subviews.copy) {
        if ([subview isKindOfClass:[WKWebView class]]) [subview removeFromSuperview];
    }
    [self rebuildTabStrip];
    [self rebuildSidebarTabs];
}

- (void)onTabSwitched:(BrowserTab*)tab atIndex:(NSInteger)_ {
    for (NSView* subview in _contentArea.subviews.copy) {
        if ([subview isKindOfClass:[WKWebView class]] && subview != tab.webView)
            [subview removeFromSuperview];
    }
    tab.webView.frame = _contentArea.bounds;
    tab.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    if (tab.webView.superview == _contentArea) [tab.webView removeFromSuperview];
    [_contentArea addSubview:tab.webView];
    tab.webView.hidden = NO;
    [_urlField setStringValue:tab.url ?: @""];
    [self updateSecurityIndicatorForURL:tab.url];
    [self updateNavButtons];
    [self updateBookmarkStar];
    for (BrowserTab* t in _tabManager.tabs)
        t.tabButton.state = (t == tab) ? NSControlStateValueOn : NSControlStateValueOff;
    [self.window setTitle:tab.title.length ? tab.title : @"KBrowser"];
    [self rebuildTabStrip];
    [self rebuildSidebarTabs];
}

- (void)onTitleChanged:(NSString*)title forTab:(BrowserTab*)tab {
    if (tab == _tabManager.activeTab)
        [self.window setTitle:title.length ? title : @"BuildBrowser"];
    [self rebuildTabStrip];
    [self rebuildSidebarTabs];
    if (![SettingsManager profileShared].privateBrowsing && tab.url.length)
        [[HistoryManager profileShared] recordVisitWithTitle:title url:tab.url];
}

- (void)onURLChanged:(NSString*)url forTab:(BrowserTab*)tab {
    if (tab == _tabManager.activeTab) {
        [_urlField setStringValue:url ?: @""];
        [self updateSecurityIndicatorForURL:url];
        [self updateBookmarkStar];
    }
    [self rebuildSidebarTabs];
}

- (void)onLoadProgress:(double)p forTab:(BrowserTab*)tab {
    if (tab == _tabManager.activeTab) _progressBar.progress = p;
}

- (void)onLoadStateChanged:(BOOL)loading forTab:(BrowserTab*)tab {
    if (tab != _tabManager.activeTab) return;
    _progressBar.visible  = loading;
    _progressBar.progress = loading ? _progressBar.progress : 0.0;
    [_progressBar setNeedsDisplay:YES];
    NSString* sym = loading ? @"xmark" : @"arrow.clockwise";
    [_reloadBtn setImage:[NSImage imageWithSystemSymbolName:sym accessibilityDescription:nil]];
    [self updateNavButtons];
    if (!loading) [self injectContextMenuScript:tab.webView];
    if (!loading) [self updateReaderModeAvailability:tab];
}

- (void)onFaviconChanged:(NSImage*)icon forTab:(BrowserTab*)tab {
    [self rebuildTabStrip];
    [self rebuildSidebarTabs];
}

/**
 * @brief   Handle internal buildbrowser:// commands from the TabManager.
 *
 * @param   command  The command string (e.g. @"bookmarks", @"history").
 */
- (void)handleInternalCommand:(NSString*)command {
    if ([command isEqualToString:@"bookmarks"]) {
        [self showBookmarks:nil];
    } else if ([command isEqualToString:@"history"]) {
        [self showHistory:nil];
    } else if ([command isEqualToString:@"downloads"]) {
        [self showDownloads:nil];
    } else if ([command isEqualToString:@"settings"]) {
        [self showSettings:nil];
    } else if ([command isEqualToString:@"profiles"]) {
        [self manageProfiles:nil];
    }
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Navigation Actions
// ───────────────────────────────────────────────────────────────────────────────

/** @brief   Open a new tab with the homepage. */
- (void)newTab:(id)_ {
    [_tabManager newTabWithURL:[SettingsManager profileShared].homepage];
    [self rebuildTabStrip];
    [self rebuildSidebarTabs];
}

/**
 * @brief   Open a URL in a new tab (used by side panel and URL open requests).
 *
 * @param   url  The URL string to open.
 */
- (void)openURLInNewTab:(NSString*)url {
    if (!url.length) return;
    [_tabManager newTabWithURL:url];
    [self rebuildTabStrip];
    [self rebuildSidebarTabs];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)goBack:(id)_    { [_tabManager.activeTab.webView goBack]; }
- (void)goForward:(id)_ { [_tabManager.activeTab.webView goForward]; }
- (void)goHome:(id)_    { [_tabManager loadURL:[SettingsManager profileShared].homepage inTab:_tabManager.activeTab]; }

- (void)reloadOrStop:(id)_ {
    WKWebView* wv = _tabManager.activeTab.webView;
    if (wv.isLoading) [wv stopLoading]; else [wv reload];
}

/** @brief   Load the URL from the address bar. */
- (void)urlFieldActivated:(id)_ {
    BrowserTab* tab = _tabManager.activeTab;
    if (!tab) return;
    [_tabManager loadURL:_urlField.stringValue inTab:tab];
    [self.window makeFirstResponder:tab.webView];
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Reader Mode
// ───────────────────────────────────────────────────────────────────────────────

/// Toggle a simplistic reader mode overlay via JS.
- (void)toggleReaderMode:(id)_ {
    WKWebView* wv = _tabManager.activeTab.webView;
    [wv evaluateJavaScript:@"(function(){ if(window._readerOn){ location.reload(); } else { document.body.innerHTML = '<div style=\"max-width:800px;margin:50px auto;font-family:serif;font-size:20px;line-height:1.6;color:#333;background:#fff;padding:40px;\">' + (document.querySelector('article') || document.body).innerHTML + '</div>'; window._readerOn=true; document.body.style.background='#fff'; } })()" completionHandler:nil];
}

/**
 * @brief   Check if the page has article content and show/hide the reader button.
 */
- (void)updateReaderModeAvailability:(BrowserTab*)tab {
    [tab.webView evaluateJavaScript:@"(!!document.querySelector('article') || document.body.innerText.length > 2000)" completionHandler:^(id res, NSError* _) {
        if (tab == self.tabManager.activeTab) {
            self.readerModeBtn.hidden = ![res boolValue];
        }
    }];
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Tab UI
// ───────────────────────────────────────────────────────────────────────────────

/// Handle tab button click (Option+click closes, normal click switches).
- (void)tabButtonClicked:(NSButton*)btn {
    NSEvent* ev = NSApp.currentEvent;
    if (ev.modifierFlags & NSEventModifierFlagOption)
        [_tabManager closeTabAtIndex:btn.tag];
    else
        [_tabManager switchToIndex:btn.tag];
}

/// Handle close button on a tab.
- (void)closeTabButtonClicked:(NSButton*)btn {
    [_tabManager closeTabAtIndex:btn.tag];
}

/// Toggle pinned state for the active tab.
- (void)togglePinCurrentTab:(id)_ {
    NSInteger index = _tabManager.activeIndex;
    BrowserTab* tab = _tabManager.activeTab;
    if (!tab) return;
    [_tabManager setPinned:!tab.pinned forTabAtIndex:index];
    [self rebuildTabStrip];
    [self rebuildSidebarTabs];
}

/// Toggle the in-window left sidebar.
- (void)toggleSidebarMode:(id)_ {
    SettingsManager* settings = [SettingsManager profileShared];
    settings.showSidebar = !settings.showSidebar;
    [self layoutChrome];
    [self rebuildTabStrip];
    [self rebuildSidebarTabs];
}

- (void)updateSidebarModeButton {
    BOOL enabled = [SettingsManager profileShared].showSidebar;
    _sidebarModeBtn.contentTintColor = enabled ? [NSColor controlAccentColor] : [NSColor secondaryLabelColor];
    _sidebarModeBtn.toolTip = enabled ? @"Hide Sidebar" : @"Show Sidebar";
}

- (void)rebuildSidebarTabs {
    if (!_sidebarTabsTableView) return;
    [_sidebarTabsTableView reloadData];
    NSInteger active = _tabManager.activeIndex;
    if (active >= 0 && active < (NSInteger)_tabManager.tabs.count) {
        [_sidebarTabsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:active] byExtendingSelection:NO];
        [_sidebarTabsTableView scrollRowToVisible:active];
    }
}

- (void)closeSidebarTabButtonClicked:(NSButton*)btn {
    [_tabManager closeTabAtIndex:btn.tag];
    [self rebuildSidebarTabs];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    if (tableView != _sidebarTabsTableView) return 0;
    return (NSInteger)_tabManager.tabs.count;
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)_ row:(NSInteger)row {
    if (tableView != _sidebarTabsTableView || row < 0 || row >= (NSInteger)_tabManager.tabs.count) return nil;
    NSTableCellView* cell = [tableView makeViewWithIdentifier:@"sidebarTabCell" owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, kSidebarW, 46)];
        cell.identifier = @"sidebarTabCell";

        NSImageView* favicon = [[NSImageView alloc] initWithFrame:NSMakeRect(12, 23, 16, 16)];
        favicon.identifier = @"favicon";
        favicon.imageScaling = NSImageScaleProportionallyUpOrDown;
        [cell addSubview:favicon];

        NSTextField* title = [NSTextField labelWithString:@""];
        title.identifier = @"title";
        title.frame = NSMakeRect(36, 24, kSidebarW - 72, 16);
        title.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
        title.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:title];

        NSTextField* url = [NSTextField labelWithString:@""];
        url.identifier = @"url";
        url.frame = NSMakeRect(36, 8, kSidebarW - 72, 14);
        url.font = [NSFont systemFontOfSize:10];
        url.textColor = [NSColor secondaryLabelColor];
        url.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [cell addSubview:url];

        NSImageView* pin = [[NSImageView alloc] initWithFrame:NSMakeRect(kSidebarW - 44, 28, 10, 10)];
        pin.identifier = @"pin";
        pin.image = [NSImage imageWithSystemSymbolName:@"pin.fill" accessibilityDescription:nil];
        pin.contentTintColor = [NSColor secondaryLabelColor];
        [cell addSubview:pin];

        NSButton* close = [self makeSymbolButton:@"xmark" size:9 tooltip:@"Close Tab"];
        close.identifier = @"close";
        close.frame = NSMakeRect(kSidebarW - 32, 14, 20, 20);
        close.target = self;
        close.action = @selector(closeSidebarTabButtonClicked:);
        [cell addSubview:close];
    }

    BrowserTab* tab = _tabManager.tabs[row];
    BOOL active = (row == _tabManager.activeIndex);
    for (NSView* sub in cell.subviews) {
        if ([sub.identifier isEqualToString:@"favicon"]) {
            ((NSImageView*)sub).image = tab.favicon ?: [NSImage imageWithSystemSymbolName:@"globe" accessibilityDescription:nil];
        } else if ([sub.identifier isEqualToString:@"title"]) {
            NSTextField* label = (NSTextField*)sub;
            label.stringValue = tab.title.length ? tab.title : @"New Tab";
            label.textColor = active ? [NSColor labelColor] : [NSColor secondaryLabelColor];
        } else if ([sub.identifier isEqualToString:@"url"]) {
            ((NSTextField*)sub).stringValue = tab.url.length ? tab.url : @"";
        } else if ([sub.identifier isEqualToString:@"pin"]) {
            sub.hidden = !tab.pinned;
        } else if ([sub.identifier isEqualToString:@"close"]) {
            NSButton* close = (NSButton*)sub;
            close.tag = row;
            close.hidden = tab.pinned;
        }
    }
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
    if (notification.object != _sidebarTabsTableView) return;
    NSInteger row = _sidebarTabsTableView.selectedRow;
    if (row >= 0 && row < (NSInteger)_tabManager.tabs.count && row != _tabManager.activeIndex) {
        [_tabManager switchToIndex:row];
    }
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Bookmark Actions
// ───────────────────────────────────────────────────────────────────────────────

/// Toggle bookmark for the active tab's URL.
- (void)toggleBookmark:(id)_ {
    BrowserTab* tab = _tabManager.activeTab;
    if (!tab || !tab.url.length) return;
    BookmarkManager* bm = [BookmarkManager profileShared];
    if ([bm isBookmarked:tab.url]) {
        NSArray<Bookmark*>* list = bm.bookmarks;
        for (NSInteger i = 0; i < (NSInteger)list.count; i++)
            if ([list[i].url isEqualToString:tab.url]) { [bm removeBookmarkAtIndex:i]; break; }
    } else {
        [bm addBookmarkWithTitle:tab.title url:tab.url];
    }
    [self updateBookmarkStar];
    [self rebuildBookmarksBar];
}

/// Update the bookmark star icon (filled if bookmarked, outline otherwise).
- (void)updateBookmarkStar {
    BrowserTab* tab = _tabManager.activeTab;
    BOOL starred = tab && [[BookmarkManager profileShared] isBookmarked:tab.url];
    NSString* sym = starred ? @"bookmark.fill" : @"bookmark";
    [_bookmarkStarBtn setImage:[NSImage imageWithSystemSymbolName:sym accessibilityDescription:nil]];
}

/**
 * @brief   Update the security indicator icon and color based on the URL scheme.
 */
- (void)updateSecurityIndicatorForURL:(NSString*)urlString {
    NSURL* url = [NSURL URLWithString:urlString ?: @""];
    NSString* scheme = url.scheme.lowercaseString ?: @"";
    NSString* sym = @"globe";
    NSString* tip = @"Search or page";
    NSColor* tint = [NSColor secondaryLabelColor];

    if ([scheme isEqualToString:@"https"]) {
        sym = @"lock.fill";
        tip = @"Secure connection (HTTPS)";
        tint = [NSColor systemGreenColor];
    } else if ([scheme isEqualToString:@"http"]) {
        sym = @"exclamationmark.triangle.fill";
        tip = @"Not secure (HTTP)";
        tint = [NSColor systemOrangeColor];
    } else if ([scheme isEqualToString:@"buildbrowser"]) {
        sym = @"house.fill";
        tip = @"BuildBrowser internal page";
        tint = [NSColor controlAccentColor];
    } else if ([scheme isEqualToString:@"file"]) {
        sym = @"doc.fill";
        tip = @"Local file";
        tint = [NSColor secondaryLabelColor];
    } else if (scheme.length) {
        sym = @"questionmark.circle.fill";
        tip = [NSString stringWithFormat:@"Unknown scheme: %@", scheme];
        tint = [NSColor systemYellowColor];
    }

    NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration
        configurationWithPointSize:13 weight:NSFontWeightMedium];
    NSImage* img = [[NSImage imageWithSystemSymbolName:sym accessibilityDescription:tip]
                    imageWithSymbolConfiguration:cfg];
    _securityIndicatorBtn.image = img;
    _securityIndicatorBtn.contentTintColor = tint;
    _securityIndicatorBtn.toolTip = tip;
}

/**
 * @brief   Show a security info alert with certificate details for HTTPS pages.
 */
- (void)showSecurityInfo:(id)sender {
    BrowserTab* tab = _tabManager.activeTab;
    NSString* urlString = tab.url ?: @"";
    NSURL* url = [NSURL URLWithString:urlString];
    NSString* scheme = url.scheme.lowercaseString ?: @"";
    NSString* message = @"Page Security";
    NSString* detail = @"This page does not expose standard web security information.";

    if ([scheme isEqualToString:@"https"]) {
        message = @"Secure Connection";
        NSDictionary* cert = tab.certificateInfo;
        if (cert.count) {
            NSString* trust = [cert[@"trusted"] boolValue] ? @"Trusted by macOS" : (cert[@"trustError"] ?: @"Not trusted");
            detail = [NSString stringWithFormat:
                @"Host: %@\nStatus: %@\nSubject: %@\nIssuer: %@\nValid From: %@\nValid Until: %@\nCertificate Chain: %@ certificate%@",
                cert[@"host"] ?: url.host ?: @"Unknown",
                trust,
                cert[@"subject"] ?: @"Unknown",
                cert[@"issuer"] ?: @"Unknown",
                cert[@"notBefore"] ?: @"Unknown",
                cert[@"notAfter"] ?: @"Unknown",
                cert[@"chainLength"] ?: @0,
                [cert[@"chainLength"] integerValue] == 1 ? @"" : @"s"];
        } else {
            detail = @"This page was loaded over HTTPS. Certificate details were not exposed for this navigation, but WebKit and macOS still performed trust validation.";
        }
    } else if ([scheme isEqualToString:@"http"]) {
        message = @"Not Secure";
        detail = @"This page was loaded over HTTP. Other people on the network may be able to view or change traffic.";
    } else if ([scheme isEqualToString:@"buildbrowser"]) {
        message = @"BuildBrowser Page";
        detail = @"This is an internal local browser page.";
    } else if ([scheme isEqualToString:@"file"]) {
        message = @"Local File";
        detail = @"This content was loaded from the local file system.";
    }

    NSAlert* alert = [NSAlert new];
    alert.messageText = message;
    alert.informativeText = [NSString stringWithFormat:@"%@\n\n%@", detail, urlString.length ? urlString : @"No URL"];
    [alert addButtonWithTitle:@"OK"];
    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Bookmarks Bar
// ───────────────────────────────────────────────────────────────────────────────

/**
 * @brief   Rebuild the bookmarks bar buttons from the BookmarkManager data.
 *
 * @details Removes old bookmark buttons, groups bookmarks by folder.
 *          Shows "Favorites" items as inline buttons, other folders as
 *          pop-up menu buttons.
 */
- (void)rebuildBookmarksBar {
    for (NSView* v in _bookmarksBarView.subviews.copy)
        if ([v isKindOfClass:[NSButton class]]) [v removeFromSuperview];

    CGFloat x = 8;
    BookmarkManager* manager = [BookmarkManager profileShared];
    NSMutableDictionary<NSString*, NSMutableArray<Bookmark*>*>* grouped = [NSMutableDictionary new];
    for (Bookmark* bm in manager.bookmarks) {
        NSString* folder = bm.folder.length ? bm.folder : @"Favorites";
        if (!grouped[folder]) grouped[folder] = [NSMutableArray new];
        [grouped[folder] addObject:bm];
    }

    NSArray<NSString*>* folders = [manager folders];
    for (NSString* folder in folders) {
        NSArray<Bookmark*>* items = grouped[folder];
        if (!items.count) continue;

        BOOL favorites = [folder isEqualToString:@"Favorites"];
        if (favorites) {
            for (Bookmark* bm in items) {
                NSButton* btn = [self bookmarkBarButtonWithTitle:bm.title url:bm.url x:x];
                [_bookmarksBarView addSubview:btn];
                x = NSMaxX(btn.frame) + 4;
                if (x > _bookmarksBarView.bounds.size.width - 20) return;
            }
            continue;
        }

        NSButton* folderBtn = [NSButton buttonWithTitle:[NSString stringWithFormat:@"%@  v", folder]
                                                 target:self action:@selector(bookmarkFolderButtonClicked:)];
        folderBtn.bezelStyle = NSBezelStyleInline;
        folderBtn.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        [folderBtn sizeToFit];
        CGFloat w = MAX(folderBtn.frame.size.width + 16, 72);
        folderBtn.frame = NSMakeRect(x, 4, w, kBookmarksBarH - 8);

        NSMenu* menu = [NSMenu new];
        for (Bookmark* bm in items) {
            NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:bm.title.length ? bm.title : bm.url
                                                          action:@selector(bookmarkFolderMenuItemClicked:)
                                                   keyEquivalent:@""];
            item.target = self;
            item.representedObject = bm.url;
            [menu addItem:item];
        }
        objc_setAssociatedObject(folderBtn, "folderMenu", menu, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [_bookmarksBarView addSubview:folderBtn];
        x += w + 4;
        if (x > _bookmarksBarView.bounds.size.width - 20) break;
    }
}

/// Create a single bookmark bar button.
- (NSButton*)bookmarkBarButtonWithTitle:(NSString*)title url:(NSString*)url x:(CGFloat)x {
    NSButton* btn = [NSButton buttonWithTitle:title.length ? title : url target:self
                                       action:@selector(bookmarkBarItemClicked:)];
    btn.bezelStyle = NSBezelStyleInline;
    btn.font       = [NSFont systemFontOfSize:11];
    [btn sizeToFit];
    CGFloat w = MAX(btn.frame.size.width + 12, 60);
    btn.frame = NSMakeRect(x, 4, w, kBookmarksBarH - 8);
    [btn.cell setLineBreakMode:NSLineBreakByTruncatingTail];
    objc_setAssociatedObject(btn, "bmurl", url, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return btn;
}

/// Click a bookmark bar item — opens the URL in a new tab.
- (void)bookmarkBarItemClicked:(NSButton*)btn {
    NSString* url = objc_getAssociatedObject(btn, "bmurl");
    if (url) [_tabManager newTabWithURL:url];
    [self rebuildTabStrip];
}

/// Click a folder button — pop up its menu.
- (void)bookmarkFolderButtonClicked:(NSButton*)btn {
    NSMenu* menu = objc_getAssociatedObject(btn, "folderMenu");
    if (!menu) return;
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(0, NSHeight(btn.bounds) + 2) inView:btn];
}

/// Select a bookmark from a folder menu.
- (void)bookmarkFolderMenuItemClicked:(NSMenuItem*)item {
    NSString* url = [item.representedObject isKindOfClass:[NSString class]] ? item.representedObject : nil;
    if (url) [_tabManager newTabWithURL:url];
    [self rebuildTabStrip];
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Panel Actions
// ───────────────────────────────────────────────────────────────────────────────

- (void)showBookmarks:(id)_  { [[SidePanel shared] showBookmarks]; }
- (void)showHistory:(id)_    { [[SidePanel shared] showHistory]; }
- (void)showDownloads:(id)_  { [[DownloadsPanel shared] show]; }
- (void)showSettings:(id)_   { [SettingsPanel showAsSheetOnWindow:self.window]; }

/// Respond to settings changes (e.g., bookmarks bar toggle).
- (void)settingsDidChange:(NSNotification*)_ {
    _bookmarksBarView.hidden = ![SettingsManager profileShared].showBookmarksBar;
    [self layoutChrome];
    [self rebuildBookmarksBar];
    [self rebuildTabStrip];
    [self rebuildSidebarTabs];
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Profile Menu
// ───────────────────────────────────────────────────────────────────────────────

/// Show the profile pop-up menu from the profile button.
- (void)showProfileMenu:(id)sender {
    NSMenu* menu = [NSMenu new];
    NSMenuItem* header = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Active Profile: %@", _profile.name ?: @"Profile"]
                                                    action:nil keyEquivalent:@""];
    header.enabled = NO;
    [menu addItem:header];
    [menu addItem:[NSMenuItem separatorItem]];

    for (Profile* p in [ProfileManager shared].profiles) {
        NSMenuItem* item = [menu addItemWithTitle:p.name action:@selector(switchProfileFromMenu:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = p;
        item.image = [self profileAvatarImage:p size:18];
        if (p == _profile) item.state = NSControlStateValueOn;
    }
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* newProfile = [menu addItemWithTitle:@"New Profile…" action:@selector(createProfileFromMenu:) keyEquivalent:@""];
    newProfile.target = self;

    NSMenuItem* googleAccount = [menu addItemWithTitle:@"Google Account…" action:@selector(openGoogleAccountFromMenu:) keyEquivalent:@""];
    googleAccount.target = self;
    googleAccount.image = [NSImage imageWithSystemSymbolName:@"person.crop.circle.badge.checkmark" accessibilityDescription:@"Google Account"];

    NSMenuItem* colorItem = [[NSMenuItem alloc] initWithTitle:@"Profile Color" action:nil keyEquivalent:@""];
    NSMenu* colorMenu = [NSMenu new];
    NSArray<NSDictionary*>* colors = @[
        @{@"name": @"Blue", @"color": [NSColor systemBlueColor]},
        @{@"name": @"Green", @"color": [NSColor systemGreenColor]},
        @{@"name": @"Orange", @"color": [NSColor systemOrangeColor]},
        @{@"name": @"Pink", @"color": [NSColor systemPinkColor]},
        @{@"name": @"Purple", @"color": [NSColor systemPurpleColor]},
        @{@"name": @"Graphite", @"color": [NSColor systemGrayColor]},
    ];
    for (NSDictionary* entry in colors) {
        NSMenuItem* c = [[NSMenuItem alloc] initWithTitle:entry[@"name"]
                                                   action:@selector(setProfileColorFromMenu:)
                                            keyEquivalent:@""];
        c.target = self;
        c.representedObject = entry[@"color"];
        c.image = [self profileSwatchImage:entry[@"color"] size:14];
        [colorMenu addItem:c];
    }
    colorItem.submenu = colorMenu;
    [menu addItem:colorItem];

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* choosePicture = [menu addItemWithTitle:@"Choose Profile Picture…"
                                                action:@selector(chooseProfilePictureFromMenu:)
                                         keyEquivalent:@""];
    choosePicture.target = self;
    NSMenuItem* removePicture = [menu addItemWithTitle:@"Remove Profile Picture"
                                                action:@selector(removeProfilePictureFromMenu:)
                                         keyEquivalent:@""];
    removePicture.target = self;
    removePicture.enabled = _profile.avatarPath.length > 0;

    NSMenuItem* manage = [menu addItemWithTitle:@"Manage Profiles…" action:@selector(manageProfiles:) keyEquivalent:@""];
    manage.target = self;

    NSButton* btn = (NSButton*)sender;
    [NSMenu popUpContextMenu:menu withEvent:[NSApp currentEvent] forView:btn];
}

/// Open Google Account sign-in page with privacy warning if needed.
- (void)openGoogleAccountFromMenu:(id)_ {
    if ([SettingsManager profileShared].privateBrowsing) {
        NSAlert* alert = [NSAlert new];
        alert.messageText = @"Google sign-in will not be saved";
        alert.informativeText = @"Private browsing uses temporary website data. Turn it off in Settings to keep Google sign-in for this profile.";
        [alert addButtonWithTitle:@"Continue"];
        [alert addButtonWithTitle:@"Cancel"];
        [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
            if (result == NSAlertFirstButtonReturn)
                [self.tabManager loadURL:@"https://accounts.google.com/" inTab:self.tabManager.activeTab];
        }];
        return;
    }

    [_tabManager loadURL:@"https://accounts.google.com/" inTab:_tabManager.activeTab];
}

/// Switch to a different profile, opening a new window.
- (void)switchProfileFromMenu:(NSMenuItem*)item {
    Profile* p = (Profile*)item.representedObject;
    if (p == _profile) return;

    [ProfileManager shared].activeProfile = p;
    [[ProfileManager shared] saveProfiles];

    BrowserWindowController* wc = [[BrowserWindowController alloc] initWithProfile:p];
    [wc showWindow:nil];
}

/// Prompt for a new profile name and create it.
- (void)createProfileFromMenu:(id)_ {
    NSAlert* alert = [NSAlert new];
    alert.messageText = @"New Profile";
    alert.informativeText = @"Create a separate browser profile with its own bookmarks, history, settings, and website data.";
    [alert addButtonWithTitle:@"Create"];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField* field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    field.placeholderString = @"Profile name";
    alert.accessoryView = field;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSAlertFirstButtonReturn) return;
        NSString* name = [field.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!name.length) name = @"New Profile";
        Profile* p = [[ProfileManager shared] createProfileWithName:name];
        [ProfileManager shared].activeProfile = p;
        [[ProfileManager shared] saveProfiles];
        BrowserWindowController* wc = [[BrowserWindowController alloc] initWithProfile:p];
        [wc showWindow:nil];
    }];
}

/// Set the profile accent color from the menu.
- (void)setProfileColorFromMenu:(NSMenuItem*)item {
    NSColor* color = [item.representedObject isKindOfClass:[NSColor class]] ? item.representedObject : [NSColor controlAccentColor];
    _profile.color = color;
    [[ProfileManager shared] saveProfiles];
    [self updateProfileButtonIcon];
}

/// Open a file picker to choose a profile picture.
- (void)chooseProfilePictureFromMenu:(id)_ {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.allowedContentTypes = @[ UTTypeImage ];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || !panel.URL) return;
        [_profile setAvatarFromImageURL:panel.URL];
        [[ProfileManager shared] saveProfiles];
        [self updateProfileButtonIcon];
    }];
}

/// Remove the current profile picture.
- (void)removeProfilePictureFromMenu:(id)_ {
    [_profile clearAvatar];
    [[ProfileManager shared] saveProfiles];
    [self updateProfileButtonIcon];
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Profile UI Helpers
// ───────────────────────────────────────────────────────────────────────────────

/// Update the profile button image to show the current profile's avatar or swatch.
- (void)updateProfileButtonIcon {
    NSImage* img = [self profileAvatarImage:_profile size:22];
    if (img) {
        _profileBtn.image = img;
        _profileBtn.contentTintColor = nil;
    } else {
        NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration
            configurationWithPointSize:15 weight:NSFontWeightRegular];
        _profileBtn.image = [[NSImage imageWithSystemSymbolName:@"person.circle"
                                       accessibilityDescription:@"Profile"]
                             imageWithSymbolConfiguration:cfg];
        _profileBtn.contentTintColor = _profile.color ?: [NSColor controlAccentColor];
    }
}

/// Generate a circular avatar image (or fallback swatch) for a profile.
- (NSImage*)profileAvatarImage:(Profile*)profile size:(CGFloat)size {
    NSImage* source = [profile avatarImage];
    if (source) return [self circularImageFromImage:source size:size borderColor:profile.color ?: [NSColor controlAccentColor]];
    return [self profileSwatchImage:profile.color ?: [NSColor controlAccentColor] size:size];
}

/// Generate a circular colored swatch for a profile with no avatar.
- (NSImage*)profileSwatchImage:(NSColor*)color size:(CGFloat)size {
    NSImage* image = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [image lockFocus];
    NSBezierPath* path = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(1, 1, size - 2, size - 2)];
    [color setFill];
    [path fill];
    [[NSColor separatorColor] setStroke];
    path.lineWidth = 1;
    [path stroke];
    [image unlockFocus];
    return image;
}

/// Crop a source image to a circle with a border.
- (NSImage*)circularImageFromImage:(NSImage*)source size:(CGFloat)size borderColor:(NSColor*)borderColor {
    NSImage* image = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [image lockFocus];
    NSRect rect = NSMakeRect(1, 1, size - 2, size - 2);
    NSBezierPath* clip = [NSBezierPath bezierPathWithOvalInRect:rect];
    [clip addClip];
    [source drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    [borderColor setStroke];
    clip.lineWidth = 1.5;
    [clip stroke];
    [image unlockFocus];
    return image;
}

/// Open the profile management panel.
- (void)manageProfiles:(id)_ {
    [ProfilePanel showAsSheetOnWindow:self.window];
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Find in Page
// ───────────────────────────────────────────────────────────────────────────────

/** @brief   Show the find bar. */
- (void)openFindBar:(id)_ {
    _findBarVisible = YES;
    _findBarView.hidden = NO;
    [self recalcContentArea];
    [self.window makeFirstResponder:_findField];
}

/** @brief   Hide the find bar and clear selection. */
- (void)closeFindBar:(id)_ {
    _findBarVisible = NO;
    _findBarView.hidden = YES;
    [self recalcContentArea];
    [_tabManager.activeTab.webView evaluateJavaScript:
        @"window.getSelection().removeAllRanges();" completionHandler:nil];
    _findStatusLabel.stringValue = @"";
}

/** @brief   Find next occurrence. */
- (void)findNext:(id)_ { [self findInPage:YES]; }
/** @brief   Find previous occurrence. */
- (void)findPrev:(id)_ { [self findInPage:NO]; }

/**
 * @brief   Perform a find-in-page search using window.find().
 *
 * @param   forward  YES for forward search, NO for backward.
 */
- (void)findInPage:(BOOL)forward {
    NSString* query = _findField.stringValue;
    if (!query.length) { _findStatusLabel.stringValue = @""; return; }

    NSString* js = [NSString stringWithFormat:
        @"window.find(%@, false, %@, true, false, false, false)",
        [self jsString:query], forward ? @"false" : @"true"];

    __unsafe_unretained typeof(self) ws = self;
    [_tabManager.activeTab.webView evaluateJavaScript:js completionHandler:^(id res, NSError* _) {
        BOOL found = [res boolValue];
        ws.findStatusLabel.stringValue = found ? @"" : @"Not found";
        ws.findStatusLabel.textColor   = found
            ? [NSColor secondaryLabelColor] : [NSColor systemRedColor];
    }];
}

/// Escape a string for use in a JS string literal.
- (NSString*)jsString:(NSString*)s {
    NSString* escaped = [s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}

// ───────────────────────────────────────────────────────────────────────────────
// @name General Helpers
// ───────────────────────────────────────────────────────────────────────────────

/// Enable/disable the back and forward navigation buttons.
- (void)updateNavButtons {
    WKWebView* wv = _tabManager.activeTab.webView;
    _backBtn.enabled = wv.canGoBack;
    _fwdBtn.enabled  = wv.canGoForward;
}

/**
 * @brief   Rebuild the tab strip: remove old buttons, create new ones with
 *          favicons, titles, close buttons, and click targets.
 */
- (void)rebuildTabStrip {
    for (NSView* v in _tabBarView.subviews.copy)
        if ([v isKindOfClass:[NSButton class]] || [v.identifier isEqualToString:@"tabItem"])
            [v removeFromSuperview];

    NSArray<BrowserTab*>* tabs = _tabManager.tabs;
    CGFloat totalW = _tabBarView.bounds.size.width - 4;
    NSInteger pinnedCount = 0;
    for (BrowserTab* tab in tabs) if (tab.pinned) pinnedCount++;
    CGFloat pinnedW = 48;
    CGFloat availableForRegular = MAX(kTabMinW, totalW - pinnedCount * (pinnedW + 2));
    NSInteger regularCount = MAX(1, (NSInteger)tabs.count - pinnedCount);
    CGFloat regularTabW = MIN(kTabW, MAX(kTabMinW, (availableForRegular / regularCount) - 2));
    CGFloat x = 2;

    for (NSInteger i = 0; i < (NSInteger)tabs.count; i++) {
        BrowserTab* tab = tabs[i];
        BOOL active = (i == _tabManager.activeIndex);
        CGFloat tabW = tab.pinned ? pinnedW : regularTabW;
        BOOL showClose = !tab.pinned && (tabW > 100);

        NSView* item = [[NSView alloc] initWithFrame:
                        NSMakeRect(x, 2, tabW, kTabBarH-4)];
        item.wantsLayer = YES;
        item.layer.cornerRadius = 6;
        item.identifier = @"tabItem";

        if (active) {
            item.layer.backgroundColor = [NSColor colorWithWhite:1.0 alpha:0.15].CGColor;
            item.layer.borderColor     = [NSColor colorWithWhite:1.0 alpha:0.12].CGColor;
            item.layer.borderWidth     = 0.5;
        }

        // Favicon
        NSImageView* iv = [[NSImageView alloc] initWithFrame:NSMakeRect(8, (kTabBarH-4-16)/2, 16, 16)];
        iv.image = tab.favicon;
        iv.imageScaling = NSImageScaleProportionallyUpOrDown;
        [item addSubview:iv];

        // Title label
        NSTextField* lbl = [NSTextField labelWithString:tab.pinned ? @"" : (tab.title.length ? tab.title : @"New Tab")];
        CGFloat lblX = 28;
        CGFloat lblW = showClose ? tabW - 54 : tabW - 36;
        lbl.frame = NSMakeRect(lblX, (kTabBarH-4-16)/2, lblW, 16);
        lbl.font  = active
            ? [NSFont systemFontOfSize:12 weight:NSFontWeightMedium]
            : [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
        lbl.textColor    = active ? [NSColor labelColor] : [NSColor secondaryLabelColor];
        lbl.lineBreakMode = NSLineBreakByTruncatingTail;
        [item addSubview:lbl];

        // Close button
        if (showClose) {
            NSButton* closeBtn = [self makeSymbolButton:@"xmark" size:9 tooltip:@"Close Tab"];
            closeBtn.frame  = NSMakeRect(tabW - 26, (kTabBarH-4-18)/2, 18, 18);
            closeBtn.tag    = i;
            closeBtn.target = self;
            closeBtn.action = @selector(closeTabButtonClicked:);
            closeBtn.alphaValue = active ? 0.7 : 0.0;
            [item addSubview:closeBtn];
        }

        if (tab.pinned) {
            NSImageView* pin = [[NSImageView alloc] initWithFrame:NSMakeRect(tabW - 17, 5, 11, 11)];
            pin.image = [NSImage imageWithSystemSymbolName:@"pin.fill" accessibilityDescription:nil];
            pin.contentTintColor = active ? [NSColor labelColor] : [NSColor secondaryLabelColor];
            [item addSubview:pin];
        }

        // Invisible click target
        NSButton* hitArea = [[NSButton alloc] initWithFrame:
                             NSMakeRect(0, 0, showClose ? tabW - 24 : tabW, kTabBarH-4)];
        hitArea.bordered    = NO;
        hitArea.transparent = YES;
        hitArea.tag         = i;
        hitArea.target      = self;
        hitArea.action      = @selector(tabButtonClicked:);
        [item addSubview:hitArea];

        tab.tabButton = hitArea;

        [_tabBarView addSubview:item];
        x += tabW + 2;
    }

    // "+" new-tab button
    NSButton* addBtn = [self makeSymbolButton:@"plus" size:12 tooltip:@"New Tab (⌘T)"];
    CGFloat addX = x + 4;
    addBtn.frame = NSMakeRect(addX, (kTabBarH - 24) / 2, 24, 24);
    addBtn.target = self;
    addBtn.action = @selector(newTab:);
    [_tabBarView addSubview:addBtn];
}

/**
 * @brief   Create an SF Symbols toolbar button.
 *
 * @param   sym     The SF Symbol name (e.g. @"chevron.left").
 * @param   ptSize  The point size of the symbol.
 * @param   tip     The tooltip string.
 * @return  A configured NSButton with circular bezel style.
 */
- (NSButton*)makeSymbolButton:(NSString*)sym size:(CGFloat)ptSize tooltip:(NSString*)tip {
    NSImageSymbolConfiguration* cfg = [NSImageSymbolConfiguration
        configurationWithPointSize:ptSize weight:NSFontWeightRegular];
    NSImage* img = [[NSImage imageWithSystemSymbolName:sym accessibilityDescription:tip]
                    imageWithSymbolConfiguration:cfg];
    NSButton* btn = [NSButton buttonWithImage:img target:nil action:nil];
    btn.bezelStyle   = NSBezelStyleCircular;
    btn.bordered     = NO;
    btn.toolTip      = tip;
    btn.imageScaling = NSImageScaleProportionallyDown;
    return btn;
}

/// Legacy overload: make a 15pt symbol button.
- (NSButton*)makeSymbolButton:(NSString*)sym tooltip:(NSString*)tip {
    return [self makeSymbolButton:sym size:15 tooltip:tip];
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Context Menu Injection (Right-Click on Web View)
// ───────────────────────────────────────────────────────────────────────────────

/**
 * @brief   Inject a JS event listener that tracks context-menu link targets.
 *
 * @details Uses a document-level contextmenu listener to store the closest
 *          anchor's href on window._kbContextURL. This is a fallback for
 *          macOS < 13 which lacks the WKUIDelegate context menu API.
 *
 * @param   wv  The WKWebView to inject the script into.
 */
- (void)injectContextMenuScript:(WKWebView*)wv {
    NSString* js = @""
    "document.addEventListener('contextmenu', function(e) {"
    "  var el = e.target;"
    "  var link = el.closest('a');"
    "  if (link) {"
    "    window._kbContextURL = link.href;"
    "  } else {"
    "    window._kbContextURL = null;"
    "  }"
    "}, true);";
    [wv evaluateJavaScript:js completionHandler:nil];
}

// ───────────────────────────────────────────────────────────────────────────────
// @name NSTextFieldDelegate (URL field autocomplete)
// ───────────────────────────────────────────────────────────────────────────────

/**
 * @brief   Provide URL autocomplete suggestions from open tabs, history, and bookmarks.
 */
- (NSArray<NSString*>*)control:(NSControl*)control textView:(NSTextView*)textView completions:(NSArray<NSString*>*)words forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(NSInteger*)index {
    if (control != _urlField) return words;

    NSString* partial = [control.stringValue substringWithRange:charRange];
    if (partial.length < 2) return words;

    NSMutableArray* results = [NSMutableArray new];
    for (BrowserTab* t in _tabManager.tabs) {
        if ([t.url containsString:partial]) [results addObject:t.url];
    }
    for (HistoryEntry* e in [HistoryManager profileShared].entries) {
        if ([e.url containsString:partial]) [results addObject:e.url];
        if (results.count > 10) break;
    }
    for (Bookmark* b in [BookmarkManager profileShared].bookmarks) {
        if ([b.url containsString:partial]) [results addObject:b.url];
        if (results.count > 20) break;
    }

    return [[NSSet setWithArray:results] allObjects];
}

// ───────────────────────────────────────────────────────────────────────────────
// @name NSWindowDelegate
// ───────────────────────────────────────────────────────────────────────────────

- (void)windowDidResize:(NSNotification*)_ {
    [self layoutChrome];
    [self rebuildBookmarksBar];
    [self rebuildTabStrip];
}

- (void)windowWillClose:(NSNotification*)_ {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSApp terminate:nil];
}

@end
