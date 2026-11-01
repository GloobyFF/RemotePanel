#import <Foundation/Foundation.h>

@interface ZJHolding : NSObject
@property (nonatomic, copy) NSString *code;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) double buyPrice;
@property (nonatomic, assign) double shares;
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
@end
