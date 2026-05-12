//
//  SettingsWindowController.h
//  i3Chat
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class SettingsWindowController;

@protocol SettingsWindowControllerDelegate <NSObject>

- (void)settingsWindowController:(SettingsWindowController *)controller didChangeShowLogWindowOnStartup:(BOOL)showLogWindow;
- (void)settingsWindowController:(SettingsWindowController *)controller didChangeShowChannelColors:(BOOL)showColors;
- (void)settingsWindowController:(SettingsWindowController *)controller didChangeMaxMessagesPerChannel:(NSInteger)maxMessages;
- (void)settingsWindowController:(SettingsWindowController *)controller didChangeMessageLineSpacing:(NSInteger)spacing;

@end

@interface SettingsWindowController : NSWindowController <NSWindowDelegate>

@property (nonatomic, weak, nullable) id<SettingsWindowControllerDelegate> delegate;

- (void)showWindow:(nullable id)sender;
- (void)applyLocalization;
- (void)loadSettings;
- (void)saveSettings;

@end

NS_ASSUME_NONNULL_END
