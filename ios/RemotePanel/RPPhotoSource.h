#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

@interface RPPhotoSource : NSObject
@property (nonatomic, copy) NSString *albumLocalIdentifier; // persisted
- (void)ensureAuthorization:(void(^)(BOOL granted))completion;
- (void)loadAlbumAssetsPreferFavorites:(void(^)(NSArray<PHAsset *> *assets, NSString *albumTitle))completion;
- (void)requestImageForAsset:(PHAsset *)asset targetSize:(CGSize)size completion:(void(^)(UIImage *image))completion;
- (NSArray<PHAssetCollection *> *)allAlbums;
- (NSString *)titleForCollection:(PHAssetCollection *)c;
@end
