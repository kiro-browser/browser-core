/**
 * @file      Profile.mm
 * @project   BuildBrowser
 * @brief     Profile data model — name, UUID, color, and avatar.
 *
 * @details   Conforms to NSSecureCoding for secure archiving.
 *            Each profile has a unique UUID used as its directory name,
 *            an accent color for chrome customization, and an optional
 *            avatar image file copied into the profile's data directory.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#import "Profile.h"
#import <AppKit/AppKit.h>

#pragma mark - Implementation

@implementation Profile

+ (BOOL)supportsSecureCoding {
    return YES;
}

/**
 * @brief   Create a new profile with the given name.
 *
 * @details Generates a UUID, sets the default accent color, and leaves
 *          the avatar path nil.
 *
 * @param   name  The human-readable profile name.
 * @return  An initialized Profile.
 */
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

/**
 * @brief   Get the path to this profile's data directory.
 *
 * @details Returns ~/Library/Application Support/BuildBrowser/Profiles/<uuid>/
 *          and creates the directory if it does not exist.
 *
 * @return  The profile data directory path.
 */
- (NSString*)dataDirectory {
    NSString* support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString* base = [support stringByAppendingPathComponent:@"BuildBrowser"];
    NSString* profiles = [base stringByAppendingPathComponent:@"Profiles"];
    NSString* path = [profiles stringByAppendingPathComponent:self.uuid];

    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return path;
}

/**
 * @brief   Load the avatar image from disk.
 *
 * @return  An NSImage if avatarPath is set and readable, nil otherwise.
 */
- (NSImage*)avatarImage {
    if (!_avatarPath.length) return nil;
    return [[NSImage alloc] initWithContentsOfFile:_avatarPath];
}

/**
 * @brief   Set the profile avatar from a source image file.
 *
 * @details Copies the source file into the profile's data directory as
 *          avatar.<ext>, replacing any existing avatar file. Updates
 *          avatarPath to the new location.
 *
 * @param   url  The file URL of the source image.
 */
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

/**
 * @brief   Remove the avatar image from disk and clear the path.
 */
- (void)clearAvatar {
    if (_avatarPath.length) {
        [[NSFileManager defaultManager] removeItemAtPath:_avatarPath error:nil];
    }
    _avatarPath = nil;
}

@end
