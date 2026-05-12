//
//  ChannelListWindowController.h
//  i3Chat
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class ChannelListWindowController;

@protocol ChannelListWindowControllerDelegate <NSObject>

- (void)channelListWindowController:(ChannelListWindowController *)controller didSelectChannel:(NSString *)channel;

@optional
- (void)channelListWindowControllerDidRequestRefresh:(ChannelListWindowController *)controller;

@end

@interface ChannelListWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>

@property (nonatomic, weak, nullable) id<ChannelListWindowControllerDelegate> delegate;
@property (nonatomic, strong) NSMutableArray<NSDictionary<NSString *, id> *> *channels;
@property (nonatomic, copy, nullable) NSString *serverAddress; // Server this window belongs to

- (instancetype)initWithServerAddress:(nullable NSString *)serverAddress;
- (void)addChannel:(NSString *)channel userCount:(NSInteger)userCount topic:(NSString *)topic;
- (void)setChannelList:(NSArray<NSDictionary<NSString *, id> *> *)channels; // Set all channels at once (like Go code)
- (void)clearChannels;
- (void)finalizeChannels; // Sort and refresh after all channels are added
- (void)showWindow;
- (void)applyLocalization;

@end

NS_ASSUME_NONNULL_END
