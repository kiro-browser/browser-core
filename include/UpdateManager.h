#pragma once
#import <Cocoa/Cocoa.h>

@interface UpdateManager : NSObject
+ (instancetype)shared;
- (void)checkForUpdates;
- (void)checkForUpdatesSilently;
@end
