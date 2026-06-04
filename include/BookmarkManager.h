#pragma once
#import <Foundation/Foundation.h>

@interface Bookmark : NSObject <NSSecureCoding>
@property (copy) NSString* title;
@property (copy) NSString* url;
@property (copy) NSString* folder;
@property (strong) NSDate* dateAdded;
- (instancetype)initWithTitle:(NSString*)title url:(NSString*)url;
- (instancetype)initWithTitle:(NSString*)title url:(NSString*)url folder:(NSString*)folder;
@end

// Persists bookmarks to ~/Library/Application Support/KBrowser/bookmarks.plist
@interface BookmarkManager : NSObject
+ (instancetype)profileShared;
@property (readonly) NSArray<Bookmark*>* bookmarks;
- (instancetype)initWithRootPath:(NSString*)path;
- (void)addBookmarkWithTitle:(NSString*)title url:(NSString*)url;
- (void)addBookmarkWithTitle:(NSString*)title url:(NSString*)url folder:(NSString*)folder;
- (void)updateBookmarkAtIndex:(NSInteger)index title:(NSString*)title url:(NSString*)url;
- (void)updateBookmarkAtIndex:(NSInteger)index title:(NSString*)title url:(NSString*)url folder:(NSString*)folder;
- (void)removeBookmarkAtIndex:(NSInteger)index;
- (BOOL)isBookmarked:(NSString*)url;
- (NSArray<NSString*>*)folders;
- (void)save;
@end
