#pragma once
#import <Foundation/Foundation.h>

@interface DefaultBrowserManager : NSObject
+ (BOOL)isDefaultBrowser;
+ (BOOL)setAsDefaultBrowserWithError:(NSError**)error;
+ (NSString*)statusText;
@end
