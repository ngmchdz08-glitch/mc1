#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <objc/runtime.h>
#import <os/log.h>

@class VCamRenderer;

// Forward declarations for private Apple classes in cameracaptured
@interface NSObject (BWPipelineNode)
- (void)renderSampleBuffer:(CMSampleBufferRef)sampleBuffer forInput:(NSInteger)input;
- (void)emitSampleBuffer:(CMSampleBufferRef)sampleBuffer;
@end

/// Installs hooks on BW* camera pipeline classes.
/// Also scans all loaded classes for dynamic subclasses.
/// Should be called at constructor time and retried via timer.
void VCamInstallHooks(void);
