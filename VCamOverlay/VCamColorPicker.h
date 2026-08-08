#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface VCamColorPicker : NSObject

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL lockScreenActive;
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIView *previewRing;
@property (nonatomic, strong) dispatch_queue_t sampleQueue;
@property (nonatomic, strong) dispatch_source_t sampleTimer;
@property (nonatomic, assign) CGPoint samplePoint;
@property (nonatomic, assign) CGFloat lastRed;
@property (nonatomic, assign) CGFloat lastGreen;
@property (nonatomic, assign) CGFloat lastBlue;

+ (instancetype)shared;
- (void)showPicker;
- (void)updateColorPickerPointX:(CGFloat)x y:(CGFloat)y;
- (void)updateColorSyncRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b;

@end
