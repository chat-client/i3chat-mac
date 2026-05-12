#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class WhoisWindowController;

@protocol WhoisWindowControllerDelegate <NSObject>
@optional
- (void)whoisWindowController:(WhoisWindowController *)controller didRequestJoinChannel:(NSString *)channel;
@end

@interface WhoisWindowController : NSWindowController <NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate>

@property (nonatomic, strong, readonly) NSString *nickname;
@property (nonatomic, strong, readonly, nullable) NSString *server;
@property (nonatomic, weak, nullable) id<WhoisWindowControllerDelegate> delegate;

- (instancetype)initWithNickname:(NSString *)nickname server:(nullable NSString *)server;
- (void)setWhoisInfo:(NSDictionary<NSString *, id> *)info;
- (void)applyLocalization;

@end

NS_ASSUME_NONNULL_END
