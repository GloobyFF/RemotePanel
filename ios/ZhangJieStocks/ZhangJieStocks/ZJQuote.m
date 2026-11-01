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

+ (void)refreshNow:(void (^)(BOOL ok, NSString *error))done {
    NSArray<ZJHolding *> *holds = [ZJStore holdings];
    NSMutableArray *codes = [NSMutableArray array];
    NSMutableArray *secids = [NSMutableArray array];
    for (ZJHolding *h in holds) {
        NSString *secid = [self secidForCode:h.code];
        if (!secid) continue;
        [codes addObject:h.code];
        [secids addObject:secid];
    }
    if (secids.count == 0) {
        if (done) done(NO, @"还没有股票");
        return;
    }
    NSString *urlText = [NSString stringWithFormat:@"https://push2.eastmoney.com/api/qt/ulist.np/get?fltt=2&fields=f2,f3,f4,f12,f14&secids=%@", [secids componentsJoinedByString:@","]];
    NSURL *url = [NSURL URLWithString:urlText];
    if (!url) {
        if (done) done(NO, @"行情地址无效");
        return;
    }
    // One shared session. A new session per refresh (every minute in market hours)
    // was never invalidated, so each one leaked along with its connection pool.
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest = 20;
        cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        session = [NSURLSession sessionWithConfiguration:cfg];
    });
    NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || data.length == 0) {
                if (done) done(NO, @"行情没更新");
                return;
            }
            NSInteger status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 200;
            if (status >= 400) {
                if (done) done(NO, @"行情没更新");
                return;
            }
            NSArray *items = [self parse:data codes:codes];
            if (items.count == 0) {
                if (done) done(NO, @"没有解析到行情");
                return;
            }
            [ZJStore mergeQuotes:items];
            if (done) done(YES, nil);
        });
    }];
    [task resume];
}

@end
