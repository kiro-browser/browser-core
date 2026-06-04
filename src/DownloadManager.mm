#import "DownloadManager.h"

#import "ProfileManager.h"

@implementation DownloadItem
@end

@interface DownloadManager ()
@property (strong) NSMutableArray<DownloadItem*>* mutableItems;
@end

@implementation DownloadManager

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

- (instancetype)init {
    self = [super init];
    if (self) { _mutableItems = [NSMutableArray new]; }
    return self;
}

- (NSArray<DownloadItem*>*)items { return _mutableItems; }

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

// ── WKDownloadDelegate ────────────────────────────────────────────────────────

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

- (void)download:(WKDownload*)dl didReceiveData:(int64_t)length {
    DownloadItem* item = [self itemForDownload:dl];
    item.bytesReceived += length;
    if (self.onUpdate) self.onUpdate();
}

- (void)downloadDidFinish:(WKDownload*)dl {
    DownloadItem* item = [self itemForDownload:dl];
    item.state = DownloadStateComplete;
    if (self.onUpdate) self.onUpdate();
}

- (void)download:(WKDownload*)dl didFailWithError:(NSError*)err resumeData:(NSData*)_ {
    DownloadItem* item = [self itemForDownload:dl];
    item.state = DownloadStateFailed;
    if (self.onUpdate) self.onUpdate();
}

// ── Helpers ───────────────────────────────────────────────────────────────────

- (DownloadItem*)itemForDownload:(WKDownload*)dl {
    for (DownloadItem* i in _mutableItems)
        if (i.download == dl) return i;
    return nil;
}
@end
