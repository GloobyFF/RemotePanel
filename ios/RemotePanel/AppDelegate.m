#import "AppDelegate.h"
#import "RPKioskRootVC.h"
#import "RPPages.h"
#import "RPTheme.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [RPTheme registerFonts];
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [RPTheme bg];
    self.window.rootViewController = [[RPKioskRootVC alloc] init];
    [self.window makeKeyAndVisible];
    [UIApplication sharedApplication].idleTimerDisabled = YES;
    return YES;
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {
    RPPurgeImageCache();
}

@end
