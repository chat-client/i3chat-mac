//
//  ChatViewController+Private.h
//  i3Chat
//
//  Private header for ChatViewController categories
//  This file contains internal interfaces, types, and constants
//

#import "ChatViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "IRCClient.h"
#import "IRCConfig.h"
#import "MessageStorage.h"
#import "StorageConstants.h"
#import "ChannelBuffer.h"
#import "ChannelListWindowController.h"
#import "LinksListWindowController.h"
#import "WhoisWindowController.h"
#import "HistoryWindowController.h"
#import "SettingsWindowController.h"
#import "LocalizationManager.h"
#import "ServerHistoryStorage.h"
#import "DebugLog.h"
#import "MainWindowController.h"

NS_ASSUME_NONNULL_BEGIN

// MARK: - Constants

// Channel-specific constants (defined in ChatViewController.m)
extern NSString * const ChannelKeySeparator;
extern NSString * const ChannelGroupInfoGroupKey;
extern NSString * const ChannelGroupInfoChannelKey;

// Storage constants are defined in StorageConstants.h
// Use kChannelBackgroundColorDefaultsPrefix, kChannelCustomGroupsDefaultsKey, 
// kChannelRecentListDefaultsKey, kFavoritesItemsDefaultsKey from StorageConstants.h

// MARK: - Enums

typedef NS_ENUM(NSInteger, ChannelTreeItemType) {
    ChannelTreeItemTypeServer = 0,
    ChannelTreeItemTypeChannel = 1,
    ChannelTreeItemTypeGroup = 2,
    ChannelTreeItemTypeRecent = 3,
    ChannelTreeItemTypePlaceholder = 4
};

typedef NS_ENUM(NSInteger, ChannelListMode) {
    ChannelListModeChannels = 0,
    ChannelListModeGroups = 1,
    ChannelListModeRecent = 2
};

typedef NS_ENUM(NSInteger, SidebarMode) {
    SidebarModeMessages = 0,
    SidebarModeFavorites = 1
};

typedef NS_ENUM(NSInteger, FavoritesFilter) {
    FavoritesFilterAll = 0,
    FavoritesFilterRecent = 1,
    FavoritesFilterLinks = 2,
    FavoritesFilterMedia = 3,
    FavoritesFilterFiles = 4,
    FavoritesFilterHistory = 5
};

// MARK: - Helper Classes

@interface ChannelTreeItem : NSObject
@property (nonatomic, assign) ChannelTreeItemType type;
@property (nonatomic, strong) NSString *server;
@property (nonatomic, strong, nullable) NSString *channelKey;
@end

// MARK: - Custom Views

@interface ChatView : NSView
@property (nonatomic, weak) ChatViewController *chatViewController;
@end

@interface ChatTextView : NSTextView
@property (nonatomic, weak) ChatViewController *chatViewController;
@end

@interface FavoritesTextView : NSTextView
@property (nonatomic, weak) ChatViewController *chatViewController;
@end

// MARK: - Private Interface

// Note: Protocol conformances are declared in the category interfaces below
// to allow implementations in separate category files without compiler warnings.
@interface ChatViewController ()

// Methods implemented in main class, called from categories
- (void)updateWindowTitleForChatName:(NSString *)chatName;

// Data Management
@property (nonatomic, strong) NSArray<IRCConfig *> *configs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, IRCConfig *> *serverConfigs;
@property (nonatomic, strong) NSMutableDictionary<NSString *, IRCClient *> *ircClients;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ChannelBuffer *> *channels;
@property (nonatomic, strong) NSMutableArray<NSString *> *serverOrder;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *serverChannelOrder;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ChannelTreeItem *> *serverItems;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ChannelTreeItem *> *channelItems;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *joinedChannels;
@property (nonatomic, strong) NSMutableSet<NSString *> *disconnectedServers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableSet<NSString *> *> *autoJoinChannels;
@property (nonatomic, assign) BOOL isLoadingPersistedChannels;
@property (nonatomic, strong, nullable) NSString *currentChannelKey;
@property (nonatomic, strong) NSString *currentServer;

// UI Components - Main Layout
@property (nonatomic, strong) NSSplitView *mainSplitView;
@property (nonatomic, strong) NSSplitView *middleSplitView;
@property (nonatomic, strong) NSView *channelPanel;
@property (nonatomic, strong) NSView *leftToolbarView;
@property (nonatomic, strong) NSStackView *leftToolbarStackView;
@property (nonatomic, strong) NSButton *messagesToolbarButton;
@property (nonatomic, strong) NSButton *favoritesToolbarButton;
@property (nonatomic, strong) NSView *channelContentContainer;
@property (nonatomic, strong) NSScrollView *channelScrollView;
@property (nonatomic, strong) NSView *channelAdBanner;
@property (nonatomic, strong) NSTextField *channelAdLabel;
@property (nonatomic, strong) NSImageView *channelAdImageView;
@property (nonatomic, strong) NSString *channelAdTargetURL;
@property (nonatomic, strong) NSView *bottomBar;
@property (nonatomic, strong) NSView *channelBottomBar;
@property (nonatomic, strong) NSView *inputBar;
@property (nonatomic, strong) NSView *middleContainer;
@property (nonatomic, strong) NSView *middleBottomSpacer;
@property (nonatomic, strong) NSView *userPanelContainer;
@property (nonatomic, strong) NSView *userPanelContent;

// UI Components - Chat
@property (nonatomic, strong) NSScrollView *chatScrollView;
@property (nonatomic, strong) NSTextView *chatTextView;
@property (nonatomic, strong) NSScrollView *logScrollView;
@property (nonatomic, strong) NSView *logContainer;
@property (nonatomic, strong) NSTextView *logTextView;
@property (nonatomic, strong) NSOutlineView *channelListView;
@property (nonatomic, strong) NSTableView *userListView;
@property (nonatomic, strong) NSTextField *userCountLabel;
@property (nonatomic, strong) NSSearchField *userSearchField;
@property (nonatomic, copy, nullable) NSString *userSearchQuery;
@property (nonatomic, strong) NSTextField *inputField;
@property (nonatomic, strong) NSTextField *statusField;

// UI Components - Channel List Mode
@property (nonatomic, strong) NSStackView *channelListModeStackView;
@property (nonatomic, strong) NSButton *addButton;
@property (nonatomic, strong) NSButton *channelModeButton;
@property (nonatomic, strong) NSButton *groupModeButton;
@property (nonatomic, strong) NSButton *recentModeButton;

// UI Components - Favorites
@property (nonatomic, strong) NSView *favoritesPanel;
@property (nonatomic, strong) NSTextField *favoritesPanelTitleLabel;
@property (nonatomic, strong) NSArray<NSButton *> *favoritesButtons;
@property (nonatomic, strong) NSView *favoritesMiddleView;
@property (nonatomic, strong) NSTextField *favoritesTitleLabel;
@property (nonatomic, strong) NSScrollView *favoritesScrollView;
@property (nonatomic, strong) NSTableView *favoritesTableView;
@property (nonatomic, strong) NSTextField *favoritesEmptyLabel;
@property (nonatomic, strong) NSMenu *favoritesMenu;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *favoriteItems;
@property (nonatomic, assign) FavoritesFilter currentFavoritesFilter;

// UI State
@property (nonatomic, strong) NSMutableArray<NSString *> *inputHistory;
@property (nonatomic, assign) BOOL logWindowVisible;
@property (nonatomic, assign) BOOL channelListVisible;
@property (nonatomic, assign) BOOL userListVisible;
@property (nonatomic, assign) BOOL userListWasVisibleBeforeFavorites;
@property (nonatomic, assign) CGFloat lastLeftPanelWidth;
@property (nonatomic, assign) CGFloat lastRightPanelWidth;
@property (nonatomic, assign) CGFloat savedChannelPanelWidth;
@property (nonatomic, assign) NSInteger inputHistoryIndex;
@property (nonatomic, strong, nullable) NSString *originalInput;
@property (nonatomic, assign) BOOL showChannelColors;
@property (nonatomic, assign) NSInteger previousChannelListSelectedRow;
@property (nonatomic, assign) NSInteger previousUserListSelectedRow;
@property (nonatomic, assign) BOOL userIsScrolling;  // Track if user has scrolled up
@property (nonatomic, assign) BOOL userPinnedToBottom; // Whether auto-scroll should stay at bottom
@property (nonatomic, assign) NSTimeInterval suppressAutoScrollUntil; // Temporarily suppress auto-scroll
@property (nonatomic, assign) BOOL preserveScrollOnNextRender; // Keep scroll position for next render
@property (nonatomic, assign) NSPoint preservedScrollOrigin;
@property (nonatomic, assign) NSTimeInterval lastScrollEventTime; // Track recent scroll activity
@property (nonatomic, assign) BOOL logUserIsScrolling;
@property (nonatomic, assign) BOOL logUserPinnedToBottom;
@property (nonatomic, assign) NSTimeInterval logLastScrollEventTime;
@property (nonatomic, assign) NSInteger maxMessagesPerChannel;  // Maximum messages to display per channel
@property (nonatomic, assign) CGFloat messageLineSpacing;  // Spacing between messages
@property (nonatomic, assign) BOOL isUpdatingChannelSelection;

// Window Controllers
// Channel list windows: one per server (key = server address)
@property (nonatomic, strong) NSMutableDictionary<NSString *, ChannelListWindowController *> *channelListWindowControllers;
@property (nonatomic, strong, nullable) LinksListWindowController *linksListWindowController;
@property (nonatomic, strong, nullable) WhoisWindowController *whoisWindowController;
@property (nonatomic, strong, nullable) HistoryWindowController *historyWindowController;
@property (nonatomic, strong, nullable) SettingsWindowController *settingsWindowController;

// Whois State
@property (nonatomic, strong, nullable) NSString *pendingWhoisNick;
@property (nonatomic, strong, nullable) NSString *pendingWhoisServer;

// Menus
@property (nonatomic, strong) NSMenu *channelListMenu;
@property (nonatomic, strong) NSMenu *userListMenu;
@property (nonatomic, strong, nullable) NSMenu *autocompleteMenu;

// Channel List State
@property (nonatomic, strong, nullable) NSString *channelListServer;
@property (nonatomic, strong, nullable) NSString *linksListServer;
@property (nonatomic, copy, nullable) NSString *colorEditingChannelKey;
@property (nonatomic, assign) ChannelListMode channelListMode;
@property (nonatomic, assign) SidebarMode leftSidebarMode;

// Recent Channels
@property (nonatomic, strong) NSMutableArray<NSString *> *recentChannelKeys;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ChannelTreeItem *> *recentItems;

// Groups
@property (nonatomic, strong) NSArray<NSString *> *customGroupOrder;
@property (nonatomic, strong) NSDictionary<NSString *, NSArray<NSString *> *> *customGroupChannels;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ChannelTreeItem *> *groupItems;
// Separate channel items for groups mode (key: "groupName:channelKey") to allow same channel in multiple groups
@property (nonatomic, strong) NSMutableDictionary<NSString *, ChannelTreeItem *> *groupChannelItems;
@property (nonatomic, strong, nullable) ChannelTreeItem *groupPlaceholderItem;
@property (nonatomic, assign) BOOL isReloadingChannelList;
@property (nonatomic, assign) BOOL pendingChannelListReload;

// Message Cache
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableArray<NSAttributedString *> *> *cachedAttributedMessages;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastRenderedMessageCount;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *renderStartIndexByChannel;
@property (nonatomic, copy, nullable) NSString *lastDisplayedChannelKey;  // Track which channel is currently displayed in textView
/// When set, displayMessagesForChannel will delete message blocks from textStorage before appending (used when buffer trimmed from head; cache already had elements removed by caller)
@property (nonatomic, copy, nullable) NSString *channelKeyWithTrimmedHead;
/// Number of messages trimmed from head (for batch deletion optimization)
@property (nonatomic, assign) NSUInteger trimmedHeadCount;
// Batch display optimization: track pending display operations
@property (nonatomic, strong) NSMutableSet<NSString *> *pendingDisplayChannels;
@property (nonatomic, strong, nullable) dispatch_source_t displayTimer;
@property (nonatomic, assign) NSTimeInterval lastDisplayTimestamp; // Throttle UI redraws

// Nickname Highlight
// Set of nicknames currently highlighted in chat (empty means no highlight, show all messages normally)
@property (nonatomic, strong) NSMutableSet<NSString *> *highlightedNicknames;

@end

// MARK: - Category Declarations

// UI Category
@interface ChatViewController (UI)
- (void)setupUI;
- (void)updateSidePanelLayouts;
- (void)updateChannelPanelLayout;
- (void)updateInputLayoutForWidth:(CGFloat)width;
- (NSButton *)makeChannelListModeButtonWithSymbol:(NSString *)symbolName fallbackTitle:(NSString *)fallbackTitle tag:(NSInteger)tag;
- (NSButton *)makeSidebarButtonWithSymbol:(NSString *)symbolName fallbackTitle:(NSString *)fallbackTitle tag:(NSInteger)tag;
- (void)updateChannelListModeButtonStates;
- (void)updateChannelListModeButtonTooltips;
- (void)handleAddButtonClicked:(NSButton *)sender;
- (void)updateSidebarButtonStates;
- (void)updateSidebarButtonTooltips;
- (void)handleSidebarModeChanged:(NSButton *)sender;
- (void)updateSidebarModeUI;
- (void)handleChannelListModeChanged:(NSButton *)sender;
- (void)applyAdaptiveLayerColors;
@end

// Channel Category
@interface ChatViewController (Channel)
- (void)connectToServers;
- (NSString *)makeChannelKey:(NSString *)server channel:(NSString *)channel;
- (NSString *)serverFromChannelKey:(NSString *)channelKey;
- (NSString *)channelFromChannelKey:(NSString *)channelKey;
- (IRCClient *)clientForServer:(NSString *)server;
- (IRCConfig *)configForServer:(NSString *)server;
- (IRCConfig *)ensureConfigForServer:(NSString *)server;
- (NSMutableSet<NSString *> *)joinedChannelSetForServer:(NSString *)server createIfNeeded:(BOOL)createIfNeeded;
- (NSMutableSet<NSString *> *)autoJoinChannelSetForServer:(NSString *)server createIfNeeded:(BOOL)createIfNeeded;
- (BOOL)addServerIfNeeded:(NSString *)server;
- (void)addChannel:(NSString *)server channel:(NSString *)channel isPrivate:(BOOL)isPrivate;
- (void)addPersistedChannel:(NSString *)server channel:(NSString *)channel;
- (void)removeChannelWithKey:(NSString *)channelKey;
- (void)switchToChannel:(NSString *)channelKey;
- (void)clearUsersForServer:(NSString *)server;
- (void)selectServerIfEmpty:(NSString *)server;
- (void)selectServer:(NSString *)server;
- (BOOL)isChannelJoined:(ChannelBuffer *)buffer;
- (void)persistServersAndChannels;
- (void)loadPersistedServersAndChannels;

// Recent channels
- (void)recordRecentChannelKey:(NSString *)channelKey;
- (void)removeRecentChannelKey:(NSString *)channelKey;
- (void)loadRecentChannelKeysFromDefaults;
- (void)persistRecentChannelKeys;
- (BOOL)isChannelKeyInServerList:(NSString *)channelKey;
- (ChannelTreeItem *)recentItemForChannelKey:(NSString *)channelKey;
- (void)requestChannelListReload;
- (void)reloadChannelListPreservingSelection;
- (NSString *)displayNameForRecentChannelKey:(NSString *)channelKey;
- (void)reloadChannelListForMode;

// Groups
- (void)loadCustomGroupsFromDefaults;
- (void)persistCustomGroupChannels:(NSDictionary<NSString *, NSArray<NSString *> *> *)groups;
- (BOOL)isChannelKey:(NSString *)channelKey inGroup:(NSString *)groupName;
- (NSString *)existingGroupNameMatching:(NSString *)name;

// Connection/Join Status
- (BOOL)isServerConnected:(NSString *)server;
- (BOOL)isChannelListItemDisabled:(ChannelTreeItem *)item;
@end

// Message Category
@interface ChatViewController (Message)
- (void)displayMessagesForChannel:(NSString *)channelKey;
- (void)addSystemMessage:(NSString *)message;
- (void)addSystemMessage:(NSString *)message forServer:(NSString *)server;
- (NSString *)formatTime;
- (NSString *)formatTimestamp:(NSDate *)date;
- (NSString *)formattedMessageFromStoredMessage:(Message *)message;
- (void)loadRecentMessagesIfNeededForChannelKey:(NSString *)channelKey;
- (NSAttributedString *)parseIRCFormattingString:(NSString *)message font:(NSFont *)font defaultColor:(NSColor *)defaultColor;
- (NSString *)normalizedIRCFormattingString:(NSString *)message;
- (BOOL)isValidHexColorString:(NSString *)string;
- (NSColor *)colorFromHexString:(NSString *)string;
- (NSArray<NSColor *> *)ircColorTable;
- (CGFloat)colorLuminance:(NSColor *)color;
- (BOOL)hasSufficientContrastBetween:(NSColor *)color1 and:(NSColor *)color2;
- (void)updateUserListForChannel:(NSString *)channelKey;
- (BOOL)isScrollViewAtBottom;
- (BOOL)isScrollViewAtTop;
- (void)chatScrollViewBoundsDidChange:(NSNotification *)notification;
- (void)handleUserSearchChanged:(id)sender;
- (NSArray<NSString *> *)displayedUsersForCurrentChannel;
- (void)updateStatus;
// Nickname highlight
- (void)toggleHighlightForNickname:(NSString *)nickname;
- (void)clearAllNicknameHighlights;
- (BOOL)isNicknameHighlighted:(NSString *)nickname;
- (void)openPrivateChatWithNickname:(NSString *)nickname;
- (nullable NSString *)extractNicknameAtPoint:(NSPoint)point inTextView:(NSTextView *)textView;
@end

// IRC Delegate Category
@interface ChatViewController (IRC) <IRCClientDelegate, ChannelListWindowControllerDelegate, WhoisWindowControllerDelegate>
- (ChannelListWindowController *)channelListWindowControllerForClient:(IRCClient *)client;
@end

// DataSource Category
@interface ChatViewController (DataSource) <NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSplitViewDelegate, NSTextViewDelegate>
- (void)applyChannelListRowStyle:(NSTableRowView *)rowView forItem:(ChannelTreeItem *)item;
- (BOOL)isChannelListViewFocused;
- (void)updateChannelListTextColors;
@end

// Menu Category
@interface ChatViewController (Menu) <NSMenuDelegate>
- (NSMenu *)chatMenuForEvent:(NSEvent *)event inTextView:(NSTextView *)textView;
- (void)handleFavoritesCopyShortcutFromTextView:(NSTextView *)textView;
- (void)handleFavoritesOpenShortcutFromTextView:(NSTextView *)textView;
- (NSString *)baseNickFromUserListEntry:(NSString *)user;
- (void)menuJoinChannel:(id)sender;
- (void)menuPartChannel:(id)sender;
- (void)menuPrivateMessage:(id)sender;
- (void)menuChangeNick:(id)sender;
- (void)menuConnectServer:(id)sender;
- (void)menuConnectToServer:(id)sender;
- (void)menuServerLinks:(id)sender;
- (void)menuListChannels:(id)sender;
- (void)menuRawCommand:(id)sender;
- (void)menuHelp:(id)sender;
- (void)menuQuit:(id)sender;

// User menu handlers
- (void)handleUserWhoisFromMenu:(id)sender;
- (void)handleUserInviteFromMenu:(id)sender;

// Channel menu handlers
- (void)handleJoinServerFromMenu:(id)sender;
- (void)handleJoinChannelFromMenu:(id)sender;
- (void)handlePartChannel:(id)sender;
- (void)handleClosePrivateChat:(id)sender;
- (void)handleDeleteChannelFromMenu:(id)sender;
- (void)handleDeleteServerFromMenu:(id)sender;
- (void)handleClearHistoryFromMenu:(id)sender;
- (void)handleShowHistoryFromMenu:(id)sender;
- (void)handleToggleMessageStorage:(id)sender;
- (void)handleRemoveFromRecentFromMenu:(id)sender;

// Group menu handlers
- (void)handleAddChannelToGroup:(id)sender;
- (void)handleCreateGroupFromMenu:(id)sender;
- (void)handleRemoveChannelFromGroup:(id)sender;
- (void)handleDeleteGroupFromMenu:(id)sender;

// Color menu handlers
- (void)handleSetBackgroundColorFromMenu:(id)sender;
- (void)handleResetBackgroundColorFromMenu:(id)sender;
- (void)backgroundColorPanelDidChange:(id)sender;
- (NSString *)backgroundColorSettingKeyForChannelKey:(NSString *)channelKey;
- (NSColor *)defaultChatBackgroundColor;
- (BOOL)hasBackgroundColorForChannelKey:(NSString *)channelKey;
- (nullable NSColor *)loadBackgroundColorForChannelKey:(NSString *)channelKey;
- (nullable NSColor *)colorFromDictionary:(NSDictionary *)colorInfo;
- (void)saveBackgroundColor:(NSColor *)color forChannelKey:(NSString *)channelKey;
- (void)clearBackgroundColorForChannelKey:(NSString *)channelKey;
- (void)applyBackgroundColorForChannelKey:(NSString *)channelKey;

// Message storage handlers
- (NSString *)messageStorageSettingKeyForChannelKey:(NSString *)channelKey;
- (void)saveMessageStorageSetting:(BOOL)enabled forChannelKey:(NSString *)channelKey;
- (BOOL)loadMessageStorageSettingForChannelKey:(NSString *)channelKey;

// Prompt helpers
- (NSString *)promptForInputWithTitle:(NSString *)title message:(NSString *)message placeholder:(NSString *)placeholder;
- (NSString *)promptForChannelFromList:(NSArray<NSString *> *)channels title:(NSString *)title message:(NSString *)message preferredChannel:(NSString *)preferredChannel;
- (BOOL)promptForConnectOptionsForServer:(NSString *)server config:(IRCConfig *)config;
@end

// Input Category
@interface ChatViewController (Input) <NSTextFieldDelegate>
- (void)handleInput;
- (void)handleCommand:(NSString *)command;
- (void)handleLinksCommand:(NSArray *)parts activeServer:(NSString *)activeServer activeClient:(IRCClient *)activeClient;
- (void)handleCommandAutocomplete;
- (void)updateAutocompleteMenuForInput:(NSString *)input;
- (void)showAutocompleteMenuWithMatches:(NSArray<NSString *> *)matches;
- (void)handleAutocompleteMenu:(id)sender;
- (NSArray<NSString *> *)commandAutocompleteList;
- (void)addToInputHistory:(NSString *)input;
- (void)navigateHistory:(BOOL)forward;
- (void)showHelp;
- (BOOL)handleChannelListNavigation:(NSEvent *)event;
- (NSInteger)firstSelectableChannelRow;
- (NSInteger)nextSelectableChannelRowFrom:(NSInteger)start direction:(NSInteger)direction;
@end

// Favorites Category
@interface ChatViewController (Favorites)
- (NSArray<NSDictionary<NSString *, id> *> *)favoritesButtonConfigs;
- (NSButton *)makeFavoritesButtonWithTitle:(NSString *)title;
- (void)handleFavoritesButtonClicked:(NSButton *)sender;
- (void)updateFavoritesButtonTitles;
- (void)updateFavoritesButtonStates;
- (NSArray<NSDictionary *> *)filteredFavoriteItems;
- (BOOL)favoriteItemIsMedia:(NSDictionary *)item;
- (BOOL)favoriteItemIsFile:(NSDictionary *)item;
- (NSString *)pathExtensionForURLString:(NSString *)urlString;
- (void)reloadFavoritesTable;
- (void)updateFavoritesEmptyState;
- (void)layoutFavoritesButtonsInPanel;
- (NSString *)displayTextForFavoriteItem:(NSDictionary *)item;
- (void)addFavoriteItem:(NSDictionary *)item;
- (void)addFavoriteItemWithType:(NSString *)type content:(NSString *)content url:(nullable NSString *)urlString;
- (void)removeFavoriteItemAtIndex:(NSUInteger)index;
@end

// Settings Delegate
@interface ChatViewController (Settings) <SettingsWindowControllerDelegate>
- (void)openSettings;
@end

NS_ASSUME_NONNULL_END
