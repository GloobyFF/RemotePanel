#import "RPPhotoSource.h"

@implementation RPPhotoSource

- (void)ensureAuthorization:(void(^)(BOOL granted))completion {
    PHAuthorizationStatus st = [PHPhotoLibrary authorizationStatus];
    if (st == PHAuthorizationStatusAuthorized) {
        if (completion) completion(YES);
        return;
    }
    if (st == PHAuthorizationStatusDenied || st == PHAuthorizationStatusRestricted) {
        if (completion) completion(NO);
        return;
    }
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(status == PHAuthorizationStatusAuthorized);
        });
    }];
}

- (NSString *)titleForCollection:(PHAssetCollection *)c {
    return c.localizedTitle ?: @"相册";
}

- (NSArray<PHAssetCollection *> *)allAlbums {
    NSMutableArray *out = [NSMutableArray array];
    PHFetchResult *smart = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeAny options:nil];
    [smart enumerateObjectsUsingBlock:^(PHAssetCollection *obj, NSUInteger idx, BOOL *stop) {
        [out addObject:obj];
    }];
    PHFetchResult *user = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:nil];
    [user enumerateObjectsUsingBlock:^(PHAssetCollection *obj, NSUInteger idx, BOOL *stop) {
        [out addObject:obj];
    }];
    return out;
}

- (PHAssetCollection *)findFavorites {
    PHFetchResult *smart = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeSmartAlbumFavorites options:nil];
    if (smart.count > 0) return smart.firstObject;
    for (PHAssetCollection *c in [self allAlbums]) {
        NSString *t = c.localizedTitle ?: @"";
        if ([t containsString:@"收藏"] || [t.lowercaseString containsString:@"favorite"]) return c;
    }
    return nil;
}

- (PHAssetCollection *)findCameraRoll {
    PHFetchResult *r = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeSmartAlbumUserLibrary options:nil];
    if (r.count > 0) return r.firstObject;
    return nil;
}

- (PHFetchOptions *)imageFetchOptions {
    PHFetchOptions *opts = [[PHFetchOptions alloc] init];
    opts.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    opts.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d", PHAssetMediaTypeImage];
    return opts;
}

- (NSArray<PHAsset *> *)assetsFromCollection:(PHAssetCollection *)col limit:(NSUInteger)limit {
    if (!col) return @[];
    PHFetchResult *assets = [PHAsset fetchAssetsInAssetCollection:col options:[self imageFetchOptions]];
    NSMutableArray *arr = [NSMutableArray array];
    [assets enumerateObjectsUsingBlock:^(PHAsset *obj, NSUInteger idx, BOOL *stop) {
        [arr addObject:obj];
        if (arr.count >= limit) *stop = YES;
    }];
    return arr;
}

- (NSArray<PHAsset *> *)allPhotoAssetsLimit:(NSUInteger)limit {
    PHFetchResult *assets = [PHAsset fetchAssetsWithOptions:[self imageFetchOptions]];
    NSMutableArray *arr = [NSMutableArray array];
    [assets enumerateObjectsUsingBlock:^(PHAsset *obj, NSUInteger idx, BOOL *stop) {
        [arr addObject:obj];
        if (arr.count >= limit) *stop = YES;
    }];
    return arr;
}

- (NSArray<PHAsset *> *)momentAssetsLimit:(NSUInteger)limit {
    // iOS 8–12 Moments smart collections
    PHFetchResult *moments = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeMoment subtype:PHAssetCollectionSubtypeAny options:nil];
    NSMutableArray *arr = [NSMutableArray array];
    [moments enumerateObjectsUsingBlock:^(PHAssetCollection *col, NSUInteger idx, BOOL *stopOuter) {
        NSArray *chunk = [self assetsFromCollection:col limit:limit - arr.count];
        [arr addObjectsFromArray:chunk];
        if (arr.count >= limit) *stopOuter = YES;
    }];
    return arr;
}

- (void)loadAlbumAssetsPreferFavorites:(void(^)(NSArray<PHAsset *> *assets, NSString *albumTitle))completion {
    const NSUInteger kLimit = 200;
    PHAssetCollection *col = nil;
    BOOL usedPersisted = NO;

    if (self.albumLocalIdentifier.length) {
        PHFetchResult *fr = [PHAssetCollection fetchAssetCollectionsWithLocalIdentifiers:@[self.albumLocalIdentifier] options:nil];
        col = fr.firstObject;
        usedPersisted = YES;
        if (!col) {
            // Stale localIdentifier — reset so next time we use defaults
            self.albumLocalIdentifier = nil;
            usedPersisted = NO;
        }
    }

    NSArray *arr = nil;
    NSString *title = nil;

    if (col) {
        arr = [self assetsFromCollection:col limit:kLimit];
        title = [self titleForCollection:col];
        // Persisted album empty or missing assets → fall through unless user explicitly picked an empty album with assets later.
        // If stale empty favorites-like pick with 0 assets, fall through.
        if (arr.count == 0 && usedPersisted) {
            self.albumLocalIdentifier = nil;
            col = nil;
            arr = nil;
        }
    }

    if (arr.count == 0) {
        col = [self findFavorites];
        if (col) {
            arr = [self assetsFromCollection:col limit:kLimit];
            title = [self titleForCollection:col];
        }
    }
    if (arr.count == 0) {
        col = [self findCameraRoll];
        if (col) {
            arr = [self assetsFromCollection:col limit:kLimit];
            title = [self titleForCollection:col];
        }
    }
    if (arr.count == 0) {
        // Try smart album titles: 所有照片 / All Photos / 相机胶卷
        for (PHAssetCollection *c in [self allAlbums]) {
            NSString *t = c.localizedTitle ?: @"";
            NSString *low = t.lowercaseString;
            if ([t containsString:@"所有照片"] || [t containsString:@"相机胶卷"] ||
                [low containsString:@"all photos"] || [low containsString:@"camera roll"] ||
                [low containsString:@"recents"] || [t containsString:@"最近项目"]) {
                arr = [self assetsFromCollection:c limit:kLimit];
                if (arr.count) {
                    title = t;
                    break;
                }
            }
        }
    }
    if (arr.count == 0) {
        arr = [self allPhotoAssetsLimit:kLimit];
        title = arr.count ? @"全部照片" : title;
    }
    if (arr.count == 0) {
        arr = [self momentAssetsLimit:kLimit];
        title = arr.count ? @"时刻" : (title ?: @"无相册");
    }
    if (!title) title = arr.count ? @"相册" : @"无相册";
    if (!arr) arr = @[];
    if (completion) completion(arr, title);
}

- (void)requestImageForAsset:(PHAsset *)asset targetSize:(CGSize)size completion:(void(^)(UIImage *image))completion {
    if (!asset) {
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        }
        return;
    }
    if (size.width < 1 || size.height < 1) {
        size = CGSizeMake(1024, 1024);
    }
    PHImageRequestOptions *opts = [[PHImageRequestOptions alloc] init];
    // FastFormat + sized request keeps peak memory down on iPad 3.
    opts.deliveryMode = PHImageRequestOptionsDeliveryModeFastFormat;
    opts.resizeMode = PHImageRequestOptionsResizeModeExact;
    opts.networkAccessAllowed = YES;
    opts.synchronous = NO;
    [[PHImageManager defaultManager] requestImageForAsset:asset
                                              targetSize:size
                                             contentMode:PHImageContentModeAspectFill
                                                 options:opts
                                           resultHandler:^(UIImage *result, NSDictionary *info) {
        BOOL degraded = [info[PHImageResultIsDegradedKey] boolValue];
        BOOL cancelled = [info[PHImageCancelledKey] boolValue];
        NSError *err = info[PHImageErrorKey];
        if (cancelled || err) return;
        if (degraded && result) {
            // Keep degraded as temporary; high-quality will follow
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(result);
            });
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(result);
        });
    }];
}

@end
