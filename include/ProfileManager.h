/**
 * @file      ProfileManager.h
 * @project   BuildBrowser
 * @brief     Multi-profile management and persistence.
 *
 * @details   Manages creation, deletion, and persistence of browser profiles.
 *            Stores the full profile list in profiles.plist and tracks the
 *            last active profile UUID via NSUserDefaults. On first launch,
 *            creates a "Default" profile and migrates any legacy non-profile
 *            data files into it.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#pragma once
#import <Foundation/Foundation.h>
#import "Profile.h"

/**
 * @interface ProfileManager
 * @brief     Singleton that owns the profile list and active profile.
 *
 * @details   Loads profiles from disk on initialization. If no profiles
 *            exist, creates a "Default" profile and migrates legacy data.
 *            The active profile is persisted across app launches via
 *            NSUserDefaults under the key @"LastActiveProfile".
 */
@interface ProfileManager : NSObject

/**
 * @brief   Returns the shared profile manager singleton.
 * @return  The singleton ProfileManager instance.
 */
+ (instancetype)shared;

/// All existing profiles (read-only; use createProfileWithName: to add).
@property (readonly) NSArray<Profile*>* profiles;

/// The currently active profile (used by all per-profile managers).
@property (strong) Profile* activeProfile;

/**
 * @brief   Create and persist a new profile with the given name.
 * @param   name  The display name for the new profile.
 * @return  The newly created Profile instance.
 */
- (Profile*)createProfileWithName:(NSString*)name;

/**
 * @brief   Delete a profile and its data directory.
 * @details The active profile cannot be deleted. This operation is permanent.
 * @param   profile  The profile to delete.
 */
- (void)deleteProfile:(Profile*)profile;

/**
 * @brief   Load profiles from disk (called automatically on init).
 * @details Reads profiles.plist and sets activeProfile from NSUserDefaults.
 */
- (void)loadProfiles;

/**
 * @brief   Save all profiles to disk immediately.
 * @details Also persists the active profile UUID to NSUserDefaults.
 */
- (void)saveProfiles;

@end
