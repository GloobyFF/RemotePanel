#import "RPLocalFeed.h"
#import "RPNet.h"
#import <CoreFoundation/CoreFoundation.h>
#import <arpa/inet.h>
#import <ctype.h>
#import <ifaddrs.h>
#import <math.h>
#import <netinet/in.h>
#import <stdio.h>
#import <sys/socket.h>
#import <unistd.h>

NSString * const RPProxyDefaultsKey = @"RemotePanel.httpProxy";
NSString * const RPSourceURLPrefix = @"RemotePanel.source.url.";
NSString * const RPSourceProxyPrefix = @"RemotePanel.source.proxy.";
NSString * const RPVpsURLKey = @"RemotePanel.vpsURL";
NSString * const RPVpsTokenKey = @"RemotePanel.vpsToken";
NSString * const RPVpsProxyKey = @"RemotePanel.vps.useProxy";
NSString * const RPPageEnabledPrefix = @"RemotePanel.page.enabled.";
NSString * const RPRefreshPrefix = @"RemotePanel.refresh.";
NSString * const RPTickerURLKey = @"RemotePanel.tickerURL";
NSString * const RPTickerProxyKey = @"RemotePanel.ticker.useProxy";
NSString * const RPHelloKeyKey = @"RemotePanel.hello.key";
NSString * const RPHelloModelKey = @"RemotePanel.hello.model";
NSString * const RPFeedProgressNotification = @"RPFeedProgress";
NSString * const RPWebPagesDefaultsKey = @"RemotePanel.webPages";

NSString *RPLocalDefaultProxy(void) { return @"socks5h://192.168.28.77:1080"; }

NSString * const RPProxyUserKey = @"RemotePanel.proxy.user";
NSString * const RPProxyPassKey = @"RemotePanel.proxy.pass";

/** Percent-encode a userinfo part so ':' '@' '/' in a password don't break the URL. */
static NSString *RPEscapeUserinfo(NSString *s) {
    // ASCII unreserved only. alphanumericCharacterSet includes Unicode letters, which
    // left Chinese characters unescaped and made NSURL reject the whole proxy URL.
    NSCharacterSet *ok = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [s stringByAddingPercentEncodingWithAllowedCharacters:ok] ?: @"";
}

NSString *RPConfiguredProxy(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *proxy = [[ud stringForKey:RPProxyDefaultsKey] ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (proxy.length == 0) proxy = RPLocalDefaultProxy();
    NSString *user = [[ud stringForKey:RPProxyUserKey] ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *pass = [ud stringForKey:RPProxyPassKey] ?: @"";
    if (user.length == 0) return proxy;
    NSRange scheme = [proxy rangeOfString:@"://"];
    if (scheme.location == NSNotFound) return proxy;
    NSString *rest = [proxy substringFromIndex:NSMaxRange(scheme)];
    // Credentials typed into the URL itself win over the separate fields.
    NSRange slash = [rest rangeOfString:@"/"];
    NSString *authority = slash.location == NSNotFound ? rest : [rest substringToIndex:slash.location];
    if ([authority rangeOfString:@"@"].location != NSNotFound) return proxy;
    return [NSString stringWithFormat:@"%@%@:%@@%@", [proxy substringToIndex:NSMaxRange(scheme)], RPEscapeUserinfo(user), RPEscapeUserinfo(pass), rest];
}
NSString *RPLocalDefaultVPSURL(void) { return @"https://igobeat.com/api/traffic"; }
NSString *RPLocalDefaultVPSToken(void) { return @""; }
NSString *RPLocalDefaultHelloKey(void) { return @""; }
NSString *RPLocalDefaultHelloModel(void) { return @"gpt-6-astra"; }

NSDictionary *RPLocalSourceDefaults(void) {
    return @{
        @"hello": @"https://apiclaude.cc",
        @"weather": @"Shanghai",
        @"daily-news": @"https://www.chinanews.com.cn/rss/scroll-news.xml",
        @"github-news": @"https://api.github.com/search/repositories",
        @"print": @"http://192.168.28.126:8088/api/printers",
        @"movie-now-showing": @"https://m.maoyan.com/ajax/movieOnInfoList",
        @"steam-new-releases": @"https://store.steampowered.com/api/featuredcategories?cc=cn&l=schinese",
        @"steam-new-releases-2": @"https://store.steampowered.com/api/featuredcategories?cc=cn&l=schinese",
        @"gamer520-pc-latest": @"https://www.gamer520.com/pcplay",
        @"gamer520-switch-latest": @"https://www.gamer520.com/gameswitch",
        @"ps5-games-latest": @"https://2468c.com/ps5game",
        @"x-news": @"https://getdaytrends.com/united-states/",
        @"xiaohongshu-hot": @"https://tophub.today/n/L4MdA5ldxD",
        @"bilibili-hot": @"https://api.bilibili.com/x/web-interface/popular?ps=20&pn=1",
        @"stocks-cn": @"600519,300750,600036,601318,002594",
        @"crypto": @"btc,eth,sol,bnb,xrp",
        @"schedule": @"",
    };
}

BOOL RPLocalDefaultUseProxy(NSString *pid) {
    return [@[@"github-news", @"steam-new-releases", @"steam-new-releases-2", @"gamer520-pc-latest", @"gamer520-switch-latest", @"ps5-games-latest", @"x-news", @"xiaohongshu-hot", @"crypto"] containsObject:pid];
}

NSTimeInterval RPLocalDefaultTTL(NSString *feedKey) {
    if ([feedKey isEqualToString:@"print"] || [feedKey isEqualToString:@"ticker"]) return 600;
    if ([feedKey isEqualToString:@"stocks"] || [feedKey isEqualToString:@"crypto"]) return 30 * 60;
    if ([feedKey isEqualToString:@"x"] || [feedKey isEqualToString:@"xhs"] || [feedKey isEqualToString:@"bili"]) return 2 * 3600;
    if ([feedKey isEqualToString:@"weather"]) return 6 * 3600;
    if ([@[@"hello", @"daily"] containsObject:feedKey]) return 12 * 3600;
    return 24 * 3600;
}

NSTimeInterval RPLocalTTL(NSString *feedKey) {
    id saved = [[NSUserDefaults standardUserDefaults] objectForKey:[RPRefreshPrefix stringByAppendingString:feedKey ?: @""]];
    if ([saved isKindOfClass:[NSNumber class]] && [saved doubleValue] >= 60) return [saved doubleValue];
    return RPLocalDefaultTTL(feedKey);
}

NSString *RPLocalFeedKeyForPage(NSString *pid) {
    NSDictionary *map = @{
        @"hello": @"hello",
        @"weather": @"weather",
        @"daily-news": @"daily",
        @"github-news": @"github",
        @"x-news": @"x",
        @"xiaohongshu-hot": @"xhs",
        @"bilibili-hot": @"bili",
        @"stocks-cn": @"stocks",
        @"crypto": @"crypto",
        @"print": @"print",
        @"movie-now-showing": @"movies",
        @"steam-new-releases": @"steam",
        @"steam-new-releases-2": @"steam",
        @"gamer520-pc-latest": @"pc",
        @"gamer520-switch-latest": @"switch",
        @"ps5-games-latest": @"ps5",
        @"schedule": @"schedule",
    };
    return map[pid];
}

NSArray *RPLocalRefreshChoices(void) {
    return @[ @600, @(30 * 60), @3600, @(2 * 3600), @(6 * 3600), @(12 * 3600), @(24 * 3600) ];
}

NSArray *RPLocalRefreshChoiceTitles(void) {
    return @[ @"10分", @"30分", @"1小时", @"2小时", @"6小时", @"12小时", @"24小时" ];
}

NSInteger RPLocalRefreshChoiceIndex(NSTimeInterval ttl) {
    NSArray *choices = RPLocalRefreshChoices();
    NSInteger best = 0;
    double bestDiff = 1e12;
    for (NSInteger i = 0; i < (NSInteger)choices.count; i++) {
        double diff = fabs([choices[i] doubleValue] - ttl);
        if (diff < bestDiff) { bestDiff = diff; best = i; }
    }
    return best;
}

NSString *RPHelloSlot(NSString **labelOut) {
    NSDate *now = [NSDate date];
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDateComponents *parts = [cal components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay|NSCalendarUnitHour fromDate:now];
    NSInteger hour = parts.hour;
    NSString *period = @"evening";
    NSString *label = @"晚上好";
    NSDate *day = now;
    if (hour >= 5 && hour < 11) {
        period = @"morning";
        label = @"早上好";
    } else if (hour >= 11 && hour < 17) {
        period = @"noon";
        label = @"中午好";
    } else if (hour < 5) {
        day = [cal dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:now options:0] ?: now;
    }
    NSDateComponents *d = [cal components:NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay fromDate:day];
    if (labelOut) *labelOut = label;
    return [NSString stringWithFormat:@"%04ld-%02ld-%02ld-%@", (long)d.year, (long)d.month, (long)d.day, period];
}

NSArray *RPLocalPageCatalog(void) {
    return @[
        @{@"id": @"hello", @"title": @"问候海报", @"dwell": @60, @"hint": @"AI 接口地址", @"refresh_period": @YES},
        @{@"id": @"schedule", @"title": @"日程与提醒", @"dwell": @60, @"hint": @"ICS 订阅地址，留空则不拉日程"},
        @{@"id": @"weather", @"title": @"天气+VPS", @"dwell": @70, @"hint": @"城市名，例如 Shanghai"},
        @{@"id": @"daily-news", @"title": @"每日新闻", @"dwell": @70, @"hint": @"新闻 RSS"},
        @{@"id": @"github-news", @"title": @"AI·热门项目", @"dwell": @70, @"hint": @"GitHub 接口或 RSS"},
        @{@"id": @"x-news", @"title": @"X · 动态", @"dwell": @60, @"hint": @"默认美国区热门，译成中文。也可换成 RSS"},
        @{@"id": @"xiaohongshu-hot", @"title": @"小红书热门", @"dwell": @60, @"hint": @"小红书热榜页面"},
        @{@"id": @"bilibili-hot", @"title": @"哔哩哔哩热门", @"dwell": @60, @"hint": @"哔哩哔哩热门接口"},
        @{@"id": @"stocks-cn", @"title": @"国内股票", @"dwell": @70, @"hint": @"股票代码，逗号分隔，如 600519,300750"},
        @{@"id": @"crypto", @"title": @"比特币", @"dwell": @70, @"hint": @"币种，逗号分隔，如 btc,eth,sol"},
        @{@"id": @"person-photo-local-1", @"title": @"本地相册 A", @"dwell": @60},
        @{@"id": @"print", @"title": @"打印机", @"dwell": @75, @"hint": @"打印机 JSON 接口"},
        @{@"id": @"movie-now-showing", @"title": @"最近上映", @"dwell": @35, @"hint": @"电影接口"},
        @{@"id": @"steam-new-releases", @"title": @"Steam 新游", @"dwell": @60, @"hint": @"Steam 接口"},
        @{@"id": @"steam-new-releases-2", @"title": @"Steam 热销", @"dwell": @60, @"hint": @"与 Steam 新游共用接口", @"refresh_shared": @YES},
        @{@"id": @"gamer520-pc-latest", @"title": @"PC 游戏上新", @"dwell": @60, @"hint": @"PC 游戏页面"},
        @{@"id": @"person-photo-local-2", @"title": @"本地相册 B", @"dwell": @60},
        @{@"id": @"gamer520-switch-latest", @"title": @"Switch 上新", @"dwell": @60, @"hint": @"Switch 游戏页面"},
        @{@"id": @"ps5-games-latest", @"title": @"PS5 上新", @"dwell": @60, @"hint": @"PS5 游戏页面"},
        // Two video boards. Both play one random clip muted, then turn the page.
        @{@"id": @"local-video", @"title": @"相册视频", @"dwell": @12, @"hint": @"播放相册里的视频（或用浏览器上传到 iPad 的视频）。播完再翻页；这里的秒数只在没有视频时使用。", @"default_off": @YES},
        @{@"id": @"net-video", @"title": @"网络视频", @"dwell": @12, @"hint": @"播放 HTTP / WebDAV 目录里的视频（mp4、mov、m4v）。播完再翻页。", @"default_off": @YES},
    ];
}

BOOL RPLocalPageDefaultOn(NSString *pid) {
    for (NSDictionary *meta in RPLocalPageCatalog()) {
        if ([meta[@"id"] isEqualToString:pid]) return ![meta[@"default_off"] boolValue];
    }
    return YES;
}

static NSString * const RPVideoSourceKey = @"RemotePanel.video.source";
static NSString * const RPVideoAlbumKey = @"RemotePanel.video.albumId";
static NSString * const RPVideoHTTPKey = @"RemotePanel.video.http";
static NSString * const RPVideoMaxKey = @"RemotePanel.video.maxMinutes";

NSString *RPVideoDirectory(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [docs stringByAppendingPathComponent:@"Videos"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir ?: @"";
}

static NSString *RPVideoSafeName(NSString *raw) {
    NSString *base = [[raw ?: @"" lastPathComponent] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (base.length < 5 || base.length > 120) return @"";
    if ([base rangeOfString:@"/"].location != NSNotFound || [base rangeOfString:@".."].location != NSNotFound) return @"";
    NSString *ext = base.pathExtension.lowercaseString;
    if (![@[@"mp4", @"mov", @"m4v"] containsObject:ext]) return @"";
    return base;
}

NSArray *RPVideoLocalFiles(void) {
    NSString *dir = RPVideoDirectory();
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil] ?: @[];
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *name in names) {
        if ([name hasSuffix:@".part"]) continue;
        if (RPVideoSafeName(name).length == 0) continue;
        [files addObject:[dir stringByAppendingPathComponent:name]];
    }
    [files sortUsingSelector:@selector(compare:)];
    return files;
}

static NSString *RPString(id value) {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

NSString * const RPVideoMutedKey = @"RemotePanel.video.muted";
NSString * const RPVideoHTTPUserKey = @"RemotePanel.video.httpUser";
NSString * const RPVideoHTTPPassKey = @"RemotePanel.video.httpPass";

NSDictionary *RPVideoSettings(void) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *src = RPString([ud stringForKey:RPVideoSourceKey]);
    if (![@[@"album", @"files", @"http"] containsObject:src]) src = @"album";
    NSInteger mins = [ud integerForKey:RPVideoMaxKey];
    if (mins < 0) mins = 0;
    if (mins > 180) mins = 180;
    id muted = [ud objectForKey:RPVideoMutedKey];
    return @{
        // "source" is kept for the old single 视频 page / browser settings; the
        // 相册视频 page plays album (or uploaded files), 网络视频 plays "http".
        @"source": src,
        @"album": RPString([ud stringForKey:RPVideoAlbumKey]),
        @"http": RPString([ud stringForKey:RPVideoHTTPKey]),
        @"http_user": RPString([ud stringForKey:RPVideoHTTPUserKey]),
        @"http_pass": [ud stringForKey:RPVideoHTTPPassKey] ?: @"",
        @"max": @(mins),
        // Muted unless the owner turned sound on.
        @"muted": @(muted ? [muted boolValue] : YES),
        @"photo_album": RPString([ud stringForKey:@"RemotePanel.albumLocalId"]),
    };
}

void RPVideoSetMuted(BOOL muted) {
    [[NSUserDefaults standardUserDefaults] setBool:muted forKey:RPVideoMutedKey];
}

void RPVideoSaveNetwork(NSString *url, NSString *user, NSString *pass) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setObject:url ?: @"" forKey:RPVideoHTTPKey];
    [ud setObject:user ?: @"" forKey:RPVideoHTTPUserKey];
    if (pass) [ud setObject:pass forKey:RPVideoHTTPPassKey];
}

void RPVideoSaveAlbum(NSString *albumId) {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (albumId.length) [ud setObject:albumId forKey:RPVideoAlbumKey];
    else [ud removeObjectForKey:RPVideoAlbumKey];
}

void RPVideoSaveMaxMinutes(NSInteger mins) {
    [[NSUserDefaults standardUserDefaults] setInteger:MAX(0, MIN(180, mins)) forKey:RPVideoMaxKey];
}

NSUInteger RPWebPagesMaxCount(void) { return 8; }

NSString *RPWebPagesMakeId(void) {
    return [NSString stringWithFormat:@"web-%ld", (long)llround([[NSDate date] timeIntervalSince1970] * 1000.0)];
}

NSMutableDictionary *RPWebPageNormalize(NSDictionary *raw, NSInteger indexHint) {
    NSMutableDictionary *page = [NSMutableDictionary dictionary];
    NSString *pid = RPString(raw[@"id"]);
    if (![pid hasPrefix:@"web-"]) pid = RPWebPagesMakeId();
    NSString *title = RPString(raw[@"title"]);
    if (title.length == 0) title = [NSString stringWithFormat:@"网页 %ld", (long)MAX(1, indexHint + 1)];
    NSString *url = RPString(raw[@"url"]);
    if ([url hasPrefix:@"webcal://"]) url = [@"https://" stringByAppendingString:[url substringFromIndex:9]];
    NSInteger dwell = [raw[@"dwell"] respondsToSelector:@selector(integerValue)] ? [raw[@"dwell"] integerValue] : 60;
    if (dwell <= 0) dwell = 60;
    if (dwell < 8) dwell = 8;
    if (dwell > 3600) dwell = 3600;
    BOOL enabled = [raw[@"enabled"] respondsToSelector:@selector(boolValue)] ? [raw[@"enabled"] boolValue] : NO;
    if (url.length == 0) enabled = NO;
    page[@"id"] = pid;
    page[@"title"] = title;
    page[@"url"] = url;
    page[@"dwell"] = @(dwell);
    page[@"enabled"] = @(enabled);
    return page;
}

NSArray *RPWebPagesLoad(void) {
    id raw = [[NSUserDefaults standardUserDefaults] objectForKey:RPWebPagesDefaultsKey];
    if (![raw isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *out = [NSMutableArray array];
    NSInteger i = 0;
    for (id item in (NSArray *)raw) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        [out addObject:RPWebPageNormalize(item, i)];
        if (out.count >= RPWebPagesMaxCount()) break;
        i++;
    }
    return out;
}

void RPWebPagesSave(NSArray *pages) {
    NSMutableArray *out = [NSMutableArray array];
    NSInteger i = 0;
    for (id item in pages ?: @[]) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        [out addObject:RPWebPageNormalize(item, i)];
        if (out.count >= RPWebPagesMaxCount()) break;
        i++;
    }
    [[NSUserDefaults standardUserDefaults] setObject:out forKey:RPWebPagesDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

NSDictionary *RPWebPageFind(NSString *pageId) {
    if (pageId.length == 0) return nil;
    for (NSDictionary *page in RPWebPagesLoad()) {
        if ([page[@"id"] isEqualToString:pageId]) return page;
    }
    return nil;
}

static NSString *RPDecode(NSString *text) {
    if (![text isKindOfClass:[NSString class]]) return @"";
    NSString *s = text;
    s = [s stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    s = [s stringByReplacingOccurrencesOfString:@"&lt;" withString:@"<"];
    s = [s stringByReplacingOccurrencesOfString:@"&gt;" withString:@">"];
    s = [s stringByReplacingOccurrencesOfString:@"&quot;" withString:@"\""];
    s = [s stringByReplacingOccurrencesOfString:@"&#39;" withString:@"'"];
    s = [s stringByReplacingOccurrencesOfString:@"&nbsp;" withString:@" "];
    NSRegularExpression *tags = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>" options:0 error:nil];
    s = [tags stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@" "];
    s = [s stringByReplacingOccurrencesOfString:@"\\n" withString:@" "];
    NSRegularExpression *space = [NSRegularExpression regularExpressionWithPattern:@"\\s+" options:0 error:nil];
    s = [space stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@" "];
    return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *RPSliceTag(NSString *xml, NSString *tag) {
    if (xml.length == 0 || tag.length == 0) return @"";
    NSString *open = [NSString stringWithFormat:@"<%@", tag];
    NSRange start = [xml rangeOfString:open options:NSCaseInsensitiveSearch];
    if (start.location == NSNotFound) return @"";
    NSRange gt = [xml rangeOfString:@">" options:0 range:NSMakeRange(start.location, xml.length - start.location)];
    if (gt.location == NSNotFound) return @"";
    NSString *close = [NSString stringWithFormat:@"</%@>", tag];
    NSRange end = [xml rangeOfString:close options:NSCaseInsensitiveSearch range:NSMakeRange(NSMaxRange(gt), xml.length - NSMaxRange(gt))];
    if (end.location == NSNotFound) return @"";
    NSString *body = [xml substringWithRange:NSMakeRange(NSMaxRange(gt), end.location - NSMaxRange(gt))];
    if ([body hasPrefix:@"<![CDATA["]) {
        body = [body substringFromIndex:9];
        if ([body hasSuffix:@"]]>"]) body = [body substringToIndex:body.length - 3];
    }
    return body;
}

static NSArray *RPParseRSS(NSData *data, NSInteger limit) {
    NSString *xml = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!xml) xml = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!xml) return @[];
    NSMutableArray *items = [NSMutableArray array];
    NSString *lower = xml;
    NSUInteger cursor = 0;
    while (items.count < limit && cursor < lower.length) {
        NSRange found = [lower rangeOfString:@"<item" options:NSCaseInsensitiveSearch range:NSMakeRange(cursor, lower.length - cursor)];
        if (found.location == NSNotFound) {
            found = [lower rangeOfString:@"<entry" options:NSCaseInsensitiveSearch range:NSMakeRange(cursor, lower.length - cursor)];
        }
        if (found.location == NSNotFound) break;
        NSString *endTag = [[lower substringWithRange:found] hasPrefix:@"<entry"] || [[xml substringWithRange:found] hasPrefix:@"<entry"] ? @"</entry>" : @"</item>";
        NSRange end = [lower rangeOfString:endTag options:NSCaseInsensitiveSearch range:NSMakeRange(found.location, lower.length - found.location)];
        if (end.location == NSNotFound) break;
        NSString *block = [xml substringWithRange:NSMakeRange(found.location, NSMaxRange(end) - found.location)];
        NSString *title = RPDecode(RPSliceTag(block, @"title"));
        NSString *summary = RPDecode(RPSliceTag(block, @"description"));
        if (summary.length == 0) summary = RPDecode(RPSliceTag(block, @"summary"));
        NSString *link = RPString(RPSliceTag(block, @"link"));
        if ([link rangeOfString:@"<"].location != NSNotFound) link = @"";
        if (link.length == 0) {
            NSRegularExpression *href = [NSRegularExpression regularExpressionWithPattern:@"<link[^>]+href=\"([^\"]+)\"" options:NSRegularExpressionCaseInsensitive error:nil];
            NSTextCheckingResult *m = [href firstMatchInString:block options:0 range:NSMakeRange(0, block.length)];
            if (m.numberOfRanges > 1) link = [block substringWithRange:[m rangeAtIndex:1]];
        }
        NSString *image = @"";
        NSRegularExpression *enc = [NSRegularExpression regularExpressionWithPattern:@"<(?:enclosure|media:content|media:thumbnail)[^>]+url=\"([^\"]+)\"" options:NSRegularExpressionCaseInsensitive error:nil];
        NSTextCheckingResult *im = [enc firstMatchInString:block options:0 range:NSMakeRange(0, block.length)];
        if (im.numberOfRanges > 1) image = [block substringWithRange:[im rangeAtIndex:1]];
        if (title.length) {
            [items addObject:@{ @"title": title, @"summary": summary ?: @"", @"link": link ?: @"", @"image_url": image ?: @"" }];
        }
        cursor = NSMaxRange(end);
    }
    return items;
}

static NSString *RPWeatherText(NSInteger code) {
    switch (code) {
        case 0: return @"晴";
        case 1: return @"大部晴";
        case 2: return @"局部多云";
        case 3: return @"阴";
        case 45: case 48: return @"雾";
        case 51: case 53: case 55: return @"毛毛雨";
        case 61: return @"小雨";
        case 63: return @"雨";
        case 65: return @"大雨";
        case 71: return @"小雪";
        case 73: return @"雪";
        case 75: return @"大雪";
        case 80: case 81: return @"阵雨";
        case 82: return @"强阵雨";
        case 95: case 96: case 99: return @"雷暴";
        default: return @"天气";
    }
}

static NSString *RPWeatherIcon(NSString *desc) {
    NSString *d = desc ?: @"";
    if ([d rangeOfString:@"雷"].location != NSNotFound) return @"\uf01e";
    if ([d rangeOfString:@"大雨"].location != NSNotFound || [d rangeOfString:@"暴雨"].location != NSNotFound) return @"\uf019";
    if ([d rangeOfString:@"阵雨"].location != NSNotFound) return @"\uf01a";
    if ([d rangeOfString:@"雨"].location != NSNotFound) return @"\uf008";
    if ([d rangeOfString:@"雪"].location != NSNotFound) return @"\uf01b";
    if ([d rangeOfString:@"雾"].location != NSNotFound) return @"\uf014";
    if ([d rangeOfString:@"阴"].location != NSNotFound || [d rangeOfString:@"云"].location != NSNotFound) return @"\uf041";
    if ([d rangeOfString:@"晴"].location != NSNotFound) return @"\uf00d";
    return @"\uf041";
}

static NSString *RPWeekday(NSString *iso) {
    NSDateFormatter *inFmt = [[NSDateFormatter alloc] init];
    inFmt.dateFormat = @"yyyy-MM-dd";
    inFmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSDate *date = [inFmt dateFromString:iso ?: @""];
    if (!date) return iso ?: @"";
    NSDateFormatter *out = [[NSDateFormatter alloc] init];
    out.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    out.dateFormat = @"EEE";
    return [out stringFromDate:date] ?: iso;
}

static NSArray *RPParseListing(NSData *data, NSString *pageURL, NSInteger limit) {
    NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!html) return @[];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<h2[^>]*class=\"[^\"]*entry-title[^\"]*\"[^>]*>\\s*<a[^>]+href=\"([^\"]+)\"[^>]*>([\\s\\S]*?)</a>" options:NSRegularExpressionCaseInsensitive error:nil];
    NSArray *matches = [re matchesInString:html options:0 range:NSMakeRange(0, html.length)];
    NSMutableArray *items = [NSMutableArray array];
    NSURL *base = [NSURL URLWithString:pageURL];
    for (NSTextCheckingResult *m in matches) {
        if (m.numberOfRanges < 3) continue;
        NSString *href = [html substringWithRange:[m rangeAtIndex:1]];
        NSString *title = RPDecode([html substringWithRange:[m rangeAtIndex:2]]);
        if (title.length == 0) continue;
        NSString *abs = href;
        NSURL *resolved = [NSURL URLWithString:href relativeToURL:base];
        if (resolved.absoluteString.length) abs = resolved.absoluteString;
        NSUInteger begin = m.range.location > 900 ? m.range.location - 900 : 0;
        NSUInteger end = MIN(html.length, NSMaxRange(m.range) + 400);
        NSString *chunk = [html substringWithRange:NSMakeRange(begin, end - begin)];
        NSRegularExpression *realImg = [NSRegularExpression regularExpressionWithPattern:@"(?:data-src|data-original|src)=\"(https?://[^\"]+)\"" options:NSRegularExpressionCaseInsensitive error:nil];
        NSArray *imgs = [realImg matchesInString:chunk options:0 range:NSMakeRange(0, chunk.length)];
        NSString *image = @"";
        NSInteger bestDist = NSIntegerMax;
        NSInteger titleAt = (NSInteger)m.range.location - (NSInteger)begin;
        for (NSTextCheckingResult *im in imgs) {
            if (im.numberOfRanges < 2) continue;
            NSString *src = [chunk substringWithRange:[im rangeAtIndex:1]];
            if ([src rangeOfString:@"logo" options:NSCaseInsensitiveSearch].location != NSNotFound) continue;
            NSInteger dist = labs((NSInteger)im.range.location - titleAt);
            if (dist < bestDist) { bestDist = dist; image = src; }
        }
        if (image.length) {
            NSURL *imgURL = [NSURL URLWithString:image relativeToURL:base];
            image = imgURL.absoluteString ?: image;
        }
        [items addObject:@{ @"title": title, @"link": abs ?: @"", @"image_url": image ?: @"" }];
        if ((NSInteger)items.count >= limit) break;
    }
    return items;
}

static NSArray *RPMoviesFromMaoyan(NSData *data, NSInteger limit) {
    id json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:nil];
    NSArray *list = [json isKindOfClass:[NSDictionary class]] ? json[@"movieList"] : nil;
    if (![list isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *movie in list) {
        if (![movie isKindOfClass:[NSDictionary class]]) continue;
        NSString *title = RPString(movie[@"nm"]);
        if (title.length == 0) continue;
        [items addObject:@{
            @"title": title,
            @"release_date": RPString(movie[@"rt"]),
            @"overview": RPString(movie[@"star"]),
            @"poster_url": RPString(movie[@"img"]),
        }];
        if ((NSInteger)items.count >= limit) break;
    }
    return items;
}

static NSArray *RPParseMovies(NSData *data, NSInteger limit) {
    NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!html) return @[];
    NSMutableArray *items = [NSMutableArray array];
    NSRegularExpression *script = [NSRegularExpression regularExpressionWithPattern:@"<script type=\"application/ld\\+json\">(.*?)</script>" options:NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators error:nil];
    NSArray *blocks = [script matchesInString:html options:0 range:NSMakeRange(0, html.length)];
    for (NSTextCheckingResult *m in blocks) {
        if (m.numberOfRanges < 2) continue;
        NSData *raw = [[html substringWithRange:[m rangeAtIndex:1]] dataUsingEncoding:NSUTF8StringEncoding];
        id json = [NSJSONSerialization JSONObjectWithData:raw options:0 error:nil];
        NSArray *list = [json isKindOfClass:[NSArray class]] ? json : ([json isKindOfClass:[NSDictionary class]] ? @[json] : @[]);
        for (NSDictionary *entry in list) {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            if (![[NSString stringWithFormat:@"%@", entry[@"@type"] ?: @""].lowercaseString isEqualToString:@"movie"]) continue;
            NSString *title = RPString(entry[@"name"]);
            if (title.length == 0) continue;
            id image = entry[@"image"];
            NSString *poster = [image isKindOfClass:[NSString class]] ? image : ([image isKindOfClass:[NSArray class]] ? [image firstObject] : @"");
            if (![poster isKindOfClass:[NSString class]]) poster = @"";
            [items addObject:@{
                @"title": title,
                @"release_date": RPString(entry[@"dateCreated"] ?: entry[@"datePublished"]),
                @"overview": RPDecode([NSString stringWithFormat:@"%@", entry[@"description"] ?: @""]),
                @"poster_url": poster,
            }];
            if ((NSInteger)items.count >= limit) return items;
        }
    }
    return items;
}

static NSStringEncoding RPICSEncodingNamed(NSString *charset) {
    NSString *n = [(charset ?: @"") lowercaseString];
    if ([n rangeOfString:@"gb18030"].location != NSNotFound || [n rangeOfString:@"gbk"].location != NSNotFound ||
        [n rangeOfString:@"gb2312"].location != NSNotFound || [n rangeOfString:@"cp936"].location != NSNotFound) {
        return CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    }
    if ([n rangeOfString:@"utf-8"].location != NSNotFound || [n rangeOfString:@"utf8"].location != NSNotFound) {
        return NSUTF8StringEncoding;
    }
    return NSUTF8StringEncoding;
}

static NSString *RPICSDataToString(NSData *data) {
    if (data.length == 0) return @"";
    const unsigned char *b = data.bytes;
    NSUInteger off = 0;
    if (data.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) off = 3;
    NSData *body = off ? [data subdataWithRange:NSMakeRange(off, data.length - off)] : data;
    NSString *utf8 = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
    if (utf8.length) return utf8;
    NSStringEncoding gb = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    NSString *gbStr = [[NSString alloc] initWithData:body encoding:gb];
    if (gbStr.length) return gbStr;
    return [[NSString alloc] initWithData:body encoding:NSISOLatin1StringEncoding] ?: @"";
}

static NSString *RPICSDecodeQP(NSString *value, NSStringEncoding enc) {
    if (value.length == 0) return @"";
    NSString *s = [value stringByReplacingOccurrencesOfString:@"=\r\n" withString:@""];
    s = [s stringByReplacingOccurrencesOfString:@"=\n" withString:@""];
    NSMutableData *bytes = [NSMutableData dataWithCapacity:s.length];
    const char *utf8 = [s UTF8String];
    if (!utf8) return value;
    for (size_t i = 0; utf8[i]; ) {
        if (utf8[i] == '=' && isxdigit((unsigned char)utf8[i + 1]) && isxdigit((unsigned char)utf8[i + 2])) {
            unsigned int b = 0;
            sscanf(utf8 + i + 1, "%02x", &b);
            unsigned char c = (unsigned char)b;
            [bytes appendBytes:&c length:1];
            i += 3;
        } else {
            [bytes appendBytes:utf8 + i length:1];
            i += 1;
        }
    }
    NSString *out = [[NSString alloc] initWithData:bytes encoding:enc];
    if (!out && enc != NSUTF8StringEncoding) out = [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
    return out.length ? out : value;
}

static NSString *RPICSUnescape(NSString *value) {
    if (value.length == 0) return @"";
    NSString *s = value;
    s = [s stringByReplacingOccurrencesOfString:@"\\n" withString:@"\n"];
    s = [s stringByReplacingOccurrencesOfString:@"\\N" withString:@"\n"];
    s = [s stringByReplacingOccurrencesOfString:@"\\," withString:@","];
    s = [s stringByReplacingOccurrencesOfString:@"\\;" withString:@";"];
    s = [s stringByReplacingOccurrencesOfString:@"\\\\" withString:@"\\"];
    return s;
}

/** Parse one ICS content line into key / params / value; decode CHARSET + QUOTED-PRINTABLE. */
static void RPICSParseLine(NSString *line, NSString **outKey, NSString **outValue) {
    *outKey = nil; *outValue = nil;
    NSRange colon = [line rangeOfString:@":"];
    if (colon.location == NSNotFound) return;
    NSArray *parts = [[line substringToIndex:colon.location] componentsSeparatedByString:@";"];
    NSString *key = [parts.firstObject uppercaseString];
    NSString *value = [line substringFromIndex:NSMaxRange(colon)];
    NSStringEncoding enc = NSUTF8StringEncoding;
    BOOL qp = NO;
    for (NSUInteger i = 1; i < parts.count; i++) {
        NSString *p = parts[i];
        NSRange eq = [p rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;
        NSString *pk = [[p substringToIndex:eq.location] uppercaseString];
        NSString *pv = [[p substringFromIndex:NSMaxRange(eq)] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
        if ([pk isEqualToString:@"CHARSET"]) enc = RPICSEncodingNamed(pv);
        if ([pk isEqualToString:@"ENCODING"] && [[pv uppercaseString] rangeOfString:@"QUOTED-PRINTABLE"].location != NSNotFound) qp = YES;
    }
    if (qp) value = RPICSDecodeQP(value, enc);
    else if (enc != NSUTF8StringEncoding) {
        // Some exporters put GBK bytes into a mislabeled UTF-8 transport; try re-decode from latin1 bridge.
        NSData *raw = [value dataUsingEncoding:NSISOLatin1StringEncoding];
        NSString *re = raw ? [[NSString alloc] initWithData:raw encoding:enc] : nil;
        if (re.length) value = re;
    }
    *outKey = key;
    *outValue = RPICSUnescape(value);
}

static NSDictionary *RPParseICS(NSData *data) {
    NSString *text = RPICSDataToString(data);
    // RFC 5545 line unfolding (space or tab continuation).
    text = [text stringByReplacingOccurrencesOfString:@"\r\n " withString:@""];
    text = [text stringByReplacingOccurrencesOfString:@"\r\n\t" withString:@""];
    text = [text stringByReplacingOccurrencesOfString:@"\n " withString:@""];
    text = [text stringByReplacingOccurrencesOfString:@"\n\t" withString:@""];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd";
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSString *today = [fmt stringFromDate:[NSDate date]];
    NSMutableArray *events = [NSMutableArray array];
    NSMutableArray *todos = [NSMutableArray array];
    NSString *kind = @"";
    NSMutableDictionary *cur = nil;
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\r"]];
        if ([line isEqualToString:@"BEGIN:VEVENT"]) { kind = @"event"; cur = [NSMutableDictionary dictionary]; continue; }
        if ([line isEqualToString:@"BEGIN:VTODO"]) { kind = @"todo"; cur = [NSMutableDictionary dictionary]; continue; }
        if ([line isEqualToString:@"END:VEVENT"] || [line isEqualToString:@"END:VTODO"]) {
            if ([kind isEqualToString:@"event"]) [events addObject:cur ?: @{}];
            if ([kind isEqualToString:@"todo"]) [todos addObject:cur ?: @{}];
            kind = @""; cur = nil; continue;
        }
        if (!cur) continue;
        NSString *key = nil, *value = nil;
        RPICSParseLine(line, &key, &value);
        if (key.length == 0) continue;
        cur[key] = value ?: @"";
    }
    NSMutableArray *upcoming = [NSMutableArray array];
    NSDateFormatter *utc = [[NSDateFormatter alloc] init];
    utc.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    utc.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    utc.dateFormat = @"yyyyMMddHHmm";
    NSDateFormatter *localDay = [[NSDateFormatter alloc] init];
    localDay.locale = utc.locale;
    localDay.dateFormat = @"yyyyMMdd";
    NSDateFormatter *localClock = [[NSDateFormatter alloc] init];
    localClock.locale = utc.locale;
    localClock.dateFormat = @"HH:mm";
    for (NSDictionary *ev in events) {
        NSString *title = RPDecode([RPString(ev[@"SUMMARY"]) stringByReplacingOccurrencesOfString:@"\n" withString:@" "]);
        NSString *start = RPString(ev[@"DTSTART"]);
        NSString *day = @"";
        NSString *clock = @"";
        if ([start rangeOfString:@"T"].location != NSNotFound) {
            NSArray *parts = [start componentsSeparatedByString:@"T"];
            day = parts.firstObject;
            NSString *tim = parts.lastObject;
            if ([tim hasSuffix:@"Z"] && day.length >= 8 && tim.length >= 5) {
                // Google Calendar exports UTC times ("…T013000Z"); show them in local time.
                NSDate *at = [utc dateFromString:[[day substringToIndex:8] stringByAppendingString:[tim substringToIndex:4]]];
                if (at) {
                    day = [localDay stringFromDate:at];
                    clock = [localClock stringFromDate:at];
                }
            } else if (tim.length >= 4) {
                clock = [NSString stringWithFormat:@"%@:%@", [tim substringToIndex:2], [tim substringWithRange:NSMakeRange(2, 2)]];
            }
        } else {
            day = start;
        }
        NSString *digits = [[day componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
        if (digits.length < 8) continue;
        NSString *iso = [NSString stringWithFormat:@"%@-%@-%@", [digits substringToIndex:4], [digits substringWithRange:NSMakeRange(4, 2)], [digits substringWithRange:NSMakeRange(6, 2)]];
        if ([iso compare:today] == NSOrderedAscending) continue;
        NSString *uid = RPString(ev[@"UID"]);
        [upcoming addObject:@{ @"date": iso, @"time": clock, @"title": title.length ? title : @"未命名日程", @"notes": RPDecode(RPString(ev[@"DESCRIPTION"])), @"id": uid.length ? uid : title }];
    }
    // ICS files are not in date order: sort everything first, then keep the nearest 18.
    [upcoming sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult byDay = [a[@"date"] compare:b[@"date"]];
        if (byDay != NSOrderedSame) return byDay;
        // All-day items (no time) first within a day.
        return [a[@"time"] compare:b[@"time"]];
    }];
    if (upcoming.count > 18) [upcoming removeObjectsInRange:NSMakeRange(18, upcoming.count - 18)];
    NSMutableArray *todayItems = [NSMutableArray array];
    for (NSDictionary *item in upcoming) if ([item[@"date"] isEqualToString:today]) [todayItems addObject:item];
    NSMutableArray *reminders = [NSMutableArray array];
    for (NSDictionary *todo in todos) {
        NSString *status = [RPString(todo[@"STATUS"]) uppercaseString];
        if ([status isEqualToString:@"COMPLETED"] || [status isEqualToString:@"CANCELLED"]) continue;
        NSString *title = RPDecode(todo[@"SUMMARY"] ?: @"");
        if (title.length == 0) continue;
        [reminders addObject:@{ @"title": title, @"due": @"", @"time": @"", @"notes": RPDecode(todo[@"DESCRIPTION"] ?: @"") }];
        if (reminders.count >= 12) break;
    }
    return @{ @"today": todayItems, @"week": upcoming, @"reminders": reminders, @"sync_error": @"" };
}

static NSString *RPCountText(id value) {
    double n = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0;
    if (n >= 100000000) return [NSString stringWithFormat:@"%.1f亿", n / 100000000.0];
    if (n >= 10000) return [NSString stringWithFormat:@"%.1f万", n / 10000.0];
    if (n <= 0) return @"";
    return [NSString stringWithFormat:@"%.0f", n];
}

static double RPDouble(id value);

static NSInteger RPTitleOverlap(NSString *query, NSString *title) {
    if (query.length == 0 || title.length == 0) return 0;
    NSInteger n = 0;
    for (NSUInteger i = 0; i < query.length; i++) {
        NSString *ch = [query substringWithRange:NSMakeRange(i, 1)];
        if ([title rangeOfString:ch].location != NSNotFound) n++;
    }
    return n;
}

static NSString *RPBestTopicImage(NSData *data, NSString *query) {
    id json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:nil];
    NSArray *list = [json isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)json)[@"list"] : nil;
    if (![list isKindOfClass:[NSArray class]]) return @"";
    NSString *best = @"";
    NSInteger bestScore = 4;
    double bestArea = 0;
    for (NSDictionary *row in list) {
        if (![row isKindOfClass:[NSDictionary class]]) continue;
        NSString *title = RPString(row[@"title"]);
        if (query.length && [title isEqualToString:query]) continue;
        NSString *thumb = RPString(row[@"thumb"] ?: row[@"_thumb"]);
        if ([thumb hasPrefix:@"http://"]) thumb = [@"https://" stringByAppendingString:[thumb substringFromIndex:7]];
        if (![thumb hasPrefix:@"https://"]) continue;
        double w = RPDouble(row[@"width"]);
        double h = RPDouble(row[@"height"]);
        if (w > 0 && h > 0 && (w < 360 || h < 220)) continue;
        NSInteger score = RPTitleOverlap(query, title);
        double area = w * h;
        if (score > bestScore || (score == bestScore && area > bestArea)) {
            bestScore = score;
            bestArea = area;
            best = thumb;
        }
    }
    return best;
}

static double RPHeatValue(NSString *heat);
static NSArray *RPParseXiaohongshu(NSData *data, NSInteger limit) {
    NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!html) return @[];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"<td align=\"center\">\\s*(\\d+)\\.\\s*</td>\\s*<td>\\s*<a href=\"([^\"]+)\"[^>]*>([^<]+)</a></td>\\s*<td class=\"ws\">([^<]*)</td>" options:NSRegularExpressionCaseInsensitive error:nil];
    NSArray *matches = [re matchesInString:html options:0 range:NSMakeRange(0, html.length)];
    NSMutableArray *items = [NSMutableArray array];
    for (NSTextCheckingResult *m in matches) {
        if (m.numberOfRanges < 5) continue;
        NSString *title = RPDecode([html substringWithRange:[m rangeAtIndex:3]]);
        if (title.length == 0) continue;
        NSString *heat = RPDecode([html substringWithRange:[m rangeAtIndex:4]]);
        NSString *link = [html substringWithRange:[m rangeAtIndex:2]];
        [items addObject:@{
            @"title": title,
            @"heat": heat ?: @"",
            @"heat_value": @(RPHeatValue(heat)),
            @"summary": heat.length ? [NSString stringWithFormat:@"热度 %@", heat] : @"小红书热榜",
            @"link": link ?: @"",
            @"image_url": @"",
        }];
        if ((NSInteger)items.count >= limit) break;
    }
    return items;
}

/** "918.6w" / "1.2万" / "3456" → number, for the heat bars. */
static double RPHeatValue(NSString *heat) {
    NSString *s = [[heat ?: @"" lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    double n = [s doubleValue];
    if ([s hasSuffix:@"w"] || [s hasSuffix:@"万"]) n *= 10000;
    else if ([s hasSuffix:@"亿"]) n *= 100000000;
    return n;
}

/* tophub.today node page, current markup:
   <a class="rank-item-container" href="…search_result?keyword=…">
     <div class="number …">1</div> … <div class="s-title">标题</div>
     … <div class="s-tie-count">918.6w</div> … url('…') … </a> */
static NSArray *RPParseTophubCards(NSData *data, NSInteger limit) {
    NSString *html = [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding];
    if (html.length == 0) return @[];
    NSRegularExpression *card = [NSRegularExpression regularExpressionWithPattern:@"<a class=\"rank-item-container\"[^>]*href=\"([^\"]*)\"[^>]*>([\\s\\S]*?)</a>" options:0 error:nil];
    NSRegularExpression *titleRe = [NSRegularExpression regularExpressionWithPattern:@"class=\"s-title\">([^<]+)<" options:0 error:nil];
    NSRegularExpression *heatRe = [NSRegularExpression regularExpressionWithPattern:@"class=\"s-tie-count\">([^<]+)<" options:0 error:nil];
    NSRegularExpression *imgRe = [NSRegularExpression regularExpressionWithPattern:@"url\\(['\"]?(https?://[^'\")]+)" options:0 error:nil];
    NSMutableArray *items = [NSMutableArray array];
    for (NSTextCheckingResult *m in [card matchesInString:html options:0 range:NSMakeRange(0, html.length)]) {
        if (m.numberOfRanges < 3) continue;
        NSString *body = [html substringWithRange:[m rangeAtIndex:2]];
        NSTextCheckingResult *t = [titleRe firstMatchInString:body options:0 range:NSMakeRange(0, body.length)];
        if (!t) continue;
        NSString *title = RPDecode([body substringWithRange:[t rangeAtIndex:1]]);
        if (title.length == 0) continue;
        NSTextCheckingResult *h = [heatRe firstMatchInString:body options:0 range:NSMakeRange(0, body.length)];
        NSString *heat = h ? RPDecode([body substringWithRange:[h rangeAtIndex:1]]) : @"";
        NSTextCheckingResult *im = [imgRe firstMatchInString:body options:0 range:NSMakeRange(0, body.length)];
        [items addObject:@{
            @"title": title,
            @"heat": heat,
            @"heat_value": @(RPHeatValue(heat)),
            @"summary": heat.length ? [NSString stringWithFormat:@"热度 %@", heat] : @"小红书热榜",
            @"link": [html substringWithRange:[m rangeAtIndex:1]] ?: @"",
            @"image_url": im ? [body substringWithRange:[im rangeAtIndex:1]] : @"",
        }];
        if ((NSInteger)items.count >= limit) break;
    }
    return items;
}

static NSArray *RPParseXiaohongshuText(NSData *data, NSInteger limit) {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) return @[];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)\\.\\[([^\\]]+)\\]\\((https://www\\.xiaohongshu\\.com/search_result[^)]+)\\)([0-9.]+[wW]?)" options:0 error:nil];
    NSArray *matches = [re matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    NSMutableArray *items = [NSMutableArray array];
    for (NSTextCheckingResult *m in matches) {
        if (m.numberOfRanges < 5) continue;
        NSString *title = RPDecode([text substringWithRange:[m rangeAtIndex:2]]);
        if (title.length == 0) continue;
        NSString *heat = [text substringWithRange:[m rangeAtIndex:4]];
        [items addObject:@{
            @"title": title,
            @"heat": heat ?: @"",
            @"heat_value": @(RPHeatValue(heat)),
            @"summary": heat.length ? [NSString stringWithFormat:@"热度 %@", heat] : @"小红书热榜",
            @"link": [text substringWithRange:[m rangeAtIndex:3]] ?: @"",
            @"image_url": @"",
        }];
        if ((NSInteger)items.count >= limit) break;
    }
    return items;
}

static NSArray *RPParseBilibili(NSData *data, NSInteger limit) {
    id json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:nil];
    NSDictionary *root = [json isKindOfClass:[NSDictionary class]] ? json : nil;
    NSDictionary *body = [root[@"data"] isKindOfClass:[NSDictionary class]] ? root[@"data"] : nil;
    NSArray *list = [body[@"list"] isKindOfClass:[NSArray class]] ? body[@"list"] : nil;
    if (![list isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *row in list) {
        if (![row isKindOfClass:[NSDictionary class]]) continue;
        NSString *title = RPString(row[@"title"]);
        if (title.length == 0) continue;
        NSDictionary *owner = [row[@"owner"] isKindOfClass:[NSDictionary class]] ? row[@"owner"] : @{};
        NSDictionary *stat = [row[@"stat"] isKindOfClass:[NSDictionary class]] ? row[@"stat"] : @{};
        NSString *views = RPCountText(stat[@"view"]);
        NSMutableArray *bits = [NSMutableArray array];
        if (RPString(owner[@"name"]).length) [bits addObject:RPString(owner[@"name"])];
        if (RPString(row[@"tname"]).length) [bits addObject:RPString(row[@"tname"])];
        if (views.length) [bits addObject:[NSString stringWithFormat:@"播放 %@", views]];
        NSString *desc = RPString(row[@"desc"]);
        if (desc.length > 80) desc = [[desc substringToIndex:80] stringByAppendingString:@"…"];
        if (desc.length) [bits addObject:desc];
        NSInteger dur = [row[@"duration"] integerValue];
        if (dur > 0) [bits addObject:[NSString stringWithFormat:@"时长 %ld:%02ld", (long)(dur / 60), (long)(dur % 60)]];
        NSString *link = RPString(row[@"short_link_v2"]);
        if (link.length == 0 && RPString(row[@"bvid"]).length) {
            link = [NSString stringWithFormat:@"https://www.bilibili.com/video/%@", RPString(row[@"bvid"])];
        }
        NSString *pic = RPString(row[@"pic"]);
        if ([pic hasPrefix:@"http://"]) pic = [@"https://" stringByAppendingString:[pic substringFromIndex:7]];
        double viewN = [stat[@"view"] doubleValue];
        NSDictionary *reason = [row[@"rcmd_reason"] isKindOfClass:[NSDictionary class]] ? row[@"rcmd_reason"] : @{};
        [items addObject:@{
            @"title": title,
            @"summary": [bits componentsJoinedByString:@" · "],
            @"link": link ?: @"",
            @"image_url": pic ?: @"",
            // Separate fields for the board layout (lead card, grid, ranked list).
            @"author": RPString(owner[@"name"]),
            @"tname": RPString(row[@"tname"]),
            @"duration": dur > 0 ? (dur >= 3600 ? [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)(dur / 3600), (long)(dur % 3600 / 60), (long)(dur % 60)] : [NSString stringWithFormat:@"%ld:%02ld", (long)(dur / 60), (long)(dur % 60)]) : @"",
            @"views": views ?: @"",
            @"view_value": @(viewN),
            @"likes": RPCountText(stat[@"like"]),
            @"danmaku": RPCountText(stat[@"danmaku"]),
            @"coins": RPCountText(stat[@"coin"]),
            @"reason": RPString(reason[@"content"]),
            @"desc": desc ?: @"",
        }];
        if ((NSInteger)items.count >= limit) break;
    }
    return items;
}

static NSArray *RPParseXTrends(NSData *data, NSInteger limit) {
    NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!html) return @[];
    NSRange trendAt = [html rangeOfString:@"ranking trends"];
    NSRange mostAt = [html rangeOfString:@"Most Tweeted"];
    NSString *trendHTML = html;
    NSString *mostHTML = @"";
    if (trendAt.location != NSNotFound) {
        NSUInteger loc = trendAt.location;
        NSUInteger end = (mostAt.location != NSNotFound && mostAt.location > loc) ? mostAt.location : html.length;
        trendHTML = [html substringWithRange:NSMakeRange(loc, end - loc)];
        if (mostAt.location != NSNotFound) mostHTML = [html substringFromIndex:mostAt.location];
    }
    NSMutableDictionary *scores = [NSMutableDictionary dictionary];
    NSString *hotLine = @"";
    if (mostHTML.length) {
        NSRegularExpression *scoreRe = [NSRegularExpression regularExpressionWithPattern:@"class=\"pos\">\\s*(\\d+)\\s*</th>\\s*<td class=\"main\"><a[^>]*>([^<]+)</a></td>\\s*<td class=\"details[^\"]*\"[^>]*>([^<]+)</td>" options:0 error:nil];
        for (NSTextCheckingResult *m in [scoreRe matchesInString:mostHTML options:0 range:NSMakeRange(0, mostHTML.length)]) {
            if (m.numberOfRanges < 4) continue;
            NSString *title = RPDecode([mostHTML substringWithRange:[m rangeAtIndex:2]]);
            NSString *score = [[mostHTML substringWithRange:[m rangeAtIndex:3]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (title.length == 0) continue;
            if (score.length) scores[title] = score;
            if (hotLine.length == 0 && score.length) hotLine = [NSString stringWithFormat:@"24小时讨论最热 %@ · %@", title, score];
        }
    }
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"class=\"pos\">\\s*(\\d+)\\s*</th>\\s*<td class=\"main\"><a[^>]*>([^<]+)</a></td>\\s*<td class=\"graph\">([\\s\\S]*?)</td>" options:0 error:nil];
    NSRegularExpression *sparkRe = [NSRegularExpression regularExpressionWithPattern:@"polyline points=\"([0-9][^\"]*)\"" options:0 error:nil];
    NSMutableArray *items = [NSMutableArray array];
    for (NSTextCheckingResult *m in [re matchesInString:trendHTML options:0 range:NSMakeRange(0, trendHTML.length)]) {
        if (m.numberOfRanges < 4) continue;
        NSString *rank = [trendHTML substringWithRange:[m rangeAtIndex:1]];
        NSString *title = RPDecode([trendHTML substringWithRange:[m rangeAtIndex:2]]);
        if (title.length == 0) continue;
        NSString *graph = [trendHTML substringWithRange:[m rangeAtIndex:3]];
        NSArray *sparks = [sparkRe matchesInString:graph options:0 range:NSMakeRange(0, graph.length)];
        NSString *spark = @"";
        if (sparks.count) {
            NSTextCheckingResult *last = sparks.lastObject;
            if (last.numberOfRanges > 1) spark = [graph substringWithRange:[last rangeAtIndex:1]];
        }
        NSString *score = RPString(scores[title]);
        NSMutableString *summary = [NSMutableString stringWithFormat:@"第 %@ 名", rank];
        if (score.length) [summary appendFormat:@" · %@", score];
        NSString *q = [title stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: @"";
        q = [q stringByReplacingOccurrencesOfString:@"#" withString:@"%23"];
        q = [q stringByReplacingOccurrencesOfString:@"&" withString:@"%26"];
        NSMutableDictionary *item = [@{
            @"title": title,
            @"summary": summary,
            @"link": [NSString stringWithFormat:@"https://x.com/search?q=%@&f=live", q],
            @"image_url": @"",
            @"rank": rank ?: @"",
            @"spark": spark ?: @"",
            @"score": score ?: @"",
            @"rich": @YES,
        } mutableCopy];
        if (items.count == 0 && hotLine.length) item[@"hot_line"] = hotLine;
        [items addObject:item];
        if ((NSInteger)items.count >= limit) break;
    }
    return items;
}

static NSArray *RPParseXMarkdown(NSData *data, NSInteger limit) {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (text.length == 0) return @[];
    NSRange mostAt = [text rangeOfString:@"Most Tweeted"];
    NSString *trendText = text;
    NSString *mostText = @"";
    if (mostAt.location != NSNotFound) {
        trendText = [text substringToIndex:mostAt.location];
        mostText = [text substringFromIndex:mostAt.location];
    }
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\|\\s*(\\d+)\\s*\\|\\s*\\[([^\\]]+)\\]\\(([^)]*)\\)\\s*\\|\\s*([^|]*)\\|" options:0 error:nil];
    NSMutableDictionary *scores = [NSMutableDictionary dictionary];
    if (mostText.length) {
        for (NSTextCheckingResult *m in [re matchesInString:mostText options:0 range:NSMakeRange(0, mostText.length)]) {
            if (m.numberOfRanges < 5) continue;
            NSString *title = RPDecode([mostText substringWithRange:[m rangeAtIndex:2]]);
            NSString *score = [[mostText substringWithRange:[m rangeAtIndex:4]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (title.length && score.length) scores[title] = score;
        }
    }
    NSMutableArray *items = [NSMutableArray array];
    for (NSTextCheckingResult *m in [re matchesInString:trendText options:0 range:NSMakeRange(0, trendText.length)]) {
        if (m.numberOfRanges < 5) continue;
        NSString *rank = [trendText substringWithRange:[m rangeAtIndex:1]];
        NSString *title = RPDecode([trendText substringWithRange:[m rangeAtIndex:2]]);
        if (title.length == 0) continue;
        NSString *score = RPString(scores[title]);
        if (score.length == 0) {
            score = [[trendText substringWithRange:[m rangeAtIndex:4]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        NSString *q = [title stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: @"";
        q = [q stringByReplacingOccurrencesOfString:@"#" withString:@"%23"];
        q = [q stringByReplacingOccurrencesOfString:@"&" withString:@"%26"];
        [items addObject:[@{
            @"title": title,
            @"summary": [NSString stringWithFormat:@"第 %@ 名", rank],
            @"link": [NSString stringWithFormat:@"https://x.com/search?q=%@&f=live", q],
            @"image_url": @"",
            @"rank": rank ?: @"",
            @"spark": @"",
            @"score": score ?: @"",
            @"rich": @YES,
        } mutableCopy]];
        if ((NSInteger)items.count >= limit) break;
    }
    return items;
}

static double RPDouble(id value) {
    if ([value isKindOfClass:[NSNumber class]]) return [(NSNumber *)value doubleValue];
    if ([value isKindOfClass:[NSString class]]) return [(NSString *)value doubleValue];
    return 0;
}

static NSArray *RPSplitSymbols(NSString *raw, NSInteger limit) {
    if (raw.length == 0) return @[];
    NSCharacterSet *seps = [NSCharacterSet characterSetWithCharactersInString:@",，、 \n\t"];
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *part in [raw componentsSeparatedByCharactersInSet:seps]) {
        NSString *s = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (s.length == 0) continue;
        [out addObject:s];
        if ((NSInteger)out.count >= limit) break;
    }
    return out;
}

static NSString *RPStockSecid(NSString *token) {
    NSString *s = [[token lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    s = [s stringByReplacingOccurrencesOfString:@"." withString:@""];
    NSString *market = nil;
    NSString *code = s;
    if ([s hasPrefix:@"sh"]) { market = @"1"; code = [s substringFromIndex:2]; }
    else if ([s hasPrefix:@"sz"]) { market = @"0"; code = [s substringFromIndex:2]; }
    else if ([s hasPrefix:@"bj"]) { market = @"0"; code = [s substringFromIndex:2]; }
    else if (s.length == 6) {
        unichar c = [s characterAtIndex:0];
        market = (c == '6' || c == '5' || c == '9') ? @"1" : @"0";
        code = s;
    }
    if (market.length == 0 || code.length != 6) return nil;
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    if ([[code stringByTrimmingCharactersInSet:digits] length] != 0) return nil;
    return [NSString stringWithFormat:@"%@.%@", market, code];
}

static NSArray *RPParseEastmoney(NSData *data, NSArray *codes) {
    id json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:nil];
    NSDictionary *root = [json isKindOfClass:[NSDictionary class]] ? json : nil;
    NSArray *diff = [root[@"data"] isKindOfClass:[NSDictionary class]] ? root[@"data"][@"diff"] : nil;
    if (![diff isKindOfClass:[NSArray class]]) return @[];
    NSMutableDictionary *byCode = [NSMutableDictionary dictionary];
    for (NSDictionary *row in diff) {
        if (![row isKindOfClass:[NSDictionary class]]) continue;
        NSString *code = RPString(row[@"f12"]);
        if (code.length == 0) continue;
        NSString *name = RPString(row[@"f14"]);
        if (name.length == 0) name = code;
        byCode[code] = @{
            @"name": name,
            @"symbol": code,
            @"price": @(RPDouble(row[@"f2"])),
            @"percent": @(RPDouble(row[@"f3"])),
            @"change": @(RPDouble(row[@"f4"])),
            @"high": @(RPDouble(row[@"f15"])),
            @"low": @(RPDouble(row[@"f16"])),
            @"open": @(RPDouble(row[@"f17"])),
            @"prev": @(RPDouble(row[@"f18"])),
            @"turnover": @(RPDouble(row[@"f6"])),
            @"unit": @"元",
            @"market": @"stock",
        };
    }
    NSMutableArray *items = [NSMutableArray array];
    if (codes.count == 0) {
        for (NSDictionary *row in diff) {
            NSString *code = [row isKindOfClass:[NSDictionary class]] ? RPString(row[@"f12"]) : @"";
            if (byCode[code]) [items addObject:byCode[code]];
        }
        return items;
    }
    for (NSString *code in codes) {
        NSDictionary *item = byCode[code];
        if (item) [items addObject:item];
    }
    return items;
}

static NSDictionary *RPCoinTable(void) {
    return @{
        @"btc": @[@"BTC-USDT", @"比特币"],
        @"eth": @[@"ETH-USDT", @"以太坊"],
        @"sol": @[@"SOL-USDT", @"Solana"],
        @"bnb": @[@"BNB-USDT", @"币安币"],
        @"xrp": @[@"XRP-USDT", @"瑞波币"],
        @"doge": @[@"DOGE-USDT", @"狗狗币"],
        @"ada": @[@"ADA-USDT", @"艾达币"],
        @"trx": @[@"TRX-USDT", @"波场"],
        @"ltc": @[@"LTC-USDT", @"莱特币"],
        @"bch": @[@"BCH-USDT", @"比特币现金"],
        @"dot": @[@"DOT-USDT", @"波卡"],
        @"avax": @[@"AVAX-USDT", @"Avalanche"],
        @"link": @[@"LINK-USDT", @"Chainlink"],
        @"ton": @[@"TON-USDT", @"TON"],
        @"usdt": @[@"USDT-USD", @"泰达币"],
    };
}

static NSArray *RPParseOKX(NSData *data, NSArray *wanted) {
    id json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:nil];
    NSDictionary *root = [json isKindOfClass:[NSDictionary class]] ? json : nil;
    NSArray *rows = [root[@"data"] isKindOfClass:[NSArray class]] ? root[@"data"] : nil;
    if (![rows isKindOfClass:[NSArray class]]) return @[];
    NSMutableDictionary *byId = [NSMutableDictionary dictionary];
    for (NSDictionary *row in rows) {
        if (![row isKindOfClass:[NSDictionary class]]) continue;
        NSString *inst = RPString(row[@"instId"]);
        if (inst.length) byId[inst] = row;
    }
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *spec in wanted) {
        NSDictionary *row = byId[spec[@"inst"]];
        if (![row isKindOfClass:[NSDictionary class]]) continue;
        double last = RPDouble(row[@"last"]);
        double open = RPDouble(row[@"open24h"]);
        double change = last - open;
        double percent = open > 0 ? change / open * 100.0 : 0;
        [items addObject:@{
            @"name": spec[@"name"] ?: spec[@"symbol"] ?: @"",
            @"symbol": spec[@"symbol"] ?: @"",
            @"price": @(last),
            @"percent": @(percent),
            @"change": @(change),
            @"high": @(RPDouble(row[@"high24h"])),
            @"low": @(RPDouble(row[@"low24h"])),
            @"open": @(open),
            @"prev": @(open),
            @"turnover": @(RPDouble(row[@"volCcy24h"])),
            @"unit": @"USDT",
            @"market": @"crypto",
        }];
    }
    return items;
}

static NSString *RPSetupHTML(void) {
    return [NSString stringWithUTF8String:
        "<!DOCTYPE html>\n"
        "<html lang=\"zh\">\n"
        "<head>\n"
        "<meta charset=\"utf-8\">\n"
        "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n"
        "<title>RemotePanel 设置</title>\n"
        "<style>\n"
        "body{font-family:-apple-system,\"Segoe UI\",sans-serif;background:#eef3fb;color:#14213d;margin:0}\n"
        "main{max-width:880px;margin:0 auto;padding:24px 16px 48px}\n"
        "h1{font-size:22px;margin:0 0 6px}\n"
        "h2{font-size:16px;margin:0 0 8px}\n"
        "p{color:#445;font-size:14px}\n"
        ".card{background:#fff;border-radius:12px;padding:16px;margin:12px 0;box-shadow:0 1px 4px rgba(20,40,80,.08)}\n"
        "label{display:block;font-size:13px;color:#445;margin:10px 0 4px}\n"
        "input[type=text],input[type=number],select{width:100%;box-sizing:border-box;padding:8px 10px;border:1px solid #c5d0e0;border-radius:8px;font-size:14px;background:#fff}\n"
        ".row{display:flex;gap:16px;align-items:center;flex-wrap:wrap}\n"
        ".page{border-top:1px solid #e6edf5;padding-top:12px;margin-top:12px}\n"
        ".check{display:flex;align-items:center;gap:8px;font-size:14px}\n"
        ".check input{width:auto}\n"
        "button{background:#1a6fe8;color:#fff;border:0;border-radius:8px;padding:12px 20px;font-size:16px;cursor:pointer}\n"
        "#msg{min-height:22px;margin:8px 0;font-size:14px}\n"
        ".narrow{width:120px}\n"
        "</style>\n"
        "</head>\n"
        "<body>\n"
        "<main>\n"
        "<h1>RemotePanel 设置</h1>\n"
        "<p>这里改的就是 iPad 上的设置。保存后，iPad 会按新内容重新拉取。</p>\n"
        "<div id=\"msg\"></div>\n"
        "<div id=\"app\">正在读取…</div>\n"
        "<button id=\"save\" type=\"button\">保存到 iPad</button>\n"
        "</main>\n"
        "<script>\n"
        "var state;\n"
        "function esc(s){return String(s==null?\"\":s).replace(/[&<>\"]/g,function(c){return {\"&\":\"&amp;\",\"<\":\"&lt;\",\">\":\"&gt;\",\"\\\"\":\"&quot;\"}[c]})}\n"
        "function opt(choices,titles,cur){\n"
        "  var h=\"\", n=Number(cur);\n"
        "  for(var i=0;i<choices.length;i++){\n"
        "    h+=\"<option value=\\\"\"+choices[i]+\"\\\"\"+(Number(choices[i])===n?\" selected\":\"\")+\">\"+esc(titles[i])+\"</option>\";\n"
        "  }\n"
        "  return h;\n"
        "}\n"
        "function uploadVideo(){\n"
        "  var input=document.getElementById(\"vfile\"), msg=document.getElementById(\"vmsg\");\n"
        "  if(!input||!input.files||!input.files[0]){ if(msg) msg.textContent=\"先选择一个 mp4、mov 或 m4v。\"; return; }\n"
        "  var file=input.files[0], name=file.name||\"clip.mp4\", chunk=100000, seq=0;\n"
        "  if(!file.size){ if(msg) msg.textContent=\"文件是空的。\"; return; }\n"
        "  if(file.size>200*1024*1024){ if(msg) msg.textContent=\"单个文件请小于 200MB。\"; return; }\n"
        "  if(msg) msg.textContent=\"正在上传…\";\n"
        "  function step(){\n"
        "    var end=Math.min(file.size,(seq+1)*chunk), last=end>=file.size?1:0, blob=file.slice(seq*chunk,end);\n"
        "    fetch(\"/video-chunk?name=\"+encodeURIComponent(name)+\"&seq=\"+seq+\"&last=\"+last,{method:\"POST\",body:blob})\n"
        "      .then(function(r){return r.text().then(function(t){if(!r.ok) throw new Error(t||\"失败\");});})\n"
        "      .then(function(){\n"
        "        if(last){ if(msg) msg.textContent=\"已上传。来源选「上传到这台 iPad」，并勾选视频页的显示。\"; return; }\n"
        "        seq++; if(msg) msg.textContent=\"正在上传… \"+Math.round(end*100/file.size)+\"%\"; step();\n"
        "      }).catch(function(e){ if(msg) msg.textContent=\"上传失败：\"+(e&&e.message?e.message:\"\"); });\n"
        "  }\n"
        "  step();\n"
        "}\n"
        "function render(){\n"
        "  var ch=state.refresh_choices, ti=state.refresh_titles, h=\"\";\n"
        "  h+=\"<div class=\\\"card\\\"><h2>连接</h2><label>HTTP / SOCKS 代理</label><input id=\\\"proxy\\\" type=\\\"text\\\" value=\\\"\"+esc(state.proxy)+\"\\\">\";\n"
        "  h+=\"<label>代理用户名（代理不需要登录就留空）</label><input id=\\\"proxyUser\\\" type=\\\"text\\\" autocomplete=\\\"off\\\" value=\\\"\"+esc(state.proxy_user||\"\")+\"\\\">\";\n"
        "  h+=\"<label>代理密码\"+(state.proxy_pass_set?\"（已保存，留空则不改）\":\"\")+\"</label><input id=\\\"proxyPass\\\" type=\\\"password\\\" autocomplete=\\\"new-password\\\" value=\\\"\\\">\";\n"
        "  if(state.proxy_pass_set) h+=\"<label class=\\\"check\\\"><input id=\\\"proxyPassClear\\\" type=\\\"checkbox\\\"> 清除已保存的代理密码</label>\";\n"
        "  h+=\"<label>全局停留秒（0 表示用每一页自己的秒数）</label><input id=\\\"dwell\\\" class=\\\"narrow\\\" type=\\\"number\\\" value=\\\"\"+esc(state.dwell_override)+\"\\\"></div>\";\n"
        "  h+=\"<div class=\\\"card\\\"><h2>消息</h2><label>走马灯地址（JSON、纯文本或 RSS，留空则不显示）</label><input id=\\\"ticker\\\" type=\\\"text\\\" value=\\\"\"+esc(state.ticker_url)+\"\\\">\";\n"
        "  h+=\"<label class=\\\"check\\\"><input id=\\\"tickerProxy\\\" type=\\\"checkbox\\\"\"+(state.ticker_proxy?\" checked\":\"\")+\"> 使用代理</label>\";\n"
        "  h+=\"<label>多久拉一次</label><select id=\\\"tickerRefresh\\\">\"+opt(ch,ti,state.ticker_refresh)+\"</select></div>\";\n"
        "  h+=\"<div class=\\\"card\\\"><h2>VPS 流量</h2><label>接口地址</label><input id=\\\"vps\\\" type=\\\"text\\\" value=\\\"\"+esc(state.vps_url)+\"\\\">\";\n"
        "  h+=\"<label>Token</label><input id=\\\"vpsToken\\\" type=\\\"text\\\" value=\\\"\"+esc(state.vps_token)+\"\\\">\";\n"
        "  h+=\"<label class=\\\"check\\\"><input id=\\\"vpsProxy\\\" type=\\\"checkbox\\\"\"+(state.vps_proxy?\" checked\":\"\")+\"> 使用代理</label>\";\n"
        "  h+=\"<label>流量更新</label><select id=\\\"vpsRefresh\\\">\"+opt(ch,ti,state.vps_refresh)+\"</select></div>\";\n"
        "  h+=\"<div class=\\\"card\\\"><h2>相册</h2><label>本地相册 A / B 使用的相册</label><select id=\\\"album\\\"><option value=\\\"\\\">默认（收藏夹或图库）</option>\";\n"
        "  (state.albums||[]).forEach(function(a){\n"
        "    h+=\"<option value=\\\"\"+esc(a.id)+\"\\\"\"+(a.id===state.album_id?\" selected\":\"\")+\">\"+esc(a.title)+\"</option>\";\n"
        "  });\n"
        "  if(!(state.albums||[]).length) h+=\"</select><p>还没有读到相册列表。iPad 需要先允许访问照片。</p></div>\";\n"
        "  else h+=\"</select></div>\";\n"
        "  h+=\"<div class=\\\"card\\\"><h2>视频</h2>\";\n"
        "  h+=\"<p>有两个视频页：「相册视频」和「网络视频」，默认都不显示，到下面的页面列表里勾选「显示」。每次随机播一段，默认静音，播完再翻页。只支持 H.264 的 mp4、mov、m4v，建议 1080p 以内。</p>\";\n"
        "  h+=\"<label class=\\\"check\\\"><input id=\\\"vmuted\\\" type=\\\"checkbox\\\"\"+(state.video_muted!==false?\" checked\":\"\")+\"> 播放时静音</label>\";\n"
        "  h+=\"<h3>相册视频</h3><label>放哪里的视频</label><select id=\\\"vsource\\\">\";\n"
        "  h+=\"<option value=\\\"album\\\"\"+(state.video_source!==\"files\"?\" selected\":\"\")+\">相册里的视频</option>\";\n"
        "  h+=\"<option value=\\\"files\\\"\"+(state.video_source===\"files\"?\" selected\":\"\")+\">上传到这台 iPad 的视频</option></select>\";\n"
        "  h+=\"<label>相册（留空则用上面选的相册；那个相册没有视频时，再用全部视频）</label><select id=\\\"valbum\\\"><option value=\\\"\\\">跟随上面的相册</option>\";\n"
        "  (state.albums||[]).forEach(function(a){\n"
        "    h+=\"<option value=\\\"\"+esc(a.id)+\"\\\"\"+(a.id===state.video_album?\" selected\":\"\")+\">\"+esc(a.title)+\"</option>\";\n"
        "  });\n"
        "  h+=\"</select>\";\n"
        "  h+=\"<h3>网络视频</h3><label>视频目录（HTTP 目录列表或 WebDAV）</label><input id=\\\"vhttp\\\" type=\\\"text\\\" value=\\\"\"+esc(state.video_http)+\"\\\" placeholder=\\\"http://192.168.28.30/videos/\\\">\";\n"
        "  h+=\"<label>目录用户名（不需要登录就留空）</label><input id=\\\"vhttpUser\\\" type=\\\"text\\\" autocomplete=\\\"off\\\" value=\\\"\"+esc(state.video_http_user||\"\")+\"\\\">\";\n"
        "  h+=\"<label>目录密码\"+(state.video_http_pass_set?\"（已保存，留空则不改）\":\"\")+\"</label><input id=\\\"vhttpPass\\\" type=\\\"password\\\" autocomplete=\\\"new-password\\\" value=\\\"\\\">\";\n"
        "  h+=\"<p>群晖、威联通等 NAS 打开 WebDAV 后填它的地址即可。iPad 读不了 SMB（\\\\\\\\电脑\\\\共享），请改用 HTTP 或 WebDAV。</p>\";\n"
        "  h+=\"<label>最长播放（分钟，0 表示播完再翻页）</label><input id=\\\"vmax\\\" class=\\\"narrow\\\" type=\\\"number\\\" value=\\\"\"+esc(state.video_max)+\"\\\">\";\n"
        "  h+=\"<label>已经上传的视频</label>\";\n"
        "  if(!(state.video_files||[]).length) h+=\"<p>还没有上传。</p>\";\n"
        "  else (state.video_files||[]).forEach(function(f){\n"
        "    h+=\"<label class=\\\"check\\\"><input type=\\\"checkbox\\\" class=\\\"vdel\\\" data-name=\\\"\"+esc(f.name)+\"\\\"> 删除 \"+esc(f.name)+\" （\"+esc(f.mb)+\" MB）</label>\";\n"
        "  });\n"
        "  h+=\"<label>从这台电脑上传</label><input id=\\\"vfile\\\" type=\\\"file\\\" accept=\\\".mp4,.mov,.m4v,video/mp4,video/quicktime\\\">\";\n"
        "  h+=\"<p><button id=\\\"vupload\\\" type=\\\"button\\\">上传到 iPad</button></p><p id=\\\"vmsg\\\"></p></div>\";\n"
        "  h+=\"<div class=\\\"card\\\"><h2>页面</h2>\";\n"
        "  (state.pages||[]).forEach(function(pg,i){\n"
        "    h+=\"<div class=\\\"page\\\" data-i=\\\"\"+i+\"\\\"><div class=\\\"row\\\"><strong>\"+esc(pg.title)+\"</strong>\";\n"
        "    h+=\"<label class=\\\"check\\\"><input type=\\\"checkbox\\\" class=\\\"en\\\"\"+(pg.enabled?\" checked\":\"\")+\"> 显示</label>\";\n"
        "    h+=\"<label class=\\\"check\\\">停留 <input class=\\\"dw narrow\\\" type=\\\"number\\\" value=\\\"\"+esc(pg.dwell)+\"\\\"> 秒</label></div>\";\n"
        "    if(pg.id===\"local-video\"||pg.id===\"net-video\") h+=\"<p>这里的秒数只在没有视频可播时使用。正在播放时会播完，或到达上面的最长播放，再翻页。</p>\";\n"
        "    if(pg.has_source){\n"
        "      h+=\"<label>\"+esc(pg.hint||\"接口\")+\"</label><input class=\\\"url\\\" type=\\\"text\\\" value=\\\"\"+esc(pg.url)+\"\\\">\";\n"
        "      if(pg.api_key!=null){\n"
        "        h+=\"<label>API Key</label><input class=\\\"akey\\\" type=\\\"text\\\" value=\\\"\"+esc(pg.api_key)+\"\\\">\";\n"
        "        h+=\"<label>模型</label><input class=\\\"model\\\" type=\\\"text\\\" value=\\\"\"+esc(pg.model)+\"\\\">\";\n"
        "      }\n"
        "      h+=\"<label class=\\\"check\\\"><input type=\\\"checkbox\\\" class=\\\"px\\\"\"+(pg.use_proxy?\" checked\":\"\")+\"> 使用代理</label>\";\n"
        "      if(pg.refresh_shared) h+=\"<p>数据更新与「Steam 新游」共用。</p>\";\n"
        "      else if(pg.refresh_period) h+=\"<p>早上、中午、晚上各请求一次。</p>\";\n"
        "      else h+=\"<label>数据更新</label><select class=\\\"rf\\\">\"+opt(ch,ti,pg.refresh)+\"</select>\";\n"
        "    }\n"
        "    h+=\"</div>\";\n"
        "  });\n"
        "  h+=\"</div>\";\n"
        "  document.getElementById(\"app\").innerHTML=h;\n"
        "  var up=document.getElementById(\"vupload\");\n"
        "  if(up) up.onclick=uploadVideo;\n"
        "}\n"
        "function collect(){\n"
        "  var body=JSON.parse(JSON.stringify(state));\n"
        "  body.proxy=document.getElementById(\"proxy\").value;\n"
        "  body.proxy_user=document.getElementById(\"proxyUser\").value;\n"
        "  body.proxy_pass=document.getElementById(\"proxyPass\").value;\n"
        "  var ppc=document.getElementById(\"proxyPassClear\"); body.proxy_pass_clear=!!(ppc&&ppc.checked);\n"
        "  body.dwell_override=Number(document.getElementById(\"dwell\").value)||0;\n"
        "  body.ticker_url=document.getElementById(\"ticker\").value;\n"
        "  body.ticker_proxy=document.getElementById(\"tickerProxy\").checked;\n"
        "  body.ticker_refresh=Number(document.getElementById(\"tickerRefresh\").value);\n"
        "  body.vps_url=document.getElementById(\"vps\").value;\n"
        "  body.vps_token=document.getElementById(\"vpsToken\").value;\n"
        "  body.vps_proxy=document.getElementById(\"vpsProxy\").checked;\n"
        "  body.vps_refresh=Number(document.getElementById(\"vpsRefresh\").value);\n"
        "  body.album_id=document.getElementById(\"album\").value;\n"
        "  body.video_source=document.getElementById(\"vsource\").value;\n"
        "  body.video_album=document.getElementById(\"valbum\").value;\n"
        "  body.video_http=document.getElementById(\"vhttp\").value;\n"
        "  body.video_http_user=document.getElementById(\"vhttpUser\").value;\n"
        "  body.video_http_pass=document.getElementById(\"vhttpPass\").value;\n"
        "  body.video_muted=document.getElementById(\"vmuted\").checked;\n"
        "  body.video_max=Number(document.getElementById(\"vmax\").value)||0;\n"
        "  body.video_remove=[];\n"
        "  var dels=document.querySelectorAll(\".vdel\");\n"
        "  for(var di=0;di<dels.length;di++) if(dels[di].checked) body.video_remove.push(dels[di].getAttribute(\"data-name\"));\n"
        "  var nodes=document.querySelectorAll(\".page\");\n"
        "  for(var i=0;i<nodes.length;i++){\n"
        "    var n=nodes[i], pg=body.pages[i];\n"
        "    pg.enabled=n.querySelector(\".en\").checked;\n"
        "    pg.dwell=Number(n.querySelector(\".dw\").value)||pg.dwell;\n"
        "    var u=n.querySelector(\".url\"); if(u) pg.url=u.value;\n"
        "    var ak=n.querySelector(\".akey\"); if(ak) pg.api_key=ak.value;\n"
        "    var md=n.querySelector(\".model\"); if(md) pg.model=md.value;\n"
        "    var px=n.querySelector(\".px\"); if(px) pg.use_proxy=px.checked;\n"
        "    var rf=n.querySelector(\".rf\"); if(rf) pg.refresh=Number(rf.value);\n"
        "  }\n"
        "  return body;\n"
        "}\n"
        "document.getElementById(\"save\").onclick=function(){\n"
        "  var msg=document.getElementById(\"msg\");\n"
        "  msg.textContent=\"正在保存…\";\n"
        "  fetch(\"/setup\",{method:\"POST\",headers:{\"Content-Type\":\"application/json\"},body:JSON.stringify(collect())})\n"
        "    .then(function(r){return r.text().then(function(t){if(!r.ok) throw new Error(t); return t})})\n"
        "    .then(function(){msg.textContent=\"已保存。iPad 会按新设置重新拉取。\"})\n"
        "    .catch(function(){msg.textContent=\"保存失败，请确认 iPad 上的 App 还开着。\"});\n"
        "};\n"
        "fetch(\"/setup.json\").then(function(r){return r.json()}).then(function(j){state=j;render()}).catch(function(){\n"
        "  document.getElementById(\"app\").textContent=\"读不到 iPad 上的设置。\";\n"
        "});\n"
        "</script>\n"
        "</body>\n"
        "</html>\n"
    ];
}

static NSString * const RPDwellPrefix = @"RemotePanel.page.dwell.";
static NSString * const RPAlbumDefaultsKey = @"RemotePanel.albumLocalId";
static NSString * const RPDwellOverrideDefaultsKey = @"RemotePanel.dwellOverride";

/* Feeds hand us parsed JSON, which can hold NSNull (GitHub description, printer
   fields, weather min/max). NSNull is not a plist type, so one of them made every
   saveDisk fail, and on screen it showed as "<null>" or threw on -boolValue.
   Replace it with @"" all the way down. */
static id RPPlistSafe(id value) {
    if (!value || value == [NSNull null]) return nil;
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionaryWithCapacity:[value count]];
        [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id k, id v, BOOL *stop) {
            if (![k isKindOfClass:[NSString class]]) return;
            id c = RPPlistSafe(v);
            out[k] = c ?: @"";
        }];
        return out;
    }
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:[value count]];
        for (id v in (NSArray *)value) {
            id c = RPPlistSafe(v);
            [out addObject:c ?: @""];
        }
        return out;
    }
    if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] ||
        [value isKindOfClass:[NSDate class]] || [value isKindOfClass:[NSData class]]) return value;
    return [value description] ?: @"";
}

@interface RPLocalFeed ()
@property (nonatomic, strong) NSMutableDictionary *cache;
@property (nonatomic, strong) NSMutableDictionary *failedAt;
@property (nonatomic, strong) NSMutableDictionary *failStreak;
@property (nonatomic, assign) BOOL dirty;
@property (nonatomic, assign) NSTimeInterval refreshStartedAt;
@property (atomic, assign) NSUInteger refreshGeneration;
@property (atomic, assign) BOOL refreshing;
@property (nonatomic, assign) BOOL settingsRerun;
@property (nonatomic, copy) NSString *fetchError;
@property (nonatomic, copy) NSString *fetchNote;
@property (nonatomic, strong) NSMutableArray *logLines;
@end

@implementation RPLocalFeed

+ (instancetype)sharedFeed {
    static RPLocalFeed *feed;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ feed = [[RPLocalFeed alloc] init]; });
    return feed;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cache = [NSMutableDictionary dictionary];
        _failedAt = [NSMutableDictionary dictionary];
        _failStreak = [NSMutableDictionary dictionary];
        _logLines = [NSMutableArray array];
        [self migrateHelloDefaults];
        [self loadDisk];
        [self migrateXDefaults];
        [NSThread detachNewThreadSelector:@selector(runStatusServer) toTarget:self withObject:nil];
    }
    return self;
}

- (NSString *)diskPath {
    NSString *dir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
    return [dir stringByAppendingPathComponent:@"RemotePanelLocalFeed.plist"];
}

- (void)loadDisk {
    // A plist file cannot hold NSNull, so whatever loads from disk is already clean.
    // Every value added later goes through store: → RPPlistSafe, so the state the
    // pages receive never contains NSNull and -boolValue/-doubleValue cannot throw.
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:[self diskPath]];
    if ([saved isKindOfClass:[NSDictionary class]]) [self.cache addEntriesFromDictionary:saved];
}

- (void)markDirty {
    @synchronized (self) { self.dirty = YES; }
}

- (void)saveDisk {
    NSDictionary *snapshot;
    @synchronized (self) {
        if (!self.dirty) return;
        snapshot = [self.cache copy];
        self.dirty = NO;
    }
    // writeToFile: silently returns NO for any non-plist value; say so instead
    // of losing the cache on every restart.
    if (![snapshot writeToFile:[self diskPath] atomically:YES]) {
        [self appendLog:@"缓存" status:@"fail" detail:@"写入磁盘失败，重启后要重新拉取"];
    }
}

- (BOOL)pageEnabled:(NSString *)pid {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *key = [RPPageEnabledPrefix stringByAppendingString:pid];
    if ([ud objectForKey:key] == nil) return RPLocalPageDefaultOn(pid);
    return [ud boolForKey:key];
}

- (void)migrateHelloDefaults {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *key = [RPSourceURLPrefix stringByAppendingString:@"hello"];
    NSString *saved = [ud stringForKey:key];
    if ([saved rangeOfString:@"hellogithub"].location != NSNotFound) {
        [ud removeObjectForKey:key];
        [ud setBool:NO forKey:[RPSourceProxyPrefix stringByAppendingString:@"hello"]];
    }
}

- (void)migrateXDefaults {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([[ud stringForKey:@"RemotePanel.x.region"] isEqualToString:@"us"]) return;
    NSString *key = [RPSourceURLPrefix stringByAppendingString:@"x-news"];
    NSString *saved = RPString([ud stringForKey:key]);
    NSString *trim = [saved stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    BOOL world = trim.length == 0
        || [trim isEqualToString:@"https://getdaytrends.com"]
        || [trim isEqualToString:@"https://getdaytrends.com/"]
        || [trim isEqualToString:@"http://getdaytrends.com"]
        || [trim isEqualToString:@"http://getdaytrends.com/"];
    if (!world) return;
    [ud setObject:@"https://getdaytrends.com/united-states/" forKey:key];
    [ud setObject:@"us" forKey:@"RemotePanel.x.region"];
    @synchronized (self) {
        [self.cache removeObjectForKey:@"x"];
        self.dirty = YES;
    }
    [self saveDisk];
}

- (NSString *)sourceURL:(NSString *)pid {
    NSString *saved = RPString([[NSUserDefaults standardUserDefaults] stringForKey:[RPSourceURLPrefix stringByAppendingString:pid]]);
    if ([pid isEqualToString:@"hello"] && [saved rangeOfString:@"hellogithub"].location != NSNotFound) saved = @"";
    if (saved.length) return saved;
    return RPString(RPLocalSourceDefaults()[pid]);
}

- (NSString *)proxyFor:(NSString *)pid {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *key = [RPSourceProxyPrefix stringByAppendingString:pid];
    BOOL on = [ud objectForKey:key] == nil ? RPLocalDefaultUseProxy(pid) : [ud boolForKey:key];
    if (!on) return nil;
    NSString *proxy = RPConfiguredProxy();
    return proxy;
}

- (BOOL)fresh:(NSString *)key ttl:(NSTimeInterval)ttl {
    @synchronized (self) {
        NSDictionary *box = self.cache[key];
        if (![box isKindOfClass:[NSDictionary class]] || !box[@"payload"]) return NO;
        id payload = box[@"payload"];
        BOOL young = [[NSDate date] timeIntervalSince1970] - [box[@"at"] doubleValue] < ttl;
        // Fetched by this build within the TTL: trust it. The shape checks below exist
        // to throw away caches written by older builds. Applied to fresh data they
        // could never pass for some sources (X via RSS, a 0-second bilibili clip, an
        // empty ticker), and those refetched on every 30 s poll forever.
        // (The greeting still goes through its slot check: a morning line must not last into the evening.)
        BOOL oldXhs = [key isEqualToString:@"xhs"] && [payload isKindOfClass:[NSArray class]] && [(NSArray *)payload count] &&
            [[(NSArray *)payload firstObject] isKindOfClass:[NSDictionary class]] &&
            [[(NSArray *)payload firstObject][@"cover"] integerValue] < 4;
        // v3 (build 10): cover feeds keep 10–15 items so pages fill whole rows. A v2
        // cover cache (6–8 items) is refetched once instead of waiting out its 24 h TTL.
        BOOL coverFeed = [@[@"movies", @"steam", @"pc", @"switch", @"ps5", @"bili"] containsObject:key];
        if (coverFeed && [box[@"v"] integerValue] < 3) return NO;
        if (young && [box[@"v"] integerValue] >= 2 && ![key isEqualToString:@"hello"] && !oldXhs) return YES;
        if ([payload isKindOfClass:[NSArray class]] && [(NSArray *)payload count] == 0) return NO;
        if ([key isEqualToString:@"hello"]) {
            if ([box[@"at"] doubleValue] <= 0) return NO;
            if (![payload isKindOfClass:[NSDictionary class]]) return NO;
            NSString *text = payload[@"text"];
            NSString *slot = payload[@"slot"];
            NSString *source = payload[@"source"];
            // Greetings cached before this build have no source tag; keep them for their slot.
            BOOL sameSource = ![source isKindOfClass:[NSString class]] || [source isEqualToString:[self helloSourceTag]];
            return [text isKindOfClass:[NSString class]] && text.length > 0 && [slot isEqualToString:RPHelloSlot(NULL)] && sameSource;
        }
        if (([key isEqualToString:@"x"] || [key isEqualToString:@"xhs"] || [key isEqualToString:@"github"]) && [payload isKindOfClass:[NSArray class]] && [(NSArray *)payload count]) {
            id first = [(NSArray *)payload firstObject];
            if (![first isKindOfClass:[NSDictionary class]] || ![(NSDictionary *)first objectForKey:@"image_url"] || (([key isEqualToString:@"x"] || [key isEqualToString:@"xhs"]) && ![first[@"rich"] boolValue])) return NO;
            // cover 4 = the build-7.1 list (16 items, heat values, 7 photos); older caches refetch once.
            if ([key isEqualToString:@"xhs"] && [first[@"cover"] integerValue] < 4) return NO;
            if ([key isEqualToString:@"x"] && ![first[@"blurb"] isKindOfClass:[NSString class]]) return NO;
        }
        if ([key isEqualToString:@"bili"] && [payload isKindOfClass:[NSArray class]] && [(NSArray *)payload count]) {
            id first = [(NSArray *)payload firstObject];
            NSString *sum = [first isKindOfClass:[NSDictionary class]] ? first[@"summary"] : nil;
            if (![sum isKindOfClass:[NSString class]] || [sum rangeOfString:@"时长"].location == NSNotFound) return NO;
        }
        if ([payload isKindOfClass:[NSArray class]]) {
            for (id row in (NSArray *)payload) {
                if (![row isKindOfClass:[NSDictionary class]]) continue;
                for (NSString *field in @[@"image_url", @"poster_url", @"header_url", @"capsule_url"]) {
                    NSString *url = row[field];
                    if ([url isKindOfClass:[NSString class]] && [url hasPrefix:@"data:"]) return NO;
                }
            }
        }
        return [[NSDate date] timeIntervalSince1970] - [box[@"at"] doubleValue] < ttl;
    }
}

- (void)store:(NSString *)key payload:(id)payload {
    id clean = RPPlistSafe(payload);
    if (!clean) return;
    @synchronized (self) {
        self.cache[key] = @{ @"at": @([[NSDate date] timeIntervalSince1970]), @"payload": clean, @"v": @3 };
        [self.failedAt removeObjectForKey:key];
        self.dirty = YES;
    }
}

/** Remember a failed fetch so the key is not retried on every 30 s poll. */
- (void)noteFailure:(NSString *)key {
    if (key.length == 0) return;
    @synchronized (self) {
        NSInteger streak = [self.failStreak[key] integerValue] + 1;
        self.failStreak[key] = @(streak);
        self.failedAt[key] = @([[NSDate date] timeIntervalSince1970]);
    }
}

/** 5, 10, 20, 40 then 60 min after consecutive failures, never longer than the TTL. */
- (BOOL)backingOff:(NSString *)key ttl:(NSTimeInterval)ttl {
    @synchronized (self) {
        NSNumber *at = self.failedAt[key];
        if (!at) return NO;
        NSInteger streak = MAX(1, [self.failStreak[key] integerValue]);
        NSTimeInterval wait = MIN(MIN(5 * 60 * pow(2, streak - 1), 3600), MAX(60, ttl));
        return [[NSDate date] timeIntervalSince1970] - at.doubleValue < wait;
    }
}

- (id)payload:(NSString *)key {
    @synchronized (self) {
        NSDictionary *box = self.cache[key];
        return [box isKindOfClass:[NSDictionary class]] ? box[@"payload"] : nil;
    }
}

- (NSData *)syncGET:(NSString *)url proxy:(NSString *)proxy headers:(NSDictionary *)headers {
    if (url.length == 0) {
        self.fetchError = @"地址是空的";
        return nil;
    }
    NSError *error = nil;
    NSData *data = [RPNet syncGET:url proxy:proxy headers:headers timeout:25 error:&error];
    if (!data && proxy.length) {
        NSError *proxyError = error;
        NSError *directError = nil;
        data = [RPNet syncGET:url proxy:nil headers:headers timeout:25 error:&directError];
        if (!data) {
            BOOL gaveUp = directError.code == 3 || directError.code == 5;
            error = (proxyError && gaveUp) ? proxyError : (directError ?: proxyError);
        } else {
            error = nil;
        }
    }
    self.fetchError = data ? nil : (error.localizedDescription ?: @"请求失败");
    return data;
}

- (NSData *)syncPOST:(NSString *)url body:(NSData *)body proxy:(NSString *)proxy headers:(NSDictionary *)headers {
    if (url.length == 0) {
        self.fetchError = @"地址是空的";
        return nil;
    }
    NSError *error = nil;
    NSData *data = [RPNet syncPOST:url body:body proxy:proxy headers:headers timeout:45 error:&error];
    if (!data && proxy.length) {
        NSError *proxyError = error;
        NSError *directError = nil;
        data = [RPNet syncPOST:url body:body proxy:nil headers:headers timeout:45 error:&directError];
        if (!data) {
            BOOL gaveUp = directError.code == 3 || directError.code == 5;
            error = (proxyError && gaveUp) ? proxyError : (directError ?: proxyError);
        } else {
            error = nil;
        }
    }
    self.fetchError = data ? nil : (error.localizedDescription ?: @"请求失败");
    return data;
}

- (void)markCacheStale {
    @synchronized (self) {
        for (NSString *key in [self.cache allKeys]) {
            // The greeting is generated per day-period by a paid API and does not
            // depend on any setting except its own key/model; leave it alone.
            if ([key isEqualToString:@"hello"]) continue;
            NSDictionary *box = self.cache[key];
            if (![box isKindOfClass:[NSDictionary class]]) continue;
            NSMutableDictionary *next = [box mutableCopy];
            next[@"at"] = @0;
            self.cache[key] = next;
        }
        self.dirty = YES;
    }
}

- (NSDictionary *)settingsDocument {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSDictionary *sourceDefaults = RPLocalSourceDefaults();
    NSArray *choices = RPLocalRefreshChoices();
    NSMutableArray *pages = [NSMutableArray array];
    for (NSDictionary *meta in RPLocalPageCatalog()) {
        NSString *pid = meta[@"id"] ?: @"";
        BOOL hasSource = sourceDefaults[pid] != nil;
        NSString *enabledKey = [RPPageEnabledPrefix stringByAppendingString:pid];
        BOOL enabled = [ud objectForKey:enabledKey] == nil ? RPLocalPageDefaultOn(pid) : [ud boolForKey:enabledKey];
        NSInteger dwell = [ud integerForKey:[RPDwellPrefix stringByAppendingString:pid]];
        if (dwell <= 0) dwell = [meta[@"dwell"] integerValue];
        NSString *proxyKey = [RPSourceProxyPrefix stringByAppendingString:pid];
        BOOL useProxy = [ud objectForKey:proxyKey] == nil ? RPLocalDefaultUseProxy(pid) : [ud boolForKey:proxyKey];
        NSString *savedURL = RPString([ud stringForKey:[RPSourceURLPrefix stringByAppendingString:pid]]);
        if ([pid isEqualToString:@"hello"] && [savedURL rangeOfString:@"hellogithub"].location != NSNotFound) savedURL = @"";
        NSString *url = savedURL.length ? savedURL : RPString(sourceDefaults[pid]);
        NSString *feed = RPLocalFeedKeyForPage(pid);
        NSInteger snap = feed.length ? RPLocalRefreshChoiceIndex(RPLocalTTL(feed)) : 0;
        NSMutableDictionary *page = [@{
            @"id": pid,
            @"title": meta[@"title"] ?: pid,
            @"hint": meta[@"hint"] ?: @"",
            @"enabled": @(enabled),
            @"dwell": @(dwell),
            @"has_source": @(hasSource),
            @"url": hasSource ? (url ?: @"") : @"",
            @"use_proxy": @(useProxy),
            @"refresh": choices[snap],
            @"refresh_shared": meta[@"refresh_shared"] ?: @NO,
            @"refresh_period": meta[@"refresh_period"] ?: @NO,
        } mutableCopy];
        if ([pid isEqualToString:@"hello"]) {
            NSString *helloKey = RPString([ud stringForKey:RPHelloKeyKey]);
            NSString *helloModel = RPString([ud stringForKey:RPHelloModelKey]);
            page[@"api_key"] = helloKey.length ? helloKey : RPLocalDefaultHelloKey();
            page[@"model"] = helloModel.length ? helloModel : RPLocalDefaultHelloModel();
        }
        [pages addObject:page];
    }
    NSMutableArray *albums = [NSMutableArray array];
    if ([NSThread isMainThread]) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"RPCollectAlbums" object:albums];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:@"RPCollectAlbums" object:albums];
        });
    }
    // Address only; the username and password go out as their own fields.
    NSString *proxy = RPString([ud stringForKey:RPProxyDefaultsKey]);
    if (proxy.length == 0) proxy = RPLocalDefaultProxy();
    NSString *vpsURL = RPString([ud stringForKey:RPVpsURLKey]);
    if (vpsURL.length == 0) vpsURL = RPLocalDefaultVPSURL();
    NSString *vpsToken = RPString([ud stringForKey:RPVpsTokenKey]);
    if (vpsToken.length == 0) vpsToken = RPLocalDefaultVPSToken();
    BOOL vpsProxy = [ud objectForKey:RPVpsProxyKey] ? [ud boolForKey:RPVpsProxyKey] : NO;
    return @{
        @"proxy": proxy ?: @"",
        @"proxy_user": RPString([ud stringForKey:RPProxyUserKey]),
        // Never echo the saved password back to the browser; the page shows
        // "已保存" and sends a new one only if the user types it.
        @"proxy_pass_set": @(RPString([ud stringForKey:RPProxyPassKey]).length > 0),
        @"dwell_override": @([ud integerForKey:RPDwellOverrideDefaultsKey]),
        @"ticker_url": RPString([ud stringForKey:RPTickerURLKey]),
        @"ticker_proxy": @([ud boolForKey:RPTickerProxyKey]),
        @"ticker_refresh": choices[RPLocalRefreshChoiceIndex(RPLocalTTL(@"ticker"))],
        @"vps_url": vpsURL ?: @"",
        @"vps_token": vpsToken ?: @"",
        @"vps_proxy": @(vpsProxy),
        @"vps_refresh": choices[RPLocalRefreshChoiceIndex(RPLocalTTL(@"vps"))],
        @"album_id": RPString([ud stringForKey:RPAlbumDefaultsKey]),
        @"albums": albums,
        @"video_source": ({
            NSString *src = RPString([ud stringForKey:RPVideoSourceKey]);
            src.length ? src : @"album";
        }),
        @"video_album": RPString([ud stringForKey:RPVideoAlbumKey]),
        @"video_http": RPString([ud stringForKey:RPVideoHTTPKey]),
        @"video_http_user": RPString([ud stringForKey:RPVideoHTTPUserKey]),
        @"video_http_pass_set": @([[ud stringForKey:RPVideoHTTPPassKey] length] > 0),
        @"video_muted": RPVideoSettings()[@"muted"],
        @"video_max": @([ud integerForKey:RPVideoMaxKey]),
        @"video_files": ({
            NSMutableArray *rows = [NSMutableArray array];
            for (NSString *path in RPVideoLocalFiles()) {
                NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
                double mb = [attr[NSFileSize] doubleValue] / (1024.0 * 1024.0);
                [rows addObject:@{ @"name": path.lastPathComponent ?: @"", @"mb": [NSString stringWithFormat:@"%.1f", mb] }];
            }
            rows;
        }),
        @"refresh_choices": choices,
        @"refresh_titles": RPLocalRefreshChoiceTitles(),
        @"pages": pages,
        @"web_pages": RPWebPagesLoad(),
        @"web_pages_max": @(RPWebPagesMaxCount()),
    };
}

- (BOOL)applySettingsDocument:(NSDictionary *)doc error:(NSString **)error {
    if (![doc isKindOfClass:[NSDictionary class]]) {
        if (error) *error = @"格式不对";
        return NO;
    }
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([doc[@"proxy"] isKindOfClass:[NSString class]]) [ud setObject:doc[@"proxy"] forKey:RPProxyDefaultsKey];
    if ([doc[@"proxy_user"] isKindOfClass:[NSString class]]) [ud setObject:RPString(doc[@"proxy_user"]) forKey:RPProxyUserKey];
    // Only replace the password when one was typed; "proxy_pass_clear" removes it.
    if ([doc[@"proxy_pass"] isKindOfClass:[NSString class]] && [doc[@"proxy_pass"] length]) [ud setObject:doc[@"proxy_pass"] forKey:RPProxyPassKey];
    if ([doc[@"proxy_pass_clear"] boolValue]) [ud removeObjectForKey:RPProxyPassKey];
    if ([doc[@"dwell_override"] respondsToSelector:@selector(integerValue)]) {
        NSInteger n = [doc[@"dwell_override"] integerValue];
        if (n < 0) n = 0;
        if (n > 3600) n = 3600;
        [ud setInteger:n forKey:RPDwellOverrideDefaultsKey];
    }
    if ([doc[@"ticker_url"] isKindOfClass:[NSString class]]) [ud setObject:doc[@"ticker_url"] forKey:RPTickerURLKey];
    if ([doc[@"ticker_proxy"] respondsToSelector:@selector(boolValue)]) [ud setBool:[doc[@"ticker_proxy"] boolValue] forKey:RPTickerProxyKey];
    if ([doc[@"ticker_refresh"] respondsToSelector:@selector(doubleValue)] && [doc[@"ticker_refresh"] doubleValue] >= 60) {
        [ud setDouble:[doc[@"ticker_refresh"] doubleValue] forKey:[RPRefreshPrefix stringByAppendingString:@"ticker"]];
    }
    if ([doc[@"vps_url"] isKindOfClass:[NSString class]]) [ud setObject:doc[@"vps_url"] forKey:RPVpsURLKey];
    if ([doc[@"vps_token"] isKindOfClass:[NSString class]]) [ud setObject:doc[@"vps_token"] forKey:RPVpsTokenKey];
    if ([doc[@"vps_proxy"] respondsToSelector:@selector(boolValue)]) [ud setBool:[doc[@"vps_proxy"] boolValue] forKey:RPVpsProxyKey];
    if ([doc[@"vps_refresh"] respondsToSelector:@selector(doubleValue)] && [doc[@"vps_refresh"] doubleValue] >= 60) {
        [ud setDouble:[doc[@"vps_refresh"] doubleValue] forKey:[RPRefreshPrefix stringByAppendingString:@"vps"]];
    }
    if ([doc[@"video_source"] isKindOfClass:[NSString class]]) {
        NSString *src = RPString(doc[@"video_source"]);
        if (![@[@"album", @"files", @"http"] containsObject:src]) src = @"album";
        [ud setObject:src forKey:RPVideoSourceKey];
    }
    if ([doc objectForKey:@"video_album"]) {
        NSString *aid = RPString(doc[@"video_album"]);
        if (aid.length) [ud setObject:aid forKey:RPVideoAlbumKey];
        else [ud removeObjectForKey:RPVideoAlbumKey];
    }
    if ([doc[@"video_http"] isKindOfClass:[NSString class]]) [ud setObject:RPString(doc[@"video_http"]) forKey:RPVideoHTTPKey];
    if ([doc[@"video_http_user"] isKindOfClass:[NSString class]]) [ud setObject:RPString(doc[@"video_http_user"]) forKey:RPVideoHTTPUserKey];
    if ([doc[@"video_http_pass"] isKindOfClass:[NSString class]] && [doc[@"video_http_pass"] length]) [ud setObject:doc[@"video_http_pass"] forKey:RPVideoHTTPPassKey];
    if ([doc[@"video_muted"] respondsToSelector:@selector(boolValue)]) RPVideoSetMuted([doc[@"video_muted"] boolValue]);
    if ([doc[@"video_max"] respondsToSelector:@selector(integerValue)]) {
        NSInteger mins = [doc[@"video_max"] integerValue];
        if (mins < 0) mins = 0;
        if (mins > 180) mins = 180;
        [ud setInteger:mins forKey:RPVideoMaxKey];
    }
    if ([doc[@"video_remove"] isKindOfClass:[NSArray class]]) {
        NSString *dir = RPVideoDirectory();
        for (id raw in doc[@"video_remove"]) {
            NSString *name = RPVideoSafeName([raw isKindOfClass:[NSString class]] ? raw : @"");
            if (name.length == 0) continue;
            [[NSFileManager defaultManager] removeItemAtPath:[dir stringByAppendingPathComponent:name] error:nil];
        }
    }
    if ([doc objectForKey:@"album_id"]) {
        NSString *aid = RPString(doc[@"album_id"]);
        if (aid.length) [ud setObject:aid forKey:RPAlbumDefaultsKey];
        else [ud removeObjectForKey:RPAlbumDefaultsKey];
    }
    NSMutableDictionary *known = [NSMutableDictionary dictionary];
    for (NSDictionary *meta in RPLocalPageCatalog()) if (meta[@"id"]) known[meta[@"id"]] = meta;
    NSArray *pages = [doc[@"pages"] isKindOfClass:[NSArray class]] ? doc[@"pages"] : @[];
    for (NSDictionary *page in pages) {
        if (![page isKindOfClass:[NSDictionary class]]) continue;
        NSString *pid = RPString(page[@"id"]);
        NSDictionary *meta = known[pid];
        if (!meta) continue;
        if ([page[@"enabled"] respondsToSelector:@selector(boolValue)]) {
            [ud setBool:[page[@"enabled"] boolValue] forKey:[RPPageEnabledPrefix stringByAppendingString:pid]];
        }
        if ([page[@"dwell"] respondsToSelector:@selector(integerValue)]) {
            NSInteger dwell = [page[@"dwell"] integerValue];
            if (dwell > 0) {
                if (dwell < 5) dwell = 5;
                if (dwell > 3600) dwell = 3600;
                [ud setInteger:dwell forKey:[RPDwellPrefix stringByAppendingString:pid]];
            }
        }
        if (RPLocalSourceDefaults()[pid]) {
            if ([page[@"url"] isKindOfClass:[NSString class]]) {
                [ud setObject:page[@"url"] forKey:[RPSourceURLPrefix stringByAppendingString:pid]];
            }
            if ([page[@"use_proxy"] respondsToSelector:@selector(boolValue)]) {
                [ud setBool:[page[@"use_proxy"] boolValue] forKey:[RPSourceProxyPrefix stringByAppendingString:pid]];
            }
            if ([pid isEqualToString:@"hello"]) {
                if ([page[@"api_key"] isKindOfClass:[NSString class]]) [ud setObject:page[@"api_key"] forKey:RPHelloKeyKey];
                if ([page[@"model"] isKindOfClass:[NSString class]]) [ud setObject:page[@"model"] forKey:RPHelloModelKey];
            }
            if (![meta[@"refresh_shared"] boolValue] && ![meta[@"refresh_period"] boolValue] && [page[@"refresh"] respondsToSelector:@selector(doubleValue)]) {
                NSString *feed = RPLocalFeedKeyForPage(pid);
                double sec = [page[@"refresh"] doubleValue];
                if (feed.length && sec >= 60) [ud setDouble:sec forKey:[RPRefreshPrefix stringByAppendingString:feed]];
            }
        }
    }
    // Only replace when the browser payload includes web_pages (avoid wiping on old clients).
    if ([doc objectForKey:@"web_pages"]) {
        NSArray *webPages = [doc[@"web_pages"] isKindOfClass:[NSArray class]] ? doc[@"web_pages"] : @[];
        RPWebPagesSave(webPages);
    }
    [ud synchronize];
    [self invalidateForSettingsChange];
    [self appendLog:@"设置" status:@"ok" detail:@"已从浏览器保存"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"RPRemoteSettingsChanged" object:nil];
    });
    return YES;
}

- (BOOL)readClient:(int)client first:(NSString **)firstOut body:(NSData **)bodyOut {
    NSMutableData *buf = [NSMutableData data];
    char tmp[16384];
    NSUInteger headerEnd = NSNotFound;
    NSInteger contentLength = 0;
    // Read until the whole body has arrived. The old 30-recv cap cut 100 KB video
    // chunks short (recv often returns one ~1.4 KB segment). SO_RCVTIMEO (8 s) and
    // the 260 KB cap below still bound the loop.
    // The server is single-threaded: cap the whole read at 30 s so a client
    // trickling a byte every few seconds cannot hold it indefinitely.
    NSTimeInterval giveUpAt = [NSDate timeIntervalSinceReferenceDate] + 30;
    for (;;) {
        if ([NSDate timeIntervalSinceReferenceDate] > giveUpAt) break;
        ssize_t n = recv(client, tmp, sizeof(tmp), 0);
        if (n < 0) break;
        if (n == 0) break;
        [buf appendBytes:tmp length:(NSUInteger)n];
        if (headerEnd == NSNotFound) {
            const unsigned char *bytes = buf.bytes;
            for (NSUInteger k = 0; k + 3 < buf.length; k++) {
                if (bytes[k] == '\r' && bytes[k + 1] == '\n' && bytes[k + 2] == '\r' && bytes[k + 3] == '\n') {
                    headerEnd = k + 4;
                    NSString *headers = [[NSString alloc] initWithBytes:bytes length:k encoding:NSUTF8StringEncoding] ?: @"";
                    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"Content-Length:\\s*(\\d+)" options:NSRegularExpressionCaseInsensitive error:nil];
                    NSTextCheckingResult *m = [re firstMatchInString:headers options:0 range:NSMakeRange(0, headers.length)];
                    contentLength = (m.numberOfRanges > 1) ? [[headers substringWithRange:[m rangeAtIndex:1]] integerValue] : 0;
                    // Refuse rather than clamp: a clamped length would let an oversized
                    // body through the short-body check below, cut at 200 KB.
                    if (contentLength > 200000 || contentLength < 0) return NO;
                    break;
                }
            }
        }
        if (headerEnd != NSNotFound && buf.length >= headerEnd + (NSUInteger)contentLength) break;
        if (buf.length > 260000) break;
    }
    if (buf.length == 0 || headerEnd == NSNotFound) return NO;
    NSString *head = [[NSString alloc] initWithBytes:buf.bytes length:MIN(headerEnd, buf.length) encoding:NSUTF8StringEncoding] ?: @"";
    NSRange lineEnd = [head rangeOfString:@"\r\n"];
    NSString *first = lineEnd.location == NSNotFound ? head : [head substringToIndex:lineEnd.location];
    NSData *body = [NSData data];
    if (headerEnd < buf.length) {
        NSUInteger len = MIN((NSUInteger)contentLength, buf.length - headerEnd);
        body = [buf subdataWithRange:NSMakeRange(headerEnd, len)];
    }
    // A short body means the client stalled or hung up; refuse it rather than
    // writing a truncated chunk into a video file.
    if ((NSInteger)body.length < contentLength) return NO;
    if (firstOut) *firstOut = first;
    if (bodyOut) *bodyOut = body;
    return first.length > 0;
}

- (void)sendAll:(int)client data:(NSData *)data {
    const char *p = data.bytes;
    size_t left = data.length;
    while (left) {
        ssize_t n = send(client, p, left, 0);
        if (n <= 0) return;
        p += n;
        left -= (size_t)n;
    }
}

- (void)replyClient:(int)client code:(int)code type:(NSString *)type data:(NSData *)data {
    NSString *reason = code == 200 ? @"OK" : @"Bad Request";
    NSString *head = [NSString stringWithFormat:@"HTTP/1.1 %d %@\r\nContent-Type: %@\r\nConnection: close\r\nContent-Length: %lu\r\n\r\n", code, reason, type ?: @"text/plain", (unsigned long)data.length];
    [self sendAll:client data:[head dataUsingEncoding:NSUTF8StringEncoding]];
    if (data.length) [self sendAll:client data:data];
}


- (NSString *)lanIPv4 {
    struct ifaddrs *ifs = NULL;
    NSString *found = @"";
    if (getifaddrs(&ifs) != 0) return found;
    for (struct ifaddrs *p = ifs; p; p = p->ifa_next) {
        if (!p->ifa_addr || p->ifa_addr->sa_family != AF_INET) continue;
        NSString *name = [NSString stringWithUTF8String:p->ifa_name ?: ""];
        if ([name hasPrefix:@"lo"]) continue;
        char buf[INET_ADDRSTRLEN] = {0};
        inet_ntop(AF_INET, &((struct sockaddr_in *)p->ifa_addr)->sin_addr, buf, sizeof(buf));
        found = [NSString stringWithUTF8String:buf] ?: @"";
        if ([name hasPrefix:@"en"]) break;
    }
    freeifaddrs(ifs);
    return found;
}

- (NSString *)query:(NSString *)first key:(NSString *)key {
    NSRange q = [first rangeOfString:@"?"];
    if (q.location == NSNotFound) return @"";
    NSString *rest = [first substringFromIndex:q.location + 1];
    NSRange sp = [rest rangeOfString:@" "];
    if (sp.location != NSNotFound) rest = [rest substringToIndex:sp.location];
    for (NSString *pair in [rest componentsSeparatedByString:@"&"]) {
        NSRange eq = [pair rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;
        NSString *k = [pair substringToIndex:eq.location];
        if (![k isEqualToString:key]) continue;
        NSString *v = [pair substringFromIndex:eq.location + 1];
        v = [v stringByRemovingPercentEncoding] ?: v;
        return [v stringByReplacingOccurrencesOfString:@"+" withString:@" "];
    }
    return @"";
}

- (BOOL)writeVideoChunk:(NSData *)body name:(NSString *)name seq:(NSInteger)seq last:(BOOL)last error:(NSString **)error {
    if (name.length == 0) {
        if (error) *error = @"文件名需要以 mp4、mov 或 m4v 结尾";
        return NO;
    }
    if (seq < 0 || seq > 4000) {
        if (error) *error = @"分片序号不对";
        return NO;
    }
    NSString *dir = RPVideoDirectory();
    NSString *part = [dir stringByAppendingPathComponent:[name stringByAppendingString:@".part"]];
    NSString *dest = [dir stringByAppendingPathComponent:name];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (seq == 0) {
        [fm removeItemAtPath:part error:nil];
        if (RPVideoLocalFiles().count >= 30 && ![fm fileExistsAtPath:dest]) {
            if (error) *error = @"最多保存 30 个视频";
            return NO;
        }
        [fm createFileAtPath:part contents:nil attributes:nil];
    }
    if (![fm fileExistsAtPath:part]) {
        if (error) *error = @"上传中断了，请重试";
        return NO;
    }
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:part];
    if (!fh) {
        if (error) *error = @"写不进去";
        return NO;
    }
    @try {
        [fh seekToEndOfFile];
        if (body.length) [fh writeData:body];
    } @catch (NSException *ex) {
        [fh closeFile];
        [fm removeItemAtPath:part error:nil];
        if (error) *error = @"写入失败";
        return NO;
    }
    [fh closeFile];
    NSDictionary *attr = [fm attributesOfItemAtPath:part error:nil];
    if ([attr[NSFileSize] unsignedLongLongValue] > 200ull * 1024ull * 1024ull) {
        [fm removeItemAtPath:part error:nil];
        if (error) *error = @"单个文件请小于 200MB";
        return NO;
    }
    if (!last) return YES;
    [fm removeItemAtPath:dest error:nil];
    if (![fm moveItemAtPath:part toPath:dest error:nil]) {
        if (error) *error = @"保存失败";
        return NO;
    }
    [self appendLog:@"视频" status:@"ok" detail:[NSString stringWithFormat:@"已上传 %@", name]];
    return YES;
}

- (void)runStatusServer {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return;
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(8090);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 || listen(fd, 2) < 0) {
        close(fd);
        [self appendLog:@"状态服务" status:@"fail" detail:@"8090 端口没有打开"];
        return;
    }
    [self appendLog:@"状态服务" status:@"ok" detail:[NSString stringWithFormat:@"设置页 http://%@:8090/setup", [self lanIPv4]]];
    for (;;) {
        int client = accept(fd, NULL, NULL);
        if (client < 0) continue;
        // This thread never returns to a run loop, so without a pool every request's
        // strings, JSON and /shot PNGs (several MB) stayed alive for the app's lifetime.
        @autoreleasepool {
            [self serveClient:client];
        }
    }
}

- (void)serveClient:(int)client {
    int yes = 1;
    setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    struct timeval tv;
    tv.tv_sec = 8;
    tv.tv_usec = 0;
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
    for (int once = 0; once < 1; once++) {
        NSString *first = nil;
        NSData *reqBody = nil;
        if (![self readClient:client first:&first body:&reqBody]) {
            close(client);
            continue;
        }
        if ([first hasPrefix:@"GET /setup.json"]) {
            NSDictionary *doc = [self settingsDocument];
            NSData *bytes = [NSJSONSerialization dataWithJSONObject:doc options:0 error:nil];
            if (!bytes) bytes = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
            [self replyClient:client code:200 type:@"application/json; charset=utf-8" data:bytes];
            close(client);
            continue;
        }
        if ([first hasPrefix:@"GET /setup"]) {
            NSData *bytes = [RPSetupHTML() dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
            [self replyClient:client code:200 type:@"text/html; charset=utf-8" data:bytes];
            close(client);
            continue;
        }
        if ([first hasPrefix:@"POST /video-chunk"]) {
            NSString *name = RPVideoSafeName([self query:first key:@"name"]);
            NSInteger seq = [[self query:first key:@"seq"] integerValue];
            BOOL last = [[self query:first key:@"last"] integerValue] != 0;
            NSString *why = nil;
            BOOL ok = name.length && [self writeVideoChunk:reqBody name:name seq:seq last:last error:&why];
            NSString *text = ok ? @"ok" : (why.length ? why : @"上传失败");
            [self replyClient:client code:(ok ? 200 : 400) type:@"text/plain; charset=utf-8" data:[text dataUsingEncoding:NSUTF8StringEncoding]];
            close(client);
            continue;
        }
        if ([first hasPrefix:@"POST /setup"]) {
            NSError *jsonErr = nil;
            id obj = reqBody.length ? [NSJSONSerialization JSONObjectWithData:reqBody options:0 error:&jsonErr] : nil;
            NSString *why = nil;
            BOOL ok = !jsonErr && [obj isKindOfClass:[NSDictionary class]] && [self applySettingsDocument:obj error:&why];
            NSString *text = ok ? @"ok" : (why.length ? why : @"保存失败");
            [self replyClient:client code:(ok ? 200 : 400) type:@"text/plain; charset=utf-8" data:[text dataUsingEncoding:NSUTF8StringEncoding]];
            close(client);
            continue;
        }
        if ([first hasPrefix:@"GET /tell"]) {
            NSString *text = @"";
            NSRange mark = [first rangeOfString:@"t="];
            if (mark.location != NSNotFound) {
                text = [first substringFromIndex:mark.location + 2];
                NSRange stop = [text rangeOfString:@" "];
                if (stop.location != NSNotFound) text = [text substringToIndex:stop.location];
                stop = [text rangeOfString:@"&"];
                if (stop.location != NSNotFound) text = [text substringToIndex:stop.location];
                text = [text stringByReplacingOccurrencesOfString:@"+" withString:@" "];
                text = [text stringByRemovingPercentEncoding] ?: text;
                text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
            if (text.length > 120) text = [[text substringToIndex:120] stringByAppendingString:@"…"];
            NSString *reply = @"empty";
            if (text.length) {
                [self addNotice:text];
                [self appendLog:@"走马灯" status:@"ok" detail:@"收到一条提醒"];
                [self emitName:@"走马灯" status:@"ok" detail:@"收到一条提醒" includeState:NO];
                reply = @"ok";
            }
            NSData *bytes = [reply dataUsingEncoding:NSUTF8StringEncoding];
            NSString *head = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\nContent-Length: %lu\r\n\r\n", (unsigned long)bytes.length];
            NSData *hb = [head dataUsingEncoding:NSUTF8StringEncoding];
            [self sendAll:client data:hb];
            [self sendAll:client data:bytes];
            close(client);
            continue;
        }
        if ([first hasPrefix:@"GET /shot"] || [first hasPrefix:@"GET /pages"]) {
            NSInteger jump = -1;
            NSRange mark = [first rangeOfString:@"i="];
            if (mark.location != NSNotFound) jump = [[first substringFromIndex:mark.location + 2] integerValue];
            NSMutableDictionary *box = [NSMutableDictionary dictionary];
            dispatch_sync(dispatch_get_main_queue(), ^{
                [[NSNotificationCenter defaultCenter] postNotificationName:@"RPCapturePage" object:nil userInfo:@{ @"index": @(jump), @"box": box }];
            });
            NSData *png = [first hasPrefix:@"GET /shot"] ? box[@"png"] : nil;
            NSString *text = box[@"titles"] ?: @"";
            if ([first hasPrefix:@"GET /pages"]) {
                text = [NSString stringWithFormat:@"%@\n\n%@", box[@"here"] ?: @"", text];
                png = nil;
            }
            if (png.length) {
                NSString *head = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nConnection: close\r\nContent-Length: %lu\r\n\r\n", (unsigned long)png.length];
                NSData *hb = [head dataUsingEncoding:NSUTF8StringEncoding];
                [self sendAll:client data:hb];
                [self sendAll:client data:png];
            } else {
                NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
                NSString *head = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\nContent-Length: %lu\r\n\r\n", (unsigned long)bytes.length];
                NSData *hb = [head dataUsingEncoding:NSUTF8StringEncoding];
                [self sendAll:client data:hb];
                if (bytes.length) [self sendAll:client data:bytes];
            }
            close(client);
            continue;
        }
        NSArray *lines = [self activityLog];
        NSString *body = lines.count ? [[lines reverseObjectEnumerator].allObjects componentsJoinedByString:@"\n"] : @"还没有更新记录";
        body = [body stringByAppendingString:@"\n"];
        NSData *bytes = [body dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
        NSString *head = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\nContent-Length: %lu\r\n\r\n", (unsigned long)bytes.length];
        NSData *hb = [head dataUsingEncoding:NSUTF8StringEncoding];
        [self sendAll:client data:hb];
        if (bytes.length) [self sendAll:client data:bytes];
        close(client);
    }
}

- (void)emitName:(NSString *)name status:(NSString *)status detail:(NSString *)detail includeState:(BOOL)includeState {
    NSMutableDictionary *info = [@{ @"name": name ?: @"", @"status": status ?: @"", @"detail": detail ?: @"" } mutableCopy];
    if (includeState) info[@"state"] = [self assemble];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:RPFeedProgressNotification object:self userInfo:info];
    });
}

- (void)appendLog:(NSString *)name status:(NSString *)status detail:(NSString *)detail {
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"HH:mm:ss";
    });
    // appendLog runs on several threads; NSDateFormatter is thread-safe on iOS 7+.
    fmt.timeZone = [NSTimeZone localTimeZone];
    NSString *mark = @"成功";
    if ([status isEqualToString:@"fail"]) mark = @"失败";
    else if ([status isEqualToString:@"skip"]) mark = @"跳过";
    NSString *line = [NSString stringWithFormat:@"%@  %@  %@  %@", [fmt stringFromDate:[NSDate date]], name ?: @"", mark, detail ?: @""];
    @synchronized (self) {
        [self.logLines addObject:line];
        while (self.logLines.count > 80) [self.logLines removeObjectAtIndex:0];
    }
}

- (NSArray *)activityLog {
    @synchronized (self) { return [self.logLines copy]; }
}

- (NSArray *)tickerMessages {
    id payload = [self payload:@"ticker"];
    return [payload isKindOfClass:[NSArray class]] ? payload : @[];
}

- (void)refreshWithCompletion:(void (^)(NSDictionary *, NSError *))completion {
    @synchronized (self) {
        if (self.refreshing) {
            // A pass should finish in a few minutes now that reads time out. If one
            // has been running for over 10 minutes, assume it is stuck and start fresh;
            // otherwise the panel would never update again.
            NSTimeInterval age = [NSDate timeIntervalSinceReferenceDate] - self.refreshStartedAt;
            if (age < 600) return;
            [self appendLog:@"刷新" status:@"fail" detail:[NSString stringWithFormat:@"上一轮卡了 %.0f 分钟，重新开始", age / 60.0]];
        }
        self.refreshing = YES;
        self.refreshStartedAt = [NSDate timeIntervalSinceReferenceDate];
        self.refreshGeneration += 1;
    }
    NSUInteger generation = self.refreshGeneration;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self runRefreshPass:completion generation:generation];
    });
}

/** One full pass. Runs on a background queue with `refreshing` already set. */
- (void)runRefreshPass:(void (^)(NSDictionary *, NSError *))completion generation:(NSUInteger)generation {
    for (;;) {
        NSMutableArray *jobs = [NSMutableArray array];
        void (^add)(NSString *, NSString *, NSTimeInterval, BOOL (^)(void)) = ^(NSString *name, NSString *key, NSTimeInterval ttl, BOOL (^work)(void)) {
            if ([self fresh:key ttl:ttl]) return;
            if ([self backingOff:key ttl:ttl]) return;
            [jobs addObject:@{ @"name": name, @"key": key, @"work": [work copy] }];
        };
        if ([self pageEnabled:@"weather"]) {
            add(@"天气", @"weather", RPLocalTTL(@"weather"), ^{ return [self fetchWeather]; });
            add(@"VPS", @"vps", RPLocalTTL(@"vps"), ^{ return [self fetchVPS]; });
        }
        if ([self pageEnabled:@"print"]) add(@"打印机", @"print", RPLocalTTL(@"print"), ^{ return [self fetchPrint]; });
        if ([self pageEnabled:@"daily-news"]) add(@"每日新闻", @"daily", RPLocalTTL(@"daily"), ^{ return [self fetchDaily]; });
        if ([self pageEnabled:@"hello"]) add(@"问候", @"hello", RPLocalTTL(@"hello"), ^{ return [self fetchHello]; });
        if ([self pageEnabled:@"github-news"]) add(@"GitHub", @"github", RPLocalTTL(@"github"), ^{ return [self fetchGitHub]; });
        if (![self pageEnabled:@"x-news"]) {
            [self appendLog:@"X" status:@"skip" detail:@"页面开关是关的"];
        } else if ([self fresh:@"x" ttl:RPLocalTTL(@"x")]) {
            [self appendLog:@"X" status:@"skip" detail:@"未到两小时"];
        } else {
            add(@"X", @"x", RPLocalTTL(@"x"), ^{ return [self fetchX]; });
        }
        if ([self pageEnabled:@"xiaohongshu-hot"]) add(@"小红书", @"xhs", RPLocalTTL(@"xhs"), ^{ return [self fetchXiaohongshu]; });
        if ([self pageEnabled:@"bilibili-hot"]) add(@"哔哩哔哩", @"bili", RPLocalTTL(@"bili"), ^{ return [self fetchBilibili]; });
        if ([self pageEnabled:@"stocks-cn"]) add(@"股票", @"stocks", RPLocalTTL(@"stocks"), ^{ return [self fetchStocks]; });
        if ([self pageEnabled:@"crypto"]) add(@"比特币", @"crypto", RPLocalTTL(@"crypto"), ^{ return [self fetchCrypto]; });
        if ([self pageEnabled:@"movie-now-showing"]) add(@"电影", @"movies", RPLocalTTL(@"movies"), ^{ return [self fetchMovies]; });
        if ([self pageEnabled:@"steam-new-releases"] || [self pageEnabled:@"steam-new-releases-2"]) {
            add(@"Steam", @"steam", RPLocalTTL(@"steam"), ^{ return [self fetchSteam]; });
        }
        if ([self pageEnabled:@"gamer520-pc-latest"]) add(@"PC游戏", @"pc", RPLocalTTL(@"pc"), ^{ return [self fetchGames:@"gamer520-pc-latest" key:@"pc"]; });
        if ([self pageEnabled:@"gamer520-switch-latest"]) add(@"Switch", @"switch", RPLocalTTL(@"switch"), ^{ return [self fetchGames:@"gamer520-switch-latest" key:@"switch"]; });
        if ([self pageEnabled:@"ps5-games-latest"]) add(@"PS5", @"ps5", RPLocalTTL(@"ps5"), ^{ return [self fetchGames:@"ps5-games-latest" key:@"ps5"]; });
        if ([self pageEnabled:@"schedule"] && [self sourceURL:@"schedule"].length) add(@"日程", @"schedule", RPLocalTTL(@"schedule"), ^{ return [self fetchSchedule]; });
        NSString *tickerURL = RPString([[NSUserDefaults standardUserDefaults] stringForKey:RPTickerURLKey]);
        if (tickerURL.length) add(@"走马灯", @"ticker", RPLocalTTL(@"ticker"), ^{ return [self fetchTicker]; });

        for (NSDictionary *job in jobs) {
            @autoreleasepool {
                NSString *name = job[@"name"];
                NSString *key = job[@"key"];
                BOOL (^work)(void) = job[@"work"];
                self.fetchError = nil;
                self.fetchNote = nil;
                [self emitName:name status:@"start" detail:@"" includeState:NO];
                BOOL ok = work ? work() : NO;
                if (!ok) {
                    [self noteFailure:key];
                } else {
                    @synchronized (self) { [self.failStreak removeObjectForKey:key]; }
                }
                NSString *status = ok ? (self.fetchNote.length ? @"skip" : @"ok") : @"fail";
                NSString *detail = ok ? (self.fetchNote.length ? self.fetchNote : @"完成") : (self.fetchError.length ? self.fetchError : @"失败");
                [self appendLog:name status:status detail:detail];
                [self emitName:name status:status detail:detail includeState:(ok && self.fetchNote.length == 0)];
            }
        }
        // saveDisk is a no-op unless store: ran, so idle 30 s polls no longer rewrite the plist.
        [self saveDisk];
        BOOL rerun = NO;
        BOOL superseded = NO;
        @synchronized (self) {
            // The watchdog may have started a newer pass while this one was stuck.
            // Only the current generation may rerun or clear `refreshing`.
            superseded = generation != self.refreshGeneration;
            if (!superseded) {
                // Settings changed mid-pass: go again without dropping `refreshing`,
                // so a main-thread poll cannot start a second loop alongside this one.
                // Checked and cleared under one lock so a change cannot slip between.
                rerun = self.settingsRerun;
                self.settingsRerun = NO;
                if (rerun) self.refreshStartedAt = [NSDate timeIntervalSinceReferenceDate];
                else self.refreshing = NO;
            }
        }
        if (superseded) return;
        if (rerun) continue;
        NSDictionary *state = [self assemble];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(state, nil);
        });
        return;
    }
}

/** Prepend a pushed message to the 公告 list. /tell used to replace the whole list,
    so a second push erased the first and the ✉ list never held more than one. The
    time goes into the body so two identical texts still count as two messages. */
- (void)addNotice:(NSString *)text {
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"M月d日 HH:mm:ss";
    });
    NSMutableArray *list = [[self tickerMessages] mutableCopy] ?: [NSMutableArray array];
    [list insertObject:@{ @"title": text, @"body": [NSString stringWithFormat:@"%@\n%@", [fmt stringFromDate:[NSDate date]], text] } atIndex:0];
    while (list.count > 20) [list removeLastObject];
    [self store:@"ticker" payload:list];
    [self saveDisk];
}

- (void)postTestNotice:(NSString *)text {
    [self addNotice:text.length ? text : @"测试提醒"];
    [self appendLog:@"走马灯" status:@"ok" detail:@"设置里发送了一条测试提醒"];
}

/** Called after the user saves settings on the iPad itself. */
- (void)invalidateForSettingsChange {
    [self markCacheStale];
    @synchronized (self) {
        [self.failedAt removeAllObjects];
        [self.failStreak removeAllObjects];
        if (self.refreshing) self.settingsRerun = YES;
    }
}

- (BOOL)fetchWeather {
    NSString *city = [self sourceURL:@"weather"];
    if (city.length == 0 || [city hasPrefix:@"http"]) city = @"Shanghai";
    NSString *proxy = [self proxyFor:@"weather"];
    NSString *geoURL = [NSString stringWithFormat:@"https://geocoding-api.open-meteo.com/v1/search?name=%@&count=1&language=zh&format=json", [city stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    NSData *geoData = [self syncGET:geoURL proxy:proxy headers:nil];
    NSDictionary *geo = [NSJSONSerialization JSONObjectWithData:geoData ?: [NSData data] options:0 error:nil];
    NSDictionary *hit = [geo[@"results"] isKindOfClass:[NSArray class]] ? [geo[@"results"] firstObject] : nil;
    if (![hit isKindOfClass:[NSDictionary class]]) {
        if (self.fetchError.length == 0) self.fetchError = @"没有找到这个城市";
        return NO;
    }
    NSString *forecast = [NSString stringWithFormat:@"https://api.open-meteo.com/v1/forecast?latitude=%@&longitude=%@&current=temperature_2m,weather_code,wind_speed_10m&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto", hit[@"latitude"], hit[@"longitude"]];
    NSData *body = [self syncGET:forecast proxy:proxy headers:nil];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body ?: [NSData data] options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (self.fetchError.length == 0) self.fetchError = @"天气数据无法解析";
        return NO;
    }
    NSDictionary *cur = json[@"current"] ?: @{};
    NSDictionary *daily = json[@"daily"] ?: @{};
    NSInteger code = [cur[@"weather_code"] integerValue];
    NSString *desc = RPWeatherText(code);
    NSArray *dates = daily[@"time"] ?: @[];
    NSArray *maxs = daily[@"temperature_2m_max"] ?: @[];
    NSArray *mins = daily[@"temperature_2m_min"] ?: @[];
    NSArray *codes = daily[@"weather_code"] ?: @[];
    NSMutableArray *weekly = [NSMutableArray array];
    NSUInteger n = MIN(MIN(dates.count, maxs.count), MIN(mins.count, codes.count));
    for (NSUInteger i = 0; i < MIN(n, 6); i++) {
        NSString *dayDesc = RPWeatherText([codes[i] integerValue]);
        [weekly addObject:@{
            @"weekday": RPWeekday([NSString stringWithFormat:@"%@", dates[i]]),
            @"description": dayDesc,
            @"temp_min": mins[i],
            @"temp_max": maxs[i],
            @"icon": RPWeatherIcon(dayDesc),
        }];
    }
    NSArray *min0 = mins;
    NSArray *max0 = maxs;
    [self store:@"weather" payload:@{
        @"city": hit[@"name"] ?: city,
        @"temperature": cur[@"temperature_2m"] ?: @"--",
        @"description": desc,
        @"temp_min": min0.count ? min0[0] : @"-",
        @"temp_max": max0.count ? max0[0] : @"-",
        @"wind_speed": cur[@"wind_speed_10m"] ?: @"-",
        @"icon": RPWeatherIcon(desc),
        @"weekly": weekly,
    }];
    return YES;
}

- (BOOL)fetchVPS {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *url = RPString([ud stringForKey:RPVpsURLKey]);
    if (url.length == 0) url = RPLocalDefaultVPSURL();
    NSString *token = RPString([ud stringForKey:RPVpsTokenKey]);
    if (token.length == 0) token = RPLocalDefaultVPSToken();
    BOOL useProxy = [ud objectForKey:RPVpsProxyKey] ? [ud boolForKey:RPVpsProxyKey] : NO;
    NSString *proxy = nil;
    if (useProxy) {
        proxy = RPConfiguredProxy();
    }
    NSData *data = [self syncGET:url proxy:proxy headers:@{ @"Authorization": [NSString stringWithFormat:@"Bearer %@", token] }];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (self.fetchError.length == 0) self.fetchError = @"VPS 数据无法解析";
        return NO;
    }
    NSDictionary *monthly = [json[@"monthly"] isKindOfClass:[NSDictionary class]] ? json[@"monthly"] : @{};
    NSDictionary *alert = [json[@"alert"] isKindOfClass:[NSDictionary class]] ? json[@"alert"] : @{};
    NSDictionary *cycle = [json[@"cycle"] isKindOfClass:[NSDictionary class]] ? json[@"cycle"] : @{};
    NSString *startFull = [NSString stringWithFormat:@"%@", cycle[@"start"] ?: @""];
    NSString *endFull = [NSString stringWithFormat:@"%@", cycle[@"end"] ?: @""];
    NSString *start = startFull.length > 10 ? [startFull substringToIndex:10] : startFull;
    NSString *end = endFull.length > 10 ? [endFull substringToIndex:10] : endFull;
    [self store:@"vps" payload:@{
        @"used": [NSString stringWithFormat:@"%@", monthly[@"used_human"] ?: @"-"],
        @"remain": [NSString stringWithFormat:@"%@", monthly[@"remaining_human"] ?: @"-"],
        @"percent": monthly[@"percent_used"] ?: @0,
        @"cycle": [NSString stringWithFormat:@"%@ → %@", start, end],
        @"status": [NSString stringWithFormat:@"%@", alert[@"message"] ?: alert[@"level"] ?: @"-"],
    }];
    return YES;
}

- (NSString *)completeChat:(NSString *)prompt limit:(NSInteger)limit {
    NSString *base = [self sourceURL:@"hello"];
    if (base.length == 0) base = @"https://apiclaude.cc";
    NSString *url = base;
    if ([url rangeOfString:@"chat/completions"].location == NSNotFound) {
        while ([url hasSuffix:@"/"]) url = [url substringToIndex:url.length - 1];
        url = [url hasSuffix:@"/v1"] ? [url stringByAppendingString:@"/chat/completions"] : [url stringByAppendingString:@"/v1/chat/completions"];
    }
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *key = RPString([ud stringForKey:RPHelloKeyKey]);
    if (key.length == 0) key = RPLocalDefaultHelloKey();
    if (key.length == 0) {
        self.fetchError = @"没有填写接口密钥";
        return nil;
    }
    NSString *model = RPString([ud stringForKey:RPHelloModelKey]);
    if (model.length == 0) model = RPLocalDefaultHelloModel();
    NSDictionary *payload = @{
        @"model": model,
        @"messages": @[ @{ @"role": @"user", @"content": prompt ?: @"" } ],
    };
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    NSData *data = [self syncPOST:url body:body proxy:[self proxyFor:@"hello"] headers:@{ @"Authorization": [NSString stringWithFormat:@"Bearer %@", key] }];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:nil];
    if ([json[@"error"] isKindOfClass:[NSDictionary class]]) {
        NSString *msg = RPString(json[@"error"][@"message"]);
        self.fetchError = msg.length ? msg : @"接口拒绝了";
        return nil;
    }
    NSArray *choices = [json[@"choices"] isKindOfClass:[NSArray class]] ? json[@"choices"] : nil;
    NSDictionary *message = [choices.firstObject isKindOfClass:[NSDictionary class]] ? choices.firstObject[@"message"] : nil;
    id raw = [message isKindOfClass:[NSDictionary class]] ? message[@"content"] : nil;
    NSString *text = [raw isKindOfClass:[NSString class]] ? raw : @"";
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([text hasPrefix:@"「"] && [text hasSuffix:@"」"] && text.length > 2) text = [text substringWithRange:NSMakeRange(1, text.length - 2)];
    if ([text hasPrefix:@"\""] && [text hasSuffix:@"\""] && text.length > 2) text = [text substringWithRange:NSMakeRange(1, text.length - 2)];
    if (limit > 0 && (NSInteger)text.length > limit) text = [[text substringToIndex:limit] stringByAppendingString:@"…"];
    if (text.length == 0) {
        if (self.fetchError.length == 0) self.fetchError = @"没有读到回复";
        return nil;
    }
    return text;
}

- (BOOL)fetchHello {
    NSString *label = nil;
    NSString *slot = RPHelloSlot(&label);
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
    fmt.dateFormat = @"M月d日 EEEE HH:mm";
    NSString *when = [fmt stringFromDate:[NSDate date]];
    NSString *prompt = [NSString stringWithFormat:@"现在是%@，时段是%@。请给家里的人写一句问候，中文，28到46个字，具体、温和，不要鸡汤口号，不要 emoji，不要引号，不要换行。只输出这一句话。", when, label ?: @"现在"];
    NSString *text = [[self completeChat:prompt limit:80] stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    if (text.length == 0) {
        if (self.fetchError.length == 0) self.fetchError = @"没有读到问候";
        return NO;
    }
    [self store:@"hello" payload:@{ @"text": text, @"slot": slot, @"period": label ?: @"", @"source": [self helloSourceTag] }];
    return YES;
}

/** Which endpoint/key/model wrote the greeting. A change in settings makes the cached line stale. */
- (NSString *)helloSourceTag {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *key = RPString([ud stringForKey:RPHelloKeyKey]);
    if (key.length == 0) key = RPLocalDefaultHelloKey();
    NSString *model = RPString([ud stringForKey:RPHelloModelKey]);
    if (model.length == 0) model = RPLocalDefaultHelloModel();
    // Only the key's length and tail, so the secret itself is not copied into the cache file.
    NSString *keyTag = key.length > 4 ? [NSString stringWithFormat:@"%lu:%@", (unsigned long)key.length, [key substringFromIndex:key.length - 4]] : key;
    return [NSString stringWithFormat:@"%@|%@|%@", [self sourceURL:@"hello"], model, keyTag];
}

- (BOOL)fetchDaily {
    NSArray *items = RPParseRSS([self syncGET:[self sourceURL:@"daily-news"] proxy:[self proxyFor:@"daily-news"] headers:nil], 8);
    if (!items.count) {
        if (self.fetchError.length == 0) self.fetchError = @"没有解析到新闻";
        return NO;
    }
    [self store:@"daily" payload:items];
    return YES;
}

- (BOOL)fetchX {
    NSString *url = [self sourceURL:@"x-news"];
    if (url.length == 0) url = RPLocalSourceDefaults()[@"x-news"];
    NSString *proxy = [self proxyFor:@"x-news"];
    if (proxy.length == 0) proxy = RPConfiguredProxy();
    NSDictionary *browser = @{ @"User-Agent": @"Mozilla/5.0 (iPad; CPU OS 9_3_6 like Mac OS X) AppleWebKit/601.1.46 (KHTML, like Gecko) Version/9.0 Mobile/13G37 Safari/601.1" };
    BOOL trends = [url rangeOfString:@"getdaytrends.com"].location != NSNotFound;
    NSData *data = [self syncGET:url proxy:proxy headers:browser];
    BOOL markdown = NO;
    if (trends && data.length < 500) {
        NSString *jina = [@"https://r.jina.ai/" stringByAppendingString:url];
        NSData *via = [self syncGET:jina proxy:proxy headers:browser];
        if (via.length > data.length) {
            data = via;
            markdown = YES;
        }
    }
    NSArray *items = markdown ? RPParseXMarkdown(data, 12) : (trends ? RPParseXTrends(data, 12) : RPParseRSS(data, 12));
    if (!items.count) {
        if (self.fetchError.length == 0) self.fetchError = @"没有解析到热门";
        return NO;
    }
    NSString *place = @"热门";
    if ([url rangeOfString:@"united-states"].location != NSNotFound) place = @"美国区";
    else if ([url rangeOfString:@"getdaytrends.com"].location != NSNotFound) place = @"该地区";
    if (trends) {
        NSMutableArray *titles = [NSMutableArray array];
        for (NSDictionary *item in items) {
            NSString *title = RPString(item[@"title"]);
            if (title.length) [titles addObject:title];
        }
        NSString *prompt = [NSString stringWithFormat:@"把下面每条 X 热门话题写成一行，格式严格为：中文话题｜一句话说明。说明不超过22个字，告诉家里人这条在聊什么。保持 %lu 行，一行一条，不要编号，不要空行。已经是中文的话题名保持原样，后面仍要有说明。\n%@", (unsigned long)titles.count, [titles componentsJoinedByString:@"\n"]];
        NSString *savedError = self.fetchError;
        NSString *translated = [self completeChat:prompt limit:1200];
        self.fetchError = savedError;
        NSMutableArray *lines = [NSMutableArray array];
        for (NSString *rawLine in [translated componentsSeparatedByString:@"\n"]) {
            NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([line hasPrefix:@"-"]) line = [[line substringFromIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSRange dot = [line rangeOfString:@". "];
            if (dot.location != NSNotFound && dot.location <= 2) {
                NSString *head = [line substringToIndex:dot.location];
                if (head.length && [head rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location == NSNotFound) {
                    line = [line substringFromIndex:dot.location + dot.length];
                }
            }
            if (line.length) [lines addObject:line];
        }
        NSMutableArray *rich = [NSMutableArray array];
        NSInteger i = 0;
        for (NSDictionary *item in items) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            NSMutableDictionary *row = [item mutableCopy];
            row[@"place"] = place;
            if (i < (NSInteger)lines.count) {
                NSString *line = lines[i];
                NSString *zh = line;
                NSString *blurb = @"";
                NSRange bar = [line rangeOfString:@"｜"];
                if (bar.location == NSNotFound) bar = [line rangeOfString:@"|"];
                if (bar.location != NSNotFound && bar.location > 0 && bar.location + 1 < line.length) {
                    zh = [[line substringToIndex:bar.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                    NSUInteger cut = bar.location + 1;
                    if (bar.length > 1) cut = bar.location + bar.length;
                    blurb = [[line substringFromIndex:cut] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                }
                row[@"zh"] = zh;
                if (blurb.length == 0) blurb = RPString(row[@"summary"]);
                if (blurb.length == 0) blurb = @"热门话题";
                row[@"blurb"] = blurb;
            }
            if (![row[@"blurb"] isKindOfClass:[NSString class]] || [row[@"blurb"] length] == 0) {
                NSString *fallback = RPString(row[@"summary"]);
                row[@"blurb"] = fallback.length ? fallback : @"热门话题";
            }
            NSMutableString *summary = [NSMutableString stringWithFormat:@"%@ 第 %@ 名", place, row[@"rank"] ?: @""];
            NSString *score = RPString(row[@"score"]);
            if (score.length) [summary appendFormat:@" · %@", score];
            row[@"summary"] = summary;
            [rich addObject:row];
            i++;
        }
        items = rich;
    }
    [self store:@"x" payload:items];
    return YES;
}

- (BOOL)fetchGitHub {
    NSString *base = [self sourceURL:@"github-news"];
    if ([base rangeOfString:@"/rss"].location != NSNotFound || [base rangeOfString:@"feed"].location != NSNotFound || [base rangeOfString:@".xml"].location != NSNotFound) {
        NSArray *items = RPParseRSS([self syncGET:base proxy:[self proxyFor:@"github-news"] headers:nil], 8);
        NSMutableArray *mapped = [NSMutableArray array];
        for (NSDictionary *item in items) {
            [mapped addObject:@{ @"name": item[@"title"] ?: @"", @"full_name": item[@"title"] ?: @"", @"description": item[@"summary"] ?: @"", @"url": item[@"link"] ?: @"", @"stars": @0, @"forks": @0, @"language": @"RSS", @"topics": @[], @"image_url": item[@"image_url"] ?: @"" }];
        }
        if (!mapped.count) {
            if (self.fetchError.length == 0) self.fetchError = @"没有解析到项目";
            return NO;
        }
        [self store:@"github" payload:mapped];
        return YES;
    }
    NSDate *since = [NSDate dateWithTimeIntervalSinceNow:-30 * 24 * 3600];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd";
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSString *day = [fmt stringFromDate:since];
    NSString *q = [NSString stringWithFormat:@"topic:ai created:>=%@ fork:false archived:false", day];
    NSString *url = [NSString stringWithFormat:@"https://api.github.com/search/repositories?q=%@&sort=stars&order=desc&per_page=12", [q stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    if (base.length && [base rangeOfString:@"api.github.com"].location == NSNotFound && [base hasPrefix:@"http"]) url = base;
    NSData *data = [self syncGET:url proxy:[self proxyFor:@"github-news"] headers:@{ @"Accept": @"application/vnd.github+json" }];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:nil];
    NSArray *raw = [json[@"items"] isKindOfClass:[NSArray class]] ? json[@"items"] : @[];
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *repo in raw) {
        if (![repo isKindOfClass:[NSDictionary class]]) continue;
        NSString *name = RPString(repo[@"full_name"]);
        if (name.length == 0) continue;
        [items addObject:@{
            @"full_name": name,
            @"name": RPString(repo[@"name"]).length ? RPString(repo[@"name"]) : name,
            // GitHub sends JSON null for missing description/language; ?: does not catch NSNull.
            @"description": RPString(repo[@"description"]),
            @"stars": [repo[@"stargazers_count"] isKindOfClass:[NSNumber class]] ? repo[@"stargazers_count"] : @0,
            @"forks": [repo[@"forks_count"] isKindOfClass:[NSNumber class]] ? repo[@"forks_count"] : @0,
            @"language": RPString(repo[@"language"]).length ? RPString(repo[@"language"]) : @"--",
            @"url": RPString(repo[@"html_url"]),
            @"topics": [repo[@"topics"] isKindOfClass:[NSArray class]] ? repo[@"topics"] : @[],
            @"image_url": [repo[@"owner"] isKindOfClass:[NSDictionary class]] ? RPString(repo[@"owner"][@"avatar_url"]) : @"",
        }];
        if (items.count >= 12) break;
    }
    if (!items.count) {
        if (self.fetchError.length == 0) self.fetchError = @"没有解析到项目";
        return NO;
    }
    [self store:@"github" payload:items];
    return YES;
}

- (BOOL)fetchPrint {
    NSString *url = [self sourceURL:@"print"];
    if (url.length == 0) { self.fetchNote = @"未填写地址"; return YES; }
    NSData *data = [self syncGET:url proxy:[self proxyFor:@"print"] headers:nil];
    if (!data) return NO;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *printers = [json isKindOfClass:[NSArray class]] ? json : ([json isKindOfClass:[NSDictionary class]] ? @[json] : @[]);
    NSDictionary *primary = [printers.firstObject isKindOfClass:[NSDictionary class]] ? printers.firstObject : @{};
    NSString *pid = RPString(primary[@"id"]);
    if (pid.length) {
        NSString *detailURL = [url stringByAppendingFormat:@"%@%@", [url hasSuffix:@"/"] ? @"" : @"/", pid];
        NSData *detailData = [self syncGET:detailURL proxy:[self proxyFor:@"print"] headers:nil];
        NSDictionary *detail = [NSJSONSerialization JSONObjectWithData:detailData ?: [NSData data] options:0 error:nil];
        if ([detail isKindOfClass:[NSDictionary class]] && detail.count) primary = detail;
    }
    if (![json isKindOfClass:[NSArray class]] && ![json isKindOfClass:[NSDictionary class]]) {
        self.fetchError = @"打印机数据无法解析";
        return NO;
    }
    [self store:@"print" payload:@{ @"printers": printers ?: @[], @"primary": primary ?: @{} }];
    return YES;
}

- (BOOL)fetchMovies {
    NSString *url = [self sourceURL:@"movie-now-showing"];
    if (url.length == 0 || [url rangeOfString:@"themoviedb.org"].location != NSNotFound) {
        url = RPLocalSourceDefaults()[@"movie-now-showing"];
    }
    BOOL maoyan = [url rangeOfString:@"maoyan.com"].location != NSNotFound;
    NSData *data = [self syncGET:url proxy:(maoyan ? nil : [self proxyFor:@"movie-now-showing"]) headers:nil];
    // 12 so the page can show whole rows (4×3 portrait, 5×2 landscape); 8 left gaps.
    NSArray *items = maoyan ? RPMoviesFromMaoyan(data, 12) : RPParseMovies(data, 12);
    if (!items.count) {
        if (self.fetchError.length == 0) self.fetchError = @"没有解析到电影";
        return NO;
    }
    [self store:@"movies" payload:items];
    return YES;
}

- (NSArray *)steamItems:(NSArray *)raw limit:(NSInteger)limit {
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *rawItem in raw) {
        if (![rawItem isKindOfClass:[NSDictionary class]]) continue;
        NSString *title = RPString(rawItem[@"name"]);
        if (title.length == 0) continue;
        NSInteger cents = [rawItem[@"final_price"] integerValue];
        NSString *price = cents > 0 ? [NSString stringWithFormat:@"¥%.0f", cents / 100.0] : @"";
        NSInteger discount = [rawItem[@"discount_percent"] integerValue];
        [items addObject:@{
            @"title": title,
            @"summary": @"",
            @"header_url": RPString(rawItem[@"header_image"]),
            @"capsule_url": RPString(rawItem[@"large_capsule_image"] ?: rawItem[@"header_image"]),
            @"price": price,
            @"discount": discount > 0 ? [NSString stringWithFormat:@"-%ld%%", (long)discount] : @"",
        }];
        if ((NSInteger)items.count >= limit) break;
    }
    return items;
}

- (BOOL)fetchSteam {
    NSString *url = [self sourceURL:@"steam-new-releases"];
    if (url.length == 0) url = RPLocalSourceDefaults()[@"steam-new-releases"];
    NSString *proxy = [self proxyFor:@"steam-new-releases"] ?: [self proxyFor:@"steam-new-releases-2"];
    NSData *data = [self syncGET:url proxy:proxy headers:nil];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) {
        if (self.fetchError.length == 0) self.fetchError = @"Steam 数据无法解析";
        return NO;
    }
    NSArray *fresh = [json[@"new_releases"][@"items"] isKindOfClass:[NSArray class]] ? json[@"new_releases"][@"items"] : @[];
    NSArray *hot = [json[@"top_sellers"][@"items"] isKindOfClass:[NSArray class]] ? json[@"top_sellers"][@"items"] : @[];
    // 10 each (Steam returns 30 new / 10 top): enough for 2×4 portrait or 3×3 landscape.
    [self store:@"steam" payload:@{ @"new_releases": [self steamItems:fresh limit:10], @"top_sellers": [self steamItems:hot limit:10] }];
    return YES;
}

- (BOOL)fetchGames:(NSString *)pid key:(NSString *)key {
    NSString *url = [self sourceURL:pid];
    // Listings carry 20–25 games; keep 15 so a page can fill 3×4 / 4×3 / 5×3.
    NSArray *items = RPParseListing([self syncGET:url proxy:[self proxyFor:pid] headers:nil], url, 15);
    if (!items.count) {
        if (self.fetchError.length == 0) self.fetchError = @"没有解析到游戏";
        return NO;
    }
    [self store:key payload:items];
    return YES;
}

- (BOOL)fetchSchedule {
    NSString *url = [self sourceURL:@"schedule"];
    if (url.length == 0) { self.fetchNote = @"未填写地址"; return YES; }
    if ([url hasPrefix:@"webcal://"]) url = [@"https://" stringByAppendingString:[url substringFromIndex:9]];
    NSData *data = [self syncGET:url proxy:[self proxyFor:@"schedule"] headers:nil];
    if (!data) return NO;
    [self store:@"schedule" payload:RPParseICS(data)];
    return YES;
}

- (NSArray *)messagesFromData:(NSData *)data {
    if (data.length == 0) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *raw = nil;
    if ([json isKindOfClass:[NSArray class]]) raw = json;
    else if ([json isKindOfClass:[NSDictionary class]]) {
        id inner = json[@"messages"] ?: json[@"items"] ?: json[@"data"];
        if ([inner isKindOfClass:[NSArray class]]) raw = inner;
        else raw = @[json];
    }
    if (raw) {
        NSMutableArray *messages = [NSMutableArray array];
        for (id item in raw) {
            if ([item isKindOfClass:[NSString class]] && RPString(item).length) {
                [messages addObject:@{ @"title": RPString(item), @"body": RPString(item) }];
            } else if ([item isKindOfClass:[NSDictionary class]]) {
                NSString *title = RPString(item[@"title"] ?: item[@"text"] ?: item[@"message"]);
                NSString *body = RPString(item[@"body"] ?: item[@"content"] ?: item[@"summary"] ?: item[@"text"] ?: title);
                if (title.length == 0) title = body;
                if (title.length) [messages addObject:@{ @"title": title, @"body": body ?: title }];
            }
            if (messages.count >= 12) break;
        }
        return messages;
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if ([text rangeOfString:@"<item" options:NSCaseInsensitiveSearch].location != NSNotFound || [text rangeOfString:@"<entry" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        NSMutableArray *messages = [NSMutableArray array];
        for (NSDictionary *item in RPParseRSS(data, 8)) {
            NSString *title = RPString(item[@"title"]);
            if (!title.length) continue;
            [messages addObject:@{ @"title": title, @"body": RPString(item[@"summary"]).length ? item[@"summary"] : title }];
        }
        return messages;
    }
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) return @[];
    NSString *title = [[text componentsSeparatedByString:@"\n"] firstObject];
    if (title.length > 40) title = [[title substringToIndex:40] stringByAppendingString:@"…"];
    return @[ @{ @"title": title, @"body": text } ];
}

- (BOOL)fetchXiaohongshu {
    NSString *url = [self sourceURL:@"xiaohongshu-hot"];
    if (url.length == 0) url = RPLocalSourceDefaults()[@"xiaohongshu-hot"];
    NSString *proxy = [self proxyFor:@"xiaohongshu-hot"];
    if (proxy.length == 0) proxy = RPConfiguredProxy();
    // tophub serves the list as plain HTML (rank-item-container cards), so read it
    // directly first; r.jina.ai is only a fallback (it timed out often and returns
    // at most ~10 rows).
    NSData *data = [self syncGET:url proxy:proxy headers:@{ @"User-Agent": @"Mozilla/5.0 (iPad; CPU OS 9_3_5 like Mac OS X) AppleWebKit/601.1.46 (KHTML, like Gecko) Version/9.0 Mobile/13G36 Safari/601.1" }];
    NSArray *items = RPParseTophubCards(data, 20);
    if (!items.count) items = RPParseXiaohongshu(data, 20);
    if (!items.count && [url rangeOfString:@"tophub.today"].location != NSNotFound) {
        data = [self syncGET:[@"https://r.jina.ai/" stringByAppendingString:url] proxy:proxy headers:nil];
        items = RPParseXiaohongshuText(data, 20);
    }
    if (!items.count) {
        if (self.fetchError.length == 0) self.fetchError = @"没有解析到热门";
        return NO;
    }
    NSMutableArray *rich = [NSMutableArray array];
    NSMutableSet *usedImages = [NSMutableSet set];
    NSInteger tries = 0;
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSMutableDictionary *row = [item mutableCopy];
        // The page shows a lead photo plus a photo grid: find pictures for the
        // first 7 topics (was 4), and never reuse one picture for two topics.
        if (tries < 7 && RPString(row[@"image_url"]).length == 0) {
            tries++;
            NSString *q = [RPString(row[@"title"]) stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            if (q.length) {
                NSString *imgURL = [NSString stringWithFormat:@"https://image.so.com/j?q=%@&src=srp&sn=0&pn=12", q];
                NSData *imgData = [self syncGET:imgURL proxy:nil headers:@{ @"User-Agent": @"Mozilla/5.0 (iPad) AppleWebKit/601.1", @"Referer": @"https://image.so.com/" }];
                NSString *thumb = RPBestTopicImage(imgData, RPString(row[@"title"]));
                if (thumb.length && ![usedImages containsObject:thumb]) {
                    row[@"image_url"] = thumb;
                    [usedImages addObject:thumb];
                }
            }
        }
        row[@"rich"] = @YES;
        row[@"cover"] = @4;
        row[@"rank"] = @(rich.count + 1);
        if (!row[@"image_url"]) row[@"image_url"] = @"";
        [rich addObject:row];
        if (rich.count >= 16) break;
    }
    [self store:@"xhs" payload:rich];
    return YES;
}

- (BOOL)fetchBilibili {
    NSString *url = [self sourceURL:@"bilibili-hot"];
    if (url.length == 0) url = RPLocalSourceDefaults()[@"bilibili-hot"];
    // The old default asked for 10; the board shows up to 16. Upgrade only that exact value.
    if ([url isEqualToString:@"https://api.bilibili.com/x/web-interface/popular?ps=10&pn=1"]) url = RPLocalSourceDefaults()[@"bilibili-hot"];
    NSData *data = [self syncGET:url proxy:[self proxyFor:@"bilibili-hot"] headers:@{ @"Referer": @"https://www.bilibili.com" }];
    NSArray *items = RPParseBilibili(data, 20);
    if (!items.count) {
        if (self.fetchError.length == 0) self.fetchError = @"没有解析到热门";
        return NO;
    }
    [self store:@"bili" payload:items];
    return YES;
}

- (BOOL)fetchStocks {
    NSString *spec = [self sourceURL:@"stocks-cn"];
    if (spec.length == 0) spec = RPLocalSourceDefaults()[@"stocks-cn"];
    NSString *url = spec;
    NSMutableArray *codes = [NSMutableArray array];
    if ([spec rangeOfString:@"http" options:NSCaseInsensitiveSearch].location != 0) {
        NSMutableArray *secids = [NSMutableArray array];
        for (NSString *token in RPSplitSymbols(spec, 8)) {
            NSString *secid = RPStockSecid(token);
            if (!secid) continue;
            [secids addObject:secid];
            [codes addObject:[secid substringFromIndex:2]];
        }
        if (secids.count == 0) {
            self.fetchError = @"没有认出股票代码";
            return NO;
        }
        url = [NSString stringWithFormat:@"https://push2.eastmoney.com/api/qt/ulist.np/get?fltt=2&fields=f2,f3,f4,f6,f12,f14,f15,f16,f17,f18&secids=%@", [secids componentsJoinedByString:@","]];
    }
    NSData *data = [self syncGET:url proxy:[self proxyFor:@"stocks-cn"] headers:nil];
    NSArray *items = RPParseEastmoney(data, codes);
    if (!items.count) {
        if (self.fetchError.length == 0) self.fetchError = @"没有解析到行情";
        return NO;
    }
    [self store:@"stocks" payload:items];
    return YES;
}

- (BOOL)fetchCrypto {
    NSString *spec = [self sourceURL:@"crypto"];
    if (spec.length == 0) spec = RPLocalSourceDefaults()[@"crypto"];
    NSMutableArray *wanted = [NSMutableArray array];
    NSDictionary *table = RPCoinTable();
    for (NSString *token in RPSplitSymbols(spec, 8)) {
        NSString *key = [token lowercaseString];
        NSArray *pair = table[key];
        if (pair) {
            [wanted addObject:@{ @"inst": pair[0], @"name": pair[1], @"symbol": [key uppercaseString] }];
        } else {
            NSString *inst = [key rangeOfString:@"-"].location != NSNotFound ? [key uppercaseString] : [[key uppercaseString] stringByAppendingString:@"-USDT"];
            NSString *symbol = [[inst componentsSeparatedByString:@"-"] firstObject] ?: inst;
            [wanted addObject:@{ @"inst": inst, @"name": symbol, @"symbol": symbol }];
        }
    }
    if (wanted.count == 0) {
        self.fetchError = @"没有认出币种";
        return NO;
    }
    NSString *proxy = [self proxyFor:@"crypto"];
    if (proxy.length == 0) proxy = RPConfiguredProxy();
    NSData *data = [self syncGET:@"https://www.okx.com/api/v5/market/tickers?instType=SPOT" proxy:proxy headers:nil];
    NSArray *items = RPParseOKX(data, wanted);
    if (!items.count) {
        if (self.fetchError.length == 0) self.fetchError = @"没有解析到行情";
        return NO;
    }
    [self store:@"crypto" payload:items];
    return YES;
}

- (BOOL)fetchTicker {
    NSString *url = RPString([[NSUserDefaults standardUserDefaults] stringForKey:RPTickerURLKey]);
    if (url.length == 0) { self.fetchNote = @"未填写地址"; return YES; }
    NSString *proxy = nil;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([ud boolForKey:RPTickerProxyKey]) {
        proxy = RPConfiguredProxy();
    }
    NSData *data = [self syncGET:url proxy:proxy headers:nil];
    if (!data) return NO;
    NSArray *messages = [self messagesFromData:data];
    if (!messages) {
        if (self.fetchError.length == 0) self.fetchError = @"消息无法解析";
        return NO;
    }
    [self store:@"ticker" payload:messages];
    if (messages.count == 0) self.fetchNote = @"没有新消息";
    return YES;
}

- (NSDictionary *)assemble {
    NSDictionary *weather = [self payload:@"weather"];
    NSDictionary *vps = [self payload:@"vps"];
    NSDictionary *print = [self payload:@"print"];
    NSDictionary *steam = [self payload:@"steam"];
    NSDictionary *schedule = [self payload:@"schedule"];
    id hello = [self payload:@"hello"];
    NSString *helloText = @"";
    NSString *helloPeriod = @"";
    if ([hello isKindOfClass:[NSDictionary class]]) {
        helloText = [hello[@"text"] isKindOfClass:[NSString class]] ? hello[@"text"] : @"";
        helloPeriod = [hello[@"period"] isKindOfClass:[NSString class]] ? hello[@"period"] : @"";
    }
    if (helloPeriod.length == 0) RPHelloSlot(&helloPeriod);
    NSArray *daily = [self payload:@"daily"];
    NSArray *github = [self payload:@"github"];
    NSArray *x = [self payload:@"x"];
    NSArray *movies = [self payload:@"movies"];
    NSArray *pc = [self payload:@"pc"];
    NSArray *sw = [self payload:@"switch"];
    NSArray *ps5 = [self payload:@"ps5"];
    return @{
        @"weather": [weather isKindOfClass:[NSDictionary class]] ? weather : @{},
        @"vps": [vps isKindOfClass:[NSDictionary class]] ? vps : @{},
        @"news": @{
            @"hello_text": helloText ?: @"",
            @"hello_period": helloPeriod ?: @"",
            @"daily_items": [daily isKindOfClass:[NSArray class]] ? daily : @[],
            @"daily": [daily isKindOfClass:[NSArray class]] ? daily : @[],
            @"github_items": [github isKindOfClass:[NSArray class]] ? github : @[],
            @"x_items": [x isKindOfClass:[NSArray class]] ? x : @[],
            @"x": [x isKindOfClass:[NSArray class]] ? x : @[],
            @"xhs_items": [[self payload:@"xhs"] isKindOfClass:[NSArray class]] ? [self payload:@"xhs"] : @[],
            @"bili_items": [[self payload:@"bili"] isKindOfClass:[NSArray class]] ? [self payload:@"bili"] : @[],
        },
        @"stocks": [[self payload:@"stocks"] isKindOfClass:[NSArray class]] ? [self payload:@"stocks"] : @[],
        @"crypto": [[self payload:@"crypto"] isKindOfClass:[NSArray class]] ? [self payload:@"crypto"] : @[],
        @"print": [print isKindOfClass:[NSDictionary class]] ? print : @{},
        @"movies": [movies isKindOfClass:[NSArray class]] ? movies : @[],
        @"steam": [steam isKindOfClass:[NSDictionary class]] ? steam : @{},
        @"gamer520": @{
            @"items": [pc isKindOfClass:[NSArray class]] ? pc : @[],
            @"switch_items": [sw isKindOfClass:[NSArray class]] ? sw : @[],
        },
        @"switch_games": [sw isKindOfClass:[NSArray class]] ? sw : @[],
        @"ps5_games": [ps5 isKindOfClass:[NSArray class]] ? ps5 : @[],
        @"schedule": [schedule isKindOfClass:[NSDictionary class]] ? schedule : @{ @"today": @[], @"week": @[], @"reminders": @[] },
        @"daily": @{ @"greeting": @"你好", @"quote": @"" },
    };
}

@end
