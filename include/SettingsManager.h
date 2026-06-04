#pragma once
#import <Foundation/Foundation.h>

// All settings stored in NSUserDefaults under "KBrowser.*"
@interface SettingsManager : NSObject
+ (instancetype)profileShared;
- (instancetype)initWithRootPath:(NSString*)path;

// General
@property (copy) NSString* homepage;        // default: https://start.duckduckgo.com
@property (copy) NSString* searchEngineURL; // default: https://duckduckgo.com/?q=%@
@property (copy) NSDictionary* domainLaunchers; // alias -> { url, search }
@property (copy) NSString* updateFeedURL;   // default: http://127.0.0.1:8787/manifest.json

// Privacy
@property (assign) BOOL javascriptEnabled;
@property (assign) BOOL blockPopups;
@property (assign) BOOL privateBrowsing;
@property (assign) BOOL adBlockEnabled;
@property (assign) BOOL autoCheckUpdates;

// Appearance
@property (assign) BOOL showBookmarksBar;

- (void)resetToDefaults;
@end
