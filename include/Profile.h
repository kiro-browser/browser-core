/**
 * @file      Profile.h
 * @project   BuildBrowser
 * @brief     User profile data model.
 *
 * @details   Represents a browser profile with a unique name, UUID, accent
 *            color, and optional avatar image. Conforms to NSSecureCoding
 *            for persistence via ProfileManager. Each profile has its own
 *            data directory containing bookmarks, history, and settings.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#pragma once
#import <AppKit/AppKit.h>

/**
 * @interface Profile
 * @brief     A user profile with isolated browsing data.
 *
 * @details   Profiles enable multiple users (or contexts like Work/School)
 *            to keep separate bookmarks, history, settings, and website data.
 *            Each profile is identified by a UUID and stored in its own
 *            subdirectory under ~/Library/Application Support/BuildBrowser/Profiles/.
 */
@interface Profile : NSObject <NSSecureCoding>

/// The human-readable profile name (e.g. "Default", "Work").
@property (copy) NSString* name;
/// The unique identifier for this profile (UUID string).
@property (copy) NSString* uuid;
/// The accent color associated with this profile (used for UI chrome).
@property (strong) NSColor* color;
/// Path to an optional avatar image file on disk.
@property (copy) NSString* avatarPath;

/**
 * @brief   Create a new profile with the given name.
 * @details Automatically generates a UUID and sets the default color.
 * @param   name  The display name for the profile.
 * @return  A fully initialized Profile.
 */
- (instancetype)initWithName:(NSString*)name;

/**
 * @brief   Get the profile's data directory on disk.
 * @details Returns ~/Library/Application Support/BuildBrowser/Profiles/<uuid>/
 *          and creates the directory if it does not exist.
 * @return  The path to the profile's data directory.
 */
- (NSString*)dataDirectory;

/**
 * @brief   Load and return the avatar image from disk.
 * @return  An NSImage if avatarPath is set and the file exists, nil otherwise.
 */
- (NSImage*)avatarImage;

/**
 * @brief   Set the profile avatar by copying an image file into the data directory.
 * @details Copies the source file to the profile directory as avatar.<ext>,
 *          replacing any existing avatar.
 * @param   url  The file URL of the source image.
 */
- (void)setAvatarFromImageURL:(NSURL*)url;

/**
 * @brief   Remove the avatar image and clear the avatarPath.
 */
- (void)clearAvatar;

@end
