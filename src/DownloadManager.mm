/**
 * @file      DownloadManager.mm
 * @project   BuildBrowser
 * @brief     Download lifecycle management.
 *
 * @details   Tracks all downloads for the active profile. Conforms to
 *            WKDownloadDelegate to automatically handle destination
 *            decisions (with rename-on-collision logic), progress updates,
 *            completion, and failure events. Fires onUpdate on any state
 *            change for the UI to refresh.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#import "DownloadManager.h"
#import "ProfileManager.h"

#pragma mark - DownloadItem

@implementation DownloadItem
@end

#pragma mark - Private Interface

@interface DownloadManager ()
/// Mutable array backing the items property.
@property (strong) NSMutableArray<DownloadItem*>* mutableItems;
@end

#pragma mark - Implementation

@implementation DownloadManager

/**
 * @brief   Returns the per-profile shared download manager instance.
 *
 * @details Creates one instance per profile UUID. The instance is cached
 *          in a static dictionary.
 *
 * @return  The shared DownloadManager, or nil if no active profile.
 */
+ (instancetype)profileShared {
    static NSMutableDictionary* instances;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ instances = [NSMutableDictionary new]; });

    Profile* p = [ProfileManager shared].activeProfile;
    if (!p) return nil;

    if (!instances[p.uuid]) {
        instances[p.uuid] = [DownloadManager new];
    }
    return instances[p.uuid];
}

/**
 * @brief   Initialize with an empty mutable items array.
 *
 * @return  An initialized DownloadManager.
 */
- (instancetype)init {
    self = [super init];
    if (self) { _mutableItems = [NSMutableArray new]; }
    return self;
}

/// Returns the immutable items array.
- (NSArray<DownloadItem*>*)items { return _mutableItems; }

/**
 * @brief   Start tracking a new download from a WKDownload.
 *
 * @details Creates a DownloadItem, sets self as the WKDownload delegate,
 *          and inserts the item at the front of the list.
 *
 * @param   dl  The WKDownload to track.
 */
- (void)startDownload:(WKDownload*)dl {
    DownloadItem* item = [DownloadItem new];
    item.download      = dl;
    item.state         = DownloadStateInProgress;
    item.totalBytes    = -1;
    item.bytesReceived = 0;
    item.filename      = @"download";
    dl.delegate        = self;
    [_mutableItems insertObject:item atIndex:0];
    if (self.onUpdate) self.onUpdate();
}

// ───────────────────────────────────────────────────────────────────────────────
// @name WKDownloadDelegate
// ───────────────────────────────────────────────────────────────────────────────

/**
 * @brief   Decide the destination path for a download.
 *
 * @details Uses the user's Downloads directory. If a file already exists
 *          at that path, appends (1), (2), etc. to avoid overwriting.
 *
 * @param   dl          The download requiring a destination.
 * @param   response    The URL response (used for expected content length).
 * @param   filename    The suggested filename from the server.
 * @param   handler     Callback with the destination NSURL.
 */
- (void)download:(WKDownload*)dl decideDestinationUsingResponse:(NSURLResponse*)response
    suggestedFilename:(NSString*)filename completionHandler:(void(^)(NSURL*))handler {

    DownloadItem* item = [self itemForDownload:dl];
    item.filename = filename;
    item.totalBytes = response.expectedContentLength;

    NSString* downloads = [NSSearchPathForDirectoriesInDomains(
        NSDownloadsDirectory, NSUserDomainMask, YES) firstObject];
    NSURL* dest = [NSURL fileURLWithPath:
                   [downloads stringByAppendingPathComponent:filename]];

    // Avoid overwriting — append (1), (2) etc.
    NSFileManager* fm = [NSFileManager defaultManager];
    NSInteger n = 1;
    while ([fm fileExistsAtPath:dest.path]) {
        NSString* base = filename.stringByDeletingPathExtension;
        NSString* ext  = filename.pathExtension;
        NSString* name = ext.length
            ? [NSString stringWithFormat:@"%@ (%ld).%@", base, (long)n, ext]
            : [NSString stringWithFormat:@"%@ (%ld)", base, (long)n];
        dest = [NSURL fileURLWithPath:[downloads stringByAppendingPathComponent:name]];
        n++;
    }

    item.destinationPath = dest.path;
    if (self.onUpdate) self.onUpdate();
    handler(dest);
}

/**
 * @brief   Called when data is received during download.
 *
 * @param   dl      The download receiving data.
 * @param   length  Number of bytes just received.
 */
- (void)download:(WKDownload*)dl didReceiveData:(int64_t)length {
    DownloadItem* item = [self itemForDownload:dl];
    item.bytesReceived += length;
    if (self.onUpdate) self.onUpdate();
}

/**
 * @brief   Called when the download finishes successfully.
 *
 * @param   dl  The completed download.
 */
- (void)downloadDidFinish:(WKDownload*)dl {
    DownloadItem* item = [self itemForDownload:dl];
    item.state = DownloadStateComplete;
    if (self.onUpdate) self.onUpdate();
}

/**
 * @brief   Called when the download fails.
 *
 * @param   dl      The failed download.
 * @param   err     The error describing the failure.
 * @param   _       Resume data (unused).
 */
- (void)download:(WKDownload*)dl didFailWithError:(NSError*)err resumeData:(NSData*)_ {
    DownloadItem* item = [self itemForDownload:dl];
    item.state = DownloadStateFailed;
    if (self.onUpdate) self.onUpdate();
}

// ───────────────────────────────────────────────────────────────────────────────
// @name Helpers
// ───────────────────────────────────────────────────────────────────────────────

/**
 * @brief   Find the DownloadItem associated with a specific WKDownload.
 *
 * @param   dl  The WKDownload to look up.
 * @return  The matching DownloadItem, or nil.
 */
- (DownloadItem*)itemForDownload:(WKDownload*)dl {
    for (DownloadItem* i in _mutableItems)
        if (i.download == dl) return i;
    return nil;
}

@end
