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
/** Put each block off-canvas before the first paint, so the fly-in is the first thing shown. */
- (void)parkMotionOffscreen;
- (BOOL)rpIntroHasPlayed;
/** If this page is on screen and the fly-in has not started, start it now. */
- (void)rpCatchUpIntro;
- (NSURL *)absURL:(NSString *)path base:(NSString *)base;
- (void)loadImageURL:(NSURL *)url into:(UIImageView *)iv;
/** Drop decoded bitmaps held by this page (call on leave / memory warning). */
- (void)purgeDisplayedImages;
@end

/** Prefetch remote images for a page id into the shared cache (no UI). */
void RPPrefetchImagesForPage(NSString *pageId, NSDictionary *state, NSString *baseURL);
/** Start buffering the next video about 15 s before that page is shown. */
void RPPrepareUpcomingVideo(BOOL network);
void RPDropPreparedVideo(void);
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
/** Fullscreen user-configured webpage (pageId prefix web-). */
@interface RPWebPageVC : RPBasePageVC
@end
/** One random video, muted by default, then advance. No fly-in. Off until enabled.
    network NO = 相册视频 (album, or files uploaded to the iPad); YES = 网络视频
    (HTTP directory listing or WebDAV, optional Basic auth). */
@interface RPVideoPageVC : RPBasePageVC
@property (nonatomic, assign) BOOL network;
@end

@interface RPPageFactory : NSObject
+ (UIViewController<RPPage> *)pageForId:(NSString *)pid title:(NSString *)title;
+ (BOOL)isWebPageId:(NSString *)pid;
@end
