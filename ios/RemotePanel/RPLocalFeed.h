#import <Foundation/Foundation.h>

extern NSString * const RPProxyDefaultsKey;
extern NSString * const RPSourceURLPrefix;
extern NSString * const RPSourceProxyPrefix;
extern NSString * const RPVpsURLKey;
extern NSString * const RPVpsTokenKey;
extern NSString * const RPVpsProxyKey;
extern NSString * const RPPageEnabledPrefix;
extern NSString * const RPRefreshPrefix;
extern NSString * const RPTickerURLKey;
extern NSString * const RPTickerProxyKey;
/** Where a tap should ask a PC to open the item. Empty stored value means off. */
extern NSString * const RPPCOpenURLKey;
NSString *RPLocalDefaultPCOpenURL(void);
extern NSString * const RPHelloKeyKey;
extern NSString * const RPHelloModelKey;
extern NSString * const RPFeedProgressNotification;

NSDictionary *RPLocalSourceDefaults(void);
NSString *RPLocalDefaultProxy(void);
/** Optional proxy login, stored separately from the proxy address. */
extern NSString * const RPProxyUserKey;
extern NSString * const RPProxyPassKey;
/** The proxy to use: saved address (or the default), with the saved username and
    password added as "scheme://user:pass@host:port" when set. Use this everywhere
    instead of reading RPProxyDefaultsKey directly. */
NSString *RPConfiguredProxy(void);
NSString *RPLocalDefaultVPSURL(void);
NSString *RPLocalDefaultVPSToken(void);
NSString *RPLocalDefaultHelloKey(void);
NSString *RPLocalDefaultHelloModel(void);
BOOL RPLocalDefaultUseProxy(NSString *pid);
NSTimeInterval RPLocalDefaultTTL(NSString *feedKey);
NSTimeInterval RPLocalTTL(NSString *feedKey);
NSString *RPLocalFeedKeyForPage(NSString *pid);
NSArray *RPLocalRefreshChoices(void);
NSArray *RPLocalRefreshChoiceTitles(void);
NSInteger RPLocalRefreshChoiceIndex(NSTimeInterval ttl);
NSArray *RPLocalPageCatalog(void);
/** Built-in pages are on unless the catalog marks default_off. */
BOOL RPLocalPageDefaultOn(NSString *pid);
NSString *RPVideoDirectory(void);
NSArray *RPVideoLocalFiles(void);
/** source / album / http / max / photo_album */
NSDictionary *RPVideoSettings(void);
void RPVideoSetMuted(BOOL muted);
/** 网络视频: directory URL plus optional Basic-auth login. Pass nil pass to keep the saved one. */
void RPVideoSaveNetwork(NSString *url, NSString *user, NSString *pass);
void RPVideoSaveAlbum(NSString *albumId);
void RPVideoSaveMaxMinutes(NSInteger mins);

/** Custom fullscreen WebView pages (max 8). Each: id/title/url/enabled/dwell. */
extern NSString * const RPWebPagesDefaultsKey;
NSUInteger RPWebPagesMaxCount(void);
NSArray *RPWebPagesLoad(void);
void RPWebPagesSave(NSArray *pages);
NSDictionary *RPWebPageFind(NSString *pageId);
NSString *RPWebPagesMakeId(void);
NSMutableDictionary *RPWebPageNormalize(NSDictionary *raw, NSInteger indexHint);

@interface RPLocalFeed : NSObject
+ (instancetype)sharedFeed;
- (void)refreshWithCompletion:(void (^)(NSDictionary *state, NSError *error))completion;
- (NSArray *)activityLog;
- (NSArray *)tickerMessages;
- (void)appendLog:(NSString *)name status:(NSString *)status detail:(NSString *)detail;
/** Expire every feed (except the greeting) and clear failure backoff, then let the
    next poll refetch. Call after settings change. */
- (void)invalidateForSettingsChange;
/** Add one message to the 公告 list the same way GET /tell does (newest first, up to 20). */
- (void)postTestNotice:(NSString *)text;
@end
