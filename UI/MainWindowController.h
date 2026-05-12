//
//  MainWindowController.h
//  i3Chat
//

#import <Cocoa/Cocoa.h>

@class IRCClient;

@interface MainWindowController : NSWindowController

- (void)updateTitleBarButtonsForFavoritesMode:(BOOL)isFavoritesMode;

@end
