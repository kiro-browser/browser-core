/**
 * @file      ProfileManager.mm
 * @project   BuildBrowser
 * @brief     Multi-profile lifecycle management.
 *
 * @details   Singleton that owns the list of profiles. Persists to
 *            profiles.plist via NSKeyedArchiver. On first launch, creates
 *            a "Default" profile and migrates any pre-existing non-profile
 *            data files (bookmarks.plist, history.plist) into it.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#import "ProfileManager.h"

#pragma mark - Private Interface

@interface ProfileManager ()
@property (strong) NSMutableArray<Profile*>* mutableProfiles;
@end

#pragma mark - Implementation

@implementation ProfileManager

/**
 * @brief   Returns the shared profile manager singleton.
 *
 * @return  The singleton instance.
 */
+ (instancetype)shared {
    static ProfileManager* inst;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ inst = [ProfileManager new]; });
    return inst;
}

/**
 * @brief   Initialize — load profiles from disk, create default if needed.
 *
 * @details If no profiles exist, creates a "Default" profile. The active
 *          profile is set to the first profile if none was previously saved.
 *
 * @return  An initialized ProfileManager.
 */
- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableProfiles = [NSMutableArray new];
        [self loadProfiles];

        if (_mutableProfiles.count == 0) {
            [self createDefaultProfile];
        }

        if (!_activeProfile && _mutableProfiles.count > 0) {
            _activeProfile = _mutableProfiles[0];
        }
    }
    return self;
}

/// Returns the immutable profiles array.
- (NSArray<Profile*>*)profiles {
    return _mutableProfiles;
}

/**
 * @brief   Create a new profile with the given name.
 *
 * @param   name  The display name for the new profile.
 * @return  The newly created Profile.
 */
- (Profile*)createProfileWithName:(NSString*)name {
    Profile* p = [[Profile alloc] initWithName:name];
    [_mutableProfiles addObject:p];
    [self saveProfiles];
    return p;
}

/**
 * @brief   Create the initial "Default" profile and migrate legacy data.
 */
- (void)createDefaultProfile {
    Profile* p = [[Profile alloc] initWithName:@"Default"];
    [_mutableProfiles addObject:p];
    [self saveProfiles];
    [self migrateLegacyDataToProfile:p];
}

/**
 * @brief   Delete a profile and its data directory.
 *
 * @param   profile  The profile to delete. Cannot delete the active profile.
 */
- (void)deleteProfile:(Profile*)profile {
    if (profile == _activeProfile) return; // Cannot delete active profile
    [_mutableProfiles removeObject:profile];
    [[NSFileManager defaultManager] removeItemAtPath:[profile dataDirectory] error:nil];
    [self saveProfiles];
}

/**
 * @brief   Save profiles to disk and persist active profile UUID.
 */
- (void)saveProfiles {
    NSError* err;
    NSData* data = [NSKeyedArchiver archivedDataWithRootObject:_mutableProfiles requiringSecureCoding:YES error:&err];
    if (data) {
        NSString* path = [self profileListPath];
        [data writeToFile:path atomically:YES];
    }
    if (_activeProfile) {
        [[NSUserDefaults standardUserDefaults] setObject:_activeProfile.uuid forKey:@"LastActiveProfile"];
    }
}

/**
 * @brief   Load profiles from disk and restore active profile.
 */
- (void)loadProfiles {
    NSString* path = [self profileListPath];
    NSData* data = [NSData dataWithContentsOfFile:path];
    if (data) {
        NSError* err;
        NSArray* arr = [NSKeyedUnarchiver unarchivedArrayOfObjectsOfClass:[Profile class] fromData:data error:&err];
        if (arr) {
            [_mutableProfiles addObjectsFromArray:arr];
        }
    }

    NSString* lastUUID = [[NSUserDefaults standardUserDefaults] stringForKey:@"LastActiveProfile"];
    if (lastUUID) {
        for (Profile* p in _mutableProfiles) {
            if ([p.uuid isEqualToString:lastUUID]) {
                _activeProfile = p;
                break;
            }
        }
    }
}

/// Path to the profiles list file.
- (NSString*)profileListPath {
    NSString* support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString* base = [support stringByAppendingPathComponent:@"BuildBrowser"];
    [[NSFileManager defaultManager] createDirectoryAtPath:base withIntermediateDirectories:YES attributes:nil error:nil];
    return [base stringByAppendingPathComponent:@"profiles.plist"];
}

/**
 * @brief   Migrate legacy flat data files into a profile's directory.
 *
 * @details Used on first launch after introducing profiles. Moves existing
 *          bookmarks.plist and history.plist from the flat directory into
 *          the new Default profile directory.
 *
 * @param   profile  The profile to receive the legacy files.
 */
- (void)migrateLegacyDataToProfile:(Profile*)profile {
    NSString* support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    NSString* base = [support stringByAppendingPathComponent:@"BuildBrowser"];
    NSString* target = [profile dataDirectory];

    NSArray* files = @[@"bookmarks.plist", @"history.plist"];
    NSFileManager* fm = [NSFileManager defaultManager];

    for (NSString* file in files) {
        NSString* oldPath = [base stringByAppendingPathComponent:file];
        NSString* newPath = [target stringByAppendingPathComponent:file];
        if ([fm fileExistsAtPath:oldPath] && ![fm fileExistsAtPath:newPath]) {
            [fm moveItemAtPath:oldPath toPath:newPath error:nil];
        }
    }
}

@end
