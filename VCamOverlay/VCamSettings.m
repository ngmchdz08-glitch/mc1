#import "VCamSettings.h"
#import <CoreFoundation/CoreFoundation.h>

static NSString *const kSuiteName = @"com.vcam.shared";
static NSString *const kConfigPath = @"/var/jb/var/mobile/Library/VCam/CameraConfig.plist";

@implementation VCamSettings {
    NSUserDefaults *_storage;
}

+ (instancetype)shared {
    static VCamSettings *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCamSettings alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _storage = [[NSUserDefaults alloc] initWithSuiteName:kSuiteName];
        
        // Register defaults
        [_storage registerDefaults:@{
            @"linkMode": @0,
            @"linkEnabled": @NO,
            @"colorSyncEnabled": @NO,
            @"colorSyncRed": @1.0,
            @"colorSyncGreen": @1.0,
            @"colorSyncBlue": @1.0,
            @"colorSyncRegion": @0,
            @"floatingControlEnabled": @YES,
            @"directMediaEnabled": @NO,
            @"zoom": @1.0,
            @"rotationDegrees": @0,
            @"horizontalFlip": @NO,
            @"controlOffsetX": @0.0,
            @"controlOffsetY": @0.0,
            @"deviceOrientation": @1
        }];
        
        [self reload];
    }
    return self;
}

- (void)reload {
    _linkMode = [_storage integerForKey:@"linkMode"];
    _linkEnabled = [_storage boolForKey:@"linkEnabled"];
    _colorSyncEnabled = [_storage boolForKey:@"colorSyncEnabled"];
    _colorSyncRed = [_storage doubleForKey:@"colorSyncRed"];
    _colorSyncGreen = [_storage doubleForKey:@"colorSyncGreen"];
    _colorSyncBlue = [_storage doubleForKey:@"colorSyncBlue"];
    _colorSyncRegion = [_storage integerForKey:@"colorSyncRegion"];
    _colorPickerPointX = [_storage doubleForKey:@"colorPickerPointX"];
    _colorPickerPointY = [_storage doubleForKey:@"colorPickerPointY"];
    _floatingControlEnabled = [_storage boolForKey:@"floatingControlEnabled"];
    _directMediaEnabled = [_storage boolForKey:@"directMediaEnabled"];
    _selectedMediaName = [_storage stringForKey:@"selectedMediaName"];
    _selectedMediaPath = [_storage stringForKey:@"selectedMediaPath"];
    _selectedMediaKind = [_storage integerForKey:@"selectedMediaKind"];
    _controlOffsetX = [_storage doubleForKey:@"controlOffsetX"];
    _controlOffsetY = [_storage doubleForKey:@"controlOffsetY"];
    _rotationDegrees = [_storage integerForKey:@"rotationDegrees"];
    _horizontalFlip = [_storage boolForKey:@"horizontalFlip"];
    _deviceOrientation = [_storage integerForKey:@"deviceOrientation"];
    _zoom = [_storage doubleForKey:@"zoom"];
    
    if (_zoom < 0.1) _zoom = 1.0;
}

- (void)save {
    [_storage setInteger:_linkMode forKey:@"linkMode"];
    [_storage setBool:_linkEnabled forKey:@"linkEnabled"];
    [_storage setBool:_colorSyncEnabled forKey:@"colorSyncEnabled"];
    [_storage setDouble:_colorSyncRed forKey:@"colorSyncRed"];
    [_storage setDouble:_colorSyncGreen forKey:@"colorSyncGreen"];
    [_storage setDouble:_colorSyncBlue forKey:@"colorSyncBlue"];
    [_storage setInteger:_colorSyncRegion forKey:@"colorSyncRegion"];
    [_storage setDouble:_colorPickerPointX forKey:@"colorPickerPointX"];
    [_storage setDouble:_colorPickerPointY forKey:@"colorPickerPointY"];
    [_storage setBool:_floatingControlEnabled forKey:@"floatingControlEnabled"];
    [_storage setBool:_directMediaEnabled forKey:@"directMediaEnabled"];
    if (_selectedMediaName) [_storage setObject:_selectedMediaName forKey:@"selectedMediaName"];
    if (_selectedMediaPath) [_storage setObject:_selectedMediaPath forKey:@"selectedMediaPath"];
    [_storage setInteger:_selectedMediaKind forKey:@"selectedMediaKind"];
    [_storage setDouble:_controlOffsetX forKey:@"controlOffsetX"];
    [_storage setDouble:_controlOffsetY forKey:@"controlOffsetY"];
    [_storage setInteger:_rotationDegrees forKey:@"rotationDegrees"];
    [_storage setBool:_horizontalFlip forKey:@"horizontalFlip"];
    [_storage setInteger:_deviceOrientation forKey:@"deviceOrientation"];
    [_storage setDouble:_zoom forKey:@"zoom"];
    [_storage synchronize];
    
    // Also write to plist for camera daemon
    [self writeToPlist];
}

- (void)writeToPlist {
    NSMutableDictionary *dict = [NSMutableDictionary new];
    
    dict[@"linkMode"] = @(_linkMode);
    dict[@"linkEnabled"] = @(_linkEnabled);
    dict[@"colorSyncEnabled"] = @(_colorSyncEnabled);
    dict[@"colorSyncRed"] = @(_colorSyncRed);
    dict[@"colorSyncGreen"] = @(_colorSyncGreen);
    dict[@"colorSyncBlue"] = @(_colorSyncBlue);
    dict[@"colorSyncRegion"] = @(_colorSyncRegion);
    dict[@"floatingControlEnabled"] = @(_floatingControlEnabled);
    dict[@"directMediaEnabled"] = @(_directMediaEnabled);
    if (_selectedMediaName) dict[@"selectedMediaName"] = _selectedMediaName;
    if (_selectedMediaPath) dict[@"selectedMediaPath"] = _selectedMediaPath;
    dict[@"selectedMediaKind"] = @(_selectedMediaKind);
    dict[@"controlOffsetX"] = @(_controlOffsetX);
    dict[@"controlOffsetY"] = @(_controlOffsetY);
    dict[@"rotationDegrees"] = @(_rotationDegrees);
    dict[@"horizontalFlip"] = @(_horizontalFlip);
    dict[@"deviceOrientation"] = @(_deviceOrientation);
    dict[@"zoom"] = @(_zoom);
    
    NSArray *paths = @[
        @"/var/jb/var/mobile/Library/VCam/CameraConfig.plist",
        @"/var/mobile/Library/VCam/CameraConfig.plist"
    ];
    
    for (NSString *path in paths) {
        NSString *dir = [path stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        [dict writeToFile:path atomically:YES];
    }
}

- (void)resetControlTransform {
    _zoom = 1.0;
    _rotationDegrees = 0;
    _horizontalFlip = NO;
    _controlOffsetX = 0;
    _controlOffsetY = 0;
    [self save];
}

@end
