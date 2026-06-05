/**
 * @file      ProfilePanel.h
 * @project   BuildBrowser
 * @brief     Profile selector and management sheet UI.
 *
 * @details   A lightweight NSWindowController subclass presented as a
 *            sheet on the parent window. Provides a table of profiles
 *            with add, delete, and picture-change actions.
 *
 * @author    BuildBrowser Team
 * @date      2024-2026
 */

#pragma once
#import <Cocoa/Cocoa.h>

/**
 * @interface ProfilePanel
 * @brief     Sheet-based profile management window controller.
 *
 * @details   Displays all profiles in a table, allowing creation, deletion,
 *            and avatar management. Presented modally as a sheet via
 *            showAsSheetOnWindow:.
 */
@interface ProfilePanel : NSWindowController

/**
 * @brief   Show the profile management panel as a sheet on the given window.
 * @param   parent  The parent window to attach the sheet to.
 */
+ (void)showAsSheetOnWindow:(NSWindow*)parent;

@end
