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
#import <ctype.h>

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
static const CGFloat kRPImageMaxSide = 720.0;
static const NSTimeInterval kRPIntroImageWait = 1.35;

static NSCache *RPImageCache(void) {
    static NSCache *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = [[NSCache alloc] init];
        c.countLimit = 28;
        // ~18 MB of decoded RGBA budget for the kiosk.
        c.totalCostLimit = 18 * 1024 * 1024;
    });
    return c;
}

void RPPurgeImageCache(void) {
    [RPImageCache() removeAllObjects];
}

static UIImage *RPDownscaleImage(UIImage *img, CGFloat maxSide) {
    if (!img) return nil;
    CGSize s = img.size;
    CGFloat longest = MAX(s.width, s.height);
    if (longest <= 1.0 || longest <= maxSide) return img;
    CGFloat scale = maxSide / longest;
    CGSize ns = CGSizeMake(MAX(1.0, round(s.width * scale)), MAX(1.0, round(s.height * scale)));
    UIGraphicsBeginImageContextWithOptions(ns, YES, 1.0);
    [img drawInRect:CGRectMake(0, 0, ns.width, ns.height)];
    UIImage *out = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return out ?: img;
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
        else if ([pageId isEqualToString:@"bilibili-hot"]) items = state[@"bilibili"][@"items"] ?: state[@"news"][@"bilibili_items"];
        else items = state[@"news"][@"daily_items"] ?: state[@"news"][@"daily"];
        NSInteger n = 0;
        for (NSDictionary *it in (items ?: @[])) {
            if (![it isKindOfClass:[NSDictionary class]]) continue;
            RPCollectURL(keys, it[@"image_url"], baseURL);
            if (++n >= 8) break;
        }
    }
    if (keys.count == 0) return;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        for (NSString *key in keys) {
            if ([RPImageCache() objectForKey:key]) continue;
            NSError *error = nil;
            NSString *proxy = nil;
            if ([key rangeOfString:@"github"].location != NSNotFound) {
                proxy = [[NSUserDefaults standardUserDefaults] stringForKey:RPProxyDefaultsKey];
                if (proxy.length == 0) proxy = RPLocalDefaultProxy();
            }
            NSData *data = [RPNet syncGET:key proxy:proxy headers:nil timeout:16 error:&error];
            UIImage *img = data ? RPDownscaleImage([UIImage imageWithData:data], kRPImageMaxSide) : nil;
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
    _introWaitToken += 1;
    NSInteger token = _introWaitToken;
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
    _introPlayed = NO;
    _pendingImageLoads = 0;
    for (UIView *v in self.contentView.subviews) [v removeFromSuperview];
}
- (void)tryPlayIntro {
    if (!_waitingIntro || _introPlayed) return;
    if (_pendingImageLoads > 0) return;
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
- (void)purgeDisplayedImages {
    void (^walk)(UIView *) = nil;
    __block void (^walkBlock)(UIView *) = ^(UIView *root) {
        if ([root isKindOfClass:[UIImageView class]]) {
            ((UIImageView *)root).image = nil;
        }
        for (UIView *sub in root.subviews) walkBlock(sub);
    };
    walk = walkBlock;
    walk(self.contentView);
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
- (CGAffineTransform)rpMotionShift:(NSInteger)kind index:(NSInteger)i outro:(BOOL)outro {
    CGFloat w = MAX(self.contentView.bounds.size.width, 480);
    CGFloat h = MAX(self.contentView.bounds.size.height, 320);
    NSInteger style = kind % 8;
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
        v.transform = [self rpMotionShift:kind index:(NSInteger)i outro:NO];
        v.alpha = (kind % 8 == 4 || kind % 8 == 6) ? 0 : 1;
        [UIView animateWithDuration:2.3 delay:MIN(0.55, i * 0.07) options:UIViewAnimationOptionCurveEaseOut animations:^{
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
        [UIView animateWithDuration:2.1 delay:MIN(0.35, i * 0.04) options:UIViewAnimationOptionCurveEaseIn animations:^{
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
- (UIView *)makeCard {
    return [self makeCardTinted:0 accent:nil];
}
- (UIView *)makeCardTinted:(NSInteger)idx accent:(UIColor *)accent {
    UIView *c = [[UIView alloc] init];
    c.backgroundColor = [RPTheme cardTint:idx];
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
    if (cached) {
        iv.image = cached;
        objc_setAssociatedObject(iv, &kRPImageURLKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
        return;
    }
    objc_setAssociatedObject(iv, &kRPImageURLKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self noteImageLoadBegan];
    __weak typeof(self) weakSelf = self;
    __weak UIImageView *weakIV = iv;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSString *proxy = nil;
        if ([key rangeOfString:@"github"].location != NSNotFound) {
            proxy = [[NSUserDefaults standardUserDefaults] stringForKey:RPProxyDefaultsKey];
            if (proxy.length == 0) proxy = RPLocalDefaultProxy();
        }
        NSData *data = [RPNet syncGET:key proxy:proxy headers:nil timeout:18 error:&error];
        UIImage *img = data ? RPDownscaleImage([UIImage imageWithData:data], kRPImageMaxSide) : nil;
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
    NSString *fp = [NSString stringWithFormat:@"hello3|%@|%@", period, text];
    if ([self shouldSkipRebuildForKey:fp bounds:b]) return;
    [self clearContent];
    BOOL landscape = [self isLandscape];
    CGFloat m = [self mInset];
    UIColor *tone = [RPTheme accent];
    if ([period isEqualToString:@"中午好"]) tone = [RPTheme tintOrange];
    else if ([period isEqualToString:@"晚上好"]) tone = [RPTheme tintPurple];

    UILabel *big = [self makeLabel:[RPTheme title:landscape ? 72 : 60] color:tone];
    big.text = period;
    big.textAlignment = NSTextAlignmentCenter;
    big.adjustsFontSizeToFitWidth = YES;
    big.minimumScaleFactor = 0.6;
    CGFloat bigH = landscape ? 110 : 100;
    big.frame = CGRectMake(m, landscape ? 36 : 48, b.size.width - 2 * m, bigH);
    [self.contentView addSubview:big];

    UILabel *line = [self makeLabel:[RPTheme title:36] color:waiting ? [RPTheme textDim] : [RPTheme text]];
    line.text = text;
    line.textAlignment = NSTextAlignmentCenter;
    line.numberOfLines = 4;
    line.adjustsFontSizeToFitWidth = YES;
    line.minimumScaleFactor = 0.45;
    CGFloat lineY = CGRectGetMaxY(big.frame) + (landscape ? 18 : 28);
    CGFloat lineH = b.size.height - lineY - (landscape ? 64 : 80);
    if (lineH < 80) lineH = 80;
    line.frame = CGRectMake(m + 24, lineY, b.size.width - 2 * m - 48, lineH);
    [self.contentView addSubview:line];

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    fmt.dateFormat = @"M月d日 EEEE";
    UILabel *when = [self makeLabel:[RPTheme body:22] color:[RPTheme textDim]];
    when.text = [fmt stringFromDate:[NSDate date]];
    when.textAlignment = NSTextAlignmentCenter;
    when.frame = CGRectMake(m, b.size.height - (landscape ? 48 : 56), b.size.width - 2 * m, 28);
    [self.contentView addSubview:when];
}
@end

#pragma mark - Weather

@implementation RPWeatherPageVC
- (void)applyState:(NSDictionary *)state baseURL:(NSString *)baseURL {
    (void)baseURL;
    CGRect b = self.contentView.bounds;
    NSDictionary *w = state[@"weather"] ?: @{};
    NSDictionary *vps = state[@"vps"] ?: @{};
    NSString *fp = [NSString stringWithFormat:@"weather2-%d|%@|%@", self.weekly?1:0, RPHashObject(w), RPHashObject(vps)];
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
        CGFloat heroW = landscape ? b.size.width*0.38 : b.size.width-2*m;
        CGFloat heroH = landscape ? 220 : 210;
        UIView *hero = [self makeCardTinted:0 accent:[RPTheme accent]];
        hero.frame = CGRectMake(m, y, heroW, heroH);
        UILabel *temp = [self makeLabel:[RPTheme hero:96] color:[RPTheme accent]];
        temp.text = [NSString stringWithFormat:@"%@°", w[@"temperature"] ?: @"--"];
        temp.frame = CGRectMake(22, 28, heroW*0.55, 100);
        UILabel *icon = [self makeLabel:[RPTheme weatherIcon:72] color:[RPTheme text]];
        icon.text = [NSString stringWithFormat:@"%@", w[@"icon"] ?: @""];
        icon.textAlignment = NSTextAlignmentCenter;
        icon.frame = CGRectMake(heroW*0.55, 36, heroW*0.4, 80);
        UILabel *desc = [self makeLabel:[RPTheme title:36] color:[RPTheme text]];
        desc.text = [NSString stringWithFormat:@"%@", w[@"description"]?:@""];
        desc.frame = CGRectMake(22, 130, heroW-40, 40);
        UILabel *meta = [self makeLabel:[RPTheme body:24] color:[RPTheme textDim]];
        meta.text = [NSString stringWithFormat:@"风 %@ · %@°~%@°", w[@"wind_speed"]?:@"-", w[@"temp_min"]?:@"-", w[@"temp_max"]?:@"-"];
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
                    UIView *card = [self makeCardTinted:(NSInteger)i+1 accent:[RPTheme tintBlue]];
                    card.frame = CGRectMake(x0 + col*(cw+gap), y + row*(ch+gap), cw, ch);
                    UILabel *day = [self makeLabel:[RPTheme title:20] color:[RPTheme accent]];
                    day.text = [NSString stringWithFormat:@"%@", d[@"weekday"]?:@""];
                    day.textAlignment = NSTextAlignmentCenter;
                    day.frame = CGRectMake(6, 8, cw-12, 24);
                    UILabel *ds = [self makeLabel:[RPTheme body:16] color:[RPTheme text]];
                    ds.text = [NSString stringWithFormat:@"%@", d[@"description"]?:@""];
                    ds.textAlignment = NSTextAlignmentCenter;
                    ds.numberOfLines = 1;
                    ds.frame = CGRectMake(6, 32, cw-12, 22);
                    UILabel *tr = [self makeLabel:[RPTheme mono:18] color:[RPTheme text]];
                    tr.text = [NSString stringWithFormat:@"%@° / %@°", d[@"temp_max"]?:@"-", d[@"temp_min"]?:@"-"];
                    tr.textAlignment = NSTextAlignmentCenter;
                    tr.adjustsFontSizeToFitWidth = YES;
                    tr.minimumScaleFactor = 0.7;
                    tr.frame = CGRectMake(6, ch-30, cw-12, 22);
                    [card addSubview:day]; [card addSubview:ds]; [card addSubview:tr];
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
                UIView *card = [self makeCardTinted:(NSInteger)i+1 accent:[UIColor colorWithRed:0.22 green:0.55 blue:0.95 alpha:1]];
                card.frame = CGRectMake(m + col*(cw+gap), y + row*(ch+gap), cw, ch);
                UILabel *day = [self makeLabel:[RPTheme title:26] color:[RPTheme accent]];
                day.text = [NSString stringWithFormat:@"%@", d[@"weekday"]?:@""];
                day.textAlignment = NSTextAlignmentCenter;
                day.frame = CGRectMake(6, 10, cw-12, 28);
                UILabel *ic = [self makeLabel:[RPTheme weatherIcon:40] color:[RPTheme text]];
                ic.text = [NSString stringWithFormat:@"%@", d[@"icon"]?:@""];
                ic.textAlignment = NSTextAlignmentCenter;
                ic.frame = CGRectMake(6, 42, cw-12, 42);
                UILabel *tr = [self makeLabel:[RPTheme mono:22] color:[RPTheme text]];
                tr.text = [NSString stringWithFormat:@"%@°/%@°", d[@"temp_max"]?:@"-", d[@"temp_min"]?:@"-"];
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
            UIView *card = [self makeCardTinted:(NSInteger)i accent:[RPTheme accent]];
            card.frame = CGRectMake(m + col*(cw+gap), y + row*(ch+gap), cw, ch);
            UILabel *day = [self makeLabel:[RPTheme title:28] color:[RPTheme accent]];
            day.text = [NSString stringWithFormat:@"%@", d[@"weekday"] ?: @""];
            day.frame = CGRectMake(14, 12, cw-28, 32);
            UILabel *icon = [self makeLabel:[RPTheme weatherIcon:44] color:[RPTheme text]];
            icon.text = [NSString stringWithFormat:@"%@", d[@"icon"] ?: @""];
            icon.frame = CGRectMake(14, 48, cw-28, 46);
            UILabel *desc = [self makeLabel:[RPTheme body:24] color:[RPTheme text]];
            desc.text = [NSString stringWithFormat:@"%@", d[@"description"]?:@""];
            desc.frame = CGRectMake(14, 96, cw-28, 28);
            UILabel *tr = [self makeLabel:[RPTheme mono:24] color:[RPTheme textDim]];
            tr.text = [NSString stringWithFormat:@"%@° ~ %@°", d[@"temp_min"]?:@"-", d[@"temp_max"]?:@"-"];
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
        CGFloat ch = MIN(120, b.size.height - y - m);
        NSArray *cards = @[
            @[@"流量使用", [NSString stringWithFormat:@"%.0f%%", [vps[@"percent"] floatValue]], [NSString stringWithFormat:@"%@", vps[@"used"]?:@""], [RPTheme accent]],
            @[@"剩余", [NSString stringWithFormat:@"%@", vps[@"remain"]?:@"-"], [NSString stringWithFormat:@"%@", vps[@"cycle"]?:@""], [RPTheme ok]],
            @[@"状态", [NSString stringWithFormat:@"%@", vps[@"status"]?:@"-"], @"Traffic", [RPTheme tintBlue]],
            @[@"周期", @"本月", [NSString stringWithFormat:@"%@", vps[@"cycle"]?:@""], [RPTheme tintPurple]],
        ];
        for (NSUInteger i=0; i<MIN((NSUInteger)cols, cards.count); i++) {
            NSArray *c = cards[i];
            UIView *card = [self makeCardTinted:(NSInteger)i accent:c[3]];
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
    NSString *fp = [NSString stringWithFormat:@"news2-%d-%@|%@|%@", self.github?1:0, kind, RPHashObject(items), baseURL?:@""];
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
    if ([kind isEqualToString:@"xhs"] || [kind isEqualToString:@"bili"]) {
        [self layoutCoverGrid:items bounds:b base:baseURL];
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
    NSInteger slots = MIN(5, MAX(1, maxN == 0 ? 1 : maxN));
    CGFloat cardH = floor((avail - gap * MAX(slots - 1, 0)) / slots);
    if (cardH < 118 && slots > 4) {
        slots = 4;
        cardH = floor((avail - gap * MAX(slots - 1, 0)) / slots);
    }
    if (cardH > 132) cardH = 132;
    if (cardH < 96) cardH = 96;
    maxN = MIN(maxN, slots);
    for (NSInteger i=0; i<maxN; i++) {
        NSDictionary *it = items[i];
        UIView *card = [self makeCardTinted:i accent:self.github ? [RPTheme tintPurple] : [RPTheme tintOrange]];
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
            metaLine = [NSString stringWithFormat:@"★ %@  ·  %@  ·  forks %@", it[@"stars"]?:@"0", it[@"language"]?:@"--", it[@"forks"]?:@"0"];
            NSString *img = [NSString stringWithFormat:@"%@", it[@"image_url"] ?: @""];
            if (img.length) imgURL = [self absURL:img base:baseURL];
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
    NSInteger n = MIN(12, (NSInteger)items.count);
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
    if (cardH > 108) cardH = 108;
    if (cardH < 76) cardH = 76;
    for (NSInteger i = 0; i < n; i++) {
        NSDictionary *it = items[i];
        NSInteger col = i % cols;
        NSInteger row = i / cols;
        UIView *card = [self makeCardTinted:i accent:[RPTheme accent]];
        card.frame = CGRectMake(m + col * (cardW + gap), top + row * (cardH + gap), cardW, cardH);
        card.tag = 7000 + i;
        card.userInteractionEnabled = YES;
        UILabel *rank = [self makeLabel:[RPTheme title:28] color:[RPTheme accent]];
        rank.text = [NSString stringWithFormat:@"%@", it[@"rank"] ?: @(i + 1)];
        rank.frame = CGRectMake(10, 8, 42, 32);
        [card addSubview:rank];
        NSString *zh = [NSString stringWithFormat:@"%@", it[@"zh"] ?: @""];
        if ([zh isEqualToString:@"(null)"]) zh = @"";
        NSString *title = [NSString stringWithFormat:@"%@", it[@"title"] ?: @""];
        if ([title isEqualToString:@"(null)"]) title = @"";
        UILabel *tl = [self makeLabel:[RPTheme title:22] color:[UIColor whiteColor]];
        tl.text = zh.length ? zh : title;
        tl.numberOfLines = 2;
        tl.frame = CGRectMake(54, 6, cardW - 66, cardH > 90 ? 48 : 40);
        [card addSubview:tl];
        UILabel *sl = [self makeLabel:[RPTheme body:14] color:[RPTheme textDim]];
        NSString *score = [NSString stringWithFormat:@"%@", it[@"score"] ?: @""];
        if ([score isEqualToString:@"(null)"]) score = @"";
        NSString *origin = zh.length ? title : @"";
        sl.text = score.length ? [NSString stringWithFormat:@"%@%@", origin.length ? [origin stringByAppendingString:@" · "] : @"", score] : origin;
        sl.numberOfLines = 1;
        sl.lineBreakMode = NSLineBreakByTruncatingTail;
        sl.frame = CGRectMake(54, cardH - 24, cardW - 66, 18);
        [card addSubview:sl];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(rpNewsTap:)];
        [card addGestureRecognizer:tap];
        objc_setAssociatedObject(card, &kRPImageURLKey, @{ @"item": it ?: @{}, @"base": @"", @"github": @NO }, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [self.contentView addSubview:card];
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
        UIView *card = [self makeCardTinted:i accent:[UIColor whiteColor]];
        card.frame = CGRectMake(m + col * (cardW + gap), top + row * (cardH + gap), cardW, cardH);
        card.tag = 7000 + i;
        card.userInteractionEnabled = YES;
        BOOL wide = cardW > cardH * 1.15;
        CGRect imgFrame = wide ? CGRectMake(0, 0, floor(cardW * 0.46), cardH) : CGRectMake(0, 0, cardW, floor(cardH * 0.62));
        UIImageView *iv = [[UIImageView alloc] initWithFrame:imgFrame];
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.clipsToBounds = YES;
        iv.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.2];
        [card addSubview:iv];
        NSString *img = [NSString stringWithFormat:@"%@", it[@"image_url"] ?: @""];
        if (img.length && ![img isEqualToString:@"(null)"]) {
            [self loadImageURL:[self absURL:img base:baseURL] into:iv];
        } else {
            UILabel *mark = [self makeLabel:[RPTheme hero:36] color:[UIColor whiteColor]];
            NSString *title = [NSString stringWithFormat:@"%@", it[@"title"] ?: @""];
            mark.text = title.length >= 2 ? [title substringToIndex:2] : title;
            mark.textAlignment = NSTextAlignmentCenter;
            mark.frame = iv.bounds;
            mark.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [iv addSubview:mark];
        }
        CGFloat textX = wide ? CGRectGetMaxX(imgFrame) + 12 : 14;
        CGFloat textY = wide ? 16 : CGRectGetMaxY(imgFrame) + 8;
        CGFloat textW = cardW - textX - 14;
        UILabel *tl = [self makeLabel:[RPTheme title:24] color:[UIColor whiteColor]];
        tl.text = [NSString stringWithFormat:@"%@", it[@"title"] ?: @""];
        tl.numberOfLines = 2;
        tl.frame = CGRectMake(textX, textY, textW, wide ? 64 : 52);
        [card addSubview:tl];
        UILabel *sl = [self makeLabel:[RPTheme body:18] color:[UIColor whiteColor]];
        sl.text = [NSString stringWithFormat:@"%@", it[@"summary"] ?: @""];
        sl.numberOfLines = 2;
        sl.frame = CGRectMake(textX, CGRectGetMaxY(tl.frame) + 4, textW, 44);
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

    NSDictionary *p = print[@"primary"] ?: @{};
    NSArray *printers = print[@"printers"] ?: @[];
    if (p.count == 0 && printers.count) p = printers[0];
    NSDictionary *temps = p[@"temps"] ?: @{};
    NSArray *ams = p[@"ams"] ?: @[];
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

        // Temps on right of status
        NSMutableArray *tempItems = [NSMutableArray array];
        [tempItems addObject:@[@"热床", [NSString stringWithFormat:@"%@°", temps[@"bed"]?:@"-"]]];
        [tempItems addObject:@[@"腔体", [NSString stringWithFormat:@"%@°", temps[@"chamber"]?:@"-"]]];
        [tempItems addObject:@[@"喷嘴", [NSString stringWithFormat:@"%@°", temps[@"nozzle"]?:@"-"]]];
        NSArray *nozzles = temps[@"nozzles"] ?: @[];
        for (NSDictionary *n in nozzles) {
            NSString *mark = [n[@"active"] boolValue] ? @"●" : @"○";
            [tempItems addObject:@[[NSString stringWithFormat:@"%@%@", mark, n[@"name"]?:@"喷嘴"],
                                   [NSString stringWithFormat:@"%@°", n[@"temp"]?:@"-"]]];
        }
        NSInteger tcols = MIN(3, (NSInteger)tempItems.count);
        CGFloat tgap = 8;
        CGFloat tcw = (rightW - tgap*(tcols-1)) / MAX(1,tcols);
        CGFloat tch = (statusH - tgap) / 2.0;
        for (NSUInteger i=0; i<tempItems.count; i++) {
            NSInteger row = i / tcols, col = i % tcols;
            if (row > 1) break;
            UIView *card = [self makeCard];
            card.frame = CGRectMake(rightX + col*(tcw+tgap), top + row*(tch+tgap), tcw, tch);
            UILabel *k = [self makeLabel:[RPTheme small:14] color:[RPTheme textDim]];
            k.text = tempItems[i][0]; k.frame = CGRectMake(10, 8, tcw-20, 20);
            UILabel *v = [self makeLabel:[RPTheme hero:36] color:[RPTheme accent]];
            v.text = tempItems[i][1]; v.frame = CGRectMake(10, 32, tcw-20, 48);
            [card addSubview:k]; [card addSubview:v];
            [self.contentView addSubview:card];
        }

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

        NSMutableArray *tempItems = [NSMutableArray array];
        [tempItems addObject:@[@"热床", [NSString stringWithFormat:@"%@°", temps[@"bed"]?:@"-"]]];
        [tempItems addObject:@[@"腔体", [NSString stringWithFormat:@"%@°", temps[@"chamber"]?:@"-"]]];
        [tempItems addObject:@[@"喷嘴", [NSString stringWithFormat:@"%@°", temps[@"nozzle"]?:@"-"]]];
        NSArray *nozzles = temps[@"nozzles"] ?: @[];
        for (NSDictionary *n in nozzles) {
            NSString *mark = [n[@"active"] boolValue] ? @"●" : @"○";
            [tempItems addObject:@[[NSString stringWithFormat:@"%@%@", mark, n[@"name"]?:@""],
                                   [NSString stringWithFormat:@"%@°", n[@"temp"]?:@"-"]]];
        }
        CGFloat ty = top + statusH + gap;
        NSInteger tcols = MIN(3, (NSInteger)tempItems.count);
        if (tempItems.count >= 5) tcols = 3;
        CGFloat tgap = 8;
        CGFloat tcw = (b.size.width - 2*m - tgap*(tcols-1)) / MAX(1,tcols);
        CGFloat tch = 88;
        NSInteger shown = MIN(6, (NSInteger)tempItems.count);
        NSInteger trows = (shown + tcols - 1) / tcols;
        for (NSUInteger i=0; i<(NSUInteger)shown; i++) {
            NSInteger row = i / tcols, col = i % tcols;
            UIView *card = [self makeCard];
            card.frame = CGRectMake(m + col*(tcw+tgap), ty + row*(tch+tgap), tcw, tch);
            UILabel *k = [self makeLabel:[RPTheme small:14] color:[RPTheme textDim]];
            k.text = tempItems[i][0]; k.frame = CGRectMake(10, 8, tcw-20, 20);
            UILabel *v = [self makeLabel:[RPTheme hero:32] color:[RPTheme accent]];
            v.text = tempItems[i][1]; v.frame = CGRectMake(10, 32, tcw-20, 44);
            [card addSubview:k]; [card addSubview:v];
            [self.contentView addSubview:card];
        }
        CGFloat amsTop = ty + trows*(tch+tgap) + 2;
        [self layoutAMS:ams inRect:CGRectMake(m, amsTop, b.size.width-2*m, bottomY-amsTop) landscape:NO];
    }
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
    for (NSDictionary *unit in ams) {
        unitNo++;
        NSInteger rawIndex = unit[@"index"] ? [unit[@"index"] integerValue] : (unitNo - 1);
        NSString *amsNo = [NSString stringWithFormat:@"%ld", (long)(rawIndex + 1)];
        NSArray *slots = unit[@"slots"] ?: @[];
        for (NSDictionary *slot in slots) {
            NSMutableDictionary *row = [NSMutableDictionary dictionaryWithDictionary:slot];
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
        NSDictionary *bound = slot[@"bound"] ?: @{};
        NSInteger row = i / cols, col = i % cols;
        if (gridTop + row*(ch+gap) + ch > rect.origin.y + rect.size.height + 1) break;
        UIView *card = [self makeCardTinted:(NSInteger)i accent:[RPTheme tintTeal]];
        card.frame = CGRectMake(rect.origin.x + col*(cw+gap), gridTop + row*(ch+gap), cw, ch);
        NSString *hex = bound[@"colorHex"] ?: slot[@"colorHex"] ?: @"888888FF";
        UIView *swatch = [[UIView alloc] initWithFrame:CGRectMake(10, 12, 18, 18)];
        swatch.backgroundColor = [self colorFromHex:hex];
        swatch.layer.cornerRadius = 4;
        [card addSubview:swatch];
        double pct = [bound[@"remainingPercent"] doubleValue];
        if (pct == 0 && slot[@"remainPercent"]) pct = [slot[@"remainPercent"] doubleValue];
        if (pct < 0) pct = 0;
        NSInteger slotNo = slot[@"slot"] ? [slot[@"slot"] integerValue] + 1 : (NSInteger)i + 1;
        UILabel *num = [self makeLabel:[RPTheme title:28] color:[RPTheme accent]];
        num.text = [NSString stringWithFormat:@"%ld", (long)slotNo];
        num.frame = CGRectMake(8, 4, 40, 30);
        UILabel *name = [self makeLabel:[RPTheme small:16] color:[RPTheme text]];
        NSString *nm = [NSString stringWithFormat:@"%@", bound[@"name"] ?: slot[@"type"] ?: @"空"];
        name.text = nm;
        name.adjustsFontSizeToFitWidth = YES;
        name.minimumScaleFactor = 0.7f;
        name.numberOfLines = 1;
        name.frame = CGRectMake(48, 8, cw-56, 22);
        UILabel *rp = [self makeLabel:[RPTheme title:40] color:(pct < 15 ? [RPTheme bad] : [RPTheme text])];
        rp.text = [NSString stringWithFormat:@"%.0f%%", pct];
        rp.textAlignment = NSTextAlignmentCenter;
        rp.adjustsFontSizeToFitWidth = YES;
        rp.minimumScaleFactor = 0.6f;
        rp.frame = CGRectMake(6, 34, cw-12, 44);
        UILabel *typ = [self makeLabel:[RPTheme small:14] color:[RPTheme textDim]];
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

@implementation RPMoviePageVC
- (void)applyState:(NSDictionary *)state baseURL:(NSString *)baseURL {
    CGRect b = self.contentView.bounds;
    NSArray *movies = state[@"movies"] ?: @[];
    NSString *fp = [NSString stringWithFormat:@"movies|%@|%@", RPHashObject(movies), baseURL?:@""];
    if ([self shouldSkipRebuildForKey:fp bounds:b]) return;
    [self clearContent];
    CGFloat m = [self mInset];
    BOOL landscape = [self isLandscape];
    NSInteger cols = landscape ? 4 : 3;
    NSInteger maxN = landscape ? 8 : 6;
    CGFloat gap = 10;
    CGFloat top = 8;
    CGFloat cw = (b.size.width - 2*m - gap*(cols-1)) / cols;
    CGFloat availH = b.size.height - top - m;
    NSInteger n = MIN(maxN, (NSInteger)movies.count);
    NSInteger rows = (n + cols - 1) / MAX(1,cols);
    // poster ratio ~2:3, caption ~40
    CGFloat ch = rows > 0 ? (availH - gap*(rows-1)) / MAX(1,rows) : 200;
    CGFloat imgH = MAX(80, ch - 42);
    ch = imgH + 42;
    for (NSUInteger i=0;i<(NSUInteger)n;i++) {
        NSDictionary *mov=movies[i];
        NSInteger row=i/cols, col=i%cols;
        UIView *card=[self makeCard];
        card.frame=CGRectMake(m+col*(cw+gap), top+row*(ch+gap), cw, ch);
        UIImageView *iv=[[UIImageView alloc] initWithFrame:CGRectMake(0,0,cw,imgH)];
        iv.contentMode=UIViewContentModeScaleAspectFill; iv.clipsToBounds=YES;
        iv.backgroundColor=[UIColor colorWithWhite:0.08 alpha:1];
        [card addSubview:iv];
        [self loadImageURL:[self absURL:mov[@"poster_url"] base:baseURL] into:iv];
        UILabel *t=[self makeLabel:[RPTheme body:14] color:[RPTheme text]];
        t.text=[NSString stringWithFormat:@"%@", mov[@"title"]?:@""];
        t.numberOfLines = 1;
        t.lineBreakMode = NSLineBreakByTruncatingTail;
        t.frame=CGRectMake(6, imgH+4, cw-12, 20);
        UILabel *rd=[self makeLabel:[RPTheme small:12] color:[RPTheme textDim]];
        rd.text=[NSString stringWithFormat:@"%@", mov[@"release_date"]?:@""];
        rd.frame=CGRectMake(6, imgH+24, cw-12, 16);
        [card addSubview:t]; [card addSubview:rd];
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
    NSInteger cols = landscape ? 3 : 2;
    NSInteger maxN = landscape ? 6 : 6;
    CGFloat gap = 10;
    CGFloat top = 8;
    CGFloat cw = (b.size.width - 2*m - gap*(cols-1)) / cols;
    CGFloat availH = b.size.height - top - m;
    NSInteger n = MIN(maxN, (NSInteger)items.count);
    NSInteger rows = MAX(1, (n + cols - 1) / cols);
    CGFloat ch = (availH - gap*(rows-1)) / rows;
    CGFloat imgH = MAX(60, ch - 58);
    ch = imgH + 58;
    // filter items missing art so we do not show a black hole slot
    NSMutableArray *vis = [NSMutableArray array];
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *img = item[@"header_url"] ?: item[@"capsule_url"] ?: item[@"image_url"] ?: @"";
        if ([img isKindOfClass:[NSString class]] && img.length > 0) [vis addObject:item];
        else if ([[NSString stringWithFormat:@"%@", item[@"title"]?:@""] length] > 0) [vis addObject:item];
    }
    if (vis.count) { items = vis; n = MIN(maxN, (NSInteger)items.count); rows = MAX(1, (n + cols - 1) / cols); ch = (availH - gap*(rows-1)) / rows; imgH = MAX(60, ch - 58); ch = imgH + 58; }
    for (NSUInteger i=0;i<(NSUInteger)n;i++) {
        NSDictionary *item=items[i];
        NSInteger row=i/cols, col=i%cols;
        UIView *card=[self makeCardTinted:(NSInteger)i accent:[RPTheme tintOrange]];
        card.frame=CGRectMake(m+col*(cw+gap), top+row*(ch+gap), cw, ch);
        UIImageView *iv=[[UIImageView alloc] initWithFrame:CGRectMake(0,0,cw,imgH)];
        iv.contentMode=UIViewContentModeScaleAspectFill; iv.clipsToBounds=YES;
        iv.backgroundColor=[UIColor colorWithRed:0.12 green:0.14 blue:0.2 alpha:1];
        [card addSubview:iv];
        NSString *img = item[@"header_url"] ?: item[@"capsule_url"] ?: item[@"image_url"];
        if ([img isKindOfClass:[NSString class]] && img.length) {
            [self loadImageURL:[self absURL:img base:baseURL] into:iv];
        } else {
            UILabel *ph=[self makeLabel:[RPTheme title:22] color:[RPTheme textDim]];
            ph.text=@"暂无封面"; ph.textAlignment=NSTextAlignmentCenter;
            ph.frame=iv.bounds; ph.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
            [iv addSubview:ph];
        }
        UILabel *t=[self makeLabel:[RPTheme body:22] color:[RPTheme text]];
        t.text=[NSString stringWithFormat:@"%@", item[@"title"]?:@""];
        t.frame=CGRectMake(8, imgH+4, cw-16, 26);
        t.numberOfLines = 1;
        t.lineBreakMode = NSLineBreakByTruncatingTail;
        [card addSubview:t];
        if (item[@"price"] || item[@"discount"]) {
            UILabel *pr=[self makeLabel:[RPTheme small:13] color:[RPTheme accent]];
            pr.text=[NSString stringWithFormat:@"%@ %@", item[@"discount"]?:@"", item[@"price"]?:@""];
            pr.frame=CGRectMake(8, imgH+32, cw-16, 16);
            [card addSubview:pr];
        }
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
    NSInteger cols = landscape ? 4 : 2;
    NSInteger maxN = 8;
    CGFloat gap = 10;
    CGFloat top = 8;
    CGFloat cw = (b.size.width - 2*m - gap*(cols-1)) / cols;
    CGFloat availH = b.size.height - top - m;
    NSInteger n = MIN(maxN, (NSInteger)items.count);
    NSInteger rows = MAX(1, (n + cols - 1) / cols);
    CGFloat ch = (availH - gap*(rows-1)) / rows;
    CGFloat imgH = MAX(70, ch - 48);
    ch = imgH + 48;
    for (NSUInteger i=0;i<(NSUInteger)n;i++) {
        NSDictionary *item=items[i];
        NSInteger row=i/cols, col=i%cols;
        UIView *card=[self makeCard];
        card.frame=CGRectMake(m+col*(cw+gap), top+row*(ch+gap), cw, ch);
        UIImageView *iv=[[UIImageView alloc] initWithFrame:CGRectMake(0,0,cw,imgH)];
        iv.contentMode=UIViewContentModeScaleAspectFill; iv.clipsToBounds=YES;
        iv.backgroundColor=[UIColor colorWithWhite:0.08 alpha:1];
        [card addSubview:iv];
        NSString *img = item[@"image_url"] ?: item[@"cover_url"] ?: item[@"poster_url"];
        [self loadImageURL:[self absURL:img base:baseURL] into:iv];
        UILabel *t=[self makeLabel:[RPTheme body:22] color:[RPTheme text]];
        NSString *titleText=[NSString stringWithFormat:@"%@", item[@"title"]?:@""];
        // strip noisy pipes for readability
        if (titleText.length > 0) {
            NSArray *parts = [titleText componentsSeparatedByString:@"|"];
            if (parts.count > 1) titleText = [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        t.text = titleText.length ? titleText : @" ";
        t.frame=CGRectMake(8, imgH+6, cw-16, 48);
        t.numberOfLines = 2;
        [card addSubview:t];
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
@end

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
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    f.dateFormat = @"HH:mm";
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
            weakSelf.assets = filtered;
            if (filtered.count == 0) {
                weakSelf.errorLabel.hidden = NO;
                weakSelf.errorLabel.text = @"相册无照片";
                weakSelf.caption.text = [NSString stringWithFormat:@"%@ · 0 张", weakSelf.albumTitle];
                weakSelf.imageView.image = nil;
                [weakSelf noteImageLoadEnded];
                return;
            }
            weakSelf.errorLabel.hidden = YES;
            weakSelf.caption.text = [NSString stringWithFormat:@"%@ · %lu 张 · 槽 %ld", weakSelf.albumTitle, (unsigned long)filtered.count, (long)(weakSelf.slot+1)];
            if (filtered.count >= 2) {
                weakSelf.assetIndex = (weakSelf.slot == 0) ? 0 : 1;
            } else {
                weakSelf.assetIndex = 0;
            }
            [weakSelf showCurrent];
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
- (NSArray<PHAsset *> *)partitionAssets:(NSArray<PHAsset *> *)assets {
    if (assets.count == 0) return assets;
    NSMutableArray *pref = [NSMutableArray array];
    NSMutableArray *rest = [NSMutableArray array];
    for (PHAsset *a in assets) {
        BOOL portrait = a.pixelHeight >= a.pixelWidth;
        if (self.slot == 0 && portrait) [pref addObject:a];
        else if (self.slot == 1 && !portrait) [pref addObject:a];
        else [rest addObject:a];
    }
    NSArray *pool = pref.count ? pref : assets;
    if (pool.count < 2) {
        return pool.count ? pool : assets;
    }
    NSMutableArray *mine = [NSMutableArray array];
    for (NSUInteger i=0; i<pool.count; i++) {
        if ((NSInteger)(i % 2) == self.slot) [mine addObject:pool[i]];
    }
    if (mine.count == 0) return pool;
    return mine;
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
    // Cap decode size for iPad 3 memory; screen is 1024×768.
    CGFloat scale = MIN(2.0, [UIScreen mainScreen].scale);
    CGSize host = self.contentView.bounds.size;
    CGSize sz = CGSizeMake(MIN(1024.0, MAX(320.0, host.width * scale)),
                           MIN(1024.0, MAX(320.0, host.height * scale)));
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
    self.assetIndex = (self.assetIndex + 1) % self.assets.count;
    self.currentAssetId = nil;
    [self showCurrent];
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

@implementation RPSchedulePageVC
/** Strip HTML / QP leftovers that often show up as “乱码” in calendar notes. */
- (NSString *)cleanCalText:(id)raw {
    if (![raw isKindOfClass:[NSString class]]) return @"";
    NSString *s = (NSString *)raw;
    if ([s isEqualToString:@"(null)"]) return @"";
    // Quoted-printable that leaked through (ICS or mail-sourced notes).
    if ([s rangeOfString:@"="].location != NSNotFound) {
        NSMutableData *bytes = [NSMutableData data];
        const char *utf8 = [s UTF8String];
        if (utf8) {
            for (size_t i = 0; utf8[i]; ) {
                if (utf8[i] == '=' && isxdigit((unsigned char)utf8[i+1]) && isxdigit((unsigned char)utf8[i+2])) {
                    unsigned int b = 0;
                    sscanf(utf8 + i + 1, "%02x", &b);
                    unsigned char c = (unsigned char)b;
                    [bytes appendBytes:&c length:1];
                    i += 3;
                } else if (utf8[i] == '=' && (utf8[i+1] == '\r' || utf8[i+1] == '\n')) {
                    i += (utf8[i+1] == '\r' && utf8[i+2] == '\n') ? 3 : 2;
                } else {
                    [bytes appendBytes:utf8 + i length:1];
                    i += 1;
                }
            }
            NSString *decoded = [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
            if (decoded.length) s = decoded;
        }
    }
    s = [s stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    s = [s stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<" ];
    s = [s stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    s = [s stringByReplacingOccurrencesOfString:@"&nbsp;" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\\n" withString:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\\," withString:@","];
    NSRegularExpression *tags = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>" options:0 error:nil];
    s = [tags stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@" "];
    NSRegularExpression *space = [NSRegularExpression regularExpressionWithPattern:@"[ \\t\\x0B\\f\\r\\n]+" options:0 error:nil];
    s = [space stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@" "];
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}
- (NSString *)lineForItem:(NSDictionary *)item reminder:(BOOL)reminder {
    NSString *when = [self cleanCalText:reminder ? item[@"due"] : item[@"date"]];
    NSString *clock = [self cleanCalText:item[@"time"]];
    NSString *title = [self cleanCalText:item[@"title"]];
    NSString *notes = [self cleanCalText:item[@"notes"]];
    if (title.length == 0) title = reminder ? @"未命名提醒" : @"未命名日程";
    // Cap notes — Exchange/Outlook dumps huge HTML that looks like garbage on a kiosk card.
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
    return @{
        @"title": title.length ? title : @"未命名日程",
        @"date": when ?: @"",
        @"time": clock ?: @"",
        @"notes": [self cleanCalText:ev.notes],
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
            [events addObject:[self eventRow:ev dayFmt:dayFmt timeFmt:timeFmt]];
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
                    if ([rem isKindOfClass:[EKReminder class]]) [rows addObject:[weakSelf reminderRow:rem dayFmt:dayFmt timeFmt:timeFmt]];
                }
                for (EKReminder *rem in doneItems) {
                    if ([rem isKindOfClass:[EKReminder class]]) [rows addObject:[weakSelf reminderRow:rem dayFmt:dayFmt timeFmt:timeFmt]];
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
    NSString *fp = [NSString stringWithFormat:@"sched3|%@|%@|%@|%@|%@|%@|%@|%d|%d",
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
    y = [self addSection:@"今天" items:deviceToday reminder:NO y:y width:w margin:m scroll:scroll];
    y = [self addSection:@"接下来" items:deviceLater reminder:NO y:y width:w margin:m scroll:scroll];
    y = [self addReminderSection:self.deviceReminders y:y width:w margin:m scroll:scroll];
    NSMutableArray *subscribed = [NSMutableArray array];
    [subscribed addObjectsFromArray:feedToday];
    for (id item in feedWeek) {
        if ([item isKindOfClass:[NSDictionary class]]) [subscribed addObject:item];
    }
    for (id item in feedReminders) {
        if ([item isKindOfClass:[NSDictionary class]]) [subscribed addObject:item];
    }
    y = [self addSection:@"订阅" items:subscribed reminder:NO y:y width:w margin:m scroll:scroll];
    if (deviceToday.count == 0 && deviceLater.count == 0 && self.deviceReminders.count == 0 && subscribed.count == 0) {
        UILabel *empty = [self makeLabel:[RPTheme readable:22] color:[RPTheme textDim]];
        empty.numberOfLines = 4;
        empty.text = self.calendarStarted && self.askedEvent
            ? @"系统日历和提醒事项里，这几天还是空的。若刚弹出授权，允许之后会自动出现。"
            : @"正在读取这台 iPad 的日历和提醒事项。";
        empty.frame = CGRectMake(m, y, w, 110);
        [scroll addSubview:empty];
        y += 120;
    }
    scroll.contentSize = CGSizeMake(b.size.width, y + 20);
}
- (CGFloat)addSection:(NSString *)name items:(NSArray *)items reminder:(BOOL)reminder y:(CGFloat)y width:(CGFloat)w margin:(CGFloat)m scroll:(UIScrollView *)scroll {
    if (items.count == 0) return y;
    UILabel *head = [self makeLabel:[RPTheme title:22] color:reminder ? [RPTheme tintOrange] : [RPTheme accent]];
    head.text = name;
    head.frame = CGRectMake(m, y, w, 28);
    [scroll addSubview:head];
    y += 34;
    NSInteger shown = 0;
    for (id raw in items) {
        if (![raw isKindOfClass:[NSDictionary class]] || shown >= 8) break;
        UIView *card = [self makeCardTinted:shown accent:reminder ? [RPTheme tintOrange] : [RPTheme tintTeal]];
        card.frame = CGRectMake(m, y, w, 90);
        // Pixel fonts miss many CJK glyphs used in calendar titles → looks like 乱码/tofu.
        UILabel *lab = [self makeLabel:[RPTheme readable:17] color:[RPTheme text]];
        lab.text = [self lineForItem:raw reminder:reminder];
        lab.frame = CGRectMake(16, 8, w - 28, 74);
        [card addSubview:lab];
        [scroll addSubview:card];
        y += 100;
        shown++;
    }
    return y + 8;
}
- (CGFloat)addReminderSection:(NSArray *)items y:(CGFloat)y width:(CGFloat)w margin:(CGFloat)m scroll:(UIScrollView *)scroll {
    if (items.count == 0) return y;
    UILabel *head = [self makeLabel:[RPTheme title:22] color:[RPTheme tintOrange]];
    head.text = @"提醒事项";
    head.frame = CGRectMake(m, y, w, 28);
    [scroll addSubview:head];
    y += 34;
    NSInteger shown = 0;
    for (NSDictionary *raw in items) {
        if (![raw isKindOfClass:[NSDictionary class]] || shown >= 12) break;
        BOOL done = [raw[@"completed"] boolValue];
        UIView *card = [self makeCardTinted:shown accent:[RPTheme tintOrange]];
        card.frame = CGRectMake(m, y, w, 86);
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
        lab.frame = CGRectMake(64, 8, w - 80, 70);
        [card addSubview:lab];
        [scroll addSubview:card];
        y += 96;
        shown++;
    }
    return y + 8;
}
@end

static NSString *RPGrouped(double n, NSInteger frac) {
    NSNumberFormatter *fmt = [[NSNumberFormatter alloc] init];
    fmt.numberStyle = NSNumberFormatterDecimalStyle;
    fmt.minimumFractionDigits = frac;
    fmt.maximumFractionDigits = frac;
    fmt.usesGroupingSeparator = YES;
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
