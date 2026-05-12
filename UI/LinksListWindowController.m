#import "LinksListWindowController.h"
#import "DebugLog.h"
#import "LocalizationManager.h"

@interface LinksTreeNode : NSObject
@property (nonatomic, strong) NSString *server;
@property (nonatomic, strong) NSString *info;
@property (nonatomic, assign) NSInteger hopCount;
@property (nonatomic, strong) NSMutableArray<LinksTreeNode *> *children;
@end

@implementation LinksTreeNode
@end

@interface LinksListWindowController ()

@property (nonatomic, strong) NSOutlineView *outlineView;
@property (nonatomic, strong) NSTableColumn *serverColumn;
@property (nonatomic, strong) NSTableColumn *hopColumn;
@property (nonatomic, strong) NSTableColumn *infoColumn;
@property (nonatomic, strong) NSButton *closeButton;
@property (nonatomic, strong) NSMutableArray<LinksTreeNode *> *rootNodes;

@end

@implementation LinksListWindowController

- (instancetype)init {
    _links = [[NSMutableArray alloc] init];
    _rootNodes = [[NSMutableArray alloc] init];

    NSRect screenRect = [[NSScreen mainScreen] frame];
    NSRect windowRect = NSMakeRect(
        (screenRect.size.width - 800) / 2,
        (screenRect.size.height - 500) / 2,
        800,
        500
    );

    NSWindow *window = [[NSWindow alloc] initWithContentRect:windowRect
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:L(@"links.window.title", @"Server Links")];
    [window setMinSize:NSMakeSize(600, 400)];
    [window setDelegate:self];
    [window setLevel:NSFloatingWindowLevel];
    [window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
    [window setHidesOnDeactivate:NO];

    self = [super initWithWindow:window];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applyLocalization)
                                                     name:LocalizationDidChangeNotification
                                                   object:nil];
        NSView *contentView = window.contentView;
        contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

        NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 50, 780, 420)];
        scrollView.hasVerticalScroller = YES;
        scrollView.hasHorizontalScroller = YES;
        scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        scrollView.borderType = NSBezelBorder;
        [contentView addSubview:scrollView];

        self.outlineView = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 780, 420)];
        self.outlineView.delegate = self;
        self.outlineView.dataSource = self;
        self.outlineView.allowsMultipleSelection = NO;
        self.outlineView.usesAlternatingRowBackgroundColors = YES;
        self.outlineView.rowHeight = 22;

        self.serverColumn = [[NSTableColumn alloc] initWithIdentifier:@"Server"];
        self.serverColumn.title = L(@"links.column.server", @"Server");
        self.serverColumn.width = 240;
        self.serverColumn.minWidth = 160;
        [self.outlineView addTableColumn:self.serverColumn];
        self.outlineView.outlineTableColumn = self.serverColumn;

        self.hopColumn = [[NSTableColumn alloc] initWithIdentifier:@"Hop"];
        self.hopColumn.title = L(@"links.column.hop", @"Hop");
        self.hopColumn.width = 60;
        self.hopColumn.minWidth = 50;
        [self.outlineView addTableColumn:self.hopColumn];

        self.infoColumn = [[NSTableColumn alloc] initWithIdentifier:@"Info"];
        self.infoColumn.title = L(@"links.column.info", @"Info");
        self.infoColumn.width = 460;
        self.infoColumn.minWidth = 200;
        [self.outlineView addTableColumn:self.infoColumn];

        scrollView.documentView = self.outlineView;

        self.closeButton = [[NSButton alloc] initWithFrame:NSMakeRect(690, 10, 100, 32)];
        [self.closeButton setTitle:L(@"links.button.close", @"Close")];
        [self.closeButton setButtonType:NSButtonTypeMomentaryPushIn];
        [self.closeButton setBezelStyle:NSBezelStyleRounded];
        [self.closeButton setTarget:self];
        [self.closeButton setAction:@selector(closeButtonClicked:)];
        [contentView addSubview:self.closeButton];
    }
    return self;
}

- (void)beginReceivingForServer:(NSString *)server {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self beginReceivingForServer:server];
        });
        return;
    }

    [self.links removeAllObjects];
    [self.rootNodes removeAllObjects];
    [self.outlineView reloadData];

    NSString *title = server.length > 0
        ? [NSString stringWithFormat:L(@"links.title.receivingWithServer", @"Server Links (%@) - Receiving..."), server]
        : L(@"links.title.receiving", @"Server Links - Receiving...");
    [self.window setTitle:title];

    [super showWindow:nil];
    [self.window setLevel:NSFloatingWindowLevel];
    [self.window orderFrontRegardless];
}

- (void)addLinkWithServer:(NSString *)server mask:(NSString *)mask hopCount:(NSInteger)hopCount info:(NSString *)info {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self addLinkWithServer:server mask:mask hopCount:hopCount info:info];
        });
        return;
    }

    if (!self.links) {
        self.links = [[NSMutableArray alloc] init];
    }

    NSDictionary *linkInfo = @{
        @"server": server ?: @"",
        @"mask": mask ?: @"",
        @"hopCount": @(hopCount),
        @"info": info ?: @""
    };
    [self.links addObject:linkInfo];

    if (self.window) {
        [self.window setTitle:[NSString stringWithFormat:L(@"links.title.receivingCount", @"Server Links (Receiving... %lu)"), (unsigned long)self.links.count]];
    }
}

- (void)finalizeLinks {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finalizeLinks];
        });
        return;
    }

    if (!self.links || self.links.count == 0) {
        [self.outlineView reloadData];
        if (self.window) {
            [self.window setTitle:L(@"links.title.empty", @"Server Links (0)")];
        }
        return;
    }

    NSArray *linksSnapshot = [self.links copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray<LinksTreeNode *> *rootNodes = [[NSMutableArray alloc] init];
        NSMutableArray<LinksTreeNode *> *stack = [[NSMutableArray alloc] init];

        for (NSDictionary *link in linksSnapshot) {
            NSString *server = link[@"server"] ?: @"";
            NSString *info = link[@"info"] ?: @"";
            NSInteger hopCount = [link[@"hopCount"] integerValue];

            LinksTreeNode *node = [[LinksTreeNode alloc] init];
            node.server = server;
            node.info = info;
            node.hopCount = hopCount;
            node.children = [[NSMutableArray alloc] init];

            NSInteger depth = hopCount >= 0 ? hopCount : 0;
            while (stack.count > depth) {
                [stack removeLastObject];
            }

            LinksTreeNode *parent = (depth > 0 && stack.count >= depth) ? stack[depth - 1] : nil;
            if (parent) {
                [parent.children addObject:node];
            } else {
                [rootNodes addObject:node];
            }

            if (stack.count == depth) {
                [stack addObject:node];
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.rootNodes = rootNodes;
            [self.outlineView reloadData];
            [self.outlineView expandItem:nil expandChildren:YES];
            if (self.window) {
                [self.window setTitle:[NSString stringWithFormat:L(@"links.title.count", @"Server Links (%lu)"), (unsigned long)linksSnapshot.count]];
            }
        });
    });
}

- (void)closeButtonClicked:(id)sender {
    [self.window close];
}

- (void)windowWillClose:(NSNotification *)notification {
    [self.links removeAllObjects];
    [self.rootNodes removeAllObjects];
    [self.outlineView reloadData];
}

- (void)applyLocalization {
    if (self.window) {
        [self.window setTitle:L(@"links.window.title", @"Server Links")];
    }
    if (self.serverColumn) {
        self.serverColumn.title = L(@"links.column.server", @"Server");
    }
    if (self.hopColumn) {
        self.hopColumn.title = L(@"links.column.hop", @"Hop");
    }
    if (self.infoColumn) {
        self.infoColumn.title = L(@"links.column.info", @"Info");
    }
    if (self.closeButton) {
        [self.closeButton setTitle:L(@"links.button.close", @"Close")];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (!item) {
        return self.rootNodes.count;
    }
    if (![item isKindOfClass:[LinksTreeNode class]]) {
        return 0;
    }
    LinksTreeNode *node = (LinksTreeNode *)item;
    return node.children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (!item) {
        return (index >= 0 && index < self.rootNodes.count) ? self.rootNodes[index] : nil;
    }
    if (![item isKindOfClass:[LinksTreeNode class]]) {
        return nil;
    }
    LinksTreeNode *node = (LinksTreeNode *)item;
    return (index >= 0 && index < node.children.count) ? node.children[index] : nil;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    if (![item isKindOfClass:[LinksTreeNode class]]) {
        return NO;
    }
    LinksTreeNode *node = (LinksTreeNode *)item;
    return node.children.count > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    if (![item isKindOfClass:[LinksTreeNode class]]) {
        return @"";
    }
    LinksTreeNode *node = (LinksTreeNode *)item;
    if ([tableColumn.identifier isEqualToString:@"Server"]) {
        return node.server ?: @"";
    }
    if ([tableColumn.identifier isEqualToString:@"Hop"]) {
        return node.hopCount >= 0 ? [NSString stringWithFormat:@"%ld", (long)node.hopCount] : @"";
    }
    if ([tableColumn.identifier isEqualToString:@"Info"]) {
        return node.info ?: @"";
    }
    return @"";
}

@end
