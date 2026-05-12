//
//  ChannelBuffer.h
//  i3Chat
//

#import <Foundation/Foundation.h>

@interface ChannelBuffer : NSObject

@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *server;
@property (nonatomic, strong) NSMutableArray<NSString *> *messages;
@property (nonatomic, strong) NSMutableArray<NSString *> *users;
@property (nonatomic, assign) BOOL isPrivate;
@property (nonatomic, assign) NSInteger unreadCount;
@property (nonatomic, assign) BOOL allowMessageStorage; // Whether to store messages for this channel
@property (nonatomic, assign) NSInteger maxMessages; // Maximum number of messages to keep (0 = unlimited)

- (instancetype)initWithName:(NSString *)name server:(NSString *)server isPrivate:(BOOL)isPrivate;
// Returns the number of messages removed due to limit (0 if none removed)
- (NSUInteger)addMessage:(NSString *)message;
// Returns the number of messages removed (for batch deletion optimization)
- (NSUInteger)trimMessagesToLimit;

@end
