#import "VCamVideoReader.h"
#import <os/log.h>

static os_log_t videoLog;

@implementation VCamVideoReader

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        videoLog = os_log_create("com.vcam.mch", "video");
        _path = [path copy];
        _frameSequence = 0;
        _firstPTS = kCMTimeInvalid;
        _cycleStartedAt = 0;
        [self setupReader];
    }
    return self;
}

- (void)setupReader {
    NSURL *url = [NSURL fileURLWithPath:_path];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{
        AVURLAssetPreferPreciseDurationAndTimingKey: @YES
    }];
    
    NSArray *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (videoTracks.count == 0) {
        os_log_error(videoLog, "No video tracks in %{public}@", _path);
        return;
    }
    
    AVAssetTrack *track = videoTracks.firstObject;
    _preferredTransform = track.preferredTransform;
    
    NSError *error = nil;
    _reader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
    if (error) {
        os_log_error(videoLog, "AVAssetReader error: %{public}@", error);
        return;
    }
    
    NSDictionary *outputSettings = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
    };
    
    _trackOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:track
                                                    outputSettings:outputSettings];
    _trackOutput.alwaysCopiesSampleData = NO;
    
    if ([_reader canAddOutput:_trackOutput]) {
        [_reader addOutput:_trackOutput];
    }
    
    [_reader startReading];
    _cycleStartedAt = CFAbsoluteTimeGetCurrent();
    _firstPTS = kCMTimeInvalid;
}

- (CIImage *)nextFrame {
    if (!_reader || _reader.status != AVAssetReaderStatusReading) {
        // Loop: restart reader
        [self resetReader];
        if (!_reader) return nil;
    }
    
    CMSampleBufferRef sampleBuffer = [_trackOutput copyNextSampleBuffer];
    if (!sampleBuffer) {
        // End of video — loop
        [self resetReader];
        sampleBuffer = [_trackOutput copyNextSampleBuffer];
        if (!sampleBuffer) return nil;
    }
    
    // Track PTS for sync
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    if (CMTIME_IS_INVALID(_firstPTS)) {
        _firstPTS = pts;
    }
    
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) {
        CFRelease(sampleBuffer);
        return nil;
    }
    
    CIImage *image = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    
    // Apply video's preferred transform (orientation)
    if (!CGAffineTransformIsIdentity(_preferredTransform)) {
        image = [image imageByApplyingTransform:_preferredTransform];
    }
    
    _frameSequence++;
    
    // Release current, store new
    if (_currentSample) CFRelease(_currentSample);
    _currentSample = sampleBuffer;
    
    return image;
}

- (void)resetReader {
    if (_reader) {
        [_reader cancelReading];
    }
    if (_currentSample) {
        CFRelease(_currentSample);
        _currentSample = NULL;
    }
    if (_pendingSample) {
        CFRelease(_pendingSample);
        _pendingSample = NULL;
    }
    
    _frameSequence = 0;
    [self setupReader];
}

- (void)dealloc {
    if (_currentSample) CFRelease(_currentSample);
    if (_pendingSample) CFRelease(_pendingSample);
    if (_reader) [_reader cancelReading];
}

@end
