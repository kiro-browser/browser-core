/**
 * @file      TabManager.h
 * @project   BuildBrowser
 * @brief     Tab lifecycle, navigation, and WebView management.
 *
 * @details   Owns all BrowserTab instances for a single window. Handles
 *            tab creation, switching, closing, URL loading, favicon fetching,
 *            context menus, and delegates (WKNavigationDelegate, WKUIDelegate).
 *            Communicates state changes via callback blocks wired by the
 *            owning BrowserWindowController.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#pragma once
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "Profile.h"

#pragma mark - BrowserTab Model

/**
 * @interface BrowserTab
 * @brief     Represents a single tab with its WebView and associated UI.
 *
 * @details   One BrowserTab = one WKWebView + its button in the tab strip.
 *            Stores the current title, URL, favicon, certificate info
 *            (for the security indicator), and pinned state.
 */
@interface BrowserTab : NSObject

/// The WKWebView used for rendering web content.
@property (strong) WKWebView*   webView;
/// The NSButton shown in the tab strip for this tab.
@property (strong) NSButton*    tabButton;
/// The current page title.
@property (copy)   NSString*    title;
/// The current page URL string.
@property (copy)   NSString*    url;
/// The favicon image (fetched from page or Google favicon API).
@property (strong) NSImage*     favicon;
/// Certificate information dictionary from NSURLAuthenticationChallenge.
@property (strong) NSDictionary* certificateInfo;
/// Whether the tab is pinned (pinned tabs survive close-last-tab logic).
@property (assign) BOOL         pinned;

@end

#pragma mark - TabManager

/**
 * @interface TabManager
 * @brief     Manages all tabs for a browser window.
 *
 * @details   Creates WKWebView instances with per-profile configuration
 *            (data store, content blocker, JavaScript settings). Observes
 *            KVO for estimatedProgress, title, and URL changes. Fires
 *            callback blocks for every state change so the UI layer
 *            (BrowserWindowController) can update the chrome.
 */
@interface TabManager : NSObject

/**
 * @brief   Initialize with a profile for data store isolation.
 * @param   profile  The profile whose data store and settings to use.
 * @return  An initialized TabManager.
 */
- (instancetype)initWithProfile:(Profile*)profile;

/// The profile associated with this tab manager.
@property (readonly) Profile* profile;

/// All currently open BrowserTab objects.
@property (readonly) NSArray<BrowserTab*>* tabs;
/// The currently visible / active tab.
@property (readonly) BrowserTab*           activeTab;
/// The index of the active tab (or -1 if no tabs).
@property (readonly) NSInteger             activeIndex;

// ── Callback blocks (wired by BrowserWindowController) ────────────────────────

/// Fired when a new tab is created.
@property (copy) void (^onTabAdded)(BrowserTab* tab, NSInteger index);
/// Fired after a tab is removed.
@property (copy) void (^onTabClosed)(NSInteger index);
/// Fired when the active tab changes.
@property (copy) void (^onTabSwitched)(BrowserTab* tab, NSInteger index);
/// Fired when a tab's title changes.
@property (copy) void (^onTitleChanged)(BrowserTab* tab, NSString* title);
/// Fired when a tab's URL changes.
@property (copy) void (^onURLChanged)(BrowserTab* tab, NSString* url);
/// Fired when loading progress updates (0.0 to 1.0).
@property (copy) void (^onLoadProgress)(BrowserTab* tab, double progress);
/// Fired when the loading state changes (started/stopped).
@property (copy) void (^onLoadStateChanged)(BrowserTab* tab, BOOL loading);
/// Fired when a favicon is fetched for a tab.
@property (copy) void (^onFaviconChanged)(BrowserTab* tab, NSImage* icon);
/// Fired on buildbrowser://command navigation for internal routing.
@property (copy) void (^onInternalCommand)(NSString* command);

// ── Tab operations ───────────────────────────────────────────────────────────

/**
 * @brief   Create a new tab and start loading the given URL.
 * @param   url  The URL to load (passed through sanitizeURL:).
 * @return  The newly created BrowserTab.
 */
- (BrowserTab*)newTabWithURL:(NSString*)url;

/**
 * @brief   Load (or reload) a URL in the specified tab.
 * @details Handles buildbrowser:// commands, file:// URLs, and standard
 *          HTTP/HTTPS requests.
 * @param   raw  The raw URL string (will be sanitized).
 * @param   tab  The target tab.
 */
- (void)loadURL:(NSString*)raw inTab:(BrowserTab*)tab;

/**
 * @brief   Close the tab at the given index.
 * @details If this is the last tab, navigates home instead of closing.
 *          Removes KVO observers before releasing the web view.
 * @param   index  The index of the tab to close.
 */
- (void)closeTabAtIndex:(NSInteger)index;

/**
 * @brief   Switch to the tab at the given index.
 * @param   index  The index to switch to (must be in range).
 */
- (void)switchToIndex:(NSInteger)index;

/**
 * @brief   Set or clear the pinned state for a tab.
 * @param   pinned Whether the tab should be pinned.
 * @param   index  The index of the tab.
 */
- (void)setPinned:(BOOL)pinned forTabAtIndex:(NSInteger)index;

/**
 * @brief   Sanitize and normalize a raw URL input string.
 * @details Converts search queries to the configured search engine URL,
 *          adds https:// prefix when appropriate, resolves @alias shortcuts,
 *          handles file:// URLs and local paths.
 *
 * @param   input  The raw input string.
 * @return  A fully qualified URL string suitable for loading.
 */
+ (NSString*)sanitizeURL:(NSString*)input;

@end
