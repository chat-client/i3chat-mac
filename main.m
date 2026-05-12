//
//  main.m
//  i3Chat
//
//  Created on macOS
//

#import <Cocoa/Cocoa.h>
#import "UI/AppDelegate.h"
#import "DebugLog.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        @try {
            NSApplication *app = [NSApplication sharedApplication];
            AppDelegate *delegate = [[AppDelegate alloc] init];
            app.delegate = delegate;
            return NSApplicationMain(argc, argv);
        } @catch (NSException *exception) {
            // 致命错误始终输出，不受日志开关控制
            NSLog(@"Fatal exception in main: %@", exception);
            fprintf(stderr, "Fatal error: %s\n", [exception.reason UTF8String]);
            return 1;
        }
    }
}
