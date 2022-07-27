#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface SLChunkDecoder : NSObject
@property(nonatomic, readonly) NSData *body;
@property(nonatomic, readonly) BOOL complete;
- (void)feed:(NSData *)data;
@end
NS_ASSUME_NONNULL_END
