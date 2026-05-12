//
//  HistoryWindowController.h
//  i3Chat
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface HistoryWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate>

- (void)showHistoryForWindowKey:(NSString *)windowKey displayName:(NSString *)displayName;
- (void)applyLocalization;

@end

NS_ASSUME_NONNULL_END
