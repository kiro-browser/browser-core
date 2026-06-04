#import "Profile.h"
#import <AppKit/AppKit.h>

@implementation Profile

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (instancetype)initWithName:(NSString*)name {
    self = [super init];
    if (self) {
        _name = name;
        _uuid = [[NSUUID UUID] UUIDString];
        _color = [NSColor controlAccentColor];
        _avatarPath = nil;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder*)c {
    self = [super init];
    if (self) {
        _name = [c decodeObjectOfClass:[NSString class] forKey:@"name"];
        _uuid = [c decodeObjectOfClass:[NSString class] forKey:@"uuid"];
        _color = [c decodeObjectOfClass:[NSColor class] forKey:@"color"];
        _avatarPath = [c decodeObjectOfClass:[NSString class] forKey:@"avatarPath"];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder*)c {
    [c encodeObject:_name forKey:@"name"];
    [c encodeObject:_uuid forKey:@"uuid"];
    [c encodeObject:_color forKey:@"color"];
    [c encodeObject:_avatarPath forKey:@"avatarPath"];
}

- (NSString*)dataDirectory {
    NSString* support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString* base = [support stringByAppendingPathComponent:@"BuildBrowser"];
    NSString* profiles = [base stringByAppendingPathComponent:@"Profiles"];
    NSString* path = [profiles stringByAppendingPathComponent:self.uuid];
    
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}

- (NSImage*)avatarImage {
    if (!_avatarPath.length) return nil;
    return [[NSImage alloc] initWithContentsOfFile:_avatarPath];
}

- (void)setAvatarFromImageURL:(NSURL*)url {
    if (!url.path.length) return;
    NSString* ext = url.pathExtension.length ? url.pathExtension : @"png";
    NSString* dest = [[self dataDirectory] stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"avatar.%@", ext]];
    NSFileManager* fm = [NSFileManager defaultManager];
    if ([_avatarPath length]) [fm removeItemAtPath:_avatarPath error:nil];
    [fm removeItemAtPath:dest error:nil];
    if ([fm copyItemAtPath:url.path toPath:dest error:nil]) {
        _avatarPath = dest;
    }
}

- (void)clearAvatar {
    if (_avatarPath.length) {
        [[NSFileManager defaultManager] removeItemAtPath:_avatarPath error:nil];
    }
    _avatarPath = nil;
}

@end
