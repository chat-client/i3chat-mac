//
//  StorageConstants.h
//  i3Chat
//
//  Global constants for storage paths and filenames
//  All data is stored in SQLite database at ~/.i3chat/
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Application name
extern NSString * const kAppName;

// Storage directory (hidden directory in user's home)
extern NSString * const kStorageDirectoryName;           // .i3chat

// Database file
extern NSString * const kDatabaseFilename;               // i3chat.db

// Database table names
extern NSString * const kTableMessages;
extern NSString * const kTableServerHistory;
extern NSString * const kTableFavorites;
extern NSString * const kTableServersChannels;
extern NSString * const kTableSettings;

// Settings keys (stored in SQLite settings table)
extern NSString * const kSettingLanguageCode;
extern NSString * const kSettingShowLogWindowOnStartup;
extern NSString * const kSettingShowChannelColors;
extern NSString * const kSettingRecentChannelKeys;
extern NSString * const kSettingCustomChannelGroups;
extern NSString * const kSettingChannelBackgroundColorPrefix;
extern NSString * const kSettingChannelMessageStoragePrefix;
extern NSString * const kSettingMaxMessagesPerChannel;
extern NSString * const kSettingMessageLineSpacing;

// Default values
extern NSInteger const kDefaultMaxMessagesPerChannel;
extern NSInteger const kDefaultMessageLineSpacing;

// Legacy UserDefaults keys (deprecated, migrating to SQLite)
extern NSString * const kChannelBackgroundColorDefaultsPrefix;
extern NSString * const kChannelRecentListDefaultsKey;
extern NSString * const kChannelCustomGroupsDefaultsKey;
extern NSString * const kShowLogWindowOnStartupKey;
extern NSString * const kShowChannelColorsKey;

// Dispatch queue identifiers
extern NSString * const kStorageQueueName;

// Helper functions
NSString * _Nullable StorageGetHomeDirectory(void);
NSString * _Nullable StorageGetStorageDirectory(void);
NSString * _Nullable StorageGetDatabasePath(void);
BOOL StorageEnsureDirectoryExists(NSString *path);

NS_ASSUME_NONNULL_END
