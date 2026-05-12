//
//  MessageStorage.h
//  i3Chat
//
//  Central storage for all application data using SQLite
//  Database location: ~/.i3chat/i3chat.db
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class Message;

@interface MessageStorage : NSObject

+ (instancetype)sharedStorage;
- (BOOL)initializeDatabase;

#pragma mark - Messages

- (BOOL)saveMessage:(Message *)message;
- (NSArray<Message *> *)loadMessagesForWindowKey:(NSString *)windowKey limit:(NSInteger)limit;
- (NSArray<Message *> *)loadRecentMessagesForWindowKey:(NSString *)windowKey limit:(NSInteger)limit;
- (NSArray<Message *> *)searchMessagesForWindowKey:(NSString *)windowKey keyword:(NSString *)keyword limit:(NSInteger)limit;
- (NSArray<Message *> *)searchMessagesForWindowKey:(NSString *)windowKey
                                           keyword:(NSString *)keyword
                                         startDate:(NSDate * _Nullable)startDate
                                           endDate:(NSDate * _Nullable)endDate
                                             limit:(NSInteger)limit;
- (BOOL)deleteMessagesForWindowKey:(NSString *)windowKey;
- (NSArray<NSString *> *)getWindowList;
- (NSInteger)getMessageCountForWindowKey:(NSString *)windowKey;

#pragma mark - Favorites

- (BOOL)saveFavoriteItem:(NSDictionary *)item;
- (NSArray<NSDictionary *> *)loadAllFavorites;
- (BOOL)deleteFavoriteById:(NSInteger)favoriteId;
- (BOOL)deleteAllFavorites;

#pragma mark - Servers and Channels Configuration

- (BOOL)saveServersChannelsConfig:(NSDictionary *)config;
- (NSDictionary * _Nullable)loadServersChannelsConfig;

#pragma mark - Settings

- (NSString * _Nullable)getSettingForKey:(NSString *)key;
- (BOOL)setSettingForKey:(NSString *)key value:(NSString * _Nullable)value;
- (BOOL)deleteSettingForKey:(NSString *)key;
- (NSDictionary<NSString *, NSString *> *)getAllSettings;

@end

@interface Message : NSObject

@property (nonatomic, strong) NSString *windowKey;
@property (nonatomic, strong) NSString *sender;
@property (nonatomic, strong) NSString *content;
@property (nonatomic, strong) NSString *msgType; // "self", "other", "private", "notice", "system"
@property (nonatomic, strong) NSDate *timestamp;

- (instancetype)initWithWindowKey:(NSString *)windowKey
                            sender:(NSString *)sender
                           content:(NSString *)content
                           msgType:(NSString *)msgType
                         timestamp:(NSDate *)timestamp;

@end

NS_ASSUME_NONNULL_END
