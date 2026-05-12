//
//  IRCConfig.h
//  i3Chat
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface IRCConfig : NSObject

@property (nonatomic, strong) NSString *server;
@property (nonatomic, strong) NSString *nick;
@property (nonatomic, strong) NSString *user;
@property (nonatomic, strong) NSString *realName;
@property (nonatomic, strong) NSString *channel;
@property (nonatomic, strong, nullable) NSString *password;
@property (nonatomic, assign) BOOL useTLS;

- (instancetype)initWithServer:(NSString *)server
                          nick:(NSString *)nick
                          user:(NSString *)user
                      realName:(NSString *)realName
                       channel:(NSString *)channel
                      password:(nullable NSString *)password
                        useTLS:(BOOL)useTLS;

@end

NS_ASSUME_NONNULL_END
