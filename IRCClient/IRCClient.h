//
//  IRCClient.h
//  i3Chat
//

#import <Foundation/Foundation.h>
#import "IRCConfig.h"

NS_ASSUME_NONNULL_BEGIN

@class IRCClient;

@protocol IRCClientDelegate <NSObject>

@optional
- (void)ircClient:(IRCClient *)client didConnectToServer:(NSString *)server;
- (void)ircClient:(IRCClient *)client didDisconnectWithError:(nullable NSError *)error;
- (void)ircClient:(IRCClient *)client didReceiveMessage:(NSString *)message fromNick:(NSString *)nick inChannel:(NSString *)channel isPrivate:(BOOL)isPrivate;
- (void)ircClient:(IRCClient *)client didReceiveNotice:(NSString *)notice fromNick:(NSString *)nick;
- (void)ircClient:(IRCClient *)client didJoinChannel:(NSString *)channel;
- (void)ircClient:(IRCClient *)client didPartChannel:(NSString *)channel;
- (void)ircClient:(IRCClient *)client didReceiveSystemMessage:(NSString *)message;
- (void)ircClient:(IRCClient *)client didReceiveLogMessage:(NSString *)message;
- (void)ircClient:(IRCClient *)client didReceiveRawMessage:(NSString *)rawMessage;
- (void)ircClient:(IRCClient *)client didUpdateUserList:(NSArray<NSString *> *)users forChannel:(NSString *)channel;
- (void)ircClient:(IRCClient *)client didAddUser:(NSString *)user toChannel:(NSString *)channel;
- (void)ircClient:(IRCClient *)client didRemoveUser:(NSString *)user fromChannel:(NSString *)channel;
- (void)ircClient:(IRCClient *)client didRemoveUserFromAllChannels:(NSString *)user reason:(NSString *)reason;
- (void)ircClient:(IRCClient *)client didChangeNick:(NSString *)oldNick toNick:(NSString *)newNick inChannels:(NSArray<NSString *> *)channels;
- (void)ircClient:(IRCClient *)client nicknameInUse:(NSString *)nick;
- (void)ircClientDidRegister:(IRCClient *)client;
- (void)ircClientDidReceiveChannelListStart:(IRCClient *)client;
- (void)ircClient:(IRCClient *)client didReceiveChannelListItem:(NSString *)channel userCount:(NSInteger)userCount topic:(NSString *)topic; // Deprecated: use didReceiveChannelList: instead
- (void)ircClient:(IRCClient *)client didReceiveChannelList:(NSArray<NSDictionary<NSString *, id> *> *)channels; // New method: receives complete channel list at once
- (void)ircClientDidReceiveChannelListEnd:(IRCClient *)client;
- (void)ircClient:(IRCClient *)client didReceiveLinksItemWithServer:(NSString *)server mask:(NSString *)mask hopCount:(NSInteger)hopCount info:(NSString *)info;
- (void)ircClientDidReceiveLinksEnd:(IRCClient *)client;
- (void)ircClient:(IRCClient *)client didReceiveWhoisInfo:(NSDictionary<NSString *, id> *)info forNick:(NSString *)nick;

@end

@interface IRCClient : NSObject

@property (nonatomic, strong, readonly) IRCConfig *config;
@property (nonatomic, weak, nullable) id<IRCClientDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL isConnected;
@property (nonatomic, assign, readonly) BOOL isRegistered;  // YES after receiving 001 RPL_WELCOME
@property (nonatomic, assign, readonly) BOOL isJoined;

- (instancetype)initWithConfig:(IRCConfig *)config;
- (BOOL)connect;
- (void)disconnect;
- (void)joinChannel:(NSString *)channel;
- (void)sendMessage:(NSString *)message toTarget:(NSString *)target;
- (void)sendRawCommand:(NSString *)command;
- (void)run; // Start message processing loop

@end

NS_ASSUME_NONNULL_END
