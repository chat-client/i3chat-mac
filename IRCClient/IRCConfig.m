//
//  IRCConfig.m
//  i3Chat
//

#import "IRCConfig.h"

@implementation IRCConfig

- (instancetype)initWithServer:(NSString *)server
                          nick:(NSString *)nick
                          user:(NSString *)user
                      realName:(NSString *)realName
                       channel:(NSString *)channel
                      password:(nullable NSString *)password
                        useTLS:(BOOL)useTLS {
    self = [super init];
    if (self) {
        _server = server;
        _nick = nick;
        _user = user;
        _realName = realName;
        _channel = channel;
        _password = password;
        _useTLS = useTLS;
    }
    return self;
}

@end
