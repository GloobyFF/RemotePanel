#import "RPLocalFeed.h"
#import "RPNet.h"
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <math.h>
#import <netinet/in.h>
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

NSString *RPLocalDefaultProxy(void) { return @"socks5h://192.168.28.77:1080"; }
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
        @"bilibili-hot": @"https://api.bilibili.com/x/web-interface/popular?ps=10&pn=1",
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
    ];
}

static NSString *RPString(id value) {
    if (![value isKindOfClass:[NSString class]]) return @"";
    return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
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

static NSDictionary *RPParseICS(NSData *data) {
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    text = [text stringByReplacingOccurrencesOfString:@"\r\n " withString:@""];
    text = [text stringByReplacingOccurrencesOfString:@"\n " withString:@""];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd";
    fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSString *today = [fmt stringFromDate:[NSDate date]];
    NSMutableArray *events = [NSMutableArray array];
    NSMutableArray *todos = [NSMutableArray array];
    NSString *kind = @"";
    NSMutableDictionary *cur = nil;
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([line isEqualToString:@"BEGIN:VEVENT"]) { kind = @"event"; cur = [NSMutableDictionary dictionary]; continue; }
        if ([line isEqualToString:@"BEGIN:VTODO"]) { kind = @"todo"; cur = [NSMutableDictionary dictionary]; continue; }
        if ([line isEqualToString:@"END:VEVENT"] || [line isEqualToString:@"END:VTODO"]) {
            if ([kind isEqualToString:@"event"]) [events addObject:cur ?: @{}];
            if ([kind isEqualToString:@"todo"]) [todos addObject:cur ?: @{}];
            kind = @""; cur = nil; continue;
        }
        if (!cur || [line rangeOfString:@":"].location == NSNotFound) continue;
        NSRange colon = [line rangeOfString:@":"];
        NSString *key = [[line substringToIndex:colon.location] componentsSeparatedByString:@";"].firstObject.uppercaseString;
        cur[key] = [line substringFromIndex:NSMaxRange(colon)];
    }
    NSMutableArray *upcoming = [NSMutableArray array];
    for (NSDictionary *ev in events) {
        NSString *title = RPDecode([ev[@"SUMMARY"] stringByReplacingOccurrencesOfString:@"\\n" withString:@" "]);
        NSString *start = ev[@"DTSTART"] ?: @"";
        NSString *day = @"";
        NSString *clock = @"";
        if ([start rangeOfString:@"T"].location != NSNotFound) {
            NSArray *parts = [start componentsSeparatedByString:@"T"];
            day = parts.firstObject;
            NSString *tim = [parts.lastObject stringByReplacingOccurrencesOfString:@"Z" withString:@""];
            if (tim.length >= 4) clock = [NSString stringWithFormat:@"%@:%@", [tim substringToIndex:2], [tim substringWithRange:NSMakeRange(2, 2)]];
        } else {
            day = start;
        }
        NSString *digits = [[day componentsSeparatedByCharactersInSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet]] componentsJoinedByString:@""];
        if (digits.length < 8) continue;
        NSString *iso = [NSString stringWithFormat:@"%@-%@-%@", [digits substringToIndex:4], [digits substringWithRange:NSMakeRange(4, 2)], [digits substringWithRange:NSMakeRange(6, 2)]];
        if ([iso compare:today] == NSOrderedAscending) continue;
        [upcoming addObject:@{ @"date": iso, @"time": clock, @"title": title.length ? title : @"未命名日程", @"notes": RPDecode(ev[@"DESCRIPTION"] ?: @""), @"id": ev[@"UID"] ?: title }];
        if (upcoming.count >= 18) break;
    }
    [upcoming sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"date"] compare:b[@"date"]];
    }];
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
            @"summary": heat.length ? [NSString stringWithFormat:@"热度 %@", heat] : @"小红书热榜",
            @"link": link ?: @"",
            @"image_url": @"",
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
        NSString *link = RPString(row[@"short_link_v2"]);
        if (link.length == 0 && RPString(row[@"bvid"]).length) {
            link = [NSString stringWithFormat:@"https://www.bilibili.com/video/%@", RPString(row[@"bvid"])];
        }
        NSString *pic = RPString(row[@"pic"]);
        if ([pic hasPrefix:@"http://"]) pic = [@"https://" stringByAppendingString:[pic substringFromIndex:7]];
        [items addObject:@{
            @"title": title,
            @"summary": [bits componentsJoinedByString:@" · "],
            @"link": link ?: @"",
            @"image_url": pic ?: @"",
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
        "function render(){\n"
        "  var ch=state.refresh_choices, ti=state.refresh_titles, h=\"\";\n"
        "  h+=\"<div class=\\\"card\\\"><h2>连接</h2><label>HTTP / SOCKS 代理</label><input id=\\\"proxy\\\" type=\\\"text\\\" value=\\\"\"+esc(state.proxy)+\"\\\">\";\n"
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
        "  h+=\"<div class=\\\"card\\\"><h2>页面</h2>\";\n"
        "  (state.pages||[]).forEach(function(pg,i){\n"
        "    h+=\"<div class=\\\"page\\\" data-i=\\\"\"+i+\"\\\"><div class=\\\"row\\\"><strong>\"+esc(pg.title)+\"</strong>\";\n"
        "    h+=\"<label class=\\\"check\\\"><input type=\\\"checkbox\\\" class=\\\"en\\\"\"+(pg.enabled?\" checked\":\"\")+\"> 显示</label>\";\n"
        "    h+=\"<label class=\\\"check\\\">停留 <input class=\\\"dw narrow\\\" type=\\\"number\\\" value=\\\"\"+esc(pg.dwell)+\"\\\"> 秒</label></div>\";\n"
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
        "}\n"
        "function collect(){\n"
        "  var body=JSON.parse(JSON.stringify(state));\n"
        "  body.proxy=document.getElementById(\"proxy\").value;\n"
        "  body.dwell_override=Number(document.getElementById(\"dwell\").value)||0;\n"
        "  body.ticker_url=document.getElementById(\"ticker\").value;\n"
        "  body.ticker_proxy=document.getElementById(\"tickerProxy\").checked;\n"
        "  body.ticker_refresh=Number(document.getElementById(\"tickerRefresh\").value);\n"
        "  body.vps_url=document.getElementById(\"vps\").value;\n"
        "  body.vps_token=document.getElementById(\"vpsToken\").value;\n"
        "  body.vps_proxy=document.getElementById(\"vpsProxy\").checked;\n"
        "  body.vps_refresh=Number(document.getElementById(\"vpsRefresh\").value);\n"
        "  body.album_id=document.getElementById(\"album\").value;\n"
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
        "\n"
    ];
}

static NSString * const RPDwellPrefix = @"RemotePanel.page.dwell.";
static NSString * const RPAlbumDefaultsKey = @"RemotePanel.albumLocalId";
static NSString * const RPDwellOverrideDefaultsKey = @"RemotePanel.dwellOverride";

@interface RPLocalFeed ()
@property (nonatomic, strong) NSMutableDictionary *cache;
@property (nonatomic, assign) BOOL refreshing;
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
    NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:[self diskPath]];
    if ([saved isKindOfClass:[NSDictionary class]]) [self.cache addEntriesFromDictionary:saved];
}

- (void)saveDisk {
    NSDictionary *snapshot;
    @synchronized (self) { snapshot = [self.cache copy]; }
    [snapshot writeToFile:[self diskPath] atomically:YES];
}

- (BOOL)pageEnabled:(NSString *)pid {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *key = [RPPageEnabledPrefix stringByAppendingString:pid];
    if ([ud objectForKey:key] == nil) return YES;
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
    @synchronized (self) { [self.cache removeObjectForKey:@"x"]; }
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
    NSString *proxy = RPString([ud stringForKey:RPProxyDefaultsKey]);
    if (proxy.length == 0) proxy = RPLocalDefaultProxy();
    return proxy;
}

- (BOOL)fresh:(NSString *)key ttl:(NSTimeInterval)ttl {
    @synchronized (self) {
        NSDictionary *box = self.cache[key];
        if (![box isKindOfClass:[NSDictionary class]] || !box[@"payload"]) return NO;
        id payload = box[@"payload"];
        if ([payload isKindOfClass:[NSArray class]] && [(NSArray *)payload count] == 0) return NO;
        if ([key isEqualToString:@"hello"]) {
            if ([box[@"at"] doubleValue] <= 0) return NO;
            if (![payload isKindOfClass:[NSDictionary class]]) return NO;
            NSString *text = payload[@"text"];
            NSString *slot = payload[@"slot"];
            return [text isKindOfClass:[NSString class]] && text.length > 0 && [slot isEqualToString:RPHelloSlot(NULL)];
        }
        if (([key isEqualToString:@"x"] || [key isEqualToString:@"xhs"] || [key isEqualToString:@"github"]) && [payload isKindOfClass:[NSArray class]] && [(NSArray *)payload count]) {
            id first = [(NSArray *)payload firstObject];
            if (![first isKindOfClass:[NSDictionary class]] || ![(NSDictionary *)first objectForKey:@"image_url"] || (([key isEqualToString:@"x"] || [key isEqualToString:@"xhs"]) && ![first[@"rich"] boolValue])) return NO;
            if ([key isEqualToString:@"xhs"] && [first[@"cover"] integerValue] < 3) return NO;
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
    if (!payload) return;
    @synchronized (self) {
        self.cache[key] = @{ @"at": @([[NSDate date] timeIntervalSince1970]), @"payload": payload };
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
            NSDictionary *box = self.cache[key];
            if (![box isKindOfClass:[NSDictionary class]]) continue;
            NSMutableDictionary *next = [box mutableCopy];
            next[@"at"] = @0;
            self.cache[key] = next;
        }
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
        BOOL enabled = [ud objectForKey:enabledKey] == nil ? YES : [ud boolForKey:enabledKey];
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
    NSString *proxy = RPString([ud stringForKey:RPProxyDefaultsKey]);
    if (proxy.length == 0) proxy = RPLocalDefaultProxy();
    NSString *vpsURL = RPString([ud stringForKey:RPVpsURLKey]);
    if (vpsURL.length == 0) vpsURL = RPLocalDefaultVPSURL();
    NSString *vpsToken = RPString([ud stringForKey:RPVpsTokenKey]);
    if (vpsToken.length == 0) vpsToken = RPLocalDefaultVPSToken();
    BOOL vpsProxy = [ud objectForKey:RPVpsProxyKey] ? [ud boolForKey:RPVpsProxyKey] : NO;
    return @{
        @"proxy": proxy ?: @"",
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
        @"refresh_choices": choices,
        @"refresh_titles": RPLocalRefreshChoiceTitles(),
        @"pages": pages,
    };
}

- (BOOL)applySettingsDocument:(NSDictionary *)doc error:(NSString **)error {
    if (![doc isKindOfClass:[NSDictionary class]]) {
        if (error) *error = @"格式不对";
        return NO;
    }
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if ([doc[@"proxy"] isKindOfClass:[NSString class]]) [ud setObject:doc[@"proxy"] forKey:RPProxyDefaultsKey];
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
    [ud synchronize];
    [self markCacheStale];
    if (self.refreshing) self.settingsRerun = YES;
    [self appendLog:@"设置" status:@"ok" detail:@"已从浏览器保存"];
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"RPRemoteSettingsChanged" object:nil];
    });
    return YES;
}

- (BOOL)readClient:(int)client first:(NSString **)firstOut body:(NSData **)bodyOut {
    NSMutableData *buf = [NSMutableData data];
    char tmp[4096];
    NSUInteger headerEnd = NSNotFound;
    NSInteger contentLength = 0;
    for (int i = 0; i < 30; i++) {
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
                    if (contentLength > 200000) contentLength = 200000;
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
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
        struct timeval tv;
        tv.tv_sec = 8;
        tv.tv_usec = 0;
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
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
                [self store:@"ticker" payload:@[ @{ @"title": text, @"body": text } ]];
                [self saveDisk];
                [self appendLog:@"走马灯" status:@"ok" detail:@"收到一条提醒"];
                [self emitName:@"走马灯" status:@"ok" detail:@"收到一条提醒" includeState:NO];
                reply = @"ok";
            }
            NSData *bytes = [reply dataUsingEncoding:NSUTF8StringEncoding];
            NSString *head = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\nContent-Length: %lu\r\n\r\n", (unsigned long)bytes.length];
            NSData *hb = [head dataUsingEncoding:NSUTF8StringEncoding];
            send(client, hb.bytes, hb.length, 0);
            send(client, bytes.bytes, bytes.length, 0);
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
                send(client, hb.bytes, hb.length, 0);
                send(client, png.bytes, png.length, 0);
            } else {
                NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
                NSString *head = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\nContent-Length: %lu\r\n\r\n", (unsigned long)bytes.length];
                NSData *hb = [head dataUsingEncoding:NSUTF8StringEncoding];
                send(client, hb.bytes, hb.length, 0);
                if (bytes.length) send(client, bytes.bytes, bytes.length, 0);
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
        send(client, hb.bytes, hb.length, 0);
        if (bytes.length) send(client, bytes.bytes, bytes.length, 0);
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
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"HH:mm:ss";
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
    if (self.refreshing) return;
    self.refreshing = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *jobs = [NSMutableArray array];
        void (^add)(NSString *, NSString *, NSTimeInterval, BOOL (^)(void)) = ^(NSString *name, NSString *key, NSTimeInterval ttl, BOOL (^work)(void)) {
            if ([self fresh:key ttl:ttl]) return;
            [jobs addObject:@{ @"name": name, @"work": [work copy] }];
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
            NSString *name = job[@"name"];
            BOOL (^work)(void) = job[@"work"];
            self.fetchError = nil;
            self.fetchNote = nil;
            [self emitName:name status:@"start" detail:@"" includeState:NO];
            BOOL ok = work ? work() : NO;
            NSString *status = ok ? (self.fetchNote.length ? @"skip" : @"ok") : @"fail";
            NSString *detail = ok ? (self.fetchNote.length ? self.fetchNote : @"完成") : (self.fetchError.length ? self.fetchError : @"失败");
            [self appendLog:name status:status detail:detail];
            [self emitName:name status:status detail:detail includeState:(ok && self.fetchNote.length == 0)];
        }
        [self saveDisk];
        if (self.settingsRerun) {
            self.settingsRerun = NO;
            self.refreshing = NO;
            [self refreshWithCompletion:completion];
            return;
        }
        NSDictionary *state = [self assemble];
        self.refreshing = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(state, nil);
        });
    });
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
        proxy = RPString([ud stringForKey:RPProxyDefaultsKey]);
        if (proxy.length == 0) proxy = RPLocalDefaultProxy();
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
    [self store:@"hello" payload:@{ @"text": text, @"slot": slot, @"period": label ?: @"" }];
    return YES;
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
    if (proxy.length == 0) proxy = RPLocalDefaultProxy();
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
        NSString *prompt = [NSString stringWithFormat:@"把下面每条 X 热门话题翻译成一句简短中文，口语、准确。保持 %lu 行，一行一条，不要编号，不要空行，不要解释。已经是中文就原样输出。\n%@", (unsigned long)titles.count, [titles componentsJoinedByString:@"\n"]];
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
            if (i < (NSInteger)lines.count) row[@"zh"] = lines[i];
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
            @"name": repo[@"name"] ?: name,
            @"description": repo[@"description"] ?: @"",
            @"stars": repo[@"stargazers_count"] ?: @0,
            @"forks": repo[@"forks_count"] ?: @0,
            @"language": repo[@"language"] ?: @"--",
            @"url": repo[@"html_url"] ?: @"",
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
    NSArray *items = maoyan ? RPMoviesFromMaoyan(data, 8) : RPParseMovies(data, 8);
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
    [self store:@"steam" payload:@{ @"new_releases": [self steamItems:fresh limit:6], @"top_sellers": [self steamItems:hot limit:6] }];
    return YES;
}

- (BOOL)fetchGames:(NSString *)pid key:(NSString *)key {
    NSString *url = [self sourceURL:pid];
    NSArray *items = RPParseListing([self syncGET:url proxy:[self proxyFor:pid] headers:nil], url, 8);
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
    if (proxy.length == 0) proxy = RPLocalDefaultProxy();
    NSString *fetchURL = url;
    if ([url rangeOfString:@"tophub.today"].location != NSNotFound) {
        fetchURL = [@"https://r.jina.ai/" stringByAppendingString:url];
    }
    NSData *data = [self syncGET:fetchURL proxy:proxy headers:nil];
    NSArray *items = RPParseXiaohongshu(data, 10);
    if (!items.count) items = RPParseXiaohongshuText(data, 10);
    if (!items.count) {
        if (self.fetchError.length == 0) self.fetchError = @"没有解析到热门";
        return NO;
    }
    NSMutableArray *rich = [NSMutableArray array];
    NSInteger tries = 0;
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSMutableDictionary *row = [item mutableCopy];
        if (tries < 4 && RPString(row[@"image_url"]).length == 0) {
            tries++;
            NSString *q = [RPString(row[@"title"]) stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            if (q.length) {
                NSString *imgURL = [NSString stringWithFormat:@"https://image.so.com/j?q=%@&src=srp&sn=0&pn=12", q];
                NSData *imgData = [self syncGET:imgURL proxy:nil headers:@{ @"User-Agent": @"Mozilla/5.0 (iPad) AppleWebKit/601.1", @"Referer": @"https://image.so.com/" }];
                NSString *thumb = RPBestTopicImage(imgData, RPString(row[@"title"]));
                if (thumb.length) row[@"image_url"] = thumb;
            }
        }
        row[@"rich"] = @YES;
        row[@"cover"] = @3;
        if (!row[@"image_url"]) row[@"image_url"] = @"";
        [rich addObject:row];
        if (rich.count >= 8) break;
    }
    [self store:@"xhs" payload:rich];
    return YES;
}

- (BOOL)fetchBilibili {
    NSString *url = [self sourceURL:@"bilibili-hot"];
    if (url.length == 0) url = RPLocalSourceDefaults()[@"bilibili-hot"];
    NSData *data = [self syncGET:url proxy:[self proxyFor:@"bilibili-hot"] headers:@{ @"Referer": @"https://www.bilibili.com" }];
    NSArray *items = RPParseBilibili(data, 10);
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
    if (proxy.length == 0) proxy = RPLocalDefaultProxy();
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
        proxy = RPString([ud stringForKey:RPProxyDefaultsKey]);
        if (proxy.length == 0) proxy = RPLocalDefaultProxy();
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
