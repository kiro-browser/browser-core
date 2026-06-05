/**
 * @file      UpdateManager.h
 * @project   BuildBrowser
 * @brief     Auto-update engine with download, verification, and installation.
 *
 * @details   Checks a JSON manifest from the configured feed URL, compares
 *            the remote build number against the current bundle version,
 *            and if a newer build exists, downloads a .zip archive,
 *            unpacks it via ditto, and installs it via a shell script that
 *            waits for the current process to exit and then replaces the app
 *            bundle and relaunches.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#pragma once
#import <Cocoa/Cocoa.h>

/**
 * @interface UpdateManager
 * @brief     Singleton that manages software update checking and installation.
 *
 * @details   Uses NSURLSession for manifest fetching and NSURLSessionDownloadTask
 *            for downloading the update bundle. Displays a progress window
 *            during download and an installer shell script that runs after
 *            the app terminates.
 */
@interface UpdateManager : NSObject

/**
 * @brief   Returns the shared update manager singleton.
 * @return  The singleton UpdateManager instance.
 */
+ (instancetype)shared;

/**
 * @brief   Check for updates and prompt the user if a newer build is available.
 * @details Fetches the manifest from the configured feed URL, compares build
 *          numbers, and shows an alert if an update is found.
 */
- (void)checkForUpdates;

/**
 * @brief   Check for updates silently (no UI unless an update is found).
 * @details Used by the automatic check on launch. Only shows UI if a newer
 *          build is actually available.
 */
- (void)checkForUpdatesSilently;

@end
