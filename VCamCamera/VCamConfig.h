#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

@interface VCamConfig : NSObject

@property (nonatomic, assign) BOOL injectionEnabled;
@property (nonatomic, assign) BOOL linkEnabled;
@property (nonatomic, assign) NSInteger linkMode;
@property (nonatomic, assign) BOOL colorSyncEnabled;
@property (nonatomic, assign) CGFloat colorSyncRed;
@property (nonatomic, assign) CGFloat colorSyncGreen;
@property (nonatomic, assign) CGFloat colorSyncBlue;
@property (nonatomic, assign) NSInteger colorSyncRegion;
@property (nonatomic, assign) NSInteger selectedMediaKind;
@property (nonatomic, copy) NSString *selectedMediaPath;
@property (nonatomic, assign) NSInteger rotationDegrees;
@property (nonatomic, assign) BOOL horizontalFlip;
@property (nonatomic, assign) CGFloat zoom;
@property (nonatomic, assign) CGFloat controlOffsetX;
@property (nonatomic, assign) CGFloat controlOffsetY;
@property (nonatomic, assign) NSInteger deviceOrientation;
@property (nonatomic, assign) BOOL directMediaEnabled;

+ (instancetype)sharedConfig;

/// Reload config from plist.
- (void)reloadFromDisk;

/// Update hook status plist.
- (void)updateStatus:(NSDictionary *)statusDict;

@end
