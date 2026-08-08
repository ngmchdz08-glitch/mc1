#import "VCamControlPanel.h"
#import "VCamSettings.h"

// ── Design tokens ────────────────────────────────────────────────────
#define PANEL_BG        [[UIColor colorWithRed:0.06 green:0.06 blue:0.10 alpha:0.92] copy]
#define SURFACE_CLR     [[UIColor whiteColor] colorWithAlphaComponent:0.10]
#define SURFACE_PRESSED [[UIColor whiteColor] colorWithAlphaComponent:0.20]
#define ACCENT_CLR      [UIColor colorWithRed:0.25 green:0.82 blue:1.00 alpha:1.0]
#define GREEN_CLR       [UIColor colorWithRed:0.25 green:0.90 blue:0.50 alpha:1.0]
#define TEXT_CLR        [UIColor whiteColor]
#define TEXT2_CLR       [[UIColor whiteColor] colorWithAlphaComponent:0.55]
#define DANGER_CLR      [UIColor colorWithRed:1.0  green:0.38 blue:0.38 alpha:1.0]
#define BORDER_CLR      [[UIColor whiteColor] colorWithAlphaComponent:0.12]
#define SEP_CLR         [[UIColor whiteColor] colorWithAlphaComponent:0.08]

static const CGFloat kPanelWidth  = 260;
static const CGFloat kPanelHeight = 480;
static const CGFloat kBtnSize     = 46;
static const CGFloat kSmallBtn    = 36;
static const CGFloat kPadding     = 14;
static const CGFloat kCorner      = 22;

// ── Helper: section label ─────────────────────────────────────────────
static UILabel *makeSectionLabel(NSString *text, CGFloat x, CGFloat y, CGFloat w) {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(x, y, w, 18)];
    l.text = [text uppercaseString];
    l.font = [UIFont systemFontOfSize:9.5 weight:UIFontWeightBold];
    l.textColor = TEXT2_CLR;
    l.textAlignment = NSTextAlignmentLeft;
    return l;
}

@implementation VCamControlPanel {
    // Status bar
    UILabel  *_statusDot;
    UILabel  *_statusLabel;
    // Zoom row
    UIButton *_zoomOutBtn;
    UIButton *_zoomInBtn;
    // Color sync
    UIButton *_colorSyncToggle;
    BOOL      _colorSyncOn;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:CGRectMake(0, 0, kPanelWidth, kPanelHeight)];
    if (self) {
        [self buildPanel];
    }
    return self;
}

- (void)buildPanel {
    // ── Background ────────────────────────────────────────────────
    self.backgroundColor = PANEL_BG;
    self.layer.cornerRadius = kCorner;
    self.layer.borderWidth  = 0.8;
    self.layer.borderColor  = BORDER_CLR.CGColor;
    self.layer.shadowColor  = [UIColor blackColor].CGColor;
    self.layer.shadowOpacity = 0.7;
    self.layer.shadowRadius  = 20;
    self.layer.shadowOffset  = CGSizeMake(0, 6);
    self.clipsToBounds = NO;

    CGFloat y = kPadding;
    CGFloat innerW = kPanelWidth - 2 * kPadding;

    // ── Header ────────────────────────────────────────────────────
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(kPadding, y, innerW - 40, 28)];
    title.text = @"VCam";
    title.font = [UIFont systemFontOfSize:19 weight:UIFontWeightHeavy];
    title.textColor = TEXT_CLR;
    [self addSubview:title];

    // Status dot
    _statusDot = [[UILabel alloc] initWithFrame:CGRectMake(kPadding, y + 28, 10, 10)];
    _statusDot.layer.cornerRadius = 5;
    _statusDot.layer.masksToBounds = YES;
    _statusDot.backgroundColor = GREEN_CLR;
    [self addSubview:_statusDot];

    _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(kPadding + 16, y + 25, innerW - 16, 16)];
    _statusLabel.text = @"Active";
    _statusLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    _statusLabel.textColor = GREEN_CLR;
    [self addSubview:_statusLabel];

    // Close button
    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(kPanelWidth - 36, y + 2, 28, 28);
    closeBtn.tintColor = TEXT2_CLR;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
        configurationWithPointSize:14 weight:UIImageSymbolWeightMedium];
    [closeBtn setImage:[[UIImage systemImageNamed:@"xmark.circle.fill"]
        imageWithConfiguration:cfg] forState:UIControlStateNormal];
    closeBtn.tag = 199;
    [closeBtn addTarget:self action:@selector(commandTapped:)
       forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:closeBtn];

    y += 50;
    [self addSeparatorAt:y];
    y += 10;

    // ── Section: Position ─────────────────────────────────────────
    [self addSubview:makeSectionLabel(@"Position", kPadding, y, innerW)];
    y += 22;

    // Up button — centered
    UIButton *upBtn = [self makeBtn:@"arrow.up" cmd:@"up" label:@"Move up" clr:TEXT_CLR];
    upBtn.frame = CGRectMake((kPanelWidth - kBtnSize) / 2, y, kBtnSize, kBtnSize);
    [self addSubview:upBtn];
    y += kBtnSize + 4;

    // Left | Rotate | Right row
    CGFloat rowX = (kPanelWidth - 3 * kBtnSize - 16) / 2;
    UIButton *leftBtn = [self makeBtn:@"arrow.left" cmd:@"left" label:@"Move left" clr:TEXT_CLR];
    leftBtn.frame = CGRectMake(rowX, y, kBtnSize, kBtnSize);
    [self addSubview:leftBtn];

    UIButton *rotBtn = [self makeBtn:@"arrow.clockwise" cmd:@"rotate" label:@"Rotate 90°" clr:ACCENT_CLR];
    rotBtn.frame = CGRectMake(rowX + kBtnSize + 8, y, kBtnSize, kBtnSize);
    [self addSubview:rotBtn];

    UIButton *rightBtn = [self makeBtn:@"arrow.right" cmd:@"right" label:@"Move right" clr:TEXT_CLR];
    rightBtn.frame = CGRectMake(rowX + 2 * (kBtnSize + 8), y, kBtnSize, kBtnSize);
    [self addSubview:rightBtn];
    y += kBtnSize + 4;

    // Down button
    UIButton *downBtn = [self makeBtn:@"arrow.down" cmd:@"down" label:@"Move down" clr:TEXT_CLR];
    downBtn.frame = CGRectMake((kPanelWidth - kBtnSize) / 2, y, kBtnSize, kBtnSize);
    [self addSubview:downBtn];
    y += kBtnSize + 6;

    // Reset + Flip — side by side
    CGFloat pairX = (kPanelWidth - 2 * kSmallBtn - 8 - 80) / 2;
    UIButton *resetBtn = [self makeBtn:@"arrow.counterclockwise" cmd:@"reset" label:@"Reset" clr:DANGER_CLR];
    resetBtn.frame = CGRectMake(pairX, y, kSmallBtn, kSmallBtn);
    [self addSubview:resetBtn];

    UILabel *resetLbl = [[UILabel alloc] initWithFrame:CGRectMake(pairX + kSmallBtn + 4, y + 8, 36, 18)];
    resetLbl.text = @"Reset";
    resetLbl.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    resetLbl.textColor = TEXT2_CLR;
    [self addSubview:resetLbl];

    UIButton *flipBtn = [self makeBtn:@"arrow.left.and.right" cmd:@"flip" label:@"Flip" clr:TEXT_CLR];
    flipBtn.frame = CGRectMake(pairX + kSmallBtn + 48, y, kSmallBtn, kSmallBtn);
    [self addSubview:flipBtn];

    UILabel *flipLbl = [[UILabel alloc] initWithFrame:CGRectMake(pairX + kSmallBtn + 52, y + 8, 30, 18)];
    flipLbl.text = @"Flip";
    flipLbl.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    flipLbl.textColor = TEXT2_CLR;
    [self addSubview:flipLbl];
    y += kSmallBtn + 8;

    [self addSeparatorAt:y];
    y += 10;

    // ── Section: Zoom ─────────────────────────────────────────────
    [self addSubview:makeSectionLabel(@"Zoom", kPadding, y, innerW)];
    y += 22;

    _zoomOutBtn = [self makeBtn:@"minus.magnifyingglass" cmd:@"zoomout" label:@"Zoom -" clr:TEXT_CLR];
    _zoomOutBtn.frame = CGRectMake(rowX, y, kBtnSize, kBtnSize);
    [self addSubview:_zoomOutBtn];

    _zoomLabel = [[UILabel alloc] initWithFrame:CGRectMake(rowX + kBtnSize + 6, y, kBtnSize + 4, kBtnSize)];
    _zoomLabel.text = @"1.00x";
    _zoomLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightSemibold];
    _zoomLabel.textColor = ACCENT_CLR;
    _zoomLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_zoomLabel];

    _zoomInBtn = [self makeBtn:@"plus.magnifyingglass" cmd:@"zoomin" label:@"Zoom +" clr:TEXT_CLR];
    _zoomInBtn.frame = CGRectMake(rowX + 2 * (kBtnSize + 8), y, kBtnSize, kBtnSize);
    [self addSubview:_zoomInBtn];
    y += kBtnSize + 8;

    [self addSeparatorAt:y];
    y += 10;

    // ── Section: Options ──────────────────────────────────────────
    [self addSubview:makeSectionLabel(@"Options", kPadding, y, innerW)];
    y += 22;

    // Color sync toggle
    UILabel *csLabel = [[UILabel alloc] initWithFrame:CGRectMake(kPadding, y + 6, innerW - 60, 22)];
    csLabel.text = @"Color Sync";
    csLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    csLabel.textColor = TEXT_CLR;
    [self addSubview:csLabel];

    UISwitch *csSwitch = [[UISwitch alloc] init];
    csSwitch.frame = CGRectMake(kPanelWidth - kPadding - csSwitch.frame.size.width,
                                 y, csSwitch.frame.size.width, csSwitch.frame.size.height);
    csSwitch.onTintColor = ACCENT_CLR;
    csSwitch.on = NO;
    [csSwitch addTarget:self action:@selector(colorSyncToggled:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:csSwitch];
    y += 44;

    // Panel height dynamic resize
    CGRect f = self.frame;
    f.size.height = y + kPadding;
    self.frame = f;
}

- (void)addSeparatorAt:(CGFloat)y {
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(kPadding, y, kPanelWidth - 2*kPadding, 0.5)];
    sep.backgroundColor = SEP_CLR;
    [self addSubview:sep];
}

- (UIButton *)makeBtn:(NSString *)sf cmd:(NSString *)cmd label:(NSString *)lbl clr:(UIColor *)clr {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.backgroundColor = SURFACE_CLR;
    btn.layer.cornerRadius = kBtnSize / 2;
    btn.layer.masksToBounds = YES;
    btn.tintColor = clr;
    btn.accessibilityLabel = lbl;

    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration
        configurationWithPointSize:17 weight:UIImageSymbolWeightMedium];
    [btn setImage:[[UIImage systemImageNamed:sf] imageWithConfiguration:cfg]
         forState:UIControlStateNormal];

    btn.tag = [self tagFor:cmd];
    [btn addTarget:self action:@selector(commandTapped:)
  forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

- (NSInteger)tagFor:(NSString *)cmd {
    NSDictionary *m = @{@"up":@1,@"down":@2,@"left":@3,@"right":@4,
                        @"rotate":@5,@"flip":@6,@"zoomin":@7,@"zoomout":@8,
                        @"reset":@9,@"close":@10};
    return [m[cmd] integerValue];
}

- (NSString *)cmdFor:(NSInteger)tag {
    NSDictionary *m = @{@1:@"up",@2:@"down",@3:@"left",@4:@"right",
                        @5:@"rotate",@6:@"flip",@7:@"zoomin",@8:@"zoomout",
                        @9:@"reset",@10:@"close",@199:@"close"};
    return m[@(tag)];
}

- (void)commandTapped:(UIButton *)btn {
    NSString *cmd = [self cmdFor:btn.tag];
    if (!cmd) return;

    if ([cmd isEqualToString:@"close"]) {
        [UIView animateWithDuration:0.2 animations:^{
            self.alpha = 0;
            self.transform = CGAffineTransformMakeScale(0.88, 0.88);
        } completion:^(BOOL done) {
            self.hidden = YES;
            self.alpha = 1;
            self.transform = CGAffineTransformIdentity;
        }];
        return;
    }

    if (_commandHandler) _commandHandler(cmd);

    // Haptic-like scale feedback
    [UIView animateWithDuration:0.08 animations:^{
        btn.transform = CGAffineTransformMakeScale(0.82, 0.82);
    } completion:^(BOOL d) {
        [UIView animateWithDuration:0.12 animations:^{
            btn.transform = CGAffineTransformIdentity;
        }];
    }];
}

- (void)colorSyncToggled:(UISwitch *)sw {
    if (_commandHandler) {
        _commandHandler(sw.on ? @"colorsync_on" : @"colorsync_off");
    }
}

- (void)updatePanelFrame {
    CGRect screen = [UIScreen mainScreen].bounds;
    UIEdgeInsets safe = UIEdgeInsetsZero;
    if (@available(iOS 15.0, *)) {
        safe = self.window ? self.window.safeAreaInsets : UIEdgeInsetsZero;
    }
    CGFloat x = (screen.size.width - kPanelWidth) / 2;
    CGFloat y = safe.top + 60;
    self.frame = CGRectMake(x, y, self.frame.size.width, self.frame.size.height);
}

- (void)updateZoomValue:(CGFloat)zoom {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_zoomLabel.text = [NSString stringWithFormat:@"%.2fx", zoom];
    });
}

- (void)updateStatus:(NSString *)message active:(BOOL)active {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_statusLabel.text = message;
        UIColor *c = active ? GREEN_CLR : [UIColor colorWithRed:1 green:0.7 blue:0.2 alpha:1];
        self->_statusLabel.textColor = c;
        self->_statusDot.backgroundColor = c;
    });
}

// Pass through touches outside interactive elements
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}

@end
