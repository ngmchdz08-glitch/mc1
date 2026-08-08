#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface VCamControlPanel : UIView

@property (nonatomic, copy)   void (^commandHandler)(NSString *command);
@property (nonatomic, strong) UILabel *zoomLabel;

- (void)updatePanelFrame;
- (void)updateZoomValue:(CGFloat)zoom;
- (void)updateStatus:(NSString *)message active:(BOOL)active;

@end
