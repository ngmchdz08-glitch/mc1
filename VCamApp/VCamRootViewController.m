#import "VCamRootViewController.h"
#import "VCamSettings.h"
#import <MobileCoreServices/MobileCoreServices.h>

@interface VCamRootViewController ()
@property (nonatomic, strong) VCamSettings *settings;
@property (nonatomic, strong) UISwitch *bypassSwitch;
@property (nonatomic, strong) UISwitch *floatingMenuSwitch;
@end

@implementation VCamRootViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"VCam Settings";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.settings = [VCamSettings shared];
    
    [self setupUI];
}

- (void)setupUI {
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:scrollView];
    
    CGFloat y = 20;
    
    // Bypass Toggle
    UILabel *bypassLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 200, 30)];
    bypassLabel.text = @"Enable Hook (OBS/Media)";
    [scrollView addSubview:bypassLabel];
    
    self.bypassSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - 80, y, 50, 30)];
    self.bypassSwitch.on = self.settings.linkEnabled || self.settings.directMediaEnabled || self.settings.selectedMediaPath.length > 0;
    [self.bypassSwitch addTarget:self action:@selector(toggleBypass:) forControlEvents:UIControlEventValueChanged];
    [scrollView addSubview:self.bypassSwitch];
    
    y += 60;
    
    // Floating Menu Toggle
    UILabel *menuLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 200, 30)];
    menuLabel.text = @"Show Floating Menu";
    [scrollView addSubview:menuLabel];
    
    self.floatingMenuSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - 80, y, 50, 30)];
    self.floatingMenuSwitch.on = self.settings.floatingControlEnabled;
    [self.floatingMenuSwitch addTarget:self action:@selector(toggleMenu:) forControlEvents:UIControlEventValueChanged];
    [scrollView addSubview:self.floatingMenuSwitch];
    
    y += 60;
    
    // Select Image Button
    UIButton *imageBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    imageBtn.frame = CGRectMake(20, y, self.view.bounds.size.width - 40, 44);
    [imageBtn setTitle:@"Load Image" forState:UIControlStateNormal];
    imageBtn.backgroundColor = [UIColor systemBlueColor];
    [imageBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    imageBtn.layer.cornerRadius = 8;
    [imageBtn addTarget:self action:@selector(pickImage) forControlEvents:UIControlEventTouchUpInside];
    [scrollView addSubview:imageBtn];
    
    y += 60;
    
    // Select Video Button
    UIButton *videoBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    videoBtn.frame = CGRectMake(20, y, self.view.bounds.size.width - 40, 44);
    [videoBtn setTitle:@"Load Video" forState:UIControlStateNormal];
    videoBtn.backgroundColor = [UIColor systemGreenColor];
    [videoBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    videoBtn.layer.cornerRadius = 8;
    [videoBtn addTarget:self action:@selector(pickVideo) forControlEvents:UIControlEventTouchUpInside];
    [scrollView addSubview:videoBtn];
    
    y += 60;
    
    // OBS Stream Server Section
    UILabel *obsHeader = [[UILabel alloc] initWithFrame:CGRectMake(20, y, self.view.bounds.size.width - 40, 25)];
    obsHeader.text = @"📡 OBS / PC LAN Live Stream Connect";
    obsHeader.font = [UIFont boldSystemFontOfSize:16];
    [scrollView addSubview:obsHeader];
    
    y += 30;
    UILabel *obsLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, self.view.bounds.size.width - 40, 40)];
    obsLabel.text = @"Stream live video from OBS/PC (Port 8888). Enable Direct LAN to receive live video.";
    obsLabel.numberOfLines = 0;
    obsLabel.font = [UIFont systemFontOfSize:13];
    obsLabel.textColor = [UIColor secondaryLabelColor];
    [scrollView addSubview:obsLabel];
    
    y += 45;
    
    // Zoom Slider
    UILabel *zoomLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 200, 25)];
    zoomLabel.text = [NSString stringWithFormat:@"Zoom Scale: %.1fx", self.settings.zoom];
    [scrollView addSubview:zoomLabel];
    
    y += 30;
    UISlider *zoomSlider = [[UISlider alloc] initWithFrame:CGRectMake(20, y, self.view.bounds.size.width - 40, 30)];
    zoomSlider.minimumValue = 0.5;
    zoomSlider.maximumValue = 3.0;
    zoomSlider.value = self.settings.zoom;
    [zoomSlider addTarget:self action:@selector(zoomChanged:) forControlEvents:UIControlEventValueChanged];
    [scrollView addSubview:zoomSlider];
    
    y += 45;
    
    // Rotate & Flip Control Buttons
    UIButton *rotateBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    rotateBtn.frame = CGRectMake(20, y, (self.view.bounds.size.width - 50) / 2, 40);
    [rotateBtn setTitle:[NSString stringWithFormat:@"Rotate: %ld°", (long)self.settings.rotationDegrees] forState:UIControlStateNormal];
    rotateBtn.backgroundColor = [UIColor systemGray5Color];
    rotateBtn.layer.cornerRadius = 8;
    [rotateBtn addTarget:self action:@selector(rotateVideo:) forControlEvents:UIControlEventTouchUpInside];
    [scrollView addSubview:rotateBtn];
    
    UIButton *flipBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    flipBtn.frame = CGRectMake(self.view.bounds.size.width / 2 + 5, y, (self.view.bounds.size.width - 50) / 2, 40);
    [flipBtn setTitle:self.settings.horizontalFlip ? @"Flip: ON" : @"Flip: OFF" forState:UIControlStateNormal];
    flipBtn.backgroundColor = [UIColor systemGray5Color];
    flipBtn.layer.cornerRadius = 8;
    [flipBtn addTarget:self action:@selector(flipVideo:) forControlEvents:UIControlEventTouchUpInside];
    [scrollView addSubview:flipBtn];
    
    y += 60;
    scrollView.contentSize = CGSizeMake(self.view.bounds.size.width, y + 80);
}

- (void)zoomChanged:(UISlider *)sender {
    self.settings.zoom = sender.value;
    [self saveAndNotify];
}

- (void)rotateVideo:(UIButton *)sender {
    NSInteger deg = (self.settings.rotationDegrees + 90) % 360;
    self.settings.rotationDegrees = deg;
    [sender setTitle:[NSString stringWithFormat:@"Rotate: %ld°", (long)deg] forState:UIControlStateNormal];
    [self saveAndNotify];
}

- (void)flipVideo:(UIButton *)sender {
    self.settings.horizontalFlip = !self.settings.horizontalFlip;
    [sender setTitle:self.settings.horizontalFlip ? @"Flip: ON" : @"Flip: OFF" forState:UIControlStateNormal];
    [self saveAndNotify];
}


- (void)toggleBypass:(UISwitch *)sender {
    // If enabling without media, fallback to LAN stream
    if (sender.isOn && self.settings.selectedMediaPath.length == 0) {
        self.settings.directMediaEnabled = YES;
    } else if (!sender.isOn) {
        self.settings.directMediaEnabled = NO;
        self.settings.selectedMediaPath = nil;
    }
    [self saveAndNotify];
}

- (void)toggleMenu:(UISwitch *)sender {
    self.settings.floatingControlEnabled = sender.isOn;
    [self saveAndNotify];
}

- (void)saveAndNotify {
    [self.settings save];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.vcam.state.changed"), NULL, NULL, YES);
}

- (void)pickImage {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[@"public.image"];
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)pickVideo {
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.delegate = self;
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[@"public.movie"];
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey,id> *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
    
    NSString *mediaDir = @"/var/jb/var/mobile/Library/VCam/Media";
    [[NSFileManager defaultManager] createDirectoryAtPath:mediaDir withIntermediateDirectories:YES attributes:nil error:nil];
    
    NSString *mediaType = info[UIImagePickerControllerMediaType];
    if ([mediaType isEqualToString:@"public.image"]) {
        UIImage *image = info[UIImagePickerControllerOriginalImage];
        if (image) {
            NSData *data = UIImageJPEGRepresentation(image, 1.0);
            NSString *path = [mediaDir stringByAppendingPathComponent:@"virtual_image.jpg"];
            [data writeToFile:path atomically:YES];
            self.settings.selectedMediaPath = path;
            self.settings.selectedMediaKind = 0;
            self.settings.directMediaEnabled = NO;
            self.bypassSwitch.on = YES;
            [self saveAndNotify];
        }
    } else if ([mediaType isEqualToString:@"public.movie"]) {
        NSURL *url = info[UIImagePickerControllerMediaURL];
        if (url) {
            NSString *destPath = [mediaDir stringByAppendingPathComponent:@"virtual_video.mp4"];
            [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
            [[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:destPath] error:nil];
            
            self.settings.selectedMediaPath = destPath;
            self.settings.selectedMediaKind = 1;
            self.settings.directMediaEnabled = NO;
            self.bypassSwitch.on = YES;
            [self saveAndNotify];
        }
    }
}

@end
