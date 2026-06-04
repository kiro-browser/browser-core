#pragma once
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import "Profile.h"

// One tab = one WKWebView + its button in the tab strip
@interface BrowserTab : NSObject
@property (strong) WKWebView*   webView;
@property (strong) NSButton*    tabButton;   // shown in tab strip
@property (copy)   NSString*    title;
@property (copy)   NSString*    url;
@property (strong) NSImage*     favicon;     // New property
@property (strong) NSDictionary* certificateInfo;
@property (assign) BOOL         pinned;
@end

// Owns all tabs, drives switching / creation / closing
@interface TabManager : NSObject

- (instancetype)initWithProfile:(Profile*)profile;
@property (readonly) Profile* profile;

@property (readonly) NSArray<BrowserTab*>* tabs;
@property (readonly) BrowserTab*           activeTab;
@property (readonly) NSInteger             activeIndex;

// Callbacks fired when state changes — set by BrowserWindowController
@property (copy) void (^onTabAdded)(BrowserTab* tab, NSInteger index);
@property (copy) void (^onTabClosed)(NSInteger index);
@property (copy) void (^onTabSwitched)(BrowserTab* tab, NSInteger index);
@property (copy) void (^onTitleChanged)(BrowserTab* tab, NSString* title);
@property (copy) void (^onURLChanged)(BrowserTab* tab, NSString* url);
@property (copy) void (^onLoadProgress)(BrowserTab* tab, double progress);
@property (copy) void (^onLoadStateChanged)(BrowserTab* tab, BOOL loading);
@property (copy) void (^onFaviconChanged)(BrowserTab* tab, NSImage* icon); // New callback
@property (copy) void (^onInternalCommand)(NSString* command);

- (BrowserTab*)newTabWithURL:(NSString*)url;
- (void)loadURL:(NSString*)raw inTab:(BrowserTab*)tab;
- (void)closeTabAtIndex:(NSInteger)index;
- (void)switchToIndex:(NSInteger)index;
- (void)setPinned:(BOOL)pinned forTabAtIndex:(NSInteger)index;

+ (NSString*)sanitizeURL:(NSString*)input;

@end
