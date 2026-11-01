#import "ZJRootVC.h"
#import "ZJSettingsVC.h"
#import "ZJQuote.h"
#import "ZJStore.h"
#import "ZJTheme.h"

@interface ZJRootVC ()
@property (nonatomic, strong) UIView *chrome;
@property (nonatomic, strong) UIView *board;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *indexLabel;
@property (nonatomic, strong) UILabel *clockLabel;
@property (nonatomic, copy) NSArray<ZJHolding *> *holdings;
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, assign) NSInteger dwellLeft;
@property (nonatomic, assign) CGSize laidOut;
@property (nonatomic, assign) BOOL dirty;
@property (nonatomic, assign) BOOL quoting;
@property (nonatomic, assign) NSTimeInterval lastFetchAt;
@property (nonatomic, copy) NSString *lastError;
@property (nonatomic, strong) NSTimer *tick;
@end

@implementation ZJRootVC

- (BOOL)prefersStatusBarHidden { return YES; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = ZJBG();
    self.chrome = [[UIView alloc] initWithFrame:CGRectZero];
    self.board = [[UIView alloc] initWithFrame:CGRectZero];
    self.board.backgroundColor = ZJBG();
    [self.view addSubview:self.board];
    [self.view addSubview:self.chrome];

    self.titleLabel = ZJLabel(@"张洁股票", 26, UIFontWeightSemibold, ZJText());
    self.titleLabel.textAlignment = NSTextAlignmentLeft;
    self.statusLabel = ZJLabel(@"", 18, UIFontWeightMedium, ZJDim());
    self.indexLabel = ZJLabel(@"", 18, UIFontWeightMedium, ZJDim());
    self.clockLabel = ZJLabel(@"", 20, UIFontWeightMedium, ZJText());
    [self.chrome addSubview:self.titleLabel];
    [self.chrome addSubview:self.statusLabel];
    [self.chrome addSubview:self.indexLabel];
    [self.chrome addSubview:self.clockLabel];
    UIButton *prev = [self iconButton:@"◀" action:@selector(goPrev)];
    UIButton *gear = [self iconButton:@"设置" action:@selector(openSettings)];
    UIButton *next = [self iconButton:@"▶" action:@selector(goNext)];
    prev.tag = 11;
    gear.tag = 12;
    next.tag = 13;
    [self.chrome addSubview:prev];
    [self.chrome addSubview:gear];
    [self.chrome addSubview:next];

    UILongPressGestureRecognizer *press = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onLongPress:)];
    press.minimumPressDuration = 0.8;
    [self.view addGestureRecognizer:press];
    self.dirty = YES;
}

- (UIButton *)iconButton:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:ZJText() forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:[title isEqualToString:@"设置"] ? 18 : 28 weight:UIFontWeightMedium];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.holdings = [ZJStore holdings];
    NSInteger pages = [self pageCount];
    if (self.index >= pages) self.index = 0;
    [self restartDwell];
    [self startTimers];
    [self refreshQuotes];
    self.dirty = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.tick invalidate];
    self.tick = nil;
}

- (void)startTimers {
    [self.tick invalidate];
    self.tick = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(onTick) userInfo:nil repeats:YES];
}

- (NSInteger)pageCount {
    return 1 + (NSInteger)self.holdings.count;
}

- (NSInteger)dwellForCurrent {
    return self.index == 0 ? [ZJStore dwellSummary] : [ZJStore dwellStock];
}

- (void)restartDwell {
    self.dwellLeft = [self dwellForCurrent];
}

- (void)onTick {
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
        fmt.dateFormat = @"HH:mm";
    });
    self.clockLabel.text = [fmt stringFromDate:[NSDate date]];
    self.statusLabel.text = [ZJStore marketIsOpen] ? @"交易中" : @"未开盘";
    self.statusLabel.textColor = [ZJStore marketIsOpen] ? ZJUp() : ZJDim();
    NSInteger pages = [self pageCount];
    self.indexLabel.text = [NSString stringWithFormat:@"%ld/%ld", (long)(self.index + 1), (long)pages];
    if (pages > 1) {
        self.dwellLeft -= 1;
        if (self.dwellLeft <= 0) [self turn:1];
    }
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSTimeInterval since = now - self.lastFetchAt;
    if ([ZJStore shouldFetch] && since >= 60) {
        [self refreshQuotes];
    } else if (self.lastError.length && since >= 300) {
        // Outside trading hours a failed fetch used to stay failed until the view
        // reappeared; retry every 5 minutes so the last close eventually shows.
        [self refreshQuotes];
    }
}

- (void)refreshQuotes {
    if (self.quoting) return;
    self.quoting = YES;
    self.lastFetchAt = [NSDate date].timeIntervalSince1970;
    __weak ZJRootVC *weak = self;
    [ZJQuote refreshNow:^(BOOL ok, NSString *error) {
        ZJRootVC *self = weak;
        if (!self) return;
        self.quoting = NO;
        self.holdings = [ZJStore holdings];
        self.lastError = ok ? nil : error;
        self.dirty = YES;
        [self.view setNeedsLayout];
    }];
}

- (void)goPrev { [self turn:-1]; }
- (void)goNext { [self turn:1]; }

- (void)turn:(NSInteger)delta {
    NSInteger pages = [self pageCount];
    if (pages <= 0) return;
    NSInteger next = self.index + delta;
    if (next < 0) next = pages - 1;
    if (next >= pages) next = 0;
    if (pages == 1) {
        self.index = 0;
        [self restartDwell];
        return;
    }
    CGFloat travel = delta >= 0 ? -36 : 36;
    [UIView animateWithDuration:0.18 animations:^{
        self.board.transform = CGAffineTransformMakeTranslation(travel, 0);
        self.board.alpha = 0.2;
    } completion:^(BOOL finished) {
        (void)finished;
        self.index = next;
        [self restartDwell];
        self.dirty = YES;
        [self render];
        self.board.transform = CGAffineTransformMakeTranslation(-travel, 0);
        [UIView animateWithDuration:0.24 animations:^{
            self.board.transform = CGAffineTransformIdentity;
            self.board.alpha = 1;
        }];
    }];
}

- (void)onLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state == UIGestureRecognizerStateBegan) [self openSettings];
}

- (void)openSettings {
    ZJSettingsVC *settings = [[ZJSettingsVC alloc] init];
    settings.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:settings animated:YES completion:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    self.chrome.frame = CGRectMake(0, 0, b.size.width, 64);
    self.board.frame = CGRectMake(0, 64, b.size.width, b.size.height - 64);
    [self layoutChrome];
    if (self.dirty || !CGSizeEqualToSize(self.board.bounds.size, self.laidOut)) {
        self.laidOut = self.board.bounds.size;
        self.dirty = NO;
        [self render];
    }
}

- (void)layoutChrome {
    CGFloat w = self.chrome.bounds.size.width;
    CGFloat h = 64;
    UIButton *prev = (UIButton *)[self.chrome viewWithTag:11];
    UIButton *gear = (UIButton *)[self.chrome viewWithTag:12];
    UIButton *next = (UIButton *)[self.chrome viewWithTag:13];
    prev.frame = CGRectMake(8, 6, 52, h - 12);
    next.frame = CGRectMake(w - 60, 6, 52, h - 12);
    gear.frame = CGRectMake(w - 128, 6, 64, h - 12);
    self.clockLabel.frame = CGRectMake(w - 220, 0, 84, h);
    self.indexLabel.frame = CGRectMake(w - 300, 0, 72, h);
    self.statusLabel.frame = CGRectMake(w - 430, 0, 120, h);
    self.titleLabel.frame = CGRectMake(68, 0, MAX(40, w - 520), h);
}

- (void)render {
    for (UIView *sub in [self.board.subviews copy]) [sub removeFromSuperview];
    if (self.board.bounds.size.width < 10 || self.board.bounds.size.height < 10) return;
    if (self.index <= 0 || self.holdings.count == 0) [self renderSummary];
    else [self renderDetail:self.holdings[self.index - 1]];
}

- (NSString *)stamp:(NSDictionary *)quote {
    NSTimeInterval at = [quote[@"at"] doubleValue];
    if (at <= 0) return @"";
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
        fmt.dateFormat = @"MM-dd HH:mm";
    });
    return [NSString stringWithFormat:@"更新 %@", [fmt stringFromDate:[NSDate dateWithTimeIntervalSince1970:at]]];
}

- (void)renderSummary {
    CGFloat W = self.board.bounds.size.width;
    CGFloat H = self.board.bounds.size.height;
    UILabel *head = ZJLabel([ZJStore sessionTitle], 22, UIFontWeightMedium, ZJDim());
    head.frame = CGRectMake(16, 4, W - 32, 32);
    [self.board addSubview:head];
    if (self.lastError.length && self.holdings.count == 0) {
        UILabel *err = ZJLabel(self.lastError, 28, UIFontWeightMedium, ZJDim());
        err.frame = CGRectMake(16, 48, W - 32, 40);
        [self.board addSubview:err];
    }
    if (self.holdings.count == 0) {
        UILabel *empty = ZJLabel(@"长按屏幕，或点右上角设置，添加股票", 28, UIFontWeightMedium, ZJText());
        empty.frame = CGRectMake(24, H * 0.4, W - 48, 48);
        [self.board addSubview:empty];
        return;
    }
    NSInteger n = (NSInteger)self.holdings.count;
    NSInteger cols = W >= H ? 2 : 2;
    if (n == 1) cols = 1;
    NSInteger rows = (n + cols - 1) / cols;
    CGFloat gap = 12;
    CGFloat top = 42;
    CGFloat cardW = (W - 20 * 2 - gap * (cols - 1)) / cols;
    CGFloat cardH = (H - top - 12 - gap * (rows - 1)) / rows;
    for (NSInteger i = 0; i < n; i++) {
        NSInteger col = i % cols;
        NSInteger row = i / cols;
        CGRect frame = CGRectMake(20 + col * (cardW + gap), top + row * (cardH + gap), cardW, cardH);
        [self.board addSubview:[self cardFor:self.holdings[i] frame:frame]];
    }
}

- (UIView *)cardFor:(ZJHolding *)h frame:(CGRect)frame {
    UIView *card = [[UIView alloc] initWithFrame:frame];
    card.backgroundColor = ZJCard();
    card.layer.cornerRadius = 16;
    NSDictionary *q = [ZJStore quoteForCode:h.code];
    double price = [q[@"price"] doubleValue];
    double pct = [q[@"percent"] doubleValue];
    BOOL has = price > 0;
    CGFloat hgt = frame.size.height;
    UILabel *name = ZJLabel(h.name.length ? h.name : h.code, hgt * 0.16, UIFontWeightSemibold, ZJText());
    UILabel *px = ZJLabel(has ? ZJGrouped(price) : @"—", hgt * 0.26, UIFontWeightBold, has ? ZJMove(pct) : ZJDim());
    UILabel *mv = ZJLabel(has ? ZJPct(pct) : h.code, hgt * 0.16, UIFontWeightSemibold, has ? ZJMove(pct) : ZJDim());
    NSString *pnl = @"";
    UIColor *pnlColor = ZJDim();
    if (has && h.buyPrice > 0 && h.shares > 0) {
        double total = (price - h.buyPrice) * h.shares;
        pnl = [NSString stringWithFormat:@"一共 %@", ZJSigned(total)];
        pnlColor = ZJMove(total);
    } else if (has && h.buyPrice > 0) {
        double one = price - h.buyPrice;
        pnl = [NSString stringWithFormat:@"每股 %@", ZJSigned(one)];
        pnlColor = ZJMove(one);
    } else if (has) {
        pnl = @"未设买入价";
    }
    UILabel *pl = ZJLabel(pnl, hgt * 0.13, UIFontWeightMedium, pnlColor);
    CGFloat y = hgt * 0.06;
    name.frame = CGRectMake(8, y, frame.size.width - 16, hgt * 0.18);
    px.frame = CGRectMake(8, CGRectGetMaxY(name.frame), frame.size.width - 16, hgt * 0.38);
    mv.frame = CGRectMake(8, CGRectGetMaxY(px.frame), frame.size.width - 16, hgt * 0.16);
    pl.frame = CGRectMake(8, CGRectGetMaxY(mv.frame), frame.size.width - 16, hgt * 0.16);
    [card addSubview:name];
    [card addSubview:px];
    [card addSubview:mv];
    [card addSubview:pl];
    return card;
}

- (void)renderDetail:(ZJHolding *)h {
    CGFloat W = self.board.bounds.size.width;
    CGFloat H = self.board.bounds.size.height;
    NSDictionary *q = [ZJStore quoteForCode:h.code];
    double price = [q[@"price"] doubleValue];
    double pct = [q[@"percent"] doubleValue];
    double change = [q[@"change"] doubleValue];
    BOOL has = price > 0;
    BOOL bought = h.buyPrice > 0;
    CGFloat y = H * 0.03;
    CGFloat inset = 24;
    UILabel *session = ZJLabel([ZJStore sessionTitle], 22, UIFontWeightMedium, ZJDim());
    UILabel *name = ZJLabel(h.name.length ? h.name : h.code, H * 0.08, UIFontWeightSemibold, ZJText());
    UILabel *code = ZJLabel(h.code, H * 0.045, UIFontWeightMedium, ZJDim());
    UILabel *px = ZJLabel(has ? ZJGrouped(price) : @"—", H * (bought ? 0.22 : 0.30), UIFontWeightBold, has ? ZJMove(pct) : ZJDim());
    NSString *moveText = has ? [NSString stringWithFormat:@"%@    %@", ZJSigned(change), ZJPct(pct)] : (self.lastError ?: @"正在读取");
    UILabel *mv = ZJLabel(moveText, H * (bought ? 0.075 : 0.10), UIFontWeightBold, has ? ZJMove(pct) : ZJDim());
    NSArray *labels = @[session, name, code, px, mv];
    NSArray *heights = @[
        @(H * 0.06), @(H * 0.09), @(H * 0.05),
        @(H * (bought ? 0.30 : 0.42)),
        @(H * (bought ? 0.11 : 0.16)),
    ];
    for (NSInteger i = 0; i < (NSInteger)labels.count; i++) {
        UILabel *label = labels[i];
        CGFloat lh = [heights[i] doubleValue];
        label.frame = CGRectMake(inset, y, W - inset * 2, lh);
        [self.board addSubview:label];
        y += lh;
    }
    if (!bought || !has) {
        UILabel *hint = ZJLabel(has ? @"设置买入价后显示赚了多少" : @"", 22, UIFontWeightMedium, ZJDim());
        hint.frame = CGRectMake(inset, y + 8, W - inset * 2, H * 0.06);
        [self.board addSubview:hint];
    } else {
        double one = price - h.buyPrice;
        double yield = one / h.buyPrice * 100.0;
        UILabel *buy = ZJLabel([NSString stringWithFormat:@"买入价  %@", ZJGrouped(h.buyPrice)], H * 0.055, UIFontWeightMedium, ZJText());
        UILabel *per = ZJLabel([NSString stringWithFormat:@"每股 %@    %@", ZJSigned(one), ZJPct(yield)], H * 0.07, UIFontWeightSemibold, ZJMove(one));
        [self.board addSubview:buy];
        [self.board addSubview:per];
        buy.frame = CGRectMake(inset, y, W - inset * 2, H * 0.07);
        y += H * 0.07;
        per.frame = CGRectMake(inset, y, W - inset * 2, H * 0.08);
        y += H * 0.08;
        if (h.shares > 0) {
            double total = one * h.shares;
            UILabel *all = ZJLabel([NSString stringWithFormat:@"%@ 股    一共 %@", ZJSharesText(h.shares), ZJSigned(total)], H * 0.08, UIFontWeightBold, ZJMove(total));
            all.frame = CGRectMake(inset, y, W - inset * 2, H * 0.09);
            [self.board addSubview:all];
        }
    }
    NSString *stamp = [self stamp:q];
    if (stamp.length) {
        UILabel *foot = ZJLabel(stamp, 16, UIFontWeightMedium, ZJDim());
        foot.frame = CGRectMake(inset, H - 36, W - inset * 2, 24);
        [self.board addSubview:foot];
    }
}

@end
