#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface VCamSettings : NSObject

// Link
@property (nonatomic, assign) NSInteger linkMode;
@property (nonatomic, assign) BOOL linkEnabled;

// Color sync
@property (nonatomic, assign) BOOL colorSyncEnabled;
@property (nonatomic, assign) CGFloat colorSyncRed;
@property (nonatomic, assign) CGFloat colorSyncGreen;
@property (nonatomic, assign) CGFloat colorSyncBlue;
@property (nonatomic, assign) NSInteger colorSyncRegion;
@property (nonatomic, assign) CGFloat colorPickerPointX;
@property (nonatomic, assign) CGFloat colorPickerPointY;

// Floating control
@property (nonatomic, assign) BOOL floatingControlEnabled;

// Media
@property (nonatomic, assign) BOOL directMediaEnabled;
@property (nonatomic, copy) NSString *selectedMediaName;
@property (nonatomic, copy) NSString *selectedMediaPath;
@property (nonatomic, assign) NSInteger selectedMediaKind;

// Transform
@property (nonatomic, assign) CGFloat controlOffsetX;
@property (nonatomic, assign) CGFloat controlOffsetY;
@property (nonatomic, assign) NSInteger rotationDegrees;
@property (nonatomic, assign) BOOL horizontalFlip;
@property (nonatomic, assign) NSInteger deviceOrientation;
@property (nonatomic, assign) CGFloat zoom;

+ (instancetype)shared;

- (void)reload;
- (void)save;
- (void)resetControlTransform;

@end
