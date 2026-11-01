#import <Foundation/Foundation.h>

@interface ZJHolding : NSObject
@property (nonatomic, copy) NSString *code;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) double buyPrice;
@property (nonatomic, assign) double shares;
/** Price alerts. 0 means off. */
@property (nonatomic, assign) double alertAbove;
@property (nonatomic, assign) double alertBelow;
@end

/** One triggered price alert, shown in the banner. */
@interface ZJAlert : NSObject
@property (nonatomic, copy) NSString *code;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) BOOL above;      // YES: rose to/above the limit
@property (nonatomic, assign) double limit;
@property (nonatomic, assign) double price;
@property (nonatomic, assign) NSTimeInterval at;
@end

@interface ZJStore : NSObject
+ (NSArray<ZJHolding *> *)holdings;
+ (void)saveHoldings:(NSArray<ZJHolding *> *)holdings;
+ (NSDictionary *)quoteForCode:(NSString *)code;
+ (void)mergeQuotes:(NSArray *)items;
+ (BOOL)marketIsOpen;
/** Fetch window: trading hours plus the opening (9:15) and closing (until 15:05) auctions. */
+ (BOOL)shouldFetch;
+ (NSInteger)dwellSummary;
+ (NSInteger)dwellStock;
+ (void)setDwellSummary:(NSInteger)summary stock:(NSInteger)stock;
+ (NSString *)sessionTitle;

/** Which quote source answered last ("东方财富" / "腾讯"), for the header. */
+ (NSString *)lastSource;
+ (void)setLastSource:(NSString *)source;

/** Master switch for the chime (banner still shows when off). Default on. */
+ (BOOL)alertSoundOn;
+ (void)setAlertSoundOn:(BOOL)on;

/**
 Compare fresh quotes with each holding's limits and return alerts that just fired.
 An alert fires when the price reaches its limit, once per trading day. It re-arms
 only after the price moves back by 0.5% of the limit, so a price hovering on the
 line does not chime every minute.
 */
+ (NSArray<ZJAlert *> *)checkAlerts;
@end
