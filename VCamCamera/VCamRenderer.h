#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CoreImage.h>
#import <VideoToolbox/VideoToolbox.h>
#import <Vision/Vision.h>

typedef struct OpaqueVTPixelTransferSession* VTPixelTransferSessionRef;

@class VCamVideoReader;
@class VCamLANStream;

@interface VCamRenderer : NSObject

@property (nonatomic, assign) BOOL injectionEnabled;
@property (nonatomic, strong) dispatch_queue_t renderQueue;
@property (nonatomic, strong) CIContext *ciContext;
@property (nonatomic, strong) NSLock *stateLock;

// Cached media
@property (nonatomic, strong) CIImage *cachedStillImage;
@property (nonatomic, copy) NSString *cachedStillImageStamp;
@property (nonatomic, strong) VCamVideoReader *videoReader;
@property (nonatomic, strong) VCamLANStream *lanStream;

// Pixel transfer
@property (nonatomic, assign) VTPixelTransferSessionRef transferSession;

// Face tracking
@property (nonatomic, assign) BOOL hasTrackedFace;
@property (nonatomic, assign) CGRect lastFaceBounds;
@property (nonatomic, assign) NSTimeInterval lastFaceDetection;
@property (nonatomic, assign) NSTimeInterval lastFaceSeen;

// Ready frames cache
@property (nonatomic, strong) NSMutableDictionary *readyFrames;

+ (instancetype)sharedRenderer;

/// Main entry: replace a camera sample buffer with virtual content.
/// Returns a new retained CMSampleBufferRef, or NULL if replacement failed.
- (CMSampleBufferRef)renderReplacementForSampleBuffer:(CMSampleBufferRef)originalBuffer
                                              purpose:(NSInteger)purpose;

/// Reload configuration from disk.
- (void)reloadConfiguration;

@end
