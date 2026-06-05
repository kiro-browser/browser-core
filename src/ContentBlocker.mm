/**
 * @file      ContentBlocker.mm
 * @project   BuildBrowser
 * @brief     Ad/tracker blocking via WKContentRuleList.
 *
 * @details   Compiles a built-in set of WKContentRuleList JSON rules
 *            targeting common advertising and tracking domains
 *            (google-analytics.com, doubleclick.net, etc.). Respects the
 *            adBlockEnabled setting from SettingsManager. Results are
 *            cached in _ruleList for reuse across all tabs.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#import "ContentBlocker.h"
#import "SettingsManager.h"
#import "ProfileManager.h"

#pragma mark - Private Properties

@interface ContentBlocker () {
    /// The compiled content rule list, cached after first compilation.
    WKContentRuleList* _ruleList;
}
@end

#pragma mark - Implementation

@implementation ContentBlocker

/**
 * @brief   Returns the shared singleton instance.
 *
 * @return  The global ContentBlocker instance.
 */
+ (instancetype)shared {
    static ContentBlocker* inst;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ inst = [ContentBlocker new]; });
    return inst;
}

/**
 * @brief   Compile and apply ad-blocking rules to a web view configuration.
 *
 * @details   Checks the user's adBlockEnabled setting first. If disabled,
 *            the completion handler fires immediately. If the rules are
 *            already compiled and cached, they are applied synchronously.
 *            Otherwise, the JSON rule list is compiled asynchronously and
 *            applied to the configuration on completion.
 *
 * @param   config      The WKWebViewConfiguration to modify.
 * @param   completion  Block called after rules are applied (may be nil).
 */
- (void)applyToConfiguration:(WKWebViewConfiguration*)config completion:(void(^)(void))completion {
    if (![SettingsManager profileShared].adBlockEnabled) {
        if (completion) completion();
        return;
    }

    if (_ruleList) {
        [config.userContentController addContentRuleList:_ruleList];
        if (completion) completion();
        return;
    }

    /// WKContentRuleList JSON — blocks common ad/tracker domains.
    NSString* json = @"["
    "  { \"trigger\": { \"url-filter\": \".*google-analytics\\\\.com.*\" }, \"action\": { \"type\": \"block\" } },"
    "  { \"trigger\": { \"url-filter\": \".*doubleclick\\\\.net.*\" }, \"action\": { \"type\": \"block\" } },"
    "  { \"trigger\": { \"url-filter\": \".*scorecardresearch\\\\.com.*\" }, \"action\": { \"type\": \"block\" } },"
    "  { \"trigger\": { \"url-filter\": \".*ads\\\\..*\" }, \"action\": { \"type\": \"block\" } },"
    "  { \"trigger\": { \"url-filter\": \".*tracker.*\" }, \"action\": { \"type\": \"block\" } }"
    "]";

    [[WKContentRuleListStore defaultStore] compileContentRuleListForIdentifier:@"KBrowserBlocker"
                                                       encodedContentRuleList:json
                                                            completionHandler:^(WKContentRuleList* list, NSError* error) {
        if (list) {
            self->_ruleList = list;
            [config.userContentController addContentRuleList:list];
        } else {
            NSLog(@"ContentBlocker: Compilation failed: %@", error);
        }
        if (completion) completion();
    }];
}

@end
