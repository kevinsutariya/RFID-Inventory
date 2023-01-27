//
//  TSLAppDelegate.m
//  Inventory
//
//  Copyright (c) 2013 Technology Solutions (UK) Ltd. All rights reserved.
//

#import <TSLAsciiCommands/TSLAsciiCommands.h>

#import "TSLAppDelegate.h"

@interface TSLAppDelegate ()

@property (nonatomic, readwrite) TSLAsciiCommander *commander;

@end

@implementation TSLAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [[EAAccessoryManager sharedAccessoryManager] registerForLocalNotifications];

    // Override point for customization after application launch.
    // Create the commander
    self.commander = [[TSLAsciiCommander alloc] init];

#ifdef DEBUG
    // Log all Reader responses when debugging
    [self.commander addResponder:[[TSLLoggerResponder alloc] init]];
#endif

    // Some synchronous commands will be used in the app
    [self.commander addSynchronousResponder];

    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    if( self.commander.isConnected )
    {
        // Stop any synchronous commands and tell the reader to abort
        // This is to leave the reader in the best possible state for other Apps
        @try
        {
            [self.commander abortSynchronousCommand];
            [self.commander executeCommand:[TSLAbortCommand synchronousCommand]];
            [self.commander disconnect];
        }
        @catch (NSException *exception)
        {
            NSLog( @"Unable to disconnect when resigningActive: %@", exception.reason);
        }
    }
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.

    // Attempt to reconnect to the last used accessory
    if( !self.commander.isConnected )
    {
        [self.commander connect:nil];
    }
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.

    // Dispose of the commander
    [self.commander halt];
    self.commander = nil;
}

@end
