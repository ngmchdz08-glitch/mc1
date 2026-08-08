#import "VCamLANStream.h"
#import <os/log.h>
#import <sys/stat.h>
#import <unistd.h>
#import <fcntl.h>

static os_log_t lanLog;

// H.264 NAL unit types
#define NAL_TYPE_SPS 7
#define NAL_TYPE_PPS 8
#define NAL_TYPE_IDR 5

// Custom stream header magic
static const uint32_t kStreamHeaderMagic = 0x56434E48; // "VCNH"

#pragma mark - VTDecompressionSession callback

static void decompressionCallback(void *decompressionOutputRefCon,
                                   void *sourceFrameRefCon,
                                   OSStatus status,
                                   VTDecodeInfoFlags infoFlags,
                                   CVImageBufferRef imageBuffer,
                                   CMTime presentationTimeStamp,
                                   CMTime presentationDuration) {
    VCamLANStream *stream = (__bridge VCamLANStream *)decompressionOutputRefCon;
    
    if (status != noErr || !imageBuffer) {
        os_log_error(lanLog, "VideoToolbox output error (%d)", (int)status);
        return;
    }
    
    CVPixelBufferRetain(imageBuffer);
    
    CVPixelBufferRef old = stream.latestPixelBuffer;
    stream.latestPixelBuffer = imageBuffer;
    stream.frameSequence++;
    
    if (old) CVPixelBufferRelease(old);
    
    if (stream.frameSequence == 1) {
        stream.statusMessage = @"LAN video is live";
        os_log(lanLog, "LAN video is live");
    }
}

@implementation VCamLANStream

- (instancetype)init {
    self = [super init];
    if (self) {
        lanLog = os_log_create("com.vcam.mch", "lan");
        // Rootless path first, fallback to rootful
        _path = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/var/mobile/Library/VCam/Streams/live.vcn"]
                ? @"/var/jb/var/mobile/Library/VCam/Streams/live.vcn"
                : @"/var/mobile/Library/VCam/Streams/live.vcn";
        _descriptor = -1;
        _inode = 0;
        _readOffset = 0;
        _generation = 0;
        _nalUnitHeaderLength = 0;
        _frameSequence = 0;
        _statusMessage = @"Waiting for LAN video";
    }
    return self;
}

- (void)poll {
    // Check if file changed (inode tracking)
    struct stat st;
    if (stat(_path.fileSystemRepresentation, &st) != 0) return;
    
    if (st.st_ino != _inode) {
        // File replaced — reopen
        [self closeDescriptor];
        [self clearDecoderKeepingFrame:YES];
        _inode = st.st_ino;
        _readOffset = 0;
        _generation++;
    }
    
    if (_descriptor < 0) {
        _descriptor = open(_path.fileSystemRepresentation, O_RDONLY);
        if (_descriptor < 0) return;
        os_log(lanLog, "Opening LAN video");
    }
    
    // Read available data
    [self readAvailableData];
}

- (void)readAvailableData {
    if (_descriptor < 0) return;
    
    // Read header if at start
    if (_readOffset == 0) {
        uint8_t header[8];
        ssize_t r = pread(_descriptor, header, sizeof(header), 0);
        if (r < (ssize_t)sizeof(header)) return;
        
        uint32_t magic = *(uint32_t *)header;
        if (magic != kStreamHeaderMagic) {
            os_log_error(lanLog, "Invalid LAN stream header");
            [self closeDescriptor];
            return;
        }
        _readOffset = 8;
    }
    
    // Read packets
    while (YES) {
        // Packet header: 4 bytes size + 4 bytes flags
        uint8_t pktHeader[8];
        ssize_t r = pread(_descriptor, pktHeader, sizeof(pktHeader), _readOffset);
        if (r < (ssize_t)sizeof(pktHeader)) break;
        
        uint32_t packetSize = *(uint32_t *)pktHeader;
        uint32_t flags = *(uint32_t *)(pktHeader + 4);
        
        if (packetSize == 0 || packetSize > 4 * 1024 * 1024) {
            os_log_error(lanLog, "Invalid LAN packet header");
            break;
        }
        
        NSMutableData *packetData = [NSMutableData dataWithLength:packetSize];
        r = pread(_descriptor, packetData.mutableBytes, packetSize, _readOffset + 8);
        if (r < (ssize_t)packetSize) {
            os_log(lanLog, "Incomplete LAN packet");
            break;
        }
        
        _readOffset += 8 + packetSize;
        
        // Parse NAL unit
        const uint8_t *bytes = packetData.bytes;
        uint8_t nalType = bytes[0] & 0x1F;
        BOOL isKeyFrame = (flags & 1) != 0;
        
        if (nalType == NAL_TYPE_SPS || nalType == NAL_TYPE_PPS) {
            [self handleParameterSet:packetData nalType:nalType];
        } else {
            [self decodeNALUnit:packetData keyFrame:isKeyFrame];
        }
    }
}

- (void)handleParameterSet:(NSData *)data nalType:(uint8_t)nalType {
    // FIX: Use instance vars instead of static locals (thread-safe, multi-instance safe)
    if (nalType == NAL_TYPE_SPS) {
        _storedSPS = [data copy];
    } else if (nalType == NAL_TYPE_PPS) {
        _storedPPS = [data copy];
    }
    
    if (_storedSPS && _storedPPS) {
        // Create H.264 format description
        const uint8_t *parameterSetPointers[2] = {
            _storedSPS.bytes, _storedPPS.bytes
        };
        size_t parameterSetSizes[2] = {
            _storedSPS.length, _storedPPS.length
        };
        
        CMFormatDescriptionRef formatDesc = NULL;
        OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            kCFAllocatorDefault,
            2,
            parameterSetPointers,
            parameterSetSizes,
            4,  // NAL unit header length
            &formatDesc
        );
        
        if (status != noErr) {
            os_log_error(lanLog, "H.264 format error (%d)", (int)status);
            return;
        }
        
        _nalUnitHeaderLength = 4;
        
        // Create decompression session
        [self clearDecoderKeepingFrame:YES];
        
        VTDecompressionOutputCallbackRecord callback;
        callback.decompressionOutputCallback = decompressionCallback;
        callback.decompressionOutputRefCon = (__bridge void *)self;
        
        NSDictionary *destAttrs = @{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
        };
        
        status = VTDecompressionSessionCreate(
            kCFAllocatorDefault,
            formatDesc,
            NULL,
            (__bridge CFDictionaryRef)destAttrs,
            &callback,
            &_decompressionSession
        );
        
        if (status != noErr) {
            os_log_error(lanLog, "VideoToolbox session error (%d)", (int)status);
            CFRelease(formatDesc);
            return;
        }
        
        // FIX: Store formatDescription for use in decodeNALUnit:
        if (_formatDescription) CFRelease(_formatDescription);
        _formatDescription = (CMFormatDescriptionRef)CFRetain(formatDesc);
        CFRelease(formatDesc);
        
        VTSessionSetProperty(_decompressionSession,
                             kVTDecompressionPropertyKey_RealTime,
                             kCFBooleanTrue);
        
        os_log(lanLog, "H.264 decoder ready");
    }
}

- (void)decodeNALUnit:(NSData *)data keyFrame:(BOOL)keyFrame {
    if (!_decompressionSession || !_formatDescription) return;
    
    // Wrap NAL in CMBlockBuffer with 4-byte length prefix
    size_t nalLen = data.length;
    size_t totalSize = 4 + nalLen;
    
    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(
        kCFAllocatorDefault, NULL, totalSize,
        kCFAllocatorDefault, NULL, 0, totalSize, 0, &blockBuffer);
    if (status != noErr || !blockBuffer) return;
    
    // Write length prefix (big-endian) + NAL data
    uint32_t nalLength = htonl((uint32_t)nalLen);
    CMBlockBufferReplaceDataBytes(&nalLength, blockBuffer, 0, 4);
    CMBlockBufferReplaceDataBytes(data.bytes, blockBuffer, 4, nalLen);
    
    // FIX: Create CMSampleBuffer from blockBuffer BEFORE calling VTDecompressionSessionDecodeFrame
    CMSampleTimingInfo timing = {
        .duration               = CMTimeMake(1, 30),
        .presentationTimeStamp  = CMTimeMake((int64_t)_frameSequence, 30),
        .decodeTimeStamp        = kCMTimeInvalid
    };
    size_t sampleSize = totalSize;
    
    CMSampleBufferRef sampleBuffer = NULL;
    status = CMSampleBufferCreateReady(
        kCFAllocatorDefault,
        blockBuffer,
        _formatDescription,
        1,           // numSamples
        1,           // numSampleTimingEntries
        &timing,
        1,           // numSampleSizeEntries
        &sampleSize,
        &sampleBuffer
    );
    CFRelease(blockBuffer);
    if (status != noErr || !sampleBuffer) return;
    
    // Mark keyframe
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
    if (attachments && CFArrayGetCount(attachments) > 0) {
        CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        if (!keyFrame) {
            CFDictionarySetValue(dict, kCMSampleAttachmentKey_NotSync, kCFBooleanTrue);
        }
    }
    
    VTDecodeFrameFlags decodeFlags = kVTDecodeFrame_EnableAsynchronousDecompression;
    VTDecodeInfoFlags infoFlags = 0;
    
    status = VTDecompressionSessionDecodeFrame(
        _decompressionSession,
        sampleBuffer,    // FIX: was NULL before — this is the actual bug
        decodeFlags,
        NULL,
        &infoFlags
    );
    CFRelease(sampleBuffer);
    
    if (status != noErr) {
        os_log_error(lanLog, "VideoToolbox decode error (%d)", (int)status);
    }
}

- (void)closeDescriptor {
    if (_descriptor >= 0) {
        close(_descriptor);
        _descriptor = -1;
    }
}

- (void)clearDecoderKeepingFrame:(BOOL)keepFrame {
    if (_decompressionSession) {
        VTDecompressionSessionWaitForAsynchronousFrames(_decompressionSession);
        VTDecompressionSessionInvalidate(_decompressionSession);
        CFRelease(_decompressionSession);
        _decompressionSession = NULL;
    }
    // FIX: also release formatDescription
    if (_formatDescription) {
        CFRelease(_formatDescription);
        _formatDescription = NULL;
    }
    if (!keepFrame && _latestPixelBuffer) {
        CVPixelBufferRelease(_latestPixelBuffer);
        _latestPixelBuffer = NULL;
    }
}

- (void)dealloc {
    [self closeDescriptor];
    [self clearDecoderKeepingFrame:NO];
}

@end
