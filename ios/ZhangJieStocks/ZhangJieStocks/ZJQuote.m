#import "ZJQuote.h"
#import "ZJStore.h"

@implementation ZJQuote

+ (NSString *)codeForToken:(NSString *)token {
    NSString *s = [[token lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    s = [s stringByReplacingOccurrencesOfString:@"." withString:@""];
    if ([s hasPrefix:@"sh"] || [s hasPrefix:@"sz"] || [s hasPrefix:@"bj"]) {
        if (s.length <= 2) return nil;
        s = [s substringFromIndex:2];
    }
    if (s.length != 6) return nil;
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    if ([[s stringByTrimmingCharactersInSet:digits] length] != 0) return nil;
    return s;
}

+ (NSString *)secidForCode:(NSString *)code {
    if (code.length != 6) return nil;
    unichar c = [code characterAtIndex:0];
    NSString *market = (c == '6' || c == '5' || c == '9') ? @"1" : @"0";
    return [NSString stringWithFormat:@"%@.%@", market, code];
}

+ (double)num:(id)value {
    if ([value isKindOfClass:[NSNumber class]]) return [value doubleValue];
    if ([value isKindOfClass:[NSString class]]) return [value doubleValue];
    return 0;
}

+ (NSString *)str:(id)value {
    if ([value isKindOfClass:[NSString class]]) return value;
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    return @"";
}

+ (NSArray *)parse:(NSData *)data codes:(NSArray *)codes {
    id json = [NSJSONSerialization JSONObjectWithData:data ?: [NSData data] options:0 error:nil];
    NSDictionary *root = [json isKindOfClass:[NSDictionary class]] ? json : nil;
    NSDictionary *dataObj = [root[@"data"] isKindOfClass:[NSDictionary class]] ? root[@"data"] : nil;
    NSArray *diff = [dataObj[@"diff"] isKindOfClass:[NSArray class]] ? dataObj[@"diff"] : nil;
    NSMutableDictionary *byCode = [NSMutableDictionary dictionary];
    for (NSDictionary *row in diff) {
        if (![row isKindOfClass:[NSDictionary class]]) continue;
        NSString *code = [self str:row[@"f12"]];
        if (code.length == 0) continue;
        NSString *name = [self str:row[@"f14"]];
        if (name.length == 0) name = code;
        byCode[code] = @{
            @"name": name,
            @"symbol": code,
            @"price": @([self num:row[@"f2"]]),
            @"percent": @([self num:row[@"f3"]]),
            @"change": @([self num:row[@"f4"]]),
        };
    }
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *code in codes) {
        NSDictionary *item = byCode[code];
        if (item) [items addObject:item];
    }
    return items;
}

/** sh / sz / bj prefix used by qt.gtimg.cn. */
+ (NSString *)tencentKeyForCode:(NSString *)code {
    if (code.length != 6) return nil;
    unichar c = [code characterAtIndex:0];
    NSString *market = @"sz";
    if (c == '6' || c == '5' || c == '9') market = @"sh";
    else if (c == '8' || c == '4') market = @"bj";
    return [market stringByAppendingString:code];
}

/*
 qt.gtimg.cn answers in GBK, one line per stock:
   v_sh600519="1~贵州茅台~600519~1392.05~1354.00~1363.00~…~31 change~32 percent~…";
 Fields used: 1 name, 2 code, 3 price, 31 change, 32 percent.
 */
+ (NSArray *)parseTencent:(NSData *)data codes:(NSArray *)codes {
    NSString *text = [[NSString alloc] initWithData:data ?: [NSData data]
                                           encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000)];
    if (text.length == 0) return @[];
    NSMutableDictionary *byCode = [NSMutableDictionary dictionary];
    for (NSString *line in [text componentsSeparatedByString:@";"]) {
        NSRange q1 = [line rangeOfString:@"\""];
        NSRange q2 = [line rangeOfString:@"\"" options:NSBackwardsSearch];
        if (q1.location == NSNotFound || q2.location <= q1.location) continue;
        NSString *body = [line substringWithRange:NSMakeRange(NSMaxRange(q1), q2.location - NSMaxRange(q1))];
        NSArray *f = [body componentsSeparatedByString:@"~"];
        if (f.count < 33) continue;
        NSString *code = f[2];
        double price = [f[3] doubleValue];
        if (code.length != 6 || price <= 0) continue;
        NSString *name = [f[1] length] ? f[1] : code;
        byCode[code] = @{
            @"name": name,
            @"symbol": code,
            @"price": @(price),
            @"percent": @([f[32] doubleValue]),
            @"change": @([f[31] doubleValue]),
        };
    }
    NSMutableArray *items = [NSMutableArray array];
    for (NSString *code in codes) {
        NSDictionary *item = byCode[code];
        if (item) [items addObject:item];
    }
    return items;
}

+ (NSURLSession *)session {
    // One shared session. A new session per refresh (every minute in market hours)
    // was never invalidated, so each one leaked along with its connection pool.
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        // Short timeout: when Eastmoney resets or stalls, fall over to Tencent quickly.
        cfg.timeoutIntervalForRequest = 12;
        cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        session = [NSURLSession sessionWithConfiguration:cfg];
    });
    return session;
}

/** GET on the shared session; the block runs on the main queue with nil on any failure. */
+ (void)get:(NSURL *)url done:(void (^)(NSData *data))done {
    if (!url) {
        done(nil);
        return;
    }
    NSURLSessionDataTask *task = [[self session] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 200;
        NSData *ok = (error || status >= 400 || data.length == 0) ? nil : data;
        dispatch_async(dispatch_get_main_queue(), ^{ done(ok); });
    }];
    [task resume];
}

+ (void)refreshNow:(void (^)(BOOL ok, NSString *error))done {
    NSArray<ZJHolding *> *holds = [ZJStore holdings];
    NSMutableArray *codes = [NSMutableArray array];
    NSMutableArray *secids = [NSMutableArray array];
    NSMutableArray *tkeys = [NSMutableArray array];
    for (ZJHolding *h in holds) {
        NSString *secid = [self secidForCode:h.code];
        NSString *tkey = [self tencentKeyForCode:h.code];
        if (!secid || !tkey) continue;
        [codes addObject:h.code];
        [secids addObject:secid];
        [tkeys addObject:tkey];
    }
    if (secids.count == 0) {
        if (done) done(NO, @"还没有股票");
        return;
    }
    NSURL *eastmoney = [NSURL URLWithString:[NSString stringWithFormat:@"https://push2.eastmoney.com/api/qt/ulist.np/get?fltt=2&fields=f2,f3,f4,f12,f14&secids=%@", [secids componentsJoinedByString:@","]]];
    NSURL *tencent = [NSURL URLWithString:[NSString stringWithFormat:@"https://qt.gtimg.cn/q=%@", [tkeys componentsJoinedByString:@","]]];
    void (^finish)(NSArray *, NSString *) = ^(NSArray *items, NSString *source) {
        [ZJStore mergeQuotes:items];
        [ZJStore setLastSource:source];
        if (done) done(YES, nil);
    };
    // Eastmoney first. On a connection error, an HTTP error, or an empty/unparsable
    // body, ask Tencent for the same codes before reporting a failure.
    [self get:eastmoney done:^(NSData *data) {
        NSArray *items = data ? [self parse:data codes:codes] : @[];
        if (items.count) {
            finish(items, @"东方财富");
            return;
        }
        [self get:tencent done:^(NSData *backup) {
            NSArray *more = backup ? [self parseTencent:backup codes:codes] : @[];
            if (more.count) {
                finish(more, @"腾讯");
                return;
            }
            if (done) done(NO, @"东方财富和腾讯行情都没连上");
        }];
    }];
}

@end
