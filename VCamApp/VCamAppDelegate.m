#import "VCamAppDelegate.h"
#import "VCamRootViewController.h"

@implementation VCamAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[[VCamRootViewController alloc] init]];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
