#import "VCamHook.h"
#import "VCamRenderer.h"
#import "VCamConfig.h"
#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <os/log.h>
#import <substrate.h>
#import <dlfcn.h>

static os_log_t vcamLog;
static NSMutableSet *hookedClasses;
static uint64_t renderedFrameCount = 0;

#pragma mark - Original IMP storage

// FIX: Store orig IMPs as function pointers, NOT as void* in NSValue.
// MSHookMessageEx on arm64/arm64e requires passing a proper IMP* so
// Substrate can build the trampoline correctly (especially for PAC on A12+).
// We use a simple static map: className -> IMP.

#define MAX_HOOKED 32
static struct {
    const char *className;
    IMP         origRender;  // renderSampleBuffer:forInput:
    IMP         origEmit;    // emitSampleBuffer:
} hookedTable[MAX_HOOKED];
static int hookedTableCount = 0;

static IMP vcamGetOrigRender(Class cls) {
    const char *name = class_getName(cls);
    for (int i = 0; i < hookedTableCount; i++) {
        if (strcmp(hookedTable[i].className, name) == 0)
            return hookedTable[i].origRender;
    }
    // Walk superclass chain
    Class sup = class_getSuperclass(cls);
    if (sup) return vcamGetOrigRender(sup);
    return NULL;
}

static IMP vcamGetOrigEmit(Class cls) {
    const char *name = class_getName(cls);
    for (int i = 0; i < hookedTableCount; i++) {
        if (strcmp(hookedTable[i].className, name) == 0)
            return hookedTable[i].origEmit;
    }
    Class sup = class_getSuperclass(cls);
    if (sup) return vcamGetOrigEmit(sup);
    return NULL;
}

#pragma mark - Hook: renderSampleBuffer:forInput:

typedef void (*RenderIMP)(id, SEL, CMSampleBufferRef, NSInteger);

static void hooked_renderSampleBuffer_forInput(id self, SEL _cmd,
                                               CMSampleBufferRef sampleBuffer,
                                               NSInteger input) {
    VCamConfig *config = [VCamConfig sharedConfig];
    RenderIMP orig = (RenderIMP)vcamGetOrigRender([self class]);

    if (!config.injectionEnabled || !orig) {
        if (orig) orig(self, _cmd, sampleBuffer, input);
        return;
    }

    CMSampleBufferRef replaced = [[VCamRenderer sharedRenderer]
                                  renderReplacementForSampleBuffer:sampleBuffer
                                  purpose:input];
    if (replaced) {
        renderedFrameCount++;
        orig(self, _cmd, replaced, input);
        CFRelease(replaced);
    } else {
        orig(self, _cmd, sampleBuffer, input);
    }
}

#pragma mark - Hook: emitSampleBuffer:

typedef void (*EmitIMP)(id, SEL, CMSampleBufferRef);

static void hooked_emitSampleBuffer(id self, SEL _cmd,
                                    CMSampleBufferRef sampleBuffer) {
    VCamConfig *config = [VCamConfig sharedConfig];
    EmitIMP orig = (EmitIMP)vcamGetOrigEmit([self class]);

    if (!config.injectionEnabled || !orig) {
        if (orig) orig(self, _cmd, sampleBuffer);
        return;
    }

    CMSampleBufferRef replaced = [[VCamRenderer sharedRenderer]
                                  renderReplacementForSampleBuffer:sampleBuffer
                                  purpose:0];
    if (replaced) {
        renderedFrameCount++;
        orig(self, _cmd, replaced);
        CFRelease(replaced);
    } else {
        orig(self, _cmd, sampleBuffer);
    }
}

#pragma mark - Hook: AVCaptureVideoDataOutput delegate

// FIX: Properly typed orig pointer for MSHookMessageEx
static void (*origSetSampleBufferDelegate)(id, SEL, id, dispatch_queue_t);

typedef void (*DelegateIMP)(id, SEL, id, CMSampleBufferRef, id);
static NSMutableDictionary<NSString *, NSValue *> *origDelegateIMPs;

static void hooked_captureOutput_didOutputSampleBuffer_fromConnection(
    id self, SEL _cmd, id output, CMSampleBufferRef sampleBuffer, id connection)
{
    VCamConfig *config = [VCamConfig sharedConfig];

    // Find orig IMP
    DelegateIMP orig = NULL;
    Class cls = [self class];
    while (cls) {
        NSString *name = NSStringFromClass(cls);
        NSValue *v = origDelegateIMPs[name];
        if (v) { orig = (DelegateIMP)[v pointerValue]; break; }
        cls = class_getSuperclass(cls);
    }

    if (!orig) return;
    if (!config.injectionEnabled) {
        orig(self, _cmd, output, sampleBuffer, connection);
        return;
    }

    CMSampleBufferRef replaced = [[VCamRenderer sharedRenderer]
                                  renderReplacementForSampleBuffer:sampleBuffer
                                  purpose:0];
    if (replaced) {
        renderedFrameCount++;
        orig(self, _cmd, output, replaced, connection);
        CFRelease(replaced);
    } else {
        orig(self, _cmd, output, sampleBuffer, connection);
    }
}

static void hooked_setSampleBufferDelegate(id self, SEL _cmd,
                                           id delegate,
                                           dispatch_queue_t queue) {
    if (delegate) {
        Class delegateCls = [delegate class];
        SEL sel = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
        Method m = class_getInstanceMethod(delegateCls, sel);
        if (m) {
            NSString *name = NSStringFromClass(delegateCls);
            if (!origDelegateIMPs[name]) {
                IMP origIMP = method_getImplementation(m);
                origDelegateIMPs[name] = [NSValue valueWithPointer:(void *)origIMP];
                // FIX: pass NULL here — we store orig manually since delegate
                // classes are dynamic and we need per-class storage
                MSHookMessageEx(delegateCls, sel,
                    (IMP)hooked_captureOutput_didOutputSampleBuffer_fromConnection,
                    NULL);
                os_log(vcamLog, "Hooked delegate %{public}s", name.UTF8String);
            }
        }
    }
    if (origSetSampleBufferDelegate) {
        origSetSampleBufferDelegate(self, _cmd, delegate, queue);
    }
}

#pragma mark - Hook Installation

static BOOL vcamHookRenderMethod(Class cls) {
    SEL sel = @selector(renderSampleBuffer:forInput:);
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) return NO;

    const char *name = class_getName(cls);
    // Already hooked?
    for (int i = 0; i < hookedTableCount; i++) {
        if (strcmp(hookedTable[i].className, name) == 0) return NO;
    }
    if (hookedTableCount >= MAX_HOOKED) return NO;

    IMP origIMP = NULL;
    // FIX: Pass &origIMP so MSHookMessageEx sets up the trampoline properly.
    // This is the correct way — Substrate writes the trampoline address into origIMP.
    MSHookMessageEx(cls, sel,
                    (IMP)hooked_renderSampleBuffer_forInput,
                    &origIMP);

    if (!origIMP) {
        // Fallback: grab IMP before hook — happens if Substrate version is old
        origIMP = method_getImplementation(method);
    }

    hookedTable[hookedTableCount].className = strdup(name);
    hookedTable[hookedTableCount].origRender = origIMP;
    hookedTable[hookedTableCount].origEmit   = NULL;
    hookedTableCount++;

    [hookedClasses addObject:[NSString stringWithUTF8String:name]];
    os_log(vcamLog, "hooked render: %{public}s", name);
    return YES;
}

static BOOL vcamHookEmitMethod(Class cls) {
    SEL sel = @selector(emitSampleBuffer:);
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) return NO;

    const char *name = class_getName(cls);
    for (int i = 0; i < hookedTableCount; i++) {
        if (strcmp(hookedTable[i].className, name) == 0) {
            // Already in table, just add emit orig
            if (hookedTable[i].origEmit) return NO;
            IMP origIMP = NULL;
            MSHookMessageEx(cls, sel,
                            (IMP)hooked_emitSampleBuffer,
                            &origIMP);
            if (!origIMP) origIMP = method_getImplementation(method);
            hookedTable[i].origEmit = origIMP;
            [hookedClasses addObject:[NSString stringWithUTF8String:name]];
            os_log(vcamLog, "hooked emit: %{public}s", name);
            return YES;
        }
    }
    if (hookedTableCount >= MAX_HOOKED) return NO;

    IMP origIMP = NULL;
    MSHookMessageEx(cls, sel,
                    (IMP)hooked_emitSampleBuffer,
                    &origIMP);
    if (!origIMP) origIMP = method_getImplementation(method);

    hookedTable[hookedTableCount].className = strdup(name);
    hookedTable[hookedTableCount].origRender = NULL;
    hookedTable[hookedTableCount].origEmit   = origIMP;
    hookedTableCount++;

    [hookedClasses addObject:[NSString stringWithUTF8String:name]];
    os_log(vcamLog, "hooked emit: %{public}s", name);
    return YES;
}

// Known BW* pipeline class names in cameracaptured (iOS 15)
static NSArray<NSString *> *vcamKnownRenderClasses(void) {
    return @[
        @"BWImageQueueSinkNode",
        @"BWRemoteQueueSinkNode",
        @"BWPhotoEncoderNode",
        @"BWStillImageSampleBufferSinkNode",
        @"BWPixelTransferNode",
        @"BWVISNode",
        @"BWHEVCRecompressionNode",
        @"BWNetworkImageSinkNode",
    ];
}

static NSArray<NSString *> *vcamKnownEmitClasses(void) {
    return @[
        @"BWNodeOutput",
        @"BWPreviewSinkNode",
        @"BWLivePhotoSinkNode",
    ];
}

// FIX: Scan ALL loaded classes for BW* subclasses — catches dynamic subclasses
// on iOS 15 that aren't in the known list.
static void vcamScanAllClasses(void) {
    unsigned int classCount = 0;
    Class *allClasses = objc_copyClassList(&classCount);
    if (!allClasses) return;

    Class previewBase  = objc_getClass("BWPreviewSinkNode");
    Class renderBase   = objc_getClass("BWImageQueueSinkNode");

    for (unsigned int i = 0; i < classCount; i++) {
        Class cls = allClasses[i];
        const char *name = class_getName(cls);
        if (!name || name[0] != 'B' || name[1] != 'W') continue;

        // Check renderSampleBuffer:forInput:
        if (class_getInstanceMethod(cls, @selector(renderSampleBuffer:forInput:))) {
            vcamHookRenderMethod(cls);
        }
        // Check emitSampleBuffer:
        if (class_getInstanceMethod(cls, @selector(emitSampleBuffer:))) {
            vcamHookEmitMethod(cls);
        }
        (void)previewBase; (void)renderBase;
    }

    free(allClasses);
}

void VCamInstallHooks(void) {
    origDelegateIMPs = [NSMutableDictionary new];

    // Step 1: Try known classes first
    for (NSString *name in vcamKnownRenderClasses()) {
        Class cls = objc_getClass(name.UTF8String);
        if (cls) vcamHookRenderMethod(cls);
    }
    for (NSString *name in vcamKnownEmitClasses()) {
        Class cls = objc_getClass(name.UTF8String);
        if (cls) vcamHookEmitMethod(cls);
    }

    // Step 2: Full class scan for dynamic subclasses
    vcamScanAllClasses();

    // Step 3: Hook AVCaptureVideoDataOutput delegate (catches 3rd party apps)
    Class avOutputCls = objc_getClass("AVCaptureVideoDataOutput");
    if (avOutputCls) {
        SEL sel = @selector(setSampleBufferDelegate:queue:);
        Method m = class_getInstanceMethod(avOutputCls, sel);
        if (m) {
            MSHookMessageEx(avOutputCls, sel,
                            (IMP)hooked_setSampleBufferDelegate,
                            (IMP *)&origSetSampleBufferDelegate);
            os_log(vcamLog, "Hooked setSampleBufferDelegate:queue:");
        }
    }

    os_log(vcamLog, "VCamInstallHooks done — %lu classes hooked",
           (unsigned long)hookedClasses.count);
}

// FIX: Retry hook installation — BW* classes in cameracaptured are loaded
// AFTER the constructor runs (lazy loaded when camera hardware activates).
// We retry every 0.5s for up to 10 seconds.
static void vcamScheduleRetryHooks(void) {
    static dispatch_source_t retryTimer;
    static int retryCount = 0;

    dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    retryTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, q);
    dispatch_source_set_timer(retryTimer,
        dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
        500 * NSEC_PER_MSEC, 50 * NSEC_PER_MSEC);

    dispatch_source_set_event_handler(retryTimer, ^{
        retryCount++;
        NSUInteger before = hookedClasses.count;
        VCamInstallHooks();
        NSUInteger after = hookedClasses.count;

        if (after > before) {
            os_log(vcamLog, "Retry %d: hooked %lu new classes (total %lu)",
                   retryCount, (unsigned long)(after - before), (unsigned long)after);
        }

        // Stop after 10 seconds or when we have enough classes
        if (retryCount >= 20 || after >= 4) {
            dispatch_source_cancel(retryTimer);
            os_log(vcamLog, "Hook retry finished — total %lu classes", (unsigned long)after);
        }
    });

    dispatch_resume(retryTimer);
}

#pragma mark - Constructor

__attribute__((constructor))
static void vcamCameraInit(void) {
    vcamLog = os_log_create("com.vcam.mch", "hook");
    hookedClasses = [NSMutableSet new];

    const char *processName = getprogname() ? getprogname() : "unknown";
    os_log(vcamLog, "VCam starting in process %s", processName);

    // Init config
    [VCamConfig sharedConfig];

    // First attempt — some classes may already be loaded
    VCamInstallHooks();

    // FIX: Schedule retries for classes that load lazily
    vcamScheduleRetryHooks();

    [[VCamConfig sharedConfig] updateStatus:@{
        @"state": @"waiting",
        @"message": @"Waiting for camera pipeline",
        @"process": [NSString stringWithUTF8String:processName],
        @"hookedClassCount": @(hookedClasses.count)
    }];

    os_log(vcamLog, "VCam init done — %lu classes hooked so far",
           (unsigned long)hookedClasses.count);
}
