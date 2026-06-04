#pragma once
#import <Cocoa/Cocoa.h>
#import "TabManager.h"
#import "Profile.h"

@interface BrowserWindowController : NSWindowController <NSWindowDelegate>
- (instancetype)initWithProfile:(Profile*)profile;
- (instancetype)initWithProfile:(Profile*)profile restoredURLs:(NSArray<NSString*>*)urls activeIndex:(NSInteger)activeIndex;
- (instancetype)initWithProfile:(Profile*)profile restoredURLs:(NSArray<NSString*>*)urls pinned:(NSArray<NSNumber*>*)pinned activeIndex:(NSInteger)activeIndex;
@property (readonly) TabManager* tabManager;
@property (readonly) Profile* profile;
- (NSDictionary*)sessionState;
- (void)restoreWindowState:(NSDictionary*)state;
- (void)openURLInNewTab:(NSString*)url;

// Actions reachable from menu / keyboard
- (void)newTab:(id)sender;
- (void)goBack:(id)sender;
- (void)goForward:(id)sender;
- (void)reloadOrStop:(id)sender;
- (void)toggleBookmark:(id)sender;
- (void)showBookmarks:(id)sender;
- (void)showHistory:(id)sender;
- (void)showDownloads:(id)sender;
- (void)showSettings:(id)sender;
- (void)openFindBar:(id)sender;
- (void)findNext:(id)sender;
- (void)togglePinCurrentTab:(id)sender;
@end
