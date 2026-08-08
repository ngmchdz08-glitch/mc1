#import <Foundation/Foundation.h>
#import <CoreImage/CoreImage.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

@interface VCamVideoReader : NSObject

@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong) AVAssetReader *reader;
@property (nonatomic, strong) AVAssetReaderTrackOutput *trackOutput;
@property (nonatomic, copy) NSString *readerStamp;
@property (nonatomic, assign) CGAffineTransform preferredTransform;
@property (nonatomic, assign) CMSampleBufferRef currentSample;
@property (nonatomic, assign) CMSampleBufferRef pendingSample;
@property (nonatomic, assign) uint64_t frameSequence;
@property (nonatomic, assign) CMTime firstPTS;
@property (nonatomic, assign) NSTimeInterval cycleStartedAt;

- (instancetype)initWithPath:(NSString *)path;
- (CIImage *)nextFrame;

@end
