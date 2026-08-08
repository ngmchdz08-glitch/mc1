#import "VCamRenderer.h"
#import "VCamConfig.h"
#import "VCamVideoReader.h"
#import "VCamLANStream.h"
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CoreImage.h>
#import <VideoToolbox/VideoToolbox.h>
#import <Vision/Vision.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <os/log.h>

// Private VideoToolbox functions not in public SDK headers
extern OSStatus VTPixelTransferSessionCreate(CFAllocatorRef allocator, VTPixelTransferSessionRef *pixelTransferSessionOut);
extern OSStatus VTPixelTransferSessionTransferImage(VTPixelTransferSessionRef session, CVPixelBufferRef sourceBuffer, CVPixelBufferRef destinationBuffer);
extern void VTPixelTransferSessionInvalidate(VTPixelTransferSessionRef session);

static os_log_t rendererLog;

@implementation VCamRenderer

+ (instancetype)sharedRenderer {
    static VCamRenderer *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VCamRenderer alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        rendererLog = os_log_create("com.vcam.mch", "renderer");
        _renderQueue = dispatch_queue_create("com.vcam.mch.renderer", DISPATCH_QUEUE_SERIAL);
        _ciContext = [CIContext contextWithOptions:@{
            kCIContextUseSoftwareRenderer: @NO,
            kCIContextHighQualityDownsample: @YES
        }];
        _stateLock = [[NSLock alloc] init];
        _readyFrames = [NSMutableDictionary new];
        _injectionEnabled = YES;
        
        // Create pixel transfer session
        VTPixelTransferSessionCreate(kCFAllocatorDefault, &_transferSession);
        if (_transferSession) {
            VTSessionSetProperty(_transferSession,
                                 kVTPixelTransferPropertyKey_ScalingMode,
                                 kVTScalingMode_Trim);
        }
    }
    return self;
}

#pragma mark - Main Render Entry

- (CMSampleBufferRef)renderReplacementForSampleBuffer:(CMSampleBufferRef)originalBuffer
                                              purpose:(NSInteger)purpose {
    if (!originalBuffer) return NULL;
    
    VCamConfig *config = [VCamConfig sharedConfig];
    if (!config.injectionEnabled) return NULL;
    
    // Get original buffer info
    CVPixelBufferRef originalPixelBuffer = CMSampleBufferGetImageBuffer(originalBuffer);
    if (!originalPixelBuffer) return NULL;
    
    size_t width = CVPixelBufferGetWidth(originalPixelBuffer);
    size_t height = CVPixelBufferGetHeight(originalPixelBuffer);
    OSType pixelFormat = CVPixelBufferGetPixelFormatType(originalPixelBuffer);
    
    // Get virtual image
    CIImage *virtualImage = [self loadVirtualImageForConfig:config];
    if (!virtualImage) return NULL;
    
    // Apply transforms
    virtualImage = [self applyTransforms:virtualImage
                                  config:config
                             targetWidth:width
                            targetHeight:height];
    
    // Apply color sync if enabled
    if (config.colorSyncEnabled) {
        virtualImage = [self applyColorSync:virtualImage config:config targetWidth:width targetHeight:height];
    }
    
    // Create output pixel buffer (always BGRA for CIContext rendering)
    CVPixelBufferRef outputPixelBuffer = NULL;
    NSDictionary *bgraAttrs = @{
        (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
    };
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          width, height,
                                          kCVPixelFormatType_32BGRA,
                                          (__bridge CFDictionaryRef)bgraAttrs,
                                          &outputPixelBuffer);
    if (status != kCVReturnSuccess || !outputPixelBuffer) return NULL;
    
    // Render CIImage into pixel buffer
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    [_ciContext render:virtualImage
       toCVPixelBuffer:outputPixelBuffer
                bounds:CGRectMake(0, 0, width, height)
            colorSpace:colorSpace];
    CGColorSpaceRelease(colorSpace);
    
    // If original format != BGRA, use VTPixelTransfer to convert
    CVPixelBufferRef finalPixelBuffer = outputPixelBuffer;
    if (pixelFormat != kCVPixelFormatType_32BGRA && _transferSession) {
        // FIX: Create target buffer with CORRECT format attrs — do NOT reuse bgraAttrs
        NSDictionary *targetAttrs = @{
            (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
            (id)kCVPixelBufferPixelFormatTypeKey: @(pixelFormat)
        };
        CVPixelBufferRef convertedBuffer = NULL;
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, pixelFormat,
                            (__bridge CFDictionaryRef)targetAttrs, &convertedBuffer);
        if (convertedBuffer) {
            OSStatus transferStatus = VTPixelTransferSessionTransferImage(
                _transferSession, outputPixelBuffer, convertedBuffer);
            if (transferStatus == noErr) {
                finalPixelBuffer = convertedBuffer;
                CVPixelBufferRelease(outputPixelBuffer);
            } else {
                CVPixelBufferRelease(convertedBuffer);
                // If transfer failed, just use BGRA — better than nothing
            }
        }
    }
    
    // Copy attachments from original buffer for anti-detection
    [self copyAttachmentsFromBuffer:originalPixelBuffer toBuffer:finalPixelBuffer];
    
    // Build new CMSampleBuffer with original timing
    CMSampleBufferRef newSampleBuffer = [self createSampleBufferFromPixelBuffer:finalPixelBuffer
                                                             originalBuffer:originalBuffer];
    
    CVPixelBufferRelease(finalPixelBuffer);
    
    return newSampleBuffer;
}

#pragma mark - Virtual Image Loading

- (CIImage *)loadVirtualImageForConfig:(VCamConfig *)config {
    NSString *mediaPath = config.selectedMediaPath;
    NSInteger mediaKind = config.selectedMediaKind;
    
    [_stateLock lock];
    CIImage *result = nil;
    
    // Check for LAN stream
    if (config.directMediaEnabled) {
        if (!_lanStream) {
            _lanStream = [[VCamLANStream alloc] init];
        }
        // FIX: Must call poll to read new data from stream file before getting frame
        [_lanStream poll];
        CVPixelBufferRef lanFrame = [_lanStream latestPixelBuffer];
        if (lanFrame) {
            result = [CIImage imageWithCVPixelBuffer:lanFrame];
        }
    }
    // Video
    else if (mediaKind == 1 && mediaPath && mediaPath.length > 0) {
        result = [self loadVideoFrame:mediaPath];
    }
    // Still image
    else if (mediaPath && mediaPath.length > 0) {
        result = [self loadStillImage:mediaPath];
    }
    
    // Fallback placeholder image if no media was loaded or file is missing
    if (!result) {
        result = [CIImage imageWithColor:[CIColor colorWithRed:0.05 green:0.05 blue:0.15 alpha:1.0]];
    }
    
    [_stateLock unlock];
    return result;
}

- (CIImage *)loadStillImage:(NSString *)path {
    // Check cache
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:nil];
    NSString *stamp = [NSString stringWithFormat:@"%@|%@",
                       attrs[NSFileSize], attrs[NSFileModificationDate]];
    
    if (_cachedStillImage && [_cachedStillImageStamp isEqualToString:stamp]) {
        return _cachedStillImage;
    }
    
    NSURL *url = [NSURL fileURLWithPath:path];
    CIImage *image = [CIImage imageWithContentsOfURL:url options:@{
        kCIImageApplyOrientationProperty: @YES
    }];
    
    if (image) {
        _cachedStillImage = image;
        _cachedStillImageStamp = stamp;
    }
    
    return image;
}

- (CIImage *)loadVideoFrame:(NSString *)path {
    if (!_videoReader) {
        _videoReader = [[VCamVideoReader alloc] initWithPath:path];
    }
    
    // Check if path changed
    if (![_videoReader.path isEqualToString:path]) {
        _videoReader = [[VCamVideoReader alloc] initWithPath:path];
    }
    
    CIImage *frame = [_videoReader nextFrame];
    return frame;
}

#pragma mark - Transform Pipeline

- (CIImage *)applyTransforms:(CIImage *)image
                       config:(VCamConfig *)config
                  targetWidth:(size_t)targetWidth
                 targetHeight:(size_t)targetHeight {
    CGRect extent = image.extent;
    if (CGRectIsEmpty(extent) || CGRectIsNull(extent)) return image;
    
    CGFloat imageW = extent.size.width;
    CGFloat imageH = extent.size.height;
    CGFloat targetW = (CGFloat)targetWidth;
    CGFloat targetH = (CGFloat)targetHeight;
    
    // Scale to fill target
    CGFloat scaleX = targetW / imageW;
    CGFloat scaleY = targetH / imageH;
    CGFloat scale = MAX(scaleX, scaleY);
    
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    // Center the image
    CGFloat scaledW = imageW * scale;
    CGFloat scaledH = imageH * scale;
    CGFloat offsetX = (targetW - scaledW) / 2.0;
    CGFloat offsetY = (targetH - scaledH) / 2.0;
    
    transform = CGAffineTransformMakeTranslation(offsetX, offsetY);
    transform = CGAffineTransformScale(transform, scale, scale);
    
    image = [image imageByApplyingTransform:transform];
    
    // Apply rotation
    NSInteger rotationDegrees = config.rotationDegrees;
    if (rotationDegrees != 0) {
        CGFloat radians = rotationDegrees * M_PI / 180.0;
        CGFloat cx = targetW / 2.0;
        CGFloat cy = targetH / 2.0;
        
        CGAffineTransform rot = CGAffineTransformIdentity;
        rot = CGAffineTransformTranslate(rot, cx, cy);
        rot = CGAffineTransformRotate(rot, radians);
        rot = CGAffineTransformTranslate(rot, -cx, -cy);
        
        image = [image imageByApplyingTransform:rot];
    }
    
    // Apply horizontal flip
    if (config.horizontalFlip) {
        CGAffineTransform flip = CGAffineTransformMakeTranslation(targetW, 0);
        flip = CGAffineTransformScale(flip, -1.0, 1.0);
        image = [image imageByApplyingTransform:flip];
    }
    
    // Apply zoom
    CGFloat zoom = config.zoom;
    if (zoom > 1.001 || zoom < 0.999) {
        CGFloat cx = targetW / 2.0;
        CGFloat cy = targetH / 2.0;
        
        CGAffineTransform z = CGAffineTransformIdentity;
        z = CGAffineTransformTranslate(z, cx, cy);
        z = CGAffineTransformScale(z, zoom, zoom);
        z = CGAffineTransformTranslate(z, -cx, -cy);
        
        image = [image imageByApplyingTransform:z];
    }
    
    // Apply control offset
    CGFloat ctrlOffX = config.controlOffsetX;
    CGFloat ctrlOffY = config.controlOffsetY;
    if (ctrlOffX != 0 || ctrlOffY != 0) {
        image = [image imageByApplyingTransform:CGAffineTransformMakeTranslation(ctrlOffX, ctrlOffY)];
    }
    
    // Crop to target rect
    image = [image imageByCroppingToRect:CGRectMake(0, 0, targetW, targetH)];
    
    return image;
}

#pragma mark - Color Sync

- (CIImage *)applyColorSync:(CIImage *)image config:(VCamConfig *)config
                targetWidth:(size_t)width targetHeight:(size_t)height {
    CGFloat r = config.colorSyncRed;
    CGFloat g = config.colorSyncGreen;
    CGFloat b = config.colorSyncBlue;
    NSInteger region = config.colorSyncRegion;
    
    // Create color overlay
    CIColor *syncColor = [CIColor colorWithRed:r green:g blue:b alpha:1.0];
    CIImage *colorImage = [CIImage imageWithColor:syncColor];
    colorImage = [colorImage imageByCroppingToRect:CGRectMake(0, 0, width, height)];
    
    // Apply soft light blend
    CIImage *blended = [image imageByApplyingFilter:@"CISoftLightBlendMode"
                                withInputParameters:@{
        kCIInputBackgroundImageKey: colorImage
    }];
    
    // Apply region mask if needed
    if (region > 0) {
        CIImage *blurred = [image imageByApplyingFilter:@"CIGaussianBlur"
                                    withInputParameters:@{
            kCIInputRadiusKey: @(20.0)
        }];
        blurred = [blurred imageByClampingToExtent];
        
        blended = [blended imageByApplyingFilter:@"CIBlendWithMask"
                             withInputParameters:@{
            kCIInputBackgroundImageKey: image,
            kCIInputMaskImageKey: blurred
        }];
    }
    
    return blended;
}

#pragma mark - Face Detection

- (void)detectFaceInImage:(CIImage *)image {
    NSTimeInterval now = CFAbsoluteTimeGetCurrent();
    
    // Don't detect too frequently
    if (now - _lastFaceDetection < 0.5) return;
    _lastFaceDetection = now;
    
    VNDetectFaceRectanglesRequest *request = [[VNDetectFaceRectanglesRequest alloc] init];
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCIImage:image options:@{}];
    
    NSError *error = nil;
    [handler performRequests:@[request] error:&error];
    
    if (!error && request.results.count > 0) {
        VNFaceObservation *face = request.results.firstObject;
        _lastFaceBounds = face.boundingBox;
        _hasTrackedFace = YES;
        _lastFaceSeen = now;
    } else if (now - _lastFaceSeen > 2.0) {
        _hasTrackedFace = NO;
    }
}

#pragma mark - Attachment Copy (Anti-Detection)

- (void)copyAttachmentsFromBuffer:(CVPixelBufferRef)source toBuffer:(CVPixelBufferRef)dest {
    if (!source || !dest) return;
    
    // Copy all CVBuffer attachments
    CFDictionaryRef attachments = CVBufferGetAttachments(source, kCVAttachmentMode_ShouldPropagate);
    if (attachments) {
        CVBufferSetAttachments(dest, attachments, kCVAttachmentMode_ShouldPropagate);
    }
    
    CFDictionaryRef npAttachments = CVBufferGetAttachments(source, kCVAttachmentMode_ShouldNotPropagate);
    if (npAttachments) {
        CVBufferSetAttachments(dest, npAttachments, kCVAttachmentMode_ShouldNotPropagate);
    }
    
    // Bulk copy above handles all critical attachment keys:
    // kCVImageBufferChromaLocation*, kCVImageBufferColorPrimaries*,
    // kCVImageBufferGammaLevel*, kCVImageBufferICCProfile*, kCVImageBufferPixelAspectRatio*,
    // kCVImageBufferTransferFunction*, kCVImageBufferYCbCrMatrix*, kCVImageBufferCleanAperture*
}

#pragma mark - CMSampleBuffer Construction

- (CMSampleBufferRef)createSampleBufferFromPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                        originalBuffer:(CMSampleBufferRef)originalBuffer {
    if (!pixelBuffer || !originalBuffer) return NULL;
    
    // Get timing from original
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(originalBuffer);
    CMTime duration = CMSampleBufferGetDuration(originalBuffer);
    CMTime dts = CMSampleBufferGetDecodeTimeStamp(originalBuffer);
    
    // Create format description
    CMVideoFormatDescriptionRef formatDesc = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, &formatDesc);
    if (!formatDesc) return NULL;
    
    // Create sample buffer
    CMSampleBufferRef newBuffer = NULL;
    CMSampleTimingInfo timing = {
        .duration = duration,
        .presentationTimeStamp = pts,
        .decodeTimeStamp = dts
    };
    
    OSStatus status = CMSampleBufferCreateReadyWithImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        formatDesc,
        &timing,
        &newBuffer
    );
    
    CFRelease(formatDesc);
    
    if (status != noErr) return NULL;
    
    // Copy sample-level attachments
    CFArrayRef sampleAttachments = CMSampleBufferGetSampleAttachmentsArray(originalBuffer, false);
    if (sampleAttachments && CFArrayGetCount(sampleAttachments) > 0) {
        CFArrayRef newAttachments = CMSampleBufferGetSampleAttachmentsArray(newBuffer, true);
        if (newAttachments && CFArrayGetCount(newAttachments) > 0) {
            CFMutableDictionaryRef srcDict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(sampleAttachments, 0);
            CFMutableDictionaryRef dstDict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(newAttachments, 0);
            
            // Copy kCMSampleAttachmentKey_NotSync
            CFTypeRef notSync = CFDictionaryGetValue(srcDict, kCMSampleAttachmentKey_NotSync);
            if (notSync) {
                CFDictionarySetValue(dstDict, kCMSampleAttachmentKey_NotSync, notSync);
            }
        }
    }
    
    // Copy buffer-level attachments
    CFDictionaryRef bufferAttachments = CMCopyDictionaryOfAttachments(
        kCFAllocatorDefault, originalBuffer, kCMAttachmentMode_ShouldPropagate);
    if (bufferAttachments) {
        CMSetAttachments(newBuffer, bufferAttachments, kCMAttachmentMode_ShouldPropagate);
        CFRelease(bufferAttachments);
    }
    
    return newBuffer;
}

#pragma mark - Configuration Reload

- (void)reloadConfiguration {
    [_stateLock lock];
    _cachedStillImage = nil;
    _cachedStillImageStamp = nil;
    [_readyFrames removeAllObjects];
    [_stateLock unlock];
}

- (void)dealloc {
    if (_transferSession) {
        VTPixelTransferSessionInvalidate(_transferSession);
        CFRelease(_transferSession);
    }
}

@end
