/**
 * @file      AppDelegate.mm
 * @project   BuildBrowser
 * @brief     Application lifecycle and global event handling.
 *
 * @details   Manages the NSApplication lifecycle (launch, terminate, open-file).
 *          Builds the main menu bar, saves/restores browser sessions, handles
 *          URL/file open requests, and shows the default browser prompt on
 *          first launch. Owns the array of BrowserWindowController instances.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#import "BrowserWindowController.h"
#import "SettingsManager.h"
#import "UpdateManager.h"
#import "ProfileManager.h"
#import "BookmarkManager.h"
#import "HistoryManager.h"
#import "DefaultBrowserManager.h"
#import <Cocoa/Cocoa.h>

#pragma mark - Private Interface

@interface AppDelegate : NSObject <NSApplicationDelegate>
/// All open browser windows.
@property(strong) NSMutableArray<BrowserWindowController*> *windows;
/// URLs queued before the first window was ready.
@property(strong) NSMutableArray<NSURL*> *pendingOpenURLs;
@end

/// NSUserDefaults key to track whether the default browser prompt has been shown.
static NSString* const kDefaultBrowserPromptSeen = @"BuildBrowser.defaultBrowserPromptSeen";

#pragma mark - Implementation

@implementation AppDelegate

// ───────────────────────────────────────────────────────────────────────────────
// @name Application Lifecycle
// ───────────────────────────────────────────────────────────────────────────────

/**
 * @brief   Called when the application has finished launching.
 *
 * @details   Sets up the menu bar and application icon. Loads the previous
 *            session (if available) or opens a new window with the default
 *            homepage. Processes any pending URLs from application:openURLs:,
 *            shows the default browser prompt if needed, and triggers a
 *            silent update check after a 2-second delay.
 *
 * @param   _  The NSNotification object (unused).
 */
- (void)applicationDidFinishLaunching:(NSNotification *)_ {
  self.windows = [NSMutableArray new];
  if (!self.pendingOpenURLs) self.pendingOpenURLs = [NSMutableArray new];
  [self buildMenu];
  [self applyApplicationIcon];

  // Load the last session if available, otherwise open a new window
  Profile* p = [ProfileManager shared].activeProfile;
  NSDictionary* session = [self loadSession];
  NSArray* urls = [session[@"urls"] isKindOfClass:[NSArray class]] ? session[@"urls"] : nil;
  NSArray* pinned = [session[@"pinned"] isKindOfClass:[NSArray class]] ? session[@"pinned"] : nil;
  NSInteger activeIndex = [session[@"activeIndex"] respondsToSelector:@selector(integerValue)]
      ? [session[@"activeIndex"] integerValue] : 0;
  BrowserWindowController* wc = [[BrowserWindowController alloc] initWithProfile:p restoredURLs:urls pinned:pinned activeIndex:activeIndex];
  [self.windows addObject:wc];
  [wc showWindow:nil];
  [wc restoreWindowState:session];
  [self openPendingURLsIfNeeded];
  [self showDefaultBrowserPromptIfNeededForWindow:wc.window];

  // Delayed silent update check
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if ([SettingsManager profileShared].autoCheckUpdates) {
      [[UpdateManager shared] checkForUpdatesSilently];
    }
  });
}

/**
 * @brief   Sets the application icon from the bundle's BuildBrowser.icns.
 *
 * @method  applyApplicationIcon
 */
- (void)applyApplicationIcon {
    NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"BuildBrowser" ofType:@"icns"];
    NSImage *icon = iconPath ? [[NSImage alloc] initWithContentsOfFile:iconPath] : nil;
    if (icon) {
        [NSApp setApplicationIconImage:icon];
    }
}

/**
 * @brief   Called when the application is about to terminate.
 *
 * @details   Saves the current session (open tabs, pinned state, window frame).
 *
 * @param   _  The NSNotification object (unused).
 */
- (void)applicationWillTerminate:(NSNotification*)_ {
  [self saveSession];
}

/**
 * @brief   Determine whether the app should quit when the last window closes.
 *
 * @return  YES (quit when all windows are closed).
 */
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)_ {
  return YES;
}

// ───────────────────────────────────────────────────────────────────────────────
// @name URL / File Handling
// ───────────────────────────────────────────────────────────────────────────────

/**
 * @brief   Handle URLs opened from other applications (e.g. clicked links).
 *
 * @details   If no windows exist yet, queues the URLs for later processing.
 *
 * @param   _      The application (unused).
 * @param   urls   The URLs to open.
 */
- (void)application:(NSApplication*)_ openURLs:(NSArray<NSURL*>*)urls {
  if (!urls.count) return;
  if (!self.windows.count) {
    if (!self.pendingOpenURLs) self.pendingOpenURLs = [NSMutableArray new];
    [self.pendingOpenURLs addObjectsFromArray:urls];
    return;
  }
  [self openURLsInBrowser:urls];
}

/**
 * @brief   Handle files opened with the application.
 *
 * @param   _          The application (unused).
 * @param   filenames  The file paths to open.
 */
- (void)application:(NSApplication*)_ openFiles:(NSArray<NSString*>*)filenames {
  if (!filenames.count) return;
  NSMutableArray<NSURL*>* urls = [NSMutableArray new];
  for (NSString* path in filenames) {
    if (![path isKindOfClass:[NSString class]] || !path.length) continue;
    [urls addObject:[NSURL fileURLWithPath:path]];
  }
  if (!urls.count) {
    [NSApp replyToOpenOrPrint:NSApplicationDelegateReplyFailure];
    return;
  }
  if (!self.windows.count) {
    if (!self.pendingOpenURLs) self.pendingOpenURLs = [NSMutableArray new];
    [self.pendingOpenURLs addObjectsFromArray:urls];
  } else {
    [self openURLsInBrowser:urls];
  }
  [NSApp replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

/**
 * @brief   Process any URLs that were queued before the first window was ready.
 */
- (void)openPendingURLsIfNeeded {
  if (!self.pendingOpenURLs.count) return;
  NSArray<NSURL*>* urls = self.pendingOpenURLs.copy;
  [self.pendingOpenURLs removeAllObjects];
  [self openURLsInBrowser:urls];
}

/**
 * @brief   Open URLs in the first browser window.
 *
 * @param   urls  The URL objects to open in new tabs.
 */
- (void)openURLsInBrowser:(NSArray<NSURL*>*)urls {
  BrowserWindowController* wc = [self firstBrowserWindowController];
  if (!wc) return;
  for (NSURL* url in urls) {
    if (![url isKindOfClass:[NSURL class]]) continue;
    [wc openURLInNewTab:url.absoluteString];
  }
  [NSApp activateIgnoringOtherApps:YES];
}

/**
 * @brief   Return the first BrowserWindowController from the windows array.
 *
 * @return  The first valid controller, or nil.
 */
- (BrowserWindowController*)firstBrowserWindowController {
  for (BrowserWindowController* candidate in self.windows) {
    if ([candidate isKindOfClass:[BrowserWindowController class]]) return candidate;
  }
  return nil;
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Default Browser Prompt
// ───────────────────────────────────────────────────────────────────────────────

/**
 * @brief   Show a prompt asking to set BuildBrowser as default (once only).
 *
 * @param   window  The window to attach the sheet to.
 */
- (void)showDefaultBrowserPromptIfNeededForWindow:(NSWindow*)window {
  if (!window) return;
  NSUserDefaults* defaults = NSUserDefaults.standardUserDefaults;
  if ([defaults boolForKey:kDefaultBrowserPromptSeen]) return;
  if ([DefaultBrowserManager isDefaultBrowser]) return;

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(700 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
    if ([DefaultBrowserManager isDefaultBrowser]) return;
    NSAlert* alert = [NSAlert new];
    alert.messageText = @"Make BuildBrowser your default browser?";
    alert.informativeText = @"Links from other apps will open in BuildBrowser.";
    [alert addButtonWithTitle:@"Make Default"];
    [alert addButtonWithTitle:@"Not Now"];
    [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
      [defaults setBool:YES forKey:kDefaultBrowserPromptSeen];
      if (response != NSAlertFirstButtonReturn) return;

      NSError* error = nil;
      if (![DefaultBrowserManager setAsDefaultBrowserWithError:&error]) {
        NSAlert* failure = [NSAlert new];
        failure.messageText = @"Could not update default browser";
        failure.informativeText = error.localizedDescription ?: @"Open macOS System Settings and choose BuildBrowser as the default browser.";
        [failure addButtonWithTitle:@"OK"];
        [failure beginSheetModalForWindow:window completionHandler:nil];
      }
    }];
  });
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Menu Bar Construction
// ───────────────────────────────────────────────────────────────────────────────

/**
 * @brief   Build the main application menu bar.
 *
 * @details   Creates menus for BuildBrowser (About, Settings, Quit),
 *            File (New Tab, Close Tab), Edit (Cut, Copy, Paste, Find),
 *            and View (Reload, Back, Forward, Pin Tab, Bookmarks, History,
 *            Downloads, Bookmark This Page).
 */
- (void)buildMenu {
  NSMenu *bar = [NSMenu new];

  // ── BuildBrowser ──
  NSMenu *appMenu = [NSMenu new];
  [appMenu addItemWithTitle:@"About BuildBrowser" action:@selector(showAbout:) keyEquivalent:@""];
  [appMenu addItem:[NSMenuItem separatorItem]];
  [appMenu addItemWithTitle:@"Settings…" action:@selector(showSettings:) keyEquivalent:@","];
  [appMenu addItemWithTitle:@"Check for Updates…" action:@selector(checkForUpdates:) keyEquivalent:@""];
  [appMenu addItem:[NSMenuItem separatorItem]];
  [appMenu addItemWithTitle:@"Quit BuildBrowser" action:@selector(terminate:) keyEquivalent:@"q"];
  NSMenuItem *appItem = [NSMenuItem new];
  appItem.submenu = appMenu;
  [bar addItem:appItem];

  // ── File ──
  NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
  [fileMenu addItemWithTitle:@"New Tab" action:@selector(newTab:) keyEquivalent:@"t"];
  [fileMenu addItemWithTitle:@"Close Tab" action:@selector(closeCurrentTab:) keyEquivalent:@"w"];
  NSMenuItem *fileItem = [NSMenuItem new];
  fileItem.submenu = fileMenu;
  [bar addItem:fileItem];

  // ── Edit ──
  NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
  [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
  [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
  [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
  [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
  [editMenu addItem:[NSMenuItem separatorItem]];
  [editMenu addItemWithTitle:@"Find…" action:@selector(openFindBar:) keyEquivalent:@"f"];
  [editMenu addItemWithTitle:@"Find Next" action:@selector(findNext:) keyEquivalent:@"g"];
  NSMenuItem *editItem = [NSMenuItem new];
  editItem.submenu = editMenu;
  [bar addItem:editItem];

  // ── View ──
  NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
  [viewMenu addItemWithTitle:@"Reload" action:@selector(reloadOrStop:) keyEquivalent:@"r"];
  [viewMenu addItemWithTitle:@"Back" action:@selector(goBack:) keyEquivalent:@"["];
  [viewMenu addItemWithTitle:@"Forward" action:@selector(goForward:) keyEquivalent:@"]"];
  [viewMenu addItem:[NSMenuItem separatorItem]];
  NSMenuItem* sidebarItem = [viewMenu addItemWithTitle:@"Toggle Sidebar" action:@selector(toggleSidebarMode:) keyEquivalent:@"s"];
  sidebarItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
  [viewMenu addItem:[NSMenuItem separatorItem]];
  [viewMenu addItemWithTitle:@"Pin Tab" action:@selector(togglePinCurrentTab:) keyEquivalent:@"p"];
  [viewMenu addItem:[NSMenuItem separatorItem]];
  [viewMenu addItemWithTitle:@"Bookmarks" action:@selector(showBookmarks:) keyEquivalent:@"b"];
  [viewMenu addItemWithTitle:@"History" action:@selector(showHistory:) keyEquivalent:@"y"];
  [viewMenu addItemWithTitle:@"Downloads" action:@selector(showDownloads:) keyEquivalent:@"j"];
  [viewMenu addItem:[NSMenuItem separatorItem]];
  [viewMenu addItemWithTitle:@"Bookmark This Page" action:@selector(toggleBookmark:) keyEquivalent:@"d"];
  NSMenuItem *viewItem = [NSMenuItem new];
  viewItem.submenu = viewMenu;
  [bar addItem:viewItem];

  NSApp.mainMenu = bar;
}

// ───────────────────────────────────────────────────────────────────────────────
// @name About / Session
// ───────────────────────────────────────────────────────────────────────────────

/**
 * @brief   Show the standard About panel with version and build info.
 *
 * @param   _  The sender (unused).
 */
- (void)showAbout:(id)_ {
  NSDictionary* info = [[NSBundle mainBundle] infoDictionary];
  NSString* version = info[@"CFBundleShortVersionString"] ?: @"1.0";
  NSString* build = info[@"CFBundleVersion"] ?: @"1";
  NSImage* icon = [NSApp applicationIconImage];
  [NSApp orderFrontStandardAboutPanelWithOptions:@{
    NSAboutPanelOptionApplicationName: @"BuildBrowser",
    NSAboutPanelOptionApplicationVersion: version,
    NSAboutPanelOptionVersion: [NSString stringWithFormat:@"Build %@", build],
    NSAboutPanelOptionCredits: [[NSAttributedString alloc] initWithString:
      @"A lightweight native macOS browser built with Cocoa and WebKit."],
    NSAboutPanelOptionApplicationIcon: icon ?: [NSImage new]
  }];
}

/// Return the path to the session plist file.
- (NSString*)sessionPath {
  NSString* support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
  NSString* base = [support stringByAppendingPathComponent:@"BuildBrowser"];
  [[NSFileManager defaultManager] createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:nil];
  return [base stringByAppendingPathComponent:@"session.plist"];
}

/// Load and return the saved session dictionary.
- (NSDictionary*)loadSession {
  NSDictionary* session = [NSDictionary dictionaryWithContentsOfFile:[self sessionPath]];
  return [session isKindOfClass:[NSDictionary class]] ? session : @{};
}

/**
 * @brief   Save the current window session (URLs, pinned state, frame).
 */
- (void)saveSession {
  BrowserWindowController* wc = nil;
  for (BrowserWindowController* candidate in self.windows) {
    if ([candidate isKindOfClass:[BrowserWindowController class]]) {
      wc = candidate;
      break;
    }
  }
  NSDictionary* state = [wc sessionState] ?: @{};
  [state writeToFile:[self sessionPath] atomically:YES];
}

/**
 * @brief   Forward the menu Close Tab action to the active window controller.
 *
 * @param   _  The sender (unused).
 */
- (void)closeCurrentTab:(id)_ {
  NSWindow* win = [NSApp keyWindow];
  if ([win.windowController isKindOfClass:[BrowserWindowController class]]) {
    BrowserWindowController* wc = (BrowserWindowController*)win.windowController;
    [wc.tabManager closeTabAtIndex:wc.tabManager.activeIndex];
  }
}

/// Trigger an update check from the menu.
- (void)checkForUpdates:(id)_ {
  [[UpdateManager shared] checkForUpdates];
}

@end
