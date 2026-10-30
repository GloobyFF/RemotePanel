#import <UIKit/UIKit.h>

@protocol RPPage <NSObject>
@property (nonatomic, copy) NSString *pageId;
@property (nonatomic, copy) NSString *pageTitle;
- (void)pageWillAppear;
- (void)pageDidDisappear;
- (void)applyState:(NSDictionary *)state baseURL:(NSString *)baseURL;
@optional
- (void)setPhotoSource:(id)photoSource slot:(NSInteger)slot;
@end

@interface RPBasePageVC : UIViewController <RPPage>
@property (nonatomic, copy) NSString *pageId;
@property (nonatomic, copy) NSString *pageTitle;
@property (nonatomic, strong) UIView *contentView;
- (UILabel *)makeLabel:(UIFont *)font color:(UIColor *)color;
- (UIView *)makeCard;
- (void)clearContent;
- (void)playPageIntro;
- (void)playPageOutro:(void (^)(void))done;
- (NSURL *)absURL:(NSString *)path base:(NSString *)base;
- (void)loadImageURL:(NSURL *)url into:(UIImageView *)iv;
/** Drop decoded bitmaps held by this page (call on leave / memory warning). */
- (void)purgeDisplayedImages;
@end

/** Prefetch remote images for a page id into the shared cache (no UI). */
void RPPrefetchImagesForPage(NSString *pageId, NSDictionary *state, NSString *baseURL);
/** Evict the shared UIImage cache (memory pressure). */
void RPPurgeImageCache(void);

@interface RPHelloPageVC : RPBasePageVC
@end
@interface RPWeatherPageVC : RPBasePageVC
@property (nonatomic, assign) BOOL weekly;
@end
@interface RPSystemPageVC : RPBasePageVC
@end
@interface RPVpsPageVC : RPBasePageVC
@end
@interface RPNewsPageVC : RPBasePageVC
@property (nonatomic, assign) BOOL github;
@property (nonatomic, copy) NSString *feedKind; // x
@end
@interface RPSchedulePageVC : RPBasePageVC
@end
/** Single dense printer page (fleet + temps + AMS filament). */
@interface RPPrintPageVC : RPBasePageVC
@end
/** Legacy aliases — factory still accepts old ids. */
@interface RPPrintFleetPageVC : RPPrintPageVC
@end
@interface RPPrintTempsPageVC : RPPrintPageVC
@end
@interface RPPrintFilamentPageVC : RPPrintPageVC
@end
@interface RPMoviePageVC : RPBasePageVC
@end
@interface RPSteamPageVC : RPBasePageVC
@property (nonatomic, assign) NSInteger pageOffset;
@end
@interface RPGameListPageVC : RPBasePageVC
@property (nonatomic, copy) NSString *kind; // pc|switch|ps5
@end
@interface RPQuotePageVC : RPBasePageVC
@property (nonatomic, copy) NSString *quoteKind; // stock | crypto
@end
@interface RPPhotoPageVC : RPBasePageVC
@property (nonatomic, assign) NSInteger slot;
@end
@interface RPWebFallbackPageVC : RPBasePageVC
@end

@interface RPPageFactory : NSObject
+ (UIViewController<RPPage> *)pageForId:(NSString *)pid title:(NSString *)title;
@end
