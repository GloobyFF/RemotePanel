#import "RPKioskRootVC.h"
#import "RPTheme.h"
#import "RPAPIClient.h"
#import "RPPhotoSource.h"
#import "RPPages.h"
#import "RPLocalFeed.h"
#import <AudioToolbox/AudioToolbox.h>
#import <Photos/Photos.h>
#import <math.h>

static NSString * const kBaseURLKey = @"RemotePanel.baseURL";
static NSString * const kDwellOverrideKey = @"RemotePanel.dwellOverride";
static NSString * const kAlbumIdKey = @"RemotePanel.albumLocalId";
static NSString * const kPageEnabledPrefix = @"RemotePanel.page.enabled.";
static NSString * const kPageDwellPrefix = @"RemotePanel.page.dwell.";
static NSString * const kProxyKey = @"RemotePanel.httpProxy";
static NSString * const kSourceURLPrefix = @"RemotePanel.source.url.";
static NSString * const kSourceProxyPrefix = @"RemotePanel.source.proxy.";
static NSString * const kDefaultBaseURL = @"http://192.168.28.12:9121";
static NSString * const kDefaultProxy = @"socks5h://192.168.28.77:1080";

static NSDictionary *RPSourceDefaults(void) { return RPLocalSourceDefaults(); }
static BOOL RPDefaultUseProxy(NSString *pid) { return RPLocalDefaultUseProxy(pid); }

@interface RPPageDef : NSObject
@property (nonatomic, copy) NSString *pid;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) NSInteger dwell; // template default
@property (nonatomic, assign) BOOL enabled;
@end
@implementation RPPageDef
@end

@interface RPKioskRootVC () <UITextFieldDelegate, UIScrollViewDelegate>
@property (nonatomic, strong) NSArray<RPPageDef *> *allDefs;   // master roster
@property (nonatomic, strong) NSArray<RPPageDef *> *pages;     // enabled only
@property (nonatomic, assign) NSInteger index;
@property (nonatomic, strong) UIViewController<RPPage> *currentPage;
@property (nonatomic, strong) UIView *chrome;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *clockLabel;
@property (nonatomic, strong) UILabel *indexLabel;
@property (nonatomic, strong) UILabel *statusPill;
@property (nonatomic, strong) UIButton *logBtn;
@property (nonatomic, strong) UIButton *bellBtn;
@property (nonatomic, strong) UILabel *bellBadge;
@property (nonatomic, strong) UIView *toast;
@property (nonatomic, strong) UILabel *toastLabel;
@property (nonatomic, assign) NSInteger toastToken;
@property (nonatomic, assign) NSInteger unreadCount;
@property (nonatomic, assign) NSInteger activityEpoch;
@property (nonatomic, assign) BOOL tickerSoundReady;
@property (nonatomic, strong) NSMutableSet *seenTickerKeys;
@property (nonatomic, assign) BOOL pageTransitioning;
@property (nonatomic, assign) NSInteger transitionToken;
@property (nonatomic, strong) UIView *overlayDim;
@property (nonatomic, strong) UIButton *settingsBtn;
@property (nonatomic, strong) UIView *progressTrack;
@property (nonatomic, strong) UIView *progressFill;
@property (nonatomic, strong) NSLayoutConstraint *progressWidth;
@property (nonatomic, strong) UIView *pageHost;
@property (nonatomic, strong) RPAPIClient *api;
@property (nonatomic, strong) RPPhotoSource *photos;
@property (nonatomic, strong) NSDictionary *lastState;
@property (nonatomic, copy) NSString *baseURL;
@property (nonatomic, assign) NSInteger dwellOverride; // 0 = use per-page
@property (nonatomic, strong) NSTimer *dwellTimer;
@property (nonatomic, strong) NSTimer *tickTimer;
@property (nonatomic, strong) NSTimer *pollTimer;
@property (nonatomic, assign) NSTimeInterval dwellTotal;
@property (nonatomic, assign) NSTimeInterval dwellLeft;
@property (nonatomic, assign) BOOL stale;
@property (nonatomic, strong) UIView *settingsDim;
@property (nonatomic, strong) UIView *settingsSheet;
@property (nonatomic, strong) UIScrollView *settingsScroll;
@property (nonatomic, strong) UITextField *baseField;
@property (nonatomic, strong) UITextField *proxyField;
@property (nonatomic, strong) UITextField *tickerField;
@property (nonatomic, strong) UISwitch *tickerProxySwitch;
@property (nonatomic, strong) UISegmentedControl *tickerRefreshControl;
@property (nonatomic, strong) UITextField *vpsURLField;
@property (nonatomic, strong) UITextField *vpsTokenField;
@property (nonatomic, strong) UITextField *helloKeyField;
@property (nonatomic, strong) UITextField *helloModelField;
@property (nonatomic, strong) UISwitch *vpsProxySwitch;
@property (nonatomic, strong) UISegmentedControl *vpsRefreshControl;
@property (nonatomic, strong) UITextField *dwellField;
@property (nonatomic, strong) UILabel *albumLabel;
@property (nonatomic, strong) NSMutableArray *pageEnableSwitches; // UISwitch
@property (nonatomic, strong) NSMutableArray *pageDwellFields;    // UITextField
@property (nonatomic, strong) NSMutableArray *pageURLFields;      // UITextField or NSNull
@property (nonatomic, strong) NSMutableArray *pageProxySwitches;  // UISwitch or NSNull
@property (nonatomic, strong) NSMutableArray *pageRefreshControls; // UISegmentedControl or NSNull
@property (nonatomic, strong) NSMutableArray *settingsDefs;       // RPPageDef mirrors
@property (nonatomic, copy) NSString *themeDayName;
@end

@implementation RPKioskRootVC

- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
- (BOOL)shouldAutorotate { return YES; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [RPTheme bg];
    self.automaticallyAdjustsScrollViewInsets = NO;
    self.edgesForExtendedLayout = UIRectEdgeAll;

    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *saved = [ud stringForKey:kBaseURLKey];
    self.baseURL = saved.length ? saved : kDefaultBaseURL;
    self.dwellOverride = [ud integerForKey:kDwellOverrideKey];
    self.api = [[RPAPIClient alloc] initWithBaseURL:self.baseURL];
    self.photos = [[RPPhotoSource alloc] init];
    self.photos.albumLocalIdentifier = [ud stringForKey:kAlbumIdKey];

    [self buildMasterRoster];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(rpModalStateChanged:) name:@"RPPageModalState" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onCapturePage:) name:@"RPCapturePage" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onCollectAlbums:) name:@"RPCollectAlbums" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onRemoteSettings) name:@"RPRemoteSettingsChanged" object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onFeedProgress:) name:RPFeedProgressNotification object:nil];
    [self rebuildEnabledPages];
    [self buildUI];
    [self installGestures];
    self.index = 0;
    [self showPageAtIndex:0 resetDwell:YES];
    [self startClock];
    [self applyTickerMessages:[[RPLocalFeed sharedFeed] tickerMessages]];
    [self pollNow];
    self.pollTimer = [NSTimer scheduledTimerWithTimeInterval:30.0 target:self selector:@selector(pollNow) userInfo:nil repeats:YES];
}

- (void)buildMasterRoster {
    // Native roster — printer merged to one dense page
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    for (NSString *gone in @[@"system", @"weather-weekly", @"vps"]) {
        [ud setBool:NO forKey:[kPageEnabledPrefix stringByAppendingString:gone]];
    }
    NSMutableArray *arr = [NSMutableArray array];
    for (NSDictionary *r in RPLocalPageCatalog()) {
        RPPageDef *d = [[RPPageDef alloc] init];
        d.pid = r[@"id"];
        d.title = r[@"title"];
        d.dwell = [r[@"dwell"] integerValue];
        NSString *ek = [kPageEnabledPrefix stringByAppendingString:d.pid];
        if ([ud objectForKey:ek] == nil) d.enabled = YES;
        else d.enabled = [ud boolForKey:ek];
        NSInteger pd = [ud integerForKey:[kPageDwellPrefix stringByAppendingString:d.pid]];
        if (pd > 0) d.dwell = pd;
        [arr addObject:d];
    }
    self.allDefs = arr;
}

- (void)rebuildEnabledPages {
    NSMutableArray *en = [NSMutableArray array];
    for (RPPageDef *d in self.allDefs) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        NSString *ek = [kPageEnabledPrefix stringByAppendingString:d.pid];
        if ([ud objectForKey:ek] == nil) d.enabled = YES;
        else d.enabled = [ud boolForKey:ek];
        if (d.enabled) [en addObject:d];
    }
    if (en.count == 0 && self.allDefs.count) {
        // Never allow empty rotate — force first page on
        RPPageDef *d = self.allDefs[0];
        d.enabled = YES;
        [en addObject:d];
    }
    self.pages = en;
}

- (NSInteger)storedDwellForPid:(NSString *)pid template:(NSInteger)tmpl {
    NSInteger pd = [[NSUserDefaults standardUserDefaults] integerForKey:[kPageDwellPrefix stringByAppendingString:pid]];
    if (pd > 0) return pd;
    return tmpl;
}

- (void)styleChromeIcon:(UIButton *)button color:(UIColor *)color action:(SEL)action {
    button.titleLabel.font = [UIFont systemFontOfSize:34];
    button.titleLabel.lineBreakMode = NSLineBreakByClipping;
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.5;
    button.titleLabel.textAlignment = NSTextAlignmentCenter;
    button.contentEdgeInsets = UIEdgeInsetsZero;
    button.titleEdgeInsets = UIEdgeInsetsZero;
    [button setTitleColor:color forState:UIControlStateNormal];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [button setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
}

- (void)buildUI {
    self.chrome = [[UIView alloc] init];
    self.chrome.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.chrome];

    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.font = [RPTheme title:36];
    self.titleLabel.textColor = [RPTheme text];
    self.titleLabel.adjustsFontSizeToFitWidth = YES;
    self.titleLabel.minimumScaleFactor = 0.55;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.chrome addSubview:self.titleLabel];

    self.settingsBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.settingsBtn setTitle:@"⚙" forState:UIControlStateNormal];
    [self styleChromeIcon:self.settingsBtn color:[RPTheme accent] action:@selector(showSettings)];
    [self.chrome addSubview:self.settingsBtn];

    self.clockLabel = [[UILabel alloc] init];
    self.clockLabel.font = [RPTheme mono:22];
    self.clockLabel.textColor = [RPTheme textDim];
    self.clockLabel.textAlignment = NSTextAlignmentRight;
    self.clockLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.chrome addSubview:self.clockLabel];

    self.indexLabel = [[UILabel alloc] init];
    self.indexLabel.font = [RPTheme mono:18];
    self.indexLabel.textColor = [RPTheme accent];
    self.indexLabel.textAlignment = NSTextAlignmentRight;
    self.indexLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.chrome addSubview:self.indexLabel];

    self.statusPill = [[UILabel alloc] init];
    self.statusPill.font = [RPTheme small:16];
    self.statusPill.textColor = [UIColor blackColor];
    self.statusPill.backgroundColor = [RPTheme ok];
    self.statusPill.text = @" LIVE ";
    self.statusPill.textAlignment = NSTextAlignmentCenter;
    self.statusPill.layer.cornerRadius = 4;
    self.statusPill.clipsToBounds = YES;
    self.statusPill.translatesAutoresizingMaskIntoConstraints = NO;
    [self.chrome addSubview:self.statusPill];

    self.logBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.logBtn setTitle:@"☰" forState:UIControlStateNormal];
    [self styleChromeIcon:self.logBtn color:[RPTheme textDim] action:@selector(showUpdateLog)];
    [self.chrome addSubview:self.logBtn];

    self.bellBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.bellBtn setTitle:@"✉" forState:UIControlStateNormal];
    [self styleChromeIcon:self.bellBtn color:[RPTheme accent] action:@selector(showTickerDetail)];
    [self.chrome addSubview:self.bellBtn];
    self.bellBadge = [[UILabel alloc] initWithFrame:CGRectMake(30, 0, 20, 18)];
    self.bellBadge.backgroundColor = [RPTheme bad];
    self.bellBadge.textColor = [UIColor whiteColor];
    self.bellBadge.font = [UIFont boldSystemFontOfSize:10];
    self.bellBadge.textAlignment = NSTextAlignmentCenter;
    self.bellBadge.layer.cornerRadius = 8;
    self.bellBadge.clipsToBounds = YES;
    self.bellBadge.hidden = YES;
    [self.bellBtn addSubview:self.bellBadge];

    self.pageHost = [[UIView alloc] init];
    self.pageHost.translatesAutoresizingMaskIntoConstraints = NO;
    self.pageHost.backgroundColor = [UIColor clearColor];
    self.pageHost.clipsToBounds = YES;
    [self.view addSubview:self.pageHost];

    self.toast = [[UIView alloc] initWithFrame:CGRectZero];
    self.toast.backgroundColor = [RPTheme tintOrange];
    self.toast.layer.cornerRadius = 16;
    self.toast.layer.borderWidth = 2;
    self.toast.layer.borderColor = [UIColor whiteColor].CGColor;
    self.toast.hidden = YES;
    self.toast.userInteractionEnabled = YES;
    [self.view addSubview:self.toast];
    self.toastLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.toastLabel.font = [RPTheme body:20];
    self.toastLabel.textColor = [UIColor whiteColor];
    self.toastLabel.numberOfLines = 2;
    [self.toast addSubview:self.toastLabel];
    UITapGestureRecognizer *toastTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(showTickerDetail)];
    [self.toast addGestureRecognizer:toastTap];

    self.progressTrack = [[UIView alloc] init];
    self.progressTrack.backgroundColor = [RPTheme cardBorder];
    self.progressTrack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.progressTrack];
    self.progressFill = [[UIView alloc] init];
    self.progressFill.backgroundColor = [RPTheme accent];
    self.progressFill.translatesAutoresizingMaskIntoConstraints = NO;
    [self.progressTrack addSubview:self.progressFill];

    NSDictionary *views = NSDictionaryOfVariableBindings(_chrome, _pageHost, _progressTrack, _titleLabel, _clockLabel, _indexLabel, _statusPill, _progressFill, _settingsBtn, _logBtn, _bellBtn);
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-16-[_chrome]-16-|" options:0 metrics:nil views:views]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[_pageHost]-0-|" options:0 metrics:nil views:views]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[_progressTrack]-0-|" options:0 metrics:nil views:views]];
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-8-[_chrome(72)][_pageHost]-0-[_progressTrack(4)]-0-|" options:0 metrics:nil views:views]];
    [self.titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self.indexLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    self.indexLabel.adjustsFontSizeToFitWidth = YES;
    self.indexLabel.minimumScaleFactor = 0.7;
    [self.chrome addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_titleLabel]-(6)-[_statusPill(72)]-4-[_indexLabel(120)]-4-[_clockLabel(188)]-4-[_bellBtn(56)]-2-[_logBtn(56)]-2-[_settingsBtn(56)]|" options:NSLayoutFormatAlignAllCenterY metrics:nil views:views]];
    [self.chrome addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_titleLabel]|" options:0 metrics:nil views:views]];
    [self.progressTrack addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_progressFill]|" options:0 metrics:nil views:views]];
    [self.progressTrack addConstraint:[NSLayoutConstraint constraintWithItem:self.progressFill attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:self.progressTrack attribute:NSLayoutAttributeLeading multiplier:1 constant:0]];
    self.progressWidth = [NSLayoutConstraint constraintWithItem:self.progressFill attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:self.progressTrack attribute:NSLayoutAttributeWidth multiplier:0 constant:0];
    [self.view addConstraint:self.progressWidth];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.toast.hidden) [self placeToast];
}

- (void)onFeedProgress:(NSNotification *)note {
    NSDictionary *info = note.userInfo;
    NSString *name = info[@"name"] ?: @"";
    NSString *status = info[@"status"] ?: @"";
    NSString *detail = info[@"detail"] ?: @"";
    if ([status isEqualToString:@"start"]) {
        [self.logBtn setTitleColor:[RPTheme accent] forState:UIControlStateNormal];
        self.statusPill.text = @"更新";
        self.statusPill.backgroundColor = [RPTheme accent];
    } else if ([status isEqualToString:@"fail"]) {
        [self.logBtn setTitleColor:[RPTheme bad] forState:UIControlStateNormal];
        self.statusPill.text = @" FAIL ";
        self.statusPill.backgroundColor = [RPTheme bad];
    } else if ([status isEqualToString:@"ok"]) {
        [self.logBtn setTitleColor:[RPTheme ok] forState:UIControlStateNormal];
        self.activityEpoch += 1;
        NSInteger epoch = self.activityEpoch;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (!weakSelf || epoch != weakSelf.activityEpoch) return;
            [weakSelf.logBtn setTitleColor:[RPTheme textDim] forState:UIControlStateNormal];
        });
        NSDictionary *state = info[@"state"];
        if ([state isKindOfClass:[NSDictionary class]] && state.count) {
            self.lastState = state;
            [self.currentPage applyState:state baseURL:@""];
        }
    } else if ([status isEqualToString:@"skip"]) {
        [self.logBtn setTitleColor:[RPTheme textDim] forState:UIControlStateNormal];
        (void)detail;
    }
    if ([name isEqualToString:@"走马灯"]) [self applyTickerMessages:[[RPLocalFeed sharedFeed] tickerMessages]];
}

- (void)refreshBell {
    self.bellBadge.hidden = self.unreadCount <= 0;
    self.bellBadge.text = self.unreadCount > 9 ? @"9+" : [NSString stringWithFormat:@"%ld", (long)self.unreadCount];
}

- (void)placeToast {
    CGFloat maxW = MIN(560, self.view.bounds.size.width - 80);
    CGSize fit = [self.toastLabel sizeThatFits:CGSizeMake(maxW - 36, 80)];
    CGFloat w = MIN(maxW, MAX(180, fit.width + 36));
    CGFloat h = MIN(84, MAX(52, fit.height + 20));
    CGFloat y = CGRectGetMaxY(self.chrome.frame) + 14;
    self.toast.frame = CGRectMake((self.view.bounds.size.width - w) / 2.0, y, w, h);
    self.toastLabel.frame = CGRectMake(18, 8, w - 36, h - 16);
}

- (void)showToast:(NSString *)text {
    if (text.length == 0) return;
    self.toastToken += 1;
    NSInteger token = self.toastToken;
    self.toastLabel.text = text;
    self.toast.hidden = NO;
    self.toast.alpha = 0;
    self.toast.transform = CGAffineTransformMakeTranslation(0, -24);
    [self placeToast];
    [self.view bringSubviewToFront:self.toast];
    [UIView animateWithDuration:0.35 animations:^{
        self.toast.alpha = 1;
        self.toast.transform = CGAffineTransformIdentity;
    }];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!weakSelf || token != weakSelf.toastToken) return;
        [UIView animateWithDuration:0.35 animations:^{
            weakSelf.toast.alpha = 0;
            weakSelf.toast.transform = CGAffineTransformMakeTranslation(0, -16);
        } completion:^(BOOL finished) {
            if (!weakSelf || token != weakSelf.toastToken) return;
            weakSelf.toast.hidden = YES;
            weakSelf.toast.transform = CGAffineTransformIdentity;
            (void)finished;
        }];
    });
}

- (void)applyTickerMessages:(NSArray *)messages {
    NSMutableArray *keys = [NSMutableArray array];
    NSString *freshTitle = nil;
    NSInteger freshCount = 0;
    for (NSDictionary *item in messages) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *title = [item[@"title"] isKindOfClass:[NSString class]] ? item[@"title"] : @"";
        NSString *body = [item[@"body"] isKindOfClass:[NSString class]] ? item[@"body"] : @"";
        if (title.length == 0 && body.length == 0) continue;
        NSString *key = [NSString stringWithFormat:@"%@\n%@", title, body];
        [keys addObject:key];
        if (self.tickerSoundReady && self.seenTickerKeys && ![self.seenTickerKeys containsObject:key]) {
            freshCount++;
            if (!freshTitle) freshTitle = title.length ? title : body;
        }
    }
    if (!self.seenTickerKeys) self.seenTickerKeys = [NSMutableSet set];
    [self.seenTickerKeys addObjectsFromArray:keys];
    BOOL announce = self.tickerSoundReady && freshCount > 0;
    self.tickerSoundReady = YES;
    if (!announce) return;
    AudioServicesPlaySystemSound(1007);
    self.unreadCount += freshCount;
    [self refreshBell];
    [self showToast:freshTitle];
}

- (void)showUpdateLog {
    if (self.overlayDim) return;
    NSArray *lines = [[RPLocalFeed sharedFeed] activityLog];
    NSString *text = lines.count ? [[lines reverseObjectEnumerator].allObjects componentsJoinedByString:@"\n"] : @"还没有更新记录。";
    [self presentOverlayTitle:@"更新日志" text:text];
}

- (void)showTickerDetail {
    if (self.overlayDim) return;
    self.unreadCount = 0;
    [self refreshBell];
    self.toastToken += 1;
    self.toast.hidden = YES;
    NSArray *messages = [[RPLocalFeed sharedFeed] tickerMessages];
    NSMutableString *text = [NSMutableString string];
    for (NSDictionary *item in messages) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *title = [item[@"title"] isKindOfClass:[NSString class]] ? item[@"title"] : @"";
        NSString *body = [item[@"body"] isKindOfClass:[NSString class]] ? item[@"body"] : title;
        if (text.length) [text appendString:@"\n\n"];
        [text appendFormat:@"%@\n%@", title, body ?: @""];
    }
    if (text.length == 0) [text setString:@"没有消息。"];
    [self presentOverlayTitle:@"公告" text:text];
}

- (void)presentOverlayTitle:(NSString *)title text:(NSString *)text {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RPPageModalState" object:nil userInfo:@{@"open": @YES}];
    self.overlayDim = [[UIView alloc] initWithFrame:self.view.bounds];
    self.overlayDim.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.overlayDim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.62];
    [self.view addSubview:self.overlayDim];
    CGFloat w = MIN(760, self.view.bounds.size.width - 40);
    CGFloat h = self.view.bounds.size.height - 70;
    UIView *sheet = [[UIView alloc] initWithFrame:CGRectMake((self.view.bounds.size.width-w)/2, 28, w, h)];
    sheet.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight|UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin;
    sheet.backgroundColor = [RPTheme card];
    sheet.layer.cornerRadius = 14;
    sheet.clipsToBounds = YES;
    [self.overlayDim addSubview:sheet];
    UILabel *heading = [[UILabel alloc] initWithFrame:CGRectMake(18, 12, w-120, 32)];
    heading.font = [RPTheme title:22];
    heading.textColor = [RPTheme text];
    heading.text = title;
    [sheet addSubview:heading];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.frame = CGRectMake(w-90, 10, 74, 34);
    close.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    close.titleLabel.font = [RPTheme title:18];
    [close setTitleColor:[RPTheme accent] forState:UIControlStateNormal];
    [close addTarget:self action:@selector(hideOverlay) forControlEvents:UIControlEventTouchUpInside];
    [sheet addSubview:close];
    UITextView *body = [[UITextView alloc] initWithFrame:CGRectMake(12, 52, w-24, h-64)];
    body.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    body.backgroundColor = [RPTheme bg];
    body.textColor = [RPTheme text];
    body.font = [RPTheme body:18];
    body.editable = NO;
    body.text = text;
    body.layer.cornerRadius = 8;
    [sheet addSubview:body];
}

- (void)hideOverlay {
    [self.overlayDim removeFromSuperview];
    self.overlayDim = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RPPageModalState" object:nil userInfo:@{@"open": @NO}];
}

- (void)installGestures {
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onLongPress:)];
    lp.minimumPressDuration = 0.85;
    [self.view addGestureRecognizer:lp];
    UITapGestureRecognizer *left = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTap:)];
    [self.view addGestureRecognizer:left];
}

- (void)onTap:(UITapGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateEnded) return;
    if (self.settingsDim || self.overlayDim) return;
    CGPoint p = [gr locationInView:self.view];
    if (!self.toast.hidden && CGRectContainsPoint(self.toast.frame, p)) return;
    CGPoint inChrome = [self.view convertPoint:p toView:self.chrome];
    if (CGRectContainsPoint(self.settingsBtn.frame, inChrome) || CGRectContainsPoint(self.logBtn.frame, inChrome) || CGRectContainsPoint(self.bellBtn.frame, inChrome)) return;
    if (p.x < self.view.bounds.size.width * 0.28) {
        [self prevPage];
    } else if (p.x > self.view.bounds.size.width * 0.72) {
        [self nextPage];
    }
}

- (void)onLongPress:(UILongPressGestureRecognizer *)gr {
    if (gr.state == UIGestureRecognizerStateBegan) [self showSettings];
}

#pragma mark - Pages

- (void)showPageAtIndex:(NSInteger)idx resetDwell:(BOOL)reset {
    self.transitionToken += 1;
    self.pageTransitioning = NO;
    if (self.pages.count == 0) return;
    if (idx < 0) idx = self.pages.count - 1;
    if (idx >= (NSInteger)self.pages.count) idx = 0;
    self.index = idx;
    RPPageDef *def = self.pages[idx];

    if (self.currentPage) {
        [self.currentPage pageDidDisappear];
        [self.currentPage willMoveToParentViewController:nil];
        [self.currentPage.view removeFromSuperview];
        [self.currentPage removeFromParentViewController];
        self.currentPage = nil;
    }

    UIViewController<RPPage> *page = [RPPageFactory pageForId:def.pid title:def.title];
    if ([page respondsToSelector:@selector(setPhotoSource:slot:)]) {
        NSInteger slot = [def.pid hasSuffix:@"-2"] ? 1 : 0;
        [page setPhotoSource:self.photos slot:slot];
    }
    [self addChildViewController:page];
    page.view.frame = self.pageHost.bounds;
    page.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.pageHost addSubview:page.view];
    [page.view layoutIfNeeded];
    [page didMoveToParentViewController:self];
    self.currentPage = page;
    self.titleLabel.text = def.title;
    self.indexLabel.text = [NSString stringWithFormat:@"%ld/%lu · %lds", (long)(idx+1), (unsigned long)self.pages.count, (long)[self dwellForDef:def]];
    if (self.lastState) [page applyState:self.lastState baseURL:self.baseURL];
    [page pageWillAppear];

    if (reset) [self restartDwell];
}

- (NSInteger)dwellForDef:(RPPageDef *)def {
    if (self.dwellOverride > 0) return self.dwellOverride;
    return MAX(8, [self storedDwellForPid:def.pid template:def.dwell]);
}

- (void)restartDwell {
    [self.dwellTimer invalidate];
    if (self.pages.count == 0) return;
    RPPageDef *def = self.pages[self.index];
    self.dwellTotal = [self dwellForDef:def];
    self.dwellLeft = self.dwellTotal;
    self.dwellTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self selector:@selector(dwellTick) userInfo:nil repeats:YES];
    [self updateProgress];
}

- (void)dwellTick {
    if (self.pageTransitioning) return;
    self.dwellLeft -= 0.25;
    if (self.dwellLeft <= 2.4) {
        [self nextPage];
        return;
    }
    [self updateProgress];
    self.indexLabel.text = [NSString stringWithFormat:@"%ld/%lu · %.0fs", (long)(self.index+1), (unsigned long)self.pages.count, ceil(self.dwellLeft)];
}

- (void)updateProgress {
    CGFloat p = (self.dwellTotal > 0) ? (1.0 - self.dwellLeft/self.dwellTotal) : 0;
    if (p < 0) p = 0; if (p > 1) p = 1;
    [self.view removeConstraint:self.progressWidth];
    self.progressWidth = [NSLayoutConstraint constraintWithItem:self.progressFill attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:self.progressTrack attribute:NSLayoutAttributeWidth multiplier:p constant:0];
    [self.view addConstraint:self.progressWidth];
}

- (void)turnBy:(NSInteger)delta {
    if (self.pageTransitioning || self.pages.count == 0 || self.settingsDim || self.overlayDim) return;
    NSInteger idx = self.index + delta;
    self.pageTransitioning = YES;
    [self.dwellTimer invalidate];
    self.dwellTimer = nil;
    NSInteger token = ++self.transitionToken;
    __weak typeof(self) weakSelf = self;
    void (^go)(void) = ^{
        if (!weakSelf || token != weakSelf.transitionToken) return;
        weakSelf.pageTransitioning = NO;
        [weakSelf showPageAtIndex:idx resetDwell:YES];
    };
    if ([self.currentPage isKindOfClass:[RPBasePageVC class]]) {
        [(RPBasePageVC *)self.currentPage playPageOutro:go];
    } else {
        go();
    }
}
- (void)nextPage { [self turnBy:1]; }
- (void)prevPage { [self turnBy:-1]; }

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    static CGSize sLastHostSize;
    CGSize sz = self.pageHost.bounds.size;
    BOOL sizeChanged = (fabs(sLastHostSize.width - sz.width) > 0.5 || fabs(sLastHostSize.height - sz.height) > 0.5);
    if (sizeChanged && self.currentPage && self.lastState && sz.width > 1 && sz.height > 1) {
        sLastHostSize = sz;
        [self.currentPage applyState:self.lastState baseURL:self.baseURL];
        if ([self.currentPage isKindOfClass:[RPBasePageVC class]]) {
            [(RPBasePageVC *)self.currentPage playPageIntro];
        }
    }
}

#pragma mark - Poll / clock

- (void)startClock {
    [self updateClock];
    self.tickTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateClock) userInfo:nil repeats:YES];
}

- (void)updateClock {
    NSString *day = [RPTheme dayName];
    if (self.themeDayName.length && ![self.themeDayName isEqualToString:day]) {
        self.view.backgroundColor = [RPTheme bg];
        self.progressTrack.backgroundColor = [RPTheme cardBorder];
        self.progressFill.backgroundColor = [RPTheme accent];
        self.titleLabel.textColor = [RPTheme text];
        self.clockLabel.textColor = [RPTheme textDim];
        self.indexLabel.textColor = [RPTheme accent];
        [self.settingsBtn setTitleColor:[RPTheme accent] forState:UIControlStateNormal];
        [self.bellBtn setTitleColor:[RPTheme accent] forState:UIControlStateNormal];
        [self.logBtn setTitleColor:[RPTheme textDim] forState:UIControlStateNormal];
        if (self.lastState && self.currentPage) [self.currentPage applyState:self.lastState baseURL:self.baseURL ?: @""];
    }
    self.themeDayName = day;
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = @"HH:mm";
    self.clockLabel.text = [NSString stringWithFormat:@"%@ %@", day, [f stringFromDate:[NSDate date]]];
}

- (void)pollNow {
    __weak typeof(self) weakSelf = self;
    if (!self.lastState) {
        self.statusPill.text = @" LOAD ";
        self.statusPill.backgroundColor = [RPTheme accent];
    }
    [[RPLocalFeed sharedFeed] refreshWithCompletion:^(NSDictionary *state, NSError *error) {
        if (state.count) {
            weakSelf.lastState = state;
            weakSelf.stale = NO;
            if (![weakSelf.statusPill.text isEqualToString:@" FAIL "]) {
                weakSelf.statusPill.text = @" LIVE ";
                weakSelf.statusPill.backgroundColor = [RPTheme ok];
            }
            [weakSelf.currentPage applyState:state baseURL:@""];
            [weakSelf applyTickerMessages:[[RPLocalFeed sharedFeed] tickerMessages]];
        } else {
            weakSelf.stale = YES;
            weakSelf.statusPill.text = @" STALE ";
            weakSelf.statusPill.backgroundColor = [RPTheme warn];
        }
        (void)error;
    }];
}

#pragma mark - Settings

- (void)showSettings {
    if (self.settingsDim) return;
    self.settingsDim = [[UIView alloc] initWithFrame:self.view.bounds];
    self.settingsDim.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.settingsDim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    [self.view addSubview:self.settingsDim];

    CGFloat sheetW = MIN(860, self.view.bounds.size.width - 32);
    CGFloat sheetH = self.view.bounds.size.height - 36;
    self.settingsSheet = [[UIView alloc] initWithFrame:CGRectMake((self.view.bounds.size.width-sheetW)/2,
                                                                  (self.view.bounds.size.height-sheetH)/2,
                                                                  sheetW, sheetH)];
    self.settingsSheet.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin;
    self.settingsSheet.backgroundColor = [RPTheme card];
    self.settingsSheet.layer.cornerRadius = 14;
    self.settingsSheet.layer.borderColor = [RPTheme cardBorder].CGColor;
    self.settingsSheet.layer.borderWidth = 1;
    self.settingsSheet.clipsToBounds = YES;
    [self.settingsDim addSubview:self.settingsSheet];

    UILabel *h = [[UILabel alloc] initWithFrame:CGRectMake(20, 12, sheetW-140, 32)];
    h.font = [RPTheme title:24]; h.textColor = [RPTheme text]; h.text = @"设置";
    [self.settingsSheet addSubview:h];

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    done.frame = CGRectMake(sheetW-110, 10, 90, 36);
    [done setTitle:@"完成" forState:UIControlStateNormal];
    done.titleLabel.font = [RPTheme title:18];
    [done setTitleColor:[RPTheme ok] forState:UIControlStateNormal];
    [done addTarget:self action:@selector(saveSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.settingsSheet addSubview:done];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    cancel.frame = CGRectMake(sheetW-200, 10, 80, 36);
    [cancel setTitle:@"取消" forState:UIControlStateNormal];
    cancel.titleLabel.font = [RPTheme title:18];
    [cancel setTitleColor:[RPTheme textDim] forState:UIControlStateNormal];
    [cancel addTarget:self action:@selector(hideSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.settingsSheet addSubview:cancel];

    self.settingsScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 52, sheetW, sheetH-52)];
    self.settingsScroll.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.settingsScroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.settingsSheet addSubview:self.settingsScroll];

    CGFloat y = 8;
    CGFloat contentW = sheetW - 40;

    UILabel *bl = [[UILabel alloc] initWithFrame:CGRectMake(20, y, contentW, 44)];
    bl.font = [RPTheme small:14]; bl.textColor = [RPTheme textDim];
    bl.numberOfLines = 2;
    bl.text = @"本机直接请求下面的接口，不再经过 9121 服务器。";
    [self.settingsScroll addSubview:bl];
    y += 48;

    UILabel *pl = [[UILabel alloc] initWithFrame:CGRectMake(20, y, contentW, 22)];
    pl.font = [RPTheme small:14]; pl.textColor = [RPTheme textDim];
    pl.text = @"HTTP / SOCKS 代理（勾选了「使用代理」的页面才会走这里）";
    [self.settingsScroll addSubview:pl];
    y += 26;
    self.proxyField = [[UITextField alloc] initWithFrame:CGRectMake(20, y, contentW, 40)];
    self.proxyField.backgroundColor = [RPTheme bg];
    self.proxyField.textColor = [RPTheme text];
    self.proxyField.font = [RPTheme mono:15];
    NSString *savedProxy = [[NSUserDefaults standardUserDefaults] stringForKey:kProxyKey];
    self.proxyField.text = savedProxy.length ? savedProxy : kDefaultProxy;
    self.proxyField.placeholder = @"http://主机:端口 或 socks5://主机:端口";
    self.proxyField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.proxyField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.proxyField.keyboardType = UIKeyboardTypeURL;
    self.proxyField.delegate = self;
    self.proxyField.layer.cornerRadius = 6;
    self.proxyField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0,0,8,40)];
    self.proxyField.leftViewMode = UITextFieldViewModeAlways;
    [self.settingsScroll addSubview:self.proxyField];
    y += 52;

    UILabel *tl = [[UILabel alloc] initWithFrame:CGRectMake(20, y, contentW, 22)];
    tl.font = [RPTheme small:14]; tl.textColor = [RPTheme textDim];
    tl.text = @"走马灯消息地址（JSON、纯文本或 RSS。留空则不显示）";
    [self.settingsScroll addSubview:tl];
    y += 26;
    self.tickerField = [[UITextField alloc] initWithFrame:CGRectMake(20, y, contentW - 120, 40)];
    self.tickerField.backgroundColor = [RPTheme bg];
    self.tickerField.textColor = [RPTheme text];
    self.tickerField.font = [RPTheme mono:15];
    self.tickerField.text = [[NSUserDefaults standardUserDefaults] stringForKey:RPTickerURLKey] ?: @"";
    self.tickerField.placeholder = @"https://.../messages.json";
    self.tickerField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.tickerField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.tickerField.keyboardType = UIKeyboardTypeURL;
    self.tickerField.delegate = self;
    self.tickerField.layer.cornerRadius = 6;
    self.tickerField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0,0,8,40)];
    self.tickerField.leftViewMode = UITextFieldViewModeAlways;
    [self.settingsScroll addSubview:self.tickerField];
    UILabel *tproxy = [[UILabel alloc] initWithFrame:CGRectMake(contentW - 70, y + 8, 40, 24)];
    tproxy.font = [RPTheme small:14]; tproxy.textColor = [RPTheme textDim]; tproxy.text = @"代理";
    [self.settingsScroll addSubview:tproxy];
    self.tickerProxySwitch = [[UISwitch alloc] initWithFrame:CGRectMake(contentW - 10, y + 4, 51, 31)];
    self.tickerProxySwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:RPTickerProxyKey];
    self.tickerProxySwitch.onTintColor = [RPTheme tintOrange];
    [self.settingsScroll addSubview:self.tickerProxySwitch];
    y += 48;
    self.tickerRefreshControl = [[UISegmentedControl alloc] initWithItems:RPLocalRefreshChoiceTitles()];
    self.tickerRefreshControl.frame = CGRectMake(20, y, contentW, 32);
    self.tickerRefreshControl.selectedSegmentIndex = RPLocalRefreshChoiceIndex(RPLocalTTL(@"ticker"));
    self.tickerRefreshControl.tintColor = [RPTheme accent];
    [self.settingsScroll addSubview:self.tickerRefreshControl];
    y += 46;

    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    UILabel *vl = [[UILabel alloc] initWithFrame:CGRectMake(20, y, contentW, 22)];
    vl.font = [RPTheme small:14]; vl.textColor = [RPTheme textDim];
    vl.text = @"VPS 流量接口（天气页下方）";
    [self.settingsScroll addSubview:vl];
    y += 26;
    self.vpsURLField = [[UITextField alloc] initWithFrame:CGRectMake(20, y, contentW, 40)];
    self.vpsURLField.backgroundColor = [RPTheme bg];
    self.vpsURLField.textColor = [RPTheme text];
    self.vpsURLField.font = [RPTheme mono:14];
    self.vpsURLField.text = [prefs stringForKey:RPVpsURLKey].length ? [prefs stringForKey:RPVpsURLKey] : RPLocalDefaultVPSURL();
    self.vpsURLField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.vpsURLField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.vpsURLField.keyboardType = UIKeyboardTypeURL;
    self.vpsURLField.delegate = self;
    self.vpsURLField.layer.cornerRadius = 6;
    self.vpsURLField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0,0,8,40)];
    self.vpsURLField.leftViewMode = UITextFieldViewModeAlways;
    [self.settingsScroll addSubview:self.vpsURLField];
    y += 48;
    self.vpsTokenField = [[UITextField alloc] initWithFrame:CGRectMake(20, y, contentW - 150, 40)];
    self.vpsTokenField.backgroundColor = [RPTheme bg];
    self.vpsTokenField.textColor = [RPTheme text];
    self.vpsTokenField.font = [RPTheme mono:14];
    self.vpsTokenField.text = [prefs stringForKey:RPVpsTokenKey].length ? [prefs stringForKey:RPVpsTokenKey] : RPLocalDefaultVPSToken();
    self.vpsTokenField.placeholder = @"Bearer token";
    self.vpsTokenField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.vpsTokenField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.vpsTokenField.delegate = self;
    self.vpsTokenField.layer.cornerRadius = 6;
    self.vpsTokenField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0,0,8,40)];
    self.vpsTokenField.leftViewMode = UITextFieldViewModeAlways;
    [self.settingsScroll addSubview:self.vpsTokenField];
    UILabel *vproxy = [[UILabel alloc] initWithFrame:CGRectMake(contentW - 110, y + 8, 70, 24)];
    vproxy.font = [RPTheme small:14]; vproxy.textColor = [RPTheme textDim]; vproxy.text = @"代理";
    [self.settingsScroll addSubview:vproxy];
    self.vpsProxySwitch = [[UISwitch alloc] initWithFrame:CGRectMake(contentW - 30, y + 4, 51, 31)];
    self.vpsProxySwitch.on = [prefs objectForKey:RPVpsProxyKey] ? [prefs boolForKey:RPVpsProxyKey] : NO;
    self.vpsProxySwitch.onTintColor = [RPTheme tintOrange];
    [self.settingsScroll addSubview:self.vpsProxySwitch];
    y += 48;
    UILabel *vpsEvery = [[UILabel alloc] initWithFrame:CGRectMake(20, y + 4, 70, 28)];
    vpsEvery.font = [RPTheme small:14];
    vpsEvery.textColor = [RPTheme textDim];
    vpsEvery.text = @"流量更新";
    [self.settingsScroll addSubview:vpsEvery];
    self.vpsRefreshControl = [[UISegmentedControl alloc] initWithItems:RPLocalRefreshChoiceTitles()];
    self.vpsRefreshControl.frame = CGRectMake(96, y, contentW - 96, 32);
    self.vpsRefreshControl.selectedSegmentIndex = RPLocalRefreshChoiceIndex(RPLocalTTL(@"vps"));
    self.vpsRefreshControl.tintColor = [RPTheme accent];
    [self.settingsScroll addSubview:self.vpsRefreshControl];
    y += 48;

    UILabel *dl = [[UILabel alloc] initWithFrame:CGRectMake(20, y, contentW, 22)];
    dl.font = [RPTheme small:14]; dl.textColor = [RPTheme textDim];
    dl.text = @"全局停留秒数覆盖 (0=各页各自设置)";
    [self.settingsScroll addSubview:dl];
    y += 26;
    self.dwellField = [[UITextField alloc] initWithFrame:CGRectMake(20, y, 140, 40)];
    self.dwellField.backgroundColor = [RPTheme bg];
    self.dwellField.textColor = [RPTheme text];
    self.dwellField.font = [RPTheme mono:18];
    self.dwellField.keyboardType = UIKeyboardTypeNumberPad;
    self.dwellField.text = [NSString stringWithFormat:@"%ld", (long)self.dwellOverride];
    self.dwellField.layer.cornerRadius = 6;
    self.dwellField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0,0,8,40)];
    self.dwellField.leftViewMode = UITextFieldViewModeAlways;
    [self.settingsScroll addSubview:self.dwellField];
    y += 52;

    self.albumLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, contentW-160, 40)];
    self.albumLabel.font = [RPTheme body:15]; self.albumLabel.textColor = [RPTheme text];
    self.albumLabel.numberOfLines = 2;
    NSString *aid = self.photos.albumLocalIdentifier;
    self.albumLabel.text = aid.length ? [NSString stringWithFormat:@"相册: %@", aid] : @"相册: 默认「个人收藏」或图库";
    [self.settingsScroll addSubview:self.albumLabel];
    UIButton *pick = [UIButton buttonWithType:UIButtonTypeSystem];
    pick.frame = CGRectMake(sheetW-160, y, 140, 40);
    [pick setTitle:@"选择相册" forState:UIControlStateNormal];
    pick.titleLabel.font = [RPTheme title:16];
    [pick setTitleColor:[RPTheme accent] forState:UIControlStateNormal];
    [pick addTarget:self action:@selector(pickAlbum) forControlEvents:UIControlEventTouchUpInside];
    [self.settingsScroll addSubview:pick];
    y += 52;

    UILabel *sec = [[UILabel alloc] initWithFrame:CGRectMake(20, y, contentW, 28)];
    sec.font = [RPTheme title:18]; sec.textColor = [RPTheme accent];
    sec.text = @"页面 · 开关 / 停留 / 数据更新 / 接口 / 代理";
    [self.settingsScroll addSubview:sec];
    y += 34;

    self.pageEnableSwitches = [NSMutableArray array];
    self.pageDwellFields = [NSMutableArray array];
    self.pageURLFields = [NSMutableArray array];
    self.pageProxySwitches = [NSMutableArray array];
    self.pageRefreshControls = [NSMutableArray array];
    self.settingsDefs = [NSMutableArray array];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSDictionary *sourceDefaults = RPSourceDefaults();
    CGFloat rowW = sheetW - 32;
    for (RPPageDef *d in self.allDefs) {
        [self.settingsDefs addObject:d];
        BOOL hasSource = sourceDefaults[d.pid] != nil;
        BOOL greet = [d.pid isEqualToString:@"hello"];
        CGFloat rowH = hasSource ? (greet ? 248 : 156) : 48;
        CGFloat proxyY = greet ? 164 : 84;
        CGFloat refreshY = greet ? 202 : 118;
        UIView *row = [[UIView alloc] initWithFrame:CGRectMake(16, y, rowW, rowH)];
        row.backgroundColor = [RPTheme bg];
        row.layer.cornerRadius = 8;

        UILabel *name = [[UILabel alloc] initWithFrame:CGRectMake(12, 8, rowW-210, 32)];
        name.font = [RPTheme body:16]; name.textColor = [RPTheme text];
        name.text = d.title;
        [row addSubview:name];

        UITextField *df = [[UITextField alloc] initWithFrame:CGRectMake(rowW-168, 8, 64, 32)];
        df.backgroundColor = [RPTheme card];
        df.textColor = [RPTheme text];
        df.font = [RPTheme mono:16];
        df.keyboardType = UIKeyboardTypeNumberPad;
        df.textAlignment = NSTextAlignmentCenter;
        df.layer.cornerRadius = 4;
        NSInteger pd = [ud integerForKey:[kPageDwellPrefix stringByAppendingString:d.pid]];
        df.text = [NSString stringWithFormat:@"%ld", (long)(pd > 0 ? pd : d.dwell)];
        df.placeholder = @"秒";
        [row addSubview:df];
        [self.pageDwellFields addObject:df];

        UILabel *secL = [[UILabel alloc] initWithFrame:CGRectMake(rowW-100, 12, 20, 24)];
        secL.font = [RPTheme small:13]; secL.textColor = [RPTheme textDim]; secL.text = @"秒";
        [row addSubview:secL];

        UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(rowW-74, 8, 51, 31)];
        NSString *ek = [kPageEnabledPrefix stringByAppendingString:d.pid];
        BOOL on = ([ud objectForKey:ek] == nil) ? YES : [ud boolForKey:ek];
        sw.on = on;
        sw.onTintColor = [RPTheme accent];
        [row addSubview:sw];
        [self.pageEnableSwitches addObject:sw];

        if (hasSource) {
            UITextField *urlField = [[UITextField alloc] initWithFrame:CGRectMake(12, 46, rowW-24, 32)];
            urlField.backgroundColor = [RPTheme card];
            urlField.textColor = [RPTheme text];
            urlField.font = [RPTheme mono:13];
            urlField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            urlField.autocorrectionType = UITextAutocorrectionTypeNo;
            urlField.keyboardType = UIKeyboardTypeURL;
            urlField.delegate = self;
            urlField.layer.cornerRadius = 4;
            urlField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0,0,6,32)];
            urlField.leftViewMode = UITextFieldViewModeAlways;
            NSString *savedURL = [ud stringForKey:[kSourceURLPrefix stringByAppendingString:d.pid]];
            urlField.text = savedURL.length ? savedURL : (sourceDefaults[d.pid] ?: @"");
            if ([d.pid isEqualToString:@"weather"]) urlField.placeholder = @"城市名，例如 Shanghai";
            else if ([d.pid isEqualToString:@"schedule"]) urlField.placeholder = @"ICS 订阅，例如 https://.../basic.ics";
            else if ([d.pid isEqualToString:@"x-news"]) urlField.placeholder = @"默认全球热门话题，也可换成 RSS";
            else if ([d.pid isEqualToString:@"xiaohongshu-hot"]) urlField.placeholder = @"小红书热榜页面";
            else if ([d.pid isEqualToString:@"bilibili-hot"]) urlField.placeholder = @"哔哩哔哩热门接口";
            else if ([d.pid isEqualToString:@"print"]) urlField.placeholder = @"打印机 JSON 接口";
            else if ([d.pid isEqualToString:@"stocks-cn"]) urlField.placeholder = @"股票代码，逗号分隔，如 600519,300750";
            else if ([d.pid isEqualToString:@"crypto"]) urlField.placeholder = @"币种，逗号分隔，如 btc,eth,sol";
            else if ([d.pid isEqualToString:@"hello"]) urlField.placeholder = @"AI 接口，例如 https://apiclaude.cc";
            else urlField.placeholder = @"接口地址";
            if ([d.pid isEqualToString:@"stocks-cn"] || [d.pid isEqualToString:@"crypto"]) {
                urlField.keyboardType = UIKeyboardTypeDefault;
            }
            [row addSubview:urlField];
            [self.pageURLFields addObject:urlField];

            if (greet) {
                self.helloKeyField = [[UITextField alloc] initWithFrame:CGRectMake(12, 84, rowW - 24, 32)];
                self.helloKeyField.backgroundColor = [RPTheme card];
                self.helloKeyField.textColor = [RPTheme text];
                self.helloKeyField.font = [RPTheme mono:13];
                self.helloKeyField.autocapitalizationType = UITextAutocapitalizationTypeNone;
                self.helloKeyField.autocorrectionType = UITextAutocorrectionTypeNo;
                self.helloKeyField.placeholder = @"API Key";
                NSString *savedKey = [ud stringForKey:RPHelloKeyKey];
                self.helloKeyField.text = savedKey.length ? savedKey : RPLocalDefaultHelloKey();
                self.helloKeyField.layer.cornerRadius = 4;
                self.helloKeyField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 6, 32)];
                self.helloKeyField.leftViewMode = UITextFieldViewModeAlways;
                self.helloKeyField.delegate = self;
                [row addSubview:self.helloKeyField];
                self.helloModelField = [[UITextField alloc] initWithFrame:CGRectMake(12, 122, rowW - 24, 32)];
                self.helloModelField.backgroundColor = [RPTheme card];
                self.helloModelField.textColor = [RPTheme text];
                self.helloModelField.font = [RPTheme mono:13];
                self.helloModelField.autocapitalizationType = UITextAutocapitalizationTypeNone;
                self.helloModelField.autocorrectionType = UITextAutocorrectionTypeNo;
                self.helloModelField.placeholder = @"模型，例如 gpt-6-astra";
                NSString *savedModel = [ud stringForKey:RPHelloModelKey];
                self.helloModelField.text = savedModel.length ? savedModel : RPLocalDefaultHelloModel();
                self.helloModelField.layer.cornerRadius = 4;
                self.helloModelField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 6, 32)];
                self.helloModelField.leftViewMode = UITextFieldViewModeAlways;
                self.helloModelField.delegate = self;
                [row addSubview:self.helloModelField];
            }

            UILabel *proxyLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, proxyY, 80, 26)];
            proxyLabel.font = [RPTheme small:14];
            proxyLabel.textColor = [RPTheme textDim];
            proxyLabel.text = @"使用代理";
            [row addSubview:proxyLabel];
            UISwitch *psw = [[UISwitch alloc] initWithFrame:CGRectMake(96, proxyY - 4, 51, 31)];
            NSString *pk = [kSourceProxyPrefix stringByAppendingString:d.pid];
            psw.on = ([ud objectForKey:pk] == nil) ? RPDefaultUseProxy(d.pid) : [ud boolForKey:pk];
            psw.onTintColor = [RPTheme tintOrange];
            [row addSubview:psw];
            [self.pageProxySwitches addObject:psw];

            UILabel *every = [[UILabel alloc] initWithFrame:CGRectMake(12, refreshY, 70, 28)];
            every.font = [RPTheme small:14];
            every.textColor = [RPTheme textDim];
            every.text = @"数据更新";
            [row addSubview:every];
            if ([d.pid isEqualToString:@"steam-new-releases-2"] || greet) {
                UILabel *shared = [[UILabel alloc] initWithFrame:CGRectMake(88, refreshY, rowW - 100, 28)];
                shared.font = [RPTheme small:14];
                shared.textColor = [RPTheme textDim];
                shared.text = greet ? @"早上、中午、晚上各一次" : @"与「Steam 新游」共用";
                [row addSubview:shared];
                [self.pageRefreshControls addObject:[NSNull null]];
            } else {
                UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:RPLocalRefreshChoiceTitles()];
                seg.frame = CGRectMake(88, refreshY - 2, rowW - 100, 32);
                seg.selectedSegmentIndex = RPLocalRefreshChoiceIndex(RPLocalTTL(RPLocalFeedKeyForPage(d.pid)));
                seg.tintColor = [RPTheme accent];
                [row addSubview:seg];
                [self.pageRefreshControls addObject:seg];
            }
        } else {
            [self.pageURLFields addObject:[NSNull null]];
            [self.pageProxySwitches addObject:[NSNull null]];
            [self.pageRefreshControls addObject:[NSNull null]];
        }

        [self.settingsScroll addSubview:row];
        y += rowH + 8;
    }

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(20, y, contentW, 72)];
    hint.font = [RPTheme small:13]; hint.textColor = [RPTheme textDim];
    hint.numberOfLines = 0;
    hint.text = @"上面的「秒」是翻页停留。「数据更新」是多久重新拉一次。同一局域网的电脑浏览器打开 http://这台iPad的地址:8090/setup ，也可以改这里的全部设置。";
    [self.settingsScroll addSubview:hint];
    y += 84;

    self.settingsScroll.contentSize = CGSizeMake(sheetW, y + 20);
}

- (void)hideSettings {
    [self.view endEditing:YES];
    [self.settingsDim removeFromSuperview];
    self.settingsDim = nil;
    self.settingsSheet = nil;
    self.settingsScroll = nil;
    self.pageEnableSwitches = nil;
    self.pageDwellFields = nil;
    self.pageURLFields = nil;
    self.pageProxySwitches = nil;
    self.pageRefreshControls = nil;
    self.vpsRefreshControl = nil;
    self.settingsDefs = nil;
    self.proxyField = nil;
    self.tickerField = nil;
    self.tickerProxySwitch = nil;
    self.tickerRefreshControl = nil;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}


- (void)saveSettings {
    self.baseURL = @"";
    self.dwellOverride = [self.dwellField.text integerValue];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:self.proxyField.text ?: @"" forKey:kProxyKey];
    [ud setObject:self.tickerField.text ?: @"" forKey:RPTickerURLKey];
    [ud setBool:self.tickerProxySwitch.on forKey:RPTickerProxyKey];
    if (self.tickerRefreshControl) {
        NSArray *tickerChoices = RPLocalRefreshChoices();
        NSInteger tickerIdx = self.tickerRefreshControl.selectedSegmentIndex;
        if (tickerIdx >= 0 && tickerIdx < (NSInteger)tickerChoices.count) {
            [ud setDouble:[tickerChoices[tickerIdx] doubleValue] forKey:[RPRefreshPrefix stringByAppendingString:@"ticker"]];
        }
    }
    [ud setObject:self.vpsURLField.text ?: @"" forKey:RPVpsURLKey];
    [ud setObject:self.vpsTokenField.text ?: @"" forKey:RPVpsTokenKey];
    if (self.helloKeyField) [ud setObject:self.helloKeyField.text ?: @"" forKey:RPHelloKeyKey];
    if (self.helloModelField) [ud setObject:self.helloModelField.text ?: @"" forKey:RPHelloModelKey];
    [ud setBool:self.vpsProxySwitch.on forKey:RPVpsProxyKey];
    [ud setInteger:self.dwellOverride forKey:kDwellOverrideKey];
    if (self.photos.albumLocalIdentifier) [ud setObject:self.photos.albumLocalIdentifier forKey:kAlbumIdKey];
    else [ud removeObjectForKey:kAlbumIdKey];

    for (NSUInteger i=0; i<self.settingsDefs.count; i++) {
        RPPageDef *d = self.settingsDefs[i];
        UISwitch *sw = self.pageEnableSwitches[i];
        UITextField *df = self.pageDwellFields[i];
        [ud setBool:sw.on forKey:[kPageEnabledPrefix stringByAppendingString:d.pid]];
        NSInteger dv = [df.text integerValue];
        if (dv > 0) [ud setInteger:dv forKey:[kPageDwellPrefix stringByAppendingString:d.pid]];
        else [ud removeObjectForKey:[kPageDwellPrefix stringByAppendingString:d.pid]];
        d.enabled = sw.on;
        id urlField = self.pageURLFields[i];
        id proxySw = self.pageProxySwitches[i];
        if (urlField != [NSNull null] && proxySw != [NSNull null]) {
            [ud setObject:((UITextField *)urlField).text ?: @"" forKey:[kSourceURLPrefix stringByAppendingString:d.pid]];
            [ud setBool:((UISwitch *)proxySw).on forKey:[kSourceProxyPrefix stringByAppendingString:d.pid]];
        }
        id refresh = self.pageRefreshControls[i];
        if (refresh != [NSNull null]) {
            UISegmentedControl *seg = refresh;
            NSArray *choices = RPLocalRefreshChoices();
            NSInteger idx = seg.selectedSegmentIndex;
            NSString *feed = RPLocalFeedKeyForPage(d.pid);
            if (feed.length && idx >= 0 && idx < (NSInteger)choices.count) {
                [ud setDouble:[choices[idx] doubleValue] forKey:[RPRefreshPrefix stringByAppendingString:feed]];
            }
        }
    }
    if (self.vpsRefreshControl) {
        NSArray *choices = RPLocalRefreshChoices();
        NSInteger idx = self.vpsRefreshControl.selectedSegmentIndex;
        if (idx >= 0 && idx < (NSInteger)choices.count) {
            [ud setDouble:[choices[idx] doubleValue] forKey:[RPRefreshPrefix stringByAppendingString:@"vps"]];
        }
    }
    [ud synchronize];

    NSString *curPid = nil;
    if (self.index >= 0 && self.index < (NSInteger)self.pages.count) curPid = self.pages[self.index].pid;
    [self rebuildEnabledPages];
    NSInteger newIdx = 0;
    if (curPid) {
        for (NSUInteger i=0;i<self.pages.count;i++) {
            if ([self.pages[i].pid isEqualToString:curPid]) { newIdx = i; break; }
        }
    }
    [self hideSettings];
    [self showPageAtIndex:newIdx resetDwell:YES];
    [self pollNow];
}

- (void)pickAlbum {
    __weak typeof(self) weakSelf = self;
    [self.photos ensureAuthorization:^(BOOL granted) {
        if (!granted) {
            weakSelf.albumLabel.text = @"无相册权限，请到系统设置开启";
            return;
        }
        NSArray *albums = [weakSelf.photos allAlbums];
        UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"选择相册" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        UIAlertAction *def = [UIAlertAction actionWithTitle:@"默认（收藏夹/图库）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            weakSelf.photos.albumLocalIdentifier = nil;
            weakSelf.albumLabel.text = @"相册: 默认「个人收藏」或图库";
        }];
        [ac addAction:def];
        for (PHAssetCollection *c in albums) {
            NSString *t = [weakSelf.photos titleForCollection:c] ?: @"相册";
            NSString *lid = c.localIdentifier;
            [ac addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
                weakSelf.photos.albumLocalIdentifier = lid;
                weakSelf.albumLabel.text = [NSString stringWithFormat:@"相册: %@", t];
            }]];
        }
        [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        UIPopoverPresentationController *pop = ac.popoverPresentationController;
        if (pop) {
            pop.sourceView = weakSelf.settingsSheet;
            pop.sourceRect = CGRectMake(weakSelf.settingsSheet.bounds.size.width-160, 100, 140, 40);
        }
        [weakSelf presentViewController:ac animated:YES completion:nil];
    }];
}


- (void)onCollectAlbums:(NSNotification *)note {
    NSMutableArray *albums = note.object;
    if (![albums isKindOfClass:[NSMutableArray class]]) return;
    for (PHAssetCollection *c in [self.photos allAlbums]) {
        NSString *lid = c.localIdentifier ?: @"";
        if (lid.length == 0) continue;
        [albums addObject:@{ @"id": lid, @"title": [self.photos titleForCollection:c] ?: @"相册" }];
    }
}

- (void)onRemoteSettings {
    if (self.settingsDim) [self hideSettings];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    self.dwellOverride = [ud integerForKey:kDwellOverrideKey];
    self.photos.albumLocalIdentifier = [ud stringForKey:kAlbumIdKey];
    NSString *curPid = nil;
    if (self.index >= 0 && self.index < (NSInteger)self.pages.count) curPid = self.pages[self.index].pid;
    [self rebuildEnabledPages];
    NSInteger newIdx = 0;
    if (curPid) {
        for (NSUInteger i = 0; i < self.pages.count; i++) {
            if ([self.pages[i].pid isEqualToString:curPid]) { newIdx = (NSInteger)i; break; }
        }
    }
    [self showPageAtIndex:newIdx resetDwell:YES];
    [self pollNow];
}

- (void)onCapturePage:(NSNotification *)note {
    NSMutableDictionary *box = note.userInfo[@"box"];
    if (![box isKindOfClass:[NSMutableDictionary class]]) return;
    NSNumber *jump = note.userInfo[@"index"];
    if ([jump isKindOfClass:[NSNumber class]] && [jump integerValue] >= 0) {
        [self showPageAtIndex:[jump integerValue] resetDwell:YES];
    }
    NSMutableArray *titles = [NSMutableArray array];
    for (RPPageDef *d in self.pages) [titles addObject:d.title ?: d.pid ?: @""];
    box[@"titles"] = [titles componentsJoinedByString:@"\n"];
    box[@"here"] = [NSString stringWithFormat:@"%ld/%lu %@", (long)(self.index + 1), (unsigned long)self.pages.count, self.titleLabel.text ?: @""];
    UIWindow *window = self.view.window ?: [UIApplication sharedApplication].keyWindow;
    if (!window) return;
    [window layoutIfNeeded];
    UIGraphicsBeginImageContextWithOptions(window.bounds.size, YES, 1.0);
    [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) box[@"png"] = UIImagePNGRepresentation(image);
}

- (void)rpModalStateChanged:(NSNotification *)note {
    BOOL open = [note.userInfo[@"open"] boolValue];
    if (open) {
        [self.dwellTimer invalidate];
        self.dwellTimer = nil;
    } else {
        [self restartDwell];
    }
}
@end
