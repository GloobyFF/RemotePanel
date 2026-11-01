#import "RPPages.h"
#import "RPTheme.h"
#import "RPNet.h"
#import "RPLocalFeed.h"
#import "RPPhotoSource.h"
#import <Photos/Photos.h>
#import <WebKit/WebKit.h>
#import <EventKit/EventKit.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import <ctype.h>

static NSString *RPShortNumber(id value);

@interface RPBasePageVC (Fingerprint)
- (BOOL)shouldSkipRebuildForKey:(NSString *)key bounds:(CGRect)b;
- (void)invalidateFingerprint;
- (UILabel *)addClockBlockIn:(UIView *)parent frame:(CGRect)frame;
- (UIView *)makePill:(NSString *)text color:(UIColor *)bg;
- (UIView *)makeCardTinted:(NSInteger)idx accent:(UIColor *)accent;
- (void)showDetailWithTitle:(NSString *)title body:(NSString *)body meta:(NSString *)meta imageURL:(NSURL *)imageURL;
- (void)rpSetModalOpen:(BOOL)open;
- (UILabel *)sectionHeader:(NSString *)text y:(CGFloat)y width:(CGFloat)w;
- (CGFloat)mInset;
- (BOOL)isLandscape;
- (UIColor *)colorFromHex:(NSString *)hex;
- (void)noteImageLoadBegan;
- (void)noteImageLoadEnded;
- (void)tryPlayIntro;
@end

static char kRPImageURLKey;
static char kRPDismissDimKey;
static char kRPReminderID;
/** Soft cap for decoded bitmaps on iPad 3 (1024×768 @2x still huge if kept full-res). */
static const CGFloat kRPImageMaxSide = 480.0;
/** String value or @"" (NSNull, numbers and the literal "(null)" all handled). */
static NSString *RPStringish(id value) {
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value isEqualToString:@"(null)"] ? @"" : value;
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value stringValue];
    return @"";
}

/* Longest the fly-in waits for covers before starting with whatever has loaded.
   Kept at 1.35 s: halving it would just start more pages with empty tiles. */
static const NSTimeInterval kRPIntroImageWait = 1.35;

static NSCache *RPImageCache(void) {
    static NSCache *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = [[NSCache alloc] init];
        c.countLimit = 24;
        // iPad 3 dies if several full-size posters decode at once. 24 MB holds one
        // page of 10 covers at tile size (~1.3 MB each at 720×336) plus the next page's
        // prefetch; NSCache evicts beyond that, and on memory warnings.
        c.totalCostLimit = 24 * 1024 * 1024;
    });
    return c;
}

void RPPurgeImageCache(void) {
    [RPImageCache() removeAllObjects];
}

/** Decode a small thumbnail. imageWithData: first would allocate the full bitmap and can jetsam this iPad. */
static UIImage *RPImageFromData(NSData *data, CGFloat maxSide) {
    if (data.length == 0) return nil;
    CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!src) return nil;
    NSDictionary *opt = @{
        (id)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize: @(MAX(64.0, maxSide)),
        (id)kCGImageSourceCreateThumbnailWithTransform: @YES,
    };
    CGImageRef cg = CGImageSourceCreateThumbnailAtIndex(src, 0, (__bridge CFDictionaryRef)opt);
    CFRelease(src);
    if (!cg) return nil;
    UIImage *img = [UIImage imageWithCGImage:cg];
    CGImageRelease(cg);
    return img;
}

static NSUInteger RPImageCost(UIImage *img) {
    if (!img) return 1;
    CGFloat w = img.size.width * img.scale;
    CGFloat h = img.size.height * img.scale;
    NSUInteger bytes = (NSUInteger)MAX(1.0, w * h * 4.0);
    return bytes;
}

static void RPCacheImage(NSString *key, UIImage *img) {
    if (key.length == 0 || !img) return;
    [RPImageCache() setObject:img forKey:key cost:RPImageCost(img)];
}

static NSURL *RPAbsURLString(NSString *path, NSString *base) {
    if (![path isKindOfClass:[NSString class]] || path.length == 0) return nil;
    if ([path hasPrefix:@"http"]) return [NSURL URLWithString:path];
    NSString *b = base ?: @"";
    if ([b hasSuffix:@"/"]) b = [b substringToIndex:b.length - 1];
    if (![path hasPrefix:@"/"]) path = [@"/" stringByAppendingString:path];
    return [NSURL URLWithString:[b stringByAppendingString:path]];
}

static void RPCollectURL(NSMutableArray *out, NSString *path, NSString *base) {
    NSURL *u = RPAbsURLString(path, base);
    if (u.absoluteString.length) [out addObject:u.absoluteString];
}

void RPPrefetchImagesForPage(NSString *pageId, NSDictionary *state, NSString *baseURL) {
    if (![state isKindOfClass:[NSDictionary class]] || pageId.length == 0) return;
    NSMutableArray *keys = [NSMutableArray array];
    if ([pageId isEqualToString:@"movie-now-showing"]) {
        for (NSDictionary *mov in (state[@"movies"] ?: @[])) {
            if ([mov isKindOfClass:[NSDictionary class]]) RPCollectURL(keys, mov[@"poster_url"], baseURL);
        }
    } else if ([pageId hasPrefix:@"steam-new-releases"]) {
        NSDictionary *steam = state[@"steam"] ?: @{};
        NSArray *items = ([pageId hasSuffix:@"-2"] ? (steam[@"top_sellers"] ?: steam[@"trending"]) : steam[@"new_releases"]) ?: @[];
        for (NSDictionary *item in items) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            RPCollectURL(keys, item[@"header_url"] ?: item[@"capsule_url"] ?: item[@"image_url"], baseURL);
        }
    } else if ([pageId hasPrefix:@"gamer520"] || [pageId isEqualToString:@"ps5-games-latest"]) {
        NSArray *items = nil;
        if ([pageId rangeOfString:@"switch"].location != NSNotFound) items = state[@"gamer520"][@"switch_items"] ?: state[@"switch_games"];
        else if ([pageId rangeOfString:@"ps5"].location != NSNotFound) items = state[@"ps5_games"] ?: state[@"gamer520"][@"ps5_items"];
        else items = state[@"gamer520"][@"items"];
        for (NSDictionary *item in (items ?: @[])) {
            if ([item isKindOfClass:[NSDictionary class]]) RPCollectURL(keys, item[@"image_url"] ?: item[@"cover_url"] ?: item[@"poster_url"], baseURL);
        }
    } else if ([pageId isEqualToString:@"daily-news"] || [pageId isEqualToString:@"github-news"] ||
               [pageId isEqualToString:@"x-news"] || [pageId isEqualToString:@"xiaohongshu-hot"] ||
               [pageId isEqualToString:@"bilibili-hot"]) {
        NSArray *items = nil;
        if ([pageId isEqualToString:@"github-news"]) items = state[@"news"][@"github_items"] ?: state[@"news"][@"github"];
        else if ([pageId isEqualToString:@"x-news"]) items = state[@"news"][@"x_items"] ?: state[@"news"][@"x"];
        else if ([pageId isEqualToString:@"xiaohongshu-hot"]) items = state[@"news"][@"xhs_items"] ?: state[@"news"][@"xiaohongshu"];
        // RPLocalFeed -assemble writes news.bili_items; the other keys are from the old :9121 server.
        else if ([pageId isEqualToString:@"bilibili-hot"]) items = state[@"news"][@"bili_items"] ?: state[@"bilibili"][@"items"] ?: state[@"news"][@"bilibili_items"];
        else items = state[@"news"][@"daily_items"] ?: state[@"news"][@"daily"];
        NSInteger n = 0;
        for (NSDictionary *it in (items ?: @[])) {
            if (![it isKindOfClass:[NSDictionary class]]) continue;
            RPCollectURL(keys, it[@"image_url"], baseURL);
            if (++n >= 8) break;
        }
    }
    if (keys.count == 0) return;
    if (keys.count > 4) [keys removeObjectsInRange:NSMakeRange(4, keys.count - 4)];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        for (NSString *key in keys) {
            if ([RPImageCache() objectForKey:key]) continue;
            NSError *error = nil;
            NSString *proxy = nil;
            if ([key rangeOfString:@"github"].location != NSNotFound) {
                proxy = RPConfiguredProxy();
            }
            NSData *data = [RPNet syncGET:key proxy:proxy headers:nil timeout:16 error:&error];
            // Match the size the cover pages now draw at, so the prefetched copy is used as-is.
            UIImage *img = RPImageFromData(data, 720.0);
            if (img) RPCacheImage(key, img);
        }
    });
}

static NSString *RPHashObject(id obj) {
    if (!obj || obj == [NSNull null]) return @"-";
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:NSJSONWritingPrettyPrinted error:&err];
    if (!data) {
        return [NSString stringWithFormat:@"%@", obj];
    }
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *out = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH*2];
    for (int i=0;i<CC_MD5_DIGEST_LENGTH;i++) [out appendFormat:@"%02x", digest[i]];
    return out;
}

@implementation RPBasePageVC {
    NSString *_lastFingerprint;
    CGSize _lastBoundsSize;
    BOOL _introPlayed;
    BOOL _waitingIntro;
    NSInteger _pendingImageLoads;
    NSInteger _introWaitToken;
    NSInteger _cardSerial;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
    self.contentView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.contentView];
}
- (void)pageWillAppear {
    _waitingIntro = YES;
    _introPlayed = NO;
    _introWaitToken += 1;
    NSInteger token = _introWaitToken;
    // Park before the run loop paints. Image pages used to sit at rest for the
    // load wait, then jump off-canvas and fly back in.
    [self parkMotionOffscreen];
    [self tryPlayIntro];
    // Don't stall the fly-in forever on a slow LAN — start with whatever is ready.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRPIntroImageWait * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (token != self->_introWaitToken) return;
        if (!self->_waitingIntro || self->_introPlayed) return;
        self->_pendingImageLoads = 0;
        [self tryPlayIntro];
    });
}
- (void)pageDidDisappear {
    _waitingIntro = NO;
    _introWaitToken += 1;
    [self purgeDisplayedImages];
}
- (void)applyState:(NSDictionary *)state baseURL:(NSString *)baseURL { (void)state; (void)baseURL; }
- (void)clearContent {
    // A refresh on the page that's already flying (or finished) must not
    // rewind the intro; the next appear creates a new controller.
    if (_waitingIntro) _introPlayed = NO;
    _pendingImageLoads = 0;
    _cardSerial = 0;
    for (UIView *v in self.contentView.subviews) [v removeFromSuperview];
}
- (void)rpReplayIntro {
    _introPlayed = NO;
    _waitingIntro = YES;
    self.contentView.alpha = 1;
    [self.view layoutIfNeeded];
    [self parkMotionOffscreen];
    [self tryPlayIntro];
}
- (void)tryPlayIntro {
    if (!_waitingIntro || _introPlayed) return;
    if (_pendingImageLoads > 0) return;
    if (self.contentView.bounds.size.width < 2) return;
    _waitingIntro = NO;
    [self playPageIntro];
}
- (void)noteImageLoadBegan {
    _pendingImageLoads += 1;
}
- (void)noteImageLoadEnded {
    if (_pendingImageLoads > 0) _pendingImageLoads -= 1;
    [self tryPlayIntro];
}
static void RPPurgeImages(UIView *root) {
    if ([root isKindOfClass:[UIImageView class]]) ((UIImageView *)root).image = nil;
    for (UIView *sub in root.subviews) RPPurgeImages(sub);
}
- (void)purgeDisplayedImages {
    // A plain C function: the old self-referencing __block block was a retain cycle
    // that leaked one block (and everything it captured) on every page turn.
    RPPurgeImages(self.contentView);
}
- (NSInteger)rpMotionKind {
    NSArray *ids = @[@"hello", @"schedule", @"weather", @"daily-news", @"github-news", @"x-news", @"xiaohongshu-hot", @"bilibili-hot", @"stocks-cn", @"crypto", @"person-photo-local-1", @"print", @"movie-now-showing", @"steam-new-releases", @"steam-new-releases-2", @"gamer520-pc-latest", @"person-photo-local-2", @"gamer520-switch-latest", @"ps5-games-latest"];
    NSUInteger idx = [ids indexOfObject:self.pageId ?: @""];
    return idx == NSNotFound ? 0 : (NSInteger)idx;
}
- (NSArray *)rpMotionViews {
    NSMutableArray *all = [NSMutableArray array];
    for (UIView *v in self.contentView.subviews) {
        if (v.hidden) continue;
        if ([v isKindOfClass:[UIScrollView class]]) {
            for (UIView *sub in v.subviews) {
                if (sub.hidden) continue;
                if ([sub isKindOfClass:[UIImageView class]] && sub.bounds.size.width < 12) continue;
                [all addObject:sub];
            }
        } else {
            [all addObject:v];
        }
    }
    return all;
}
- (BOOL)rpIntroFromOutside {
    NSString *pid = self.pageId ?: @"";
    if ([pid hasPrefix:@"person-photo"]) return YES;
    static NSArray *imagePages;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        imagePages = @[@"github-news", @"xiaohongshu-hot", @"bilibili-hot", @"daily-news",
                       @"movie-now-showing", @"steam-new-releases", @"steam-new-releases-2",
                       @"gamer520-pc-latest", @"gamer520-switch-latest", @"ps5-games-latest"];
    });
    return [imagePages containsObject:pid];
}
- (BOOL)rpIntroHasPlayed { return _introPlayed; }
- (void)parkMotionOffscreen {
    if (_introPlayed) return;
    if (self.contentView.bounds.size.width < 2) return;
    NSArray *views = [self rpMotionViews];
    NSInteger kind = [self rpMotionKind];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [views enumerateObjectsUsingBlock:^(UIView *v, NSUInteger i, BOOL *stop) {
        v.transform = [self rpMotionShift:kind index:(NSInteger)i outro:NO];
        v.alpha = 1;
    }];
    [CATransaction commit];
}
- (CGAffineTransform)rpMotionShift:(NSInteger)kind index:(NSInteger)i outro:(BOOL)outro {
    CGFloat w = MAX(self.contentView.bounds.size.width, 480);
    CGFloat h = MAX(self.contentView.bounds.size.height, 320);
    // Covers and posters fly in from off-canvas. Scale/spin styles read as a flash.
    NSInteger style = [self rpIntroFromOutside] ? 5 : (kind % 8);
    BOOL leave = outro;
    switch (style) {
        case 0: return CGAffineTransformMakeTranslation(leave ? w : -w, 0);
        case 1: return CGAffineTransformMakeTranslation(leave ? -w : w, 0);
        case 2: return CGAffineTransformMakeTranslation(0, leave ? h : -h);
        case 3: return CGAffineTransformMakeTranslation(0, leave ? -h : h);
        case 4: return CGAffineTransformMakeScale(0.08, 0.08);
        case 5: return CGAffineTransformMakeTranslation((i % 2 == 0) ? (leave ? w : -w) : (leave ? -w : w), 40);
        case 6: return CGAffineTransformConcat(CGAffineTransformMakeRotation(leave ? 0.55 : -0.55), CGAffineTransformMakeTranslation(leave ? 80 : -80, leave ? -160 : 180));
        default: return CGAffineTransformMakeTranslation(leave ? -w * 0.85 : w * 0.65, leave ? 80 : -h);
    }
}
- (void)playPageIntro {
    if (_introPlayed) return;
    if (self.contentView.bounds.size.width < 2) return;
    NSArray *views = [self rpMotionViews];
    if (views.count == 0) return;
    _introPlayed = YES;
    NSInteger kind = [self rpMotionKind];
    [views enumerateObjectsUsingBlock:^(UIView *v, NSUInteger i, BOOL *stop) {
        CGAffineTransform start = [self rpMotionShift:kind index:(NSInteger)i outro:NO];
        [UIView performWithoutAnimation:^{
            v.transform = start;
            v.alpha = 1;
        }];
        // Fly-in, half the old 2.3 s / 0.07 s stagger (owner asked for twice as fast).
        [UIView animateWithDuration:1.15 delay:MIN(0.28, i * 0.035) options:UIViewAnimationOptionCurveEaseOut animations:^{
            v.transform = CGAffineTransformIdentity;
            v.alpha = 1;
        } completion:nil];
    }];
}
- (void)playPageOutro:(void (^)(void))done {
    NSArray *views = [self rpMotionViews];
    if (views.count == 0) {
        if (done) done();
        return;
    }
    NSInteger kind = [self rpMotionKind];
    __block NSInteger left = (NSInteger)views.count;
    [views enumerateObjectsUsingBlock:^(UIView *v, NSUInteger i, BOOL *stop) {
        [v.layer removeAllAnimations];
        // Fly-out, half the old 2.1 s / 0.04 s stagger.
        [UIView animateWithDuration:1.05 delay:MIN(0.18, i * 0.02) options:UIViewAnimationOptionCurveEaseIn animations:^{
            v.transform = [self rpMotionShift:kind index:(NSInteger)i outro:YES];
            v.alpha = 0.15;
        } completion:^(BOOL finished) {
            (void)finished;
            left--;
            if (left == 0 && done) done();
        }];
    }];
}
- (BOOL)shouldSkipRebuildForKey:(NSString *)key bounds:(CGRect)b {
    NSString *full = [NSString stringWithFormat:@"%@|%@", key ?: @"", [RPTheme dayName] ?: @""];
    CGSize sz = b.size;
    BOOL sameSize = (fabs(_lastBoundsSize.width - sz.width) < 0.5 && fabs(_lastBoundsSize.height - sz.height) < 0.5);
    if (sameSize && full.length && [full isEqualToString:_lastFingerprint] && self.contentView.subviews.count > 0) {
        return YES;
    }
    _lastFingerprint = [full copy];
    _lastBoundsSize = sz;
    return NO;
}
- (void)invalidateFingerprint {
    _lastFingerprint = nil;
    _lastBoundsSize = CGSizeZero;
}
- (CGFloat)mInset { return 18.0; }
- (BOOL)isLandscape {
    CGRect b = self.contentView.bounds;
    return b.size.width > b.size.height;
}
- (UILabel *)makeLabel:(UIFont *)font color:(UIColor *)color {
    UILabel *l = [[UILabel alloc] init];
    l.font = font;
    l.textColor = color;
    l.numberOfLines = 0;
    return l;
}
- (NSInteger)rpPageColorBias {
    NSUInteger page = 0;
    NSString *pid = self.pageId ?: @"";
    for (NSUInteger i = 0; i < pid.length; i++) page = page * 33 + [pid characterAtIndex:i];
    return (NSInteger)(page % 6);
}
- (UIView *)makeCard {
    _cardSerial += 1;
    return [self makeCardTinted:_cardSerial accent:nil];
}
- (UIView *)makeCardTinted:(NSInteger)idx accent:(UIColor *)accent {
    UIView *c = [[UIView alloc] init];
    c.backgroundColor = [RPTheme cardTint:idx + [self rpPageColorBias]];
    UIColor *border = accent ?: [RPTheme cardBorder];
    c.layer.borderColor = border.CGColor;
    c.layer.borderWidth = 1.5;
    c.layer.cornerRadius = 14.0;
    c.clipsToBounds = YES;
    // left accent bar
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 6, 2000)];
    bar.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    bar.backgroundColor = accent ?: [RPTheme accent];
    bar.tag = 8801;
    [c addSubview:bar];
    return c;
}
- (void)rpSetModalOpen:(BOOL)open {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RPPageModalState" object:nil userInfo:@{@"open": @(open)}];
}
- (void)showDetailWithTitle:(NSString *)title body:(NSString *)body meta:(NSString *)meta imageURL:(NSURL *)imageURL {
    UIView *host = self.view.window ?: self.view;
    UIView *existing = [host viewWithTag:99001];
    if (existing) [existing removeFromSuperview];
    [self rpSetModalOpen:YES];
    UIView *dim = [[UIView alloc] initWithFrame:host.bounds];
    dim.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    dim.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.72];
    dim.tag = 99001;
    [host addSubview:dim];
    CGFloat W = MIN(720, host.bounds.size.width - 48);
    CGFloat H = MIN(host.bounds.size.height - 80, 560);
    UIView *sheet = [[UIView alloc] initWithFrame:CGRectMake((host.bounds.size.width-W)/2.0, (host.bounds.size.height-H)/2.0, W, H)];
    sheet.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleRightMargin|UIViewAutoresizingFlexibleTopMargin|UIViewAutoresizingFlexibleBottomMargin;
    sheet.backgroundColor = [RPTheme tintBlue];
    sheet.layer.cornerRadius = 16;
    sheet.layer.borderWidth = 2;
    sheet.layer.borderColor = [RPTheme accent].CGColor;
    sheet.clipsToBounds = YES;
    [dim addSubview:sheet];
    UILabel *tl = [self makeLabel:[RPTheme title:34] color:[RPTheme text]];
    tl.text = title ?: @"";
    tl.numberOfLines = 3;
    tl.frame = CGRectMake(20, 16, W-80, 90);
    [sheet addSubview:tl];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"✕" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont boldSystemFontOfSize:28];
    [close setTitleColor:[RPTheme accent] forState:UIControlStateNormal];
    close.frame = CGRectMake(W-56, 10, 44, 44);
    [sheet addSubview:close];
    CGFloat y = 110;
    if (imageURL) {
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(20, y, W-40, 160)];
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        iv.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1];
        iv.layer.cornerRadius = 10;
        [sheet addSubview:iv];
        [self loadImageURL:imageURL into:iv];
        y = CGRectGetMaxY(iv.frame) + 12;
    }
    if (meta.length) {
        UILabel *ml = [self makeLabel:[RPTheme body:22] color:[RPTheme accent]];
        ml.text = meta;
        ml.numberOfLines = 2;
        ml.frame = CGRectMake(20, y, W-40, 50);
        [sheet addSubview:ml];
        y = CGRectGetMaxY(ml.frame) + 8;
    }
    UIScrollView *sv = [[UIScrollView alloc] initWithFrame:CGRectMake(16, y, W-32, H-y-20)];
    sv.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [sheet addSubview:sv];
    UILabel *bl = [self makeLabel:[RPTheme body:26] color:[RPTheme text]];
    bl.text = body.length ? body : @"暂无更多详情";
    bl.numberOfLines = 0;
    CGSize sz = [bl sizeThatFits:CGSizeMake(W-40, 4000)];
    bl.frame = CGRectMake(4, 4, W-40, MAX(40, sz.height));
    [sv addSubview:bl];
    sv.contentSize = CGSizeMake(W-32, CGRectGetMaxY(bl.frame)+20);
    void (^dismiss)(void) = ^{
        [dim removeFromSuperview];
        [self rpSetModalOpen:NO];
    };
    [close addTarget:self action:@selector(rpDismissDetail:) forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(close, &kRPDismissDimKey, dim, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rpDismissDetailTap:)];
    [dim addGestureRecognizer:tap];
    objc_setAssociatedObject(tap, &kRPDismissDimKey, dim, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // prevent sheet taps dismissing
    UITapGestureRecognizer *noop = [[UITapGestureRecognizer alloc] initWithTarget:nil action:nil];
    [sheet addGestureRecognizer:noop];
}
- (void)rpDismissDetail:(UIButton *)sender {
    UIView *dim = objc_getAssociatedObject(sender, &kRPDismissDimKey);
    [dim removeFromSuperview];
    [self rpSetModalOpen:NO];
}
- (void)rpDismissDetailTap:(UITapGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateEnded) return;
    UIView *dim = objc_getAssociatedObject(gr, &kRPDismissDimKey);
    CGPoint p = [gr locationInView:dim];
    // only dismiss if tap outside sheet (first subview)
    UIView *sheet = dim.subviews.firstObject;
    if (sheet && CGRectContainsPoint(sheet.frame, p)) return;
    [dim removeFromSuperview];
    [self rpSetModalOpen:NO];
}
- (UILabel *)sectionHeader:(NSString *)text y:(CGFloat)y width:(CGFloat)w {
    UILabel *h = [self makeLabel:[RPTheme title:30] color:[RPTheme accent]];
    h.text = text;
    h.frame = CGRectMake([self mInset], y, w, 36);
    [self.contentView addSubview:h];
    return h;
}
- (UIView *)makePill:(NSString *)text color:(UIColor *)bg {
    UILabel *l = [self makeLabel:[RPTheme small:14] color:[UIColor colorWithWhite:0.05 alpha:1]];
    l.text = [NSString stringWithFormat:@" %@ ", text ?: @""];
    l.backgroundColor = bg ?: [RPTheme accent];
    l.textAlignment = NSTextAlignmentCenter;
    l.layer.cornerRadius = 5;
    l.clipsToBounds = YES;
    [l sizeToFit];
    CGRect f = l.frame;
    f.size.height = MAX(26, f.size.height + 6);
    f.size.width = MAX(52, f.size.width + 10);
    l.frame = f;
    return l;
}
- (UIColor *)colorFromHex:(NSString *)hex {
    if (hex.length < 6) return [RPTheme textDim];
    NSString *h6 = hex.length >= 8 ? [hex substringToIndex:6] : [hex substringToIndex:MIN(6, hex.length)];
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:h6] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb>>16)&0xff)/255.0 green:((rgb>>8)&0xff)/255.0 blue:(rgb&0xff)/255.0 alpha:1];
}
- (UILabel *)addClockBlockIn:(UIView *)parent frame:(CGRect)frame {
    UIView *card = [self makeCard];
    card.frame = frame;
    card.tag = 9001;
    CGFloat heroSize = frame.size.height >= 90 ? 42 : 34;
    UILabel *time = [self makeLabel:[RPTheme hero:heroSize] color:[RPTheme accent]];
    time.tag = 9002;
    time.textAlignment = NSTextAlignmentCenter;
    time.frame = CGRectMake(8, 12, frame.size.width-16, heroSize+6);
    UILabel *date = [self makeLabel:[RPTheme small:15] color:[RPTheme textDim]];
    date.tag = 9003;
    date.textAlignment = NSTextAlignmentCenter;
    date.frame = CGRectMake(8, CGRectGetMaxY(time.frame)+2, frame.size.width-16, 22);
    NSDateFormatter *tf = [[NSDateFormatter alloc] init];
    tf.dateFormat = @"HH:mm";
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    df.dateFormat = @"M月d日 EEEE";
    NSDate *now = [NSDate date];
    time.text = [tf stringFromDate:now];
    date.text = [df stringFromDate:now];
    [card addSubview:time];
    [card addSubview:date];
    [parent addSubview:card];
    return time;
}
- (NSURL *)absURL:(NSString *)path base:(NSString *)base {
    if (path.length == 0) return nil;
    if ([path hasPrefix:@"http"]) return [NSURL URLWithString:path];
    NSString *b = base ?: @"";
    if ([b hasSuffix:@"/"]) b = [b substringToIndex:b.length-1];
    if (![path hasPrefix:@"/"]) path = [@"/" stringByAppendingString:path];
    return [NSURL URLWithString:[b stringByAppendingString:path]];
}
- (void)loadImageURL:(NSURL *)url into:(UIImageView *)iv {
    if (!iv) return;
    NSString *key = url.absoluteString ?: @"";
    NSString *prev = objc_getAssociatedObject(iv, &kRPImageURLKey);
    if (key.length && [prev isEqualToString:key] && iv.image) {
        return;
    }
    if (key.length == 0) {
        objc_setAssociatedObject(iv, &kRPImageURLKey, nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
        iv.image = nil;
        return;
    }
    UIImage *cached = [RPImageCache() objectForKey:key];
    // A copy decoded smaller than this tile needs (e.g. by an older prefetch) would
    // look soft; ignore it and decode again at the right size.
    CGFloat needPx = MAX(iv.bounds.size.width, iv.bounds.size.height) * MIN(2.0, [UIScreen mainScreen].scale);
    if (cached && MAX(cached.size.width, cached.size.height) * cached.scale + 1 < MIN(1024.0, MAX(kRPImageMaxSide, needPx)) * 0.9) cached = nil;
    if (cached) {
        iv.image = cached;
        objc_setAssociatedObject(iv, &kRPImageURLKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
        return;
    }
    objc_setAssociatedObject(iv, &kRPImageURLKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self noteImageLoadBegan];
    // Decode at the tile's pixel size (retina ×2), not a fixed 480 px: the larger
    // cover tiles are ~720 px wide and looked soft. Never above 1024 px per image.
    CGFloat px = MAX(iv.bounds.size.width, iv.bounds.size.height) * MIN(2.0, [UIScreen mainScreen].scale);
    CGFloat decodeSide = MIN(1024.0, MAX(kRPImageMaxSide, px));
    __weak typeof(self) weakSelf = self;
    __weak UIImageView *weakIV = iv;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSString *proxy = nil;
        if ([key rangeOfString:@"github"].location != NSNotFound) {
            proxy = RPConfiguredProxy();
        }
        NSData *data = [RPNet syncGET:key proxy:proxy headers:nil timeout:18 error:&error];
        UIImage *img = RPImageFromData(data, decodeSide);
        if (img) RPCacheImage(key, img);
        dispatch_async(dispatch_get_main_queue(), ^{
            UIImageView *strongIV = weakIV;
            NSString *cur = strongIV ? objc_getAssociatedObject(strongIV, &kRPImageURLKey) : nil;
            if (strongIV && [cur isEqualToString:key]) {
                if (img) {
                    strongIV.image = img;
                } else if (!strongIV.image) {
                    UILabel *miss = [UILabel new];
                    miss.text = @"封面没读到";
                    miss.textAlignment = NSTextAlignmentCenter;
                    miss.textColor = [UIColor colorWithWhite:0.65 alpha:1];
                    miss.font = [RPTheme body:16];
                    miss.frame = strongIV.bounds;
                    miss.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                    [strongIV addSubview:miss];
                }
            }
            [weakSelf noteImageLoadEnded];
        });
    });
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
- (BOOL)shouldAutorotate { return YES; }
@end

#pragma mark - Hello

@implementation RPHelloPageVC
- (void)applyState:(NSDictionary *)state baseURL:(NSString *)baseURL {
    (void)baseURL;
    CGRect b = self.contentView.bounds;
    NSString *period = [NSString stringWithFormat:@"%@", state[@"news"][@"hello_period"] ?: @""];
    NSString *text = [NSString stringWithFormat:@"%@", state[@"news"][@"hello_text"] ?: @""];
    if ([period isEqualToString:@"(null)"]) period = @"";
    if ([text isEqualToString:@"(null)"]) text = @"";
    BOOL waiting = text.length == 0;
    if (period.length == 0) period = @"你好";
    if (waiting) text = @"正在准备一句问候";
    NSDictionary *weather = [state[@"weather"] isKindOfClass:[NSDictionary class]] ? state[@"weather"] : @{};
    NSString *fp = [NSString stringWithFormat:@"hello4|%@|%@|%@", period, text, weather[@"temperature"] ?: @""];
    if ([self shouldSkipRebuildForKey:fp bounds:b]) return;
    [self clearContent];
    BOOL landscape = [self isLandscape];
    CGFloat m = [self mInset];
    UIColor *tone = [RPTheme accent];

    CGFloat panelW = landscape ? floor(b.size.width * 0.34) : (b.size.width - 2 * m);
    CGFloat panelH = landscape ? (b.size.height - 2 * m) : 220;
    CGFloat panelX = landscape ? (b.size.width - m - panelW) : m;
    CGFloat panelY = landscape ? m : (b.size.height - m - panelH);
    UIView *panel = [self makeCard];
    panel.frame = CGRectMake(panelX, panelY, panelW, panelH);
    NSString *iconText = [NSString stringWithFormat:@"%@", weather[@"icon"] ?: @""];
    if ([iconText isEqualToString:@"(null)"] || iconText.length == 0) iconText = @"\uf00d";
    UILabel *icon = [self makeLabel:[RPTheme weatherIcon:landscape ? 120 : 88] color:tone];
    icon.text = iconText;
    icon.textAlignment = NSTextAlignmentCenter;
    icon.frame = CGRectMake(12, 18, panelW - 24, landscape ? 140 : 96);
    UILabel *temp = [self makeLabel:[RPTheme hero:landscape ? 64 : 48] color:[RPTheme text]];
    NSString *tempText = RPShortNumber(weather[@"temperature"]);
    if ([tempText isEqualToString:@"-"]) tempText = @"";
    temp.text = (tempText.length && ![tempText isEqualToString:@"(null)"]) ? [NSString stringWithFormat:@"%@°", tempText] : @"";
    temp.textAlignment = NSTextAlignmentCenter;
    temp.frame = CGRectMake(12, CGRectGetMaxY(icon.frame) + 4, panelW - 24, 70);
    UILabel *desc = [self makeLabel:[RPTheme title:28] color:[RPTheme text]];
    NSString *descText = [NSString stringWithFormat:@"%@", weather[@"description"] ?: @""];
    NSString *city = [NSString stringWithFormat:@"%@", weather[@"city"] ?: @""];
    if ([descText isEqualToString:@"(null)"]) descText = @"";
    if ([city isEqualToString:@"(null)"]) city = @"";
    desc.text = city.length ? [NSString stringWithFormat:@"%@  %@", city, descText] : descText;
    desc.textAlignment = NSTextAlignmentCenter;
    desc.frame = CGRectMake(12, panelH - 52, panelW - 24, 36);
    [panel addSubview:icon];
    [panel addSubview:temp];
    [panel addSubview:desc];
    [self.contentView addSubview:panel];

    CGFloat textW = landscape ? (panelX - m - 16) : (b.size.width - 2 * m);
    CGFloat textTop = landscape ? 28 : 12;
    UILabel *big = [self makeLabel:[RPTheme title:landscape ? 72 : 56] color:tone];
    big.text = period;
    big.textAlignment = NSTextAlignmentCenter;
    big.adjustsFontSizeToFitWidth = YES;
    big.minimumScaleFactor = 0.6;
    big.frame = CGRectMake(m, textTop, textW, landscape ? 100 : 80);
    [self.contentView addSubview:big];

    UILabel *line = [self makeLabel:[RPTheme title:landscape ? 32 : 28] color:waiting ? [RPTheme textDim] : [RPTheme text]];
    line.text = text;
    line.textAlignment = NSTextAlignmentCenter;
    line.numberOfLines = 5;
    line.adjustsFontSizeToFitWidth = YES;
    line.minimumScaleFactor = 0.45;
    CGFloat lineY = CGRectGetMaxY(big.frame) + 12;
    CGFloat lineBottom = landscape ? (b.size.height - 56) : panelY - 8;
    line.frame = CGRectMake(m + 8, lineY, textW - 16, MAX(80, lineBottom - lineY));
    [self.contentView addSubview:line];

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    fmt.dateFormat = @"M月d日 EEEE";
    UILabel *when = [self makeLabel:[RPTheme body:22] color:[RPTheme textDim]];
    when.text = [fmt stringFromDate:[NSDate date]];
    when.textAlignment = landscape ? NSTextAlignmentLeft : NSTextAlignmentCenter;
    when.frame = CGRectMake(m, b.size.height - 40, textW, 28);
    [self.contentView addSubview:when];
}
@end

static NSString *RPShortNumber(id value) {
    if (!value || value == [NSNull null]) return @"-";
    if ([value isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (s.length == 0 || [s isEqualToString:@"(null)"]) return @"-";
        NSScanner *scanner = [NSScanner scannerWithString:s];
        double v = 0;
        if (![scanner scanDouble:&v] || !scanner.isAtEnd) return s;
        value = @(v);
    }
    if (![value respondsToSelector:@selector(doubleValue)]) return @"-";
    double v = [value doubleValue];
    if (fabs(v - round(v)) < 0.05) return [NSString stringWithFormat:@"%.0f", round(v)];
    return [NSString stringWithFormat:@"%.1f", v];
}

#pragma mark - Weather

@implementation RPWeatherPageVC
- (void)applyState:(NSDictionary *)state baseURL:(NSString *)baseURL {
    (void)baseURL;
    CGRect b = self.contentView.bounds;
    NSDictionary *w = state[@"weather"] ?: @{};
    NSDictionary *vps = state[@"vps"] ?: @{};
    NSString *fp = [NSString stringWithFormat:@"weather4-%d|%@|%@", self.weekly?1:0, RPHashObject(w), RPHashObject(vps)];
    if ([self shouldSkipRebuildForKey:fp bounds:b]) return;
    [self clearContent];
    BOOL landscape = [self isLandscape];
    CGFloat m = [self mInset];

    UILabel *city = [self makeLabel:[RPTheme body:22] color:[RPTheme textDim]];
    city.text = [NSString stringWithFormat:@"%@", w[@"city"] ?: @""];
    if ([city.text isEqualToString:@"(null)"]) city.text = @"";
    city.frame = CGRectMake(m, 8, b.size.width-2*m-220, 28);
    [self.contentView addSubview:city];
    [self addClockBlockIn:self.contentView frame:CGRectMake(b.size.width-m-210, 2, 210, 88)];

    CGFloat y = 100;
    if (!self.weekly) {
        CGFloat heroW = landscape ? b.size.width*0.34 : b.size.width-2*m;
        CGFloat vpsBand = vps.count ? 168 : 16;
        CGFloat heroH = landscape ? MAX(280, MIN(400, b.size.height - y - vpsBand)) : 210;
        UIView *hero = [self makeCard];
        hero.frame = CGRectMake(m, y, heroW, heroH);
        UILabel *temp = [self makeLabel:[RPTheme hero:96] color:[RPTheme accent]];
        temp.text = [NSString stringWithFormat:@"%@°", RPShortNumber(w[@"temperature"])];
        temp.frame = CGRectMake(22, 28, heroW*0.55, 100);
        UILabel *icon = [self makeLabel:[RPTheme weatherIcon:72] color:[RPTheme text]];
        icon.text = [NSString stringWithFormat:@"%@", w[@"icon"] ?: @""];
        icon.textAlignment = NSTextAlignmentCenter;
        icon.frame = CGRectMake(heroW*0.55, 36, heroW*0.4, 80);
        UILabel *desc = [self makeLabel:[RPTheme title:36] color:[RPTheme text]];
        desc.text = [NSString stringWithFormat:@"%@", w[@"description"]?:@""];
        desc.frame = CGRectMake(22, 130, heroW-40, 40);
        UILabel *meta = [self makeLabel:[RPTheme body:24] color:[RPTheme textDim]];
        meta.text = [NSString stringWithFormat:@"风 %@ · %@°~%@°", RPShortNumber(w[@"wind_speed"]), RPShortNumber(w[@"temp_min"]), RPShortNumber(w[@"temp_max"])];
        meta.frame = CGRectMake(22, 172, heroW-40, 30);
        [hero addSubview:temp]; [hero addSubview:icon]; [hero addSubview:desc]; [hero addSubview:meta];
        [self.contentView addSubview:hero];
        y = landscape ? y : CGRectGetMaxY(hero.frame) + 16;
        if (landscape) {
            // weekly beside hero
            NSArray *weekly = w[@"weekly"] ?: @[];
            CGFloat x0 = heroW + m + 14;
            CGFloat availW = b.size.width - x0 - m;
            NSInteger show = MIN(6, (NSInteger)weekly.count);
            if (show > 0) {
                CGFloat gap = 10;
                NSInteger cols = MIN(3, show);
                NSInteger rows = (show + cols - 1) / cols;
                CGFloat cw = (availW - gap*(cols-1)) / cols;
                CGFloat ch = (heroH - gap*(rows-1)) / MAX(1,rows);
                for (NSUInteger i=0; i<show; i++) {
                    NSDictionary *d = weekly[i];
                    NSInteger row=i/cols, col=i%cols;
                    UIView *card = [self makeCard];
                    card.frame = CGRectMake(x0 + col*(cw+gap), y + row*(ch+gap), cw, ch);
                    UILabel *day = [self makeLabel:[RPTheme title:20] color:[RPTheme accent]];
                    day.text = [NSString stringWithFormat:@"%@", d[@"weekday"]?:@""];
                    day.textAlignment = NSTextAlignmentCenter;
                    day.frame = CGRectMake(6, 6, cw-12, 22);
                    CGFloat iconH = MAX(52, ch - 72);
                    UILabel *ic = [self makeLabel:[RPTheme weatherIcon:MIN(96, iconH)] color:[RPTheme text]];
                    ic.text = [NSString stringWithFormat:@"%@", d[@"icon"]?:@""];
                    ic.textAlignment = NSTextAlignmentCenter;
                    ic.frame = CGRectMake(4, 26, cw-8, iconH);
                    UILabel *tr = [self makeLabel:[RPTheme mono:18] color:[RPTheme text]];
                    tr.text = [NSString stringWithFormat:@"%@° / %@°", RPShortNumber(d[@"temp_max"]), RPShortNumber(d[@"temp_min"])];
                    tr.textAlignment = NSTextAlignmentCenter;
                    tr.adjustsFontSizeToFitWidth = YES;
                    tr.minimumScaleFactor = 0.7;
                    tr.frame = CGRectMake(6, ch-28, cw-12, 22);
                    [card addSubview:day]; [card addSubview:ic]; [card addSubview:tr];
                    [self.contentView addSubview:card];
                }
            }
            y = CGRectGetMaxY(hero.frame) + 16;
        } else {
            // portrait week strip
            NSArray *weekly = w[@"weekly"] ?: @[];
            [self sectionHeader:@"本周天气" y:y width:b.size.width-2*m];
            y += 42;
            NSInteger show = MIN(6, (NSInteger)weekly.count);
            CGFloat gap = 10;
            NSInteger cols = 3;
            CGFloat cw = (b.size.width - 2*m - gap*(cols-1)) / cols;
            CGFloat ch = 130;
            for (NSUInteger i=0; i<show; i++) {
                NSDictionary *d = weekly[i];
                NSInteger row=i/cols, col=i%cols;
                UIView *card = [self makeCard];
                card.frame = CGRectMake(m + col*(cw+gap), y + row*(ch+gap), cw, ch);
                UILabel *day = [self makeLabel:[RPTheme title:26] color:[RPTheme accent]];
                day.text = [NSString stringWithFormat:@"%@", d[@"weekday"]?:@""];
                day.textAlignment = NSTextAlignmentCenter;
                day.frame = CGRectMake(6, 8, cw-12, 28);
                UILabel *ic = [self makeLabel:[RPTheme weatherIcon:56] color:[RPTheme text]];
                ic.text = [NSString stringWithFormat:@"%@", d[@"icon"]?:@""];
                ic.textAlignment = NSTextAlignmentCenter;
                ic.frame = CGRectMake(6, 38, cw-12, 58);
                UILabel *tr = [self makeLabel:[RPTheme mono:22] color:[RPTheme text]];
                tr.text = [NSString stringWithFormat:@"%@°/%@°", RPShortNumber(d[@"temp_max"]), RPShortNumber(d[@"temp_min"])];
                tr.textAlignment = NSTextAlignmentCenter;
                tr.frame = CGRectMake(4, ch-36, cw-8, 28);
                [card addSubview:day]; [card addSubview:ic]; [card addSubview:tr];
                [self.contentView addSubview:card];
            }
            NSInteger rows = (show + cols - 1) / cols;
            y += rows * (ch + gap) + 8;
        }
    } else {
        // weekly-only page still shows full week grid then VPS
        NSArray *weekly = w[@"weekly"] ?: @[];
        NSInteger cols = landscape ? 3 : 2;
        CGFloat gap = 12;
        CGFloat cw = (b.size.width - 2*m - gap*(cols-1)) / cols;
        CGFloat ch = landscape ? 150 : 140;
        for (NSUInteger i=0; i<weekly.count; i++) {
            NSDictionary *d = weekly[i];
            NSInteger row = i / cols, col = i % cols;
            UIView *card = [self makeCard];
            card.frame = CGRectMake(m + col*(cw+gap), y + row*(ch+gap), cw, ch);
            UILabel *day = [self makeLabel:[RPTheme title:28] color:[RPTheme accent]];
            day.text = [NSString stringWithFormat:@"%@", d[@"weekday"] ?: @""];
            day.frame = CGRectMake(14, 12, cw-28, 32);
            UILabel *icon = [self makeLabel:[RPTheme weatherIcon:72] color:[RPTheme text]];
            icon.text = [NSString stringWithFormat:@"%@", d[@"icon"] ?: @""];
            icon.textAlignment = NSTextAlignmentCenter;
            icon.frame = CGRectMake(8, 44, cw-16, 64);
            UILabel *desc = [self makeLabel:[RPTheme body:24] color:[RPTheme text]];
            desc.text = [NSString stringWithFormat:@"%@", d[@"description"]?:@""];
            desc.frame = CGRectMake(14, 96, cw-28, 28);
            UILabel *tr = [self makeLabel:[RPTheme mono:24] color:[RPTheme textDim]];
            tr.text = [NSString stringWithFormat:@"%@° ~ %@°", RPShortNumber(d[@"temp_min"]), RPShortNumber(d[@"temp_max"])];
            tr.frame = CGRectMake(14, ch-36, cw-28, 28);
            [card addSubview:day]; [card addSubview:icon]; [card addSubview:desc]; [card addSubview:tr];
            [self.contentView addSubview:card];
        }
        NSInteger rows = (weekly.count + cols - 1) / MAX(1,cols);
        y += rows * (ch + gap) + 8;
    }

    // VPS fill section
    if (vps.count && y + 120 < b.size.height - m) {
        [self sectionHeader:@"VPS 用量" y:y width:b.size.width-2*m];
        y += 42;
        CGFloat gap = 12;
        NSInteger cols = landscape ? 4 : 2;
        CGFloat cw = (b.size.width - 2*m - gap*(cols-1)) / cols;
        CGFloat ch = MIN(150, MAX(96, b.size.height - y - m));
        NSArray *cards = @[
            @[@"流量使用", [NSString stringWithFormat:@"%.0f%%", [vps[@"percent"] floatValue]], [NSString stringWithFormat:@"%@", vps[@"used"]?:@""]],
            @[@"剩余", [NSString stringWithFormat:@"%@", vps[@"remain"]?:@"-"], [NSString stringWithFormat:@"%@", vps[@"cycle"]?:@""]],
            @[@"状态", [NSString stringWithFormat:@"%@", vps[@"status"]?:@"-"], @"流量"],
            @[@"周期", @"本月", [NSString stringWithFormat:@"%@", vps[@"cycle"]?:@""]],
        ];
        for (NSUInteger i=0; i<MIN((NSUInteger)cols, cards.count); i++) {
            NSArray *c = cards[i];
            UIView *card = [self makeCard];
            card.frame = CGRectMake(m + i*(cw+gap), y, cw, ch);
            UILabel *k=[self makeLabel:[RPTheme small:20] color:[RPTheme textDim]];
            k.text=c[0]; k.frame=CGRectMake(14,12,cw-28,24);
            UILabel *v=[self makeLabel:[RPTheme hero:28] color:[RPTheme text]];
            v.text=c[1]; v.numberOfLines=2; v.adjustsFontSizeToFitWidth=YES; v.minimumScaleFactor=0.55;
            v.frame=CGRectMake(12,36,cw-24,48);
            UILabel *s=[self makeLabel:[RPTheme body:14] color:[RPTheme textDim]];
            s.text=c[2]; s.numberOfLines=2; s.adjustsFontSizeToFitWidth=YES; s.minimumScaleFactor=0.7;
            s.frame=CGRectMake(12, ch-40,cw-24,32);
            [card addSubview:k]; [card addSubview:v]; [card addSubview:s];
            [self.contentView addSubview:card];
        }
    }
}
@end

#pragma mark - System / VPS

@implementation RPSystemPageVC
- (void)applyState:(NSDictionary *)state baseURL:(NSString *)baseURL {
    (void)baseURL;
    CGRect b = self.contentView.bounds;
    NSDictionary *ops = state[@"ops"] ?: @{};
    NSString *fp = [NSString stringWithFormat:@"system|%@", RPHashObject(ops)];
    if ([self shouldSkipRebuildForKey:fp bounds:b]) return;
    [self clearContent];
    BOOL landscape = [self isLandscape];
    CGFloat m = [self mInset];

    [self addClockBlockIn:self.contentView frame:CGRectMake(b.size.width-m-190, 2, 190, 78)];

    NSString *cpu = [NSString stringWithFormat:@"%@%%", ops[@"cpu_pct"]?:@"-"];
    CGFloat heroW = landscape ? b.size.width*0.30 : b.size.width-2*m;
    CGFloat heroH = landscape ? 180 : 130;
    UIView *hero = [self makeCard];
    hero.frame = CGRectMake(m, 90, heroW, heroH);
    UILabel *hk = [self makeLabel:[RPTheme small:16] color:[RPTheme textDim]];
    hk.text = @"CPU"; hk.frame = CGRectMake(16, 14, heroW-32, 22);
    UILabel *hv = [self makeLabel:[RPTheme hero:60] color:[RPTheme accent]];
    hv.text = cpu; hv.frame = CGRectMake(16, 44, heroW-32, 80);
    [hero addSubview:hk]; [hero addSubview:hv];
    [self.contentView addSubview:hero];

    NSArray *items = @[
        @[@"内存", [NSString stringWithFormat:@"%@%%", ops[@"mem_pct"]?:@"-"], [NSString stringWithFormat:@"%@/%@ GB", ops[@"memory_used_gb"]?:@"-", ops[@"memory_total_gb"]?:@"-"]],
        @[@"磁盘", [NSString stringWithFormat:@"%@%%", ops[@"disk_pct"]?:@"-"], [NSString stringWithFormat:@"剩余 %@ GB", ops[@"disk_free_gb"]?:@"-"]],
        @[@"负载", [NSString stringWithFormat:@"%@", ops[@"load_1m"]?:@"-"], [NSString stringWithFormat:@"%@", ops[@"thermal_status"]?:@"-"]],
        @[@"系统", [NSString stringWithFormat:@"%@", ops[@"os"]?:@"-"], [NSString stringWithFormat:@"%@", ops[@"host"]?:@""]],
    ];
    CGFloat x0 = landscape ? heroW + m + 14 : m;
    CGFloat y0 = landscape ? 90 : CGRectGetMaxY(hero.frame) + 12;
    CGFloat availW = landscape ? b.size.width - x0 - m : b.size.width - 2*m;
    NSInteger cols = 2;
    CGFloat gap = 12;
    CGFloat cw = (availW - gap*(cols-1))/cols;
    CGFloat ch = landscape ? 84 : 100;
    for (NSUInteger i=0;i<items.count;i++) {
        NSInteger row=i/cols, col=i%cols;
        UIView *card=[self makeCard];
        card.frame=CGRectMake(x0+col*(cw+gap), y0+row*(ch+gap), cw, ch);
        UILabel *k=[self makeLabel:[RPTheme small:15] color:[RPTheme textDim]];
        k.text=items[i][0]; k.frame=CGRectMake(14,12,cw-28,20);
        UILabel *v=[self makeLabel:[RPTheme mono:26] color:[RPTheme text]];
        v.text=items[i][1]; v.frame=CGRectMake(14,36,cw-28,32);
        UILabel *s=[self makeLabel:[RPTheme body:14] color:[RPTheme textDim]];
        s.text=items[i][2]; s.frame=CGRectMake(14, ch-28,cw-28,22);
        [card addSubview:k]; [card addSubview:v]; [card addSubview:s];
        [self.contentView addSubview:card];
    }

    id traffic = ops[@"traffic_lines"];
    if ([traffic isKindOfClass:[NSArray class]] && [traffic count] > 0) {
        CGFloat ty = landscape ? y0 + 2*(ch+gap) + 4 : y0 + 2*(ch+gap) + 8;
        if (ty + 60 < b.size.height - m) {
            UIView *tcard = [self makeCard];
            tcard.frame = CGRectMake(m, ty, b.size.width-2*m, MIN(100, b.size.height - ty - m));
            UILabel *tk = [self makeLabel:[RPTheme small:15] color:[RPTheme accent]];
            tk.text = @"网络流量"; tk.frame = CGRectMake(14, 10, tcard.bounds.size.width-28, 20);
            [tcard addSubview:tk];
            CGFloat ly = 34;
            for (NSUInteger i=0; i<MIN(3, [traffic count]); i++) {
                UILabel *l = [self makeLabel:[RPTheme mono:15] color:[RPTheme text]];
                l.text = [NSString stringWithFormat:@"%@", traffic[i]];
                l.frame = CGRectMake(14, ly, tcard.bounds.size.width-28, 20);
                [tcard addSubview:l];
                ly += 22;
            }
            [self.contentView addSubview:tcard];
        }
    }
}
@end

@implementation RPVpsPageVC
- (void)applyState:(NSDictionary *)state baseURL:(NSString *)baseURL {
    (void)baseURL;
    CGRect b = self.contentView.bounds;
    NSDictionary *v = state[@"vps"] ?: @{};
    NSString *fp = [NSString stringWithFormat:@"vps|%@", RPHashObject(v)];
    if ([self shouldSkipRebuildForKey:fp bounds:b]) return;
    [self clearContent];
    BOOL landscape = [self isLandscape];
    CGFloat m = [self mInset];

    [self addClockBlockIn:self.contentView frame:CGRectMake(b.size.width-m-190, 2, 190, 78)];

    CGFloat heroW = landscape ? b.size.width*0.38 : b.size.width-2*m;
    CGFloat heroH = landscape ? 230 : 170;
    UIView *hero = [self makeCard];
    hero.frame = CGRectMake(m, 90, heroW, heroH);
    UILabel *hk = [self makeLabel:[RPTheme small:16] color:[RPTheme textDim]];
    hk.text = @"本月用量"; hk.frame = CGRectMake(18, 18, heroW-36, 22);
    UILabel *pct = [self makeLabel:[RPTheme hero:76] color:[RPTheme accent]];
    pct.text = [NSString stringWithFormat:@"%@%%", v[@"percent"] ?: @"-"];
    pct.frame = CGRectMake(18, 50, heroW-36, 90);
    NSString *st = [NSString stringWithFormat:@"%@", v[@"status"]?:@""];
    UIColor *pillColor = ([st rangeOfString:@"超"].location != NSNotFound) || ([[st lowercaseString] rangeOfString:@"over"].location != NSNotFound) ? [RPTheme bad] : [RPTheme ok];
    UIView *pill = [self makePill:st.length?st:@"正常" color:pillColor];
    pill.frame = CGRectMake(18, heroH-44, pill.bounds.size.width, 28);
    [hero addSubview:hk]; [hero addSubview:pct]; [hero addSubview:pill];
    [self.contentView addSubview:hero];

    NSArray *rows = @[
        @[@"已用", [NSString stringWithFormat:@"%@", v[@"used"]?:@"-"]],
        @[@"剩余", [NSString stringWithFormat:@"%@", v[@"remain"]?:@"-"]],
        @[@"周期", [NSString stringWithFormat:@"%@", v[@"cycle"]?:@"-"]],
        @[@"状态", st.length?st:@"-"],
    ];
    CGFloat x0 = landscape ? heroW + m + 14 : m;
    CGFloat y0 = landscape ? 90 : CGRectGetMaxY(hero.frame) + 14;
    CGFloat availW = landscape ? b.size.width - x0 - m : b.size.width - 2*m;
    CGFloat gap = 12;
    CGFloat ch = landscape ? 50 : 80;
    if (landscape) {
        ch = (heroH - gap*3) / 4.0;
        for (NSUInteger i=0;i<rows.count;i++) {
            UIView *card=[self makeCard];
            card.frame = CGRectMake(x0, y0 + i*(ch+gap), availW, ch);
            UILabel *k=[self makeLabel:[RPTheme small:15] color:[RPTheme textDim]];
            k.text=rows[i][0]; k.frame=CGRectMake(16, (ch-20)/2, 80, 20);
            UILabel *val=[self makeLabel:[RPTheme mono:24] color:[RPTheme text]];
            val.text=rows[i][1]; val.frame=CGRectMake(100, (ch-30)/2, availW-120, 30);
            [card addSubview:k]; [card addSubview:val];
            [self.contentView addSubview:card];
        }
    } else {
        NSInteger cols=2;
        CGFloat cw=(availW-gap)/2;
        ch = 90;
        for (NSUInteger i=0;i<rows.count;i++) {
            NSInteger row=i/cols, col=i%cols;
            UIView *card=[self makeCard];
            card.frame = CGRectMake(x0+col*(cw+gap), y0+row*(ch+gap), cw, ch);
            UILabel *k=[self makeLabel:[RPTheme small:15] color:[RPTheme textDim]];
            k.text=rows[i][0]; k.frame=CGRectMake(14,12,cw-28,20);
            UILabel *val=[self makeLabel:[RPTheme mono:24] color:[RPTheme text]];
            val.text=rows[i][1]; val.frame=CGRectMake(14,40,cw-28,36);
            [card addSubview:k]; [card addSubview:val];
            [self.contentView addSubview:card];
        }
    }
}
@end

#pragma mark - Spark

@interface RPSparkView : UIView
@property (nonatomic, copy) NSString *points;
@end
@implementation RPSparkView
- (void)drawRect:(CGRect)rect {
    if (self.points.length == 0 || rect.size.width < 2) return;
    UIBezierPath *path = [UIBezierPath bezierPath];
    BOOL started = NO;
    for (NSString *pair in [self.points componentsSeparatedByString:@" "]) {
        NSArray *xy = [pair componentsSeparatedByString:@","];
        if (xy.count < 2) continue;
        CGFloat x = [xy[0] doubleValue] / 140.0 * rect.size.width;
        CGFloat y = [xy[1] doubleValue] / 54.0 * rect.size.height;
        if (!started) { [path moveToPoint:CGPointMake(x, y)]; started = YES; }
        else [path addLineToPoint:CGPointMake(x, y)];
    }
    if (!started) return;
    [[UIColor whiteColor] setStroke];
    path.lineWidth = 3;
    path.lineJoinStyle = kCGLineJoinRound;
    path.lineCapStyle = kCGLineCapRound;
    [path stroke];
}
@end

#pragma mark - News

@implementation RPNewsPageVC
- (void)applyState:(NSDictionary *)state baseURL:(NSString *)baseURL {
    CGRect b = self.contentView.bounds;
    NSArray *items = nil;
    NSDictionary *meta = nil;
    NSString *kind = self.feedKind ?: @"";
    BOOL xMode = [kind isEqualToString:@"x"];
    NSString *heading = @"每日新闻";
    if (self.github) {
        items = state[@"news"][@"github_items"];
        if (![items isKindOfClass:[NSArray class]] || items.count == 0) {
            NSArray *lines = state[@"news"][@"github"] ?: @[];
            NSMutableArray *built = [NSMutableArray array];
            for (id line in lines) {
                [built addObject:@{ @"name": [NSString stringWithFormat:@"%@", line], @"description": @"", @"stars": @0, @"language": @"GitHub" }];
            }
            items = built;
        }
        meta = state[@"news"][@"github_meta"];
        heading = @"AI · 热门项目集锦";
    } else if (xMode) {
        items = state[@"news"][@"x_items"];
        if (![items isKindOfClass:[NSArray class]] || items.count == 0) {
            NSArray *lines = state[@"news"][@"x"] ?: @[];
            NSMutableArray *built = [NSMutableArray array];
            for (id line in lines) {
                if ([[NSString stringWithFormat:@"%@", line] length] == 0) continue;
                [built addObject:@{ @"title": [NSString stringWithFormat:@"%@", line], @"summary": @"" }];
            }
            items = built;
        }
        heading = @"X · 动态";
    } else if ([kind isEqualToString:@"xhs"]) {
        items = state[@"news"][@"xhs_items"];
        heading = @"小红书热门";
    } else if ([kind isEqualToString:@"bili"]) {
        items = state[@"news"][@"bili_items"];
        heading = @"哔哩哔哩热门";
    } else {
        items = state[@"news"][@"daily_items"];
        if (![items isKindOfClass:[NSArray class]] || items.count == 0) {
            NSArray *lines = state[@"news"][@"daily"] ?: @[];
            NSMutableArray *built = [NSMutableArray array];
            for (id line in lines) {
                [built addObject:@{ @"title": [NSString stringWithFormat:@"%@", line], @"summary": @"" }];
            }
            items = built;
        }
    }
    NSString *fp = [NSString stringWithFormat:@"news3-%d-%@|%@|%@", self.github?1:0, kind, RPHashObject(items), baseURL?:@""];
    if ([self shouldSkipRebuildForKey:fp bounds:b]) return;
    [self clearContent];
    CGFloat m = [self mInset];
    BOOL landscape = [self isLandscape];

    if (self.github && [meta isKindOfClass:[NSDictionary class]]) {
        UILabel *sub = [self makeLabel:[RPTheme small:18] color:[RPTheme textDim]];
        sub.text = [NSString stringWithFormat:@"%@ · %@", meta[@"source"]?:@"GitHub", meta[@"window_start"]?:@""];
        sub.frame = CGRectMake(m, 4, b.size.width-2*m, 24);
        [self.contentView addSubview:sub];
    }
    (void)heading;

    if ([kind isEqualToString:@"x"]) {
        [self layoutTrendGrid:items bounds:b];
        return;
    }
    if ([kind isEqualToString:@"xhs"]) {
        [self layoutXhsBoard:items bounds:b base:baseURL];
        return;
    }
    if ([kind isEqualToString:@"bili"]) {
        [self layoutBiliBoard:items bounds:b base:baseURL];
        return;
    }

    CGFloat top = self.github ? 32 : 8;
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, top, b.size.width, b.size.height-top)];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    scroll.showsVerticalScrollIndicator = YES;
    [self.contentView addSubview:scroll];

    CGFloat gap = 12;
    CGFloat y = 4;
    NSInteger maxN = self.github ? MIN(12, (NSInteger)items.count) : MIN(10, (NSInteger)items.count);
    if (maxN == 0) {
        UILabel *empty = [self makeLabel:[RPTheme body:22] color:[RPTheme textDim]];
        if ([kind isEqualToString:@"xhs"]) empty.text = @"正在通过代理读取小红书热榜，两小时更新一次。";
        else if ([kind isEqualToString:@"bili"]) empty.text = @"正在读取哔哩哔哩热门，两小时更新一次。";
        else if ([kind isEqualToString:@"x"]) empty.text = @"正在通过代理读取 X 全球热门话题，两小时更新一次。";
        else empty.text = @"这一页还没有内容。检查设置里的接口地址，以及是否需要代理。";
        empty.frame = CGRectMake(m, 12, b.size.width-2*m, 160);
        [scroll addSubview:empty];
    }
    CGFloat avail = MAX(80, b.size.height - top - 8);
    NSInteger slots = self.github ? MIN(4, MAX(1, maxN == 0 ? 1 : maxN)) : MIN(5, MAX(1, maxN == 0 ? 1 : maxN));
    CGFloat cardH = floor((avail - gap * MAX(slots - 1, 0)) / slots);
    if (!self.github && cardH < 118 && slots > 4) {
        slots = 4;
        cardH = floor((avail - gap * MAX(slots - 1, 0)) / slots);
    }
    if (cardH > (self.github ? 188 : 132)) cardH = self.github ? 188 : 132;
    if (cardH < 96) cardH = 96;
    maxN = MIN(maxN, slots);
    for (NSInteger i=0; i<maxN; i++) {
        NSDictionary *it = items[i];
        UIView *card = [self makeCard];
        card.frame = CGRectMake(m, y, b.size.width-2*m, cardH);
        card.userInteractionEnabled = YES;
        card.tag = 7000 + i;

        NSString *t = @"";
        NSString *s = @"";
        NSString *metaLine = @"";
        NSURL *imgURL = nil;
        if (self.github) {
            t = [NSString stringWithFormat:@"%@", it[@"full_name"] ?: it[@"name"] ?: @""];
            s = [NSString stringWithFormat:@"%@", it[@"description"] ?: @""];
            if ([s isEqualToString:@"(null)"]) s = @"";
            metaLine = [NSString stringWithFormat:@"★ %@  ·  %@  ·  forks %@", it[@"stars"]?:@"0", it[@"language"]?:@"--", it[@"forks"]?:@"0"];
            NSString *img = [NSString stringWithFormat:@"%@", it[@"image_url"] ?: @""];
            if (img.length && ![img isEqualToString:@"(null)"]) imgURL = [self absURL:img base:baseURL];
            CGFloat leftW = floor(card.bounds.size.width * 0.40);
            CGFloat thumb = 56;
            if (imgURL) {
                UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(14, 14, thumb, thumb)];
                iv.contentMode = UIViewContentModeScaleAspectFill;
                iv.clipsToBounds = YES;
                iv.layer.cornerRadius = thumb / 2.0;
                iv.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12];
                [card addSubview:iv];
                [self loadImageURL:imgURL into:iv];
            }
            UILabel *idx = [self makeLabel:[RPTheme mono:22] color:[RPTheme accent]];
            idx.text = [NSString stringWithFormat:@"%02ld", (long)(i+1)];
            idx.frame = CGRectMake(imgURL ? 78 : 16, 12, 52, 26);
            [card addSubview:idx];
            UILabel *tl = [self makeLabel:[RPTheme title:24] color:[RPTheme text]];
            tl.text = t;
            tl.numberOfLines = 2;
            tl.frame = CGRectMake(14, imgURL ? 76 : 44, leftW - 20, 52);
            [card addSubview:tl];
            UILabel *ml = [self makeLabel:[RPTheme body:16] color:[RPTheme textDim]];
            ml.text = metaLine;
            ml.numberOfLines = 2;
            ml.frame = CGRectMake(14, cardH - 42, leftW - 20, 32);
            [card addSubview:ml];
            UILabel *sl = [self makeLabel:[RPTheme readable:20] color:[RPTheme text]];
            sl.text = s.length ? s : @"这个项目没有简介。";
            sl.numberOfLines = 5;
            sl.frame = CGRectMake(leftW + 8, 14, card.bounds.size.width - leftW - 22, cardH - 28);
            [card addSubview:sl];
            UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rpNewsTap:)];
            [card addGestureRecognizer:tap];
            objc_setAssociatedObject(card, &kRPImageURLKey, @{ @"item": it ?: @{}, @"base": baseURL ?: @"", @"github": @YES }, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [scroll addSubview:card];
            y += cardH + gap;
            continue;
        } else {
            t = [NSString stringWithFormat:@"%@", it[@"title"] ?: it[@"name"] ?: @""];
            s = [NSString stringWithFormat:@"%@", it[@"summary"] ?: @""];
            NSString *img = [NSString stringWithFormat:@"%@", it[@"image_url"] ?: @""];
            if (img.length) imgURL = [self absURL:img base:baseURL];
        }

        CGFloat textX = 18;
        if (imgURL) {
            CGFloat thumb = self.github ? 64 : 120;
            UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(14, (cardH - thumb) / 2.0, thumb, thumb)];
            iv.contentMode = UIViewContentModeScaleAspectFill;
            iv.clipsToBounds = YES;
            iv.layer.cornerRadius = self.github ? thumb / 2.0 : 8;
            iv.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.18];
            [card addSubview:iv];
            [self loadImageURL:imgURL into:iv];
            textX = 14 + thumb + 12;
        }

        UILabel *idx = [self makeLabel:[RPTheme mono:28] color:[RPTheme accent]];
        idx.text = [NSString stringWithFormat:@"%02ld", (long)(i+1)];
        idx.frame = CGRectMake(textX, 12, 60, 32);
        [card addSubview:idx];

        UILabel *tl = [self makeLabel:[RPTheme title:28] color:[RPTheme text]];
        tl.text = t;
        tl.numberOfLines = 2;
        tl.frame = CGRectMake(textX+56, 8, card.bounds.size.width - textX - 70, MIN(52, cardH * 0.42));
        [card addSubview:tl];

        if (metaLine.length) {
            UILabel *ml = [self makeLabel:[RPTheme body:22] color:[RPTheme accent]];
            ml.text = metaLine;
            ml.frame = CGRectMake(textX, cardH-36, card.bounds.size.width-textX-24, 26);
            [card addSubview:ml];
        } else if (s.length) {
            UILabel *sl = [self makeLabel:[RPTheme body:22] color:[RPTheme textDim]];
            sl.text = s;
            sl.numberOfLines = 2;
            sl.frame = CGRectMake(textX, cardH-40, card.bounds.size.width-textX-24, 32);
            [card addSubview:sl];
        }

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rpNewsTap:)];
        [card addGestureRecognizer:tap];
        objc_setAssociatedObject(card, &kRPImageURLKey, @{ @"item": it ?: @{}, @"base": baseURL ?: @"", @"github": @(self.github) }, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        [scroll addSubview:card];
        y += cardH + gap;
    }
    scroll.contentSize = CGSizeMake(b.size.width, y + m);
}
- (void)layoutTrendGrid:(NSArray *)items bounds:(CGRect)b {
    CGFloat m = [self mInset];
    CGFloat top = 8;
    NSString *place = @"";
    BOOL hasZh = NO;
    if ([items.firstObject isKindOfClass:[NSDictionary class]]) {
        place = [NSString stringWithFormat:@"%@", items.firstObject[@"place"] ?: @""];
        NSString *zh = [NSString stringWithFormat:@"%@", items.firstObject[@"zh"] ?: @""];
        hasZh = zh.length > 0 && ![zh isEqualToString:@"(null)"];
    }
    if ([place isEqualToString:@"(null)"]) place = @"";
    UILabel *sub = [self makeLabel:[RPTheme title:20] color:[UIColor whiteColor]];
    sub.text = place.length ? [NSString stringWithFormat:@"%@热门%@", place, hasZh ? @" · 已译成中文" : @""] : @"X 热门";
    sub.frame = CGRectMake(m, 4, b.size.width - 2 * m, 28);
    [self.contentView addSubview:sub];
    top = 38;
    NSInteger n = MIN(6, (NSInteger)items.count);
    if (n == 0) {
        UILabel *empty = [self makeLabel:[RPTheme body:22] color:[UIColor whiteColor]];
        empty.text = @"正在读取美国区 X 热门，并译成中文。这个榜没有中国区，全球榜目前多是日文和泰文。";
        empty.numberOfLines = 3;
        empty.frame = CGRectMake(m, top, b.size.width - 2 * m, 90);
        [self.contentView addSubview:empty];
        return;
    }
    BOOL land = b.size.width > b.size.height;
    NSInteger cols = land ? 2 : 1;
    NSInteger rows = (n + cols - 1) / cols;
    CGFloat gap = 8;
    CGFloat cardW = floor((b.size.width - 2 * m - gap * (cols - 1)) / cols);
    CGFloat cardH = floor((b.size.height - top - 8 - gap * (rows - 1)) / rows);
    if (cardH > 210) cardH = 210;
    if (cardH < 120) cardH = 120;
    for (NSInteger i = 0; i < n; i++) {
        NSDictionary *it = items[i];
        NSInteger col = i % cols;
        NSInteger row = i / cols;
        UIView *card = [self makeCard];
        card.frame = CGRectMake(m + col * (cardW + gap), top + row * (cardH + gap), cardW, cardH);
        card.tag = 7000 + i;
        card.userInteractionEnabled = YES;
        UILabel *rank = [self makeLabel:[RPTheme title:26] color:[RPTheme accent]];
        rank.text = [NSString stringWithFormat:@"%@", it[@"rank"] ?: @(i + 1)];
        rank.frame = CGRectMake(12, 10, 48, 30);
        [card addSubview:rank];
        NSString *zh = [NSString stringWithFormat:@"%@", it[@"zh"] ?: @""];
        if ([zh isEqualToString:@"(null)"]) zh = @"";
        NSString *title = [NSString stringWithFormat:@"%@", it[@"title"] ?: @""];
        if ([title isEqualToString:@"(null)"]) title = @"";
        NSString *blurb = [NSString stringWithFormat:@"%@", it[@"blurb"] ?: @""];
        if ([blurb isEqualToString:@"(null)"]) blurb = @"";
        NSString *score = [NSString stringWithFormat:@"%@", it[@"score"] ?: @""];
        if ([score isEqualToString:@"(null)"]) score = @"";
        UILabel *tl = [self makeLabel:[RPTheme readable:26] color:[RPTheme text]];
        tl.text = zh.length ? zh : title;
        tl.numberOfLines = 2;
        tl.frame = CGRectMake(64, 10, cardW - 78, 64);
        [card addSubview:tl];
        UILabel *origin = [self makeLabel:[RPTheme readable:18] color:[RPTheme textDim]];
        origin.text = (zh.length && title.length && ![zh isEqualToString:title]) ? title : @"";
        origin.numberOfLines = 2;
        origin.frame = CGRectMake(16, 78, cardW - 32, 44);
        [card addSubview:origin];
        UILabel *sl = [self makeLabel:[RPTheme readable:20] color:[RPTheme text]];
        NSMutableString *detail = [NSMutableString string];
        if (blurb.length) [detail appendString:blurb];
        if (score.length) {
            if (detail.length) [detail appendString:@"  ·  "];
            [detail appendString:score];
        }
        if (detail.length == 0) detail = [NSMutableString stringWithFormat:@"%@", it[@"summary"] ?: @""];
        sl.text = detail;
        sl.numberOfLines = 3;
        sl.frame = CGRectMake(16, cardH - 78, cardW - 32, 64);
        [card addSubview:sl];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rpNewsTap:)];
        [card addGestureRecognizer:tap];
        objc_setAssociatedObject(card, &kRPImageURLKey, @{ @"item": it ?: @{}, @"base": @"", @"github": @NO }, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self.contentView addSubview:card];
    }
}
/** Rank badge: 1 red, 2 orange, 3 accent, rest muted. */
- (UILabel *)rpRankBadge:(NSInteger)rank side:(CGFloat)side {
    UILabel *l = [self makeLabel:[RPTheme mono:floor(side * 0.56)] color:[UIColor whiteColor]];
    l.text = [NSString stringWithFormat:@"%ld", (long)rank];
    l.textAlignment = NSTextAlignmentCenter;
    l.numberOfLines = 1;
    l.adjustsFontSizeToFitWidth = YES;
    l.minimumScaleFactor = 0.6;
    UIColor *bg = rank == 1 ? [RPTheme bad] : rank == 2 ? [UIColor colorWithRed:1 green:0.55 blue:0.15 alpha:1] : rank == 3 ? [RPTheme accent] : [UIColor colorWithWhite:0 alpha:0.45];
    l.backgroundColor = bg;
    if (rank == 3) l.textColor = [UIColor blackColor];
    l.layer.cornerRadius = 8;
    l.clipsToBounds = YES;
    l.frame = CGRectMake(0, 0, side, side);
    return l;
}

/** Photo with a bottom gradient carrying title + heat, rank badge top-left. */
- (UIView *)rpXhsPhotoTile:(NSDictionary *)it rank:(NSInteger)rank frame:(CGRect)f base:(NSString *)baseURL titleSize:(CGFloat)ts {
    UIView *tile = [[UIView alloc] initWithFrame:f];
    tile.layer.cornerRadius = 14;
    tile.clipsToBounds = YES;
    tile.backgroundColor = [RPTheme cardTint:rank + [self rpPageColorBias]];
    UIImageView *iv = [[UIImageView alloc] initWithFrame:tile.bounds];
    iv.contentMode = UIViewContentModeScaleAspectFill;
    iv.clipsToBounds = YES;
    [tile addSubview:iv];
    NSString *title = RPStringish(it[@"title"]);
    NSString *img = RPStringish(it[@"image_url"]);
    if (img.length) {
        [self loadImageURL:[self absURL:img base:baseURL] into:iv];
    } else {
        // No photo found: a large first character on the tint, not an empty hole.
        UILabel *mark = [self makeLabel:[RPTheme title:floor(MIN(f.size.width, f.size.height) * 0.42)] color:[[UIColor whiteColor] colorWithAlphaComponent:0.85]];
        mark.text = title.length ? [title substringToIndex:1] : @"红";
        mark.textAlignment = NSTextAlignmentCenter;
        mark.frame = CGRectMake(0, 0, f.size.width, f.size.height * 0.72);
        [tile addSubview:mark];
    }
    CGFloat shadeH = MIN(f.size.height, ts * 2 + 70);
    CAGradientLayer *shade = [CAGradientLayer layer];
    shade.frame = CGRectMake(0, f.size.height - shadeH, f.size.width, shadeH);
    shade.colors = @[ (id)[UIColor colorWithWhite:0 alpha:0].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.82].CGColor ];
    [tile.layer addSublayer:shade];
    NSString *heat = RPStringish(it[@"heat"]);
    UILabel *hl = [self makeLabel:[RPTheme body:MAX(18, ts * 0.72)] color:[UIColor colorWithRed:1 green:0.82 blue:0.6 alpha:1]];
    hl.text = heat.length ? [NSString stringWithFormat:@"🔥 %@", heat] : @"";
    hl.numberOfLines = 1;
    CGFloat hlH = heat.length ? ceil(hl.font.lineHeight) : 0;
    hl.frame = CGRectMake(14, f.size.height - hlH - 10, f.size.width - 28, hlH);
    [tile addSubview:hl];
    UILabel *tl = [self makeLabel:[RPTheme readable:ts] color:[UIColor whiteColor]];
    tl.text = title;
    tl.numberOfLines = 2;
    CGFloat tlH = ceil(tl.font.lineHeight * 2.1);
    tl.frame = CGRectMake(14, CGRectGetMinY(hl.frame) - tlH - 2, f.size.width - 28, tlH);
    [tile addSubview:tl];
    UILabel *badge = [self rpRankBadge:rank side:MAX(34, floor(ts * 1.5))];
    badge.frame = CGRectOffset(badge.frame, 10, 10);
    [tile addSubview:badge];
    tile.userInteractionEnabled = YES;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rpNewsTap:)];
    [tile addGestureRecognizer:tap];
    objc_setAssociatedObject(tile, &kRPImageURLKey, @{ @"item": it ?: @{}, @"base": baseURL ?: @"", @"github": @NO }, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return tile;
}

/** Text row: rank badge, title, heat bar scaled to the hottest item, heat value. */
- (UIView *)rpXhsListRow:(NSDictionary *)it rank:(NSInteger)rank frame:(CGRect)f maxHeat:(double)maxHeat {
    UIView *row = [[UIView alloc] initWithFrame:f];
    row.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28];
    row.layer.cornerRadius = 10;
    row.clipsToBounds = YES;
    CGFloat side = MIN(f.size.height - 12, 40);
    UILabel *badge = [self rpRankBadge:rank side:side];
    badge.frame = CGRectMake(10, (f.size.height - side) / 2.0, side, side);
    [row addSubview:badge];
    double v = [it[@"heat_value"] doubleValue];
    CGFloat textX = CGRectGetMaxX(badge.frame) + 12;
    CGFloat heatW = 108;
    UILabel *tl = [self makeLabel:[RPTheme readable:22] color:[RPTheme text]];
    tl.text = RPStringish(it[@"title"]);
    tl.numberOfLines = 1;
    tl.lineBreakMode = NSLineBreakByTruncatingTail;
    tl.frame = CGRectMake(textX, 6, f.size.width - textX - heatW - 14, f.size.height - 20);
    [row addSubview:tl];
    // Heat bar under the title: share of the #1 item's heat.
    CGFloat barW = f.size.width - textX - heatW - 14;
    UIView *track = [[UIView alloc] initWithFrame:CGRectMake(textX, f.size.height - 12, barW, 5)];
    track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    track.layer.cornerRadius = 2.5;
    [row addSubview:track];
    if (maxHeat > 0 && v > 0) {
        UIView *fill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, MAX(6, barW * MIN(1.0, v / maxHeat)), 5)];
        fill.backgroundColor = [UIColor colorWithRed:1 green:0.36 blue:0.42 alpha:1];
        fill.layer.cornerRadius = 2.5;
        [track addSubview:fill];
    }
    UILabel *hl = [self makeLabel:[RPTheme mono:20] color:[RPTheme textDim]];
    hl.text = RPStringish(it[@"heat"]);
    hl.textAlignment = NSTextAlignmentRight;
    hl.numberOfLines = 1;
    hl.frame = CGRectMake(f.size.width - heatW - 12, 0, heatW, f.size.height);
    [row addSubview:hl];
    return row;
}

/* 小红书: up to 16 topics in three bands, filling the page instead of 4 small cards.
   Portrait (768×~930): lead photo + 2×3 photo grid + 9-row ranked list.
   Landscape (1024×~670): lead photo + 2×2 grid on the left, ranked list on the right. */
- (void)layoutXhsBoard:(NSArray *)items bounds:(CGRect)b base:(NSString *)baseURL {
    CGFloat m = [self mInset];
    NSMutableArray *list = [NSMutableArray array];
    for (id it in items) if ([it isKindOfClass:[NSDictionary class]] && RPStringish(it[@"title"]).length) [list addObject:it];
    if (list.count == 0) {
        UILabel *empty = [self makeLabel:[RPTheme body:24] color:[UIColor whiteColor]];
        empty.text = @"正在读取小红书热榜，两小时更新一次。";
        empty.frame = CGRectMake(m, 12, b.size.width - 2 * m, 80);
        [self.contentView addSubview:empty];
        return;
    }
    double maxHeat = 0;
    for (NSDictionary *it in list) maxHeat = MAX(maxHeat, [it[@"heat_value"] doubleValue]);
    CGFloat gap = 10;
    CGFloat top = 6;
    CGFloat W = b.size.width - 2 * m;
    CGFloat H = b.size.height - top - m;
    BOOL land = b.size.width > b.size.height;
    NSInteger next = 0;
    if (land) {
        CGFloat leftW = floor(W * 0.58);
        CGFloat leadH = floor(H * 0.48);
        [self.contentView addSubview:[self rpXhsPhotoTile:list[0] rank:1 frame:CGRectMake(m, top, leftW, leadH) base:baseURL titleSize:30]];
        next = 1;
        CGFloat gridTop = top + leadH + gap;
        CGFloat cellW = floor((leftW - gap) / 2.0);
        CGFloat cellH = floor((H - leadH - gap * 2) / 2.0);
        for (NSInteger i = 0; i < 4 && next < (NSInteger)list.count; i++, next++) {
            CGRect f = CGRectMake(m + (i % 2) * (cellW + gap), gridTop + (i / 2) * (cellH + gap), cellW, cellH);
            [self.contentView addSubview:[self rpXhsPhotoTile:list[next] rank:next + 1 frame:f base:baseURL titleSize:22]];
        }
        CGFloat listX = m + leftW + gap * 1.5;
        CGFloat listW = W - leftW - gap * 1.5;
        NSInteger rows = MIN(11, (NSInteger)list.count - next);
        CGFloat rowH = rows > 0 ? floor((H - gap * 0.6 * (rows - 1)) / MAX(rows, 9)) : 0;
        for (NSInteger r = 0; r < rows; r++, next++) {
            CGRect f = CGRectMake(listX, top + r * (rowH + gap * 0.6), listW, rowH);
            [self.contentView addSubview:[self rpXhsListRow:list[next] rank:next + 1 frame:f maxHeat:maxHeat]];
        }
        return;
    }
    CGFloat leadH = floor(H * 0.30);
    [self.contentView addSubview:[self rpXhsPhotoTile:list[0] rank:1 frame:CGRectMake(m, top, W, leadH) base:baseURL titleSize:34]];
    next = 1;
    CGFloat gridTop = top + leadH + gap;
    CGFloat cellW = floor((W - gap * 2) / 3.0);
    CGFloat cellH = floor(H * 0.20);
    for (NSInteger i = 0; i < 6 && next < (NSInteger)list.count; i++, next++) {
        CGRect f = CGRectMake(m + (i % 3) * (cellW + gap), gridTop + (i / 3) * (cellH + gap), cellW, cellH);
        [self.contentView addSubview:[self rpXhsPhotoTile:list[next] rank:next + 1 frame:f base:baseURL titleSize:20]];
    }
    NSInteger gridRows = MIN(2, (NSInteger)ceil((MIN(6, (NSInteger)list.count - 1)) / 3.0));
    CGFloat listTop = gridTop + gridRows * (cellH + gap);
    CGFloat listH = top + H - listTop;
    NSInteger rows = MIN(9, (NSInteger)list.count - next);
    if (rows <= 0) return;
    CGFloat rowGap = 6;
    CGFloat rowH = floor((listH - rowGap * (rows - 1)) / MAX(rows, 7));
    rowH = MIN(rowH, 60);
    for (NSInteger r = 0; r < rows; r++, next++) {
        CGRect f = CGRectMake(m, listTop + r * (rowH + rowGap), W, rowH);
        [self.contentView addSubview:[self rpXhsListRow:list[next] rank:next + 1 frame:f maxHeat:maxHeat]];
    }
}

/** B站 video thumbnail (16:10) with duration pill bottom-right and rank badge. */
- (UIView *)rpBiliTile:(NSDictionary *)it rank:(NSInteger)rank frame:(CGRect)f base:(NSString *)baseURL titleSize:(CGFloat)ts lines:(NSInteger)lines {
    UIView *tile = [[UIView alloc] initWithFrame:f];
    tile.layer.cornerRadius = 14;
    tile.clipsToBounds = YES;
    tile.backgroundColor = [UIColor colorWithWhite:0 alpha:0.32];
    // Bilibili covers are 16:10; keep that shape and put text under it.
    CGFloat imgH = floor(f.size.width * 10.0 / 16.0);
    CGFloat textH = f.size.height - imgH;
    if (textH < ts * 2.6) { imgH = f.size.height - ts * 2.6; textH = f.size.height - imgH; }
    UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, f.size.width, imgH)];
    iv.contentMode = UIViewContentModeScaleAspectFill;
    iv.clipsToBounds = YES;
    iv.backgroundColor = [RPTheme cardTint:rank + [self rpPageColorBias]];
    [tile addSubview:iv];
    NSString *img = RPStringish(it[@"image_url"]);
    if (img.length) [self loadImageURL:[self absURL:img base:baseURL] into:iv];
    NSString *dur = RPStringish(it[@"duration"]);
    if (dur.length) {
        UILabel *dl = [self makeLabel:[RPTheme mono:MAX(16, ts * 0.72)] color:[UIColor whiteColor]];
        dl.text = [NSString stringWithFormat:@" %@ ", dur];
        dl.numberOfLines = 1;
        dl.backgroundColor = [UIColor colorWithWhite:0 alpha:0.68];
        dl.layer.cornerRadius = 6;
        dl.clipsToBounds = YES;
        [dl sizeToFit];
        dl.frame = CGRectMake(f.size.width - dl.bounds.size.width - 10, imgH - dl.bounds.size.height - 8, dl.bounds.size.width, dl.bounds.size.height + 2);
        [tile addSubview:dl];
    }
    NSString *reason = RPStringish(it[@"reason"]);
    if (reason.length) {
        UILabel *rl = [self makeLabel:[RPTheme small:MAX(15, ts * 0.66)] color:[UIColor whiteColor]];
        rl.text = [NSString stringWithFormat:@" %@ ", reason];
        rl.numberOfLines = 1;
        rl.backgroundColor = [UIColor colorWithRed:0.98 green:0.45 blue:0.6 alpha:0.92];  // bilibili pink
        rl.layer.cornerRadius = 6;
        rl.clipsToBounds = YES;
        [rl sizeToFit];
        rl.frame = CGRectMake(f.size.width - rl.bounds.size.width - 10, 10, rl.bounds.size.width, rl.bounds.size.height + 2);
        [tile addSubview:rl];
    }
    UILabel *badge = [self rpRankBadge:rank side:MAX(32, floor(ts * 1.45))];
    badge.frame = CGRectOffset(badge.frame, 10, 10);
    [tile addSubview:badge];
    UILabel *tl = [self makeLabel:[RPTheme readable:ts] color:[RPTheme text]];
    tl.text = RPStringish(it[@"title"]);
    tl.numberOfLines = lines;
    // Leave room for the stats line under it (small landscape tiles overlapped by ~5 pt).
    CGFloat statsH = ceil([RPTheme small:MAX(15, ts * 0.74)].lineHeight);
    CGFloat tlH = MIN(f.size.height - imgH - statsH - 14, ceil(tl.font.lineHeight * (lines + 0.1)));
    tl.frame = CGRectMake(12, imgH + 6, f.size.width - 24, MAX(0, tlH));
    [tile addSubview:tl];
    NSMutableArray *bits = [NSMutableArray array];
    if (RPStringish(it[@"views"]).length) [bits addObject:[@"▶ " stringByAppendingString:RPStringish(it[@"views"])]];
    if (RPStringish(it[@"likes"]).length) [bits addObject:[@"👍 " stringByAppendingString:RPStringish(it[@"likes"])]];
    if (lines > 1 && RPStringish(it[@"danmaku"]).length) [bits addObject:[@"弹 " stringByAppendingString:RPStringish(it[@"danmaku"])]];
    NSString *author = RPStringish(it[@"author"]);
    UILabel *ml = [self makeLabel:[RPTheme small:MAX(15, ts * 0.74)] color:[RPTheme textDim]];
    ml.text = [bits componentsJoinedByString:@"  "];
    if (author.length && lines > 1) ml.text = [NSString stringWithFormat:@"UP %@   %@", author, ml.text];
    ml.numberOfLines = 1;
    ml.lineBreakMode = NSLineBreakByTruncatingTail;
    ml.frame = CGRectMake(12, f.size.height - ceil(ml.font.lineHeight) - 8, f.size.width - 24, ceil(ml.font.lineHeight));
    [tile addSubview:ml];
    tile.userInteractionEnabled = YES;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rpNewsTap:)];
    [tile addGestureRecognizer:tap];
    objc_setAssociatedObject(tile, &kRPImageURLKey, @{ @"item": it ?: @{}, @"base": baseURL ?: @"", @"github": @NO }, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return tile;
}

/** Ranked text row: badge, title, play-count bar against #1, plays. */
- (UIView *)rpBiliRow:(NSDictionary *)it rank:(NSInteger)rank frame:(CGRect)f maxViews:(double)maxViews {
    UIView *row = [[UIView alloc] initWithFrame:f];
    row.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28];
    row.layer.cornerRadius = 10;
    row.clipsToBounds = YES;
    CGFloat side = MIN(f.size.height - 12, 40);
    UILabel *badge = [self rpRankBadge:rank side:side];
    badge.frame = CGRectMake(10, (f.size.height - side) / 2.0, side, side);
    [row addSubview:badge];
    CGFloat textX = CGRectGetMaxX(badge.frame) + 12;
    CGFloat numW = 120;
    UILabel *tl = [self makeLabel:[RPTheme readable:21] color:[RPTheme text]];
    NSString *author = RPStringish(it[@"author"]);
    tl.text = author.length ? [NSString stringWithFormat:@"%@  ·  %@", RPStringish(it[@"title"]), author] : RPStringish(it[@"title"]);
    tl.numberOfLines = 1;
    tl.lineBreakMode = NSLineBreakByTruncatingTail;
    tl.frame = CGRectMake(textX, 6, f.size.width - textX - numW - 14, f.size.height - 20);
    [row addSubview:tl];
    CGFloat barW = f.size.width - textX - numW - 14;
    UIView *track = [[UIView alloc] initWithFrame:CGRectMake(textX, f.size.height - 12, barW, 5)];
    track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    track.layer.cornerRadius = 2.5;
    [row addSubview:track];
    double v = [it[@"view_value"] doubleValue];
    if (maxViews > 0 && v > 0) {
        UIView *fill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, MAX(6, barW * MIN(1.0, v / maxViews)), 5)];
        fill.backgroundColor = [UIColor colorWithRed:0.0 green:0.68 blue:0.93 alpha:1];  // bilibili blue
        fill.layer.cornerRadius = 2.5;
        [track addSubview:fill];
    }
    UILabel *nl = [self makeLabel:[RPTheme mono:19] color:[RPTheme textDim]];
    nl.text = RPStringish(it[@"views"]).length ? [@"▶ " stringByAppendingString:RPStringish(it[@"views"])] : @"";
    nl.textAlignment = NSTextAlignmentRight;
    nl.numberOfLines = 1;
    nl.frame = CGRectMake(f.size.width - numW - 12, 0, numW, f.size.height);
    [row addSubview:nl];
    return row;
}

/* 哔哩哔哩: same three bands as 小红书.
   Portrait: lead video (16:10 + title/UP/stats) | 3×2 video grid | ranked list.
   Landscape: lead + 2×2 grid on the left, ranked list on the right. */
- (void)layoutBiliBoard:(NSArray *)items bounds:(CGRect)b base:(NSString *)baseURL {
    CGFloat m = [self mInset];
    NSMutableArray *list = [NSMutableArray array];
    for (id it in items) if ([it isKindOfClass:[NSDictionary class]] && RPStringish(it[@"title"]).length) [list addObject:it];
    if (list.count == 0) {
        UILabel *empty = [self makeLabel:[RPTheme body:24] color:[UIColor whiteColor]];
        empty.text = @"正在读取哔哩哔哩热门。";
        empty.frame = CGRectMake(m, 12, b.size.width - 2 * m, 80);
        [self.contentView addSubview:empty];
        return;
    }
    double maxViews = 0;
    for (NSDictionary *it in list) maxViews = MAX(maxViews, [it[@"view_value"] doubleValue]);
    CGFloat gap = 10, top = 6;
    CGFloat W = b.size.width - 2 * m;
    CGFloat H = b.size.height - top - m;
    BOOL land = b.size.width > b.size.height;
    NSInteger next = 0;
    if (land) {
        CGFloat leftW = floor(W * 0.6);
        CGFloat leadH = floor(H * 0.52);
        [self.contentView addSubview:[self rpBiliTile:list[0] rank:1 frame:CGRectMake(m, top, leftW, leadH) base:baseURL titleSize:26 lines:2]];
        next = 1;
        CGFloat gridTop = top + leadH + gap;
        CGFloat cellW = floor((leftW - gap) / 2.0);
        CGFloat cellH = floor((H - leadH - gap * 2) / 2.0);
        for (NSInteger i = 0; i < 4 && next < (NSInteger)list.count; i++, next++) {
            CGRect f = CGRectMake(m + (i % 2) * (cellW + gap), gridTop + (i / 2) * (cellH + gap), cellW, cellH);
            [self.contentView addSubview:[self rpBiliTile:list[next] rank:next + 1 frame:f base:baseURL titleSize:19 lines:1]];
        }
        CGFloat listX = m + leftW + gap * 1.5;
        CGFloat listW = W - leftW - gap * 1.5;
        NSInteger rows = MIN(11, (NSInteger)list.count - next);
        CGFloat rowH = rows > 0 ? floor((H - gap * 0.6 * (rows - 1)) / MAX(rows, 9)) : 0;
        for (NSInteger r = 0; r < rows; r++, next++) {
            [self.contentView addSubview:[self rpBiliRow:list[next] rank:next + 1 frame:CGRectMake(listX, top + r * (rowH + gap * 0.6), listW, rowH) maxViews:maxViews]];
        }
        return;
    }
    CGFloat leadH = floor(H * 0.40);
    // Lead: wide 16:10 thumbnail would be 450 pt tall; use a side-by-side card instead.
    UIView *lead = [[UIView alloc] initWithFrame:CGRectMake(m, top, W, leadH)];
    lead.layer.cornerRadius = 14;
    lead.clipsToBounds = YES;
    lead.backgroundColor = [UIColor colorWithWhite:0 alpha:0.32];
    [self.contentView addSubview:lead];
    [lead addSubview:[self rpBiliTile:list[0] rank:1 frame:CGRectMake(0, 0, floor(W * 0.58), leadH) base:baseURL titleSize:24 lines:2]];
    NSDictionary *l0 = list[0];
    CGFloat sx = floor(W * 0.58) + 18, sw = W - sx - 16;
    NSArray *lines = @[
        @[@"UP 主", RPStringish(l0[@"author"])],
        @[@"分区", RPStringish(l0[@"tname"])],
        @[@"播放", RPStringish(l0[@"views"])],
        @[@"点赞", RPStringish(l0[@"likes"])],
        @[@"弹幕", RPStringish(l0[@"danmaku"])],
        @[@"投币", RPStringish(l0[@"coins"])],
    ];
    CGFloat ly = 16, lh = floor((leadH - 32) / 6.0);
    for (NSArray *pair in lines) {
        if ([pair[1] length] == 0) continue;
        UILabel *k = [self makeLabel:[RPTheme small:18] color:[RPTheme textDim]];
        k.text = pair[0];
        k.frame = CGRectMake(sx, ly, 64, lh);
        [lead addSubview:k];
        UILabel *v = [self makeLabel:[RPTheme title:22] color:[RPTheme text]];
        v.text = pair[1];
        v.numberOfLines = 1;
        v.lineBreakMode = NSLineBreakByTruncatingTail;
        v.frame = CGRectMake(sx + 68, ly, sw - 68, lh);
        [lead addSubview:v];
        ly += lh;
    }
    next = 1;
    CGFloat gridTop = top + leadH + gap;
    CGFloat cellW = floor((W - gap * 2) / 3.0);
    CGFloat cellH = floor(cellW * 10.0 / 16.0) + 64;
    for (NSInteger i = 0; i < 6 && next < (NSInteger)list.count; i++, next++) {
        CGRect f = CGRectMake(m + (i % 3) * (cellW + gap), gridTop + (i / 3) * (cellH + gap), cellW, cellH);
        [self.contentView addSubview:[self rpBiliTile:list[next] rank:next + 1 frame:f base:baseURL titleSize:18 lines:1]];
    }
    NSInteger gridRows = MIN(2, (NSInteger)ceil(MIN(6, (NSInteger)list.count - 1) / 3.0));
    CGFloat listTop = gridTop + gridRows * (cellH + gap);
    CGFloat listH = top + H - listTop;
    NSInteger rows = MIN(9, (NSInteger)list.count - next);
    if (rows <= 0 || listH < 40) return;
    CGFloat rowGap = 6;
    CGFloat rowH = MIN(56, floor((listH - rowGap * (rows - 1)) / rows));
    if (rowH < 38) {
        rows = MAX(1, (NSInteger)floor((listH + rowGap) / (38 + rowGap)));
        rowH = floor((listH - rowGap * (rows - 1)) / rows);
    }
    for (NSInteger r = 0; r < rows && next < (NSInteger)list.count; r++, next++) {
        [self.contentView addSubview:[self rpBiliRow:list[next] rank:next + 1 frame:CGRectMake(m, listTop + r * (rowH + rowGap), W, rowH) maxViews:maxViews]];
    }
}

- (void)layoutCoverGrid:(NSArray *)items bounds:(CGRect)b base:(NSString *)baseURL {
    CGFloat m = [self mInset];
    CGFloat top = 8;
    NSInteger n = MIN(4, (NSInteger)items.count);
    if (n == 0) {
        UILabel *empty = [self makeLabel:[RPTheme body:22] color:[UIColor whiteColor]];
        empty.text = @"正在读取热门内容。";
        empty.frame = CGRectMake(m, top, b.size.width - 2 * m, 80);
        [self.contentView addSubview:empty];
        return;
    }
    NSInteger cols = 2;
    NSInteger rows = (n + cols - 1) / cols;
    CGFloat gap = 12;
    CGFloat cardW = floor((b.size.width - 2 * m - gap) / cols);
    CGFloat cardH = floor((b.size.height - top - m - gap * MAX(rows - 1, 0)) / rows);
    if (cardH < 140) cardH = 140;
    for (NSInteger i = 0; i < n; i++) {
        NSDictionary *it = items[i];
        NSInteger col = i % cols;
        NSInteger row = i / cols;
        UIView *card = [self makeCard];
        card.frame = CGRectMake(m + col * (cardW + gap), top + row * (cardH + gap), cardW, cardH);
        card.tag = 7000 + i;
        card.userInteractionEnabled = YES;
        CGFloat imgSide = floor(MIN(cardH - 20, cardW * 0.36));
        if (imgSide < 72) imgSide = 72;
        CGRect imgFrame = CGRectMake(10, floor((cardH - imgSide) / 2.0), imgSide, imgSide);
        UIImageView *iv = [[UIImageView alloc] initWithFrame:imgFrame];
        iv.contentMode = UIViewContentModeScaleAspectFit;
        iv.clipsToBounds = YES;
        iv.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.15];
        iv.layer.cornerRadius = 8;
        [card addSubview:iv];
        NSString *img = [NSString stringWithFormat:@"%@", it[@"image_url"] ?: @""];
        if (img.length && ![img isEqualToString:@"(null)"]) {
            [self loadImageURL:[self absURL:img base:baseURL] into:iv];
        } else {
            UILabel *mark = [self makeLabel:[RPTheme readable:28] color:[RPTheme textDim]];
            NSString *title = [NSString stringWithFormat:@"%@", it[@"title"] ?: @""];
            mark.text = title.length >= 2 ? [title substringToIndex:2] : @"图";
            mark.textAlignment = NSTextAlignmentCenter;
            mark.frame = iv.bounds;
            mark.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [iv addSubview:mark];
        }
        CGFloat textX = CGRectGetMaxX(imgFrame) + 12;
        CGFloat textW = cardW - textX - 14;
        NSString *titleText = [NSString stringWithFormat:@"%@", it[@"title"] ?: @""];
        if ([titleText isEqualToString:@"(null)"]) titleText = @"";
        NSString *sumText = [NSString stringWithFormat:@"%@", it[@"summary"] ?: @""];
        if ([sumText isEqualToString:@"(null)"]) sumText = @"";
        if (sumText.length == 0) sumText = @"热门内容";
        UILabel *tl = [self makeLabel:[RPTheme readable:22] color:[RPTheme text]];
        tl.text = titleText;
        tl.numberOfLines = 3;
        tl.frame = CGRectMake(textX, 12, textW, floor(cardH * 0.48));
        [card addSubview:tl];
        UILabel *sl = [self makeLabel:[RPTheme readable:18] color:[RPTheme textDim]];
        sl.text = sumText;
        sl.numberOfLines = 4;
        sl.frame = CGRectMake(textX, CGRectGetMaxY(tl.frame) + 4, textW, cardH - CGRectGetMaxY(tl.frame) - 16);
        [card addSubview:sl];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rpNewsTap:)];
        [card addGestureRecognizer:tap];
        objc_setAssociatedObject(card, &kRPImageURLKey, @{ @"item": it ?: @{}, @"base": baseURL ?: @"", @"github": @NO }, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self.contentView addSubview:card];
    }
}
- (void)rpNewsTap:(UITapGestureRecognizer *)gr {
    if (gr.state != UIGestureRecognizerStateEnded) return;
    NSDictionary *pack = objc_getAssociatedObject(gr.view, &kRPImageURLKey);
    if (![pack isKindOfClass:[NSDictionary class]]) return;
    NSDictionary *it = pack[@"item"];
    BOOL github = [pack[@"github"] boolValue];
    NSString *base = pack[@"base"];
    if (github) {
        NSString *title = [NSString stringWithFormat:@"%@", it[@"full_name"] ?: it[@"name"] ?: @""];
        NSString *body = [NSString stringWithFormat:@"%@", it[@"description"] ?: @""];
        NSArray *topics = it[@"topics"];
        NSString *topicStr = [topics isKindOfClass:[NSArray class]] ? [topics componentsJoinedByString:@" · "] : @"";
        NSString *meta = [NSString stringWithFormat:@"★ %@  ·  %@  ·  %@\n%@", it[@"stars"]?:@"0", it[@"language"]?:@"--", it[@"url"]?:@"", topicStr];
        [self showDetailWithTitle:title body:body meta:meta imageURL:nil];
    } else {
        NSString *title = [NSString stringWithFormat:@"%@", it[@"title"] ?: @""];
        NSString *body = [NSString stringWithFormat:@"%@", it[@"summary"] ?: @""];
        NSString *link = [NSString stringWithFormat:@"%@", it[@"link"] ?: @""];
        NSURL *img = nil;
        NSString *iu = [NSString stringWithFormat:@"%@", it[@"image_url"] ?: @""];
        if (iu.length) img = [self absURL:iu base:base];
        [self showDetailWithTitle:title body:body meta:link imageURL:img];
    }
}
@end

@implementation RPPrintPageVC
- (void)applyState:(NSDictionary *)state baseURL:(NSString *)baseURL {
    (void)baseURL;
    CGRect b = self.contentView.bounds;
    NSDictionary *print = state[@"print"] ?: @{};
    NSString *fp = [NSString stringWithFormat:@"print-all|%@", RPHashObject(print)];
    if ([self shouldSkipRebuildForKey:fp bounds:b]) return;
    [self clearContent];
    BOOL landscape = [self isLandscape];
    CGFloat m = [self mInset];

    NSDictionary *p = [print[@"primary"] isKindOfClass:[NSDictionary class]] ? print[@"primary"] : @{};
    NSArray *printers = [print[@"printers"] isKindOfClass:[NSArray class]] ? print[@"printers"] : @[];
    if (p.count == 0 && printers.count && [printers[0] isKindOfClass:[NSDictionary class]]) p = printers[0];
    NSDictionary *temps = [p[@"temps"] isKindOfClass:[NSDictionary class]] ? p[@"temps"] : @{};
    NSArray *ams = [p[@"ams"] isKindOfClass:[NSArray class]] ? p[@"ams"] : @[];
    BOOL online = [p[@"online"] boolValue];
    double prog = [p[@"progress"] doubleValue];
    NSString *name = [NSString stringWithFormat:@"%@", p[@"name"] ?: @"打印机"];
    NSString *model = [NSString stringWithFormat:@"%@", p[@"model"] ?: @""];
    NSString *status = [NSString stringWithFormat:@"%@", p[@"statusText"] ?: p[@"status"] ?: @"-"];
    NSString *file = [NSString stringWithFormat:@"%@", p[@"fileName"] ?: @""];
    NSString *remain = [NSString stringWithFormat:@"%@", p[@"remainingMinutes"] ?: @"-"];
    NSString *layer = [NSString stringWithFormat:@"%@/%@", p[@"layer"]?:@"-", p[@"totalLayers"]?:@"-"];

    // ---- Header strip ----
    UIView *onlinePill = [self makePill:online?@"在线":@"离线" color:online?[RPTheme ok]:[RPTheme bad]];
    onlinePill.frame = CGRectMake(m, 4, onlinePill.bounds.size.width, 26);
    [self.contentView addSubview:onlinePill];
    UIView *stPill = [self makePill:status color:[RPTheme accent]];
    stPill.frame = CGRectMake(CGRectGetMaxX(onlinePill.frame)+8, 4, stPill.bounds.size.width, 26);
    [self.contentView addSubview:stPill];

    // ---- Layout regions ----
    CGFloat top = 36;
    CGFloat gap = 10;
    CGFloat bottomY = b.size.height - m;

    if (landscape) {
        // Left column: status + progress | Right: temps | Bottom full: AMS
        CGFloat leftW = b.size.width * 0.36;
        CGFloat rightX = m + leftW + gap;
        CGFloat rightW = b.size.width - rightX - m;
        CGFloat statusH = 200;
        UIView *statusCard = [self makeCard];
        statusCard.frame = CGRectMake(m, top, leftW, statusH);
        UILabel *nm = [self makeLabel:[RPTheme title:22] color:[RPTheme text]];
        nm.text = model.length ? [NSString stringWithFormat:@"%@ · %@", name, model] : name;
        nm.frame = CGRectMake(14, 10, leftW-28, 28);
        UILabel *progL = [self makeLabel:[RPTheme hero:64] color:[RPTheme accent]];
        progL.text = [NSString stringWithFormat:@"%.0f%%", prog];
        progL.frame = CGRectMake(14, 42, leftW-28, 72);
        UIView *track = [[UIView alloc] initWithFrame:CGRectMake(14, 118, leftW-28, 10)];
        track.backgroundColor = [RPTheme cardBorder]; track.layer.cornerRadius = 5;
        UIView *fill = [[UIView alloc] initWithFrame:CGRectMake(0,0,track.bounds.size.width*MAX(0,MIN(1,prog/100.0)),10)];
        fill.backgroundColor = [RPTheme accent]; fill.layer.cornerRadius = 5;
        [track addSubview:fill];
        UILabel *meta = [self makeLabel:[RPTheme body:15] color:[RPTheme textDim]];
        meta.text = [NSString stringWithFormat:@"剩余 %@ 分 · 层 %@", remain, layer];
        meta.frame = CGRectMake(14, 136, leftW-28, 22);
        UILabel *fl = [self makeLabel:[RPTheme body:14] color:[RPTheme text]];
        fl.text = file; fl.numberOfLines = 2;
        fl.frame = CGRectMake(14, 160, leftW-28, 34);
        [statusCard addSubview:nm]; [statusCard addSubview:progL]; [statusCard addSubview:track];
        [statusCard addSubview:meta]; [statusCard addSubview:fl];
        [self.contentView addSubview:statusCard];

        NSArray *tempItems = [self tempItemsFrom:temps];
        [self layoutTempCards:tempItems inRect:CGRectMake(rightX, top, rightW, statusH)];

        CGFloat amsTop = top + statusH + gap;
        [self layoutAMS:ams inRect:CGRectMake(m, amsTop, b.size.width-2*m, bottomY-amsTop) landscape:YES];
    } else {
        // Portrait: status hero, temps row, AMS fill
        CGFloat statusH = 168;
        UIView *statusCard = [self makeCard];
        statusCard.frame = CGRectMake(m, top, b.size.width-2*m, statusH);
        CGFloat sw = statusCard.bounds.size.width;
        UILabel *nm = [self makeLabel:[RPTheme title:22] color:[RPTheme text]];
        nm.text = model.length ? [NSString stringWithFormat:@"%@ · %@", name, model] : name;
        nm.frame = CGRectMake(14, 8, sw*0.55, 26);
        UILabel *progL = [self makeLabel:[RPTheme hero:56] color:[RPTheme accent]];
        progL.text = [NSString stringWithFormat:@"%.0f%%", prog];
        progL.frame = CGRectMake(14, 40, sw*0.40, 64);
        UILabel *meta = [self makeLabel:[RPTheme body:16] color:[RPTheme textDim]];
        meta.text = [NSString stringWithFormat:@"剩余 %@ 分\n层 %@", remain, layer];
        meta.numberOfLines = 2;
        meta.frame = CGRectMake(sw*0.45, 48, sw*0.50, 56);
        UIView *track = [[UIView alloc] initWithFrame:CGRectMake(14, 112, sw-28, 10)];
        track.backgroundColor = [RPTheme cardBorder]; track.layer.cornerRadius = 5;
        UIView *fill = [[UIView alloc] initWithFrame:CGRectMake(0,0,track.bounds.size.width*MAX(0,MIN(1,prog/100.0)),10)];
        fill.backgroundColor = [RPTheme accent]; fill.layer.cornerRadius = 5;
        [track addSubview:fill];
        UILabel *fl = [self makeLabel:[RPTheme body:14] color:[RPTheme text]];
        fl.text = file; fl.frame = CGRectMake(14, 128, sw-28, 30);
        [statusCard addSubview:nm]; [statusCard addSubview:progL]; [statusCard addSubview:meta];
        [statusCard addSubview:track]; [statusCard addSubview:fl];
        [self.contentView addSubview:statusCard];

        NSArray *tempItems = [self tempItemsFrom:temps];
        NSInteger shown = MIN(6, (NSInteger)tempItems.count);
        NSInteger tcols = shown <= 3 ? MAX(1, shown) : 3;
        NSInteger trows = (shown + tcols - 1) / tcols;
        CGFloat tch = trows > 1 ? 118 : 148;
        CGFloat ty = top + statusH + gap;
        [self layoutTempCards:[tempItems subarrayWithRange:NSMakeRange(0, shown)]
                       inRect:CGRectMake(m, ty, b.size.width-2*m, trows*tch + (trows-1)*8)];
        CGFloat amsTop = ty + trows*tch + (trows-1)*8 + 2;
        [self layoutAMS:ams inRect:CGRectMake(m, amsTop, b.size.width-2*m, bottomY-amsTop) landscape:NO];
    }
}

- (NSArray *)tempItemsFrom:(NSDictionary *)temps {
    NSMutableArray *tempItems = [NSMutableArray array];
    [tempItems addObject:@[@"热床", [NSString stringWithFormat:@"%@°", temps[@"bed"] ?: @"-"]]];
    [tempItems addObject:@[@"腔体", [NSString stringWithFormat:@"%@°", temps[@"chamber"] ?: @"-"]]];
    [tempItems addObject:@[@"喷嘴", [NSString stringWithFormat:@"%@°", temps[@"nozzle"] ?: @"-"]]];
    NSArray *nozzles = [temps[@"nozzles"] isKindOfClass:[NSArray class]] ? temps[@"nozzles"] : @[];
    for (id rawNozzle in nozzles) {
        if (![rawNozzle isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *n = rawNozzle;
        NSString *mark = [n[@"active"] boolValue] ? @"● " : @"";
        [tempItems addObject:@[[NSString stringWithFormat:@"%@%@", mark, n[@"name"] ?: @"喷嘴"],
                               [NSString stringWithFormat:@"%@°", n[@"temp"] ?: @"-"]]];
    }
    return tempItems;
}
- (void)layoutTempCards:(NSArray *)items inRect:(CGRect)rect {
    NSInteger n = (NSInteger)items.count;
    if (n <= 0 || rect.size.width < 20 || rect.size.height < 20) return;
    NSInteger cols = (n <= 4) ? n : 3;
    NSInteger rows = (n + cols - 1) / cols;
    CGFloat gap = 8;
    CGFloat cw = (rect.size.width - gap * (cols - 1)) / MAX(1, cols);
    CGFloat ch = (rect.size.height - gap * (rows - 1)) / MAX(1, rows);
    for (NSInteger i = 0; i < n; i++) {
        NSInteger row = i / cols, col = i % cols;
        if (row >= rows) break;
        UIView *card = [self makeCard];
        card.frame = CGRectMake(rect.origin.x + col * (cw + gap), rect.origin.y + row * (ch + gap), cw, ch);
        CGFloat labelH = MIN(32.0, MAX(22.0, ch * 0.22));
        CGFloat valueH = MIN(96.0, MAX(44.0, ch * 0.58));
        CGFloat y0 = MAX(2.0, (ch - labelH - valueH) / 2.0);
        UILabel *k = [self makeLabel:[RPTheme title:MIN(26, labelH)] color:[RPTheme textDim]];
        k.textAlignment = NSTextAlignmentCenter;
        k.text = items[i][0];
        k.frame = CGRectMake(6, y0, cw - 12, labelH);
        UILabel *v = [self makeLabel:[RPTheme hero:MIN(78, valueH)] color:[RPTheme accent]];
        v.textAlignment = NSTextAlignmentCenter;
        v.adjustsFontSizeToFitWidth = YES;
        v.minimumScaleFactor = 0.4f;
        v.text = items[i][1];
        v.frame = CGRectMake(4, y0 + labelH, cw - 8, valueH);
        [card addSubview:k];
        [card addSubview:v];
        [self.contentView addSubview:card];
    }
}
- (UIColor *)inkOnColor:(UIColor *)bg {
    CGFloat r = 1, g = 1, b = 1, a = 1;
    if (![bg getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat w = 1;
        if ([bg getWhite:&w alpha:&a]) r = g = b = w;
    }
    CGFloat y = 0.2126f * r + 0.7152f * g + 0.0722f * b;
    return y > 0.62f ? [UIColor colorWithWhite:0.08 alpha:1] : [UIColor whiteColor];
}
- (void)layoutAMS:(NSArray *)ams inRect:(CGRect)rect landscape:(BOOL)landscape {
    if (ams.count == 0 || rect.size.height < 40) {
        UILabel *empty = [self makeLabel:[RPTheme body:16] color:[RPTheme textDim]];
        empty.text = @"暂无 AMS 料仓数据";
        empty.frame = rect;
        [self.contentView addSubview:empty];
        return;
    }
    // Flatten slots with unit label
    NSMutableArray *flat = [NSMutableArray array];
    NSInteger unitNo = 0;
    for (id rawUnit in ams) {
        if (![rawUnit isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *unit = rawUnit;
        unitNo++;
        NSInteger rawIndex = unit[@"index"] ? [unit[@"index"] integerValue] : (unitNo - 1);
        NSString *amsNo = [NSString stringWithFormat:@"%ld", (long)(rawIndex + 1)];
        NSArray *slots = [unit[@"slots"] isKindOfClass:[NSArray class]] ? unit[@"slots"] : @[];
        for (id rawSlot in slots) {
            if (![rawSlot isKindOfClass:[NSDictionary class]]) continue;
            NSMutableDictionary *row = [NSMutableDictionary dictionaryWithDictionary:rawSlot];
            row[@"_ams"] = amsNo;
            [flat addObject:row];
        }
    }
    UILabel *amsTitle = [self makeLabel:[RPTheme title:28] color:[RPTheme accent]];
    amsTitle.text = [NSString stringWithFormat:@"耗材料仓 · %lu 槽", (unsigned long)flat.count];
    amsTitle.frame = CGRectMake(rect.origin.x, rect.origin.y, rect.size.width, 32);
    [self.contentView addSubview:amsTitle];

    CGFloat gridTop = rect.origin.y + 36;
    CGFloat gridH = rect.origin.y + rect.size.height - gridTop;
    NSInteger cols = landscape ? 4 : 3;
    if (flat.count <= 4) cols = MAX(2, (NSInteger)flat.count);
    CGFloat gap = 8;
    NSInteger rows = (flat.count + cols - 1) / MAX(1,cols);
    CGFloat cw = (rect.size.width - gap*(cols-1)) / MAX(1,cols);
    CGFloat ch = rows > 0 ? MIN(118, (gridH - gap*(rows-1)) / MAX(1,rows)) : 100;
    ch = MAX(92, ch);
    for (NSUInteger i=0; i<flat.count; i++) {
        NSDictionary *slot = flat[i];
        id rawBound = slot[@"bound"];
        NSDictionary *bound = [rawBound isKindOfClass:[NSDictionary class]] ? rawBound : @{};
        NSInteger row = i / cols, col = i % cols;
        if (gridTop + row*(ch+gap) + ch > rect.origin.y + rect.size.height + 1) break;
        id rawHex = [bound[@"colorHex"] isKindOfClass:[NSString class]] ? bound[@"colorHex"] : slot[@"colorHex"];
        NSString *hex = [rawHex isKindOfClass:[NSString class]] && [(NSString *)rawHex length] >= 6 ? rawHex : @"888888FF";
        UIColor *fill = [self colorFromHex:hex];
        UIColor *ink = [self inkOnColor:fill];
        UIView *card = [[UIView alloc] initWithFrame:CGRectMake(rect.origin.x + col*(cw+gap), gridTop + row*(ch+gap), cw, ch)];
        card.backgroundColor = fill;
        card.layer.cornerRadius = 14;
        card.clipsToBounds = YES;
        double pct = [bound[@"remainingPercent"] doubleValue];
        if (pct == 0 && slot[@"remainPercent"]) pct = [slot[@"remainPercent"] doubleValue];
        if (pct < 0) pct = 0;
        NSInteger slotNo = slot[@"slot"] ? [slot[@"slot"] integerValue] + 1 : (NSInteger)i + 1;
        UILabel *num = [self makeLabel:[RPTheme title:22] color:ink];
        num.textAlignment = NSTextAlignmentCenter;
        num.text = [NSString stringWithFormat:@"%ld", (long)slotNo];
        num.frame = CGRectMake(4, 6, cw-8, 26);
        UILabel *name = [self makeLabel:[RPTheme small:16] color:ink];
        NSString *nm = [NSString stringWithFormat:@"%@", bound[@"name"] ?: slot[@"type"] ?: @"空"];
        name.text = nm;
        name.textAlignment = NSTextAlignmentCenter;
        name.adjustsFontSizeToFitWidth = YES;
        name.minimumScaleFactor = 0.7f;
        name.numberOfLines = 1;
        name.frame = CGRectMake(6, 32, cw-12, 20);
        UILabel *rp = [self makeLabel:[RPTheme title:40] color:ink];
        rp.text = [NSString stringWithFormat:@"%.0f%%", pct];
        rp.textAlignment = NSTextAlignmentCenter;
        rp.adjustsFontSizeToFitWidth = YES;
        rp.minimumScaleFactor = 0.6f;
        rp.frame = CGRectMake(6, 52, cw-12, 44);
        UILabel *typ = [self makeLabel:[RPTheme small:13] color:[ink colorWithAlphaComponent:0.75]];
        typ.textAlignment = NSTextAlignmentCenter;
        typ.text = [NSString stringWithFormat:@"AMS %@ · %@", slot[@"_ams"] ?: @"", bound[@"type"] ?: slot[@"type"] ?: @""];
        typ.frame = CGRectMake(4, ch-22, cw-8, 16);
        [card addSubview:num]; [card addSubview:name]; [card addSubview:rp]; [card addSubview:typ];
        [self.contentView addSubview:card];
    }
}
@end

@implementation RPPrintFleetPageVC
@end
@implementation RPPrintTempsPageVC
@end
@implementation RPPrintFilamentPageVC
@end

#pragma mark - Media walls

/* Cover art shapes measured from each source (w/h): Steam header 460×215 = 2.14,
   gamer520 PC/Switch capsules 616×353 = 1.75, 2468c PS5 covers 280×360 = 0.78,
   Maoyan posters ≈ 0.72. Cards use these ratios so art is never cropped. */

/* Whole-row cover grid. Tries every cols×rows from 1×1 to 7×7 with
   minN ≤ cols·rows ≤ min(available, maxN), sizes each card by the art's ratio so
   it fits both width and height, and keeps the layout that covers the most of the
   page (within 6%, prefer more cards). Every row is full, so no "6 on top, 3
   below". Simulated on iPad 3: 85–92% of the page in both orientations, against
   45–90% for the fixed-column grid it replaces. `nOut` gets the card count. */
static NSArray *RPFillGrid(CGRect avail, NSInteger available, NSInteger minN, NSInteger maxN, CGFloat ratio, CGFloat captionH, CGFloat gap, CGFloat *imgHOut, NSInteger *nOut) {
    if (available <= 0) { if (nOut) *nOut = 0; return @[]; }
    NSInteger cap = MIN(available, maxN);
    NSInteger floorN = MIN(minN, cap);
    NSInteger bestCols = 1, bestRows = 1, bestScore = -1, bestN = 0;
    CGFloat bestW = 0;
    for (NSInteger c = 1; c <= 7; c++) {
        for (NSInteger r = 1; r <= 7; r++) {
            NSInteger n = c * r;
            if (n < floorN || n > cap) continue;
            CGFloat cw = (avail.size.width - gap * (c - 1)) / c;
            CGFloat rh = (avail.size.height - gap * (r - 1)) / r;
            CGFloat w = floor(MIN(cw, (rh - captionH) * ratio));
            if (w < 110) continue;
            CGFloat cardH = floor(w / ratio) + captionH;
            CGFloat fill = n * w * cardH / (avail.size.width * avail.size.height);
            NSInteger score = (NSInteger)floor(fill / 0.06);
            if (score > bestScore || (score == bestScore && n > bestN)) {
                bestScore = score; bestCols = c; bestRows = r; bestW = w; bestN = n;
            }
        }
    }
    if (bestN == 0) {
        // Nothing fit the minimum (very few items): one row of what there is.
        bestCols = cap; bestRows = 1; bestN = cap;
        bestW = floor(MIN((avail.size.width - gap * (cap - 1)) / cap, (avail.size.height - captionH) * ratio));
    }
    CGFloat imgH = floor(bestW / ratio);
    CGFloat ch = imgH + captionH;
    CGFloat gridW = bestCols * bestW + gap * (bestCols - 1);
    // Spread spare space between cards (up to 3× gap), then centre.
    CGFloat colGap = gap, rowGap = gap;
    if (bestCols > 1) colGap = MIN(gap * 3, gap + (avail.size.width - gridW) / (bestCols - 1));
    gridW = bestCols * bestW + colGap * (bestCols - 1);
    CGFloat gridH = bestRows * ch + gap * (bestRows - 1);
    if (bestRows > 1) rowGap = MIN(gap * 3, gap + (avail.size.height - gridH) / (bestRows - 1));
    gridH = bestRows * ch + rowGap * (bestRows - 1);
    CGFloat x0 = avail.origin.x + floor((avail.size.width - gridW) / 2.0);
    CGFloat y0 = avail.origin.y + floor(MAX(0, avail.size.height - gridH) / 2.0);
    NSMutableArray *frames = [NSMutableArray array];
    for (NSInteger i = 0; i < bestN; i++) {
        NSInteger r = i / bestCols, c = i % bestCols;
        [frames addObject:[NSValue valueWithCGRect:CGRectMake(x0 + c * (bestW + colGap), y0 + r * (ch + rowGap), bestW, ch)]];
    }
    if (imgHOut) *imgHOut = imgH;
    if (nOut) *nOut = bestN;
    return frames;
}

@implementation RPMoviePageVC
- (void)applyState:(NSDictionary *)state baseURL:(NSString *)baseURL {
    CGRect b = self.contentView.bounds;
    NSArray *movies = state[@"movies"] ?: @[];
    NSString *fp = [NSString stringWithFormat:@"movies|%@|%@", RPHashObject(movies), baseURL?:@""];
    if ([self shouldSkipRebuildForKey:fp bounds:b]) return;
    [self clearContent];
    CGFloat m = [self mInset];
    BOOL landscape = [self isLandscape];
    (void)landscape;
    // Maoyan posters are ≈0.72 (w/h). Full poster, title + date under it.
    // Whole rows only: 4×3 portrait, 5×2 landscape with 12 films.
    CGFloat captionH = 64;
    CGFloat imgH = 0;
    NSInteger n = 0;
    CGRect avail = CGRectMake(m, 8, b.size.width - 2 * m, b.size.height - 8 - m);
    NSArray *frames = RPFillGrid(avail, (NSInteger)movies.count, 6, 12, 0.72, captionH, 12, &imgH, &n);
    for (NSUInteger i = 0; i < frames.count; i++) {
        NSDictionary *mov = movies[i];
        CGRect f = [frames[i] CGRectValue];
        UIView *card = [self makeCard];
        card.frame = f;
        [[card viewWithTag:8801] removeFromSuperview]; // accent bar would cover the poster's left edge
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, f.size.width, imgH)];
        iv.contentMode = UIViewContentModeScaleAspectFill;  // box already has the poster's ratio
        iv.clipsToBounds = YES;
        iv.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
        [card addSubview:iv];
        [self loadImageURL:[self absURL:mov[@"poster_url"] base:baseURL] into:iv];
        UILabel *t = [self makeLabel:[RPTheme title:22] color:[RPTheme text]];
        t.text = RPStringish(mov[@"title"]);
        t.numberOfLines = 1;
        t.lineBreakMode = NSLineBreakByTruncatingTail;
        t.frame = CGRectMake(10, imgH + 6, f.size.width - 20, 28);
        UILabel *rd = [self makeLabel:[RPTheme small:18] color:[RPTheme textDim]];
        rd.text = RPStringish(mov[@"release_date"]);
        rd.numberOfLines = 1;
        rd.frame = CGRectMake(10, imgH + 34, f.size.width - 20, 24);
        [card addSubview:t];
        [card addSubview:rd];
        [self.contentView addSubview:card];
    }
}
@end

@implementation RPSteamPageVC
- (void)applyState:(NSDictionary *)state baseURL:(NSString *)baseURL {
    CGRect b = self.contentView.bounds;
    NSDictionary *steam = state[@"steam"] ?: @{};
    NSArray *items = nil;
    NSString *heading = @"Steam 新游";
    if (self.pageOffset == 0) {
        items = steam[@"new_releases"] ?: @[];
        heading = @"Steam 新游";
    } else {
        items = steam[@"top_sellers"] ?: @[];
        if (items.count == 0) items = steam[@"trending"] ?: @[];
        heading = @"Steam 热销";
    }
    NSString *fp = [NSString stringWithFormat:@"steam-%ld|%@|%@", (long)self.pageOffset, RPHashObject(items), baseURL?:@""];
    if ([self shouldSkipRebuildForKey:fp bounds:b]) return;
    [self clearContent];
    CGFloat m = [self mInset];
    BOOL landscape = [self isLandscape];
    (void)heading;
    NSMutableArray *vis = [NSMutableArray array];
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        if (RPStringish(item[@"title"]).length || RPStringish(item[@"header_url"]).length) [vis addObject:item];
    }
    items = vis;
    (void)landscape;
    // Steam header art is 460×215 (2.14). Whole rows: 2×4 portrait, 3×3 landscape.
    CGFloat captionH = 66;
    CGFloat imgH = 0;
    NSInteger n = 0;
    CGRect avail = CGRectMake(m, 8, b.size.width - 2 * m, b.size.height - 8 - m);
    NSArray *frames = RPFillGrid(avail, (NSInteger)items.count, 6, 10, 460.0 / 215.0, captionH, 12, &imgH, &n);
    for (NSUInteger i = 0; i < frames.count; i++) {
        NSDictionary *item = items[i];
        CGRect f = [frames[i] CGRectValue];
        UIView *card = [self makeCard];
        card.frame = f;
        [[card viewWithTag:8801] removeFromSuperview];
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, f.size.width, imgH)];
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        iv.backgroundColor = [UIColor colorWithRed:0.12 green:0.14 blue:0.2 alpha:1];
        [card addSubview:iv];
        // header_image is the 2.14 art; the 616×353 capsule would be cropped in this box.
        NSString *img = RPStringish(item[@"header_url"]);
        if (img.length == 0) img = RPStringish(item[@"capsule_url"]);
        if (img.length == 0) img = RPStringish(item[@"image_url"]);
        if (img.length) {
            [self loadImageURL:[self absURL:img base:baseURL] into:iv];
        } else {
            UILabel *ph = [self makeLabel:[RPTheme title:22] color:[RPTheme textDim]];
            ph.text = @"暂无封面";
            ph.textAlignment = NSTextAlignmentCenter;
            ph.frame = iv.bounds;
            [iv addSubview:ph];
        }
        NSString *discount = RPStringish(item[@"discount"]);
        if (discount.length) {
            UILabel *dl = [self makeLabel:[RPTheme title:20] color:[UIColor blackColor]];
            dl.text = [NSString stringWithFormat:@" %@ ", discount];
            dl.backgroundColor = [RPTheme ok];
            dl.numberOfLines = 1;
            [dl sizeToFit];
            dl.layer.cornerRadius = 6;
            dl.clipsToBounds = YES;
            dl.frame = CGRectMake(f.size.width - dl.bounds.size.width - 8, 8, dl.bounds.size.width, dl.bounds.size.height + 4);
            [card addSubview:dl];
        }
        if (self.pageOffset != 0) {
            UILabel *rank = [self makeLabel:[RPTheme mono:20] color:[UIColor whiteColor]];
            rank.text = [NSString stringWithFormat:@"%lu", (unsigned long)i + 1];
            rank.textAlignment = NSTextAlignmentCenter;
            rank.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
            rank.layer.cornerRadius = 6;
            rank.clipsToBounds = YES;
            rank.frame = CGRectMake(8, 8, 34, 30);
            [card addSubview:rank];
        }
        UILabel *t = [self makeLabel:[RPTheme title:22] color:[RPTheme text]];
        t.text = RPStringish(item[@"title"]);
        t.numberOfLines = 1;
        t.lineBreakMode = NSLineBreakByTruncatingTail;
        t.frame = CGRectMake(10, imgH + 6, f.size.width - 20, 28);
        [card addSubview:t];
        NSString *price = RPStringish(item[@"price"]);
        UILabel *pr = [self makeLabel:[RPTheme title:20] color:discount.length ? [RPTheme ok] : [RPTheme accent]];
        pr.text = price.length ? price : @"免费 / 未定价";
        pr.numberOfLines = 1;
        pr.frame = CGRectMake(10, imgH + 36, f.size.width - 20, 24);
        [card addSubview:pr];
        [self.contentView addSubview:card];
    }
}
@end

@implementation RPGameListPageVC
- (void)applyState:(NSDictionary *)state baseURL:(NSString *)baseURL {
    CGRect b = self.contentView.bounds;
    NSString *heading = @"游戏上新";
    NSArray *items = nil;
    if ([self.kind isEqualToString:@"pc"]) {
        heading = @"PC 游戏上新";
        items = state[@"gamer520"][@"items"] ?: @[];
    } else if ([self.kind isEqualToString:@"switch"]) {
        heading = @"Switch 游戏上新";
        NSArray *api = state[@"gamer520"][@"switch_items"] ?: state[@"switch_games"] ?: nil;
        items = ([api isKindOfClass:[NSArray class]]) ? api : @[];
    } else {
        heading = @"PS5 游戏上新";
        NSArray *api = state[@"ps5_games"] ?: state[@"gamer520"][@"ps5_items"] ?: nil;
        items = ([api isKindOfClass:[NSArray class]]) ? api : @[];
    }
    NSString *fp = [NSString stringWithFormat:@"games-%@|%@|%@", self.kind?:@"", RPHashObject(items), baseURL?:@""];
    if ([self shouldSkipRebuildForKey:fp bounds:b]) return;
    [self clearContent];
    CGFloat m = [self mInset];
    BOOL landscape = [self isLandscape];
    (void)heading;
    // Source art shapes: gamer520 PC/Switch capsules 616×353 (1.75, Switch also
    // 16:9 eShop art); 2468c PS5 box covers 280×360 (0.78, portrait).
    BOOL ps5 = [self.kind isEqualToString:@"ps5"];
    CGFloat ratio = ps5 ? (280.0 / 360.0) : (616.0 / 353.0);
    (void)landscape;
    // Whole rows: PC/Switch 3×4 portrait, 4×3 landscape; PS5 4×3 / 5×2.
    CGFloat captionH = ps5 ? 66 : 72;
    CGFloat imgH = 0;
    NSInteger n = 0;
    CGRect avail = CGRectMake(m, 8, b.size.width - 2 * m, b.size.height - 8 - m);
    NSArray *frames = RPFillGrid(avail, (NSInteger)items.count, ps5 ? 8 : 6, ps5 ? 15 : 12, ratio, captionH, 12, &imgH, &n);
    for (NSUInteger i = 0; i < frames.count; i++) {
        NSDictionary *item = items[i];
        CGRect f = [frames[i] CGRectValue];
        UIView *card = [self makeCard];
        card.frame = f;
        [[card viewWithTag:8801] removeFromSuperview];
        UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, f.size.width, imgH)];
        // Box matches the art, so AspectFill shows the whole cover. Switch art is
        // 1.78 vs 1.75: under 2% is trimmed, not visible.
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        iv.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
        [card addSubview:iv];
        NSString *img = RPStringish(item[@"image_url"]);
        if (img.length == 0) img = RPStringish(item[@"cover_url"]);
        if (img.length == 0) img = RPStringish(item[@"poster_url"]);
        [self loadImageURL:[self absURL:img base:baseURL] into:iv];
        NSString *titleText = RPStringish(item[@"title"]);
        NSString *subText = @"";
        NSArray *parts = [titleText componentsSeparatedByString:@"|"];
        if (parts.count > 1) {
            titleText = [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSMutableArray *bits = [NSMutableArray array];
            for (NSUInteger k = 1; k < parts.count && bits.count < 2; k++) {
                NSString *p = [parts[k] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (p.length && ![p isEqualToString:@"解压即撸"] && ![p isEqualToString:@"NSP"] && ![p isEqualToString:@"NSZ"]) [bits addObject:p];
            }
            subText = [bits componentsJoinedByString:@" · "];
        } else if (ps5) {
            // "中文名.English Name"
            NSRange dot = [titleText rangeOfString:@"."];
            if (dot.location != NSNotFound && dot.location > 1 && dot.location + 2 < titleText.length) {
                subText = [[titleText substringFromIndex:dot.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                titleText = [titleText substringToIndex:dot.location];
            }
        }
        UILabel *t = [self makeLabel:[RPTheme title:ps5 ? 20 : 22] color:[RPTheme text]];
        t.text = titleText.length ? titleText : @" ";
        t.numberOfLines = 1;
        t.lineBreakMode = NSLineBreakByTruncatingTail;
        t.frame = CGRectMake(10, imgH + 6, f.size.width - 20, 28);
        [card addSubview:t];
        if (subText.length) {
            UILabel *s = [self makeLabel:[RPTheme small:18] color:[RPTheme textDim]];
            s.text = subText;
            s.numberOfLines = 1;
            s.lineBreakMode = NSLineBreakByTruncatingTail;
            s.frame = CGRectMake(10, imgH + 36, f.size.width - 20, 24);
            [card addSubview:s];
        }
        [self.contentView addSubview:card];
    }
}
@end

#pragma mark - Photo local

@interface RPPhotoPageVC ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) UILabel *caption;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) UILabel *clockLabel;
@property (nonatomic, strong) RPPhotoSource *photoSource;
@property (nonatomic, strong) NSArray<PHAsset *> *assets;
@property (nonatomic, copy) NSString *albumTitle;
@property (nonatomic, assign) NSInteger assetIndex;
@property (nonatomic, strong) NSTimer *photoTimer;
@property (nonatomic, strong) NSTimer *clockTimer;
@property (nonatomic, copy) NSString *currentAssetId;
@property (nonatomic, assign) uint64_t photoSeed;
@property (nonatomic, strong) NSArray<NSNumber *> *photoHashes;
@property (nonatomic, copy) NSString *photoAlbumKey;
@end

static uint64_t RPPhotoNewSeed(void);
static NSArray<PHAsset *> *RPPhotoOrder(NSArray<PHAsset *> *pool, uint64_t seed, NSMutableArray<NSNumber *> *hashesOut);

@implementation RPPhotoPageVC
- (void)setPhotoSource:(id)photoSource slot:(NSInteger)slot {
    self.photoSource = photoSource;
    self.slot = slot;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.imageView = [[UIImageView alloc] initWithFrame:self.contentView.bounds];
    self.imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.imageView.contentMode = UIViewContentModeScaleAspectFill;
    self.imageView.clipsToBounds = YES;
    self.imageView.backgroundColor = [RPTheme bg];
    [self.contentView addSubview:self.imageView];

    self.errorLabel = [self makeLabel:[RPTheme title:36] color:[RPTheme text]];
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.hidden = YES;
    [self.contentView addSubview:self.errorLabel];

    self.caption = [self makeLabel:[RPTheme body:28] color:[UIColor whiteColor]];
    self.caption.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
    self.caption.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:self.caption];

    self.clockLabel = [self makeLabel:[RPTheme mono:28] color:[UIColor whiteColor]];
    self.clockLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
    self.clockLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:self.clockLabel];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.imageView.frame = self.contentView.bounds;
    self.caption.frame = CGRectMake(0, self.contentView.bounds.size.height-52, self.contentView.bounds.size.width, 52);
    self.errorLabel.frame = CGRectInset(self.contentView.bounds, 40, 80);
    self.clockLabel.frame = CGRectMake(self.contentView.bounds.size.width-130, 12, 118, 32);
}
- (void)updateClock {
    static NSDateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [[NSDateFormatter alloc] init];
        f.dateFormat = @"HH:mm";
    });
    f.timeZone = [NSTimeZone localTimeZone];
    self.clockLabel.text = [NSString stringWithFormat:@" %@ ", [f stringFromDate:[NSDate date]]];
}
- (void)pageWillAppear {
    [self noteImageLoadBegan]; // hold intro until first photo (or empty/error) lands
    [super pageWillAppear];
    [self updateClock];
    [self.clockTimer invalidate];
    self.clockTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(updateClock) userInfo:nil repeats:YES];
    __weak typeof(self) weakSelf = self;
    [self.photoSource ensureAuthorization:^(BOOL granted) {
        if (!granted) {
            weakSelf.errorLabel.hidden = NO;
            weakSelf.errorLabel.text = @"请允许访问照片\n设置 → RemotePanel → 照片";
            weakSelf.caption.text = @"无相册权限";
            weakSelf.imageView.image = nil;
            [weakSelf noteImageLoadEnded];
            return;
        }
        [weakSelf.photoSource loadAlbumAssetsPreferFavorites:^(NSArray<PHAsset *> *assets, NSString *albumTitle) {
            weakSelf.albumTitle = albumTitle ?: @"相册";
            NSArray *filtered = [weakSelf partitionAssets:assets];
            NSString *albumKey = weakSelf.photoSource.albumLocalIdentifier.length ? weakSelf.photoSource.albumLocalIdentifier : (albumTitle ?: @"");
            [weakSelf rpLoadPlaylist:filtered album:albumKey];
            if (filtered.count == 0) {
                weakSelf.errorLabel.hidden = NO;
                weakSelf.errorLabel.text = @"相册无照片";
                weakSelf.caption.text = [NSString stringWithFormat:@"%@ · 0 张", weakSelf.albumTitle];
                weakSelf.imageView.image = nil;
                [weakSelf noteImageLoadEnded];
                return;
            }
            weakSelf.errorLabel.hidden = YES;
            weakSelf.caption.text = [NSString stringWithFormat:@"%@ · %lu 张 · 随机播放", weakSelf.albumTitle, (unsigned long)filtered.count];
            // assetIndex was set by rpLoadPlaylist: to where this slot left off.
            [weakSelf showCurrent];
            [weakSelf rpSavePhotoProgress];
            [weakSelf.photoTimer invalidate];
            weakSelf.photoTimer = [NSTimer scheduledTimerWithTimeInterval:8.0 target:weakSelf selector:@selector(nextPhoto) userInfo:nil repeats:YES];
        }];
    }];
}
- (void)pageDidDisappear {
    [self.photoTimer invalidate];
    self.photoTimer = nil;
    [self.clockTimer invalidate];
    self.clockTimer = nil;
    self.imageView.image = nil;
    self.currentAssetId = nil;
    [super pageDidDisappear];
}
/** Slot A (0) shows portrait photos, slot B (1) landscape; either falls back to
    everything if the album has none of its kind. No more every-other-photo split:
    each slot uses all photos of its orientation. */
- (NSArray<PHAsset *> *)partitionAssets:(NSArray<PHAsset *> *)assets {
    if (assets.count == 0) return assets;
    NSMutableArray *pref = [NSMutableArray array];
    for (PHAsset *a in assets) {
        BOOL portrait = a.pixelHeight >= a.pixelWidth;
        if ((self.slot == 0) == portrait) [pref addObject:a];
    }
    return pref.count ? pref : assets;
}

#pragma mark Shuffle that survives restarts
/* Order = sort by a seeded hash of each photo's localIdentifier. That gives a full
   random permutation, and adding or deleting photos only inserts/removes entries
   without reshuffling the rest. Progress is stored as (seed, hash of the last photo
   shown): resuming starts at the first photo hashed after it, so nothing repeats
   until the whole pool has been shown once, across page turns and app restarts.
   When the cycle ends a new seed starts a fresh permutation. */

static uint64_t RPPhotoHash(NSString *ident, uint64_t seed) {
    uint64_t h = 1469598103934665603ULL ^ seed;           // FNV-1a 64
    const char *s = ident.UTF8String ?: "";
    for (; *s; s++) { h ^= (uint8_t)*s; h *= 1099511628211ULL; }
    h ^= h >> 33; h *= 0xff51afd7ed558ccdULL; h ^= h >> 33; // final mix
    return h ? h : 1;                                       // 0 means "nothing shown yet"
}

static NSString *RPPhotoCycleKey(NSInteger slot) {
    return [NSString stringWithFormat:@"RemotePanel.photo.cycle.%ld", (long)slot];
}

static uint64_t RPPhotoNewSeed(void) {
    return ((uint64_t)arc4random() << 32) | arc4random();
}

/** Sorted pool for `seed`, plus the hash of each entry in the same order. */
static NSArray<PHAsset *> *RPPhotoOrder(NSArray<PHAsset *> *pool, uint64_t seed, NSMutableArray<NSNumber *> *hashesOut) {
    NSMutableArray *pairs = [NSMutableArray arrayWithCapacity:pool.count];
    for (PHAsset *a in pool) [pairs addObject:@[ @(RPPhotoHash(a.localIdentifier, seed)), a ]];
    [pairs sortUsingComparator:^NSComparisonResult(NSArray *x, NSArray *y) {
        uint64_t hx = [x[0] unsignedLongLongValue], hy = [y[0] unsignedLongLongValue];
        return hx < hy ? NSOrderedAscending : (hx > hy ? NSOrderedDescending : NSOrderedSame);
    }];
    NSMutableArray *ordered = [NSMutableArray arrayWithCapacity:pairs.count];
    for (NSArray *p in pairs) {
        [ordered addObject:p[1]];
        [hashesOut addObject:p[0]];
    }
    return ordered;
}

/** Build this slot's playlist and the index to resume from. */
- (void)rpLoadPlaylist:(NSArray<PHAsset *> *)pool album:(NSString *)album {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSDictionary *saved = [ud dictionaryForKey:RPPhotoCycleKey(self.slot)];
    uint64_t seed = [saved[@"seed"] unsignedLongLongValue];
    uint64_t last = [saved[@"last"] unsignedLongLongValue];
    // A different album is a different pool: start a new cycle for it.
    if (seed == 0 || ![RPStringish(saved[@"album"]) isEqualToString:album ?: @""]) {
        seed = RPPhotoNewSeed();
        last = 0;
    }
    NSMutableArray *hashes = [NSMutableArray array];
    NSArray *ordered = RPPhotoOrder(pool, seed, hashes);
    NSInteger start = 0;
    while (start < (NSInteger)hashes.count && [hashes[start] unsignedLongLongValue] <= last) start++;
    if (start >= (NSInteger)ordered.count) {
        // Everything in this cycle has been shown: reshuffle.
        seed = RPPhotoNewSeed();
        [hashes removeAllObjects];
        ordered = RPPhotoOrder(pool, seed, hashes);
        start = 0;
    }
    self.photoSeed = seed;
    self.photoHashes = hashes;
    self.photoAlbumKey = album ?: @"";
    self.assets = ordered;
    self.assetIndex = start;
}

/** Remember that assets[assetIndex] has been shown. */
- (void)rpSavePhotoProgress {
    if (self.assetIndex < 0 || self.assetIndex >= (NSInteger)self.photoHashes.count) return;
    [[NSUserDefaults standardUserDefaults] setObject:@{
        @"seed": @(self.photoSeed),
        @"last": self.photoHashes[self.assetIndex],
        @"album": self.photoAlbumKey ?: @"",
    } forKey:RPPhotoCycleKey(self.slot)];
}
- (void)showCurrent {
    if (self.assets.count == 0) {
        self.errorLabel.hidden = NO;
        self.errorLabel.text = @"相册无照片";
        [self noteImageLoadEnded];
        return;
    }
    if (self.assetIndex >= (NSInteger)self.assets.count) self.assetIndex = 0;
    PHAsset *a = self.assets[self.assetIndex];
    if ([a.localIdentifier isEqualToString:self.currentAssetId] && self.imageView.image) {
        [self noteImageLoadEnded];
        return;
    }
    BOOL firstPaint = (self.imageView.image == nil);
    if (!firstPaint) [self noteImageLoadBegan];
    self.currentAssetId = a.localIdentifier;
    // Ask for the screen's real pixel size. iPad 3 is 2048×1536 (1024×768 pt @2x);
    // the old 1024 px cap rendered photos at half resolution, stretched 2×.
    // One 2048×1536 RGBA bitmap is ~12 MB, and only the visible photo is held.
    CGFloat scale = MIN(2.0, [UIScreen mainScreen].scale);
    CGSize host = self.contentView.bounds.size;
    CGSize sz = CGSizeMake(MIN(2048.0, MAX(320.0, host.width * scale)),
                           MIN(2048.0, MAX(320.0, host.height * scale)));
    __weak typeof(self) weakSelf = self;
    NSString *wantId = a.localIdentifier;
    [self.photoSource requestImageForAsset:a targetSize:sz completion:^(UIImage *image) {
        if (![weakSelf.currentAssetId isEqualToString:wantId]) {
            [weakSelf noteImageLoadEnded];
            return;
        }
        if (image) {
            weakSelf.imageView.image = image;
            weakSelf.errorLabel.hidden = YES;
        } else if (!weakSelf.imageView.image) {
            weakSelf.errorLabel.hidden = NO;
            weakSelf.errorLabel.text = @"无法加载照片";
        }
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        df.dateFormat = @"yyyy-MM-dd HH:mm";
        NSString *when = a.creationDate ? [df stringFromDate:a.creationDate] : @"";
        weakSelf.caption.text = [NSString stringWithFormat:@"%@ · %@ · %ld/%lu",
                                 weakSelf.albumTitle ?: @"相册",
                                 when,
                                 (long)(weakSelf.assetIndex+1),
                                 (unsigned long)weakSelf.assets.count];
        [weakSelf noteImageLoadEnded];
    }];
}
- (void)nextPhoto {
    if (self.assets.count <= 1) return;
    NSInteger next = self.assetIndex + 1;
    if (next >= (NSInteger)self.assets.count) {
        // Cycle finished: new permutation. Don't open it with the photo just shown.
        NSString *justShown = self.assets[self.assetIndex].localIdentifier;
        NSArray *pool = self.assets;
        uint64_t seed = RPPhotoNewSeed();
        NSMutableArray *hashes = [NSMutableArray array];
        NSArray *ordered = RPPhotoOrder(pool, seed, hashes);
        if (ordered.count > 1 && [[ordered.firstObject localIdentifier] isEqualToString:justShown]) {
            NSMutableArray *o = [ordered mutableCopy];
            [o exchangeObjectAtIndex:0 withObjectAtIndex:1];
            [hashes exchangeObjectAtIndex:0 withObjectAtIndex:1];
            ordered = o;
        }
        self.photoSeed = seed;
        self.photoHashes = hashes;
        self.assets = ordered;
        next = 0;
    }
    self.assetIndex = next;
    self.currentAssetId = nil;
    [self showCurrent];
    [self rpSavePhotoProgress];
}
- (void)applyState:(NSDictionary *)state baseURL:(NSString *)baseURL { (void)state; (void)baseURL; }
@end

#pragma mark - Web fallback (legacy H5 template)

@interface RPWebFallbackPageVC () <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *web;
@property (nonatomic, copy) NSString *lastURL;
@end

@implementation RPWebFallbackPageVC
- (void)viewDidLoad {
    [super viewDidLoad];
    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    self.web = [[WKWebView alloc] initWithFrame:self.contentView.bounds configuration:cfg];
    self.web.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    self.web.navigationDelegate = self;
    self.web.opaque = NO;
    self.web.backgroundColor = [RPTheme bg];
    if ([self.web respondsToSelector:@selector(scrollView)]) {
        self.web.scrollView.backgroundColor = [RPTheme bg];
    }
    [self.contentView addSubview:self.web];
}
- (void)applyState:(NSDictionary *)state baseURL:(NSString *)baseURL {
    (void)state;
    NSString *url = [NSString stringWithFormat:@"%@/h5?template=%@&rotate=0", baseURL ?: @"", self.pageId ?: @""];
    if ([url isEqualToString:self.lastURL]) return;
    self.lastURL = url;
    [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]]];
}
- (void)pageDidDisappear {
}
@end

#pragma mark - Custom fullscreen Web page

@interface RPWebPageVC () <WKNavigationDelegate>
@property (nonatomic, strong) WKWebView *web;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, copy) NSString *lastURL;
@property (nonatomic, assign) BOOL loading;
@end

@implementation RPWebPageVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.contentView.backgroundColor = [UIColor blackColor];
    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    if ([cfg respondsToSelector:@selector(setAllowsInlineMediaPlayback:)]) {
        cfg.allowsInlineMediaPlayback = YES;
    }
    self.web = [[WKWebView alloc] initWithFrame:self.contentView.bounds configuration:cfg];
    self.web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.web.navigationDelegate = self;
    self.web.opaque = YES;
    self.web.backgroundColor = [UIColor blackColor];
    if ([self.web respondsToSelector:@selector(scrollView)]) {
        self.web.scrollView.backgroundColor = [UIColor blackColor];
        self.web.scrollView.bounces = NO;
    }
    // Keep left/right 12% strips free of web touch so kiosk edge-tap still flips pages.
    // (Root VC gesture is on self.view; WKWebView would otherwise eat taps.)
    self.web.userInteractionEnabled = YES;
    [self.contentView addSubview:self.web];

    self.statusLabel = [self makeLabel:[RPTheme readable:22] color:[UIColor colorWithWhite:0.85 alpha:1]];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.hidden = YES;
    self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.contentView addSubview:self.statusLabel];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.web.frame = self.contentView.bounds;
    self.statusLabel.frame = UIEdgeInsetsInsetRect(self.contentView.bounds, UIEdgeInsetsMake(40, 40, 40, 40));
}
- (void)pageWillAppear {
    // No fly-in — fullscreen web should appear instantly (do not call super).
    [self reloadConfiguredURL];
}
- (void)pageDidDisappear {
    [self.web stopLoading];
    // Drop document to free memory on iPad 3; next appear reloads.
    if (self.lastURL.length) {
        [self.web loadHTMLString:@"" baseURL:nil];
        self.lastURL = nil;
    }
    [super pageDidDisappear];
}
- (void)applyState:(NSDictionary *)state baseURL:(NSString *)baseURL {
    (void)state; (void)baseURL;
    [self reloadConfiguredURL];
}
- (void)reloadConfiguredURL {
    NSDictionary *cfg = RPWebPageFind(self.pageId);
    NSString *raw = [cfg[@"url"] isKindOfClass:[NSString class]] ? cfg[@"url"] : @"";
    raw = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (raw.length == 0) {
        self.statusLabel.hidden = NO;
        self.statusLabel.text = @"还没有填写网址\n长按屏幕打开设置 → 自定义网页";
        self.web.hidden = YES;
        return;
    }
    if (![raw hasPrefix:@"http://"] && ![raw hasPrefix:@"https://"]) {
        raw = [@"http://" stringByAppendingString:raw];
    }
    if ([raw isEqualToString:self.lastURL] && !self.loading) {
        self.web.hidden = NO;
        self.statusLabel.hidden = YES;
        return;
    }
    NSURL *url = [NSURL URLWithString:raw];
    if (!url) {
        self.statusLabel.hidden = NO;
        self.statusLabel.text = [NSString stringWithFormat:@"网址无效\n%@", raw];
        self.web.hidden = YES;
        return;
    }
    self.lastURL = raw;
    self.web.hidden = NO;
    self.statusLabel.hidden = NO;
    self.statusLabel.text = @"正在打开网页…";
    self.loading = YES;
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    req.timeoutInterval = 25;
    [self.web loadRequest:req];
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    self.loading = NO;
    self.statusLabel.hidden = YES;
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self showWebFail:error];
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self showWebFail:error];
}
- (void)showWebFail:(NSError *)error {
    self.loading = NO;
    if (error.code == NSURLErrorCancelled) return;
    self.statusLabel.hidden = NO;
    self.statusLabel.text = [NSString stringWithFormat:@"打不开这个网页\n%@", error.localizedDescription ?: @"网络错误"];
}
- (void)playPageIntro { /* fullscreen web: no motion */ }
/* playPageIntro above never sets _introPlayed, so without this override the root VC's
   applyCurrentPageState (and rotation) kept calling the base parkMotionOffscreen,
   which translated the WKWebView a full screen width away: a blank page. */
- (void)parkMotionOffscreen {}
- (void)playPageOutro:(void (^)(void))done {
    if (done) done();
}
@end

#pragma mark - Schedule

@interface RPSchedulePageVC ()
@property (nonatomic, strong) EKEventStore *store;
@property (nonatomic, copy) NSArray *deviceEvents;
@property (nonatomic, copy) NSArray *deviceReminders;
@property (nonatomic, copy) NSString *deviceNote;
@property (nonatomic, copy) NSDictionary *schedState;
@property (nonatomic, copy) NSString *schedBase;
@property (nonatomic, assign) BOOL calendarStarted;
@property (nonatomic, assign) BOOL askedEvent;
@property (nonatomic, assign) BOOL askedReminder;
@property (nonatomic, assign) BOOL allowEvent;
@property (nonatomic, assign) BOOL allowReminder;
@property (nonatomic, assign) BOOL pausedForAuth;
@end

/** A calendar row is worth showing when the title is ordinary text. Symbol soup is skipped. */
static BOOL RPCalendarTitleOK(NSString *s) {
    if (s.length == 0) return NO;
    NSUInteger han = 0, alnum = 0, weird = 0;
    NSCharacterSet *space = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    for (NSUInteger i = 0; i < s.length; i++) {
        unichar c = [s characterAtIndex:i];
        if ((c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF)) han++;
        else if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) alnum++;
        else if ([space characterIsMember:c] || c == '-' || c == '_' || c == '.' || c == ',' || c == ':' ||
                 c == '/' || c == '(' || c == ')' || c == 0x00B7) {
        } else {
            weird++;
        }
    }
    if (han > 0 && weird * 2 <= s.length) return YES;
    if (alnum >= 1 && weird == 0) return YES;
    return NO;
}

@implementation RPSchedulePageVC
- (NSString *)cleanCalText:(id)raw {
    if (![raw isKindOfClass:[NSString class]]) return @"";
    NSString *s = [(NSString *)raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([s isEqualToString:@"(null)"]) return @"";
    return s;
}
- (NSString *)lineForItem:(NSDictionary *)item reminder:(BOOL)reminder {
    NSString *when = [self cleanCalText:reminder ? item[@"due"] : item[@"date"]];
    NSString *clock = [self cleanCalText:item[@"time"]];
    NSString *title = [self cleanCalText:item[@"title"]];
    NSString *notes = [self cleanCalText:item[@"notes"]];
    if (!RPCalendarTitleOK(title)) return @"";
    if (!RPCalendarTitleOK(notes)) notes = @"";
    if (notes.length > 80) notes = [[notes substringToIndex:80] stringByAppendingString:@"…"];
    NSMutableString *text = [NSMutableString string];
    if (when.length || clock.length) [text appendFormat:@"%@%@%@\n", when, (when.length && clock.length) ? @" " : @"", clock];
    [text appendString:title];
    if (notes.length) [text appendFormat:@"\n%@", notes];
    return text;
}
- (void)beginDeviceCalendar {
    if (self.calendarStarted) return;
    self.calendarStarted = YES;
    self.store = [[EKEventStore alloc] init];
    EKAuthorizationStatus ev = [EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent];
    EKAuthorizationStatus rm = [EKEventStore authorizationStatusForEntityType:EKEntityTypeReminder];
    self.pausedForAuth = (ev == EKAuthorizationStatusNotDetermined || rm == EKAuthorizationStatusNotDetermined);
    if (self.pausedForAuth) [self rpSetModalOpen:YES];
    __weak typeof(self) weakSelf = self;
    [self.store requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.askedEvent = YES;
            weakSelf.allowEvent = granted;
            (void)error;
            [weakSelf reloadDeviceCalendar];
        });
    }];
    [self.store requestAccessToEntityType:EKEntityTypeReminder completion:^(BOOL granted, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.askedReminder = YES;
            weakSelf.allowReminder = granted;
            (void)error;
            [weakSelf reloadDeviceCalendar];
        });
    }];
}
- (NSDictionary *)eventRow:(EKEvent *)ev dayFmt:(NSDateFormatter *)dayFmt timeFmt:(NSDateFormatter *)timeFmt {
    NSString *when = ev.startDate ? [dayFmt stringFromDate:ev.startDate] : @"";
    NSString *clock = ev.allDay ? @"全天" : (ev.startDate ? [timeFmt stringFromDate:ev.startDate] : @"");
    NSString *title = [self cleanCalText:ev.title];
    if (!RPCalendarTitleOK(title)) return nil;
    NSString *notes = [self cleanCalText:ev.notes];
    if (!RPCalendarTitleOK(notes)) notes = @"";
    return @{
        @"title": title.length ? title : @"未命名日程",
        @"date": when ?: @"",
        @"time": clock ?: @"",
        @"notes": notes ?: @"",
        @"calendar": [self cleanCalText:ev.calendar.title],
        @"sort": @([ev.startDate timeIntervalSince1970]),
        @"id": ev.eventIdentifier ?: @"",
    };
}
- (NSDictionary *)reminderRow:(EKReminder *)rem dayFmt:(NSDateFormatter *)dayFmt timeFmt:(NSDateFormatter *)timeFmt {
    // dueDateComponents.calendar is often nil on iOS 9 — always use currentCalendar + gregorian.
    NSDate *due = nil;
    if (rem.dueDateComponents) {
        NSCalendar *compCal = rem.dueDateComponents.calendar ?: [NSCalendar currentCalendar];
        if (compCal.calendarIdentifier == nil) {
            compCal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian] ?: [NSCalendar currentCalendar];
        }
        due = [compCal dateFromComponents:rem.dueDateComponents];
    }
    NSString *title = [self cleanCalText:rem.title];
    if (!RPCalendarTitleOK(title)) return nil;
    return @{
        @"title": title.length ? title : @"未命名提醒",
        @"due": due ? [dayFmt stringFromDate:due] : @"",
        @"time": due ? [timeFmt stringFromDate:due] : @"",
        @"notes": [self cleanCalText:rem.notes],
        @"id": rem.calendarItemIdentifier ?: @"",
        @"completed": @(rem.completed),
        @"sort": @(due ? [due timeIntervalSince1970] : 0),
    };
}
- (void)reloadDeviceCalendar {
    if (!self.askedEvent || !self.askedReminder || !self.store) return;
    if (self.pausedForAuth) {
        self.pausedForAuth = NO;
        [self rpSetModalOpen:NO];
    }
    // Force Gregorian + Shanghai so weekday labels match what users expect on Chinese iPads.
    NSCalendar *cal = [NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian] ?: [NSCalendar currentCalendar];
    cal.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    cal.timeZone = [NSTimeZone localTimeZone];
    NSDate *start = [cal startOfDayForDate:[NSDate date]];
    NSDate *end = [cal dateByAddingUnit:NSCalendarUnitDay value:8 toDate:start options:0];
    NSDateFormatter *dayFmt = [[NSDateFormatter alloc] init];
    dayFmt.calendar = cal;
    dayFmt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    dayFmt.timeZone = cal.timeZone;
    // EEEE (全称) is more reliable than EEE on iOS 9 zh_CN for some region settings.
    dayFmt.dateFormat = @"M月d日 EEEE";
    NSDateFormatter *timeFmt = [[NSDateFormatter alloc] init];
    timeFmt.calendar = cal;
    timeFmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    timeFmt.timeZone = cal.timeZone;
    timeFmt.dateFormat = @"HH:mm";
    NSMutableArray *events = [NSMutableArray array];
    if (self.allowEvent) {
        NSPredicate *pred = [self.store predicateForEventsWithStartDate:start endDate:end calendars:nil];
        for (EKEvent *ev in [self.store eventsMatchingPredicate:pred]) {
            if (![ev isKindOfClass:[EKEvent class]]) continue;
            if (ev.startDate && [ev.startDate compare:start] == NSOrderedAscending) continue;
            NSDictionary *row = [self eventRow:ev dayFmt:dayFmt timeFmt:timeFmt];
            if (row) [events addObject:row];
        }
        [events sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [a[@"sort"] compare:b[@"sort"]];
        }];
    }
    self.deviceEvents = events;
    if (!self.allowReminder) self.deviceReminders = @[];
    [self invalidateFingerprint];
    if (self.schedState) [self applyState:self.schedState baseURL:self.schedBase ?: @""];
    if (!self.allowReminder) return;
    __weak typeof(self) weakSelf = self;
    NSDate *doneEnd = [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:start options:0];
    NSPredicate *openP = [self.store predicateForIncompleteRemindersWithDueDateStarting:nil ending:nil calendars:nil];
    [self.store fetchRemindersMatchingPredicate:openP completion:^(NSArray *openItems) {
        EKEventStore *store = weakSelf.store;
        if (!store) return;
        NSPredicate *doneP = [store predicateForCompletedRemindersWithCompletionDateStarting:start ending:doneEnd calendars:nil];
        [store fetchRemindersMatchingPredicate:doneP completion:^(NSArray *doneItems) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!weakSelf) return;
                NSMutableArray *rows = [NSMutableArray array];
                for (EKReminder *rem in openItems) {
                    if (![rem isKindOfClass:[EKReminder class]]) continue;
                    NSDictionary *row = [weakSelf reminderRow:rem dayFmt:dayFmt timeFmt:timeFmt];
                    if (row) [rows addObject:row];
                }
                for (EKReminder *rem in doneItems) {
                    if (![rem isKindOfClass:[EKReminder class]]) continue;
                    NSDictionary *row = [weakSelf reminderRow:rem dayFmt:dayFmt timeFmt:timeFmt];
                    if (row) [rows addObject:row];
                }
                [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
                    BOOL ad = [a[@"completed"] boolValue];
                    BOOL bd = [b[@"completed"] boolValue];
                    if (ad != bd) return ad ? NSOrderedDescending : NSOrderedAscending;
                    return [a[@"sort"] compare:b[@"sort"]];
                }];
                if (rows.count > 16) [rows removeObjectsInRange:NSMakeRange(16, rows.count - 16)];
                weakSelf.deviceReminders = rows;
                [weakSelf invalidateFingerprint];
                if (weakSelf.schedState) [weakSelf applyState:weakSelf.schedState baseURL:weakSelf.schedBase ?: @""];
            });
        }];
    }];
}
- (void)onReminderCheck:(UIButton *)btn {
    NSString *ident = objc_getAssociatedObject(btn, &kRPReminderID);
    if (ident.length == 0 || !self.store) return;
    EKCalendarItem *item = [self.store calendarItemWithIdentifier:ident];
    if (![item isKindOfClass:[EKReminder class]]) return;
    EKReminder *rem = (EKReminder *)item;
    rem.completed = !rem.completed;
    NSError *err = nil;
    if (![self.store saveReminder:rem commit:YES error:&err]) {
        self.deviceNote = err.localizedDescription ?: @"没能写回提醒";
    } else {
        self.deviceNote = rem.completed ? @"已完成，并写回系统提醒" : @"已改回未完成，并写回系统提醒";
    }
    [self reloadDeviceCalendar];
}
- (void)applyState:(NSDictionary *)state baseURL:(NSString *)baseURL {
    self.schedState = [state isKindOfClass:[NSDictionary class]] ? state : @{};
    self.schedBase = baseURL ?: @"";
    [self beginDeviceCalendar];
    CGRect b = self.contentView.bounds;
    NSDictionary *sched = [state[@"schedule"] isKindOfClass:[NSDictionary class]] ? state[@"schedule"] : @{};
    NSArray *feedToday = [sched[@"today"] isKindOfClass:[NSArray class]] ? sched[@"today"] : @[];
    NSArray *feedWeek = [sched[@"week"] isKindOfClass:[NSArray class]] ? sched[@"week"] : @[];
    NSArray *feedReminders = [sched[@"reminders"] isKindOfClass:[NSArray class]] ? sched[@"reminders"] : @[];
    NSString *err = [sched[@"sync_error"] isKindOfClass:[NSString class]] ? sched[@"sync_error"] : @"";
    NSMutableArray *deviceToday = [NSMutableArray array];
    NSMutableArray *deviceLater = [NSMutableArray array];
    NSString *todayMark = @"";
    NSDateFormatter *mark = [[NSDateFormatter alloc] init];
    mark.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    mark.dateFormat = @"M月d日";
    todayMark = [mark stringFromDate:[NSDate date]];
    for (NSDictionary *item in self.deviceEvents) {
        NSString *date = [NSString stringWithFormat:@"%@", item[@"date"] ?: @""];
        if ([date hasPrefix:todayMark]) [deviceToday addObject:item];
        else [deviceLater addObject:item];
    }
    NSString *fp = [NSString stringWithFormat:@"sched4|%@|%@|%@|%@|%@|%@|%@|%d|%d",
                    RPHashObject(deviceToday), RPHashObject(deviceLater), RPHashObject(self.deviceReminders),
                    RPHashObject(feedToday), RPHashObject(feedWeek), err, self.deviceNote ?: @"",
                    self.allowEvent, self.allowReminder];
    if ([self shouldSkipRebuildForKey:fp bounds:b]) return;
    [self clearContent];
    CGFloat m = [self mInset];
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:b];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.contentView addSubview:scroll];
    CGFloat y = 8;
    CGFloat w = b.size.width - 2*m;
    UILabel *note = [self makeLabel:[RPTheme readable:15] color:[RPTheme textDim]];
    note.numberOfLines = 2;
    NSMutableString *noteText = [NSMutableString stringWithString:@"日历来自这台 iPad，只能查看。提醒事项可以打勾，会写回系统并同步。"];
    if (self.askedEvent && !self.allowEvent) [noteText appendString:@" 日历未授权。"];
    if (self.askedReminder && !self.allowReminder) [noteText appendString:@" 提醒事项未授权。"];
    if (self.deviceNote.length) [noteText appendFormat:@" %@", self.deviceNote];
    note.text = noteText;
    note.frame = CGRectMake(m, y, w, 44);
    [scroll addSubview:note];
    y += 50;
    if (err.length) {
        UILabel *bad = [self makeLabel:[RPTheme small:16] color:[RPTheme warn]];
        bad.text = [NSString stringWithFormat:@"订阅失败：%@", err];
        bad.frame = CGRectMake(m, y, w, 36);
        [scroll addSubview:bad];
        y += 42;
    }
    NSMutableArray *subscribed = [NSMutableArray array];
    for (id item in feedWeek) {
        if ([item isKindOfClass:[NSDictionary class]] && RPCalendarTitleOK([self cleanCalText:((NSDictionary *)item)[@"title"]])) [subscribed addObject:item];
    }
    for (id item in feedReminders) {
        if ([item isKindOfClass:[NSDictionary class]] && RPCalendarTitleOK([self cleanCalText:((NSDictionary *)item)[@"title"]])) [subscribed addObject:item];
    }
    NSMutableArray *feedTodayOK = [NSMutableArray array];
    for (id item in feedToday) {
        if ([item isKindOfClass:[NSDictionary class]] && RPCalendarTitleOK([self cleanCalText:((NSDictionary *)item)[@"title"]])) [feedTodayOK addObject:item];
    }
    [subscribed addObjectsFromArray:feedTodayOK];
    NSInteger cols = [self isLandscape] ? 2 : 1;
    y = [self addSection:@"今天" items:deviceToday reminder:NO y:y width:w margin:m scroll:scroll columns:cols];
    y = [self addSection:@"接下来" items:deviceLater reminder:NO y:y width:w margin:m scroll:scroll columns:cols];
    y = [self addReminderSection:self.deviceReminders y:y width:w margin:m scroll:scroll columns:cols];
    y = [self addSection:@"订阅" items:subscribed reminder:NO y:y width:w margin:m scroll:scroll columns:cols];
    if (deviceToday.count == 0 && deviceLater.count == 0 && self.deviceReminders.count == 0 && subscribed.count == 0) {
        UILabel *empty = [self makeLabel:[RPTheme title:48] color:[RPTheme textDim]];
        empty.textAlignment = NSTextAlignmentCenter;
        empty.text = (self.calendarStarted && self.askedEvent) ? @"无" : @"正在读取";
        empty.frame = CGRectMake(m, y, w, 72);
        [scroll addSubview:empty];
        y += 80;
    }
    scroll.contentSize = CGSizeMake(b.size.width, y + 20);
    if (self.view.window && self.askedEvent && self.askedReminder && ![self rpIntroHasPlayed]) {
        [self rpReplayIntro];
    }
}
- (void)pageWillAppear {
    if ([self rpIntroHasPlayed]) return;
    if (self.askedEvent && self.askedReminder) {
        [self rpReplayIntro];
        return;
    }
    // Stay visible while EventKit answers. Hiding the content here (alpha 0) left the
    // whole page black — including the "正在读取" placeholder — until both permission
    // callbacks came back, which on a first run means until someone taps the prompts.
    self.contentView.alpha = 1;
}
- (CGFloat)addSection:(NSString *)name items:(NSArray *)items reminder:(BOOL)reminder y:(CGFloat)y width:(CGFloat)w margin:(CGFloat)m scroll:(UIScrollView *)scroll columns:(NSInteger)cols {
    if (items.count == 0) return y;
    if (cols < 1) cols = 1;
    UILabel *head = [self makeLabel:[RPTheme title:22] color:[RPTheme accent]];
    head.text = name;
    head.frame = CGRectMake(m, y, w, 28);
    [scroll addSubview:head];
    y += 34;
    CGFloat gap = 10;
    CGFloat cw = (w - gap * (cols - 1)) / cols;
    CGFloat ch = 90;
    NSInteger shown = 0;
    for (id raw in items) {
        if (![raw isKindOfClass:[NSDictionary class]] || shown >= 8) break;
        NSInteger col = shown % cols;
        NSInteger row = shown / cols;
        UIView *card = [self makeCard];
        card.frame = CGRectMake(m + col * (cw + gap), y + row * (ch + gap), cw, ch);
        UILabel *lab = [self makeLabel:[RPTheme readable:17] color:[RPTheme text]];
        lab.text = [self lineForItem:raw reminder:reminder];
        lab.frame = CGRectMake(14, 8, cw - 28, ch - 16);
        [card addSubview:lab];
        [scroll addSubview:card];
        shown++;
    }
    NSInteger rows = (shown + cols - 1) / cols;
    return y + rows * (ch + gap) + 8;
}
- (CGFloat)addReminderSection:(NSArray *)items y:(CGFloat)y width:(CGFloat)w margin:(CGFloat)m scroll:(UIScrollView *)scroll columns:(NSInteger)cols {
    if (items.count == 0) return y;
    if (cols < 1) cols = 1;
    UILabel *head = [self makeLabel:[RPTheme title:22] color:[RPTheme accent]];
    head.text = @"提醒事项";
    head.frame = CGRectMake(m, y, w, 28);
    [scroll addSubview:head];
    y += 34;
    CGFloat gap = 10;
    CGFloat cw = (w - gap * (cols - 1)) / cols;
    CGFloat ch = 86;
    NSInteger shown = 0;
    for (NSDictionary *raw in items) {
        if (![raw isKindOfClass:[NSDictionary class]] || shown >= 12) break;
        BOOL done = [raw[@"completed"] boolValue];
        NSInteger col = shown % cols;
        NSInteger row = shown / cols;
        UIView *card = [self makeCard];
        card.frame = CGRectMake(m + col * (cw + gap), y + row * (ch + gap), cw, ch);
        UIButton *check = [UIButton buttonWithType:UIButtonTypeSystem];
        check.frame = CGRectMake(8, 12, 52, 48);
        check.titleLabel.font = [RPTheme readable:28];
        [check setTitle:done ? @"已" : @"待" forState:UIControlStateNormal];
        [check setTitleColor:done ? [RPTheme ok] : [RPTheme text] forState:UIControlStateNormal];
        objc_setAssociatedObject(check, &kRPReminderID, raw[@"id"] ?: @"", OBJC_ASSOCIATION_COPY_NONATOMIC);
        [check addTarget:self action:@selector(onReminderCheck:) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:check];
        UILabel *lab = [self makeLabel:[RPTheme readable:17] color:done ? [RPTheme textDim] : [RPTheme text]];
        lab.text = [self lineForItem:raw reminder:YES];
        lab.frame = CGRectMake(64, 8, cw - 78, ch - 16);
        [card addSubview:lab];
        [scroll addSubview:card];
        shown++;
    }
    NSInteger rows = (shown + cols - 1) / cols;
    return y + rows * (ch + gap) + 8;
}
@end

static NSString *RPGrouped(double n, NSInteger frac) {
    // One formatter per fraction width (0–8), built once; this runs ~8 times per quote row.
    static NSMutableDictionary *byFrac;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ byFrac = [NSMutableDictionary dictionary]; });
    NSInteger f = MAX(0, MIN(8, frac));
    NSNumberFormatter *fmt;
    @synchronized (byFrac) {
        fmt = byFrac[@(f)];
        if (!fmt) {
            fmt = [[NSNumberFormatter alloc] init];
            fmt.numberStyle = NSNumberFormatterDecimalStyle;
            fmt.minimumFractionDigits = f;
            fmt.maximumFractionDigits = f;
            fmt.usesGroupingSeparator = YES;
            byFrac[@(f)] = fmt;
        }
    }
    return [fmt stringFromNumber:@(n)] ?: @"0";
}

static NSInteger RPPriceFrac(double n, BOOL crypto) {
    if (!crypto) return 2;
    if (n >= 1000.0) return 1;
    if (n >= 1.0) return 2;
    if (n >= 0.01) return 4;
    return 6;
}

static NSString *RPSigned(double n, NSInteger frac) {
    NSString *body = RPGrouped(fabs(n), frac);
    if (n > 0.0000001) return [@"+" stringByAppendingString:body];
    if (n < -0.0000001) return [@"-" stringByAppendingString:body];
    return body;
}

static NSString *RPTurnover(double n) {
    if (n >= 100000000.0) return [NSString stringWithFormat:@"%.2f亿", n / 100000000.0];
    if (n >= 10000.0) return [NSString stringWithFormat:@"%.1f万", n / 10000.0];
    if (n <= 0) return @"";
    return RPGrouped(n, 0);
}

static UIColor *RPMoveColor(double percent) {
    if (percent > 0.0001) return [RPTheme bad];
    if (percent < -0.0001) return [RPTheme ok];
    return [RPTheme textDim];
}

@interface RPQuotePageVC ()
@property (nonatomic, copy) NSArray *quoteItems;
@end

@implementation RPQuotePageVC
- (void)onQuoteTap:(UITapGestureRecognizer *)gr {
    NSInteger i = gr.view.tag - 7100;
    if (i < 0 || i >= (NSInteger)self.quoteItems.count) return;
    NSDictionary *item = self.quoteItems[i];
    if (![item isKindOfClass:[NSDictionary class]]) return;
    BOOL crypto = [item[@"market"] isEqualToString:@"crypto"];
    double price = [item[@"price"] doubleValue];
    NSInteger frac = RPPriceFrac(price, crypto);
    NSString *unit = [item[@"unit"] isKindOfClass:[NSString class]] ? item[@"unit"] : @"";
    NSString *turn = RPTurnover([item[@"turnover"] doubleValue]);
    NSMutableString *body = [NSMutableString string];
    [body appendFormat:@"最新  %@ %@\n", RPGrouped(price, frac), unit];
    [body appendFormat:@"涨跌  %@    %@%%\n", RPSigned([item[@"change"] doubleValue], frac), RPSigned([item[@"percent"] doubleValue], 2)];
    [body appendFormat:@"今开  %@\n最高  %@\n最低  %@\n%@  %@",
        RPGrouped([item[@"open"] doubleValue], frac),
        RPGrouped([item[@"high"] doubleValue], frac),
        RPGrouped([item[@"low"] doubleValue], frac),
        crypto ? @"24小时前" : @"昨收",
        RPGrouped([item[@"prev"] doubleValue], frac)];
    if (turn.length) [body appendFormat:@"\n%@  %@", crypto ? @"24小时成交额" : @"成交额", turn];
    [self showDetailWithTitle:item[@"name"] body:body meta:item[@"symbol"] imageURL:nil];
}

- (void)applyState:(NSDictionary *)state baseURL:(NSString *)baseURL {
    (void)baseURL;
    BOOL crypto = [self.quoteKind isEqualToString:@"crypto"];
    NSArray *items = crypto ? state[@"crypto"] : state[@"stocks"];
    if (![items isKindOfClass:[NSArray class]]) items = @[];
    CGRect b = self.contentView.bounds;
    NSString *fp = [NSString stringWithFormat:@"quote-%@|%@", self.quoteKind ?: @"", RPHashObject(items)];
    if ([self shouldSkipRebuildForKey:fp bounds:b]) return;
    [self clearContent];
    self.quoteItems = items;

    CGFloat m = [self mInset];
    CGFloat w = b.size.width - m * 2.0;
    NSInteger up = 0, down = 0;
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        double pct = [item[@"percent"] doubleValue];
        if (pct > 0.0001) up++;
        else if (pct < -0.0001) down++;
    }
    UILabel *bias = [self makeLabel:[RPTheme title:20] color:[RPTheme textDim]];
    bias.textAlignment = NSTextAlignmentLeft;
    bias.text = items.count ? [NSString stringWithFormat:@"涨 %ld    跌 %ld", (long)up, (long)down] : @"";
    bias.frame = CGRectMake(m, 4, w * 0.42, 28);
    [self.contentView addSubview:bias];

    UILabel *sub = [self makeLabel:[RPTheme body:16] color:[RPTheme textDim]];
    sub.textAlignment = NSTextAlignmentRight;
    sub.text = crypto ? @"比特币、以太坊等主流币 · USDT · 每 30 分钟" : @"沪深行情 · 红涨绿跌 · 每 30 分钟";
    sub.frame = CGRectMake(m + w * 0.42, 6, w * 0.58, 24);
    [self.contentView addSubview:sub];

    if (items.count == 0) {
        UILabel *empty = [self makeLabel:[RPTheme body:22] color:[RPTheme textDim]];
        empty.text = crypto
            ? @"正在通过代理读取比特币、以太坊等行情。"
            : @"正在读取沪深行情。代码写在设置里，用逗号分开。";
        empty.frame = CGRectMake(m, 44, w, 120);
        [self.contentView addSubview:empty];
        return;
    }

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 38, b.size.width, b.size.height - 54)];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.contentView addSubview:scroll];
    NSInteger n = (NSInteger)items.count;
    CGFloat gap = 8;
    CGFloat rowH = floor((scroll.bounds.size.height - gap * MAX(n - 1, 0) - 4) / MAX(n, 1));
    if (rowH > 168) rowH = 168;
    if (rowH < 118) rowH = 118;
    CGFloat sy = 0;
    NSInteger shown = 0;
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        double price = [item[@"price"] doubleValue];
        double pct = [item[@"percent"] doubleValue];
        double change = [item[@"change"] doubleValue];
        NSInteger frac = RPPriceFrac(price, crypto);
        UIColor *move = RPMoveColor(pct);
        UIView *card = [self makeCardTinted:shown accent:move];
        card.frame = CGRectMake(m, sy, w, rowH);
        card.tag = 7100 + shown;
        card.userInteractionEnabled = YES;
        if (pct > 0.0001) card.backgroundColor = [UIColor colorWithRed:0.32 green:0.11 blue:0.13 alpha:0.96];
        else if (pct < -0.0001) card.backgroundColor = [RPTheme tintGreen];
        UIView *bar = [card viewWithTag:8801];
        bar.backgroundColor = move;
        [card addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onQuoteTap:)]];

        // Three columns: left meta · center maximized price · right change/range.
        CGFloat padL = 14.0;
        CGFloat padR = 12.0;
        CGFloat sideW = floor(w * 0.26);
        if (sideW < 120.0) sideW = 120.0;
        if (sideW > 200.0) sideW = 200.0;
        CGFloat leftX = padL;
        CGFloat rightX = w - padR - sideW;
        CGFloat centerX = leftX + sideW + 4.0;
        CGFloat centerW = MAX(80.0, rightX - centerX - 4.0);
        CGFloat topY = 8.0;
        CGFloat botPad = 8.0;

        NSString *symbol = [item[@"symbol"] isKindOfClass:[NSString class]] ? item[@"symbol"] : @"";
        NSString *nameText = [item[@"name"] isKindOfClass:[NSString class]] ? item[@"name"] : @"";
        NSString *unit = [item[@"unit"] isKindOfClass:[NSString class]] ? item[@"unit"] : @"";
        NSString *turn = RPTurnover([item[@"turnover"] doubleValue]);

        UILabel *name = [self makeLabel:[RPTheme title:22] color:[RPTheme text]];
        name.textAlignment = NSTextAlignmentLeft;
        name.adjustsFontSizeToFitWidth = YES;
        name.minimumScaleFactor = 0.7;
        name.numberOfLines = 1;
        name.text = nameText.length ? nameText : symbol;
        name.frame = CGRectMake(leftX, topY, sideW, 26);
        [card addSubview:name];

        UILabel *sym = [self makeLabel:[RPTheme body:16] color:[RPTheme textDim]];
        sym.textAlignment = NSTextAlignmentLeft;
        sym.text = symbol;
        sym.frame = CGRectMake(leftX, topY + 26, sideW, 20);
        [card addSubview:sym];

        UILabel *openL = [self makeLabel:[RPTheme body:15] color:[RPTheme textDim]];
        openL.textAlignment = NSTextAlignmentLeft;
        openL.adjustsFontSizeToFitWidth = YES;
        openL.minimumScaleFactor = 0.6;
        openL.numberOfLines = 1;
        openL.text = [NSString stringWithFormat:@"开 %@", RPGrouped([item[@"open"] doubleValue], frac)];
        openL.frame = CGRectMake(leftX, rowH - botPad - 42, sideW, 20);
        [card addSubview:openL];

        UILabel *prevL = [self makeLabel:[RPTheme body:15] color:[RPTheme textDim]];
        prevL.textAlignment = NSTextAlignmentLeft;
        prevL.adjustsFontSizeToFitWidth = YES;
        prevL.minimumScaleFactor = 0.6;
        prevL.numberOfLines = 1;
        NSString *prevLabel = crypto ? @"24h前" : @"昨收";
        prevL.text = [NSString stringWithFormat:@"%@ %@", prevLabel, RPGrouped([item[@"prev"] doubleValue], frac)];
        prevL.frame = CGRectMake(leftX, rowH - botPad - 22, sideW, 20);
        [card addSubview:prevL];

        CGFloat priceFont = MIN(92.0, MAX(44.0, rowH * 0.58));
        UILabel *px = [self makeLabel:[RPTheme hero:priceFont] color:move];
        px.textAlignment = NSTextAlignmentCenter;
        px.adjustsFontSizeToFitWidth = YES;
        px.minimumScaleFactor = 0.35;
        px.numberOfLines = 1;
        px.text = RPGrouped(price, frac);
        px.frame = CGRectMake(centerX, 10, centerW, rowH - 36);
        [card addSubview:px];

        UILabel *unitL = [self makeLabel:[RPTheme body:14] color:[RPTheme textDim]];
        unitL.textAlignment = NSTextAlignmentCenter;
        unitL.text = unit;
        unitL.frame = CGRectMake(centerX, rowH - botPad - 18, centerW, 18);
        [card addSubview:unitL];

        UILabel *pctL = [self makeLabel:[RPTheme title:26] color:move];
        pctL.textAlignment = NSTextAlignmentRight;
        pctL.adjustsFontSizeToFitWidth = YES;
        pctL.minimumScaleFactor = 0.6;
        pctL.numberOfLines = 1;
        pctL.text = [NSString stringWithFormat:@"%@%%", RPSigned(pct, 2)];
        pctL.frame = CGRectMake(rightX, topY, sideW, 28);
        [card addSubview:pctL];

        UILabel *chgL = [self makeLabel:[RPTheme title:18] color:move];
        chgL.textAlignment = NSTextAlignmentRight;
        chgL.adjustsFontSizeToFitWidth = YES;
        chgL.minimumScaleFactor = 0.6;
        chgL.numberOfLines = 1;
        chgL.text = RPSigned(change, frac);
        chgL.frame = CGRectMake(rightX, topY + 28, sideW, 22);
        [card addSubview:chgL];

        UILabel *highL = [self makeLabel:[RPTheme body:15] color:[RPTheme textDim]];
        highL.textAlignment = NSTextAlignmentRight;
        highL.adjustsFontSizeToFitWidth = YES;
        highL.minimumScaleFactor = 0.6;
        highL.numberOfLines = 1;
        highL.text = [NSString stringWithFormat:@"高 %@", RPGrouped([item[@"high"] doubleValue], frac)];
        highL.frame = CGRectMake(rightX, rowH - botPad - 42, sideW, 20);
        [card addSubview:highL];

        UILabel *lowL = [self makeLabel:[RPTheme body:15] color:[RPTheme textDim]];
        lowL.textAlignment = NSTextAlignmentRight;
        lowL.adjustsFontSizeToFitWidth = YES;
        lowL.minimumScaleFactor = 0.6;
        lowL.numberOfLines = 1;
        if (turn.length) {
            lowL.text = [NSString stringWithFormat:@"%@ %@", crypto ? @"24h" : @"成交", turn];
        } else {
            lowL.text = [NSString stringWithFormat:@"低 %@", RPGrouped([item[@"low"] doubleValue], frac)];
        }
        lowL.frame = CGRectMake(rightX, rowH - botPad - 22, sideW, 20);
        [card addSubview:lowL];

        // If turnover took the bottom-right slot, still show 低 just above when space allows.
        if (turn.length && rowH >= 140) {
            UILabel *lowExtra = [self makeLabel:[RPTheme body:14] color:[RPTheme textDim]];
            lowExtra.textAlignment = NSTextAlignmentRight;
            lowExtra.adjustsFontSizeToFitWidth = YES;
            lowExtra.minimumScaleFactor = 0.6;
            lowExtra.numberOfLines = 1;
            lowExtra.text = [NSString stringWithFormat:@"低 %@", RPGrouped([item[@"low"] doubleValue], frac)];
            lowExtra.frame = CGRectMake(rightX, rowH - botPad - 62, sideW, 18);
            [card addSubview:lowExtra];
        }

        [scroll addSubview:card];
        sy += rowH + gap;
        shown++;
    }
    scroll.contentSize = CGSizeMake(b.size.width, sy + 8);
}
@end

#pragma mark - Video

static NSString *RPLastVideoKey = @"";

static BOOL RPVideoExtensionOK(NSString *ext) {
    ext = ext.lowercaseString ?: @"";
    return [ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] || [ext isEqualToString:@"m4v"];
}

static id RPVideoPick(NSArray *items, NSString *identity) {
    if (items.count == 0) return nil;
    uint32_t n = (uint32_t)items.count;
    uint32_t i = arc4random_uniform(n);
    if (items.count > 1 && identity.length) {
        id first = items[i];
        NSString *mark = [first isKindOfClass:[PHAsset class]] ? ((PHAsset *)first).localIdentifier : [first description];
        if ([mark isEqualToString:identity]) i = (i + 1) % n;
    }
    return items[i];
}

static NSArray *RPVideoLinksInPage(NSData *data, NSString *pageURL) {
    NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (html.length == 0) html = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (html.length == 0) return @[];
    NSURL *base = [NSURL URLWithString:pageURL];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"href\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]" options:NSRegularExpressionCaseInsensitive error:nil];
    NSMutableArray *urls = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSTextCheckingResult *m in [re matchesInString:html options:0 range:NSMakeRange(0, html.length)]) {
        if (m.numberOfRanges < 2) continue;
        NSString *href = [html substringWithRange:[m rangeAtIndex:1]];
        if ([href hasPrefix:@"#"] || [href hasPrefix:@"javascript:"]) continue;
        NSURL *url = [NSURL URLWithString:href relativeToURL:base];
        if (!url.scheme.length) continue;
        if (!RPVideoExtensionOK(url.pathExtension)) continue;
        NSString *abs = url.absoluteString;
        if (abs.length == 0 || [seen containsObject:abs]) continue;
        [seen addObject:abs];
        [urls addObject:abs];
        if (urls.count >= 40) break;
    }
    return urls;
}

@interface RPVideoPageVC ()
@property (nonatomic, strong) RPPhotoSource *photos;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSTimer *watchTimer;
@property (nonatomic, strong) NSTimer *capTimer;
@property (nonatomic, assign) NSInteger playToken;
@property (nonatomic, assign) PHImageRequestID videoRequest;
@property (nonatomic, assign) BOOL advancing;
@property (nonatomic, strong) UIButton *muteButton;
@end

@implementation RPVideoPageVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.contentView.backgroundColor = [UIColor blackColor];
    self.statusLabel = [self makeLabel:[RPTheme readable:22] color:[UIColor colorWithWhite:0.9 alpha:1]];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.contentView addSubview:self.statusLabel];
}
- (void)setPhotoSource:(id)photoSource slot:(NSInteger)slot {
    (void)slot;
    if ([photoSource isKindOfClass:[RPPhotoSource class]]) self.photos = photoSource;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.playerLayer.frame = self.contentView.bounds;
    self.statusLabel.frame = UIEdgeInsetsInsetRect(self.contentView.bounds, UIEdgeInsetsMake(48, 36, 48, 36));
    if (self.muteButton) self.muteButton.frame = CGRectMake(self.contentView.bounds.size.width - 160, 16, 144, 48);
}
- (void)parkMotionOffscreen {}
- (void)playPageIntro {}
- (void)playPageOutro:(void (^)(void))done {
    [self stopPlayback];
    if (done) done();
}
- (void)pageWillAppear {
    self.advancing = NO;
    self.playToken += 1;
    [self stopPlayback];
    [self showStatus:@"正在准备视频…"];
    NSInteger token = self.playToken;
    NSDictionary *cfg = RPVideoSettings();
    [self updateMuteButton];
    if (self.network) {
        NSString *dir = cfg[@"http"] ?: @"";
        NSString *user = cfg[@"http_user"] ?: @"";
        NSString *pass = cfg[@"http_pass"] ?: @"";
        if (dir.length == 0) {
            [self showStatus:@"还没有填写视频目录。\n打开设置 → 网络视频，填 HTTP 或 WebDAV 地址。"];
            return;
        }
        [self showStatus:@"正在读取视频目录…"];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *why = nil;
            NSString *picked = [self pickNetworkVideo:dir user:user pass:pass why:&why];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (token != self.playToken) return;
                if (picked.length == 0) {
                    [self showStatus:why.length ? why : @"这个目录里没有 mp4、mov 或 m4v。"];
                    return;
                }
                RPLastVideoKey = picked;
                [self startPlayer:[self networkItem:picked user:user pass:pass] name:picked];
            });
        });
        return;
    }
    // 相册视频. Uploaded files are part of this board too (browser "上传到这台 iPad").
    NSArray *uploaded = RPVideoLocalFiles();
    BOOL useUploads = [cfg[@"source"] isEqualToString:@"files"] && uploaded.count > 0;
    if (useUploads) {
        [self playPickedFile:token];
    } else {
        [self playPickedAlbum:token album:cfg[@"album"] ?: @"" fallback:cfg[@"photo_album"] ?: @""];
    }
}

#pragma mark Network directory (HTTP listing / WebDAV)

static NSString *RPBasicAuthHeader(NSString *user, NSString *pass) {
    if (user.length == 0) return nil;
    NSData *raw = [[NSString stringWithFormat:@"%@:%@", user, pass ?: @""] dataUsingEncoding:NSUTF8StringEncoding];
    return [@"Basic " stringByAppendingString:[raw base64EncodedStringWithOptions:0]];
}

/** Video URLs found in a WebDAV PROPFIND (Depth: 1) multistatus body. */
static NSArray *RPVideoLinksInDAV(NSData *data, NSURL *base) {
    NSString *xml = [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding];
    if (xml.length == 0) return @[];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<(?:[A-Za-z0-9]+:)?href>\\s*([^<]+?)\\s*</(?:[A-Za-z0-9]+:)?href>" options:NSRegularExpressionCaseInsensitive error:nil];
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSTextCheckingResult *m in [re matchesInString:xml options:0 range:NSMakeRange(0, xml.length)]) {
        NSString *href = [[xml substringWithRange:[m rangeAtIndex:1]] stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
        NSURL *u = [NSURL URLWithString:href relativeToURL:base];
        if (!u || !RPVideoExtensionOK([u.path pathExtension])) continue;
        NSString *abs = u.absoluteString;
        if (abs.length == 0 || [seen containsObject:abs]) continue;
        [seen addObject:abs];
        [out addObject:abs];
        if (out.count >= 200) break;
    }
    return out;
}

/** Pick one video from the directory. Tries WebDAV PROPFIND first, then a plain
    GET of the directory page (nginx/Apache/python http.server index). Runs off main. */
- (NSString *)pickNetworkVideo:(NSString *)dir user:(NSString *)user pass:(NSString *)pass why:(NSString **)why {
    NSString *raw = [dir stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([raw hasPrefix:@"\\\\"] || [raw.lowercaseString hasPrefix:@"smb://"]) {
        if (why) *why = @"iPad 读不了 SMB 共享（\\\\电脑\\共享）。\n请把视频放在 HTTP 或 WebDAV 共享里，再填 http:// 开头的地址。";
        return @"";
    }
    if (![raw hasPrefix:@"http://"] && ![raw hasPrefix:@"https://"]) raw = [@"http://" stringByAppendingString:raw];
    NSURL *url = [NSURL URLWithString:raw];
    if (!url) { if (why) *why = @"视频目录地址不对。"; return @""; }
    if (RPVideoExtensionOK(url.pathExtension)) return url.absoluteString;  // a single file
    if (![raw hasSuffix:@"/"]) url = [NSURL URLWithString:[raw stringByAppendingString:@"/"]];
    NSString *auth = RPBasicAuthHeader(user, pass);
    NSMutableDictionary *headers = [NSMutableDictionary dictionary];
    if (auth) headers[@"Authorization"] = auth;
    NSError *err = nil;
    NSArray *links = @[];
    // WebDAV
    NSMutableDictionary *dav = [headers mutableCopy];
    dav[@"Depth"] = @"1";
    dav[@"Content-Type"] = @"application/xml";
    NSData *propfind = [@"<?xml version=\"1.0\"?><d:propfind xmlns:d=\"DAV:\"><d:prop><d:resourcetype/></d:prop></d:propfind>" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *davData = [RPNet syncRequest:url.absoluteString method:@"PROPFIND" body:propfind proxy:nil headers:dav timeout:15 error:&err];
    links = RPVideoLinksInDAV(davData, url);
    if (links.count == 0) {
        err = nil;
        NSData *page = [RPNet syncGET:url.absoluteString proxy:nil headers:headers timeout:15 error:&err];
        links = RPVideoLinksInPage(page, url.absoluteString);
        if (!page && why) {
            NSString *msg = err.localizedDescription ?: @"连不上";
            *why = [msg hasPrefix:@"HTTP 401"] || [msg hasPrefix:@"HTTP 403"]
                ? @"视频目录需要登录。\n在设置 → 网络视频里填用户名和密码。"
                : [NSString stringWithFormat:@"读不到视频目录：%@", msg];
        }
    }
    return RPVideoPick(links, RPLastVideoKey) ?: @"";
}

/** AVPlayerItem for a network URL. Basic auth goes in as a request header; iOS 9's
    AVURLAsset accepts it through the (long-standing, undocumented) header option. */
- (AVPlayerItem *)networkItem:(NSString *)link user:(NSString *)user pass:(NSString *)pass {
    NSURL *url = [NSURL URLWithString:link];
    if (!url) return nil;
    NSString *auth = RPBasicAuthHeader(user, pass);
    if (!auth) return [AVPlayerItem playerItemWithURL:url];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{ @"AVURLAssetHTTPHeaderFieldsKey": @{ @"Authorization": auth } }];
    return [AVPlayerItem playerItemWithAsset:asset];
}

#pragma mark Mute

- (void)updateMuteButton {
    if (!self.muteButton) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.titleLabel.font = [RPTheme title:22];
        b.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        b.layer.cornerRadius = 10;
        b.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
        [b addTarget:self action:@selector(toggleMute) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:b];
        self.muteButton = b;
    }
    BOOL muted = [RPVideoSettings()[@"muted"] boolValue];
    [self.muteButton setTitle:muted ? @"🔇 已静音" : @"🔊 有声" forState:UIControlStateNormal];
    self.muteButton.frame = CGRectMake(self.contentView.bounds.size.width - 160, 16, 144, 48);
    [self.contentView bringSubviewToFront:self.muteButton];
    self.player.muted = muted;
}

- (void)toggleMute {
    BOOL muted = ![RPVideoSettings()[@"muted"] boolValue];
    RPVideoSetMuted(muted);
    // The clip started under Ambient (muted), which the side mute switch silences.
    // Switch the session too, or "有声" stays silent until the next clip.
    NSError *err = nil;
    [[AVAudioSession sharedInstance] setCategory:muted ? AVAudioSessionCategoryAmbient : AVAudioSessionCategoryPlayback error:&err];
    [[AVAudioSession sharedInstance] setActive:YES error:&err];
    (void)err;
    [self updateMuteButton];
}
- (void)pageDidDisappear {
    self.playToken += 1;
    [self stopPlayback];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RPVideoHold" object:nil userInfo:@{ @"hold": @NO }];
    [super pageDidDisappear];
}
- (void)applyState:(NSDictionary *)state baseURL:(NSString *)baseURL {
    (void)state; (void)baseURL;
}
- (void)showStatus:(NSString *)text {
    self.statusLabel.hidden = NO;
    self.statusLabel.text = text;
}
- (void)playPickedFile:(NSInteger)token {
    (void)token;
    NSArray *files = RPVideoLocalFiles();
    NSString *path = RPVideoPick(files, RPLastVideoKey);
    if (path.length == 0) {
        [self showStatus:@"还没有上传视频。\n用浏览器打开设置页，来源选「上传到这台 iPad」。"];
        return;
    }
    RPLastVideoKey = path;
    [self startPlayer:[AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]] name:path.lastPathComponent];
}
- (void)playPickedAlbum:(NSInteger)token album:(NSString *)album fallback:(NSString *)fallback {
    if (!self.photos) self.photos = [[RPPhotoSource alloc] init];
    [self.photos ensureAuthorization:^(BOOL granted) {
        if (token != self.playToken) return;
        if (!granted) {
            [self showStatus:@"还没有允许访问照片，读不到相册里的视频。"];
            return;
        }
        NSString *look = album.length ? album : fallback;
        // Whole album (was the newest 80), so the random pick reaches old clips too.
        NSArray *assets = [self.photos videoAssetsInAlbumId:(look.length ? look : nil) limit:2000];
        if (assets.count == 0 && album.length == 0) assets = [self.photos videoAssetsInAlbumId:nil limit:2000];
        PHAsset *asset = RPVideoPick(assets, RPLastVideoKey);
        if (!asset) {
            [self showStatus:album.length ? @"这个相册里没有视频。\n在设置 → 相册视频里换一个相册。" : @"相册里没有视频。"];
            return;
        }
        RPLastVideoKey = asset.localIdentifier;
        PHVideoRequestOptions *opt = [[PHVideoRequestOptions alloc] init];
        opt.networkAccessAllowed = YES;
        opt.deliveryMode = PHVideoRequestOptionsDeliveryModeAutomatic;
        self.videoRequest = [[PHImageManager defaultManager] requestAVAssetForVideo:asset options:opt resultHandler:^(AVAsset *av, AVAudioMix *mix, NSDictionary *info) {
            (void)mix; (void)info;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (token != self.playToken) return;
                if (!av) {
                    [self showStatus:@"这条视频打不开。"];
                    return;
                }
                [self startPlayer:[AVPlayerItem playerItemWithAsset:av] name:asset.localIdentifier];
            });
        }];
    }];
}
- (NSString *)pickHTTPVideo:(NSString *)page {
    NSString *raw = [page stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (raw.length == 0) return @"";
    if (![raw hasPrefix:@"http://"] && ![raw hasPrefix:@"https://"]) raw = [@"http://" stringByAppendingString:raw];
    NSURL *url = [NSURL URLWithString:raw];
    if (!url) return @"";
    if (RPVideoExtensionOK(url.pathExtension)) return url.absoluteString;
    NSError *err = nil;
    NSData *data = [RPNet syncGET:url.absoluteString proxy:nil headers:nil timeout:12 error:&err];
    (void)err;
    NSArray *links = RPVideoLinksInPage(data, url.absoluteString);
    return RPVideoPick(links, RPLastVideoKey) ?: @"";
}
- (void)startPlayer:(AVPlayerItem *)item name:(NSString *)name {
    (void)name;
    if (!item) {
        [self showStatus:@"这条视频打不开。"];
        return;
    }
    [self stopPlayback];
    BOOL muted = [RPVideoSettings()[@"muted"] boolValue];
    NSError *audioErr = nil;
    // Muted playback must not stop other audio (the alert chime, music); Ambient also
    // respects the silent switch. With sound on, Playback so it is heard.
    [[AVAudioSession sharedInstance] setCategory:muted ? AVAudioSessionCategoryAmbient : AVAudioSessionCategoryPlayback error:&audioErr];
    [[AVAudioSession sharedInstance] setActive:YES error:&audioErr];
    (void)audioErr;
    self.player = [AVPlayer playerWithPlayerItem:item];
    self.player.muted = muted;
    self.player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.playerLayer.frame = self.contentView.bounds;
    self.playerLayer.backgroundColor = [UIColor blackColor].CGColor;
    [self.contentView.layer insertSublayer:self.playerLayer atIndex:0];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onVideoEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:item];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onVideoFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:item];
    self.watchTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(watchReady) userInfo:nil repeats:YES];
    NSInteger mins = [RPVideoSettings()[@"max"] integerValue];
    if (mins > 0) {
        self.capTimer = [NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval)mins * 60.0 target:self selector:@selector(onCap) userInfo:nil repeats:NO];
    }
    [self.player play];
}
- (void)watchReady {
    AVPlayerItem *item = self.player.currentItem;
    if (!item) return;
    if (item.status == AVPlayerItemStatusReadyToPlay) {
        [self.watchTimer invalidate];
        self.watchTimer = nil;
        self.statusLabel.hidden = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"RPVideoHold" object:nil userInfo:@{ @"hold": @YES }];
        if (self.player.rate < 0.1) [self.player play];
        return;
    }
    if (item.status == AVPlayerItemStatusFailed) {
        [self.watchTimer invalidate];
        self.watchTimer = nil;
        [self showStatus:@"这条视频播不了。请换 H.264 的 mp4。"];
        [self stopPlayback];
    }
}
- (void)onCap {
    [self finishAndAdvance];
}
- (void)onVideoEnded:(NSNotification *)note {
    (void)note;
    [self finishAndAdvance];
}
- (void)onVideoFailed:(NSNotification *)note {
    (void)note;
    [self showStatus:@"播放中断了。"];
    [self stopPlayback];
}
- (void)finishAndAdvance {
    if (self.advancing) return;
    self.advancing = YES;
    [self stopPlayback];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RPVideoHold" object:nil userInfo:@{ @"hold": @NO }];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"RPVideoAdvance" object:nil];
}
- (void)stopPlayback {
    [self.watchTimer invalidate];
    self.watchTimer = nil;
    [self.capTimer invalidate];
    self.capTimer = nil;
    if (self.videoRequest) {
        [[PHImageManager defaultManager] cancelImageRequest:self.videoRequest];
        self.videoRequest = 0;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:nil];
    [self.player pause];
    self.player = nil;
    [self.playerLayer removeFromSuperlayer];
    self.playerLayer = nil;
    // Don't deactivate the audio session here: that cut off a notice chime that was
    // still ringing when the video page left. Nothing else needs the session freed.
}
@end

#pragma mark - Factory

@implementation RPPageFactory
+ (BOOL)isWebPageId:(NSString *)pid {
    return [pid hasPrefix:@"web-"];
}
+ (UIViewController<RPPage> *)pageForId:(NSString *)pid title:(NSString *)title {
    UIViewController<RPPage> *vc = nil;
    if ([self isWebPageId:pid]) vc = [[RPWebPageVC alloc] init];
    else if ([pid isEqualToString:@"hello"]) vc = [[RPHelloPageVC alloc] init];
    else if ([pid isEqualToString:@"weather"]) { RPWeatherPageVC *w=[[RPWeatherPageVC alloc] init]; w.weekly=NO; vc=w; }
    else if ([pid isEqualToString:@"weather-weekly"]) { RPWeatherPageVC *w=[[RPWeatherPageVC alloc] init]; w.weekly=YES; vc=w; }
    else if ([pid isEqualToString:@"system"]) vc = [[RPSystemPageVC alloc] init];
    else if ([pid isEqualToString:@"vps"]) vc = [[RPVpsPageVC alloc] init];
    else if ([pid isEqualToString:@"daily-news"]) { RPNewsPageVC *n=[[RPNewsPageVC alloc] init]; n.github=NO; vc=n; }
    else if ([pid isEqualToString:@"github-news"]) { RPNewsPageVC *n=[[RPNewsPageVC alloc] init]; n.github=YES; vc=n; }
    else if ([pid isEqualToString:@"x-news"]) { RPNewsPageVC *n=[[RPNewsPageVC alloc] init]; n.feedKind=@"x"; vc=n; }
    else if ([pid isEqualToString:@"xiaohongshu-hot"]) { RPNewsPageVC *n=[[RPNewsPageVC alloc] init]; n.feedKind=@"xhs"; vc=n; }
    else if ([pid isEqualToString:@"bilibili-hot"]) { RPNewsPageVC *n=[[RPNewsPageVC alloc] init]; n.feedKind=@"bili"; vc=n; }
    else if ([pid isEqualToString:@"stocks-cn"]) { RPQuotePageVC *q=[[RPQuotePageVC alloc] init]; q.quoteKind=@"stock"; vc=q; }
    else if ([pid isEqualToString:@"crypto"]) { RPQuotePageVC *q=[[RPQuotePageVC alloc] init]; q.quoteKind=@"crypto"; vc=q; }
    else if ([pid isEqualToString:@"schedule"]) vc = [[RPSchedulePageVC alloc] init];
    else if ([pid isEqualToString:@"print"] || [pid isEqualToString:@"print-fleet"] ||
             [pid isEqualToString:@"print-temps"] || [pid isEqualToString:@"print-filament"]) {
        vc = [[RPPrintPageVC alloc] init];
    }
    else if ([pid isEqualToString:@"movie-now-showing"]) vc = [[RPMoviePageVC alloc] init];
    else if ([pid isEqualToString:@"steam-new-releases"]) { RPSteamPageVC *s=[[RPSteamPageVC alloc] init]; s.pageOffset=0; vc=s; }
    else if ([pid isEqualToString:@"steam-new-releases-2"]) { RPSteamPageVC *s=[[RPSteamPageVC alloc] init]; s.pageOffset=1; vc=s; }
    else if ([pid isEqualToString:@"gamer520-pc-latest"]) { RPGameListPageVC *g=[[RPGameListPageVC alloc] init]; g.kind=@"pc"; vc=g; }
    else if ([pid isEqualToString:@"gamer520-switch-latest"]) { RPGameListPageVC *g=[[RPGameListPageVC alloc] init]; g.kind=@"switch"; vc=g; }
    else if ([pid isEqualToString:@"ps5-games-latest"]) { RPGameListPageVC *g=[[RPGameListPageVC alloc] init]; g.kind=@"ps5"; vc=g; }
    else if ([pid isEqualToString:@"local-video"]) { RPVideoPageVC *v = [[RPVideoPageVC alloc] init]; v.network = NO; vc = v; }
    else if ([pid isEqualToString:@"net-video"]) { RPVideoPageVC *v = [[RPVideoPageVC alloc] init]; v.network = YES; vc = v; }
    else if ([pid hasPrefix:@"person-photo-local"] || [pid rangeOfString:@"person-photo"].location != NSNotFound) {
        RPPhotoPageVC *p=[[RPPhotoPageVC alloc] init];
        p.slot = ([pid rangeOfString:@"landscape"].location != NSNotFound) || [pid hasSuffix:@"-2"] ? 1 : 0;
        vc=p;
    }
    else {
        RPHelloPageVC *h = [[RPHelloPageVC alloc] init];
        vc = h;
    }
    vc.pageId = pid;
    vc.pageTitle = title ?: pid;
    return vc;
}
@end
