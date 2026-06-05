/**
 * @file      DownloadManager.h
 * @project   BuildBrowser
 * @brief     Download tracking and file management.
 *
 * @details   Manages all in-progress and completed downloads for the session.
 *            Provides a per-profile singleton, a mutable array of DownloadItem
 *            objects, and conforms to WKDownloadDelegate for automatic
 *            download lifecycle handling.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#pragma once
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

/// Possible states for a download item.
typedef NS_ENUM(NSInteger, DownloadState) {
    /// Download is actively transferring data.
    DownloadStateInProgress,
    /// Download finished successfully.
    DownloadStateComplete,
    /// Download failed with an error.
    DownloadStateFailed,
};

#pragma mark - DownloadItem Model

/**
 * @interface DownloadItem
 * @brief     Represents a single download (in-progress, complete, or failed).
 */
@interface DownloadItem : NSObject

/// The suggested filename from the server response.
@property (copy)   NSString*       filename;
/// The full destination path on disk where the file was saved.
@property (copy)   NSString*       destinationPath;
/// Number of bytes received so far.
@property (assign) int64_t         bytesReceived;
/// Total expected bytes (-1 if unknown / chunked encoding).
@property (assign) int64_t         totalBytes;
/// Current state of the download (in-progress / complete / failed).
@property (assign) DownloadState   state;
/// The WKDownload instance backing this item (used for delegate callbacks).
@property (strong) WKDownload*     download;

@end

#pragma mark - DownloadManager

/**
 * @interface DownloadManager
 * @brief     Manages all downloads for the current profile.
 *
 * @details   Conforms to WKDownloadDelegate to automatically handle
 *            destination decisions, progress tracking, completion, and
 *            failure. Provides an onUpdate block for UI refresh.
 */
@interface DownloadManager : NSObject <WKDownloadDelegate>

/**
 * @brief   Returns the per-profile shared download manager instance.
 * @details The instance is keyed by the active Profile's UUID.
 * @return  The shared DownloadManager, or nil if no active profile exists.
 */
+ (instancetype)profileShared;

/// Array of all DownloadItem objects (newest first).
@property (readonly) NSArray<DownloadItem*>* items;

/**
 * @brief   Block invoked on every state change (new download, progress,
 *          completion, failure). Used by UI panels to refresh.
 */
@property (copy) void (^onUpdate)(void);

/**
 * @brief   Begin tracking a new download.
 * @details Sets self as the download's delegate and inserts a new
 *          DownloadItem at index 0.
 * @param   dl   The WKDownload to start tracking.
 */
- (void)startDownload:(WKDownload*)dl;

@end
