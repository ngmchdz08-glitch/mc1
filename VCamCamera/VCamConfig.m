#import "VCamConfig.h"
#import "VCamRenderer.h"
#import <CoreFoundation/CoreFoundation.h>
#import <os/log.h>

static os_log_t configLog;

static NSString *const kConfigSubpath = @"var/mobile/Library/VCam/CameraConfig.plist";
static NSString *const kStatusSubpath = @"var/mobile/Library/VCam/CameraStatus.plist";
static NSString *const kNotifyStateChanged  = @"com.vcam.state.changed";
static NSString *const kNotifyStatusChanged = @"com.vcam.camera.status.changed";

static NSString *vcamGetRootlessPath(NSString *subpath) {
    NSString *jbPath = [@"/var/jb" stringByAppendingPathComponent:subpath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:jbPath]) {
        return jbPath;
    }
    return [@"/" stringByAppendingPathComponent:subpath];
}


static void vcamConfigChangedCallback(CFNotificationCenterRef center,
                                       void *observer,
                                       CFNotificationName name,
                                       const void *object,
                                       CFDictionaryRef userInfo) {
    VCamConfig *config = (__bridge VCamConfig *)observer;
    [config reloadFromDisk];
    [[VCamRenderer sharedRenderer] reloadConfiguration];
}


@implementation VCamConfig

+ (instancetype)sharedConfig {
    static VCamConfig *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCamConfig alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        configLog = os_log_create("com.vcam.mch", "config");
        
        // Defaults
        _injectionEnabled = YES;
        _zoom = 1.0;
        _colorSyncRed = 1.0;
        _colorSyncGreen = 1.0;
        _colorSyncBlue = 1.0;
        
        // Load config
        [self reloadFromDisk];
        
        // Register for Darwin notification
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self,
            vcamConfigChangedCallback,
            (__bridge CFStringRef)kNotifyStateChanged,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );
        
        os_log(configLog, "Config loaded — injection=%{public}s media=%{public}@",
               _injectionEnabled ? "YES" : "NO", _selectedMediaPath ?: @"(none)");
    }
    return self;
}

- (void)reloadFromDisk {
    NSString *configPath = vcamGetRootlessPath(kConfigSubpath);
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:configPath];
    if (!config) return;

    
    _injectionEnabled = YES; // Always enabled — no license check
    
    _linkMode = [config[@"linkMode"] integerValue];
    _linkEnabled = [config[@"linkEnabled"] boolValue];
    _colorSyncEnabled = [config[@"colorSyncEnabled"] boolValue];
    _colorSyncRed = config[@"colorSyncRed"] ? [config[@"colorSyncRed"] doubleValue] : 1.0;
    _colorSyncGreen = config[@"colorSyncGreen"] ? [config[@"colorSyncGreen"] doubleValue] : 1.0;
    _colorSyncBlue = config[@"colorSyncBlue"] ? [config[@"colorSyncBlue"] doubleValue] : 1.0;
    _colorSyncRegion = [config[@"colorSyncRegion"] integerValue];
    _selectedMediaKind = [config[@"selectedMediaKind"] integerValue];
    _selectedMediaPath = config[@"selectedMediaPath"];
    if (!_selectedMediaPath || ![[NSFileManager defaultManager] fileExistsAtPath:_selectedMediaPath]) {
        // Fallback default media path
        _selectedMediaPath = @"/var/jb/var/mobile/Library/VCam/Media/default.mp4";
        if (![[NSFileManager defaultManager] fileExistsAtPath:_selectedMediaPath]) {
            _selectedMediaPath = @"/var/mobile/Library/VCam/Media/default.mp4";
        }
    }

    _rotationDegrees = [config[@"rotationDegrees"] integerValue];
    _horizontalFlip = [config[@"horizontalFlip"] boolValue];
    _zoom = config[@"zoom"] ? [config[@"zoom"] doubleValue] : 1.0;
    _controlOffsetX = [config[@"controlOffsetX"] doubleValue];
    _controlOffsetY = [config[@"controlOffsetY"] doubleValue];
    _deviceOrientation = [config[@"deviceOrientation"] integerValue];
    _directMediaEnabled = [config[@"directMediaEnabled"] boolValue];
    
    os_log(configLog, "Config reloaded — media=%{public}@ kind=%ld zoom=%.2f",
           _selectedMediaPath ?: @"(none)", (long)_selectedMediaKind, (double)_zoom);
}

- (void)updateStatus:(NSDictionary *)statusDict {
    // Merge with base info
    NSMutableDictionary *status = [statusDict mutableCopy];
    
    NSProcessInfo *procInfo = [NSProcessInfo processInfo];
    status[@"process"] = procInfo.processName;
    status[@"updatedAt"] = @([[NSDate date] timeIntervalSince1970]);
    status[@"linkMode"] = @(_linkMode);
    status[@"linkEnabled"] = @(_linkEnabled);
    status[@"selectedMediaKind"] = @(_selectedMediaKind);
    status[@"directMediaEnabled"] = @(_directMediaEnabled);
    
    // Write to dynamic rootless path
    NSString *statusPath = vcamGetRootlessPath(kStatusSubpath);
    NSString *dir = [statusPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    [status writeToFile:statusPath atomically:YES];
    
    // Notify overlay
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)kNotifyStatusChanged,
        NULL, NULL, YES
    );
}

- (void)dealloc {
    CFNotificationCenterRemoveObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self,
        (__bridge CFStringRef)kNotifyStateChanged,
        NULL
    );
}

@end
