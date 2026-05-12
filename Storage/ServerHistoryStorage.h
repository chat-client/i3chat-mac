//
//  ServerHistoryStorage.h
//  i3Chat
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const ServerHistoryDidUpdateNotification;

@interface LoginInfo : NSObject

@property (nonatomic, strong) NSString *server;
@property (nonatomic, strong, nullable) NSString *nick;
@property (nonatomic, strong, nullable) NSString *channel;
@property (nonatomic, strong, nullable) NSString *realName;
@property (nonatomic, strong, nullable) NSString *password;
@property (nonatomic, assign) BOOL savePassword;
@property (nonatomic, assign) BOOL useTLS;

@end

@interface ServerHistoryStorage : NSObject

+ (instancetype)sharedStorage;
- (BOOL)saveLoginHistoryWithServer:(NSString *)server
                               nick:(nullable NSString *)nick
                            channel:(nullable NSString *)channel
                           realName:(nullable NSString *)realName
                           password:(nullable NSString *)password
                       savePassword:(BOOL)savePassword
                             useTLS:(BOOL)useTLS;
- (BOOL)touchLoginHistoryWithServer:(NSString *)server
                               nick:(nullable NSString *)nick
                            channel:(nullable NSString *)channel
                           realName:(nullable NSString *)realName
                             useTLS:(BOOL)useTLS;
- (nullable LoginInfo *)getLastLoginInfo;
- (NSArray<NSString *> *)getServerHistoryWithLimit:(NSInteger)limit;
- (BOOL)deleteServerFromHistory:(NSString *)server;

@end

NS_ASSUME_NONNULL_END
