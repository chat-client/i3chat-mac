//
//  StorageConstants.m
//  i3Chat
//
//  Global constants for storage paths and filenames
//  All data is stored in SQLite database at ~/.i3chat/
//

#import "StorageConstants.h"

// Application name
NSString * const kAppName = @"i3Chat";

// Storage directory
NSString * const kStorageDirectoryName = @".i3chat";

// Database file
NSString * const kDatabaseFilename = @"i3chat.db";

// Database table names
NSString * const kTableMessages = @"messages";
NSString * const kTableServerHistory = @"server_history";
NSString * const kTableFavorites = @"favorites";
NSString * const kTableServersChannels = @"servers_channels";
NSString * const kTableSettings = @"settings";

// Settings keys (stored in SQLite settings table)
NSString * const kSettingLanguageCode = @"language_code";
NSString * const kSettingShowLogWindowOnStartup = @"show_log_window_on_startup";
NSString * const kSettingShowChannelColors = @"show_channel_colors";
NSString * const kSettingRecentChannelKeys = @"recent_channel_keys";
NSString * const kSettingCustomChannelGroups = @"custom_channel_groups";
NSString * const kSettingChannelBackgroundColorPrefix = @"channel_bg_color.";
NSString * const kSettingChannelMessageStoragePrefix = @"channel_msg_storage.";
NSString * const kSettingMaxMessagesPerChannel = @"max_messages_per_channel";
NSString * const kSettingMessageLineSpacing = @"message_line_spacing";

// Default values
NSInteger const kDefaultMaxMessagesPerChannel = 2000;
NSInteger const kDefaultMessageLineSpacing = 2;

// Legacy UserDefaults keys (deprecated, will be migrated to SQLite)
NSString * const kChannelBackgroundColorDefaultsPrefix = @"ChannelBackgroundColor.";
NSString * const kChannelRecentListDefaultsKey = @"RecentChannelKeys";
NSString * const kChannelCustomGroupsDefaultsKey = @"CustomChannelGroups";
NSString * const kShowLogWindowOnStartupKey = @"ShowLogWindowOnStartup";
NSString * const kShowChannelColorsKey = @"ShowChannelColors";

// Dispatch queue identifier
NSString * const kStorageQueueName = @"com.i3chat.storage";

#pragma mark - Helper Functions

NSString * StorageGetHomeDirectory(void) {
    return NSHomeDirectory();
}

NSString * StorageGetStorageDirectory(void) {
    NSString *homeDir = StorageGetHomeDirectory();
    if (!homeDir) {
        return nil;
    }
    return [homeDir stringByAppendingPathComponent:kStorageDirectoryName];
}

NSString * StorageGetDatabasePath(void) {
    NSString *storageDir = StorageGetStorageDirectory();
    if (!storageDir) {
        return nil;
    }
    return [storageDir stringByAppendingPathComponent:kDatabaseFilename];
}

BOOL StorageEnsureDirectoryExists(NSString *path) {
    if (!path || path.length == 0) {
        return NO;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path]) {
        return YES;
    }
    NSError *error = nil;
    BOOL success = [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
    if (!success) {
        NSLog(@"[Storage] Failed to create directory %@: %@", path, error);
    }
    return success;
}
