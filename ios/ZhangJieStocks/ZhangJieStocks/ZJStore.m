#import "ZJStore.h"

@implementation ZJHolding
@end

static NSString *const kHold = @"ZJ.holdings";
static NSString *const kQuotes = @"ZJ.quotes";
static NSString *const kDwellSum = @"ZJ.dwellSummary";
static NSString *const kDwellStock = @"ZJ.dwellStock";

@implementation ZJStore

+ (NSUserDefaults *)ud {
    return [NSUserDefaults standardUserDefaults];
}

+ (void)seedIfNeeded {
    if ([[self ud] objectForKey:kHold]) return;
    NSArray *seed = @[
        @{@"code": @"600519", @"name": @"贵州茅台", @"buy": @0, @"shares": @0},
        @{@"code": @"300750", @"name": @"宁德时代", @"buy": @0, @"shares": @0},
        @{@"code": @"600036", @"name": @"招商银行", @"buy": @0, @"shares": @0},
        @{@"code": @"601318", @"name": @"中国平安", @"buy": @0, @"shares": @0},
        @{@"code": @"002594", @"name": @"比亚迪", @"buy": @0, @"shares": @0},
    ];
    [[self ud] setObject:seed forKey:kHold];
}

+ (ZJHolding *)holdingFrom:(NSDictionary *)row {
    ZJHolding *h = [[ZJHolding alloc] init];
    h.code = [row[@"code"] isKindOfClass:[NSString class]] ? row[@"code"] : @"";
    h.name = [row[@"name"] isKindOfClass:[NSString class]] ? row[@"name"] : h.code;
    if (h.name.length == 0) h.name = h.code;
    h.buyPrice = [row[@"buy"] doubleValue];
    h.shares = [row[@"shares"] doubleValue];
    return h;
}

+ (NSDictionary *)rowFrom:(ZJHolding *)h {
    return @{
        @"code": h.code ?: @"",
        @"name": h.name ?: @"",
        @"buy": @(h.buyPrice),
        @"shares": @(h.shares),
    };
}

+ (NSArray<ZJHolding *> *)holdings {
    [self seedIfNeeded];
    NSArray *raw = [[self ud] arrayForKey:kHold];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *row in raw) {
        if (![row isKindOfClass:[NSDictionary class]]) continue;
        ZJHolding *h = [self holdingFrom:row];
        if (h.code.length == 6) [out addObject:h];
    }
    return out;
}

+ (void)saveHoldings:(NSArray<ZJHolding *> *)holdings {
    NSMutableArray *raw = [NSMutableArray array];
    for (ZJHolding *h in holdings) {
        if (h.code.length != 6) continue;
        [raw addObject:[self rowFrom:h]];
    }
    [[self ud] setObject:raw forKey:kHold];
}

+ (NSDictionary *)quoteForCode:(NSString *)code {
    NSDictionary *all = [[self ud] dictionaryForKey:kQuotes];
    NSDictionary *row = all[code];
    return [row isKindOfClass:[NSDictionary class]] ? row : nil;
}

+ (void)mergeQuotes:(NSArray *)items {
    NSMutableDictionary *all = [[[self ud] dictionaryForKey:kQuotes] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableArray<ZJHolding *> *holds = [[self holdings] mutableCopy];
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *code = item[@"symbol"];
        if (![code isKindOfClass:[NSString class]] || code.length == 0) continue;
        double price = [item[@"price"] doubleValue];
        if (price <= 0) continue;
        NSMutableDictionary *saved = [item mutableCopy];
        saved[@"at"] = @(now);
        all[code] = saved;
        NSString *name = item[@"name"];
        if ([name isKindOfClass:[NSString class]] && name.length) {
            for (ZJHolding *h in holds) {
                if ([h.code isEqualToString:code]) h.name = name;
            }
        }
    }
    [[self ud] setObject:all forKey:kQuotes];
    [self saveHoldings:holds];
}

+ (BOOL)marketIsOpen {
    NSCalendar *cal = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    cal.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    NSDateComponents *c = [cal components:NSCalendarUnitWeekday | NSCalendarUnitHour | NSCalendarUnitMinute fromDate:[NSDate date]];
    if (c.weekday < 2 || c.weekday > 6) return NO;
    NSInteger m = c.hour * 60 + c.minute;
    if (m >= 9 * 60 + 30 && m < 11 * 60 + 30) return YES;
    if (m >= 13 * 60 && m < 15 * 60) return YES;
    return NO;
}

+ (NSString *)sessionTitle {
    return [self marketIsOpen] ? @"交易中 · 每分钟更新" : @"未开盘 · 最后成交";
}

+ (NSInteger)dwellSummary {
    NSInteger n = [[self ud] integerForKey:kDwellSum];
    if (n < 5) return 20;
    return MIN(n, 600);
}

+ (NSInteger)dwellStock {
    NSInteger n = [[self ud] integerForKey:kDwellStock];
    if (n < 5) return 12;
    return MIN(n, 600);
}

+ (void)setDwellSummary:(NSInteger)summary stock:(NSInteger)stock {
    [[self ud] setInteger:MAX(5, summary) forKey:kDwellSum];
    [[self ud] setInteger:MAX(5, stock) forKey:kDwellStock];
}

@end
