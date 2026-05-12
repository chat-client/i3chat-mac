//
//  ChannelBuffer.m
//  i3Chat
//

#import "ChannelBuffer.h"
#import "StorageConstants.h"
#import "MessageStorage.h"

@implementation ChannelBuffer

- (instancetype)initWithName:(NSString *)name server:(NSString *)server isPrivate:(BOOL)isPrivate {
    self = [super init];
    if (self) {
        _name = name;
        _server = server;
        _isPrivate = isPrivate;
        _messages = [[NSMutableArray alloc] init];
        _users = [[NSMutableArray alloc] init];
        _unreadCount = 0;
        _allowMessageStorage = YES; // Default to allow message storage
        
        // Load max messages setting from database
        NSString *maxMessagesValue = [[MessageStorage sharedStorage] getSettingForKey:kSettingMaxMessagesPerChannel];
        _maxMessages = (maxMessagesValue == nil) ? kDefaultMaxMessagesPerChannel : [maxMessagesValue integerValue];
    }
    return self;
}

- (NSUInteger)addMessage:(NSString *)message {
    if (!message) {
        return 0;
    }
    [self.messages addObject:message];
    // Return the number of messages removed due to limit
    return [self trimMessagesToLimit];
}

- (NSUInteger)trimMessagesToLimit {
    if (self.maxMessages <= 0) {
        return 0; // No limit
    }
    
    NSUInteger countBefore = self.messages.count;
    
    // PERFORMANCE OPTIMIZATION: Batch deletion
    // When messages exceed maxMessages + 100, delete 100 messages at once
    // This reduces the number of deletion operations and layout calculations
    // After deletion, count resets and we wait until it reaches maxMessages + 100 again
    static const NSUInteger kBatchDeleteCount = 100;
    NSUInteger threshold = (NSUInteger)self.maxMessages + kBatchDeleteCount;
    
    if (self.messages.count > threshold) {
        // Delete 100 messages at once for better performance
        NSRange deleteRange = NSMakeRange(0, kBatchDeleteCount);
        [self.messages removeObjectsInRange:deleteRange];
    }
    // Note: We don't delete one by one anymore - we wait until threshold is reached again
    
    NSUInteger countAfter = self.messages.count;
    return countBefore - countAfter; // Return number of messages removed
}

@end
