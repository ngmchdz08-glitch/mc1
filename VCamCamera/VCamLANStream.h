#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <VideoToolbox/VideoToolbox.h>

@interface VCamLANStream : NSObject

@property (nonatomic, copy)   NSString *path;
@property (nonatomic, assign) int descriptor;
@property (nonatomic, assign) uint64_t inode;
@property (nonatomic, assign) int64_t readOffset;
@property (nonatomic, assign) uint64_t generation;
@property (nonatomic, assign) VTDecompressionSessionRef decompressionSession;
@property (nonatomic, assign) NSUInteger nalUnitHeaderLength;
@property (nonatomic, assign) CVPixelBufferRef latestPixelBuffer;
@property (nonatomic, assign) uint64_t frameSequence;
@property (nonatomic, copy)   NSString *statusMessage;

// H.264 parameter sets (instance vars, not static — thread safe)
@property (nonatomic, strong) NSData *storedSPS;
@property (nonatomic, strong) NSData *storedPPS;
// Format description for CMSampleBuffer construction
@property (nonatomic, assign) CMFormatDescriptionRef formatDescription;

- (instancetype)init;
- (void)poll;
- (void)closeDescriptor;
- (void)clearDecoderKeepingFrame:(BOOL)keepFrame;

@end

