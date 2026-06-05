/**
 * @file      ContentBlocker.h
 * @project   BuildBrowser
 * @brief     Ad and tracker content blocking via WKContentRuleList.
 *
 * @details   Compiles built-in WKContentRuleList JSON rules (covering common
 *            trackers like Google Analytics, DoubleClick, etc.) and applies
 *            them to WKWebView configurations. Only activates when the
 *            user's adBlockEnabled setting is ON.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#pragma once
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

/**
 * @interface ContentBlocker
 * @brief     Singleton that manages WKContentRuleList-based content blocking.
 *
 * @details   Compiles rules once and caches the WKContentRuleList for reuse
 *            across all tabs. Checks `SettingsManager.profileShared.adBlockEnabled`
 *            before applying. Rules target common advertising and tracking domains.
 */
@interface ContentBlocker : NSObject

/**
 * @brief   Returns the shared content blocker singleton.
 * @return  The singleton ContentBlocker instance.
 */
+ (instancetype)shared;

/**
 * @brief   Compile and apply blocking rules to the given web view configuration.
 * @details If adBlockEnabled is OFF, the completion handler fires immediately
 *          without modifying the config. If rules are already compiled, the
 *          cached WKContentRuleList is applied synchronously.
 *
 * @param   config      The WKWebViewConfiguration to attach rules to.
 * @param   completion  Block called after rules are applied (may be on any queue).
 */
- (void)applyToConfiguration:(WKWebViewConfiguration*)config completion:(void(^)(void))completion;

@end
