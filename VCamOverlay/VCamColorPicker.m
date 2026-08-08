#import "VCamColorPicker.h"
#import "VCamSettings.h"
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>

typedef struct __IOSurface *IOSurfaceRef;
#define kIOSurfaceLockReadOnly 1

extern IOSurfaceRef IOSurfaceCreate(CFDictionaryRef properties);
extern int IOSurfaceLock(IOSurfaceRef buffer, uint32_t options, uint32_t *seed);
extern int IOSurfaceUnlock(IOSurfaceRef buffer, uint32_t options, uint32_t *seed);
extern void *IOSurfaceGetBaseAddress(IOSurfaceRef buffer);
extern size_t IOSurfaceGetBytesPerRow(IOSurfaceRef buffer);
#import <dlfcn.h>
#import <os/log.h>

static os_log_t pickerLog;

// Private API: CARenderServerRenderDisplay
typedef void (*CARenderServerRenderDisplayFunc)(void *, CFStringRef, IOSurfaceRef, int, int, int, int, int);

@implementation VCamColorPicker {
    IOSurfaceRef _captureSurface;
    CARenderServerRenderDisplayFunc _renderDisplay;
    NSUInteger _captureWidth;
    NSUInteger _captureHeight;
    CGFloat _screenWidth;
    CGFloat _screenHeight;
}

+ (instancetype)shared {
    static VCamColorPicker *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCamColorPicker alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        pickerLog = os_log_create("com.vcam.mch", "picker");
        
        // Resolve CARenderServerRenderDisplay
        _renderDisplay = (CARenderServerRenderDisplayFunc)dlsym(RTLD_DEFAULT, "CARenderServerRenderDisplay");
        
        // Setup capture surface
        CGRect nativeBounds = [UIScreen mainScreen].nativeBounds;
        _captureWidth = (NSUInteger)nativeBounds.size.width;
        _captureHeight = (NSUInteger)nativeBounds.size.height;
        
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        _screenWidth = screenBounds.size.width;
        _screenHeight = screenBounds.size.height;
        
        NSUInteger bytesPerRow = _captureWidth * 4;
        NSUInteger allocSize = bytesPerRow * _captureHeight;
        
        NSDictionary *surfaceProps = @{
            @"IOSurfaceBytesPerRow": @(bytesPerRow),
            @"IOSurfaceWidth": @(_captureWidth),
            @"IOSurfaceHeight": @(_captureHeight),
            @"IOSurfaceBytesPerElement": @(4),
            @"IOSurfaceAllocSize": @(allocSize),
            @"IOSurfacePixelFormat": @(0x42475241)  // BGRA
        };
        
        _captureSurface = IOSurfaceCreate((__bridge CFDictionaryRef)surfaceProps);
        
        _sampleQueue = dispatch_queue_create("com.vcam.mch.colorpicker", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)showPicker {
    if (!_renderDisplay || !_captureSurface) {
        os_log_error(pickerLog, "CARenderServerRenderDisplay not available");
        return;
    }
    
    // Start sampling timer
    if (_sampleTimer) {
        dispatch_source_cancel(_sampleTimer);
    }
    
    _sampleTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _sampleQueue);
    dispatch_source_set_timer(_sampleTimer, DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC, 10 * NSEC_PER_MSEC);
    
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_sampleTimer, ^{
        [weakSelf sampleScreen];
    });
    
    dispatch_resume(_sampleTimer);
}

- (void)sampleScreen {
    if (!_renderDisplay || !_captureSurface) return;
    
    // Render screen to IOSurface
    _renderDisplay(NULL, CFSTR("com.vcam.mch.color-picker.sample"),
                   _captureSurface, 0, 0, 0, 0, 0);
    
    // Lock surface and read pixel at sample point
    IOSurfaceLock(_captureSurface, kIOSurfaceLockReadOnly, NULL);
    
    uint8_t *baseAddr = (uint8_t *)IOSurfaceGetBaseAddress(_captureSurface);
    size_t bytesPerRow = IOSurfaceGetBytesPerRow(_captureSurface);
    
    // Convert screen coords to surface coords
    CGFloat scaleX = (CGFloat)_captureWidth / _screenWidth;
    CGFloat scaleY = (CGFloat)_captureHeight / _screenHeight;
    
    NSUInteger pixelX = (NSUInteger)(_samplePoint.x * scaleX);
    NSUInteger pixelY = (NSUInteger)(_samplePoint.y * scaleY);
    
    if (pixelX < _captureWidth && pixelY < _captureHeight) {
        uint8_t *pixel = baseAddr + pixelY * bytesPerRow + pixelX * 4;
        // BGRA format
        CGFloat b = pixel[0] / 255.0;
        CGFloat g = pixel[1] / 255.0;
        CGFloat r = pixel[2] / 255.0;
        
        _lastRed = r;
        _lastGreen = g;
        _lastBlue = b;
        
        // Update settings
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateColorSyncRed:r green:g blue:b];
            [self updatePreviewRingColor];
        });
    }
    
    IOSurfaceUnlock(_captureSurface, kIOSurfaceLockReadOnly, NULL);
}

- (void)updatePreviewRingColor {
    if (_previewRing) {
        _previewRing.backgroundColor = [UIColor colorWithRed:_lastRed green:_lastGreen blue:_lastBlue alpha:1.0];
    }
}

- (void)updateColorPickerPointX:(CGFloat)x y:(CGFloat)y {
    _samplePoint = CGPointMake(x, y);
    VCamSettings *settings = [VCamSettings shared];
    settings.colorPickerPointX = x;
    settings.colorPickerPointY = y;
    [settings save];
}

- (void)updateColorSyncRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b {
    VCamSettings *settings = [VCamSettings shared];
    settings.colorSyncRed = r;
    settings.colorSyncGreen = g;
    settings.colorSyncBlue = b;
    [settings save];
    
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.vcam.state.changed"),
        NULL, NULL, YES
    );
}

- (void)dealloc {
    if (_sampleTimer) {
        dispatch_source_cancel(_sampleTimer);
    }
    if (_captureSurface) {
        CFRelease(_captureSurface);
    }
}

@end
