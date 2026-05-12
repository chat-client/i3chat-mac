//
//  ChatViewController.h
//  i3Chat
//

#import <Cocoa/Cocoa.h>

@class IRCConfig;

@interface ChatViewController : NSViewController

- (instancetype)initWithConfig:(IRCConfig *)config;
- (instancetype)initWithConfigs:(NSArray<IRCConfig *> *)configs;
- (void)toggleLogWindow;
- (void)toggleChannelListPanel;
- (void)toggleUserListPanel;
- (void)applyLocalization;

@end
