#import "BrowserWindowController.h"
#import "SettingsManager.h"
#import "UpdateManager.h"
#import "ProfileManager.h"
#import "BookmarkManager.h"
#import "HistoryManager.h"
#import "DefaultBrowserManager.h"
#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(strong) NSMutableArray<BrowserWindowController*> *windows;
@property(strong) NSMutableArray<NSURL*> *pendingOpenURLs;
@end

static NSString* const kDefaultBrowserPromptSeen = @"BuildBrowser.defaultBrowserPromptSeen";

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)_ {
  self.windows = [NSMutableArray new];
  if (!self.pendingOpenURLs) self.pendingOpenURLs = [NSMutableArray new];
  [self buildMenu];
  [self applyApplicationIcon];
  
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
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if ([SettingsManager profileShared].autoCheckUpdates) {
      [[UpdateManager shared] checkForUpdatesSilently];
    }
  });
}

/**
 * Sets the application icon to "BuildBrowser.icns" from the main bundle.
 * @method applyApplicationIcon
 * @return void
 */
- (void)applyApplicationIcon {
    // Path to the icon resource within the app bundle
    NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"BuildBrowser" ofType:@"icns"];
    
    // Initialize an NSImage with the icon file if the path exists
    NSImage *icon = iconPath ? [[NSImage alloc] initWithContentsOfFile:iconPath] : nil;
    
    // If the icon was successfully loaded, set it as the application's icon
    if (icon) {
        [NSApp setApplicationIconImage:icon];
    }
}

- (void)applicationWillTerminate:(NSNotification*)_ {
  [self saveSession];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)_ {
  return YES;
}

- (void)application:(NSApplication*)_ openURLs:(NSArray<NSURL*>*)urls {
  if (!urls.count) return;
  if (!self.windows.count) {
    if (!self.pendingOpenURLs) self.pendingOpenURLs = [NSMutableArray new];
    [self.pendingOpenURLs addObjectsFromArray:urls];
    return;
  }
  [self openURLsInBrowser:urls];
}

- (void)openPendingURLsIfNeeded {
  if (!self.pendingOpenURLs.count) return;
  NSArray<NSURL*>* urls = self.pendingOpenURLs.copy;
  [self.pendingOpenURLs removeAllObjects];
  [self openURLsInBrowser:urls];
}

- (void)openURLsInBrowser:(NSArray<NSURL*>*)urls {
  BrowserWindowController* wc = [self firstBrowserWindowController];
  if (!wc) return;
  for (NSURL* url in urls) {
    if (![url isKindOfClass:[NSURL class]]) continue;
    [wc openURLInNewTab:url.absoluteString];
  }
  [NSApp activateIgnoringOtherApps:YES];
}

- (BrowserWindowController*)firstBrowserWindowController {
  for (BrowserWindowController* candidate in self.windows) {
    if ([candidate isKindOfClass:[BrowserWindowController class]]) return candidate;
  }
  return nil;
}

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

// ── Menu bar
// ──────────────────────────────────────────────────────────────────
- (void)buildMenu {
  NSMenu *bar = [NSMenu new];

  // ── BuildBrowser
  // ──────────────────────────────────────────────────────────────
  NSMenu *appMenu = [NSMenu new];
  [appMenu addItemWithTitle:@"About BuildBrowser"
                     action:@selector(showAbout:)
              keyEquivalent:@""];
  [appMenu addItem:[NSMenuItem separatorItem]];
  [appMenu addItemWithTitle:@"Settings…"
                     action:@selector(showSettings:)
              keyEquivalent:@","];
  [appMenu addItemWithTitle:@"Check for Updates…"
                     action:@selector(checkForUpdates:)
              keyEquivalent:@""];
  [appMenu addItem:[NSMenuItem separatorItem]];
  [appMenu addItemWithTitle:@"Quit BuildBrowser"
                     action:@selector(terminate:)
              keyEquivalent:@"q"];
  NSMenuItem *appItem = [NSMenuItem new];
  appItem.submenu = appMenu;
  [bar addItem:appItem];

  // ── File ──────────────────────────────────────────────────────────────────
  NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
  [fileMenu addItemWithTitle:@"New Tab"
                      action:@selector(newTab:)
               keyEquivalent:@"t"];
  [fileMenu addItemWithTitle:@"Close Tab"
                      action:@selector(closeCurrentTab:)
               keyEquivalent:@"w"];
  NSMenuItem *fileItem = [NSMenuItem new];
  fileItem.submenu = fileMenu;
  [bar addItem:fileItem];

  // ── Edit ──────────────────────────────────────────────────────────────────
  NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
  [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
  [editMenu addItemWithTitle:@"Copy"
                      action:@selector(copy:)
               keyEquivalent:@"c"];
  [editMenu addItemWithTitle:@"Paste"
                      action:@selector(paste:)
               keyEquivalent:@"v"];
  [editMenu addItemWithTitle:@"Select All"
                      action:@selector(selectAll:)
               keyEquivalent:@"a"];
  [editMenu addItem:[NSMenuItem separatorItem]];
  [editMenu addItemWithTitle:@"Find…"
                      action:@selector(openFindBar:)
               keyEquivalent:@"f"];
  [editMenu addItemWithTitle:@"Find Next"
                      action:@selector(findNext:)
               keyEquivalent:@"g"];
  NSMenuItem *editItem = [NSMenuItem new];
  editItem.submenu = editMenu;
  [bar addItem:editItem];

  // ── View ──────────────────────────────────────────────────────────────────
  NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
  [viewMenu addItemWithTitle:@"Reload"
                      action:@selector(reloadOrStop:)
               keyEquivalent:@"r"];
  [viewMenu addItemWithTitle:@"Back"
                      action:@selector(goBack:)
               keyEquivalent:@"["];
  [viewMenu addItemWithTitle:@"Forward"
                      action:@selector(goForward:)
               keyEquivalent:@"]"];
  [viewMenu addItem:[NSMenuItem separatorItem]];
  [viewMenu addItemWithTitle:@"Pin Tab"
                      action:@selector(togglePinCurrentTab:)
               keyEquivalent:@"p"];
  [viewMenu addItem:[NSMenuItem separatorItem]];
  [viewMenu addItemWithTitle:@"Bookmarks"
                      action:@selector(showBookmarks:)
               keyEquivalent:@"b"];
  [viewMenu addItemWithTitle:@"History"
                      action:@selector(showHistory:)
               keyEquivalent:@"y"];
  [viewMenu addItemWithTitle:@"Downloads"
                      action:@selector(showDownloads:)
               keyEquivalent:@"j"];
  [viewMenu addItem:[NSMenuItem separatorItem]];
  [viewMenu addItemWithTitle:@"Bookmark This Page"
                      action:@selector(toggleBookmark:)
               keyEquivalent:@"d"];
  NSMenuItem *viewItem = [NSMenuItem new];
  viewItem.submenu = viewMenu;
  [bar addItem:viewItem];

  NSApp.mainMenu = bar;
}

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

- (NSString*)sessionPath {
  NSString* support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
  NSString* base = [support stringByAppendingPathComponent:@"BuildBrowser"];
  [[NSFileManager defaultManager] createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:nil];
  return [base stringByAppendingPathComponent:@"session.plist"];
}

- (NSDictionary*)loadSession {
  NSDictionary* session = [NSDictionary dictionaryWithContentsOfFile:[self sessionPath]];
  return [session isKindOfClass:[NSDictionary class]] ? session : @{};
}

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

// Close-tab forwarded to window controller
- (void)closeCurrentTab:(id)_ {
  NSWindow* win = [NSApp keyWindow];
  if ([win.windowController isKindOfClass:[BrowserWindowController class]]) {
    BrowserWindowController* wc = (BrowserWindowController*)win.windowController;
    [wc.tabManager closeTabAtIndex:wc.tabManager.activeIndex];
  }
}

- (void)checkForUpdates:(id)_ {
  [[UpdateManager shared] checkForUpdates];
}

@end
