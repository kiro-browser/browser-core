#pragma once
#import <AppKit/AppKit.h>

@interface Profile : NSObject <NSSecureCoding>

@property (copy) NSString* name;
@property (copy) NSString* uuid;
@property (strong) NSColor* color;
@property (copy) NSString* avatarPath;

- (instancetype)initWithName:(NSString*)name;
- (NSString*)dataDirectory;
- (NSImage*)avatarImage;
- (void)setAvatarFromImageURL:(NSURL*)url;
- (void)clearAvatar;

@end
