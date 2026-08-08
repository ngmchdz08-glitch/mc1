#import "VCamOverlayManager.h"
#import "VCamControlPanel.h"
#import "VCamColorPicker.h"
#import "VCamSettings.h"
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>
#import <os/log.h>

static os_log_t overlayLog;

static void vcamOverlayStateChanged(CFNotificationCenterRef center,
                                     void *observer,
                                     CFNotificationName name,
                                     const void *object,
                                     CFDictionaryRef userInfo) {
    VCamOverlayManager *mgr = (__bridge VCamOverlayManager *)observer;
    VCamSettings *settings = [VCamSettings shared];
    [settings reload];
    if (mgr.controlPanel) {
        [mgr.controlPanel updateZoomValue:settings.zoom];
    }
}

// Status change notification from camera daemon
static void vcamStatusChanged(CFNotificationCenterRef center,
                              void *observer,
                              CFNotificationName name,
                              const void *object,
                              CFDictionaryRef userInfo) {
    VCamOverlayManager *mgr = (__bridge VCamOverlayManager *)observer;
    // Read status plist
    NSString *statusPath = @"/var/jb/var/mobile/Library/VCam/CameraStatus.plist";
    NSDictionary *status = [NSDictionary dictionaryWithContentsOfFile:statusPath];
    if (!status) statusPath = @"/var/mobile/Library/VCam/CameraStatus.plist";
    status = [NSDictionary dictionaryWithContentsOfFile:statusPath];
    if (!status) return;
    
    NSString *state = status[@"state"] ?: @"unknown";
    BOOL active = [state isEqualToString:@"active"];
    NSString *msg = active ? @"Active" : @"Waiting...";
    if (mgr.controlPanel) {
        [mgr.controlPanel updateStatus:msg active:active];
    }
}

@implementation VCamOverlayManager

+ (instancetype)shared {
    static VCamOverlayManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCamOverlayManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        overlayLog = os_log_create("com.vcam.mch", "overlay");
        _enabled = NO;
        _lockScreenActive = NO;
        
        // Listen for config changes
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self,
            vcamOverlayStateChanged,
            CFSTR("com.vcam.state.changed"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        // Listen for camera status updates
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self,
            vcamStatusChanged,
            CFSTR("com.vcam.camera.status.changed"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        // Listen for device orientation
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIDeviceOrientationDidChangeNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            VCamSettings *settings = [VCamSettings shared];
            UIDeviceOrientation orient = [UIDevice currentDevice].orientation;
            [settings setDeviceOrientation:(NSInteger)orient];
        }];
        
        // Protected data notifications (lock screen)
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationProtectedDataDidBecomeAvailable
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            self.lockScreenActive = NO;
            [self updateVisibility];
        }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationProtectedDataWillBecomeUnavailable
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            self.lockScreenActive = YES;
            [self updateVisibility];
        }];
    }
    return self;
}

- (void)setEnabled:(BOOL)enabled inWindow:(UIWindow *)window {
    _enabled = enabled;
    _hostWindow = window;
    
    if (enabled) {
        [self installOverlay];
    } else {
        [self clearOverlay];
    }
}

- (void)installOverlay {
    if (_overlayWindow) return;
    
    // Find window scene
    UIWindowScene *scene = nil;
    for (UIScene *s in [UIApplication sharedApplication].connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive) {
            scene = (UIWindowScene *)s;
            break;
        }
    }
    if (!scene) return;
    
    // Create overlay window
    _overlayWindow = [[UIWindow alloc] initWithWindowScene:scene];
    _overlayWindow.frame = [UIScreen mainScreen].bounds;
    _overlayWindow.windowLevel = UIWindowLevelAlert + 100;
    _overlayWindow.backgroundColor = [UIColor clearColor];
    _overlayWindow.userInteractionEnabled = YES;
    
    _overlayController = [[UIViewController alloc] init];
    _overlayController.view.backgroundColor = [UIColor clearColor];
    _overlayController.view.userInteractionEnabled = YES;
    _overlayWindow.rootViewController = _overlayController;
    
    // Create floating button
    [self createFloatingButton];
    
    // Create control panel
    _controlPanel = [[VCamControlPanel alloc] initWithFrame:CGRectZero];
    _controlPanel.hidden = YES;
    [_overlayController.view addSubview:_controlPanel];
    
    __weak typeof(self) weakSelf = self;
    _controlPanel.commandHandler = ^(NSString *command) {
        [weakSelf handleCommand:command];
    };
    
    [_overlayWindow setHidden:NO];
    
    os_log(overlayLog, "Vcam_Mch overlay installed");
}

- (void)createFloatingButton {
    _floatingButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _floatingButton.frame = CGRectMake(20, 100, 50, 50);
    _floatingButton.layer.cornerRadius = 25;
    _floatingButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    _floatingButton.tintColor = [UIColor whiteColor];
    _floatingButton.layer.borderWidth = 1.5;
    _floatingButton.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.3].CGColor;
    _floatingButton.layer.shadowColor = [UIColor blackColor].CGColor;
    _floatingButton.layer.shadowOpacity = 0.5;
    _floatingButton.layer.shadowRadius = 8;
    _floatingButton.layer.shadowOffset = CGSizeMake(0, 2);
    
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    UIImage *icon = [[UIImage systemImageNamed:@"camera.aperture"] imageWithConfiguration:config];
    [_floatingButton setImage:icon forState:UIControlStateNormal];
    _floatingButton.accessibilityLabel = @"Vcam_Mch Control";
    
    [_floatingButton addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    
    // Drag gesture
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragFloatingButton:)];
    [_floatingButton addGestureRecognizer:pan];
    
    [_overlayController.view addSubview:_floatingButton];
}

- (void)togglePanel {
    if (!_controlPanel) return;
    
    BOOL willShow = _controlPanel.hidden;
    
    if (willShow) {
        [_controlPanel updatePanelFrame];
        _controlPanel.hidden = NO;
        _controlPanel.alpha = 0;
        _controlPanel.transform = CGAffineTransformMakeScale(0.8, 0.8);
        [UIView animateWithDuration:0.25 animations:^{
            self->_controlPanel.alpha = 1.0;
            self->_controlPanel.transform = CGAffineTransformIdentity;
        }];
    } else {
        [UIView animateWithDuration:0.2 animations:^{
            self->_controlPanel.alpha = 0;
            self->_controlPanel.transform = CGAffineTransformMakeScale(0.8, 0.8);
        } completion:^(BOOL finished) {
            self->_controlPanel.hidden = YES;
        }];
    }
}

- (void)dragFloatingButton:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:_overlayController.view];
    CGPoint center = _floatingButton.center;
    center.x += translation.x;
    center.y += translation.y;
    _floatingButton.center = center;
    [gesture setTranslation:CGPointZero inView:_overlayController.view];
    
    if (gesture.state == UIGestureRecognizerStateEnded) {
        [_controlPanel updatePanelFrame];
    }
}

- (void)handleCommand:(NSString *)command {
    VCamSettings *settings = [VCamSettings shared];
    
    if ([command isEqualToString:@"reset"]) {
        [settings resetControlTransform];
    } else if ([command isEqualToString:@"up"]) {
        settings.controlOffsetY -= 20;
        [settings save];
    } else if ([command isEqualToString:@"down"]) {
        settings.controlOffsetY += 20;
        [settings save];
    } else if ([command isEqualToString:@"left"]) {
        settings.controlOffsetX -= 20;
        [settings save];
    } else if ([command isEqualToString:@"right"]) {
        settings.controlOffsetX += 20;
        [settings save];
    } else if ([command isEqualToString:@"rotate"]) {
        settings.rotationDegrees = (settings.rotationDegrees + 90) % 360;
        [settings save];
    } else if ([command isEqualToString:@"zoomin"]) {
        settings.zoom = MIN(settings.zoom + 0.1, 5.0);
        [settings save];
        [_controlPanel updateZoomValue:settings.zoom];
    } else if ([command isEqualToString:@"zoomout"]) {
        settings.zoom = MAX(settings.zoom - 0.1, 0.1);
        [settings save];
        [_controlPanel updateZoomValue:settings.zoom];
    } else if ([command isEqualToString:@"flip"]) {
        settings.horizontalFlip = !settings.horizontalFlip;
        [settings save];
    } else if ([command isEqualToString:@"colorsync_on"]) {
        settings.colorSyncEnabled = YES;
        [settings save];
    } else if ([command isEqualToString:@"colorsync_off"]) {
        settings.colorSyncEnabled = NO;
        [settings save];
    }
    
    // Notify camera daemon
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.vcam.state.changed"),
        NULL, NULL, YES
    );
}

- (void)updateVisibility {
    if (_lockScreenActive) {
        _overlayWindow.hidden = YES;
    } else if (_enabled) {
        _overlayWindow.hidden = NO;
    }
}

- (void)clearOverlay {
    [_floatingButton removeFromSuperview];
    [_controlPanel removeFromSuperview];
    _overlayWindow.hidden = YES;
    _overlayWindow = nil;
    _overlayController = nil;
    _floatingButton = nil;
    _controlPanel = nil;
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self,
        CFSTR("com.vcam.state.changed"),
        NULL
    );
    // FIX: also remove status changed observer added in init
    CFNotificationCenterRemoveObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self,
        CFSTR("com.vcam.camera.status.changed"),
        NULL
    );
}

@end

#pragma mark - Constructor (SpringBoard injection)

__attribute__((constructor))
static void vcamOverlayInit(void) {
    const char *process = getprogname();
    if (strcmp(process, "SpringBoard") != 0) return;
    
    os_log_t log = os_log_create("com.vcam.mch", "init");
    os_log(log, "Vcam_Mch overlay loading in SpringBoard");
    
    // SpringBoard scenes take time to become active. Observe scene activation.
    [[NSNotificationCenter defaultCenter] addObserverForName:@"UISceneDidActivateNotification"
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [[VCamOverlayManager shared] setEnabled:YES inWindow:nil];
        });
    }];
    
    // Fallback if already active
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{
        [[VCamOverlayManager shared] setEnabled:YES inWindow:nil];
    });
}
