#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "VCamSettings.h"

@class VCamControlPanel;
@class VCamColorPicker;

@interface VCamOverlayManager : NSObject

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL lockScreenActive;
@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, strong) UIViewController *overlayController;
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, strong) VCamControlPanel *controlPanel;
@property (nonatomic, strong) VCamColorPicker *colorPicker;
@property (nonatomic, weak) UIWindow *hostWindow;

+ (instancetype)shared;

- (void)setEnabled:(BOOL)enabled inWindow:(UIWindow *)window;
- (void)updateVisibility;

@end
